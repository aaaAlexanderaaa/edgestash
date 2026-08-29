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
    var focusContext: (() -> (settingsIsKey: Bool, collapsedPIDs: Set<pid_t>))?

    var presentation: StashCollapsePresentation?
    var lockedWidth: CGFloat = 0
    var restoreFrame: CGRect?
    var displayID: String?
    var usingSharedMinimize = false
    var restoringShared = false
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
    var focusReleaseGeneration = 0
    var lifecycleGeneration = 0

    init(appElement: AXUIElement, windowElement: AXUIElement, pid: pid_t, bundleID: String) {
        self.appElement = appElement
        self.windowElement = windowElement
        self.pid = pid
        self.bundleID = bundleID
        self.windowID = StashAX.windowID(of: windowElement)
        if let frame = StashAX.frame(of: windowElement) {
            lockedWidth = frame.width
        }
        marker.onHoverEntered = { [weak self] in self?.beginHoverReveal() }
        marker.onHoverExited = { [weak self] in self?.cancelHoverReveal() }
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
                in: displays,
                screensHaveSeparateSpaces: NSScreen.screensHaveSeparateSpaces
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

    func refreshAfterSpaceChange() {
        guard isManaged, let restoreFrame else { return }
        showMarker(windowQuartz: restoreFrame)
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
        animator.cancel()
        busy = false
        restoringShared = false
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
            if let windowID {
                alphaOK = StashSurface.setAlpha(windowID: windowID, alpha: 1)
            }
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
        isPinned = false
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
            in: cgDisplays,
            screensHaveSeparateSpaces: NSScreen.screensHaveSeparateSpaces
        )
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
        case .slideOffscreen, .displayClippedSlideOffscreen:
            usingSharedMinimize = false
            var origin = frame.origin
            if StashSessionPolicy.shouldSnapToExpandedBeforeSlide(presentation) {
                _ = StashAX.setFrame(windowElement, expanded)
                origin = StashAX.frame(of: windowElement)?.origin ?? expanded.origin
            }
            let hidden = StashGeometryPolicy.visualHiddenOrigin(
                edge: edge,
                frame: frame,
                display: display.frame,
                lockedWidth: lockedWidth
            )
            playEffects(collapsing: true, merged: merged, frame: expanded, primaryHeight: primaryHeight)
            slide(
                from: origin,
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
        if let running = NSRunningApplication(processIdentifier: pid) {
            running.activate(options: .activateIgnoringOtherApps)
        }
        if fromDock {
            StashFocusReturn.remember(excluding: pid)
        }
        if usingSharedMinimize {
            restoringShared = true
            guard StashAX.setMinimized(windowElement, false) else {
                restoringShared = false
                busy = false
                return false
            }
            usingSharedMinimize = false
            let token = lifecycleGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lifecycleGeneration == token else { return }
                _ = StashAX.setFrame(self.windowElement, restoreFrame)
                self.finishExpand(next: next, frame: restoreFrame, fromDock: fromDock)
                self.restoringShared = false
            }
            return true
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

    func finishExpand(next: StashSessionPhase, frame: CGRect, fromDock: Bool) {
        phase = next
        if let running = NSRunningApplication(processIdentifier: pid) {
            running.activate(options: .activateIgnoringOtherApps)
        }
        _ = StashAX.setBool(windowElement, kAXMainAttribute as String, true)
        _ = StashAX.setBool(windowElement, kAXFocusedAttribute as String, true)
        showMarker(windowQuartz: frame)
        startLeaveWatch()
        busy = false
        refreshPinControl()
        notifyChanged()
        if FocusReturnPolicy.shouldReleaseAfterExpand(fromDock: fromDock) {
            scheduleFocusRelease()
        }
    }

    func finishCollapse(next: StashSessionPhase, frame: CGRect, merged: Bool) {
        phase = next
        StashRescue.persist(session: self)
        showMarker(windowQuartz: frame)
        busy = false
        refreshPinControl()
        notifyChanged()
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
