import AppKit
import ApplicationServices
import EdgeStashLogic

enum ScreenSetApplicationResult: Equatable { case succeeded, waitingForControl, failed }

final class StashSession {
    let pid: pid_t
    let bundleID: String
    private(set) var appElement: AXUIElement
    private(set) var windowElement: AXUIElement
    let processLaunchDate: Date?
    var windowBindingGeneration: UInt = 0
    var observerContext: StashWindowObserverContext?
    private(set) var awaitingWindowControl = false
    private(set) var destructionNotified = false
    var controlValidationQueued = false
    var recoveryEpochActive = false
    private(set) var pendingScreenSetRecovery: ScreenSetRecoveryIntent?
    private(set) var pendingVisibleFallbackOrigin: CGPoint?
    var onControlUnavailable: ((StashSession) -> Void)?
    var onControlReady: ((StashSession) -> Void)?
    /// The application's bundle icon is stable for this window/process life.
    /// Reuse its image in merge models instead of loading two new image objects
    /// per member on every discovery poll (which also defeats model equality).
    lazy var applicationIcon = NSRunningApplication(processIdentifier: pid)?.icon

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
    /// On-desktop: idle and not yellow-minimized. Collapsed, expanded, and
    /// pinned stay stashed.
    var isOnDesktop: Bool {
        guard phase == .idle else { return false }
        return StashAX.isMinimized(windowElement) != true
    }
    var screenSetSlot: StoredScreenSetSlot? {
        guard isManaged, let windowID, let displayID, let edge else { return nil }
        return StoredScreenSetSlot(
            windowNumber: windowID,
            bundleID: bundleID,
            displayID: displayID,
            edge: edge.rawValue
        )
    }
    var captureGestureFrame: CGRect? {
        guard isIdle || isExpanded || pendingScreenSetRecovery != nil, !busy else { return nil }
        if awaitingWindowControl {
            return windowID.flatMap { StashSurface.onScreenBounds(windowID: $0, pid: pid) }
        }
        return StashAX.frame(of: windowElement)
    }
    var mergeID: String { String(describing: ObjectIdentifier(self)) }
    var onEnded: ((StashSession, SessionLifecyclePolicy.Event) -> Void)?
    var onChanged: ((StashSession) -> Void)?
    var onCollapsed: ((StashSession) -> Void)?
    var onExpanded: ((StashSession) -> Void)?
    var onRevealRequested: ((StashSession) -> Void)?
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
    var diagnosticLeaveReason: String?
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
    var focusReturn = FocusReturnCoordinator()
    var presentationRequests = StashPresentationCoordinator()
    var desiredPresentationIsExpanded: Bool { presentationRequests.desiredExpanded(phase: phase) }
    var lifecycleGeneration = 0
    var spaceRevealGeneration = 0
    /// AX moved/miniaturized notifications during a coordinator or shutdown
    /// write must not be treated as a user drag off the edge.
    var ignoringGeometryNotifications = false
    var pendingGeometryDetach: DispatchWorkItem?
    var externalGeometryWasDragged = false
    private(set) var needsScreenSetRepair = false

