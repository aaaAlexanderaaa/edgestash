import AppKit
import ApplicationServices
import EdgeStashLogic

/// Live stash coordinator. Starts only after Accessibility is already trusted.
final class StashEngine {
    private var sessions: [StashSession] = []
    private var appObservers: [pid_t: (AXObserver, CFRunLoopSource)] = [:]
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var localMouseDown: Any?
    private var localMouseUp: Any?
    private var mouseMoveMonitor: Any?
    private var showAllKeyMonitor: Any?
    private var localShowAllKeyMonitor: Any?
    private var pendingThumbnailTitle: String?
    private var approachTargetID: String?
    private var spaceRebuildGeneration = 0
    /// Sessions whose collapse completed under a parked pointer. A parked
    /// pointer is not an approach, so the band stays disarmed until the
    /// pointer has left it once — the same exit-rearm rule as the merged
    /// strip's click lock.
    private var approachSuppressedIDs = Set<String>()
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var lastAcceptedMouse: SessionMouseRelayPolicy.Kind?
    private var captureGesture: (session: StashSession, initialFrame: CGRect)?
    private var captureRetryGeneration = 0
    private var syncTimer: Timer?
    private var minimizeTimer: Timer?
    private let hotkeys = StashHotkeys()
    private let merged = StashMergeCoordinator()
    private var lastPreferredSession: [String: ObjectIdentifier] = [:]
    private var temporarySession: StashSession?
    private let screenSets = ScreenSetCoordinator()
    private var lastTopologyRevision: UInt = 0
    private var recentlyUnhidden = Set<String>()
    private var hiddenBundles = Set<String>()
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        guard AccessibilityGrant.isTrusted(prompt: false) else { return }
        isRunning = true
        StashRescue.recoverPending(reason: "engine-start")
        screenSets.captureBaseline()
        screenSets.onSettled = { [weak self] in
            guard let self else { return }
            self.merged.reconcile(sessions: self.sessions)
            self.reevaluateSeamApproach()
        }
        lastTopologyRevision = Preferences.shared.displayTopologyRevision
        StashMultiWindowTip.shared.resetForLaunch()
        observeWorkspace()
        observeMice()
        hotkeys.onAppShortcut = { [weak self] bundleID in self?.handleAppShortcut(bundleID) }
        hotkeys.onTemporaryShortcut = { [weak self] in self?.handleTemporaryShortcut() }
        hotkeys.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: PreferenceSignal.didChange,
            object: nil
        )
        syncSessions()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.syncSessions()
        }
        minimizeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.sessions.forEach { $0.reconcileMinimized() }
        }
    }

    func suspendTrustLost() {
        guard isRunning else { return }
        endSessions(sessions.map { ($0, .accessibilityLost) })
        merged.tearDown()
        teardownObservers()
        isRunning = false
    }

    func shutdown() {
        guard isRunning || !sessions.isEmpty else { return }
        endSessions(sessions.map { ($0, .appQuitting) })
        sessions.removeAll()
        temporarySession = nil
        merged.tearDown()
        teardownObservers()
        isRunning = false
    }

    func handleAppActivated(bundleID: String) {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            StashFocusReturn.noteActivation(app)
        }
        guard isRunning else { return }

        let group = sessions.filter { $0.bundleID == bundleID }
        let hasOnDesktopWindow = group.contains(where: \.isOnDesktop)
        let allStandardWindowsStashed = !group.isEmpty && group.allSatisfy(\.isManaged)
        let kind: AppActivationKind
        if StashOwnedActivation.consume(bundleID) {
            kind = .ownedReveal
        } else {
            kind = activationKind(for: bundleID)
        }
        let decision = StashActivationPolicy.decision(
            kind: kind,
            hasOnDesktopWindow: hasOnDesktopWindow,
            allStandardWindowsStashed: allStandardWindowsStashed,
            allStashedDock: Preferences.shared.allStashedDockAction(for: bundleID)
        )
        applyActivation(decision, bundleID: bundleID, group: group)
    }

    func noteMacWillSleep() {
        screenSets.noteWillSleep()
    }

    func noteMacDidWake() {
        screenSets.noteDidWake { [weak self] in self?.sessions ?? [] }
    }

    func noteMacScreensDidWake() {
        screenSets.noteScreensDidWake { [weak self] in self?.sessions ?? [] }
    }

    @objc private func preferencesChanged() {
        guard isRunning else { return }
        hotkeys.reload()
        let revision = Preferences.shared.displayTopologyRevision
        if revision != lastTopologyRevision {
            lastTopologyRevision = revision
            screenSets.noteTopologyChanged { [weak self] in self?.sessions ?? [] }
        }
        if SessionLifecyclePolicy.shouldRecoverOnPreferenceChange() {
            StashRescue.recoverPending(reason: "topology")
        }
        syncSessions()
    }

    @objc private func spaceDidChange() {
        guard isRunning else { return }
        StashMultiWindowTip.shared.hideForSpaceChange()
        merged.resetForSpaceChange(sessions: sessions)
        // A dwell started before the switch must not fire after the user has
        // left the Space; pending hovers and the approach target reset here.
        sessions.forEach { $0.cancelHoverReveal() }
        sessions.forEach { $0.cancelPendingSpaceReveal() }
        approachTargetID = nil
        sessions.forEach { $0.leaveStashIfFullScreened() }
        for session in sessions {
            if SpaceChangePolicy.shouldHideMarkerDuringSpaceTransition(
                presentation: session.presentation,
                isCollapsed: session.isCollapsed
            ) {
                session.hideMarkerForSpaceChange()
            } else if session.presentation == .systemMinimize, session.isCollapsed {
                session.refreshSeamSpaceAvailability()
                if let restoreFrame = session.restoreFrame {
                    session.showMarker(windowQuartz: restoreFrame)
                }
            }
        }
        // Space switching animates through transitional geometry; rebuild only
        // after the system settles, and only the latest switch wins.
        spaceRebuildGeneration += 1
        let generation = spaceRebuildGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + SpaceChangePolicy.rebuildDelay) { [weak self] in
            guard let self, self.spaceRebuildGeneration == generation else { return }
            self.sessions.forEach { $0.leaveStashIfFullScreened() }
            self.sessions.forEach { $0.refreshMarkerAfterSpaceChange() }
            self.merged.reconcile(sessions: self.sessions)
            self.reevaluateSeamApproach()
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appDidLaunch(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidActivate(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidUnhide(_:)), name: NSWorkspace.didUnhideApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidHide(_:)), name: NSWorkspace.didHideApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(spaceDidChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    private func observeMice() {
        StashEngineMouseRelay.shared.engine = self
        installSessionEventTap()
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.handleMouseDown()
        }
        localMouseDown = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseDown()
            return event
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouseUp()
        }
        localMouseUp = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp()
            return event
        }
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.reevaluateSeamApproach()
        }
        observeShowAllKeys()
    }

    private func observeShowAllKeys() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handleShowAllKey(event)
        }
        showAllKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
        }
        localShowAllKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return event
        }
    }

    private func handleShowAllKey(_ event: NSEvent) {
        guard isRunning else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard ShowAllWindowsKeyPolicy.matchesShowAll(
            keyCode: event.keyCode,
            control: flags.contains(.control),
            command: flags.contains(.command),
            option: flags.contains(.option)
        ) else {
            return
        }
        if ShowAllWindowsKeyPolicy.frontmostAppOnly(keyCode: event.keyCode) {
            guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
            applyShowAll(bundleIDs: [bundleID])
        } else {
            applyShowAll(bundleIDs: Array(Set(sessions.filter(\.isCollapsed).map(\.bundleID))))
        }
    }

    private func applyShowAll(bundleIDs: [String]) {
        for bundleID in bundleIDs {
            let group = sessions.filter { $0.bundleID == bundleID }
            let decision = StashActivationPolicy.decision(
                kind: .showAllWindows,
                hasOnDesktopWindow: group.contains(where: \.isOnDesktop),
                allStandardWindowsStashed: !group.isEmpty && group.allSatisfy(\.isManaged),
                allStashedDock: Preferences.shared.allStashedDockAction(for: bundleID)
            )
            applyActivation(decision, bundleID: bundleID, group: group)
        }
    }

    /// A seam beacon's own panel is only a few points wide and cannot reach
    /// past the seam, so collapsed seam stashes additionally own an approach
    /// band (see `SeamApproachPolicy`). Only a target change starts or cancels
    /// the hover dwell — re-arming on every mouse move would never let the
    /// dwell finish.
    private func reevaluateSeamApproach(rearm: Bool = false) {
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        let mouse = NSEvent.mouseLocation
        let pointer = CGPoint(
            x: mouse.x,
            y: StashGeometryPolicy.quartzOriginY(appKitY: mouse.y, height: 0, primaryHeight: primaryHeight)
        )
        let displays = DisplayCatalog.adjacencyGeometries(screens: screens)
        let segments = sessions.compactMap { session -> SeamApproachSegment? in
            guard session.isCollapsed,
                  !session.markerSuppressed,
                  session.presentation == .systemMinimize,
                  session.canBeginSeamReveal,
                  let edge = session.edge,
                  let frame = session.restoreFrame,
                  let displayID = session.displayID else {
                return nil
            }
            return SeamApproachSegment(
                id: session.mergeID,
                displayID: displayID,
                edge: edge,
                minY: frame.minY - StashGeometryPolicy.panelBleed,
                maxY: frame.maxY + StashGeometryPolicy.panelBleed
            )
        }
        for segment in segments where approachSuppressedIDs.contains(segment.id) {
            if !SeamApproachPolicy.contains(pointer: pointer, segment: segment, displays: displays) {
                approachSuppressedIDs.remove(segment.id)
            }
        }
        let candidates = segments.filter { !approachSuppressedIDs.contains($0.id) }
        let nextID = SeamApproachPolicy.target(pointer: pointer, segments: candidates, displays: displays)
        if nextID == approachTargetID {
            // A dwell that fired mid-drag aborts on the pressed button; after
            // mouse-up the same target re-arms. beginHoverReveal is idempotent
            // while a dwell is pending, so an ordinary move changes nothing.
            if rearm, let nextID, let session = sessions.first(where: { $0.mergeID == nextID }) {
                session.beginHoverReveal()
            }
            return
        }
        if let previous = approachTargetID,
           let session = sessions.first(where: { $0.mergeID == previous }) {
            session.cancelHoverReveal()
        }
        approachTargetID = nextID
        if let nextID, let session = sessions.first(where: { $0.mergeID == nextID }) {
            session.beginHoverReveal()
        }
    }

    private func installSessionEventTap() {
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, _ in
                if SessionEventTapPolicy.shouldReenableTap(type: type) {
                    StashEngineMouseRelay.shared.reenableEventTap()
                    return Unmanaged.passUnretained(event)
                }
                DispatchQueue.main.async {
                    if type == .leftMouseDown {
                        StashEngineMouseRelay.shared.engine?.handleMouseDown()
                    } else if type == .leftMouseUp {
                        StashEngineMouseRelay.shared.engine?.handleMouseUp()
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            return
        }
        eventTap = tap
        StashEngineMouseRelay.shared.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func shouldAcceptMouse(_ kind: SessionMouseRelayPolicy.Kind) -> Bool {
        let accepted = SessionMouseRelayPolicy.shouldAccept(
            kind: kind,
            buttonPressed: (NSEvent.pressedMouseButtons & 1) != 0,
            lastAccepted: lastAcceptedMouse
        )
        guard accepted else { return false }
        lastAcceptedMouse = kind
        return true
    }

    func handleMouseDown() {
        guard shouldAcceptMouse(.down) else { return }
        captureRetryGeneration += 1
        let mouse = NSEvent.mouseLocation
        StashDock.noteMouseDown(at: mouse)
        captureGesture = nil

        let primaryHeight = DisplayCatalog.primaryHeight(screens: NSScreen.screens)
        let mouseQuartz = CGPoint(
            x: mouse.x,
            y: StashGeometryPolicy.quartzOriginY(
                appKitY: mouse.y,
                height: 1,
                primaryHeight: primaryHeight
            )
        )
        guard let hit = StashSurface.frontmostWindow(atQuartz: mouseQuartz) else {
            return
        }
        let idle = sessions.filter(\.isIdle)
        let candidates = idle.map {
            StashSessionPolicy.CaptureHit(windowID: $0.windowID, pid: $0.pid)
        }
        guard let index = StashSessionPolicy.captureSessionIndex(
            hitWindowID: hit.windowID,
            hitPID: hit.pid,
            sessions: candidates
        ),
              let initialFrame = idle[index].captureGestureFrame else {
            return
        }
        let session = idle[index]
        session.resolveWindowID(fallback: hit.windowID)
        captureGesture = (session, initialFrame)
    }

    func handleMouseUp() {
        // Drags post dragged-events, not mouse-moves, so the band is stale at
        // mouse-up: cancel a dwell whose target the pointer left mid-drag, or
        // re-arm one that aborted on the pressed button while still inside.
        reevaluateSeamApproach(rearm: true)
        guard shouldAcceptMouse(.up) else { return }
        guard let captureGesture,
              sessions.contains(where: { $0 === captureGesture.session }) else {
            self.captureGesture = nil
            return
        }
        captureRetryGeneration += 1
        let generation = captureRetryGeneration
        attemptCapture(captureGesture, attempt: 0, generation: generation)
    }

    private func attemptCapture(
        _ gesture: (session: StashSession, initialFrame: CGRect),
        attempt: Int,
        generation: Int
    ) {
        guard generation == captureRetryGeneration,
              sessions.contains(where: { $0 === gesture.session }) else {
            return
        }
        if gesture.session.considerCapture(
            mouseAppKit: NSEvent.mouseLocation,
            initialFrame: gesture.initialFrame
        ) {
            captureGesture = nil
            lastPreferredSession[gesture.session.bundleID] = ObjectIdentifier(gesture.session)
            considerMultiWindowTip(for: gesture.session.bundleID)
            return
        }
        let delays = StashSessionPolicy.captureRecheckDelays()
        guard attempt < delays.count else {
            captureGesture = nil
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
            self?.attemptCapture(gesture, attempt: attempt + 1, generation: generation)
        }
    }

    @objc private func appDidLaunch(_ notification: Notification) {
        let launched = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let launched, let bundleID = launched.bundleIdentifier,
           Preferences.shared.stashActive(bundleID: bundleID) {
            discover(app: launched, bundleID: bundleID)
        }
        if SessionLifecyclePolicy.shouldRecoverOnSubjectLaunch(
            launchedBundleID: launched?.bundleIdentifier,
            pendingSubjectBundleIDs: Set(Preferences.shared.rescueDossiers.map(\.subject.bundleID))
        ) {
            StashRescue.recoverPending(reason: "app-launch", liveHolds: liveRescueHolds())
        }
    }

    private func liveRescueHolds() -> [SessionLifecyclePolicy.LiveRescueHold] {
        sessions.filter(\.isManaged).map {
            SessionLifecyclePolicy.LiveRescueHold(processID: $0.pid, windowNumber: $0.windowID)
        }
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else {
            return
        }
        if Preferences.shared.stashActive(bundleID: bundleID) {
            discover(app: app, bundleID: bundleID)
        }
        handleAppActivated(bundleID: bundleID)
    }

    @objc private func appDidHide(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else {
            return
        }
        hiddenBundles.insert(bundleID)
    }

    @objc private func appDidUnhide(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else {
            return
        }
        hiddenBundles.remove(bundleID)
        recentlyUnhidden.insert(bundleID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.recentlyUnhidden.remove(bundleID)
        }
    }

    private func syncSessions() {
        guard AccessibilityGrant.isTrusted(prompt: false) else {
            suspendTrustLost()
            return
        }
        let runningApps = NSWorkspace.shared.runningApplications
        let pids = Set(runningApps.map(\.processIdentifier))
        var doomed: [(StashSession, SessionLifecyclePolicy.Event)] = []
        for session in sessions {
            let stashActive = Preferences.shared.stashActive(bundleID: session.bundleID)
            let processStillRunning = pids.contains(session.pid)
            let roleInvalid: Bool
            if (stashActive || session.isTemporary), processStillRunning {
                roleInvalid = StashAX.roleAlive(session.windowElement) == .invalidUIElement
            } else {
                roleInvalid = false
            }
            if let event = SessionLifecyclePolicy.syncEndEvent(
                stashActive: stashActive,
                isTemporary: session.isTemporary,
                processStillRunning: processStillRunning,
                windowRoleInvalid: roleInvalid
            ) {
                doomed.append((session, event))
            }
        }
        endSessions(doomed)
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  app.activationPolicy == .regular,
                  Preferences.shared.stashActive(bundleID: bundleID) else {
                continue
            }
            discover(app: app, bundleID: bundleID)
        }
        pruneAppObservers(validPIDs: pids)
        merged.reconcile(sessions: sessions)
        reevaluateSeamApproach()
        Set(sessions.map(\.bundleID)).forEach { considerMultiWindowTip(for: $0) }
    }

    private func considerMultiWindowTip(for bundleID: String) {
        let collapsed = sessions.filter { $0.bundleID == bundleID && $0.isCollapsed }
        let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?
            .localizedName ?? bundleID
        StashMultiWindowTip.shared.consider(appName: name, collapsedCount: collapsed.count)
    }

    private func discover(app: NSRunningApplication, bundleID: String) {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        watchFocusedWindow(pid: pid, appElement: appElement)
        var windows = StashAX.windows(of: appElement)
        if let focused = StashAX.focusedWindow(of: appElement) {
            windows.append(focused)
        }
        for window in windows where StashAX.isStandardWindow(window) {
            if sessions.contains(where: { $0.sameWindow(as: window) }) { continue }
            let session = StashSession(
                appElement: appElement,
                windowElement: window,
                pid: pid,
                bundleID: bundleID
            )
            attach(session)
            sessions.append(session)
        }
    }

    /// `shutdown` may invoke `onEnded`, which writes `sessions`. Callers must
    /// not hold exclusive access to that array — in particular, do not end a
    /// session from inside `sessions.removeAll(where:)`.
    private func endSessions(_ doomed: [(StashSession, SessionLifecyclePolicy.Event)]) {
        for (session, event) in doomed {
            session.shutdown(event: event)
        }
    }

    private func attach(_ session: StashSession) {
        session.onEnded = { [weak self] ended, _ in
            self?.sessions.removeAll { $0 === ended }
            self?.approachSuppressedIDs.remove(ended.mergeID)
            if self?.temporarySession === ended {
                self?.temporarySession = nil
            }
            self?.merged.reconcile(sessions: self?.sessions ?? [])
            self?.reevaluateSeamApproach()
        }
        session.onChanged = { [weak self] changed in
            self?.merged.reconcile(sessions: self?.sessions ?? [])
            self?.reevaluateSeamApproach()
            if changed.isManaged {
                self?.recordLiveScreenSetPlacements()
            }
        }
        session.onCollapsed = { [weak self] collapsed in
            self?.approachSuppressedIDs.insert(collapsed.mergeID)
            self?.recordLiveScreenSetPlacements()
            self?.reevaluateSeamApproach()
        }
        session.onSeamMarkerActivity = { [weak self] _ in
            self?.reevaluateSeamApproach()
        }
        session.focusContext = { [weak self] in
            let collapsed = Set((self?.sessions ?? []).filter(\.isCollapsed).map(\.pid))
            return (NSApp.keyWindow != nil, collapsed)
        }
    }

    private func watchFocusedWindow(pid: pid_t, appElement: AXUIElement) {
        guard appObservers[pid] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, _ in
            var process: pid_t = 0
            AXUIElementGetPid(element, &process)
            DispatchQueue.main.async {
                StashEngineFocusRelay.shared.focused(pid: process)
            }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        guard AXObserverAddNotification(
            observer,
            appElement,
            kAXFocusedWindowChangedNotification as CFString,
            nil
        ) == .success else { return }
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        appObservers[pid] = (observer, source)
        StashEngineFocusRelay.shared.engine = self
    }

    func handleFocused(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier,
              Preferences.shared.stashActive(bundleID: bundleID) else {
            return
        }
        discover(app: app, bundleID: bundleID)
    }

    private func handleAppShortcut(_ bundleID: String) {
        discoverEnabledWindows(bundleID: bundleID)
        let group = sessions.filter { $0.bundleID == bundleID }
        if AppShortcutPolicy.shouldCaptureIdleFrontWindow(
            hasIdleWindow: group.contains(where: \.isIdle),
            hasManagedWindow: group.contains(where: \.isManaged)
        ), let idle = preferredIdle(in: group, bundleID: bundleID) {
            _ = idle.captureNearestAllowed()
            merged.reconcile(sessions: sessions)
            return
        }
        switch Preferences.shared.chordScope(for: bundleID) {
        case .allManagedWindows:
            let target = AppShortcutPolicy.targetExpanded(
                hasVisibleWindow: group.contains { $0.isExpanded },
                hasHiddenWindow: group.contains { $0.isCollapsed }
            )
            guard let target else { return }
            if target {
                group.filter(\.isCollapsed).forEach { $0.expandFromDock() }
            } else {
                group.filter(\.isExpanded).forEach { $0.toggleFromShortcut() }
            }
        case .recentWindow:
            preferred(in: group.filter(\.isManaged), bundleID: bundleID)?.toggleFromShortcut()
        }
    }

    private func handleTemporaryShortcut() {
        if let temporarySession, temporarySession.isManaged {
            temporarySession.toggleFromShortcut()
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
              TemporaryShortcutPolicy.canBegin(
                frontBundleID: front.bundleIdentifier,
                selfBundleID: Bundle.main.bundleIdentifier,
                isRegular: front.activationPolicy == .regular
              ),
              let bundleID = front.bundleIdentifier else {
            return
        }
        discover(app: front, bundleID: bundleID)
        let appElement = AXUIElementCreateApplication(front.processIdentifier)
        guard let focused = StashAX.focusedWindow(of: appElement) else { return }
        let session: StashSession
        if let existing = sessions.first(where: { $0.sameWindow(as: focused) }) {
            session = existing
        } else {
            let created = StashSession(
                appElement: appElement,
                windowElement: focused,
                pid: front.processIdentifier,
                bundleID: bundleID
            )
            attach(created)
            sessions.append(created)
            session = created
        }
        session.markTemporary()
        temporarySession = session
        if session.isIdle {
            _ = session.captureNearestAllowed()
        } else {
            session.toggleFromShortcut()
        }
        merged.reconcile(sessions: sessions)
    }

    private func discoverEnabledWindows(bundleID: String) {
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == bundleID {
            discover(app: app, bundleID: bundleID)
        }
    }

    private func preferredIdle(in group: [StashSession], bundleID: String) -> StashSession? {
        let idle = group.filter(\.isIdle)
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            let focused = StashAX.focusedWindow(of: AXUIElementCreateApplication(app.processIdentifier))
            if let focused, let match = idle.first(where: { $0.sameWindow(as: focused) }) {
                return match
            }
        }
        return idle.first
    }

    private func preferred(in group: [StashSession], bundleID: String) -> StashSession? {
        if let remembered = lastPreferredSession[bundleID],
           let match = group.first(where: { ObjectIdentifier($0) == remembered }) {
            return match
        }
        return group.first(where: \.isCollapsed) ?? group.first
    }

    private func pruneAppObservers(validPIDs: Set<pid_t>) {
        for (pid, info) in appObservers where !validPIDs.contains(pid) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), info.1, .defaultMode)
            appObservers.removeValue(forKey: pid)
        }
    }

    private func teardownObservers() {
        if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
        if let localMouseDown { NSEvent.removeMonitor(localMouseDown) }
        if let localMouseUp { NSEvent.removeMonitor(localMouseUp) }
        if let mouseMoveMonitor { NSEvent.removeMonitor(mouseMoveMonitor) }
        if let showAllKeyMonitor { NSEvent.removeMonitor(showAllKeyMonitor) }
        if let localShowAllKeyMonitor { NSEvent.removeMonitor(localShowAllKeyMonitor) }
        showAllKeyMonitor = nil
        localShowAllKeyMonitor = nil
        pendingThumbnailTitle = nil
        hiddenBundles.removeAll()
        recentlyUnhidden.removeAll()
        mouseMoveMonitor = nil
        approachTargetID = nil
        approachSuppressedIDs.removeAll()
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), eventTapSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        eventTapSource = nil
        StashEngineMouseRelay.shared.eventTap = nil
        mouseDownMonitor = nil
        mouseUpMonitor = nil
        localMouseDown = nil
        localMouseUp = nil
        captureGesture = nil
        lastAcceptedMouse = nil
        StashEngineMouseRelay.shared.engine = nil
        syncTimer?.invalidate()
        minimizeTimer?.invalidate()
        syncTimer = nil
        minimizeTimer = nil
        for info in appObservers.values {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), info.1, .defaultMode)
        }
        appObservers.removeAll()
        hotkeys.stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        screenSets.invalidate()
    }

    private func recordLiveScreenSetPlacements() {
        guard !ScreenSetCoordinator.blocksUserGeometry else { return }
        let present = Set(Preferences.shared.currentFingerprint().displayIDs)
        let slots = sessions.compactMap(\.screenSetSlot).filter { present.contains($0.displayID) }
        guard !slots.isEmpty else { return }
        Preferences.shared.rememberCurrentPlacement(slots: slots)
    }

    private func activationKind(for bundleID: String) -> AppActivationKind {
        guard StashDock.hasRecentClick() else {
            if recentlyUnhidden.contains(bundleID) || hiddenBundles.remove(bundleID) != nil {
                return .hideApp
            }
            return .commandTab
        }
        let clicked = StashDock.clickedBundleID()
        let windowTitle = StashDock.clickedWindowTitle()
        let inDock = StashDock.isDockPoint(NSEvent.mouseLocation)
        if let windowTitle, !windowTitle.isEmpty {
            StashDock.consumeRecentClick()
            pendingThumbnailTitle = windowTitle
            return .dockWindowThumbnail
        }
        if recentlyUnhidden.contains(bundleID) || hiddenBundles.remove(bundleID) != nil {
            StashDock.consumeRecentClick()
            return .hideApp
        }
        if clicked == bundleID {
            StashDock.consumeRecentClick()
            return .dockAppIcon
        }
        if clicked == nil, inDock {
            StashDock.consumeRecentClick()
            return .fileDropOrNotification
        }
        return .commandTab
    }

    private func applyActivation(
        _ decision: StashActivationDecision,
        bundleID: String,
        group: [StashSession]
    ) {
        switch decision {
        case .raiseOnDesktopOnly, .doNotOpenStash, .followSystem:
            return
        case .openMostRecent:
            let collapsed = group.filter(\.isCollapsed)
            guard let session = preferred(in: collapsed, bundleID: bundleID) else { return }
            session.expandFromDock()
            lastPreferredSession[bundleID] = ObjectIdentifier(session)
        case .openOnPointerDisplay:
            guard let displayID = pointerDisplayID() else { return }
            let matches = group.filter { $0.isCollapsed && $0.displayID == displayID }
            guard !matches.isEmpty else { return }
            matches.forEach { $0.expandFromDock() }
        case .openAllStashes:
            group.filter(\.isCollapsed).forEach { $0.expandFromDock() }
        case .openThumbnail:
            let title = pendingThumbnailTitle
            pendingThumbnailTitle = nil
            guard let title else { return }
            let match = group.first {
                $0.isCollapsed && StashAX.string($0.windowElement, kAXTitleAttribute as String) == title
            }
            match?.expandFromDock()
        }
    }

    private func pointerDisplayID() -> String? {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screen = screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return nil }
        return DisplayCatalog.identifier(for: screen, screens: screens)
    }
}

/// A rail, beacon, or shortcut reveal activates the subject app. That
/// activate must not run the Dock / Cmd-Tab all-stashed policy.
enum StashOwnedActivation {
    private static var latest: (bundleID: String, at: Date)?
    static let window: TimeInterval = 1.2

    static func note(bundleID: String) {
        latest = (bundleID, Date())
    }

    static func consume(_ bundleID: String, now: Date = Date()) -> Bool {
        guard let latest, latest.bundleID == bundleID,
              now.timeIntervalSince(latest.at) <= window else {
            return false
        }
        self.latest = nil
        return true
    }
}

/// AX observer callbacks cannot capture `self` without a stable hop.
private final class StashEngineMouseRelay {
    static let shared = StashEngineMouseRelay()
    weak var engine: StashEngine?
    var eventTap: CFMachPort?

    func reenableEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
}

private final class StashEngineFocusRelay {
    static let shared = StashEngineFocusRelay()
    weak var engine: StashEngine?
    func focused(pid: pid_t) {
        engine?.handleFocused(pid: pid)
    }
}
