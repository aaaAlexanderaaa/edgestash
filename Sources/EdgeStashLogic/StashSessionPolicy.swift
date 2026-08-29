import CoreGraphics
import Foundation

public enum StashSessionPhase: Equatable {
    case idle
    case captured
    case collapsed
    case expanded
}

public enum StashSessionEvent: Equatable {
    case capture
    case collapse
    case expand
    case release
}

public enum StashCollapsePresentation: Equatable {
    case slideOffscreen
    case displayClippedSlideOffscreen
    case systemMinimize
}

/// AppKit-free stash session rules. The live engine (Task 5+) applies these
/// outcomes; this type does not talk to Accessibility or move windows.
public enum StashSessionPolicy {
    public static func phase(
        after event: StashSessionEvent,
        from current: StashSessionPhase
    ) -> StashSessionPhase? {
        switch (current, event) {
        case (.idle, .capture):
            return .captured
        case (.captured, .collapse), (.expanded, .collapse):
            return .collapsed
        case (.captured, .expand), (.collapsed, .expand):
            return .expanded
        case (.captured, .release), (.collapsed, .release), (.expanded, .release):
            return .idle
        default:
            return nil
        }
    }

    public static func snapSideAllows(edge: DisplayEdge, snapSide: String) -> Bool {
        switch snapSide {
        case "left":
            return edge == .left
        case "right":
            return edge == .right
        default:
            // "both", plus anything unrecognized, admits every edge.
            return true
        }
    }

    public static func canCapture(
        edge: DisplayEdge,
        snapSide: String,
        blockedDockSide: String?,
        edgeEnabled: Bool
    ) -> Bool {
        guard edgeEnabled else { return false }
        guard snapSideAllows(edge: edge, snapSide: snapSide) else { return false }
        if let blockedDockSide {
            switch (edge, blockedDockSide) {
            case (.left, "left"), (.right, "right"):
                return false
            default:
                break
            }
        }
        return true
    }

    /// Separate per-display Spaces let WindowServer clip a shared-edge window
    /// to its owning display. A shared desktop cannot provide that boundary,
    /// so the safe fallback remains system minimization.
    public static func collapsePresentation(
        at edge: DisplayEdge,
        of display: DisplayGeometry,
        windowFrame: CGRect?,
        in displays: [DisplayGeometry],
        screensHaveSeparateSpaces: Bool = false
    ) -> StashCollapsePresentation {
        let strategy: DisplayEdgeCollapseStrategy
        if let windowFrame {
            strategy = DisplayEdgePolicy.collapseStrategy(
                at: edge,
                of: display,
                windowFrame: windowFrame,
                in: displays,
                screensHaveSeparateSpaces: screensHaveSeparateSpaces
            )
        } else {
            strategy = DisplayEdgePolicy.collapseStrategy(
                at: edge,
                of: display,
                in: displays,
                screensHaveSeparateSpaces: screensHaveSeparateSpaces
            )
        }
        switch strategy {
        case .slideOffscreen:
            return .slideOffscreen
        case .displayClippedSlideOffscreen:
            return .displayClippedSlideOffscreen
        case .systemMinimize:
            return .systemMinimize
        }
    }

    /// Rearranging displays can flip a seam from slide-off to minimize (or
    /// drop the display). Restore the window instead of keeping a stale stash.
    public static func shouldReleaseAfterTopologyChange(
        current: StashCollapsePresentation?,
        next: StashCollapsePresentation?,
        displayStillPresent: Bool
    ) -> Bool {
        if !displayStillPresent { return true }
        guard let current, let next else { return true }
        return current != next
    }

    /// After a successful edge snap write, a failed minimize must put the
    /// window back. Session field rollback alone is not enough.
    public static func shouldRestorePriorFrame(
        didMoveToExpanded: Bool,
        minimizeSucceeded: Bool
    ) -> Bool {
        didMoveToExpanded && !minimizeSucceeded
    }

    /// An expanded window dragged off the stash edge is released. A pin
    /// keeps the session so leave-collapse still works after the window
    /// is put back.
    public static func shouldDetachAfterOffEdgeMove(
        isPinned: Bool,
        stillOnEdge: Bool
    ) -> Bool {
        !isPinned && !stillOnEdge
    }
}

public enum MultiWindowTipPolicy {
    public static func shouldPresent(
        collapsedCount: Int,
        suppressedPermanently: Bool,
        suppressedThisLaunch: Bool,
        alreadyVisible: Bool
    ) -> Bool {
        collapsedCount >= 2
            && !suppressedPermanently
            && !suppressedThisLaunch
            && !alreadyVisible
    }
}
