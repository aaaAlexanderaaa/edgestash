import CoreGraphics
import Foundation

public enum AppShortcutWindowScope: String, Codable, CaseIterable {
    case recentWindow
    case allManagedWindows
}

public enum AppShortcutPolicy {
    // NSEvent.ModifierFlags: shift, control, option, command. Transient flags
    // such as Caps Lock, Function and Numeric Pad must never become part of a
    // persisted shortcut chord.
    public static let supportedModifierMask: UInt =
        (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)

    public static func normalizedModifiers(_ rawValue: UInt) -> UInt {
        rawValue & supportedModifierMask
    }

    public static func resolvedScope(_ storedScope: AppShortcutWindowScope?) -> AppShortcutWindowScope {
        storedScope ?? .allManagedWindows
    }

    /// Returns the group target for an all-window shortcut. `true` means reveal all;
    /// `false` means collapse all; `nil` means there is no window to change.
    /// A regular floating window is visible, so it participates in the first
    /// shortcut press just like an expanded managed window.
    public static func targetExpanded(hasVisibleWindow: Bool, hasHiddenWindow: Bool) -> Bool? {
        if hasVisibleWindow {
            return false
        }
        if hasHiddenWindow {
            return true
        }
        return nil
    }

    /// An idle window can still be captured even when another window of the
    /// same app is already stashed. Otherwise a chord only toggles the old
    /// stash and the front window looks like the shortcut did nothing.
    public static func shouldCaptureIdleFrontWindow(
        hasIdleWindow: Bool,
        hasManagedWindow _: Bool
    ) -> Bool {
        hasIdleWindow
    }
}

public enum SessionLifecyclePolicy {
    public enum Event: Equatable {
        case windowDestroyed
        case appTerminated
        case appDisabled
        case appQuitting
        case accessibilityLost
        case miniaturized
        case detachedFromEdge
    }

    public static func shouldRemoveManagerSession(for event: Event) -> Bool {
        switch event {
        case .windowDestroyed, .appTerminated, .appDisabled, .accessibilityLost:
            return true
        case .appQuitting, .miniaturized, .detachedFromEdge:
            return false
        }
    }

    public static func shouldClearRescueRecords(
        for event: Event,
        restorePositionSucceeded: Bool,
        restoreAlphaSucceeded: Bool = true,
        restoreUnminimizeSucceeded: Bool = true,
        isFloating: Bool
    ) -> Bool {
        switch event {
        case .windowDestroyed, .appTerminated:
            return true
        case .accessibilityLost, .appDisabled, .appQuitting, .miniaturized:
            return (
                restorePositionSucceeded
                    && restoreAlphaSucceeded
                    && restoreUnminimizeSucceeded
            ) || isFloating
        case .detachedFromEdge:
            return true
        }
    }

    public static func shouldUninstallObservers(for event: Event) -> Bool {
        switch event {
        case .accessibilityLost, .windowDestroyed, .appTerminated, .appDisabled, .appQuitting:
            return true
        case .miniaturized, .detachedFromEdge:
            return false
        }
    }

    public struct LiveRescueHold: Equatable {
        public let processID: Int32
        public let windowNumber: UInt32?

        public init(processID: Int32, windowNumber: UInt32?) {
            self.processID = processID
            self.windowNumber = windowNumber
        }
    }

    /// Crash dossiers are retried when the recorded app itself comes back.
    /// Any other launch must not sweep live collapsed sessions.
    public static func shouldRecoverOnSubjectLaunch(
        launchedBundleID: String?,
        pendingSubjectBundleIDs: Set<String>
    ) -> Bool {
        guard let launchedBundleID, !launchedBundleID.isEmpty else { return false }
        return pendingSubjectBundleIDs.contains(launchedBundleID)
    }

    /// Live managed sessions already persist dossiers for crash rescue.
    /// Restoring those records would force the window on-screen while the
    /// session stays collapsed.
    public static func shouldRestoreRescueRecord(
        processID: Int32,
        windowNumber: UInt32,
        liveHolds: [LiveRescueHold]
    ) -> Bool {
        !liveHolds.contains { hold in
            guard hold.processID == processID else { return false }
            guard let heldWindow = hold.windowNumber else { return true }
            return heldWindow == windowNumber
        }
    }

    /// Preference writes and screen-parameter notifications share one signal.
    /// Live collapsed sessions already persist rescue dossiers, so a rescue
    /// pass here would restore those windows while the sessions stay collapsed.
    public static func shouldRecoverOnPreferenceChange() -> Bool {
        false
    }

    public static func shouldRestoreVisibility(for event: Event) -> Bool {
        switch event {
        case .miniaturized, .appTerminated, .appDisabled, .appQuitting, .accessibilityLost:
            return true
        case .windowDestroyed, .detachedFromEdge:
            return false
        }
    }
}

/// Listen-only session taps are disabled by macOS after a timeout or when
/// user input saturates the tap. The callback must re-enable or mouse
/// delivery through the tap stops until the engine restarts.
public enum SessionEventTapPolicy {
    public static func shouldReenableTap(type: CGEventType) -> Bool {
        type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
    }
}

/// The engine hears each click twice: a session tap hops onto the main
/// queue asynchronously, and NSEvent monitors fire immediately. A short
/// wall-clock window cannot identify a late tap hop after mouse-up.
public enum SessionMouseRelayPolicy {
    public enum Kind: Equatable {
        case down
        case up
    }

    public static func shouldAccept(
        kind: Kind,
        buttonPressed: Bool,
        lastAccepted: Kind?
    ) -> Bool {
        switch kind {
        case .down:
            guard buttonPressed else { return false }
            return lastAccepted != .down
        case .up:
            return lastAccepted == .down
        }
    }
}
