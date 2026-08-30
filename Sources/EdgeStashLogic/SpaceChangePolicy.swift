import Foundation

public enum SeamSpaceAvailability: Equatable {
    /// The owning display currently shows an ordinary user Space. The id is
    /// the reveal destination resolved at the moment of interaction.
    case ready(spaceID: UInt64)
    /// Native full-screen and split-full-screen Spaces stay visible in the UI
    /// but are intentionally not migration destinations.
    case disabledFullScreen
    /// The version/runtime query contract is absent or returned an unknown
    /// state. Shared-seam behavior must fail closed.
    case unavailable
}

public enum SeamRevealPreparation: Equatable {
    /// The window already belongs to the owning display's current Space.
    case reveal
    /// Keep the window minimized, migrate, confirm membership, then reveal.
    case migrate(to: UInt64)
    /// No deminimize or activation is permitted.
    case refuse
}

public enum PendingSeamRevealCancellationAction: Equatable {
    /// There is no reveal transaction for the Space change to cancel.
    case none
    /// Invalidate the transaction and remove its busy gate. The window is
    /// either still minimized or the expansion has already committed.
    case clearTransaction
    /// The collapsed window was deminiaturized, but its expand commit has not
    /// landed. Restore the owned minimize before removing the busy gate.
    case restoreCollapsedMinimizeThenClear
}

/// Space switches animate through transitional window geometry, so markers
/// are dismissed immediately and rebuilt only after the system settles.
/// The 0.7s delay matches the reference product's proven value.
public enum SpaceChangePolicy {
    public static let rebuildDelay: TimeInterval = 0.7

    /// A minimized seam window still belongs to a Space, but its beacon is a
    /// display-anchored signal and therefore remains present on every Space.
    /// Its enabled/disabled interaction state is decided separately by
    /// `seamAvailability`. A slide-stashed window remains Space-anchored and
    /// shows its marker only beside the parked window.
    /// Slide markers sit on transitional window geometry and must hide during
    /// the Space animation. A collapsed seam beacon is display-anchored: hiding
    /// it for `rebuildDelay` is the "appeared once then gone" defect, including
    /// when minimize itself posts a Space change.
    public static func shouldHideMarkerDuringSpaceTransition(
        presentation: StashCollapsePresentation?,
        isCollapsed: Bool
    ) -> Bool {
        if presentation == .systemMinimize, isCollapsed {
            return false
        }
        return true
    }

    public static func shouldShowMarker(
        presentation: StashCollapsePresentation?,
        windowOnActiveSpace: Bool,
        isCollapsed: Bool = true
    ) -> Bool {
        switch presentation {
        case .systemMinimize:
            return isCollapsed || windowOnActiveSpace
        case .slideOffscreen:
            return windowOnActiveSpace
        case nil:
            return true
        }
    }

    /// SkyLight reports ordinary user Spaces as type 0 and native full-screen
    /// / split-full-screen Spaces as type 4 on the supported runtime. Unknown
    /// types fail closed rather than being guessed safe.
    public static func seamAvailability(
        transportAvailable: Bool,
        currentSpaceID: UInt64?,
        currentSpaceType: Int32?
    ) -> SeamSpaceAvailability {
        guard transportAvailable,
              let currentSpaceID,
              currentSpaceID != 0,
              let currentSpaceType else {
            return .unavailable
        }
        switch currentSpaceType {
        case 0:
            return .ready(spaceID: currentSpaceID)
        case 4:
            return .disabledFullScreen
        default:
            return .unavailable
        }
    }

    /// A blocked seam reveal is explained once per machine. Repeating the
    /// same panel on every click or failed hover is noise; the disabled
    /// beacon remains the standing signal.
    public static func shouldPresentSeamLimitationExplanation(alreadyAdvised: Bool) -> Bool {
        !alreadyAdvised
    }

    public static func shouldBeginSeamDwell(availability: SeamSpaceAvailability) -> Bool {
        if case .ready = availability { return true }
        return false
    }

    /// Membership must be readable before any reveal. A known same-Space
    /// window can reveal immediately; a known different-Space window must
    /// migrate and be confirmed first.
    public static func seamRevealPreparation(
        availability: SeamSpaceAvailability,
        membershipQuerySucceeded: Bool,
        windowOnTargetSpace: Bool
    ) -> SeamRevealPreparation {
        guard case let .ready(spaceID) = availability,
              membershipQuerySucceeded else {
            return .refuse
        }
        return windowOnTargetSpace ? .reveal : .migrate(to: spaceID)
    }

    /// Final commit gate immediately before deminimize/activation. Membership
    /// alone is insufficient: the owning display must still be showing the
    /// same destination Space that was resolved at interaction time.
    public static func mayCommitSeamReveal(
        targetSpaceID: UInt64,
        currentDisplaySpaceID: UInt64,
        membershipConfirmed: Bool
    ) -> Bool {
        targetSpaceID != 0
            && currentDisplaySpaceID == targetSpaceID
            && membershipConfirmed
    }

    /// A Space notification can arrive after AX deminimization succeeds but
    /// before the next-main-turn expand commit. Cancellation follows the live
    /// transaction, phase, and current AX state; it must not depend on the old
    /// minimize-ownership bit, which is necessarily false in that interval.
    public static func pendingSeamRevealCancellation(
        phase: StashSessionPhase,
        revealInFlight: Bool,
        observedMinimized: Bool?
    ) -> PendingSeamRevealCancellationAction {
        guard revealInFlight else { return .none }
        guard phase == .collapsed else { return .clearTransaction }
        guard observedMinimized == true else {
            // An unreadable value is not evidence that a collapsed window is
            // safely hidden. Re-applying minimize is idempotent and fail-closed.
            return .restoreCollapsedMinimizeThenClear
        }
        return .clearTransaction
    }
}
