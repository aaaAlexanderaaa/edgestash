import AppKit
import ApplicationServices
import EdgeStashLogic

extension StashSession {
    func reconcileMinimized(now: Date = Date()) {
        guard usingSharedMinimize, phase == .collapsed, !restoringShared else { return }
        guard now.timeIntervalSince(lastMinimizeCheck) >= 0.5 else { return }
        lastMinimizeCheck = now
        if StashAX.isMinimized(windowElement) == false {
            _ = expand(fromDock: false)
        }
    }

    func beginHoverReveal() {
        guard phase == .collapsed, !markerSuppressed else { return }
        hoverDelayTimer?.invalidate()
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
            _ = expand(fromDock: false)
        case .expanded:
            _ = collapse()
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
        guard let edge, !markerSuppressed else {
            hideMarker()
            return
        }
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        let screen = displayID.flatMap { DisplayCatalog.screen(withID: $0, screens: screens) }
            ?? owningDisplay(for: windowQuartz, screens: screens, primaryHeight: primaryHeight)?.1
            ?? NSScreen.main
        guard let screen else { return }
        let kind: StashOverlayKind = presentation == .systemMinimize ? .seamBeacon : .outerStrip
        let frame = StashGeometryPolicy.markerPanelFrame(
            kind: kind,
            edge: edge,
            windowQuartz: windowQuartz,
            displayAppKit: screen.frame,
            primaryHeight: primaryHeight
        )
        let color = Preferences.shared.stripColor(for: bundleID)
            .withAlphaComponent(CGFloat(Preferences.shared.tintAlpha(for: bundleID)))
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? bundleID
        marker.present(
            kind: kind,
            edge: edge,
            color: color,
            frame: frame,
            title: name,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    func hideMarker() {
        marker.dismiss(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func adoptIfAlreadyHidden() {
        guard let frame = StashAX.frame(of: windowElement) else { return }
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        guard let (display, screen) = owningDisplay(for: frame, screens: screens, primaryHeight: primaryHeight) else {
            return
        }
        guard let edge = parkedEdge(of: frame, in: display.frame) else { return }
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

    /// A window parked by a previous run shows only its edge lip: the sliver
    /// inside the owning display is lip-sized, hugging one edge, with the
    /// bulk of the window off-screen. Tolerance covers window-manager nudges
    /// between sessions.
    private func parkedEdge(of frame: CGRect, in display: CGRect) -> DisplayEdge? {
        let visible = frame.intersection(display)
        guard frame.width - visible.width > 24 else { return nil }
        let tolerance: CGFloat = 6
        let reach = StashGeometryPolicy.edgeLip + tolerance
        guard visible.width <= reach else { return nil }
        if visible.maxX - display.minX <= reach { return .left }
        if display.maxX - visible.minX <= reach { return .right }
        return nil
    }

    func owningDisplay(
        for frame: CGRect,
        screens: [NSScreen],
        primaryHeight: CGFloat
    ) -> (DisplayGeometry, NSScreen)? {
        let geometries = DisplayCatalog.cgGeometries(screens: screens)
        guard let display = geometries.max(by: {
            $0.frame.intersection(frame).width * $0.frame.intersection(frame).height
                < $1.frame.intersection(frame).width * $1.frame.intersection(frame).height
        }) else { return nil }
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

    private func checkLeaveToCollapse() {
        refreshPinControl()
        guard phase == .expanded, !busy else { return }
        guard PinControlPolicy.shouldAutoCollapse(isPinned: isPinned) else { return }
        if usingSharedMinimize { return }
        if NSEvent.pressedMouseButtons != 0 { return }
        guard let frame = StashAX.frame(of: windowElement) ?? restoreFrame else { return }
        let primaryHeight = DisplayCatalog.primaryHeight()
        let mouse = NSEvent.mouseLocation
        let quartz = CGPoint(
            x: mouse.x,
            y: StashGeometryPolicy.quartzOriginY(appKitY: mouse.y, height: 1, primaryHeight: primaryHeight)
        )
        let buffer = frame.insetBy(
            dx: -Preferences.shared.gateSpanX,
            dy: -Preferences.shared.gateSpanY
        )
        if buffer.contains(quartz) { return }
        if FocusReturnPolicy.shouldReleaseAfterLeaveCollapse(didCollapse: collapse()) {
            scheduleFocusRelease()
        }
    }

    private func handleNotification(_ name: String, element: AXUIElement) {
        if name == kAXUIElementDestroyedNotification as String {
            shutdown(event: .windowDestroyed)
            return
        }
        if name == kAXWindowMiniaturizedNotification as String {
            if usingSharedMinimize { return }
            shutdown(event: .miniaturized)
            return
        }
        if name == kAXWindowDeminiaturizedNotification as String, usingSharedMinimize {
            _ = expand(fromDock: false)
        }
        if name == kAXMovedNotification as String, phase == .expanded, !busy {
            guard let frame = StashAX.frame(of: windowElement), let edge else { return }
            let screens = NSScreen.screens
            let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
            guard let display = owningDisplay(for: frame, screens: screens, primaryHeight: primaryHeight)?.0 else {
                return
            }
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
        }
    }
}