    init(appElement: AXUIElement, windowElement: AXUIElement, pid: pid_t, bundleID: String) {
        self.appElement = appElement
        self.windowElement = windowElement
        self.pid = pid
        self.bundleID = bundleID
        processLaunchDate = NSRunningApplication(processIdentifier: pid)?.launchDate
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
        diagnose("session.discovered")
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

    var recoveryIntent: ScreenSetRecoveryIntent? {
        if let pendingScreenSetRecovery { return pendingScreenSetRecovery }
        guard let slot = screenSetSlot else { return nil }
        return ScreenSetRecoveryIntent(placement: slot, expanded: isExpanded, pinned: isPinned,
                                       frame: restoreFrame, displayFrame: rescueDisplayFrame)
    }

    func retainRecoveryIntent(_ intent: ScreenSetRecoveryIntent) {
        pendingScreenSetRecovery = intent
        needsScreenSetRepair = true
        recoveryEpochActive = true
    }

    /// A transport failure suspends control, not window membership. Discovery
    /// must corroborate death or find the exact live window before we act again.
    func markWindowControlUnavailable(destruction: Bool = false) {
        destructionNotified = destructionNotified || destruction
        if !awaitingWindowControl {
            pendingScreenSetRecovery = recoveryIntent
            prepareForScreenSetChange()
            awaitingWindowControl = true
            needsScreenSetRepair = isManaged || pendingScreenSetRecovery != nil
            hideMarker()
            pinWindow.conceal()
            diagnose("session.control-wait")
            onChanged?(self)
        }
        onControlUnavailable?(self)
    }

    /// Called only after unique numeric identity, process lifetime and
    /// WindowServer ownership have all been checked by discovery.
    func rebindWindow(appElement: AXUIElement, windowElement: AXUIElement) {
        uninstallObserver()
        self.appElement = appElement
        self.windowElement = windowElement
        awaitingWindowControl = false
        destructionNotified = false
        installObserver()
        diagnose("session.control-rebound")
        onControlReady?(self)
    }

    func cancelPendingRecovery() {
        pendingScreenSetRecovery = nil
        pendingVisibleFallbackOrigin = nil
        recoveryEpochActive = false
        needsScreenSetRepair = false
        ScreenSetCoordinator.active?.cancelRestoration(of: self)
    }

    func noteFallbackDrag(from initialFrame: CGRect) {
        guard pendingScreenSetRecovery != nil || pendingVisibleFallbackOrigin != nil, isIdle,
              let frame = captureGestureFrame,
              StashSessionPolicy.isWindowDrag(from: initialFrame, to: frame) else { return }
        cancelPendingRecovery()
        if let windowID {
            ScreenSetCoordinator.active?.forgetPlacement(windowNumber: windowID, bundleID: bundleID, everywhere: false)
        }
        diagnose("session.recovery-cancelled-by-drag")
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
        guard isManaged, !awaitingWindowControl, let edge, let restoreFrame else { return nil }
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
            title: NSRunningApplication(processIdentifier: pid)?.localizedName ?? bundleID,
            presentation: presentation ?? .slideOffscreen
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
        guard isManaged else { return }
        if !desiredPresentationIsExpanded {
            // Shortcut reveals are deliberate like Dock reveals: they
            // participate in focus return.
            _ = expand(fromDock: true)
        } else {
            if isPinned { isPinned = false }
            _ = collapse()
        }
    }

    func expandFromDock() {
        guard isManaged else { return }
        _ = expand(fromDock: true)
    }

    /// Invalidate callbacks carrying pre-change coordinates before waiting for
    /// display enumeration. The settled transaction will restore presentation.
    func prepareForScreenSetChange() {
        diagnose("session.environment-pause")
        recoveryEpochActive = isManaged || pendingScreenSetRecovery != nil
        externalGeometryWasDragged = false
        needsScreenSetRepair = needsScreenSetRepair || busy || restoringShared || phase == .captured
        cancelHoverReveal()
        leaveTimer?.invalidate()
        leaveTimer = nil
        outsideSince = nil
        lastSiblingInteractionAt = nil
        pendingGeometryDetach?.cancel()
        pendingGeometryDetach = nil
        animator.cancel()
        presentationRequests.cancel()
        lifecycleGeneration += 1
        focusReturn.cancel()
        spaceRevealGeneration += 1
        restoringShared = false
        busy = false
    }

    func resumeAfterScreenSetChange() {
        guard !awaitingWindowControl, pendingScreenSetRecovery == nil else { return }
        recoveryEpochActive = false
        leaveStashIfFullScreened()
        // A quiet increment can skip every AX write and still needs to resume
        // the watcher paused during enumeration.
        if isExpanded, !isPinned, leaveTimer?.isValid != true {
            outsideSince = nil
            lastSiblingInteractionAt = nil
            startLeaveWatch()
        }
        diagnose("session.environment-resume")
    }

    func adoptExternalPlacement(frame: CGRect, display: DisplayGeometry, edge: DisplayEdge) {
        self.edge = edge
        displayID = display.id
        restoreFrame = frame
        rescueDisplayFrame = display.frame
        lockedWidth = frame.width
        if !refreshCollapsePresentation(), !awaitingWindowControl { shutdown(event: .miniaturized) }
    }

    func adoptExpandedGeometry(frame: CGRect, display: DisplayGeometry) {
        guard let edge, frame.width > 0, frame.height > 0 else { return }
        // AX has already accepted this geometry. Update signals and rescue
        // without issuing another frame write back to the app.
        restoreFrame = frame
        lockedWidth = frame.width
        rescueVisibleFrame = frame
        rescueDisplayFrame = display.frame
        presentation = StashSessionPolicy.collapsePresentation(
            at: edge, of: display, windowFrame: frame, in: DisplayCatalog.adjacencyGeometries()
        )
        if presentation == .systemMinimize { refreshSeamSpaceAvailability() }
        StashRescue.persist(session: self)
        showMarker(windowQuartz: frame)
        refreshPinControl()
        notifyChanged()
    }

    /// Keep the same display and side while rebasing actual desktop geometry.
    @discardableResult
    func refreshCollapsePresentation() -> Bool {
        reconcileScreenSetPresentation() == .succeeded
    }

    func reconcileScreenSetPresentation(
        inspectFirst: Bool = false,
        readWindows: () -> [StashRecoverySurface]? = { StashSurface.allWindows() }
    ) -> ScreenSetApplicationResult {
        guard isManaged, let edge, let displayID else { return .failed }
        guard !awaitingWindowControl else { return .waitingForControl }
        if isExpanded, StashAX.isFullScreen(windowElement) == true {
            // The settled callback releases this user-owned full-screen
            // transition outside the coordinator guard. Never reframe it.
            cancelPendingRecovery()
            diagnose("session.recovery-yielded-fullscreen")
            return .succeeded
        }
        let displays = DisplayCatalog.adjacencyGeometries()
        guard let display = displays.first(where: { $0.id == displayID }) else { return .failed }
        let minimized = StashAX.boolResult(windowElement, kAXMinimizedAttribute as String)
        guard let isMinimized = minimized.value else {
            markWindowControlUnavailable()
            return .waitingForControl
        }
        let frameRead = StashAX.frameResult(of: windowElement)
        // Minimized windows need not export a usable frame. Their saved
        // visible geometry and display identity remain authoritative.
        guard frameRead.value != nil || (isMinimized && restoreFrame != nil) else {
            markWindowControlUnavailable()
            return .waitingForControl
        }
        let frame = restoreFrame ?? frameRead.value!
        let rebased = StashGeometryPolicy.screenSetFrame(
            frame: frame, previousDisplay: rescueDisplayFrame, display: display.frame, edge: edge
        )
        let next = StashSessionPolicy.collapsePresentation(at: edge, of: display, windowFrame: rebased, in: displays)
        let hidden = CGRect(origin: StashGeometryPolicy.visualHiddenOrigin(
            edge: edge, frame: rebased, display: display.frame, lockedWidth: rebased.width
        ), size: rebased.size)
        let windows = readWindows()
        let surface = windows?.first { $0.windowID == windowID && $0.pid == pid }
        diagnose("session.recovery-observed", [
            "minimized": isMinimized, "frameReadable": frameRead.value != nil,
            "ownerObserved": surface != nil, "alpha": surface?.alpha.map { Double($0) } ?? -1,
            "observedFrame": frameRead.value.map { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] } ?? []
        ])
        let matches = WindowRecoveryPolicy.presentationMatches(
            phase: phase, presentation: next, expectedFrame: isExpanded ? rebased : hidden,
            actualFrame: frameRead.value, minimized: isMinimized, alpha: surface?.alpha
        )
        // A settled healthy wake is a read-only presentation check. In
        // particular it must not rewrite every already-minimized seam window.
        if inspectFirst && matches {
            let rescueChanged = rescueVisibleFrame != rebased || rescueDisplayFrame != display.frame
            restoreFrame = rebased
            lockedWidth = rebased.width
            rescueVisibleFrame = rebased
            rescueDisplayFrame = display.frame
            presentation = next
            usingSharedMinimize = !isExpanded && next == .systemMinimize
            if !isExpanded { phase = .collapsed }
            if rescueChanged { StashRescue.persist(session: self) }
            finishScreenSetRepair()
            diagnose("session.recovery-unchanged")
            return .succeeded
        }
        // Missing metadata is not permission to mutate an unverified numeric
        // surface. The normal discovery pass will resume this target later.
        guard surface != nil, surface?.alpha != nil else {
            markWindowControlUnavailable()
            return .waitingForControl
        }
        restoreFrame = rebased
        lockedWidth = rebased.width
        rescueVisibleFrame = rebased
        rescueDisplayFrame = display.frame
        ignoringGeometryNotifications = true
        defer { ignoringGeometryNotifications = false }
        StashRescue.persist(session: self)
        if isExpanded {
            if isMinimized, !StashAX.setMinimized(windowElement, false) { return .failed }
            if let windowID, !StashSurface.setAlpha(windowID: windowID, alpha: 1) { return .failed }
            usingSharedMinimize = false
            guard StashAX.setFrame(windowElement, rebased) else { return .failed }
        } else {
            guard rehideCollapsed(on: display, next: next) else { return .failed }
            phase = .collapsed
        }
        presentation = next
        // AX success is a write acknowledgement, not proof of appearance.
        // Log readback and fail bounded recovery if the observable result
        // still disagrees. An unreadable result retains the same intent.
        let observedMinimized = StashAX.isMinimized(windowElement)
        let observedFrame = StashAX.frame(of: windowElement)
        let observedSurface = readWindows()?.first { $0.windowID == windowID && $0.pid == pid }
        let confirmed = WindowRecoveryPolicy.presentationMatches(
            phase: phase, presentation: next, expectedFrame: isExpanded ? rebased : hidden,
            actualFrame: observedFrame, minimized: observedMinimized, alpha: observedSurface?.alpha
        )
        diagnose("session.recovery-readback", ["confirmed": confirmed, "minimized": observedMinimized.map { $0 as Any } ?? "unknown",
                                               "alpha": observedSurface?.alpha.map { Double($0) } ?? -1])
        guard confirmed else { return .failed }
        finishScreenSetRepair()
        return .succeeded
    }

