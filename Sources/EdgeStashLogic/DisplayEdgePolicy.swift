import CoreGraphics
import Foundation

public enum DisplayEdge: Int, Codable, CaseIterable {
    case left = 1
    case right = 2
}

public struct DisplayEdgeSelection: Codable, Equatable {
    public var leftEnabled: Bool
    public var rightEnabled: Bool

    public init(leftEnabled: Bool, rightEnabled: Bool) {
        self.leftEnabled = leftEnabled
        self.rightEnabled = rightEnabled
    }

    public func isEnabled(_ edge: DisplayEdge) -> Bool {
        switch edge {
        case .left:
            return leftEnabled
        case .right:
            return rightEnabled
        }
    }

    public mutating func setEnabled(_ enabled: Bool, for edge: DisplayEdge) {
        switch edge {
        case .left:
            leftEnabled = enabled
        case .right:
            rightEnabled = enabled
        }
    }
}

public struct DisplayGeometry: Equatable {
    public let id: String
    public let frame: CGRect

    public init(id: String, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

public enum DisplayEdgeCollapseStrategy: Equatable {
    case slideOffscreen
    case displayClippedSlideOffscreen
    case systemMinimize
}

public enum DisplayEdgeAdjacency: Equatable {
    case outer
    case partiallyShared
    case fullyShared
}

public enum DisplayEdgePolicy {
    /// Two displays count as touching when the gap between their frames is
/// under four points — half a layout-grid unit — enough to absorb the
/// rounding differences between reported display frames.
    public static let adjacencyTolerance: CGFloat = 4

    public static func hasAdjacentDisplay(
        at edge: DisplayEdge,
        of display: DisplayGeometry,
        in displays: [DisplayGeometry],
        tolerance: CGFloat = adjacencyTolerance
    ) -> Bool {
        adjacency(at: edge, of: display, in: displays, tolerance: tolerance) != .outer
    }

    public static func sharedIntervals(
        at edge: DisplayEdge,
        of display: DisplayGeometry,
        in displays: [DisplayGeometry],
        tolerance: CGFloat = adjacencyTolerance
    ) -> [ClosedRange<CGFloat>] {
        let rawIntervals = displays.compactMap { candidate -> ClosedRange<CGFloat>? in
            guard candidate.id != display.id,
                  touches(candidate, edge: edge, of: display, tolerance: tolerance) else {
                return nil
            }

            let lowerBound = max(display.frame.minY, candidate.frame.minY)
            let upperBound = min(display.frame.maxY, candidate.frame.maxY)
            guard upperBound > lowerBound else { return nil }
            return lowerBound...upperBound
        }

        return rawIntervals
            .sorted { $0.lowerBound < $1.lowerBound }
            .reduce(into: [ClosedRange<CGFloat>]()) { result, interval in
                guard let last = result.last else {
                    result.append(interval)
                    return
                }
                if interval.lowerBound <= last.upperBound + tolerance {
                    result[result.count - 1] = last.lowerBound...max(last.upperBound, interval.upperBound)
                } else {
                    result.append(interval)
                }
            }
    }

    public static func adjacency(
        at edge: DisplayEdge,
        of display: DisplayGeometry,
        in displays: [DisplayGeometry],
        tolerance: CGFloat = adjacencyTolerance
    ) -> DisplayEdgeAdjacency {
        let mergedIntervals = sharedIntervals(
            at: edge,
            of: display,
            in: displays,
            tolerance: tolerance
        )
        guard !mergedIntervals.isEmpty else { return .outer }

        let coveredLength = mergedIntervals.reduce(CGFloat.zero) {
            $0 + max(0, $1.upperBound - $1.lowerBound)
        }
        return coveredLength >= display.frame.height - tolerance ? .fullyShared : .partiallyShared
    }

    public static func defaultSelection(
        for display: DisplayGeometry,
        in displays: [DisplayGeometry]
    ) -> DisplayEdgeSelection {
        DisplayEdgeSelection(
            leftEnabled: adjacency(at: .left, of: display, in: displays) != .fullyShared,
            rightEnabled: adjacency(at: .right, of: display, in: displays) != .fullyShared
        )
    }

    public static func collapseStrategy(
        at edge: DisplayEdge,
        of display: DisplayGeometry,
        in displays: [DisplayGeometry],
        screensHaveSeparateSpaces: Bool = false,
        tolerance: CGFloat = adjacencyTolerance
    ) -> DisplayEdgeCollapseStrategy {
        let isShared = hasAdjacentDisplay(
            at: edge,
            of: display,
            in: displays,
            tolerance: tolerance
        )
        guard isShared else { return .slideOffscreen }
        return screensHaveSeparateSpaces ? .displayClippedSlideOffscreen : .systemMinimize
    }

    /// Chooses a strategy for the vertical segment occupied by this window. A
    /// partially shared display edge can therefore slide windows through its
    /// exposed segment while still protecting the segment beside another display.
    public static func collapseStrategy(
        at edge: DisplayEdge,
        of display: DisplayGeometry,
        windowFrame: CGRect,
        in displays: [DisplayGeometry],
        screensHaveSeparateSpaces: Bool = false,
        tolerance: CGFloat = adjacencyTolerance
    ) -> DisplayEdgeCollapseStrategy {
        let windowLowerBound = max(display.frame.minY, windowFrame.minY)
        let windowUpperBound = min(display.frame.maxY, windowFrame.maxY)
        guard windowUpperBound > windowLowerBound else { return .slideOffscreen }

        let overlapsSharedSegment = displays.contains { candidate in
            guard candidate.id != display.id,
                  touches(candidate, edge: edge, of: display, tolerance: tolerance) else {
                return false
            }
            let sharedLowerBound = max(display.frame.minY, candidate.frame.minY)
            let sharedUpperBound = min(display.frame.maxY, candidate.frame.maxY)
            return min(windowUpperBound, sharedUpperBound)
                - max(windowLowerBound, sharedLowerBound) > 0
        }
        guard overlapsSharedSegment else { return .slideOffscreen }
        return screensHaveSeparateSpaces ? .displayClippedSlideOffscreen : .systemMinimize
    }

    public static func resolvedSelection(
        for display: DisplayGeometry,
        in displays: [DisplayGeometry],
        preferences: [String: DisplayEdgeSelection]
    ) -> DisplayEdgeSelection {
        preferences[display.id] ?? defaultSelection(for: display, in: displays)
    }

    private static func touches(
        _ candidate: DisplayGeometry,
        edge: DisplayEdge,
        of display: DisplayGeometry,
        tolerance: CGFloat
    ) -> Bool {
        switch edge {
        case .left:
            return abs(candidate.frame.maxX - display.frame.minX) <= tolerance
        case .right:
            return abs(candidate.frame.minX - display.frame.maxX) <= tolerance
        }
    }
}
