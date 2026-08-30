import CoreGraphics
import Foundation

/// One collapsed seam beacon's approach zone, in Quartz coordinates (y down),
/// vertically spanning the stashed window plus the marker panel bleed.
public struct SeamApproachSegment: Equatable {
    public let id: String
    public let displayID: String
    public let edge: DisplayEdge
    public let minY: CGFloat
    public let maxY: CGFloat

    public init(id: String, displayID: String, edge: DisplayEdge, minY: CGFloat, maxY: CGFloat) {
        self.id = id
        self.displayID = displayID
        self.edge = edge
        self.minY = minY
        self.maxY = maxY
    }
}

/// A pointer cannot be slammed into a seam the way a bezel stops it at a real
/// screen edge: a hard flick overshoots onto the neighbor display, so seam
/// approaches are gentle. A collapsed seam beacon therefore owns an approach
/// band instead of relying on the visible rail alone.
///
/// `bandWidth` matches the 28pt HIG small-control size already used for the
/// pin button — a comfortable target a gentle approach actually dwells in.
/// `overshoot` matches the merged strip's 12pt hit slop, so a pointer that
/// slips slightly past the seam still counts. The dwell itself stays with
/// `revealDelayMS`; the band only makes the dwell reachable.
public enum SeamApproachPolicy {
    public static let bandWidth: CGFloat = 28
    public static let overshoot: CGFloat = 12

    /// Whether the pointer sits inside one segment's band.
    public static func contains(
        pointer: CGPoint,
        segment: SeamApproachSegment,
        displays: [DisplayGeometry]
    ) -> Bool {
        guard let display = displays.first(where: { $0.id == segment.displayID }) else {
            return false
        }
        let seamX = segment.edge == .left ? display.frame.minX : display.frame.maxX
        let lower = segment.edge == .left ? seamX - overshoot : seamX - bandWidth
        let upper = segment.edge == .left ? seamX + bandWidth : seamX + overshoot
        return pointer.x >= lower && pointer.x <= upper
            && pointer.y >= segment.minY && pointer.y <= segment.maxY
    }

    /// The segment whose band holds the pointer, or nil. When bands on both
    /// sides of a seam match (one inside, one by overshoot), the segment whose
    /// owning display contains the pointer wins; remaining ties break on
    /// seam distance and then id, so the answer never flickers.
    public static func target(
        pointer: CGPoint,
        segments: [SeamApproachSegment],
        displays: [DisplayGeometry]
    ) -> String? {
        var best: (id: String, owns: Bool, seamDistance: CGFloat)?
        for segment in segments {
            guard contains(pointer: pointer, segment: segment, displays: displays),
                  let display = displays.first(where: { $0.id == segment.displayID }) else {
                continue
            }
            let seamX = segment.edge == .left ? display.frame.minX : display.frame.maxX
            let candidate = (
                id: segment.id,
                owns: display.frame.contains(pointer),
                seamDistance: abs(pointer.x - seamX)
            )
            if let current = best {
                if candidate.owns != current.owns {
                    if candidate.owns { best = candidate }
                    continue
                }
                if candidate.seamDistance != current.seamDistance {
                    if candidate.seamDistance < current.seamDistance { best = candidate }
                    continue
                }
                if candidate.id < current.id { best = candidate }
            } else {
                best = candidate
            }
        }
        return best?.id
    }
}
