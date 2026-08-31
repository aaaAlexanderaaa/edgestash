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

    /// Periodic sync classifies a live session without mutating the manager
    /// list. The engine must apply the event after it releases exclusive
    /// access to that list: `onEnded` also removes from it, and a nested
    /// exclusive write aborts the process.
    public static func syncEndEvent(
        stashActive: Bool,
        isTemporary: Bool,
        processStillRunning: Bool,
        windowRoleInvalid: Bool
    ) -> Event? {
        if !stashActive, !isTemporary {
            return .appDisabled
        }
        if !processStillRunning {
            return .appTerminated
        }
        if windowRoleInvalid {
            return .windowDestroyed
        }
        return nil
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

    /// Detach keeps the user's live frame but must undo the 2% hide, or
    /// a Mission Control drag leaves a ghost window that will not capture.
    public static func shouldRestoreAlpha(for event: Event) -> Bool {
        switch event {
        case .miniaturized, .appTerminated, .appDisabled, .appQuitting, .accessibilityLost, .detachedFromEdge:
            return true
        case .windowDestroyed:
            return false
        }
    }

    public static func shouldClearDisplayBinding(for event: Event) -> Bool {
        switch event {
        case .detachedFromEdge, .miniaturized:
            return true
        case .windowDestroyed, .appTerminated, .appDisabled, .appQuitting, .accessibilityLost:
            return false
        }
    }
}

public enum ManagedMinimizeNotification: Equatable {
    case miniaturized
    case deminiaturized
}

public enum ManagedMinimizeNotificationAction: Equatable {
    /// The notification describes an EdgeStash-owned transition, duplicates a
    /// transition already committed, or disagrees with the window's current AX
    /// value. It must not consume the managed session.
    case ignore
    /// The window is currently minimized outside EdgeStash's owned collapsed
    /// state. Preserve the existing product rule that an external minimize
    /// releases an expanded stash.
    case releaseSession
    /// The system (for example a Dock window thumbnail) has already restored a
    /// collapsed seam window. Adopt that result without a second migration.
    case adoptSystemReveal
    /// An expanded seam window was minimized. Minimize is the seam hide, so
    /// the session recollapses and keeps its beacon instead of going idle.
    case recollapse
}

/// AX notifications are asynchronous observations, not ordered transaction
/// completions. Classification therefore uses the window's current minimized
/// value plus the durable session state; a lone mutable ownership flag cannot
/// distinguish a delayed notification from a new external action.
public enum ManagedMinimizeNotificationPolicy {
    public static func action(
        for notification: ManagedMinimizeNotification,
        phase: StashSessionPhase,
        ownsCollapsedMinimize: Bool,
        revealInFlight: Bool,
        observedMinimized: Bool?,
        presentation: StashCollapsePresentation? = nil
    ) -> ManagedMinimizeNotificationAction {
        switch notification {
        case .miniaturized:
            // A miniaturized notification delivered after deminimization is
            // stale. An unreadable AX value is also insufficient evidence for
            // the destructive release path.
            guard observedMinimized == true else { return .ignore }
            // A collapsed or captured session is already parked. Clearing the
            // ownership bit during reveal, or AX lag that still reports
            // minimized, must not consume it.
            if phase == .collapsed || phase == .captured || revealInFlight {
                return .ignore
            }
            _ = ownsCollapsedMinimize
            // Minimize is the seam hide. An expanded seam window that
            // miniaturizes must recollapse, not go idle — otherwise the
            // 0.5s poll can false-expand, a delayed owned notification
            // looks "external", and the beacon vanishes after one appearance.
            if presentation == .systemMinimize {
                return .recollapse
            }
            return .releaseSession

        case .deminiaturized:
            guard observedMinimized == false else { return .ignore }
            guard phase == .collapsed,
                  ownsCollapsedMinimize,
                  !revealInFlight else {
                return .ignore
            }
            return .adoptSystemReveal
        }
    }
}

/// Two observers watch the same seam hide: the AX notification and a 0.5s
/// poll. The poll used to treat "AX says not minimized" as a Dock reveal
/// during settle, flip the session to expanded, and let the delayed
/// miniaturized notification release it. One policy now owns both.
public enum SeamSessionDurabilityPolicy {
    /// AX and WindowServer often lag the owned `setMinimized(true)` write.
    public static let ownedMinimizeSettle: TimeInterval = 1.5

    public static func shouldAdoptUnminimizedPoll(
        ownsCollapsedMinimize: Bool,
        elapsedSinceOwnedMinimize: TimeInterval,
        observedMinimized: Bool?
    ) -> Bool {
        guard ownsCollapsedMinimize, observedMinimized == false else { return false }
        return elapsedSinceOwnedMinimize >= ownedMinimizeSettle
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