    private func finishScreenSetRepair() {
        pendingScreenSetRecovery = nil
        recoveryEpochActive = false
        needsScreenSetRepair = false
        if presentation == .systemMinimize { refreshSeamSpaceAvailability() }
        if let restoreFrame { showMarker(windowQuartz: restoreFrame) }
        if isExpanded, !isPinned {
            outsideSince = nil
            lastSiblingInteractionAt = nil
            startLeaveWatch()
        }
        refreshPinControl()
        notifyChanged()
    }

    /// Screen-set restores finish inside the coordinator's write guard. A
    /// visible fallback keeps the original appearance separate from idle.
    func applyScreenSetSlot(
        displayID: String, edge: DisplayEdge, intent: ScreenSetRecoveryIntent? = nil
    ) -> ScreenSetApplicationResult {
        guard DisplayCatalog.screen(withID: displayID) != nil else { return .failed }
        guard !awaitingWindowControl else { return .waitingForControl }
        prepareForScreenSetChange()
        if let intent {
            restoreFrame = intent.frame ?? restoreFrame
            rescueDisplayFrame = intent.displayFrame ?? rescueDisplayFrame
            pendingScreenSetRecovery = intent
        } else if phase == .idle {
            restoreFrame = StashAX.frame(of: windowElement) ?? restoreFrame
        }
        isPinned = intent?.pinned ?? false
        pinWindow.conceal()
        self.edge = edge
        self.displayID = displayID
        phase = intent?.expanded == true ? .expanded : .captured
        markerHiddenForSpace = false
        return reconcileScreenSetPresentation(inspectFirst: true)
    }

