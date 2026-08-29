import AppKit
import EdgeStashLogic

/// Remembers the last non-stash front app and restores it after Dock/shortcut
/// collapse. Never hides EdgeStash while Settings is key.
enum StashFocusReturn {
    static func noteActivation(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        lastObservedPID = app.processIdentifier
    }

    static func remember(excluding sourcePID: pid_t) {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != sourcePID,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            rememberedPID = front.processIdentifier
            return
        }
        if let lastObservedPID, lastObservedPID != sourcePID {
            rememberedPID = lastObservedPID
            return
        }
        rememberedPID = nil
    }

    static func release(
        sourcePID: pid_t,
        settingsIsKey: Bool,
        collapsedManagedPIDs: Set<pid_t>
    ) {
        guard FocusReturnPolicy.shouldSchedule(settingsIsKey: settingsIsKey) else { return }
        let preferred = rememberedPID
        rememberedPID = nil
        if let preferred,
           activate(pid: preferred, sourcePID: sourcePID, collapsedManagedPIDs: collapsedManagedPIDs) {
            return
        }
        if activateFromWindowList(sourcePID: sourcePID, collapsedManagedPIDs: collapsedManagedPIDs) {
            return
        }
        _ = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first?
            .activate()
    }

    private static var lastObservedPID: pid_t?
    private static var rememberedPID: pid_t?

    private static func activate(
        pid: pid_t,
        sourcePID: pid_t,
        collapsedManagedPIDs: Set<pid_t>
    ) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        guard FocusReturnPolicy.isEligibleTarget(
            candidateBundleID: app.bundleIdentifier,
            selfBundleID: Bundle.main.bundleIdentifier,
            candidatePID: pid,
            sourcePID: sourcePID,
            candidateIsCollapsedManaged: collapsedManagedPIDs.contains(pid)
        ) else {
            return false
        }
        return app.activate()
    }

    private static func activateFromWindowList(
        sourcePID: pid_t,
        collapsedManagedPIDs: Set<pid_t>
    ) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let sourceIndex = list.firstIndex { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == sourcePID
        }
        let start = (sourceIndex ?? -1) + 1
        guard start < list.count else { return false }
        for info in list[start...] {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
            if activate(pid: pid, sourcePID: sourcePID, collapsedManagedPIDs: collapsedManagedPIDs) {
                return true
            }
        }
        return false
    }
}
