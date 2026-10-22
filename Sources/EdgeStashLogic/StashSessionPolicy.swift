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
    case systemMinimize
}

public enum ManagedGeometryAction: Equatable {
    case none
    case detach
    case repairHidden
    case rebind(displayID: String, edge: DisplayEdge)
}

/// AppKit-free stash session rules. The live engine (Task 5+) applies these
/// outcomes; this type does not talk to Accessibility or move windows.
public enum StashSessionPolicy {
    /// AXMoved describes a physical change, not necessarily a user decision.
    /// Hidden windows moved by the system retain membership. Visible user
    /// drags may leave stash or change sides; a system move to another display
    /// retains the original side even if the system centers its initial frame.
    public static func externalGeometryAction(
        phase: StashSessionPhase, presentation: StashCollapsePresentation?,
        frame: CGRect, displayID: String, edge: DisplayEdge,
        displays: [DisplayGeometry], wasDragged: Bool,
        isBusy: Bool = false, screenSetQuiet: Bool = false, recovering: Bool = false
    ) -> ManagedGeometryAction {
        guard !isBusy, !screenSetQuiet else { return .none }
        guard let source = displays.first(where: { $0.id == displayID }) else { return .none }
        if recovering, !wasDragged, phase == .expanded { return .repairHidden }
        func alignedSide(on display: DisplayGeometry) -> DisplayEdge? {
            ([edge] + DisplayEdge.allCases.filter { $0 != edge }).first {
                abs($0 == .left ? frame.minX - display.frame.minX : frame.maxX - display.frame.maxX) <= 20
            }
        }
        if phase == .collapsed, let presentation {
            // A hidden frame may overlap its old neighbor almost entirely;
            // the narrow lip identifies the display it is actually parked on.
            let parkedDestination = displays.first {
                $0.id != displayID && frame.intersection($0.frame).width > 0
                    && StashGeometryPolicy.parkedEdge(of: frame, in: $0.frame) != nil
            }
            let destination = parkedDestination
                ?? StashGeometryPolicy.owningDisplay(for: frame, in: displays, preferredID: displayID)
            if let destination, destination.id != displayID {
                if !wasDragged { return .rebind(displayID: destination.id, edge: edge) }
                if let side = StashGeometryPolicy.parkedEdge(of: frame, in: destination.frame)
                    ?? alignedSide(on: destination) {
                    return .rebind(displayID: destination.id, edge: side)
                }
                return .detach
            }
            if wasDragged, let side = alignedSide(on: source) {
                return side == edge && StashGeometryPolicy.isStillOnStashEdge(
                    frame: frame, display: source.frame, edge: edge, presentation: presentation
                ) ? .none : .rebind(displayID: displayID, edge: side)
            }
            if StashGeometryPolicy.isStillOnStashEdge(frame: frame, display: source.frame, edge: edge, presentation: presentation) {
                return .none
            }
            return wasDragged ? .detach : .repairHidden
        }
        guard phase == .expanded,
              let destination = StashGeometryPolicy.owningDisplay(for: frame, in: displays) else { return .none }
        if let side = alignedSide(on: destination) {
            return destination.id == displayID && side == edge ? .none : .rebind(displayID: destination.id, edge: side)
        }
        if destination.id != displayID, !wasDragged {
            return .rebind(displayID: destination.id, edge: edge)
        }
        return .detach
    }

    /// Edge capture belongs to the window that was under the pointer when the
    /// gesture began, and only after that window actually moved. AX positions
    /// can round by a fraction of a point, so a one-point threshold filters a
    /// click without making deliberate short drags feel unresponsive.
    public static func isWindowDrag(
        from initialFrame: CGRect,
        to currentFrame: CGRect,
        minimumTranslation: CGFloat = 1
    ) -> Bool {
        abs(currentFrame.minX - initialFrame.minX) >= minimumTranslation
            || abs(currentFrame.minY - initialFrame.minY) >= minimumTranslation
    }

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

    /// Shared segments always minimize (see `DisplayEdgePolicy`); exposed
    /// segments slide offscreen.
    public static func collapsePresentation(
        at edge: DisplayEdge,
        of display: DisplayGeometry,
        windowFrame: CGRect?,
        in displays: [DisplayGeometry]
    ) -> StashCollapsePresentation {
        let strategy: DisplayEdgeCollapseStrategy
        if let windowFrame {
            strategy = DisplayEdgePolicy.collapseStrategy(
                at: edge,
                of: display,
                windowFrame: windowFrame,
                in: displays
            )
        } else {
            strategy = DisplayEdgePolicy.collapseStrategy(
                at: edge,
                of: display,
                in: displays
            )
        }
        switch strategy {
        case .slideOffscreen:
            return .slideOffscreen
        case .systemMinimize:
            return .systemMinimize
        }
    }

    /// Collapse binds an edge to the capture display. Prefer that display
    /// over whichever screen currently owns the most pixels — a seam-spanning
    /// frame would otherwise flip the presentation to the neighbor.
    public static func displayForCollapse(
        sessionDisplayID: String?,
        intersectionDisplayID: String?,
        displays: [DisplayGeometry]
    ) -> DisplayGeometry? {
        if let sessionDisplayID, let match = displays.first(where: { $0.id == sessionDisplayID }) {
            return match
        }
        if let intersectionDisplayID, let match = displays.first(where: { $0.id == intersectionDisplayID }) {
            return match
        }
        return nil
    }

    public static func captureRecheckDelays() -> [TimeInterval] {
        [0.05, 0.12, 0.22]
    }

    public struct CaptureHit: Equatable {
        public let windowID: UInt32?
        public let pid: Int32

        public init(windowID: UInt32?, pid: Int32) {
            self.windowID = windowID
            self.pid = pid
        }
    }

    /// Exact window numbers win. A session that never learned its number may
    /// still match when it is the only idle session for that process.
    public static func captureSessionIndex(
        hitWindowID: UInt32,
        hitPID: Int32,
        sessions: [CaptureHit]
    ) -> Int? {
        if let exact = sessions.firstIndex(where: {
            $0.pid == hitPID && $0.windowID == hitWindowID
        }) {
            return exact
        }
        let nilIDIndexes = sessions.indices.filter {
            sessions[$0].pid == hitPID && sessions[$0].windowID == nil
        }
        guard nilIDIndexes.count == 1 else { return nil }
        return nilIDIndexes[0]
    }

    /// After a successful edge snap write, a failed minimize must put the
    /// window back. Session field rollback alone is not enough.
    public static func shouldRestorePriorFrame(
        didMoveToExpanded: Bool,
        minimizeSucceeded: Bool
    ) -> Bool {
        didMoveToExpanded && !minimizeSucceeded
    }

}