    func leaveStash(to origin: CGPoint, preservingRecovery intent: ScreenSetRecoveryIntent? = nil) {
        pendingScreenSetRecovery = intent
        ignoringGeometryNotifications = true
        let size = restoreFrame?.size
            ?? StashAX.frame(of: windowElement)?.size
            ?? CGSize(width: max(lockedWidth, 100), height: 400)
        restoreFrame = CGRect(origin: origin, size: size)
        if awaitingWindowControl {
            // A genuine display departure can supersede a suspended stash.
            // Keep its usable landing point without writing through an
            // unverified reference. Discovery completes this fallback first.
            pendingVisibleFallbackOrigin = origin
            phase = .idle
            edge = nil
            presentation = nil
            isPinned = false
            hideMarker()
            pinWindow.conceal()
            ignoringGeometryNotifications = false
            diagnose("session.fallback-waits-for-control")
            return
        }
        shutdown(event: .miniaturized)
    }

    func completePendingVisibleFallback() {
        guard let origin = pendingVisibleFallbackOrigin, !awaitingWindowControl else { return }
        pendingVisibleFallbackOrigin = nil
        leaveStash(to: origin, preservingRecovery: pendingScreenSetRecovery)
    }

    /// Full-screening a window that is open on an edge ends the stash and
    /// leaves the window where the system put it.
    func leaveStashIfFullScreened() {
        guard isManaged, !awaitingWindowControl, phase == .expanded || phase == .captured else { return }
        guard StashAX.isFullScreen(windowElement) == true else { return }
        shutdown(event: .detachedFromEdge)
    }

    func mergeReveal() {
        guard !isPinned else { return }
        _ = expand(fromDock: false, merged: true)
    }

    func mergeHide() {
        guard !isPinned else { return }
        _ = collapse(merged: true)
    }

    func hideMarkerForSpaceChange() {
        hideMarker()
        pinWindow.conceal()
    }

