import Foundation
import CoreGraphics

public enum WindowOwnerObservation: Equatable {
    case owned, absent, differentProcess, unavailable
}

public enum WindowBindingDecision: Equatable {
    case rebind, wait, confirmedGone
}

/// Acknowledged asynchronous writes can precede AX/WindowServer readback.
/// Uses the existing owned-minimize settle bound and the engine's 0.5s poll.
/// Waiting never authorizes a successful presentation or clears rescue debt.
public struct WindowWriteConfirmation {
    public enum Result: Equatable { case waiting, confirmed, expired }
    public let startedAt: TimeInterval
    public init(now: TimeInterval) { startedAt = now }
    public func hasSettled(now: TimeInterval) -> Bool {
        now - startedAt >= SeamSessionDurabilityPolicy.ownedMinimizeSettle
    }
    public func observe(matches: Bool, now: TimeInterval) -> Result {
        if matches { return .confirmed }
        return hasSettled(now: now) ? .expired : .waiting
    }
}

/// A failed transport is not a dead window. Missing metadata alone is never
/// positive death evidence, including for minimized or off-Space windows.
public enum WindowRecoveryPolicy {
    public static func requiresSpacePreparation(expanded: Bool, minimized: Bool,
        previous: StashCollapsePresentation?, next: StashCollapsePresentation,
        ownsMinimize: Bool) -> Bool {
        minimized && (expanded || next == .slideOffscreen)
            && (previous == .systemMinimize || ownsMinimize || next == .systemMinimize)
    }

    /// Route A lazy conversion: when a topology change exposes a formerly
    /// shared edge, keep an already-minimized collapsed stash minimized rather
    /// than forcing an online deminimize-and-re-park transition during hotplug.
    /// It converts naturally to the exposed-edge strategy on its next reveal.
    public static func effectiveCollapsedPresentation(
        computed: StashCollapsePresentation,
        expanded: Bool,
        currentlyMinimized: Bool,
        ownsMinimize: Bool
    ) -> StashCollapsePresentation {
        if !expanded, computed == .slideOffscreen, currentlyMinimized, ownsMinimize {
            return .systemMinimize
        }
        return computed
    }

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
        isUsableFrame(actual) && isUsableFrame(expected)
            && abs(actual.minX - expected.minX) <= 1 && abs(actual.minY - expected.minY) <= 1
            && abs(actual.width - expected.width) <= 1 && abs(actual.height - expected.height) <= 1
    }

    public static func isUsableFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.size.width.isFinite && frame.size.height.isFinite
            && frame.size.width > 0 && frame.size.height > 0
    }

    /// Semantic acceptance for an expanded stash frame: tolerates menu-bar or
    /// Dock clamping, character-cell size increments (Terminal/Emacs), and
    /// application minimum sizes while still rejecting windows stuck on another
    /// display or far from the target edge.
    public static func expandedFrameMatches(
        _ actual: CGRect,
        expected: CGRect,
        on display: CGRect,
        edge: DisplayEdge
    ) -> Bool {
        if framesMatch(actual, expected) { return true }
        guard isUsableFrame(actual), isUsableFrame(expected) else { return false }
        let overlap = actual.intersection(display)
        guard !overlap.isNull,
              overlap.width >= min(actual.width, display.width) * 0.5,
              overlap.height >= min(actual.height, display.height) * 0.5 else {
            return false
        }
        let edgeAligned: Bool
        switch edge {
        case .left:
            edgeAligned = abs(actual.minX - expected.minX) <= 24
        case .right:
            edgeAligned = abs(actual.maxX - expected.maxX) <= 24
        }
        guard edgeAligned else { return false }
        // Menu bars (up to ~44pt on notched displays) and character-cell grids
        // may shift Y slightly without indicating a failed move.
        return abs(actual.minY - expected.minY) <= 56
    }

    /// Width of the horizontal overlap between a parked window and its owning
    /// display. Zero indicates full off-screen occlusion.
    public static func visibleOverlapWidth(of frame: CGRect, on display: CGRect) -> CGFloat {
        let overlap = frame.intersection(display)
        guard !overlap.isNull, overlap.width.isFinite, overlap.height.isFinite, overlap.height > 0 else {
            return 0
        }
        return max(0, overlap.width)
    }

    public static func presentationMatches(
        phase: StashSessionPhase, presentation: StashCollapsePresentation,
        expectedFrame: CGRect, actualFrame: CGRect?, minimized: Bool?, alpha: Float?,
        displayFrame: CGRect? = nil, edge: DisplayEdge? = nil,
        requiresZeroAlphaReadback: Bool = true
    ) -> Bool {
        guard phase != .idle else { return false }
        if phase != .expanded, presentation == .systemMinimize { return minimized == true }
        guard minimized == false, let actualFrame else { return false }
        if phase == .expanded {
            guard let alpha, alpha >= 0.99 else { return false }
            if let displayFrame, let edge {
                return expandedFrameMatches(actualFrame, expected: expectedFrame, on: displayFrame, edge: edge)
            }
            return framesMatch(actualFrame, expectedFrame)
        }
        // Collapsed exposed-edge slide:
        if let displayFrame, let edge {
            let parked = framesMatch(actualFrame, expectedFrame)
                || StashGeometryPolicy.parkedEdge(of: actualFrame, in: displayFrame) == edge
            guard parked else { return false }
            let overlapWidth = visibleOverlapWidth(of: actualFrame, on: displayFrame)
            // Fully off-screen parking contributes zero pixels and lets macOS
            // occlude the window without relying on cross-process alpha readback.
            if overlapWidth <= 0.5 { return true }
            if !requiresZeroAlphaReadback { return true }
            return alpha == 0
        }
        guard let alpha, framesMatch(actualFrame, expectedFrame) else { return false }
        return alpha == 0
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
    public var preferredSize: CGSize?
    public var relativeY: CGFloat?

    public init(placement: ScreenSetPlacement, expanded: Bool = false, pinned: Bool = false,
                frame: CGRect? = nil, displayFrame: CGRect? = nil,
                preferredSize: CGSize? = nil, relativeY: CGFloat? = nil) {
        self.placement = placement
        self.expanded = expanded
        self.pinned = expanded && pinned
        self.frame = frame
        self.displayFrame = displayFrame
        self.preferredSize = preferredSize ?? placement.preferredSize
        self.relativeY = relativeY ?? placement.relativeY
    }
}
