import CoreGraphics
import Foundation

public struct MergeMember: Equatable {
    public let id: String
    public let edge: DisplayEdge
    public let screenFrame: CGRect
    public let visibleMinY: CGFloat
    public let visibleMaxY: CGFloat
    public let windowHeight: CGFloat
    public let title: String

    public init(
        id: String,
        edge: DisplayEdge,
        screenFrame: CGRect,
        visibleMinY: CGFloat,
        visibleMaxY: CGFloat,
        windowHeight: CGFloat,
        title: String
    ) {
        self.id = id
        self.edge = edge
        self.screenFrame = screenFrame
        self.visibleMinY = visibleMinY
        self.visibleMaxY = visibleMaxY
        self.windowHeight = windowHeight
        self.title = title
    }
}

public struct MergeGroup: Equatable {
    public let edge: DisplayEdge
    public let screenFrame: CGRect
    public let members: [MergeMember]
}

public struct MergeSegmentLayout: Equatable {
    public let id: String
    public let slotRect: CGRect

    public init(id: String, slotRect: CGRect) {
        self.id = id
        self.slotRect = slotRect
    }
}

public struct MergeStripLayout: Equatable {
    public let panelFrame: CGRect
    /// Screen frame of the only region that may consume pointer events: the
    /// track plus hit slop. The label column lives on `panelFrame` and is
    /// paint-only.
    public let mouseOpaqueFrame: CGRect
    public let trackRect: CGRect
    public let hitRect: CGRect
    public let segments: [MergeSegmentLayout]
}

/// Window geometry after shifting panel-local rects so they match
/// `windowFrame`. Resting (no labels) uses `mouseOpaqueFrame`; hover labels
/// use the reserved `panelFrame`.
public struct MergeStripPresentation: Equatable {
    public let windowFrame: CGRect
    public let trackRect: CGRect
    public let hitRect: CGRect
    public let segments: [MergeSegmentLayout]

    public init(windowFrame: CGRect, trackRect: CGRect, hitRect: CGRect, segments: [MergeSegmentLayout]) {
        self.windowFrame = windowFrame
        self.trackRect = trackRect
        self.hitRect = hitRect
        self.segments = segments
    }
}

/// Overlapping markers on one edge of one logical display merge into one
/// strip. Geometry derives from platform metrics instead of bespoke pixels:
/// the track is 5pt wide to match the glass rail; hitPad keeps the target, the
/// panel overhangs the screen edge by 6pt so the track sits within two grid
/// units of the physical edge, the panel width keeps every label column
/// inside 384pt so it still reads as a strip, and the vertical bleed is one
/// 28pt title-bar height plus the track's own width per end.
///
/// `panelFrame` is only the label reservation. Pointer events belong to
/// `mouseOpaqueFrame` / `hitRect` (`trackInset + trackWidth + hitPad`). A
/// 240pt window that eats clicks is a defect, not the hit contract.
public enum MergeGroupPolicy {
    public static let trackWidth: CGFloat = 5
    public static let trackInset: CGFloat = 4
    public static let edgeOverhang: CGFloat = 6
    public static let minimumPanelWidth: CGFloat = 240
    public static let maximumPanelWidth: CGFloat = 384
    public static let labelGutter: CGFloat = 16
    public static let heightBleed: CGFloat = 38
    public static let hitPad: CGFloat = 12
    /// Width of the only mouse-consuming band. Labels sit past this and
    /// must not own a window.
    public static let mouseOpaqueWidth: CGFloat = trackInset + trackWidth + hitPad
    /// Comfortable hit-target span for one fused segment (HIG minimum for a
    /// row-like target). A strip is overloaded when its members no longer fit
    /// that target, so the warning follows the strip's own span instead of a
    /// fixed window count.
    public static let minimumSegmentSpan: CGFloat = 44
    /// Two markers fuse when they overlap by at least a quarter of the
    /// smaller one's height; a bare corner-touch does not merge.
    public static let fuseOverlapFraction: CGFloat = 0.25