    /// Rebuild after a Space switch has settled. A collapsed seam beacon is
    /// display-anchored and remains visible, enabled only when that display's
    /// current Space is an ordinary user Space. Expanded and slide-stashed
    /// windows show a marker only on the Space that contains the real window.
    func refreshMarkerAfterSpaceChange(
        isOnScreen: (UInt32, pid_t) -> Bool = { StashSurface.isOnScreen(windowID: $0, pid: $1) }
    ) {
        guard isManaged, !awaitingWindowControl, let restoreFrame else {
            hideMarker()
            return
        }
        let onActiveSpace: Bool
        if presentation == .systemMinimize, isCollapsed {
            // A collapsed seam's beacon is display-anchored, independent of
            // its minimized window's presence in the on-screen window list.
            onActiveSpace = true
        } else if let windowID {
            onActiveSpace = isOnScreen(windowID, pid)
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
        guard !awaitingWindowControl, isExpanded || isPinned else { return }
        cancelPendingRecovery()
        focusReturn.cancel()
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
        diagnose("session.shutdown", ["reason": String(describing: event)])
        let preservingRecovery = ScreenSetCoordinator.isApplying && event == .miniaturized
            && pendingScreenSetRecovery != nil
        if !preservingRecovery { cancelPendingRecovery() }
        focusReturn.cancel()
        presentationRequests.cancel()
        lifecycleGeneration += 1
        spaceRevealGeneration += 1
        pendingGeometryDetach?.cancel()
        pendingGeometryDetach = nil
        ignoringGeometryNotifications = true
        animator.cancel()
        busy = false
        restoringShared = false
        clickCollapseLockActive = false
        outsideSince = nil
        lastSiblingInteractionAt = nil
        hoverDelayTimer?.invalidate()
        leaveTimer?.invalidate()
        if event == .detachedFromEdge, !awaitingWindowControl, let liveFrame = StashAX.frame(of: windowElement) {
            // Keep the user's actual landing frame for a failed visibility
            // undo; a later retry must not return a deliberate drag to the edge.
            restoreFrame = liveFrame
        }
        let shouldRestore = SessionLifecyclePolicy.shouldRestoreVisibility(for: event)
        var positionOK = true
        var alphaOK = true
        var unminimizeOK = true
        if shouldRestore && awaitingWindowControl {
            // Quit/disable/trust loss must not send AX writes through a
            // disputed binding. Preserve the rescue dossier for later help.
            positionOK = false
            unminimizeOK = !usingSharedMinimize
        } else if shouldRestore {
            if usingSharedMinimize {
                unminimizeOK = StashAX.isMinimized(windowElement) == false
                    || StashAX.setMinimized(windowElement, false)
            }
            if let restoreFrame {
                positionOK = StashAX.setFrame(windowElement, restoreFrame)
            }
        }
        if SessionLifecyclePolicy.shouldRestoreAlpha(for: event), let windowID {
            alphaOK = StashSurface.belongsToProcess(windowID: windowID, pid: pid)
                && StashSurface.setAlpha(windowID: windowID, alpha: 1)
        }
        if event == .detachedFromEdge, usingSharedMinimize, !awaitingWindowControl {
            unminimizeOK = StashAX.isMinimized(windowElement) == false
                || StashAX.setMinimized(windowElement, false)
        } else if event == .detachedFromEdge, usingSharedMinimize {
            unminimizeOK = false
        }
        let restorationSettled = SessionLifecyclePolicy.shouldClearRescueRecords(
            for: event,
            restorePositionSucceeded: positionOK,
            restoreAlphaSucceeded: alphaOK,
            restoreUnminimizeSucceeded: unminimizeOK,
            isFloating: phase == .idle
        )
        if restorationSettled {
            StashRescue.clear(processID: pid, windowNumber: windowID)
        }
        hideMarker()
        pinWindow.conceal()
        effects.stop()
        if SessionLifecyclePolicy.shouldUninstallObservers(for: event) {
            uninstallObserver()
        }
        phase = .idle
        needsScreenSetRepair = preservingRecovery
        recoveryEpochActive = preservingRecovery
        edge = nil
        presentation = nil
        usingSharedMinimize = !unminimizeOK
        lastOwnedMinimizeAt = .distantPast
        isPinned = false
        if restorationSettled, SessionLifecyclePolicy.shouldClearDisplayBinding(for: event) {
            displayID = nil
            restoreFrame = nil
            rescueVisibleFrame = nil
            rescueDisplayFrame = nil
        }
        if !ScreenSetCoordinator.isApplying {
            switch event {
            case .detachedFromEdge, .windowDestroyed, .appDisabled, .appTerminated:
                if let windowID {
                    ScreenSetCoordinator.active?.forgetPlacement(
                        windowNumber: windowID, bundleID: bundleID,
                        everywhere: event != .detachedFromEdge
                    )
                }
            case .miniaturized, .appQuitting, .accessibilityLost:
                break
            }
        }
        if isTemporary, !preservingRecovery, !TemporaryShortcutPolicy.shouldKeepAfterIdle(
            stashActive: Preferences.shared.stashActive(bundleID: bundleID)
        ) {
            isTemporary = false
            ignoringGeometryNotifications = false
            onEnded?(self, event)
            return
        }
        if SessionLifecyclePolicy.shouldRemoveManagerSession(for: event) {
            onEnded?(self, event)
        }
        ignoringGeometryNotifications = false
        diagnose("session.shutdown-result", ["reason": String(describing: event),
                                             "positionOK": positionOK, "alphaOK": alphaOK,
                                             "unminimizeOK": unminimizeOK, "rescueCleared": restorationSettled])
        notifyChanged()
    }

    private func rehideCollapsed(on display: DisplayGeometry, next: StashCollapsePresentation) -> Bool {
        guard let edge, let restoreFrame else { return false }
        switch next {
        case .systemMinimize:
            guard let screen = DisplayCatalog.screen(withID: display.id),
                  let cgID = DisplayCatalog.displayID(for: screen) else { return false }
            seamSpaceAvailability = DisplaySpaceTransport.shared.availability(for: cgID)
            // Already minimized stashes may retain a disabled beacon while
            // Space information is unavailable. New seam hides require support.
            guard seamSpaceAvailability != .unavailable || usingSharedMinimize else { return false }
            usingSharedMinimize = true
            lastOwnedMinimizeAt = Date()
            guard StashAX.isMinimized(windowElement) == true || StashAX.setMinimized(windowElement, true) else { return false }
            // A minimized window is anchored by displayID; its frame can be
            // written on the confirmed reveal path if AX rejects it while hidden.
            if let windowID, !StashSurface.setAlpha(windowID: windowID, alpha: 1) { return false }
        case .slideOffscreen:
            let hidden = StashGeometryPolicy.visualHiddenOrigin(
                edge: edge, frame: restoreFrame, display: display.frame, lockedWidth: lockedWidth
            )
            // Hide before deminiaturizing so a topology conversion cannot flash
            // an ordinary window forward. No application activation is involved.
            guard let windowID,
                  StashSurface.setAlpha(windowID: windowID, alpha: StashGeometryPolicy.hiddenWindowAlpha) else { return false }
            if StashAX.isMinimized(windowElement) == true {
                guard StashAX.setMinimized(windowElement, false) else { return false }
            }
            usingSharedMinimize = false
            guard StashAX.setFrame(windowElement, CGRect(origin: hidden, size: restoreFrame.size)) else { return false }
        }
        return true
    }

    func capture(
        edge: DisplayEdge,
        frame: CGRect,
        display: DisplayGeometry,
        screen _: NSScreen,
        primaryHeight _: CGFloat
    ) -> Bool {
        diagnose("session.capture-request", ["targetDisplay": display.id, "targetEdge": edge.rawValue])
        guard !ScreenSetCoordinator.blocksUserGeometry, !awaitingWindowControl,
              StashSessionPolicy.phase(after: .capture, from: phase) == .captured else { return false }
        cancelPendingRecovery()
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
        restoreFrame = frame
        shutdown(event: .miniaturized)
        return false
    }

    @discardableResult
    func collapse(merged: Bool = false) -> Bool {
        diagnose("session.collapse-request", ["merged": merged])
        guard !ScreenSetCoordinator.blocksUserGeometry, !awaitingWindowControl else { return false }
        guard !isPinned else { return false }
        if busy {
            return presentationRequests.queue(StashPresentationRequest(expanded: false, merged: merged))
        }
        guard let next = StashSessionPolicy.phase(after: .collapse, from: phase),
              let edge,
              let frame = StashAX.frame(of: windowElement) ?? restoreFrame else {
            return false
        }
        cancelPendingRecovery()
        focusReturn.beginOperation()
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
        lockedWidth = frame.width > 0 ? frame.width : lockedWidth
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
        var collapseStarted = false
        presentationRequests.begin(StashPresentationRequest(expanded: false, merged: merged))
        defer {
            if !collapseStarted { presentationRequests.cancel() }
            if !collapseStarted, phase == .expanded, !isPinned {
                outsideSince = nil
                startLeaveWatch()
                refreshPinControl()
            }
        }

        switch presentation {
        case .systemMinimize:
            guard StashAX.canSetMinimized(windowElement) else { return false }
            let priorFrame = StashAX.frame(of: windowElement) ?? frame
            let moved = StashAX.setFrame(windowElement, expanded)
            guard moved else {
                _ = StashAX.setFrame(windowElement, priorFrame)
                return false
            }
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
            ) { [weak self] placed in
                guard let self else { return }
                // The 2pt positioning lip must not contribute content pixels.
                // A failed hide cannot commit a falsely collapsed session.
                guard placed, let windowID = self.windowID,
                      StashSurface.setAlpha(windowID: windowID, alpha: StashGeometryPolicy.hiddenWindowAlpha) else {
                    self.shutdown(event: .miniaturized)
                    return
                }
                self.finishCollapse(next: next, frame: expanded, merged: merged)
            }
        }
        collapseStarted = true
        return true
    }

