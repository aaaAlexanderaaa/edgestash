import CoreGraphics
import Foundation

public struct ScreenSetFingerprint: Equatable, Hashable, Codable {
    public let displayIDs: [String]
    public let relations: [ScreenSetRelation]

    public init(displayIDs: [String], relations: [ScreenSetRelation]) {
        self.displayIDs = Array(Set(displayIDs)).sorted()
        self.relations = ScreenSetPolicy.normalizedRelations(relations)
    }
}

/// Directed pair: when `axis` is `horizontal`, `leadingID` is to the left of
/// `trailingID`; when `vertical`, `leadingID` is above `trailingID`.
public struct ScreenSetRelation: Equatable, Hashable, Codable {
    public enum Axis: String, Codable, Hashable {
        case horizontal
        case vertical
    }

    public let axis: Axis
    public let leadingID: String
    public let trailingID: String

    public init(axis: Axis, leadingID: String, trailingID: String) {
        self.axis = axis
        self.leadingID = leadingID
        self.trailingID = trailingID
    }
}

public struct ScreenSetClassifyFlags: Equatable {
    public var isSleepingOrWaking: Bool
    public var mirrorChanged: Bool
    public var scaleChanged: Bool
    /// Same-ID relation changes are cancel only when the person is likely
    /// rearranging in System Settings. A reflow during unplug is not cancel.
    public var userRearrangeLikely: Bool

    public init(
        isSleepingOrWaking: Bool = false,
        mirrorChanged: Bool = false,
        scaleChanged: Bool = false,
        userRearrangeLikely: Bool = true
    ) {
        self.isSleepingOrWaking = isSleepingOrWaking
        self.mirrorChanged = mirrorChanged
        self.scaleChanged = scaleChanged
        self.userRearrangeLikely = userRearrangeLikely
    }
}

public enum ScreenSetEvent: Equatable {
    case none
    case sleep
    case increment
    case dropConfigured
    case dropUnconfigured
    case returnConfigured
    case cancel
    case scale
    /// Identities changed in a way that is not increment, drop, or return.
    /// Keep every configured memory. Windows whose owning display is gone
    /// become usable on a remaining display (INV-L4).
    case recover
}

public enum ScreenSetPolicy {
    public static func fingerprint(displays: [DisplayGeometry]) -> ScreenSetFingerprint {
        var unique: [DisplayGeometry] = []
        var seen = Set<String>()
        for display in displays {
            if seen.insert(display.id).inserted {
                unique.append(display)
            }
        }

        let tolerance = DisplayEdgePolicy.adjacencyTolerance
        var relations: [ScreenSetRelation] = []
        for first in unique {
            for second in unique where first.id != second.id {
                if second.frame.minX - first.frame.minX > tolerance {
                    relations.append(
                        ScreenSetRelation(
                            axis: .horizontal,
                            leadingID: first.id,
                            trailingID: second.id
                        )
                    )
                }
                if first.frame.minY - second.frame.minY > tolerance {
                    relations.append(
                        ScreenSetRelation(
                            axis: .vertical,
                            leadingID: first.id,
                            trailingID: second.id
                        )
                    )
                }
            }
        }

        return ScreenSetFingerprint(
            displayIDs: unique.map(\.id),
            relations: relations
        )
    }

    public static func classify(
        previous: ScreenSetFingerprint?,
        current: ScreenSetFingerprint,
        configured: Set<ScreenSetFingerprint>,
        flags: ScreenSetClassifyFlags
    ) -> ScreenSetEvent {
        if flags.isSleepingOrWaking { return .sleep }

        guard let previous else {
            // First observation only records the baseline. Restoring or
            // cancelling needs a previous set; launch/reboot is `fresh` in
            // the engine, not a classify event.
            return .none
        }

        let previousIDs = Set(previous.displayIDs)
        let currentIDs = Set(current.displayIDs)

        // Hardware mirroring is cancel even when the visible ID count drops.
        // Overlapping frames during an unplug are not this flag.
        if flags.mirrorChanged { return .cancel }

        if previousIDs == currentIDs {
            if previous.relations != current.relations {
                return flags.userRearrangeLikely ? .cancel : .none
            }
            if flags.scaleChanged { return .scale }
            return .none
        }

        // Returning to a configured set (laptop → remembered 3-set) is not
        // increment. A shrink onto a configured remaining set is dropConfigured,
        // so this arm does not fire when current IDs are a proper subset.
        let isShrink = currentIDs.isSubset(of: previousIDs)
            && currentIDs.count < previousIDs.count
        if configured.contains(current), current != previous, !isShrink {
            return .returnConfigured
        }

        let isGrow = currentIDs.isSuperset(of: previousIDs)
            && currentIDs.count > previousIDs.count
        if isGrow {
            return .increment
        }

        // A shrink whose remaining frames have not settled must still be a
        // drop, not cancel: cancel would discard the departed set's memory.
        if isShrink {
            return configured.contains(current) ? .dropConfigured : .dropUnconfigured
        }

        return .recover
    }

    /// Displays that disappeared (previous − current).
    public static func departedDisplayIDs(
        previous: ScreenSetFingerprint,
        current: ScreenSetFingerprint
    ) -> Set<String> {
        Set(previous.displayIDs).subtracting(current.displayIDs)
    }

    /// Displays that appeared (current − previous).
    public static func addedDisplayIDs(
        previous: ScreenSetFingerprint,
        current: ScreenSetFingerprint
    ) -> Set<String> {
        Set(current.displayIDs).subtracting(previous.displayIDs)
    }

