import Foundation

/// Carbon modifier bits from Carbon Events.h. Kept numeric so logic tests stay
/// AppKit-free. `RegisterEventHotKey` needs these, not NSEvent bits.
public enum CarbonHotkeyPolicy {
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    public static func shouldExcludeFromEventMonitor(carbonHandlerInstalled: Bool) -> Bool {
        carbonHandlerInstalled
    }

    public static func carbonModifiers(fromNSEvent modifiers: UInt) -> UInt32 {
        let normalized = AppShortcutPolicy.normalizedModifiers(modifiers)
        var result: UInt32 = 0
        if normalized & (1 << 20) != 0 { result |= command }
        if normalized & (1 << 19) != 0 { result |= option }
        if normalized & (1 << 18) != 0 { result |= control }
        if normalized & (1 << 17) != 0 { result |= shift }
        return result
    }
}

/// Temporary shortcut is a one-shot stash of the front regular window. That
/// window may belong to an app that is not on the enabled list — that is the
/// point of the temporary chord. After the session returns to idle, keep it
/// only if the app is now a configured stash target.
public enum TemporaryShortcutPolicy {
    public static func canBegin(
        frontBundleID: String?,
        selfBundleID: String?,
        isRegular: Bool
    ) -> Bool {
        guard isRegular, let frontBundleID, !frontBundleID.isEmpty else { return false }
        if let selfBundleID, frontBundleID == selfBundleID { return false }
        return true
    }

    public static func shouldKeepAfterIdle(stashActive: Bool) -> Bool {
        stashActive
    }
}

/// After a Dock or shortcut reveal, return focus to the previous app instead of
/// hiding EdgeStash (which would also hide Settings if it is key).
public enum FocusReturnPolicy {
    public static func shouldSchedule(settingsIsKey: Bool) -> Bool {
        !settingsIsKey
    }

    /// Dock / shortcut reveal may return focus. A user unminimize or hover
    /// reveal must leave the window frontmost.
    public static func shouldReleaseAfterExpand(fromDock: Bool) -> Bool {
        fromDock
    }

    /// Pointer-leave collapse may return focus only after the window
    /// actually collapsed. A failed collapse must keep the stash frontmost.
    public static func shouldReleaseAfterLeaveCollapse(
        didCollapse: Bool,
        slideFinished: Bool = false
    ) -> Bool {
        didCollapse && slideFinished
    }

    public static func isEligibleTarget(
        candidateBundleID: String?,
        selfBundleID: String?,
        candidatePID: Int32,
        sourcePID: Int32,
        candidateIsCollapsedManaged: Bool
    ) -> Bool {
        if candidatePID == sourcePID { return false }
        if let candidateBundleID, let selfBundleID, candidateBundleID == selfBundleID {
            return false
        }
        if candidateBundleID == "com.apple.dock" { return false }
        if candidateIsCollapsedManaged { return false }
        return true
    }
}