    private struct ScreenKey: Hashable {
        let edge: Int
        let x: Int
        let y: Int
        let width: Int
        let height: Int

        init(edge: DisplayEdge, frame: CGRect) {
            self.edge = edge.rawValue
            self.x = Int(frame.minX.rounded())
            self.y = Int(frame.minY.rounded())
            self.width = Int(frame.width.rounded())
            self.height = Int(frame.height.rounded())
        }
    }

    public static func groups(from members: [MergeMember]) -> [MergeGroup] {
        let byScreen = Dictionary(grouping: members) { member in
            ScreenKey(edge: member.edge, frame: member.screenFrame)
        }
        var results: [MergeGroup] = []
        for cluster in byScreen.values {
            let sorted = cluster.sorted { lhs, rhs in
                if lhs.visibleMinY == rhs.visibleMinY {
                    return lhs.visibleMaxY < rhs.visibleMaxY
                }
                return lhs.visibleMinY < rhs.visibleMinY
            }
            var pending: [MergeMember] = []
            var pendingMinY: CGFloat = 0
            var pendingMaxY: CGFloat = 0
            for member in sorted {
                if pending.isEmpty {
                    pending = [member]
                    pendingMinY = member.visibleMinY
                    pendingMaxY = member.visibleMaxY
                    continue
                }
                let overlap = min(pendingMaxY, member.visibleMaxY) - max(pendingMinY, member.visibleMinY)
                let smallerSpan = min(
                    pendingMaxY - pendingMinY,
                    member.visibleMaxY - member.visibleMinY
                )
                let enoughOverlap = overlap >= smallerSpan * fuseOverlapFraction
                if enoughOverlap, smallerSpan > 0 {
                    pending.append(member)
                    pendingMinY = min(pendingMinY, member.visibleMinY)
                    pendingMaxY = max(pendingMaxY, member.visibleMaxY)
                } else {
                    appendGroup(pending, into: &results)
                    pending = [member]
                    pendingMinY = member.visibleMinY
                    pendingMaxY = member.visibleMaxY
                }
            }
            appendGroup(pending, into: &results)
        }
        return results
    }

    public static func suppressedIDs(in groups: [MergeGroup]) -> Set<String> {
        Set(groups.flatMap { $0.members.map(\.id) })
    }

    public static func shouldWarnOverload(_ groups: [MergeGroup]) -> Bool {
        groups.contains { group in
            let unionMinY = group.members.map(\.visibleMinY).min() ?? 0
            let unionMaxY = group.members.map(\.visibleMaxY).max() ?? 0
            let span = max(1, unionMaxY - unionMinY)
            return CGFloat(group.members.count) * minimumSegmentSpan > span
        }
    }

