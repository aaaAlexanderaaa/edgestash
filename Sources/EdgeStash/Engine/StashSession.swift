import AppKit
import ApplicationServices
import EdgeStashLogic

final class StashSession {
    let pid: pid_t
    let bundleID: String
    let appElement: AXUIElement
    let windowElement: AXUIElement

    private(set) var phase: StashSessionPhase = .idle
    private(set) var edge: DisplayEdge?
    private(set) var windowID: UInt32?
    private(set) var rescueVisibleFrame: CGRect?
    private(set) var rescueDisplayFrame: CGRect?
    private(set) var isPinned = false
    private(set) var isTemporary = false
    private(set) var markerSuppressed = false

    var isIdle: Bool { phase == .idle }
    var isCollapsed: Bool { phase == .collapsed }
    var isExpanded: Bool { phase == .expanded }
    var isManaged: Bool { phase != .idle }
    var captureGestureFrame: CGRect? {
        guard isIdle, !busy else { return nil }
        return StashAX.frame(of: windowElement)
    }
    var mergeID: String { String(describing: ObjectIdentifier(self)) }
    var onEnded: ((StashSession, SessionLifecyclePolicy.Event) -> Void)?
    var onChanged: ((StashSession) -> Void)?
    var onCollapsed: ((StashSession) -> Void)?
    var onSeamMarkerActivity: ((StashSession) -> Void)?
    var focusContext: (() -> (settingsIsKey: Bool, collapsedPIDs: Set<pid_t>))?

    var presentation: StashCollapsePresentation?
    var lockedWidth: CGFloat = 0
    var restoreFrame: CGRect?
    var displayID: String?
    var usingSharedMinimize = false
    var restoringShared = false
    var seamSpaceAvailability: SeamSpaceAvailability = .unavailable
    var canBeginSeamReveal: Bool {
        SpaceChangePolicy.shouldBeginSeamDwell(availability: seamSpaceAvailability)
    }
    /// After a click-collapse, marker hover stays locked until the pointer
    /// leaves the marker once — a parked pointer must not bounce the window
    /// back out. While locked, a click expands immediately, so clicking
    /// toggles collapse/expand without hover fighting it.
    var clickCollapseLockActive = false
    /// Set only by the post-Space-change rebuild (where the on-screen window
    /// list has settled): a slide-stashed window parked on another Space keeps
    /// its marker hidden until the user returns. Any local capture/expand
    /// clears it, because interacting with the window proves it is here.
    var markerHiddenForSpace = false
    /// Leave-collapse state: the first sample of a continuous outside run, and
    /// the last time the pointer was over a sibling window of the same app.
    var outsideSince: Date?
    var lastSiblingInteractionAt: Date?
    var busy = false
    var observer: AXObserver?
    var observerSource: CFRunLoopSource?
    let marker = StashMarkerWindow()
    let pinWindow = StashPinWindow()
    let effects = StashEffectOverlay()
    let animator = StashAnimator()
    var hoverDelayTimer: Timer?
    var leaveTimer: Timer?
    var lastMinimizeCheck = Date.distantPast
    /// Wall time of the last EdgeStash-owned `setMinimized(true)`. The poll
    /// must not treat AX lag during this settle as a Dock restore.
    var lastOwnedMinimizeAt = Date.distantPast
    var focusReleaseGeneration = 0
    var lifecycleGeneration = 0
    var spaceRevealGeneration = 0

    init(appElement: AXUIElement, windowElement: AXUIElement, pid: pid_t, bundleID: String) {
        self.appElement = appElement
        self.windowElement = windowElement
        self.pid = pid
        self.bundleID = bundleID
        self.windowID = StashAX.windowID(of: windowElement)
        if let frame = StashAX.frame(of: windowElement) {
            lockedWidth = frame.width
        }
        // Seam beacons are driven by the engine's approach band. The global
        // mouse monitor goes quiet over our own panel, so panel hover events
        // poke the band's reevaluation instead of starting hover directly —
        // one state machine, two trigger sources.
        marker.onHoverEntered = { [weak self] in
            guard let self else { return }
            if self.presentation == .systemMinimize {
                self.onSeamMarkerActivity?(self)
            } else {
                guard !self.clickCollapseLockActive else { return }
                self.beginHoverReveal()
            }
        }
        marker.onHoverExited = { [weak self] in
            guard let self else { return }
            self.clickCollapseLockActive = false
            if self.presentation == .systemMinimize {
                self.onSeamMarkerActivity?(self)
            } else {
                self.cancelHoverReveal()
            }
        }
        marker.onClicked = { [weak self] in self?.handleMarkerClick() }
        pinWindow.onToggle = { [weak self] in self?.togglePin() }
        installObserver()
        adoptIfAlreadyHidden()
    }