    public static func scatterOrigins(
        count: Int,
        on display: CGRect,
        windowSize: CGSize
    ) -> [CGPoint] {
        guard count > 0 else { return [] }

        let cascade: CGFloat = 40
        let start = comfortableOrigin(on: display, windowSize: windowSize)
        if count == 1 { return [start] }

        var origins: [CGPoint] = [start]
        var wrap = 0
        var step = 1
        var safety = 0
        let safetyLimit = max(count * 64, 256)

        while origins.count < count, safety < safetyLimit {
            safety += 1
            let unclamped = CGPoint(
                x: start.x + CGFloat(wrap) * cascade + CGFloat(step) * cascade,
                y: start.y + CGFloat(step) * cascade
            )
            if !windowFits(at: unclamped, on: display, windowSize: windowSize) {
                wrap += 1
                step = 1
                let wrapped = CGPoint(
                    x: start.x + CGFloat(wrap) * cascade,
                    y: start.y
                )
                if !windowFits(at: wrapped, on: display, windowSize: windowSize) {
                    let rowWrapped = CGPoint(
                        x: start.x,
                        y: start.y + CGFloat(wrap) * cascade
                    )
                    if windowFits(at: rowWrapped, on: display, windowSize: windowSize),
                       rowWrapped != origins.last,
                       !origins.contains(rowWrapped) {
                        origins.append(rowWrapped)
                        step = 1
                        continue
                    }
                    if let fallback = nextUnusedOrigin(
                        after: origins.last ?? start,
                        used: origins,
                        on: display,
                        windowSize: windowSize
                    ) {
                        origins.append(fallback)
                    } else {
                        break
                    }
                }
                continue
            }
            if unclamped != origins.last, !origins.contains(unclamped) {
                origins.append(unclamped)
            }
            step += 1
        }

        while origins.count < count {
            guard let fallback = nextUnusedOrigin(
                after: origins.last ?? start,
                used: origins,
                on: display,
                windowSize: windowSize
            ) else {
                break
            }
            origins.append(fallback)
        }

        return origins
    }

    fileprivate static func normalizedRelations(
        _ relations: [ScreenSetRelation]
    ) -> [ScreenSetRelation] {
        Array(Set(relations)).sorted { lhs, rhs in
            if lhs.axis != rhs.axis {
                return lhs.axis.rawValue < rhs.axis.rawValue
            }
            if lhs.leadingID != rhs.leadingID {
                return lhs.leadingID < rhs.leadingID
            }
            return lhs.trailingID < rhs.trailingID
        }
    }

    private static func comfortableOrigin(
        on display: CGRect,
        windowSize: CGSize
    ) -> CGPoint {
        let inset: CGFloat = 80
        let fitsWithInset = windowSize.width + inset <= display.width
            && windowSize.height + inset <= display.height
        let origin: CGPoint
        if fitsWithInset {
            origin = CGPoint(x: display.minX + inset, y: display.minY + inset)
        } else {
            origin = CGPoint(
                x: display.minX + (display.width - windowSize.width) / 2,
                y: display.minY + (display.height - windowSize.height) / 2
            )
        }
        return clampedOrigin(origin, on: display, windowSize: windowSize)
    }

    private static func clampedOrigin(
        _ origin: CGPoint,
        on display: CGRect,
        windowSize: CGSize
    ) -> CGPoint {
        let x: CGFloat
        if windowSize.width >= display.width {
            x = display.minX
        } else {
            x = min(max(origin.x, display.minX), display.maxX - windowSize.width)
        }
        let y: CGFloat
        if windowSize.height >= display.height {
            y = display.minY
        } else {
            y = min(max(origin.y, display.minY), display.maxY - windowSize.height)
        }
        return CGPoint(x: x, y: y)
    }

    private static func windowFits(
        at origin: CGPoint,
        on display: CGRect,
        windowSize: CGSize
    ) -> Bool {
        origin.x >= display.minX
            && origin.y >= display.minY
            && origin.x + windowSize.width <= display.maxX
            && origin.y + windowSize.height <= display.maxY
    }

    private static func nextUnusedOrigin(
        after last: CGPoint,
        used: [CGPoint],
        on display: CGRect,
        windowSize: CGSize
    ) -> CGPoint? {
        let minX = display.minX
        let minY = display.minY
        let maxX = windowSize.width >= display.width ? minX : display.maxX - windowSize.width
        let maxY = windowSize.height >= display.height ? minY : display.maxY - windowSize.height
        guard maxX >= minX, maxY >= minY else { return nil }

        let cascade: CGFloat = 40
        var x = last.x + cascade
        var y = last.y + cascade
        if x > maxX || y > maxY {
            x = min(last.x + cascade, maxX)
            y = minY
            if x == last.x {
                x = minX
                y = min(last.y + cascade, maxY)
            }
        }

        let rangeX = maxX - minX
        let rangeY = maxY - minY
        let limit = Int(max(rangeX, 1) * max(rangeY, 1)) + 8
        var steps = 0
        while steps < limit {
            let candidate = clampedOrigin(
                CGPoint(x: x, y: y),
                on: display,
                windowSize: windowSize
            )
            if candidate != last, !used.contains(candidate) {
                return candidate
            }
            x += 1
            if x > maxX {
                x = minX
                y += 1
                if y > maxY {
                    y = minY
                }
            }
            steps += 1
        }
        return nil
    }
}
