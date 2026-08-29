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
    private var syncTimer: Timer?
    private var minimizeTimer: Timer?
    private let hotkeys = StashHotkeys()
    private let merged = StashMergeCoordinator()
    private var lastPreferredSession: [String: ObjectIdentifier] = [:]
    private var temporarySession: StashSession?
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        guard AccessibilityGrant.isTrusted(prompt: false) else { return }
        isRunning = true
        StashRescue.recoverPending(reason: "engine-start")
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
        for session in sessions {
            session.shutdown(event: .accessibilityLost)
        }
        merged.tearDown()
        teardownObservers()
        isRunning = false
    }

    func shutdown() {
        guard isRunning || !sessions.isEmpty else { return }
        for session in sessions {
            session.shutdown(event: .appQuitting)
        }
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
        guard isRunning, StashDock.hasRecentClick() else { return }
        let managed = sessions.filter { $0.bundleID == bundleID && $0.isManaged && !$0.isPinned }
        guard let session = preferred(in: managed, bundleID: bundleID) else { return }
        session.expandFromDock()
        lastPreferredSession[bundleID] = ObjectIdentifier(session)
    }

    @objc private func preferencesChanged() {
        guard isRunning else { return }
        hotkeys.reload()
        sessions.forEach { $0.detachIfTopologyChanged() }
        syncSessions()
    }

    @objc private func spaceDidChange() {
        guard isRunning else { return }
        merged.resetForSpaceChange(sessions: sessions)
        sessions.forEach { $0.refreshAfterSpaceChange() }
        merged.reconcile(sessions: sessions)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appDidLaunch(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidActivate(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(spaceDidChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    private func observeMice() {
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            StashDock.noteMouseDown(at: NSEvent.mouseLocation)
        }
        localMouseDown = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            StashDock.noteMouseDown(at: NSEvent.mouseLocation)
            return event
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.handleMouseUp()
        }
        localMouseUp = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp()
            return event
        }
    }

    private func handleMouseUp() {
        let mouse = NSEvent.mouseLocation
        for session in sessions where session.isIdle {
            if session.considerCapture(mouseAppKit: mouse) {
                lastPreferredSession[session.bundleID] = ObjectIdentifier(session)
                considerMultiWindowTip(for: session.bundleID)
            }
        }
    }

    @objc private func appDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              Preferences.shared.stashActive(bundleID: bundleID) else {
            return
        }
        discover(app: app, bundleID: bundleID)
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

    private func syncSessions() {
        guard AccessibilityGrant.isTrusted(prompt: false) else {
            suspendTrustLost()
            return
        }
        let runningApps = NSWorkspace.shared.runningApplications
        let pids = Set(runningApps.map(\.processIdentifier))
        sessions.removeAll { session in
            if !Preferences.shared.stashActive(bundleID: session.bundleID) && !session.isTemporary {
                session.shutdown(event: .appTerminated)
                return true
            }
            if !pids.contains(session.pid) {
                session.shutdown(event: .appTerminated)
                return true
            }
            let role = StashAX.roleAlive(session.windowElement)
            if role == .success { return false }
            if role == .invalidUIElement {
                session.shutdown(event: .windowDestroyed)
                return true
            }
            return false
        }
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

    private func attach(_ session: StashSession) {
        session.onEnded = { [weak self] ended, _ in
            self?.sessions.removeAll { $0 === ended }
            if self?.temporarySession === ended {
                self?.temporarySession = nil
            }
            self?.merged.reconcile(sessions: self?.sessions ?? [])
        }
        session.onChanged = { [weak self] _ in
            self?.merged.reconcile(sessions: self?.sessions ?? [])
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
        if group.contains(where: \.isIdle) && !group.contains(where: \.isManaged) {
            _ = group.first?.captureNearestAllowed()
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
        mouseDownMonitor = nil
        mouseUpMonitor = nil
        localMouseDown = nil
        localMouseUp = nil
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
    }
}

/// AX observer callbacks cannot capture `self` without a stable hop.
private final class StashEngineFocusRelay {
    static let shared = StashEngineFocusRelay()
    weak var engine: StashEngine?
    func focused(pid: pid_t) {
        engine?.handleFocused(pid: pid)
    }
}