    /// Segments are height-weighted: each member's share of the track is
    /// proportional to its own window height (never smaller than one hit
    /// target), so a tall window owns a proportionally taller slice and the
    /// strip's geometry mirrors the windows it stands for.
    public static func layout(
        group: MergeGroup,
        labelWidths: [CGFloat]
    ) -> MergeStripLayout? {
        guard group.members.count >= 2 else { return nil }
        let members = group.members.sorted { lhs, rhs in
            let lhsMid = (lhs.visibleMinY + lhs.visibleMaxY) / 2
            let rhsMid = (rhs.visibleMinY + rhs.visibleMaxY) / 2
            if lhsMid == rhsMid { return lhs.visibleMinY < rhs.visibleMinY }
            return lhsMid < rhsMid
        }
        let screen = group.screenFrame
        let unionMinY = members.map(\.visibleMinY).min() ?? screen.minY
        let unionMaxY = members.map(\.visibleMaxY).max() ?? screen.maxY
        let unionHeight = max(1, unionMaxY - unionMinY)
        let tallestWindow = members.map(\.windowHeight).max() ?? unionHeight

        let widestLabel = labelWidths.max() ?? minimumSegmentSpan
        let labelColumn = max(minimumSegmentSpan * 0.75, widestLabel)
        let contentSpan = trackInset + trackWidth + labelGutter + labelColumn
        let panelWidth = min(max(ceil(contentSpan), minimumPanelWidth), min(maximumPanelWidth, screen.width))
        let panelHeight = min(screen.height, max(unionHeight, tallestWindow) + heightBleed)
        let midY = (unionMinY + unionMaxY) / 2
        let panelY = min(max(midY - panelHeight / 2, screen.minY), screen.maxY - panelHeight)
        let panelX = group.edge == .left
            ? screen.minX - edgeOverhang
            : screen.maxX - panelWidth + edgeOverhang
        let panelFrame = CGRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

        // The track hugs the screen-facing edge of the panel; the label
        // column sits toward the content side.
        let trackX = group.edge == .left
            ? trackInset
            : panelWidth - trackInset - trackWidth
        let trackRect = CGRect(x: trackX, y: unionMinY - panelY, width: trackWidth, height: unionHeight)

        let hitWidth = mouseOpaqueWidth
        let hitRect = CGRect(
            x: group.edge == .left ? 0 : panelWidth - hitWidth,
            y: max(0, trackRect.minY - hitPad),
            width: hitWidth,
            height: min(panelHeight, trackRect.height + hitPad * 2)
        )
        let mouseOpaque = mouseOpaqueFrame(panelFrame: panelFrame, hitRect: hitRect)

        let weights = members.map { max($0.windowHeight, minimumSegmentSpan) }
        let totalWeight = weights.reduce(0, +)
        var cursor = unionMinY
        let segments = zip(members, weights).map { member, weight in
            let slotHeight = unionHeight * weight / totalWeight
            let slot = CGRect(
                x: trackRect.minX,
                y: cursor - panelY,
                width: trackRect.width,
                height: slotHeight
            )
            cursor += slotHeight
            return MergeSegmentLayout(id: member.id, slotRect: slot)
        }
        return MergeStripLayout(
            panelFrame: panelFrame,
            mouseOpaqueFrame: mouseOpaque,
            trackRect: trackRect,
            hitRect: hitRect,
            segments: segments
        )
    }

    public static func mouseOpaqueFrame(panelFrame: CGRect, hitRect: CGRect) -> CGRect {
        CGRect(
            x: panelFrame.minX + hitRect.minX,
            y: panelFrame.minY + hitRect.minY,
            width: hitRect.width,
            height: hitRect.height
        )
    }

    public static func presentation(layout: MergeStripLayout, showingLabels: Bool) -> MergeStripPresentation {
        let windowFrame = showingLabels ? layout.panelFrame : layout.mouseOpaqueFrame
        let dx = layout.panelFrame.minX - windowFrame.minX
        let dy = layout.panelFrame.minY - windowFrame.minY
        return MergeStripPresentation(
            windowFrame: windowFrame,
            trackRect: layout.trackRect.offsetBy(dx: dx, dy: dy),
            hitRect: layout.hitRect.offsetBy(dx: dx, dy: dy),
            segments: layout.segments.map { segment in
                MergeSegmentLayout(id: segment.id, slotRect: segment.slotRect.offsetBy(dx: dx, dy: dy))
            }
        )
    }

    public static func hitSegment(
        at point: CGPoint,
        layout: MergeStripLayout
    ) -> String? {
        if let exact = layout.segments.first(where: { $0.slotRect.contains(point) }) {
            return exact.id
        }
        guard layout.hitRect.contains(point) else { return nil }
        return layout.segments.min { lhs, rhs in
            abs(lhs.slotRect.midY - point.y) < abs(rhs.slotRect.midY - point.y)
        }?.id
    }

    public static func activeAfterReconcile(
        expandedIDs: Set<String>,
        preferred: String?
    ) -> String? {
        if let preferred, expandedIDs.contains(preferred) {
            return preferred
        }
        return expandedIDs.sorted().first
    }

    private static func appendGroup(_ members: [MergeMember], into results: inout [MergeGroup]) {
        guard members.count >= 2, let first = members.first else { return }
        results.append(MergeGroup(edge: first.edge, screenFrame: first.screenFrame, members: members))
    }
}
