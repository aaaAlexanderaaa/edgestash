import AppKit
import ApplicationServices
import EdgeStashLogic

extension StashSession {
    func reconcileMinimized(now: Date = Date()) {
        guard usingSharedMinimize, phase == .collapsed, !restoringShared else { return }
        guard now.timeIntervalSince(lastMinimizeCheck) >= 0.5 else { return }
        lastMinimizeCheck = now
        // The poll and the AX notification must agree. Adopting "not
        // minimized" during settle is what turned an owned collapse into a
        // false expand and then a session-killing miniaturized event.
        guard SeamSessionDurabilityPolicy.shouldAdoptUnminimizedPoll(
            ownsCollapsedMinimize: usingSharedMinimize,
            elapsedSinceOwnedMinimize: now.timeIntervalSince(lastOwnedMinimizeAt),
            observedMinimized: StashAX.isMinimized(windowElement)
        ) else { return }
        _ = expand(fromDock: false)
    }

    func beginHoverReveal() {
        guard phase == .collapsed, !markerSuppressed else { return }
        if presentation == .systemMinimize {
            guard canBeginSeamReveal else { return }
        }
        // The marker panel and the seam approach band can both see the same
        // arrival; a pending dwell must not restart or the reveal would lag
        // one extra delay behind every entry.
        if let timer = hoverDelayTimer, timer.isValid { return }
        let delay = TimeInterval(Preferences.shared.revealDelayMS) / 1000
        if delay <= 0 {
            _ = expand(fromDock: false)
            return
        }
        hoverDelayTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, NSEvent.pressedMouseButtons == 0 else { return }
            _ = self.expand(fromDock: false)
        }
    }

    func cancelHoverReveal() {
        hoverDelayTimer?.invalidate()
        hoverDelayTimer = nil
    }

    func handleMarkerClick() {
        hoverDelayTimer?.invalidate()
        switch phase {
        case .collapsed:
            // A click while the lock is held expands immediately; the lock
            // stays on so the next click collapses again (click toggle).
            _ = expand(fromDock: false)
        case .expanded:
            if collapse() {
                clickCollapseLockActive = true
            }
        default:
            break
        }
    }

    func startLeaveWatch() {
        leaveTimer?.invalidate()
        leaveTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkLeaveToCollapse()
        }
    }

    func showMarker(windowQuartz: CGRect) {
        guard let edge, !markerSuppressed, !markerHiddenForSpace else {
            hideMarker()
            return
        }
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        let screen = displayID.flatMap { DisplayCatalog.screen(withID: $0, screens: screens) }
            ?? owningDisplay(for: windowQuartz, screens: screens, primaryHeight: primaryHeight)?.1
            ?? NSScreen.main
        guard let screen else { return }
        let kind: StashOverlayKind
        switch presentation {
        case .systemMinimize:
            // A shared seam must keep EdgeStash's own panel wholly inside the
            // owning display; the stashed window itself is minimized.
            kind = .seamBeacon
        case .slideOffscreen, nil:
            kind = .outerStrip
        }
        let frame = StashGeometryPolicy.markerPanelFrame(
            kind: kind,
            edge: edge,
            windowQuartz: windowQuartz,
            displayAppKit: screen.frame,
            primaryHeight: primaryHeight
        )
        // Glass owns translucency. The stored per-app alpha is unused: the
        // rail is a tinted plate, not a percentage-opacity slab.
        let color = Preferences.shared.stripColor(for: bundleID)
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? bundleID
        let markerEnabled = kind != .seamBeacon || canBeginSeamReveal
        let explanation = seamSpaceAvailability == .disabledFullScreen
            ? L10n.seamFullscreenDisabled
            : L10n.seamRevealFailed
        marker.present(
            kind: kind,
            edge: edge,
            color: color,
            frame: frame,
            title: name,
            enabled: markerEnabled,
            disabledExplanation: explanation,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    func hideMarker() {
        // The click-collapse lock only makes sense while the marker is visible
        // under a parked pointer; a programmatic hide (Space change, merge
        // suppression) must not strand it.
        clickCollapseLockActive = false
        marker.dismiss(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func adoptIfAlreadyHidden() {
        guard let frame = StashAX.frame(of: windowElement) else { return }
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        let geometries = DisplayCatalog.adjacencyGeometries(screens: screens)
        let parked = geometries.compactMap { display -> (DisplayGeometry, DisplayEdge)? in
            guard let edge = StashGeometryPolicy.parkedEdge(of: frame, in: display.frame) else { return nil }
            return (display, edge)
        }.first
        let display: DisplayGeometry
        let edge: DisplayEdge
        if let parked {
            display = parked.0
            edge = parked.1
        } else {
            guard let owned = owningDisplay(for: frame, screens: screens, primaryHeight: primaryHeight),
                  let parkedEdge = StashGeometryPolicy.parkedEdge(of: frame, in: owned.0.frame) else {
                return
            }
            display = owned.0
            edge = parkedEdge
        }
        guard let screen = DisplayCatalog.screen(withID: display.id, screens: screens) else { return }
        let selection = Preferences.shared.displayEdgeSelection(
            for: ConnectedDisplay(id: display.id, name: screen.localizedName, frame: screen.frame, isMain: false)
        )
        guard StashSessionPolicy.canCapture(
            edge: edge,
            snapSide: Preferences.shared.snapPreference(for: bundleID),
            blockedDockSide: Preferences.shared.resolvedDockSide(),
            edgeEnabled: selection.isEnabled(edge)
        ) else { return }
        _ = capture(edge: edge, frame: frame, display: display, screen: screen, primaryHeight: primaryHeight)
    }

    func owningDisplay(
        for frame: CGRect,
        screens: [NSScreen],
        primaryHeight: CGFloat
    ) -> (DisplayGeometry, NSScreen)? {
        let geometries = DisplayCatalog.adjacencyGeometries(screens: screens)
        guard let display = StashGeometryPolicy.owningDisplay(
            for: frame,
            in: geometries,
            preferredID: displayID
        ) else { return nil }
        guard let screen = DisplayCatalog.screen(withID: display.id, screens: screens) else { return nil }
        return (display, screen)
    }

    func scheduleFocusRelease() {
        focusReleaseGeneration += 1
        let generation = focusReleaseGeneration
        // Let the reveal animation land and the click interaction settle before
        // handing focus back to the previous app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.focusReleaseGeneration == generation else { return }
            let context = self.focusContext?()
            StashFocusReturn.release(
                sourcePID: self.pid,
                settingsIsKey: context?.settingsIsKey ?? (NSApp.keyWindow != nil),
                collapsedManagedPIDs: context?.collapsedPIDs ?? []
            )
        }
    }

    func refreshPinControl() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard PinControlPolicy.shouldShowControl(isExpanded: isExpanded, isPinned: isPinned, isBusy: busy),
              let restoreFrame,
              let edge else {
            pinWindow.conceal()
            return
        }
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        let screen = displayID.flatMap { DisplayCatalog.screen(withID: $0, screens: screens) }
            ?? owningDisplay(for: restoreFrame, screens: screens, primaryHeight: primaryHeight)?.1
        guard let screen else {
            pinWindow.conceal()
            return
        }
        let windowAppKit = StashGeometryPolicy.appKitRect(fromQuartz: restoreFrame, primaryHeight: primaryHeight)
        let frames = PinControlPolicy.frames(
            edge: edge,
            windowAppKit: windowAppKit,
            screenAppKit: screen.frame
        )
        let mouse = NSEvent.mouseLocation
        let visible = PinControlPolicy.shouldReveal(
            isPinned: isPinned,
            mouseInTrigger: frames.triggerRect.contains(mouse),
            mouseInSafe: frames.safeRect.contains(mouse)
        )
        pinWindow.update(
            frames: frames,
            visible: visible,
            pinned: isPinned,
            accent: Preferences.shared.stripColor(for: bundleID),
            reduceMotion: reduceMotion
        )
    }

    func installObserver() {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, context in
            guard let context else { return }
            let session = Unmanaged<StashSession>.fromOpaque(context).takeUnretainedValue()
            let name = notification as String
            DispatchQueue.main.async {
                session.handleNotification(name, element: element)
            }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for note in [
            kAXUIElementDestroyedNotification as String,
            kAXWindowMiniaturizedNotification as String,
            kAXWindowDeminiaturizedNotification as String,
            kAXMovedNotification as String
        ] {
            _ = AXObserverAddNotification(observer, windowElement, note as CFString, refcon)
        }
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        self.observer = observer
        self.observerSource = source
    }

    func uninstallObserver() {
        if let observerSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), observerSource, .defaultMode)
        }
        observerSource = nil
        observer = nil
    }

    private func checkLeaveToCollapse() {
        refreshPinControl()
        guard phase == .expanded, !busy else { return }
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        guard let frame = StashAX.frame(of: windowElement) ?? restoreFrame else { return }
        let windowAppKit = StashGeometryPolicy.appKitRect(fromQuartz: frame, primaryHeight: primaryHeight)
        guard PinControlPolicy.shouldAutoCollapse(isPinned: isPinned) else { return }
        if usingSharedMinimize { return }
        let now = Date()
        if NSEvent.pressedMouseButtons != 0 {
            outsideSince = nil
            return
        }
        let screen = displayID.flatMap { DisplayCatalog.screen(withID: $0, screens: screens) }
            ?? owningDisplay(for: frame, screens: screens, primaryHeight: primaryHeight)?.1
            ?? NSScreen.main
        let pinFrames = PinControlPolicy.frames(
            edge: edge ?? .left,
            windowAppKit: windowAppKit,
            screenAppKit: screen?.frame ?? windowAppKit
        )
        let geometricallyOutside = !PinControlPolicy.pointerBlocksAutoCollapse(
            mouseAppKit: mouse,
            windowAppKit: windowAppKit,
            gateSpanX: Preferences.shared.gateSpanX,
            gateSpanY: Preferences.shared.gateSpanY,
            triggerRect: pinFrames.triggerRect,
            safeRect: pinFrames.safeRect
        )
        var pointerInSibling = false
        var siblingFocused = false
        if geometricallyOutside {
            let mouseQuartz = CGPoint(
                x: mouse.x,
                y: StashGeometryPolicy.quartzOriginY(appKitY: mouse.y, height: 0, primaryHeight: primaryHeight)
            )
            pointerInSibling = StashSurface.isPointerInSiblingWindow(
                pid: pid,
                excluding: windowID,
                atQuartz: mouseQuartz
            )
            if pointerInSibling {
                lastSiblingInteractionAt = now
            }
            siblingFocused = isSiblingWindowFocused()
        }
        guard LeaveCollapsePolicy.countsAsInside(
            geometricallyOutside: geometricallyOutside,
            pointerInSibling: pointerInSibling,
            siblingFocused: siblingFocused,
            lastSiblingInteractionAt: lastSiblingInteractionAt,
            now: now
        ) else {
            if outsideSince == nil { outsideSince = now }
            if LeaveCollapsePolicy.shouldCollapse(outsideSince: outsideSince, now: now) {
                outsideSince = nil
                _ = collapse()
            }
            return
        }
        outsideSince = nil
    }

    /// The app is frontmost and its focused window is a sibling of the stashed
    /// one: the user is working with the app, so the expanded stash stays out.
    private func isSiblingWindowFocused() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = StashAX.focusedWindow(of: appElement) else {
            return false
        }
        return !sameWindow(as: focused)
    }

    private func handleNotification(_ name: String, element: AXUIElement) {
        if name == kAXUIElementDestroyedNotification as String {
            shutdown(event: .windowDestroyed)
            return
        }
        let minimizeNotification: ManagedMinimizeNotification?
        switch name {
        case kAXWindowMiniaturizedNotification as String:
            minimizeNotification = .miniaturized
        case kAXWindowDeminiaturizedNotification as String:
            minimizeNotification = .deminiaturized
        default:
            minimizeNotification = nil
        }
        if let minimizeNotification {
            let action = ManagedMinimizeNotificationPolicy.action(
                for: minimizeNotification,
                phase: phase,
                ownsCollapsedMinimize: usingSharedMinimize,
                revealInFlight: restoringShared,
                observedMinimized: StashAX.isMinimized(element),
                presentation: presentation
            )
            switch action {
            case .ignore:
                break
            case .releaseSession:
                shutdown(event: .miniaturized)
            case .adoptSystemReveal:
                _ = expand(fromDock: false)
            case .recollapse:
                adoptSeamRecollapse()
            }
            return
        }
        if name == kAXMovedNotification as String, !busy, let edge {
            guard let frame = StashAX.frame(of: windowElement) else { return }
            let screens = NSScreen.screens
            let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
            let geometries = DisplayCatalog.adjacencyGeometries(screens: screens)
            let display = displayID.flatMap { id in geometries.first { $0.id == id } }
                ?? owningDisplay(for: frame, screens: screens, primaryHeight: primaryHeight)?.0
            guard let display else { return }
            if phase == .expanded {
                let stillOnEdge: Bool
                switch edge {
                case .left:
                    stillOnEdge = abs(frame.minX - display.frame.minX) <= 20
                case .right:
                    stillOnEdge = abs(frame.maxX - display.frame.maxX) <= 20
                }
                if StashSessionPolicy.shouldDetachAfterOffEdgeMove(
                    isPinned: isPinned,
                    stillOnEdge: stillOnEdge
                ) {
                    shutdown(event: .detachedFromEdge)
                }
            } else if phase == .collapsed, let presentation {
                let stillParked = StashGeometryPolicy.isStillOnStashEdge(
                    frame: frame,
                    display: display.frame,
                    edge: edge,
                    presentation: presentation
                )
                if StashSessionPolicy.shouldReleaseCollapsedAfterExternalMove(
                    isCollapsed: true,
                    isBusy: busy,
                    stillParkedOnOwningEdge: stillParked
                ) {
                    shutdown(event: .detachedFromEdge)
                }
            }
        }
    }
}
