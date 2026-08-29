import CoreGraphics
import Foundation

/// What the live engine can measure about the Dock on one display. Both
/// fields are optional because neither is always observable: an autohidden
/// Dock reserves no space, and the window server may not expose the Dock's
/// on-screen extent. The policy degrades gracefully through each missing
/// field instead of modeling Dock internals.
public struct DockMeasurement: Equatable {
    /// Depth the visible Dock reserves on the owning side, measured as the
    /// gap between the display's full frame and its usable frame.
    public var depth: CGFloat?
    /// Extent of the Dock along the owning edge, measured from the window
    /// server, with the midpoint of that run along the same axis.
    public var extent: CGFloat?
    public var extentMidpoint: CGFloat?
    /// True when the Dock is parked behind the edge and only reveals on
    /// approach; the claimable corridor shrinks to a sliver.
    public var revealsOnApproach: Bool

    public init(
        depth: CGFloat? = nil,
        extent: CGFloat? = nil,
        extentMidpoint: CGFloat? = nil,
        revealsOnApproach: Bool = false
    ) {
        self.depth = depth
        self.extent = extent
        self.extentMidpoint = extentMidpoint
        self.revealsOnApproach = revealsOnApproach
    }
}

/// Dock click geometry. The hit rect is built only from measurements: the
/// depth comes from the space macOS already reserves, so it can never drift
/// from the real Dock, and the extent comes from the Dock's own window
/// whenever the window server reports it.
public enum DockHitPolicy {
    /// One 8pt layout grid doubled as guard so the corridor never reaches
    /// the opposite ends of the owning edge.
    public static let edgeGuard: CGFloat = 16
    /// A parked Dock reveals as the pointer reaches the edge; this sliver is
    /// the corridor the reveal gesture must cross.
    public static let parkedSliver: CGFloat = 12
    /// When no depth measurement is available and the Dock is visibly
    /// parked nowhere (unknown state), claim a quarter of the owning axis,
    /// capped so the corridor stays honest on tall or wide displays.
    public static func fallbackDepth(owningAxis: CGFloat) -> CGFloat {
        min(owningAxis / 4, 160)
    }

    public static func hitRect(
        screenFrame: CGRect,
        side: String,
        measurement: DockMeasurement
    ) -> CGRect? {
        let rail: Rail
        switch side {
        case "left": rail = .left
        case "right": rail = .right
        case "bottom": rail = .bottom
        default: return nil
        }

        let axis = rail.ownedAxis(of: screenFrame)
        let measuredDepth: CGFloat
        if let measured = measurement.depth {
            measuredDepth = measured
        } else {
            measuredDepth = measurement.revealsOnApproach
                ? parkedSliver
                : fallbackDepth(owningAxis: axis)
        }
        let depth = min(measuredDepth, axis - edgeGuard)
        guard depth > 0 else { return nil }

        let run: (start: CGFloat, length: CGFloat)
        if let extent = measurement.extent, extent > 0 {
            let mid = measurement.extentMidpoint ?? rail.ownedMidpoint(of: screenFrame)
            run = (mid - extent / 2, extent)
        } else {
            run = (
                rail.ownedOrigin(of: screenFrame) + edgeGuard,
                rail.ownedAxis(of: screenFrame) - edgeGuard * 2
            )
        }

        switch rail {
        case .left:
            return CGRect(
                x: screenFrame.minX,
                y: run.start,
                width: depth,
                height: run.length
            )
        case .right:
            return CGRect(
                x: screenFrame.maxX - depth,
                y: run.start,
                width: depth,
                height: run.length
            )
        case .bottom:
            return CGRect(
                x: run.start,
                y: screenFrame.minY,
                width: run.length,
                height: depth
            )
        }
    }
}

private extension DockHitPolicy {
    enum Rail {
        case bottom
        case left
        case right

        func ownedAxis(of frame: CGRect) -> CGFloat {
            self == .bottom ? frame.width : frame.height
        }

        func ownedOrigin(of frame: CGRect) -> CGFloat {
            self == .bottom ? frame.minX : frame.minY
        }

        func ownedMidpoint(of frame: CGRect) -> CGFloat {
            self == .bottom ? frame.midX : frame.midY
        }
    }
}
