import AppKit
import ApplicationServices
import EdgeStashLogic

enum ScreenSetApplicationResult: Equatable {
    case succeeded, waitingForControl, waitingForPersistence, blockedSpace, failed
}

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
    var onPresentationRequested: ((StashSession, StashPresentationRequest) -> Void)?
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
    var acceptsPresentationRequests: Bool { isManaged && !awaitingWindowControl && !ScreenSetCoordinator.blocksUserGeometry }
    var lifecycleGeneration = 0
    var spaceRevealGeneration = 0
    /// AX moved/miniaturized notifications during a coordinator or shutdown
    /// write must not be treated as a user drag off the edge.
    var ignoringGeometryNotifications = false
    var pendingGeometryDetach: DispatchWorkItem?
    var externalGeometryWasDragged = false
    private(set) var needsScreenSetRepair = false
    private var recoverySpacePreparation = SeamRecoveryPreparation()
    private var pendingMinimize: (confirmation: WindowWriteConfirmation, next: StashSessionPhase,
                                  frame: CGRect, merged: Bool)?
    private var pendingPresentation: (confirmation: WindowWriteConfirmation, phase: StashSessionPhase,
                                      presentation: StashCollapsePresentation, frame: CGRect)?
    private var unconfirmedOwnedMinimize = false
    private var pendingMinimizeRelease: WindowWriteConfirmation?

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
        recoverySpacePreparation.cancel()
        cancelPresentationConfirmation()
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
        guard phase == .idle, !busy, let frame = eligibleCaptureFrame else { return false }
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
        guard phase == .idle, !busy, let frame = eligibleCaptureFrame else { return false }
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

    private var eligibleCaptureFrame: CGRect? {
        guard !awaitingWindowControl, !usingSharedMinimize, !ScreenSetCoordinator.blocksUserGeometry else { return nil }
        let frame = StashAX.frame(of: windowElement)
        return StashSessionPolicy.mayCapture(
            isStandard: StashAX.isStandardWindow(windowElement),
            minimized: StashAX.isMinimized(windowElement), fullScreen: StashAX.isFullScreen(windowElement),
            hasWindowNumber: windowID != nil, frame: frame
        ) ? frame : nil
    }

    var isEligibleForCapture: Bool { eligibleCaptureFrame != nil }

    func toggleFromShortcut() {
        guard isManaged else { return }
        setPresentation(expanded: !desiredPresentationIsExpanded, source: .shortcut)
    }

    func expandFromDock(source: StashRequestSource = .dock) {
        setPresentation(expanded: true, source: source)
    }

    func setPresentation(expanded: Bool, source: StashRequestSource, commandID: UInt? = nil) {
        guard acceptsPresentationRequests else {
            diagnose("session.presentation-rejected", ["source": source.rawValue, "targetExpanded": expanded,
                                                       "reason": "unavailable", "command": commandID ?? 0])
            return
        }
        if !expanded, source == .shortcut { isPinned = false }
        _ = requestPresentation(StashPresentationRequest(expanded: expanded, fromDock: expanded,
                                                        source: source, commandID: commandID))
    }

    /// Marker and merged hover share admission and revision ownership. The
    /// merged rail owns its own suppression and per-visit click lock.
    func canBeginHoverReveal(merged: Bool = false) -> Bool {
        acceptsPresentationRequests && !recoveryEpochActive && !presentationRequests.hasOutstandingRequest
            && HoverRevealPolicy.shouldBegin(phase: phase, isBusy: busy,
                markerSuppressed: !merged && markerSuppressed, clickLocked: !merged && clickCollapseLockActive,
                buttonPressed: NSEvent.pressedMouseButtons != 0)
            && (presentation != .systemMinimize || canBeginSeamReveal)
    }

    @discardableResult
    private func requestPresentation(_ request: StashPresentationRequest, expectedRevision: UInt? = nil) -> Bool {
        let before = presentationRequests.revision
        let decision = presentationRequests.submit(request, phase: phase, busy: busy,
            available: acceptsPresentationRequests, pinned: isPinned, expectedRevision: expectedRevision)
        diagnose("session.presentation-request", ["source": request.source.rawValue, "targetExpanded": request.expanded,
            "decision": decision.rawValue, "revisionBefore": before, "command": request.commandID ?? 0])
        guard decision.accepted else { return false }
        let operation = presentationRequests.operation
        if !request.source.isPassive { cancelHoverReveal() }
        onPresentationRequested?(self, request)
        guard decision == .start else { return true }
        return performPresentation(request, operation: operation)
    }

    private func performPresentation(_ request: StashPresentationRequest, operation: UInt) -> Bool {
        guard presentationRequests.owns(operation: operation) else {
            diagnose("session.presentation-execution-dropped", ["operation": operation, "reason": "superseded-before-write"])
            return false
        }
        guard acceptsPresentationRequests, request.expanded || !isPinned else {
            presentationRequests.cancel()
            diagnose("session.presentation-execution-dropped", ["operation": operation, "reason": "unavailable-or-pinned"])
            return false
        }
        busy = true
        let accepted = request.expanded
            ? performExpand(fromDock: request.fromDock, merged: request.merged)
            : performCollapse(merged: request.merged)
        // A synchronous native refusal must release the target it admitted,
        // but cannot erase a newer operation begun by a completion callback.
        if !accepted, presentationRequests.owns(operation: operation) {
            presentationRequests.cancel()
            busy = false
        }
        diagnose("session.presentation-execution", ["source": request.source.rawValue, "targetExpanded": request.expanded,
            "accepted": accepted, "operation": operation, "command": request.commandID ?? 0])
        return accepted
    }

    /// Invalidate callbacks carrying pre-change coordinates before waiting for
    /// display enumeration. The settled transaction will restore presentation.
    func prepareForScreenSetChange(invalidateSpacePreparation: Bool = true) {
        // Re-entering the same pending target cannot invalidate the callback
        // whose completion is the only event able to resume its control wait.
        if !invalidateSpacePreparation, recoverySpacePreparation.state == .pending { return }
        if invalidateSpacePreparation {
            if recoverySpacePreparation.state == .pending { onControlReady?(self) }
            if pendingPresentation != nil { onControlReady?(self) }
            recoverySpacePreparation.cancel()
            cancelPresentationConfirmation()
        }
        pendingMinimize = nil
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
        let result = reconcileScreenSetPresentation()
        if result == .waitingForControl {
            // Geometry refreshes outside a screen transaction need the same
            // retry owner to consume their asynchronous readback completion.
            ScreenSetCoordinator.active?.waitForControl(of: self)
            return true
        }
        return result == .succeeded
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
        if pendingPresentation != nil {
            return confirmScreenSetPresentation(readWindows: readWindows)
        }
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
        let needsSpaceTransaction = WindowRecoveryPolicy.requiresSpacePreparation(
            expanded: isExpanded, minimized: isMinimized, previous: presentation,
            next: next, ownsMinimize: usingSharedMinimize)
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
            let intent = recoveryIntent
            let rescueChanged = rescueVisibleFrame != rebased || rescueDisplayFrame != display.frame
            restoreFrame = rebased
            lockedWidth = rebased.width
            rescueVisibleFrame = rebased
            rescueDisplayFrame = display.frame
            presentation = next
            usingSharedMinimize = !isExpanded && next == .systemMinimize
            if !isExpanded { phase = .collapsed }
            if rescueChanged, !StashRescue.persist(session: self) {
                // Keep the already healthy physical presentation. Persistence
                // failure cannot claim completion, or open a hidden window via
                // the generic visible fallback just to retry its journal.
                if let intent { retainRecoveryIntent(intent) }
                recoveryEpochActive = false
                refreshPinControl()
                return .waitingForPersistence
            }
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
        guard StashRescue.persist(session: self) else {
            if needsSpaceTransaction, let intent = recoveryIntent {
                holdMinimizedRecovery(intent, availability: .unavailable, waiting: false)
                return .blockedSpace
            }
            return .failed
        }
        if needsSpaceTransaction { return repairMinimizedSession(on: display, frame: rebased, next: next) }
        if isExpanded {
            if isMinimized {
                usingSharedMinimize = true
                guard StashAX.setMinimized(windowElement, false) else { return .failed }
            }
            if let windowID, !StashSurface.setAlpha(windowID: windowID, alpha: 1) { return .failed }
            usingSharedMinimize = false
            guard StashAX.setFrame(windowElement, rebased) else { return .failed }
        } else {
            guard rehideCollapsed(on: display, next: next) else { return .failed }
            phase = .collapsed
        }
        presentation = next
        presentationRequests.begin(StashPresentationRequest(expanded: isExpanded, source: .recovery))
        busy = true
        pendingPresentation = (WindowWriteConfirmation(now: ProcessInfo.processInfo.systemUptime),
                               phase, next, isExpanded ? rebased : hidden)
        return confirmScreenSetPresentation(readWindows: readWindows)
    }

    private func confirmScreenSetPresentation(readWindows: () -> [StashRecoverySurface]?) -> ScreenSetApplicationResult {
        guard let pending = pendingPresentation else { return .failed }
        let observedMinimized = StashAX.isMinimized(windowElement)
        let observedFrame = StashAX.frame(of: windowElement)
        let observedSurface = readWindows()?.first { $0.windowID == windowID && $0.pid == pid }
        let confirmed = WindowRecoveryPolicy.presentationMatches(
            phase: pending.phase, presentation: pending.presentation, expectedFrame: pending.frame,
            actualFrame: observedFrame, minimized: observedMinimized, alpha: observedSurface?.alpha
        )
        let result = pending.confirmation.observe(matches: confirmed, now: ProcessInfo.processInfo.systemUptime)
        diagnose("session.recovery-readback", ["confirmed": confirmed, "minimized": observedMinimized.map { $0 as Any } ?? "unknown",
            "alpha": observedSurface?.alpha.map { Double($0) } ?? -1, "confirmation": String(describing: result),
            "expectedFrame": [Double(pending.frame.minX), Double(pending.frame.minY), Double(pending.frame.width), Double(pending.frame.height)],
            "observedFrame": observedFrame.map { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] } ?? []])
        switch result {
        case .waiting: return .waitingForControl
        case .expired:
            cancelPresentationConfirmation()
            return .failed
        case .confirmed:
            let completedOperation = presentationRequests.operation
            let request = presentationRequests.complete()
            let revision = presentationRequests.revision
            pendingPresentation = nil
            busy = false
            phase = pending.phase
            presentation = pending.presentation
            unconfirmedOwnedMinimize = false
            finishScreenSetRepair()
            diagnose("session.presentation-complete", ["boundary": "recovery", "completedOperation": completedOperation])
            deferPendingPresentation(request, revision: revision)
            return .succeeded
        }
    }

    private func cancelPresentationConfirmation() {
        guard pendingPresentation != nil else { return }
        pendingPresentation = nil
        busy = false
        presentationRequests.cancel()
    }

    private func deferPendingPresentation(_ request: StashPresentationRequest?, revision: UInt) {
        guard let request else { return }
        // Confirmation can finish inside the coordinator's synchronous write
        // guard. Replay after it commits; a newer action or cancellation wins
        // through the same revision check used by animation completions.
        DispatchQueue.main.async { [weak self] in
            self?.runPendingPresentation(request, revision: revision)
        }
    }

    private func holdMinimizedRecovery(_ intent: ScreenSetRecoveryIntent,
                                       availability: SeamSpaceAvailability, waiting: Bool) {
        pendingScreenSetRecovery = intent
        needsScreenSetRepair = true
        recoveryEpochActive = waiting
        phase = .collapsed
        presentation = .systemMinimize
        usingSharedMinimize = true
        isPinned = false
        seamSpaceAvailability = availability
        pinWindow.conceal()
        if let restoreFrame { showMarker(windowQuartz: restoreFrame) }
        notifyChanged()
    }

    /// Migration remains asynchronous and minimized. The existing retry owner
    /// resumes the same budget after preparation; no placement is attempted on
    /// an unconfirmed Space, and refusal never scatters an unminimized window.
    private func repairMinimizedSession(on display: DisplayGeometry, frame: CGRect,
                                    next: StashCollapsePresentation) -> ScreenSetApplicationResult {
        guard let intent = recoveryIntent, let windowID,
              let screen = DisplayCatalog.screen(withID: display.id),
              let cgID = DisplayCatalog.displayID(for: screen) else { return .failed }
        let transport = DisplaySpaceTransport.shared
        recoverySpacePreparation.select(intent.placement)
        let availability = transport.availability(for: cgID)
        guard case let .ready(currentSpace) = availability else {
            recoverySpacePreparation.cancel()
            holdMinimizedRecovery(intent, availability: availability, waiting: false)
            return .blockedSpace
        }
        let target: UInt64
        switch recoverySpacePreparation.state {
        case .pending:
            holdMinimizedRecovery(intent, availability: .unavailable, waiting: true)
            return .waitingForControl
        case let .refused(reason):
            recoverySpacePreparation.cancel()
            holdMinimizedRecovery(intent, availability: reason, waiting: false)
            return .blockedSpace
        case let .prepared(space):
            recoverySpacePreparation.cancel()
            guard space == currentSpace else {
                holdMinimizedRecovery(intent, availability: .unavailable, waiting: false)
                return .blockedSpace
            }
            target = space
        case .idle:
            if transport.confirmsDestination(windowID: windowID, displayID: cgID, targetSpaceID: currentSpace) {
                target = currentSpace
            } else {
                let ticket = recoverySpacePreparation.begin(intent.placement)
                holdMinimizedRecovery(intent, availability: .unavailable, waiting: true)
                let lifecycle = lifecycleGeneration
                let generation = spaceRevealGeneration
                transport.prepareMinimizedWindow(windowID: windowID, for: cgID) { [weak self] result in
                    // Even a synchronous refusal resumes only after the caller
                    // has registered its control wait with the coordinator.
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.lifecycleGeneration == lifecycle,
                              self.spaceRevealGeneration == generation,
                              self.pendingScreenSetRecovery?.placement == intent.placement else { return }
                        let prepared: SeamRecoveryPreparation.State
                        switch result {
                        case let .success(space): prepared = .prepared(space)
                        case let .failure(error): prepared = .refused(
                            error == .disabledFullScreen ? .disabledFullScreen : .unavailable)
                        }
                        guard self.recoverySpacePreparation.complete(ticket, target: intent.placement,
                                                                      result: prepared) else { return }
                        self.onControlReady?(self)
                    }
                }
                return .waitingForControl
            }
        }
        usingSharedMinimize = true
        let destination = intent.expanded ? frame : CGRect(
            origin: StashGeometryPolicy.visualHiddenOrigin(edge: edge ?? .left, frame: frame,
                display: display.frame, lockedWidth: frame.width), size: frame.size)
        let result = commitSeamReveal(windowID: windowID, displayID: cgID, spaceID: target,
                                     frame: destination, alpha: intent.expanded ? 1 : 0)
        switch result {
        case .succeeded:
            phase = intent.expanded ? .expanded : .collapsed
            isPinned = intent.pinned
            usingSharedMinimize = false
            presentation = next
            finishScreenSetRepair()
            return .succeeded
        case .keptMinimized:
            holdMinimizedRecovery(intent, availability: .unavailable, waiting: false)
            return .blockedSpace
        case .releaseRequired:
            return .failed
        }
    }

    private func commitSeamReveal(windowID: UInt32, displayID: CGDirectDisplayID,
                                  spaceID: UInt64, frame: CGRect, alpha: Float = 1) -> SeamRevealCommitResult {
        SeamRevealCommit.perform(
            confirmsDestination: {
                DisplaySpaceTransport.shared.confirmsDestination(
                    windowID: windowID, displayID: displayID, targetSpaceID: spaceID)
            },
            restoreOpacity: { StashSurface.setAlpha(windowID: windowID, alpha: alpha) },
            deminimize: { StashAX.setMinimized(self.windowElement, false) },
            placeFrame: {
                let written = StashAX.setFrame(self.windowElement, frame)
                let minimized = StashAX.isMinimized(self.windowElement)
                let observed = StashAX.frame(of: self.windowElement)
                let confirmed = written && minimized == false
                    && observed.map { WindowRecoveryPolicy.framesMatch($0, frame) } == true
                if !confirmed {
                    self.diagnose("session.seam-frame-rejected", [
                        "written": written, "minimized": minimized.map { $0 as Any } ?? "unknown",
                        "expectedFrame": [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)],
                        "observedFrame": observed.map { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] } ?? []
                    ])
                }
                return confirmed
            },
            reminimize: {
                self.lastOwnedMinimizeAt = Date()
                return StashAX.setMinimized(self.windowElement, true)
            },
            onFailure: { failure in
                self.diagnose("session.seam-commit-failed", ["stage": failure.rawValue,
                    "targetSpace": spaceID, "targetDisplay": displayID])
            }
        )
    }

    private func finishScreenSetRepair() {
        cancelPresentationConfirmation()
        unconfirmedOwnedMinimize = false
        recoverySpacePreparation.cancel()
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
        guard pendingMinimizeRelease == nil else { return .waitingForControl }
        if self.displayID == displayID, self.edge == edge, pendingPresentation != nil {
            // A read-only confirmation must not reinstall the pre-rebase
            // intent frame, reset phase, or cancel a newer named request.
            return reconcileScreenSetPresentation(inspectFirst: true)
        }
        cancelPresentationConfirmation()
        if let intent { recoverySpacePreparation.select(intent.placement) }
        prepareForScreenSetChange(invalidateSpacePreparation: false)
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

    func mergeReveal(source: StashRequestSource = .mergeClick, expectedRevision: UInt? = nil) {
        guard !isPinned else { return }
        _ = expand(fromDock: false, merged: true, source: source, expectedRevision: expectedRevision)
    }

    func mergeHide() {
        guard !isPinned else { return }
        _ = collapse(merged: true, source: .mergeClick)
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
        guard !awaitingWindowControl, !busy, isExpanded || isPinned else { return }
        cancelPendingRecovery()
        presentationRequests.discardPending()
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
        let hadUnconfirmedMinimize = unconfirmedOwnedMinimize
        pendingMinimize = nil
        pendingPresentation = nil
        pendingMinimizeRelease = nil
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
                // An earlier accepted minimize can still be queued in the
                // target app. Always submit the inverse, even on a false read.
                unminimizeOK = releaseOwnedMinimize()
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
            unminimizeOK = releaseOwnedMinimize()
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
        if hadUnconfirmedMinimize, shouldRestore, !awaitingWindowControl, pendingMinimizeRelease == nil {
            // Fresh binding validation must finish release before the dossier
            // can be removed. The current read may predate both queued writes.
            markWindowControlUnavailable()
        }
        diagnose("session.shutdown-result", ["reason": String(describing: event),
                                             "positionOK": positionOK, "alphaOK": alphaOK,
                                             "unminimizeOK": unminimizeOK, "rescueCleared": restorationSettled])
        notifyChanged()
    }

    /// A false read immediately after reversing an unconfirmed hide can still
    /// predate both writes. Keep its dossier through the existing settle bound.
    private func releaseOwnedMinimize() -> Bool {
        guard StashAX.requestMinimized(windowElement, false) else { return false }
        if unconfirmedOwnedMinimize {
            pendingMinimizeRelease = WindowWriteConfirmation(now: ProcessInfo.processInfo.systemUptime)
            return false
        }
        return StashAX.isMinimized(windowElement) == false
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
            if StashAX.isMinimized(windowElement) != true {
                unconfirmedOwnedMinimize = true
                guard StashAX.requestMinimized(windowElement, true) else { return false }
            }
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
        if collapse(source: .capture) { return true }
        restoreFrame = frame
        shutdown(event: .miniaturized)
        return false
    }

    @discardableResult
    func collapse(merged: Bool = false, source: StashRequestSource = .explicit) -> Bool {
        requestPresentation(StashPresentationRequest(expanded: false, merged: merged, source: source))
    }

    private func performCollapse(merged: Bool) -> Bool {
        let operation = presentationRequests.operation
        diagnose("session.collapse-request", ["merged": merged])
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
        guard StashRescue.persist(session: self) else { return false }
        leaveTimer?.invalidate()
        pinWindow.conceal()
        var collapseStarted = false
        defer {
            if !collapseStarted, phase == .expanded, !isPinned, !awaitingWindowControl {
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
            guard StashAX.requestMinimized(windowElement, true) else {
                // A failed acknowledgement can still have minimized the
                // window. Keep the visibility debt until a fresh read proves
                // otherwise; shutdown must not clear its rescue prematurely.
                // Transport failure is also uncertain: never erase ownership
                // on a possibly stale false observation.
                unconfirmedOwnedMinimize = true
                markWindowControlUnavailable()
                return false
            }
            unconfirmedOwnedMinimize = true
            pendingMinimize = (WindowWriteConfirmation(now: ProcessInfo.processInfo.systemUptime), next, expanded, merged)
            busy = true
            collapseStarted = true
            confirmOwnedMinimize()
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
                guard let self, self.presentationRequests.owns(operation: operation) else { return }
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

    /// Run by the existing 0.5s observation pass. No additional polling timer
    /// or repeated hide write is created while readback is settling.
    @discardableResult
    func reconcilePendingWindowWrites() -> Bool {
        if let release = pendingMinimizeRelease {
            let now = ProcessInfo.processInfo.systemUptime
            guard release.hasSettled(now: now) else { return true }
            pendingMinimizeRelease = nil
            let confirmed = StashAX.isMinimized(windowElement) == false
            diagnose("session.minimize-release-confirmation", ["confirmed": confirmed])
            // A timeout cannot erase visibility debt or start an unbounded
            // inverse-write loop. Failed release keeps its persisted dossier.
            guard confirmed else {
                if pendingScreenSetRecovery != nil { onControlReady?(self) }
                return true
            }
            unconfirmedOwnedMinimize = false
            if pendingScreenSetRecovery != nil {
                onControlReady?(self)
            } else {
                shutdown(event: .miniaturized)
            }
            return true
        }
        if pendingMinimize != nil {
            confirmOwnedMinimize()
            return true
        }
        if pendingPresentation != nil {
            onControlReady?(self)
            return true
        }
        return false
    }

    private func confirmOwnedMinimize() {
        guard let pending = pendingMinimize else { return }
        let observed = StashAX.isMinimized(windowElement)
        let result = pending.confirmation.observe(matches: observed == true,
                                                  now: ProcessInfo.processInfo.systemUptime)
        diagnose("session.minimize-confirmation", ["result": String(describing: result),
            "observed": observed.map { $0 as Any } ?? "unknown"])
        switch result {
        case .waiting:
            break
        case .confirmed:
            pendingMinimize = nil
            unconfirmedOwnedMinimize = false
            finishCollapse(next: pending.next, frame: pending.frame, merged: pending.merged)
        case .expired:
            pendingMinimize = nil
            // Do not convert an unconfirmed owned hide into an ordinary idle
            // window. Existing control validation/recovery retains its rescue.
            if let slot = screenSetSlot {
                retainRecoveryIntent(ScreenSetRecoveryIntent(placement: slot,
                                                              expanded: desiredPresentationIsExpanded,
                                                              frame: pending.frame,
                                                              displayFrame: rescueDisplayFrame))
            }
            markWindowControlUnavailable()
        }
    }

    @discardableResult
    func expand(fromDock: Bool, merged: Bool = false, source: StashRequestSource = .explicit,
                expectedRevision: UInt? = nil) -> Bool {
        requestPresentation(StashPresentationRequest(expanded: true, fromDock: fromDock, merged: merged, source: source),
                            expectedRevision: expectedRevision)
    }

    private func performExpand(fromDock: Bool, merged: Bool) -> Bool {
        let operation = presentationRequests.operation
        diagnose("session.expand-request", ["fromDock": fromDock, "merged": merged])
        guard let next = StashSessionPolicy.phase(after: .expand, from: phase),
              let restoreFrame else {
            return false
        }
        cancelPendingRecovery()
        focusReturn.beginOperation()
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
            guard let self, self.presentationRequests.owns(operation: operation) else { return }
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
        let minimized = StashAX.isMinimized(windowElement)
        if minimized == false {
            usingSharedMinimize = false
            restoringShared = true
            guard StashAX.setFrame(windowElement, restoreFrame) else {
                failSharedRevealAfterDeminimize()
                return false
            }
            restoringShared = false
            finishExpand(next: next, frame: restoreFrame, fromDock: false, activatesApp: false)
            return true
        }
        guard minimized == true else {
            markWindowControlUnavailable()
            return false
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
        let operation = presentationRequests.operation
        DisplaySpaceTransport.shared.prepareMinimizedWindow(
            windowID: windowID,
            for: cgDisplayID
        ) { [weak self] result in
            guard let self,
                  self.presentationRequests.owns(operation: operation),
                  self.lifecycleGeneration == lifecycleToken,
                  self.spaceRevealGeneration == revealToken,
                  self.phase == .collapsed,
                  self.usingSharedMinimize else {
                return
            }
            switch result {
            case let .success(targetSpaceID):
                if fromDock { StashFocusReturn.remember(excluding: self.pid) }
                switch self.commitSeamReveal(windowID: windowID, displayID: cgDisplayID,
                                             spaceID: targetSpaceID, frame: restoreFrame) {
                case .succeeded:
                    self.usingSharedMinimize = false
                    self.restoringShared = false
                    self.finishExpand(next: next, frame: restoreFrame, fromDock: fromDock)
                case .keptMinimized:
                    self.usingSharedMinimize = true
                    self.failSharedReveal(availability: .unavailable)
                case .releaseRequired:
                    self.shutdown(event: .miniaturized)
                }
            case let .failure(error):
                self.diagnose("session.seam-prepare-failed", ["reason": String(describing: error)])
                let availability: SeamSpaceAvailability = error == .disabledFullScreen
                    ? .disabledFullScreen
                    : .unavailable
                self.failSharedReveal(availability: availability)
            }
        }
        return true
    }

    func cancelPendingSpaceReveal() {
        if recoverySpacePreparation.state == .pending { onControlReady?(self) }
        recoverySpacePreparation.cancel()
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
        diagnose("session.seam-reveal-failed", ["availability": String(describing: availability)])
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
        let completedOperation = presentationRequests.operation
        let pending = presentationRequests.complete()
        let requestRevision = presentationRequests.revision
        phase = next
        busy = false
        if activatesApp { activateApp() }
        showMarker(windowQuartz: frame)
        startLeaveWatch()
        outsideSince = nil
        lastSiblingInteractionAt = nil
        diagnose("session.presentation-complete", ["boundary": "expand", "completedOperation": completedOperation])
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
        let completedOperation = presentationRequests.operation
        let pending = presentationRequests.complete()
        let requestRevision = presentationRequests.revision
        phase = next
        busy = false
        StashRescue.persist(session: self)
        showMarker(windowQuartz: frame)
        diagnose("session.presentation-complete", ["boundary": "collapse", "completedOperation": completedOperation])
        refreshPinControl()
        if !merged {
            scheduleFocusRelease()
        }
        notifyChanged()
        onCollapsed?(self)
        runPendingPresentation(pending, revision: requestRevision)
    }

    private func runPendingPresentation(_ request: StashPresentationRequest?, revision: UInt) {
        guard request != nil else { return }
        guard acceptsPresentationRequests, !busy,
              let replay = presentationRequests.resume(revision: revision, phase: phase) else {
            diagnose("session.presentation-replay-dropped", ["expectedRevision": revision])
            return
        }
        diagnose("session.presentation-replay", ["expectedRevision": revision, "source": replay.source.rawValue,
                                                 "command": replay.commandID ?? 0])
        _ = performPresentation(replay, operation: presentationRequests.operation)
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
        row["session"] = mergeID
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
        row["desiredExpanded"] = desiredPresentationIsExpanded
        row["requestRevision"] = presentationRequests.revision
        row["presentationOperation"] = presentationRequests.operation
        for (name, request) in [("active", presentationRequests.active), ("pending", presentationRequests.pending),
                                ("deferred", presentationRequests.deferred)] {
            row[name + "Request"] = request.map { ["expanded": $0.expanded, "source": $0.source.rawValue,
                                                  "command": $0.commandID ?? 0] as [String: Any] } ?? [:]
        }
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
        row["minimizeConfirmationPending"] = pendingMinimize != nil
        row["presentationConfirmationPending"] = pendingPresentation != nil
        row["minimizeReleaseConfirmationPending"] = pendingMinimizeRelease != nil
        row["unconfirmedOwnedMinimize"] = unconfirmedOwnedMinimize
        StashDiagnostics.record(event, row)
    }

    func diagnoseLeaveGate(_ reason: String) {
        guard StashDiagnostics.isEnabled, diagnosticLeaveReason != reason else { return }
        diagnosticLeaveReason = reason
        diagnose("session.leave-gate", ["reason": reason])
    }
}
