import Foundation
import CoreGraphics

public enum WindowOwnerObservation: Equatable {
    case owned, absent, differentProcess, unavailable
}

public enum WindowBindingDecision: Equatable {
    case rebind, wait, confirmedGone
}

/// A failed transport is not a dead window. Missing metadata alone is never
/// positive death evidence, including for minimized or off-Space windows.
public enum WindowRecoveryPolicy {
    public static func processConfirmedGone(exists: Bool?, terminated: Bool,
                                            bundleMatches: Bool?, launchMatches: Bool?) -> Bool {
        exists == false || terminated || bundleMatches == false || launchMatches == false
    }

    public static func bindingDecision(
        sameProcessLifetime: Bool,
        enumerationSucceeded: Bool,
        matchingReferences: Int,
        owner: WindowOwnerObservation,
        destructionNotified: Bool
    ) -> WindowBindingDecision {
        if owner == .differentProcess { return .confirmedGone }
        guard sameProcessLifetime else { return .wait }
        if matchingReferences == 1, owner == .owned { return .rebind }
        if destructionNotified, enumerationSucceeded,
           matchingReferences == 0, owner == .absent { return .confirmedGone }
        return .wait
    }

    public static func acceptsCallback(binding: UInt, currentBinding: UInt,
                                       lifecycle: Int, currentLifecycle: Int) -> Bool {
        binding == currentBinding && lifecycle == currentLifecycle
    }

    /// AX frame coordinates can round by a point (also the drag threshold).
    public static func framesMatch(_ actual: CGRect, _ expected: CGRect) -> Bool {
        abs(actual.minX - expected.minX) <= 1 && abs(actual.minY - expected.minY) <= 1
            && abs(actual.width - expected.width) <= 1 && abs(actual.height - expected.height) <= 1
    }

    public static func presentationMatches(
        phase: StashSessionPhase, presentation: StashCollapsePresentation,
        expectedFrame: CGRect, actualFrame: CGRect?, minimized: Bool?, alpha: Float?
    ) -> Bool {
        guard phase != .idle else { return false }
        if phase != .expanded, presentation == .systemMinimize { return minimized == true }
        guard minimized == false, let actualFrame, let alpha,
              framesMatch(actualFrame, expectedFrame) else { return false }
        return phase == .expanded ? alpha == 1 : alpha == 0
    }
}

/// In-process recovery intent, independent of a visible fallback's idle phase.
/// Never persisted across an EdgeStash launch or matched by title/geometry.
public struct ScreenSetRecoveryIntent: Equatable {
    public var placement: ScreenSetPlacement
    public var expanded: Bool
    public var pinned: Bool
    public var frame: CGRect?
    public var displayFrame: CGRect?

    public init(placement: ScreenSetPlacement, expanded: Bool = false, pinned: Bool = false,
                frame: CGRect? = nil, displayFrame: CGRect? = nil) {
        self.placement = placement
        self.expanded = expanded
        self.pinned = expanded && pinned
        self.frame = frame
        self.displayFrame = displayFrame
    }
}
