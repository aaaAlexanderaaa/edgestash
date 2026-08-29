import Foundation
import CoreGraphics

/// Reunites a persisted rescue record with a live AX window after a crash.
/// The recorded window number is authoritative when still present; otherwise
/// exactly one shape-plausible candidate may be adopted, never several.
public enum RescueMatching {
    public struct Candidate {
        public let windowID: UInt32?
        public let frame: CGRect

        public init(windowID: UInt32?, frame: CGRect) {
            self.windowID = windowID
            self.frame = frame
        }
    }

    public enum Verdict: Equatable {
        case matched(UInt32)
        case unresolved
    }

    /// Slack for shape-matching after an app relaunch. Everything is derived
    /// from the recorded frame rather than absolute pixels: sizes may snap to
    /// a preset (fractional slack), the top can shift by window chrome
    /// (menu bar, autohide Dock), and the edge test stays far tighter than
    /// the live capture threshold so a fallback match can never claim an
    /// unrelated window.
    public enum Tolerances {
        public static let widthFraction: CGFloat = 1.0 / 8.0
        public static let heightFraction: CGFloat = 1.0 / 5.0
        public static let verticalFraction: CGFloat = 1.0 / 4.0
        public static let minimumSize: CGFloat = 16
        public static let minimumVertical: CGFloat = 48
        public static let edgeFlush: CGFloat = 16
    }

    public static func identify(
        recordedNumber: UInt32,
        recordedEdge: Int,
        recordedFrame: CGRect,
        recordedDisplay: CGRect,
        among candidates: [Candidate]
    ) -> Verdict {
        if let kept = candidates.first(where: { $0.windowID == recordedNumber }), let windowID = kept.windowID {
            return .matched(windowID)
        }

        let record = Record(
            windowID: recordedNumber,
            edge: recordedEdge,
            visibleFrame: recordedFrame,
            displayFrame: recordedDisplay
        )
        let plausible = candidates.filter { candidate in
            candidate.windowID != nil && resemblesRecordedWindow(frame: candidate.frame, record: record)
        }
        guard plausible.count == 1, let windowID = plausible[0].windowID else {
            return .unresolved
        }
        return .matched(windowID)
    }

    /// A size-only AX write is not a restore. Drop the record only when the
    /// window is visible, unminimized, and fully placed back on-screen.
    public static func recordIsSettled(
        moved: Bool,
        resized: Bool,
        alphaRestored: Bool,
        unminimized: Bool
    ) -> Bool {
        moved && resized && alphaRestored && unminimized
    }

    public static func resemblesRecordedWindow(frame: CGRect, record: Record) -> Bool {
        let visible = record.visibleFrame
        let display = record.displayFrame

        let widthSlack = max(Tolerances.minimumSize, visible.width * Tolerances.widthFraction)
        let heightSlack = max(Tolerances.minimumSize, visible.height * Tolerances.heightFraction)
        let topSlack = max(Tolerances.minimumVertical, visible.height * Tolerances.verticalFraction)

        let sizeFits = abs(frame.width - visible.width) <= widthSlack
            && abs(frame.height - visible.height) <= heightSlack
        let topFits = abs(frame.minY - visible.minY) <= topSlack
        guard sizeFits, topFits else { return false }

        guard let edge = DisplayEdge(rawValue: record.edge) else { return false }
        let flushOnOwningEdge: CGFloat
        let currentAnchor: CGFloat
        switch edge {
        case .left:
            flushOnOwningEdge = display.minX + StashGeometryPolicy.edgeLip
            currentAnchor = frame.maxX
        case .right:
            flushOnOwningEdge = display.maxX - StashGeometryPolicy.edgeLip
            currentAnchor = frame.minX
        }
        return abs(currentAnchor - flushOnOwningEdge) <= Tolerances.edgeFlush
    }

    public static func shouldSkipRestoreBecauseAlreadyVisible(
        frame: CGRect,
        display: CGRect
    ) -> Bool {
        let visible = frame.intersection(display)
        guard visible.width > 1, visible.height > 1 else { return false }
        return visible.width >= frame.width - 8 && visible.height >= frame.height - 8
    }

    /// Kept as the value type threading recorded facts through the match.
    public struct Record {
        public let windowID: UInt32
        public let edge: Int
        public let visibleFrame: CGRect
        public let displayFrame: CGRect

        public init(windowID: UInt32, edge: Int, visibleFrame: CGRect, displayFrame: CGRect) {
            self.windowID = windowID
            self.edge = edge
            self.visibleFrame = visibleFrame
            self.displayFrame = displayFrame
        }
    }
}
