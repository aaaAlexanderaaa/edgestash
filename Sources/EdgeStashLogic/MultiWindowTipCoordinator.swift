import Foundation

/// AppKit-free state machine for the "this app has several windows stashed"
/// advice. The live `StashMultiWindowTip` owns only presentation; every
/// decision about *whether* to present, hide, or fall silent lives here so the
/// behavior grammar (`docs/contracts/behavior-grammar.md`, effect
/// `multi_window_tip`) can be verified without macOS.
///
/// Declared cardinality: at most one present per launch. The advice is shown
/// once while an app holds two or more collapsed stashes; after that it stays
/// quiet until the next launch (or a permanent mute). Transient hides — a Space
/// change, or the collapsed count dipping below two and returning — must not
/// re-present, because the repeating `syncSessions` tick would otherwise re-fire
/// the banner every few seconds.
public struct MultiWindowTipCoordinator {
    /// How a shown tip ended.
    public enum Dismissal: Equatable {
        case remindLater
        case neverAgain
        case timedOut
    }

    /// What the live layer should do in response to an event.
    public enum Action: Equatable {
        case none
        case present
        case hide
        /// Hide and persist the permanent mute preference.
        case hideAndMutePermanently
    }

    /// Whether re-entering the "two or more collapsed" condition after the tip
    /// has already been shown once should present the advice again within the
    /// same launch. Product decision: `false` (advice is once-per-launch). Flip
    /// this single knob, and update the grammar, to make genuine re-entry
    /// re-notify.
    public static let renotifyOnReentryWithinLaunch = false

    private var visible = false
    private var quietUntilRelaunch = false

    public init() {}

    /// Whether a tip is currently on screen (drives `alreadyVisible` guards and
    /// tests).
    public var isPresenting: Bool { visible }

    /// A periodic `syncSessions` tick or a post-capture check. `collapsedCount`
    /// is the number of collapsed stashes for one app; `suppressedPermanently`
    /// mirrors `Preferences.mutedMultiWindowAdvice`.
    public mutating func onSync(collapsedCount: Int, suppressedPermanently: Bool) -> Action {
        if collapsedCount < 2 {
            return hideIfVisible()
        }
        guard !suppressedPermanently, !quietUntilRelaunch, !visible else {
            return .none
        }
        visible = true
        // The fix: fall silent for the rest of the launch at *present* time, not
        // only when the user dismisses or the countdown ends. This is what makes
        // the cardinality provably one-per-launch.
        quietUntilRelaunch = !Self.renotifyOnReentryWithinLaunch
        return .present
    }

    /// The active Space changed. The panel is anchored to the main screen, so it
    /// is hidden, but the launch stays quiet — a Space switch is not a reason to
    /// re-advise.
    public mutating func onSpaceChange() -> Action {
        hideIfVisible()
    }

    /// The user acted on the tip, or its countdown elapsed.
    public mutating func onDismiss(_ dismissal: Dismissal) -> Action {
        visible = false
        switch dismissal {
        case .neverAgain:
            quietUntilRelaunch = true
            return .hideAndMutePermanently
        case .remindLater, .timedOut:
            quietUntilRelaunch = true
            return .hide
        }
    }

    /// Engine (re)start. Clears the per-launch quiet; the permanent mute lives in
    /// preferences and is re-supplied through `onSync`.
    public mutating func onRelaunch() -> Action {
        quietUntilRelaunch = false
        return hideIfVisible()
    }

    private mutating func hideIfVisible() -> Action {
        guard visible else { return .none }
        visible = false
        return .hide
    }
}
