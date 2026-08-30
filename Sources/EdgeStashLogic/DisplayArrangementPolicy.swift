import CoreGraphics
import Foundation

public enum DisplayEdgePreviewKind: Equatable {
    case disabled
    case slideOffscreen
    case systemMinimize
}

public struct DisplayArrangementSlot: Equatable {
    public let id: String
    public let canvasFrame: CGRect

    public init(id: String, canvasFrame: CGRect) {
        self.id = id
        self.canvasFrame = canvasFrame
    }
}

public enum DisplayArrangementPolicy {
    public static func previewKind(
        at edge: DisplayEdge,
        of display: DisplayGeometry,
        in displays: [DisplayGeometry],
        selection: DisplayEdgeSelection
    ) -> DisplayEdgePreviewKind {
        guard selection.isEnabled(edge) else { return .disabled }
        // The map paints shared intervals on top of this base preview. A
        // partially shared edge therefore needs a slide base for its exposed
        // intervals; only a fully shared edge has one strategy end-to-end.
        let adjacency = DisplayEdgePolicy.adjacency(at: edge, of: display, in: displays)
        return adjacency == .fullyShared ? .systemMinimize : .slideOffscreen
    }

    public static func fittedSlots(
        displays: [DisplayGeometry],
        canvas: CGSize,
        padding: CGFloat = 12
    ) -> [DisplayArrangementSlot] {
        guard !displays.isEmpty,
              canvas.width > padding * 2,
              canvas.height > padding * 2 else {
            return []
        }

        let union = displays.reduce(CGRect.null) { $0.union($1.frame) }
        guard union.width > 0, union.height > 0 else { return [] }

        let available = CGSize(
            width: canvas.width - padding * 2,
            height: canvas.height - padding * 2
        )
        let scale = min(available.width / union.width, available.height / union.height)
        guard scale.isFinite, scale > 0 else { return [] }

        let drawn = CGSize(width: union.width * scale, height: union.height * scale)
        let origin = CGPoint(
            x: padding + (available.width - drawn.width) / 2,
            y: padding + (available.height - drawn.height) / 2
        )

        return displays.map { display in
            let frame = display.frame
            let canvasFrame = CGRect(
                x: origin.x + (frame.minX - union.minX) * scale,
                y: origin.y + (union.maxY - frame.maxY) * scale,
                width: frame.width * scale,
                height: frame.height * scale
            )
            return DisplayArrangementSlot(id: display.id, canvasFrame: canvasFrame)
        }
    }

    public static func canvasSegments(
        worldIntervals: [ClosedRange<CGFloat>],
        display: DisplayGeometry,
        slot: DisplayArrangementSlot,
        edge: DisplayEdge,
        thickness: CGFloat = 4
    ) -> [CGRect] {
        guard slot.canvasFrame.height > 0, display.frame.height > 0 else { return [] }
        let scale = slot.canvasFrame.height / display.frame.height
        return worldIntervals.compactMap { interval in
            let lower = max(interval.lowerBound, display.frame.minY)
            let upper = min(interval.upperBound, display.frame.maxY)
            guard upper > lower else { return nil }
            let height = (upper - lower) * scale
            let y = slot.canvasFrame.maxY - (upper - display.frame.minY) * scale
            let x = edge == .left
                ? slot.canvasFrame.minX
                : slot.canvasFrame.maxX - thickness
            return CGRect(x: x, y: y, width: thickness, height: height)
        }
    }
}