    deinit {
        animator.cancel()
        observerSource.map { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), $0, .defaultMode) }
        marker.orderOut(nil)
        pinWindow.conceal()
        effects.stop()
    }

    func sameWindow(as element: AXUIElement) -> Bool {
        CFEqual(windowElement, element)
    }

    func resolveWindowID(fallback: UInt32) {
        windowID = windowID ?? StashAX.windowID(of: windowElement) ?? fallback
    }

    func markTemporary() {
        isTemporary = true
    }

    func setMarkerSuppressed(_ suppressed: Bool) {
        guard markerSuppressed != suppressed else { return }
        markerSuppressed = suppressed
        if suppressed {
            hideMarker()
        } else if isManaged, let restoreFrame {
            showMarker(windowQuartz: restoreFrame)
        }
    }

    var mergeMember: MergeMember? {
        guard isManaged, let edge, let restoreFrame else { return nil }
        // A disabled seam beacon must remain independently visible and
        // clickable for its explanation; it cannot disappear into an enabled
        // merged strip.
        if presentation == .systemMinimize, isCollapsed, !canBeginSeamReveal {
            return nil
        }
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        let screen = displayID.flatMap { DisplayCatalog.screen(withID: $0, screens: screens) }
            ?? owningDisplay(for: restoreFrame, screens: screens, primaryHeight: primaryHeight)?.1
        guard let screen else { return nil }
        let appKit = StashGeometryPolicy.appKitRect(fromQuartz: restoreFrame, primaryHeight: primaryHeight)
        return MergeMember(
            id: mergeID,
            edge: edge,
            screenFrame: screen.frame,
            visibleMinY: appKit.minY,
            visibleMaxY: appKit.maxY,
            windowHeight: appKit.height,
            title: NSRunningApplication(processIdentifier: pid)?.localizedName ?? bundleID
        )
    }

    func considerCapture(mouseAppKit: CGPoint, initialFrame: CGRect) -> Bool {
        guard phase == .idle, !busy, let frame = StashAX.frame(of: windowElement) else { return false }
        guard StashSessionPolicy.isWindowDrag(from: initialFrame, to: frame) else { return false }
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        guard let (display, screen) = owningDisplay(for: frame, screens: screens, primaryHeight: primaryHeight) else {
            return false
        }
        let selection = Preferences.shared.displayEdgeSelection(
            for: ConnectedDisplay(
                id: display.id,
                name: screen.localizedName,
                frame: screen.frame,
                isMain: DisplayCatalog.displayID(for: screen).map { CGDisplayIsMain($0) != 0 } ?? false
            )
        )
        guard let edge = StashGeometryPolicy.preferredCaptureEdge(
            windowFrame: frame,
            display: display,
            snapSide: Preferences.shared.snapPreference(for: bundleID),
            blockedDockSide: Preferences.shared.resolvedDockSide(),
            selection: selection
        ) else {
            return false
        }
        let mouseQuartz = CGPoint(
            x: mouseAppKit.x,
            y: StashGeometryPolicy.quartzOriginY(appKitY: mouseAppKit.y, height: 1, primaryHeight: primaryHeight)
        )
        guard StashGeometryPolicy.pointerAllowsEdgeCapture(
            mouse: mouseQuartz,
            edge: edge,
            displayFrame: display.frame,
            windowFrame: frame
        ) else {
            return false
        }
        return capture(edge: edge, frame: frame, display: display, screen: screen, primaryHeight: primaryHeight)
    }

    @discardableResult
    func captureNearestAllowed() -> Bool {
        guard phase == .idle, !busy, let frame = StashAX.frame(of: windowElement) else { return false }
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        guard let (display, screen) = owningDisplay(for: frame, screens: screens, primaryHeight: primaryHeight) else {
            return false
        }
        let selection = Preferences.shared.displayEdgeSelection(
            for: ConnectedDisplay(
                id: display.id,
                name: screen.localizedName,
                frame: screen.frame,
                isMain: DisplayCatalog.displayID(for: screen).map { CGDisplayIsMain($0) != 0 } ?? false
            )
        )
        guard let edge = StashGeometryPolicy.nearestAllowedEdge(
            windowFrame: frame,
            display: display,
            snapSide: Preferences.shared.snapPreference(for: bundleID),
            blockedDockSide: Preferences.shared.resolvedDockSide(),
            selection: selection
        ) else {
            return false
        }
        return capture(edge: edge, frame: frame, display: display, screen: screen, primaryHeight: primaryHeight)
    }

    func toggleFromShortcut() {
        switch phase {
        case .collapsed:
            // Shortcut reveals are deliberate like Dock reveals: they
            // participate in focus return.
            _ = expand(fromDock: true)
        case .expanded, .captured:
            if isPinned { isPinned = false }
            _ = collapse()
        case .idle:
            break
        }
    }

    func expandFromDock() {
        guard phase == .collapsed else { return }
        _ = expand(fromDock: true)
    }

    func mergeReveal() {
        guard !isPinned else { return }
        _ = expand(fromDock: false, merged: true)
    }

    func mergeHide() {
        guard !isPinned else { return }
        _ = collapse(merged: true)
    }

    func detachIfTopologyChanged() {
        guard isManaged, let edge, let restoreFrame else { return }
        let screens = NSScreen.screens
        let displays = DisplayCatalog.adjacencyGeometries(screens: screens)
        let display = displayID.flatMap { id in displays.first { $0.id == id } }
            ?? owningDisplay(for: restoreFrame, screens: screens, primaryHeight: DisplayCatalog.primaryHeight(screens: screens))?.0
        let next: StashCollapsePresentation?
        if let display {
            next = StashSessionPolicy.collapsePresentation(
                at: edge,
                of: display,
                windowFrame: restoreFrame,
                in: displays
            )
        } else {
            next = nil
        }
        if StashSessionPolicy.shouldReleaseAfterTopologyChange(
            current: presentation,
            next: next,
            displayStillPresent: display != nil
        ) {
            shutdown(event: .miniaturized)
        }
    }

    func hideMarkerForSpaceChange() {
        hideMarker()
        pinWindow.conceal()
    }

    /// Rebuild after a Space switch has settled. A collapsed seam beacon is
    /// display-anchored and remains visible, enabled only when that display's
    /// current Space is an ordinary user Space. Expanded and slide-stashed
    /// windows show a marker only on the Space that contains the real window.
    func refreshMarkerAfterSpaceChange() {
        guard isManaged, let restoreFrame else {
            hideMarker()
            return
        }
        let onActiveSpace: Bool
        if let windowID {
            onActiveSpace = StashSurface.isOnScreen(windowID: windowID, pid: pid)
        } else {
            // The window number was never resolved; keep the marker reachable
            // rather than hiding a stash the user cannot verify.
            onActiveSpace = true
        }
        markerHiddenForSpace = !SpaceChangePolicy.shouldShowMarker(
            presentation: presentation,
            windowOnActiveSpace: onActiveSpace,
            isCollapsed: isCollapsed
        )
        if presentation == .systemMinimize, isCollapsed {
            refreshSeamSpaceAvailability()
        }
        if markerHiddenForSpace {
            hideMarker()
        } else {
            showMarker(windowQuartz: restoreFrame)
        }
        refreshPinControl()
    }

    func togglePin() {
        guard isExpanded || isPinned else { return }
        isPinned.toggle()
        if isPinned {
            leaveTimer?.invalidate()
        } else {
            startLeaveWatch()
        }
        refreshPinControl()
        notifyChanged()
    }

    func shutdown(event: SessionLifecyclePolicy.Event) {
        lifecycleGeneration += 1
        spaceRevealGeneration += 1
        animator.cancel()
        busy = false
        restoringShared = false
        clickCollapseLockActive = false
        outsideSince = nil
        lastSiblingInteractionAt = nil
        hoverDelayTimer?.invalidate()
        leaveTimer?.invalidate()
        let shouldRestore = SessionLifecyclePolicy.shouldRestoreVisibility(for: event)
        var positionOK = true
        var alphaOK = true
        var unminimizeOK = true
        if shouldRestore {
            if usingSharedMinimize {
                unminimizeOK = StashAX.isMinimized(windowElement) == false
                    || StashAX.setMinimized(windowElement, false)
            }
            if let restoreFrame {
                positionOK = StashAX.setFrame(windowElement, restoreFrame)
            }
        }
        if SessionLifecyclePolicy.shouldRestoreAlpha(for: event), let windowID {
            alphaOK = StashSurface.setAlpha(windowID: windowID, alpha: 1)
        }
        if event == .detachedFromEdge, usingSharedMinimize {
            unminimizeOK = StashAX.isMinimized(windowElement) == false
                || StashAX.setMinimized(windowElement, false)
        }
        if SessionLifecyclePolicy.shouldClearRescueRecords(
            for: event,
            restorePositionSucceeded: positionOK,
            restoreAlphaSucceeded: alphaOK,
            restoreUnminimizeSucceeded: unminimizeOK,
            isFloating: phase == .idle
        ) {
            StashRescue.clear(processID: pid, windowNumber: windowID)
        }
        hideMarker()
        pinWindow.conceal()
        effects.stop()
        if SessionLifecyclePolicy.shouldUninstallObservers(for: event) {
            uninstallObserver()
        }
        phase = .idle
        edge = nil
        presentation = nil
        usingSharedMinimize = false
        lastOwnedMinimizeAt = .distantPast
        isPinned = false
        if SessionLifecyclePolicy.shouldClearDisplayBinding(for: event) {
            displayID = nil
            restoreFrame = nil
            rescueVisibleFrame = nil
            rescueDisplayFrame = nil
        }
        if isTemporary, !TemporaryShortcutPolicy.shouldKeepAfterIdle(
            stashActive: Preferences.shared.stashActive(bundleID: bundleID)
        ) {
            isTemporary = false
            onEnded?(self, event)
            return
        }
        if SessionLifecyclePolicy.shouldRemoveManagerSession(for: event) {
            onEnded?(self, event)
        }
        notifyChanged()
    }

    func capture(
        edge: DisplayEdge,
        frame: CGRect,
        display: DisplayGeometry,
        screen _: NSScreen,
        primaryHeight _: CGFloat
    ) -> Bool {
        guard StashSessionPolicy.phase(after: .capture, from: phase) == .captured else { return false }
        markerHiddenForSpace = false
        self.edge = edge
        self.displayID = display.id
        self.rescueDisplayFrame = display.frame
        lockedWidth = frame.width
        restoreFrame = CGRect(
            origin: StashGeometryPolicy.expandedOrigin(
                edge: edge,
                frame: frame,
                display: display.frame,
                lockedWidth: lockedWidth
            ),
            size: CGSize(width: lockedWidth, height: frame.height)
        )
        rescueVisibleFrame = restoreFrame
        phase = .captured
        if collapse() { return true }
        revertFailedCapture()
        return false
    }

    private func revertFailedCapture() {
        phase = .idle
        edge = nil
        displayID = nil
        restoreFrame = nil
        rescueVisibleFrame = nil
        rescueDisplayFrame = nil
        presentation = nil
        usingSharedMinimize = false
        busy = false
    }

    @discardableResult
    func collapse(merged: Bool = false) -> Bool {
        guard !isPinned else { return false }
        guard let next = StashSessionPolicy.phase(after: .collapse, from: phase),
              let edge,
              let frame = StashAX.frame(of: windowElement) ?? restoreFrame else {
            return false
        }
        guard !busy else { return false }
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        let cgDisplays = DisplayCatalog.adjacencyGeometries(screens: screens)
        let intersectionID = owningDisplay(for: frame, screens: screens, primaryHeight: primaryHeight)?.0.id
        guard let display = StashSessionPolicy.displayForCollapse(
            sessionDisplayID: displayID,
            intersectionDisplayID: intersectionID,
            displays: cgDisplays
        ) else {
            return false
        }
        let presentation = StashSessionPolicy.collapsePresentation(
            at: edge,
            of: display,
            windowFrame: frame,
            in: cgDisplays
        )
        if presentation == .systemMinimize {
            guard let screen = DisplayCatalog.screen(withID: display.id, screens: screens),
                  let cgDisplayID = DisplayCatalog.displayID(for: screen) else {
                return false
            }
            let availability = DisplaySpaceTransport.shared.availability(for: cgDisplayID)
            guard SpaceChangePolicy.shouldBeginSeamDwell(availability: availability) else {
                seamSpaceAvailability = availability
                return false
            }
            seamSpaceAvailability = availability
        }
        self.presentation = presentation
        lockedWidth = abs(frame.width - lockedWidth) > 15 ? frame.width : (lockedWidth > 0 ? lockedWidth : frame.width)
        let expanded = CGRect(
            origin: StashGeometryPolicy.expandedOrigin(
                edge: edge,
                frame: frame,
                display: display.frame,
                lockedWidth: lockedWidth
            ),
            size: CGSize(width: lockedWidth, height: frame.height)
        )
        restoreFrame = expanded
        rescueVisibleFrame = expanded
        rescueDisplayFrame = display.frame
        windowID = windowID ?? StashAX.windowID(of: windowElement)
        StashRescue.persist(session: self)
        leaveTimer?.invalidate()
        pinWindow.conceal()

        switch presentation {
        case .systemMinimize:
            guard StashAX.canSetMinimized(windowElement) else { return false }
            let priorFrame = StashAX.frame(of: windowElement) ?? frame
            let moved = StashAX.setFrame(windowElement, expanded)
            guard moved else { return false }
            usingSharedMinimize = true
            restoringShared = false
            lastOwnedMinimizeAt = Date()
            guard StashAX.setMinimized(windowElement, true) else {
                usingSharedMinimize = false
                if StashSessionPolicy.shouldRestorePriorFrame(
                    didMoveToExpanded: moved,
                    minimizeSucceeded: false
                ) {
                    _ = StashAX.setFrame(windowElement, priorFrame)
                }
                return false
            }
            finishCollapse(next: next, frame: expanded, merged: merged)
        case .slideOffscreen:
            usingSharedMinimize = false
            let hidden = StashGeometryPolicy.visualHiddenOrigin(
                edge: edge,
                frame: frame,
                display: display.frame,
                lockedWidth: lockedWidth
            )
            playEffects(collapsing: true, merged: merged, frame: expanded, primaryHeight: primaryHeight)
            slide(
                from: frame.origin,
                to: hidden,
                collapsing: true,
                merged: merged
            ) { [weak self] in
                guard let self else { return }
                if let windowID = self.windowID {
                    // 2% alpha keeps the window composited and AX-addressable while being
                    // invisible; exactly zero can let macOS drop it from the layer tree.
                    _ = StashSurface.setAlpha(windowID: windowID, alpha: 0.02)
                }
                self.finishCollapse(next: next, frame: expanded, merged: merged)
            }
        }
        return true
    }

    @discardableResult
    func expand(fromDock: Bool, merged: Bool = false) -> Bool {
        guard let next = StashSessionPolicy.phase(after: .expand, from: phase),
              let restoreFrame else {
            return false
        }
        guard !busy else { return false }
        busy = true
        hoverDelayTimer?.invalidate()
        markerHiddenForSpace = false
        if usingSharedMinimize {
            return prepareAndExpandSharedMinimize(
                next: next,
                restoreFrame: restoreFrame,
                fromDock: fromDock
            )
        }

        // Outer-edge reveals keep their existing activation-first animation;
        // only minimized seam reveals require confirmed Space membership.
        activateApp()
        if fromDock {
            StashFocusReturn.remember(excluding: pid)
        }
        let current = StashAX.frame(of: windowElement) ?? restoreFrame
        if let windowID {
            _ = StashSurface.setAlpha(windowID: windowID, alpha: 1)
        }
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        playEffects(collapsing: false, merged: merged, frame: restoreFrame, primaryHeight: primaryHeight)
        slide(
            from: current.origin,
            to: restoreFrame.origin,
            collapsing: false,
            merged: merged
        ) { [weak self] in
            self?.finishExpand(next: next, frame: restoreFrame, fromDock: fromDock)
        }
        return true
    }

    private func prepareAndExpandSharedMinimize(
        next: StashSessionPhase,
        restoreFrame: CGRect,
        fromDock: Bool
    ) -> Bool {
        // A system-owned Dock thumbnail may already have deminimized and
        // switched Spaces before EdgeStash receives the AX notification. Do
        // not move a now-visible foreign window; adopt the system result.
        if StashAX.isMinimized(windowElement) == false {
            usingSharedMinimize = false
            restoringShared = true
            _ = StashAX.setFrame(windowElement, restoreFrame)
            finishExpand(next: next, frame: restoreFrame, fromDock: false, activatesApp: false)
            restoringShared = false
            return true
        }

        guard let windowID,
              let displayID,
              let screen = DisplayCatalog.screen(withID: displayID),
              let cgDisplayID = DisplayCatalog.displayID(for: screen) else {
            failSharedReveal(availability: .unavailable)
            return false
        }

        seamSpaceAvailability = DisplaySpaceTransport.shared.availability(for: cgDisplayID)
        guard canBeginSeamReveal else {
            failSharedReveal(availability: seamSpaceAvailability)
            return false
        }

        restoringShared = true
        spaceRevealGeneration += 1
        let revealToken = spaceRevealGeneration
        let lifecycleToken = lifecycleGeneration
        DisplaySpaceTransport.shared.prepareMinimizedWindow(
            windowID: windowID,
            for: cgDisplayID
        ) { [weak self] result in
            guard let self,
                  self.lifecycleGeneration == lifecycleToken,
                  self.spaceRevealGeneration == revealToken,
                  self.phase == .collapsed,
                  self.usingSharedMinimize else {
                return
            }
            switch result {
            case .success:
                if fromDock { StashFocusReturn.remember(excluding: self.pid) }
                guard StashAX.setMinimized(self.windowElement, false) else {
                    self.failSharedReveal(availability: .unavailable)
                    return
                }
                self.usingSharedMinimize = false
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.lifecycleGeneration == lifecycleToken,
                          self.spaceRevealGeneration == revealToken else {
                        return
                    }
                    _ = StashAX.setFrame(self.windowElement, restoreFrame)
                    self.finishExpand(next: next, frame: restoreFrame, fromDock: fromDock)
                    self.restoringShared = false
                }
            case let .failure(error):
                let availability: SeamSpaceAvailability = error == .disabledFullScreen
                    ? .disabledFullScreen
                    : .unavailable
                self.failSharedReveal(availability: availability)
            }
        }
        return true
    }

    func cancelPendingSpaceReveal() {
        spaceRevealGeneration += 1
        let observedMinimized = StashAX.isMinimized(windowElement)
        let action = SpaceChangePolicy.pendingSeamRevealCancellation(
            phase: phase,
            revealInFlight: restoringShared,
            observedMinimized: observedMinimized
        )
        switch action {
        case .none:
            return
        case .clearTransaction:
            if phase == .collapsed {
                usingSharedMinimize = true
            }
            restoringShared = false
            busy = false
        case .restoreCollapsedMinimizeThenClear:
            // Keep revealInFlight true while issuing the compensating AX write
            // so its asynchronous deminiaturized notification cannot be
            // mistaken for a system-owned Dock reveal.
            usingSharedMinimize = true
            lastOwnedMinimizeAt = Date()
            let reminimized = StashAX.setMinimized(windowElement, true)
            restoringShared = false
            busy = false
            guard reminimized else {
                // AX refused the only truthful collapsed presentation. Leave
                // through the visibility-restoring release path; it keeps the
                // rescue dossier if AX also refuses to make the window visible.
                shutdown(event: .miniaturized)
                return
            }
        }
    }

    /// An expanded seam window was minimized outside the collapse() write.
    /// Minimize is the hide, so keep the session and restore the beacon.
    func adoptSeamRecollapse() {
        guard presentation == .systemMinimize else { return }
        guard let next = StashSessionPolicy.phase(after: .collapse, from: phase),
              let frame = restoreFrame else {
            return
        }
        usingSharedMinimize = true
        lastOwnedMinimizeAt = Date()
        restoringShared = false
        hoverDelayTimer?.invalidate()
        hoverDelayTimer = nil
        leaveTimer?.invalidate()
        leaveTimer = nil
        finishCollapse(next: next, frame: frame, merged: false)
    }

    func refreshSeamSpaceAvailability() {
        guard presentation == .systemMinimize,
              let displayID,
              let screen = DisplayCatalog.screen(withID: displayID),
              let cgDisplayID = DisplayCatalog.displayID(for: screen) else {
            seamSpaceAvailability = .unavailable
            return
        }
        seamSpaceAvailability = DisplaySpaceTransport.shared.availability(for: cgDisplayID)
    }

    private func failSharedReveal(availability: SeamSpaceAvailability) {
        seamSpaceAvailability = availability
        restoringShared = false
        busy = false
        cancelHoverReveal()
        if let restoreFrame { showMarker(windowQuartz: restoreFrame) }
        notifyChanged()
        marker.showDisabledExplanation()
    }

    func finishExpand(
        next: StashSessionPhase,
        frame: CGRect,
        fromDock: Bool,
        activatesApp: Bool = true
    ) {
        phase = next
        if activatesApp { activateApp() }
        showMarker(windowQuartz: frame)
        startLeaveWatch()
        outsideSince = nil
        lastSiblingInteractionAt = nil
        busy = false
        refreshPinControl()
        notifyChanged()
        if FocusReturnPolicy.shouldReleaseAfterExpand(fromDock: fromDock) {
            scheduleFocusRelease()
        }
    }

    /// Full app activation plus AX main/focused writes. Reserved for
    /// deliberate reveals and for a presented window the pointer has entered —
    /// activation raises the app's whole window stack, so a passing hover must
    /// never trigger it.
    func activateApp() {
        if let running = NSRunningApplication(processIdentifier: pid) {
            running.activate(options: .activateIgnoringOtherApps)
        }
        _ = StashAX.setBool(windowElement, kAXMainAttribute as String, true)
        _ = StashAX.setBool(windowElement, kAXFocusedAttribute as String, true)
    }

    func finishCollapse(next: StashSessionPhase, frame: CGRect, merged: Bool) {
        phase = next
        StashRescue.persist(session: self)
        showMarker(windowQuartz: frame)
        busy = false
        refreshPinControl()
        notifyChanged()
        onCollapsed?(self)
        if !merged {
            scheduleFocusRelease()
        }
    }

    private func slide(
        from start: CGPoint,
        to end: CGPoint,
        collapsing: Bool,
        merged: Bool,
        completion: @escaping () -> Void
    ) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let height = (StashAX.frame(of: windowElement) ?? restoreFrame)?.height ?? lockedWidth
        busy = true
        animator.begin(
            StashAnimator.Slide(
                target: windowElement,
                origin: start,
                destination: end,
                span: StashMotionPolicy.span(reduceMotion: reduceMotion, collapsing: collapsing, merged: merged),
                size: CGSize(width: lockedWidth, height: height),
                refundsClock: !merged
            )
        ) {
            completion()
        }
    }

    private func playEffects(collapsing: Bool, merged: Bool, frame: CGRect, primaryHeight: CGFloat) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard StashMotionPolicy.shouldEmitVisualEffects(
            enabled: Preferences.shared.decoratesSlides,
            reduceMotion: reduceMotion,
            mergedLocked: merged || markerSuppressed
        ), let edge else {
            return
        }
        let screens = NSScreen.screens
        let screen = displayID.flatMap { DisplayCatalog.screen(withID: $0, screens: screens) } ?? NSScreen.main
        guard let screen else { return }
        let appKit = StashGeometryPolicy.appKitRect(fromQuartz: frame, primaryHeight: primaryHeight)
        let point = CGPoint(
            x: edge == .left ? screen.frame.minX : screen.frame.maxX,
            y: appKit.midY
        )
        let color = Preferences.shared.stripColor(for: bundleID)
        if collapsing {
            effects.playCollapse(edge: edge, point: point, color: color, screen: screen)
        } else {
            effects.playExpand(edge: edge, point: point, color: color, screen: screen)
        }
    }

    private func notifyChanged() {
        onChanged?(self)
    }
}
