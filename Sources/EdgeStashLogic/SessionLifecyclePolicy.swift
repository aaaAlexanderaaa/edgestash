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
}

public enum SessionLifecyclePolicy {
    public enum Event: Equatable {
        case windowDestroyed
        case appTerminated
        case appQuitting
        case accessibilityLost
        case miniaturized
        case detachedFromEdge
    }

    public static func shouldRemoveManagerSession(for event: Event) -> Bool {
        switch event {
        case .windowDestroyed, .appTerminated:
            return true
        case .appQuitting, .accessibilityLost, .miniaturized, .detachedFromEdge:
            return false
        }
    }

    public static func shouldClearRescueRecords(
        for event: Event,
        restorePositionSucceeded: Bool,
        restoreAlphaSucceeded: Bool = true,
        isFloating: Bool
    ) -> Bool {
        switch event {
        case .windowDestroyed, .appTerminated:
            return true
        case .accessibilityLost:
            return false
        case .appQuitting, .miniaturized:
            return (restorePositionSucceeded && restoreAlphaSucceeded) || isFloating
        case .detachedFromEdge:
            return true
        }
    }

    public static func shouldRestoreVisibility(for event: Event) -> Bool {
        switch event {
        case .miniaturized, .appTerminated, .appQuitting, .accessibilityLost:
            return true
        case .windowDestroyed, .detachedFromEdge:
            return false
        }
    }
}