    @discardableResult
    func expand(fromDock: Bool, merged: Bool = false, recordsRequest: Bool = true) -> Bool {
        diagnose("session.expand-request", ["fromDock": fromDock, "merged": merged])
        guard !ScreenSetCoordinator.blocksUserGeometry, !awaitingWindowControl else { return false }
        if busy {
            let accepted = presentationRequests.queue(StashPresentationRequest(expanded: true, fromDock: fromDock, merged: merged))
            if accepted, recordsRequest { onRevealRequested?(self) }
            return accepted
        }
        guard let next = StashSessionPolicy.phase(after: .expand, from: phase),
              let restoreFrame else {
            return false
        }
        cancelPendingRecovery()
        focusReturn.beginOperation()
        presentationRequests.begin(StashPresentationRequest(expanded: true, fromDock: fromDock, merged: merged))
        busy = true
        if recordsRequest { onRevealRequested?(self) }
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
        let motion = Preferences.shared.appearance(for: bundleID).resolvedMotion
        let usesOpacity = motion != .slide && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let windowID, !usesOpacity {
            guard StashSurface.setAlpha(windowID: windowID, alpha: 1) else {
                presentationRequests.cancel()
                busy = false
                return false
            }
        }
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        playEffects(collapsing: false, merged: merged, frame: restoreFrame, primaryHeight: primaryHeight)
        slide(
            from: current.origin,
            to: restoreFrame.origin,
            collapsing: false,
            merged: merged
        ) { [weak self] placed in
            guard let self else { return }
            guard placed else {
                self.presentationRequests.cancel()
                self.busy = false
                if !self.refreshCollapsePresentation(), !self.awaitingWindowControl { self.shutdown(event: .miniaturized) }
                return
            }
            self.finishExpand(next: next, frame: restoreFrame, fromDock: fromDock)
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
            guard StashAX.setFrame(windowElement, restoreFrame) else {
                failSharedRevealAfterDeminimize()
                return false
            }
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
            case let .success(targetSpaceID):
                guard DisplaySpaceTransport.shared.confirmsDestination(
                    windowID: windowID, displayID: cgDisplayID, targetSpaceID: targetSpaceID
                ) else {
                    self.failSharedRevealAfterDeminimize()
                    return
                }
                if fromDock { StashFocusReturn.remember(excluding: self.pid) }
                guard StashAX.setMinimized(self.windowElement, false) else {
                    self.failSharedRevealAfterDeminimize()
                    return
                }
                self.usingSharedMinimize = false
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.lifecycleGeneration == lifecycleToken,
                          self.spaceRevealGeneration == revealToken else {
                        return
                    }
                    guard !ScreenSetCoordinator.blocksUserGeometry,
                          DisplaySpaceTransport.shared.confirmsDestination(
                            windowID: windowID, displayID: cgDisplayID, targetSpaceID: targetSpaceID
                          ),
                          StashAX.setFrame(self.windowElement, restoreFrame),
                          DisplaySpaceTransport.shared.confirmsDestination(
                            windowID: windowID, displayID: cgDisplayID, targetSpaceID: targetSpaceID
                          ) else {
                        self.failSharedRevealAfterDeminimize()
                        return
                    }
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
        focusReturn.cancel()
        if restoringShared {
            presentationRequests.cancel()
        } else {
            // An outer-edge slide keeps its existing completion, but input
            // retained on the old Space must not start another transition.
            presentationRequests.discardPending()
        }
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

    private func failSharedRevealAfterDeminimize() {
        cancelPendingSpaceReveal()
        // Cancellation can release the session when re-minimize itself fails.
        // Never recreate a collapsed marker after that visibility fallback.
        guard phase == .collapsed else { return }
        failSharedReveal(availability: .unavailable)
    }

    /// An expanded seam window was minimized outside the collapse() write.
    /// Minimize is the hide, so keep the session and restore the beacon.
    func adoptSeamRecollapse() {
        guard presentation == .systemMinimize else { return }
        guard let next = StashSessionPolicy.phase(after: .collapse, from: phase),
              let frame = restoreFrame else {
            return
        }
        focusReturn.beginOperation()
        presentationRequests.cancel()
        usingSharedMinimize = true
        lastOwnedMinimizeAt = Date()
        restoringShared = false
        hoverDelayTimer?.invalidate()
        hoverDelayTimer = nil
        leaveTimer?.invalidate()
        leaveTimer = nil
        finishCollapse(next: next, frame: frame, merged: false)
    }

    func refreshSeamSpaceAvailability(
        read: (CGDirectDisplayID) -> SeamSpaceAvailability = {
            DisplaySpaceTransport.shared.availability(for: $0)
        }
    ) {
        guard presentation == .systemMinimize,
              let displayID,
              let screen = DisplayCatalog.screen(withID: displayID),
              let cgDisplayID = DisplayCatalog.displayID(for: screen) else {
            seamSpaceAvailability = .unavailable
            return
        }
        seamSpaceAvailability = read(cgDisplayID)
    }

    private func failSharedReveal(availability: SeamSpaceAvailability) {
        presentationRequests.cancel()
        seamSpaceAvailability = availability
        restoringShared = false
        busy = false
        cancelHoverReveal()
        if let restoreFrame { showMarker(windowQuartz: restoreFrame) }
        notifyChanged()
    }

    func finishExpand(
        next: StashSessionPhase,
        frame: CGRect,
        fromDock: Bool,
        activatesApp: Bool = true
    ) {
        let pending = presentationRequests.complete()
        let requestRevision = presentationRequests.revision
        phase = next
        if activatesApp { activateApp() }
        showMarker(windowQuartz: frame)
        startLeaveWatch()
        outsideSince = nil
        lastSiblingInteractionAt = nil
        busy = false
        refreshPinControl()
        if FocusReturnPolicy.shouldReleaseAfterExpand(fromDock: fromDock) {
            scheduleFocusRelease()
        }
        onExpanded?(self)
        notifyChanged()
        runPendingPresentation(pending, revision: requestRevision)
    }

    /// Full app activation plus AX main/focused writes. Reserved for
    /// deliberate reveals and for a presented window the pointer has entered —
    /// activation raises the app's whole window stack, so a passing hover must
    /// never trigger it.
    func activateApp() {
        StashOwnedActivation.note(bundleID: bundleID)
        if let running = NSRunningApplication(processIdentifier: pid) {
            running.activate(options: .activateIgnoringOtherApps)
        }
        _ = StashAX.setBool(windowElement, kAXMainAttribute as String, true)
        _ = StashAX.setBool(windowElement, kAXFocusedAttribute as String, true)
    }

    func finishCollapse(next: StashSessionPhase, frame: CGRect, merged: Bool) {
        let pending = presentationRequests.complete()
        let requestRevision = presentationRequests.revision
        phase = next
        StashRescue.persist(session: self)
        showMarker(windowQuartz: frame)
        busy = false
        refreshPinControl()
        if !merged {
            scheduleFocusRelease()
        }
        notifyChanged()
        onCollapsed?(self)
        runPendingPresentation(pending, revision: requestRevision)
    }

    private func runPendingPresentation(_ request: StashPresentationRequest?, revision: UInt) {
        guard let request, presentationRequests.revision == revision,
              isManaged, !busy, !ScreenSetCoordinator.blocksUserGeometry else { return }
        if request.expanded {
            // This intent was already recorded when it was queued. Replaying
            // it must not take preference back from a newer group request.
            _ = expand(fromDock: request.fromDock, merged: request.merged, recordsRequest: false)
        } else {
            _ = collapse(merged: request.merged)
        }
    }

    private func slide(
        from start: CGPoint,
        to end: CGPoint,
        collapsing: Bool,
        merged: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let height = (StashAX.frame(of: windowElement) ?? restoreFrame)?.height ?? lockedWidth
        let size = CGSize(width: lockedWidth, height: height)
        let plan = StashPresentationPlan(
            motion: Preferences.shared.appearance(for: bundleID).resolvedMotion,
            origin: start, destination: end, size: size, collapsing: collapsing,
            edge: edge ?? .left, reduceMotion: reduceMotion, canSetOpacity: windowID != nil
        )
        busy = true
        animator.begin(
            StashAnimator.Slide(
                target: windowElement,
                span: StashMotionPolicy.span(reduceMotion: reduceMotion, collapsing: collapsing, merged: merged),
                refundsClock: !merged,
                plan: plan,
                windowID: windowID
            ),
            onSettled: completion
        )
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
        let material = Preferences.shared.appearance(for: bundleID).resolvedMaterial
        if collapsing {
            effects.playCollapse(edge: edge, point: point, color: color, material: material, screen: screen)
        } else {
            effects.playExpand(edge: edge, point: point, color: color, material: material, screen: screen)
        }
    }

    private func notifyChanged() {
        diagnose("session.changed")
        onChanged?(self)
    }

    func diagnose(_ event: String, _ fields: @autoclosure () -> [String: Any] = [:]) {
        guard StashDiagnostics.isEnabled else { return }
        var row = fields()
        row["app"] = bundleID
        row["pid"] = pid
        row["subjectLaunch"] = processLaunchDate?.timeIntervalSince1970 ?? -1
        row["window"] = windowID ?? 0
        row["ax"] = String(CFHash(windowElement))
        row["phase"] = String(describing: phase)
        row["display"] = displayID ?? "none"
        row["edge"] = edge?.rawValue ?? 0
        row["presentation"] = presentation.map { String(describing: $0) } ?? "none"
        row["pinned"] = isPinned
        row["busy"] = busy
        row["restoringShared"] = restoringShared
        row["usingSharedMinimize"] = usingSharedMinimize
        row["leaveWatch"] = leaveTimer?.isValid == true
        row["needsRepair"] = needsScreenSetRepair
        row["quiet"] = ScreenSetCoordinator.blocksUserGeometry
        row["restoreFrame"] = restoreFrame.map { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] } ?? []
        row["awaitingControl"] = awaitingWindowControl
        row["bindingGeneration"] = windowBindingGeneration
        row["lifecycleGeneration"] = lifecycleGeneration
        row["recoveryPending"] = pendingScreenSetRecovery != nil
        StashDiagnostics.record(event, row)
    }

    func diagnoseLeaveGate(_ reason: String) {
        guard StashDiagnostics.isEnabled, diagnosticLeaveReason != reason else { return }
        diagnosticLeaveReason = reason
        diagnose("session.leave-gate", ["reason": reason])
    }
}
