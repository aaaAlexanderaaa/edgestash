import CoreGraphics
import Foundation

public struct ScreenSetWindowKey: Hashable {
    public let windowNumber: UInt32
    public let bundleID: String

    public init(windowNumber: UInt32, bundleID: String) {
        self.windowNumber = windowNumber
        self.bundleID = bundleID
    }
}

public struct ScreenSetPlacement: Codable, Equatable {
    public var windowNumber: UInt32
    public var bundleID: String
    public var displayID: String
    public var edge: Int
    /// Optional preferred visible size and display-relative vertical ratio
    /// remembered per screen set so visiting a smaller display does not
    /// permanently crush the window's original geometry.
    public var preferredWidth: CGFloat?
    public var preferredHeight: CGFloat?
    public var relativeY: CGFloat?

    public init(
        windowNumber: UInt32,
        bundleID: String,
        displayID: String,
        edge: Int,
        preferredWidth: CGFloat? = nil,
        preferredHeight: CGFloat? = nil,
        relativeY: CGFloat? = nil
    ) {
        self.windowNumber = windowNumber
        self.bundleID = bundleID
        self.displayID = displayID
        self.edge = edge
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
        self.relativeY = relativeY
    }

    public var key: ScreenSetWindowKey {
        ScreenSetWindowKey(windowNumber: windowNumber, bundleID: bundleID)
    }

    public var preferredSize: CGSize? {
        guard let preferredWidth, let preferredHeight,
              preferredWidth.isFinite, preferredHeight.isFinite,
              preferredWidth > 0, preferredHeight > 0 else { return nil }
        return CGSize(width: preferredWidth, height: preferredHeight)
    }

    public func sameAnchor(as other: ScreenSetPlacement) -> Bool {
        windowNumber == other.windowNumber
            && bundleID == other.bundleID
            && displayID == other.displayID
            && edge == other.edge
    }
}

public struct ScreenSetConfiguration: Codable, Equatable {
    public var fingerprint: ScreenSetFingerprint
    public var slots: [ScreenSetPlacement]

    public init(fingerprint: ScreenSetFingerprint, slots: [ScreenSetPlacement]) {
        self.fingerprint = fingerprint
        self.slots = slots
    }
}

/// A complete observation, not just the identity key. Geometry must settle and
/// be reapplied even when a global origin shift leaves the fingerprint equal.
public struct ScreenSetObservation: Equatable {
    public var displays: [DisplayGeometry]
    public var scales: [String: CGFloat]
    public var mirroring: Bool

    public init(displays: [DisplayGeometry], scales: [String: CGFloat] = [:], mirroring: Bool = false) {
        self.displays = displays.sorted { $0.id < $1.id }
        self.scales = scales
        self.mirroring = mirroring
    }

    public var fingerprint: ScreenSetFingerprint { ScreenSetPolicy.fingerprint(displays: displays) }
    public var sizes: [String: CGSize] { Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.frame.size) }) }
}

public struct ScreenSetTransition {
    public let event: ScreenSetEvent
    public let restore: [ScreenSetPlacement]
    public let release: Set<ScreenSetWindowKey>
    public let refresh: Set<ScreenSetWindowKey>
    public let refreshReasons: [ScreenSetWindowKey: ScreenSetRefreshReason]
}

public enum ScreenSetRefreshReason: String {
    case wake, missingGeometry, displayFrame, scale, windowSegment, sharedIntervals
}

/// Owns memory selection, complete membership reconciliation, and writes. The
/// macOS adapter only observes displays and executes the returned operations.
/// Environment changes never save a snapshot of their transient result.
public struct ScreenSetMemoryCoordinator {
    /// WindowServer numbers are process-lifetime facts, not durable window
    /// identities. Preserve configured (including empty) screen sets on a new
    /// EdgeStash launch, but never import a previous process's membership.
    public static func startingFresh(_ configurations: [ScreenSetConfiguration]) -> [ScreenSetConfiguration] {
        configurations.map { ScreenSetConfiguration(fingerprint: $0.fingerprint, slots: []) }
    }

    public private(set) var observation: ScreenSetObservation
    public private(set) var memoryFingerprint: ScreenSetFingerprint?
    private var scaleAliases: [ScreenSetFingerprint: ScreenSetFingerprint] = [:]
    private var displaced: [ScreenSetWindowKey: ScreenSetPlacement] = [:]
    /// Per-window, per-display remembered home anchor. Unlike `displaced`, this
    /// is never erased by `dropConfigured`, so unplugging and replugging
    /// displays in any order converges to the same state even across
    /// unconfigured intermediate sets.
    private var homeAnchors: [ScreenSetWindowKey: [String: (slot: ScreenSetPlacement, order: UInt64)]] = [:]
    private var anchorSequence: UInt64 = 0
    private var lastPlacements: [ScreenSetWindowKey: ScreenSetPlacement] = [:]
    /// A closed-lid wake is still the pre-sleep configuration until display
    /// identities or mirroring change. Repeated geometry observations are not
    /// evidence that the held built-in display was unplugged while awake.
    private var sleepHeldDisplayID: String?

    public init(baseline: ScreenSetObservation) {
        observation = baseline
        memoryFingerprint = baseline.mirroring ? nil : baseline.fingerprint
    }

    /// Resolve a live observation to its remembered configuration key across
    /// resolution changes and minor vertical stagger differences.
    public func resolveConfiguredFingerprint(
        for current: ScreenSetObservation,
        configurations: [ScreenSetConfiguration]
    ) -> ScreenSetFingerprint {
        let known = Set(configurations.map(\.fingerprint))
        if let aliased = scaleAliases[current.fingerprint], known.contains(aliased) {
            return aliased
        }
        if known.contains(current.fingerprint) {
            return current.fingerprint
        }
        let sameDevices = known.filter { $0.displayIDs == current.fingerprint.displayIDs }
        if sameDevices.count == 1, let only = sameDevices.first {
            return only
        }
        if sameDevices.count > 1 {
            let currentHorizontal = current.fingerprint.relations.filter { $0.axis == .horizontal }
            let horizontalMatches = sameDevices.filter {
                $0.relations.filter { $0.axis == .horizontal } == currentHorizontal
            }
            if horizontalMatches.count == 1, let match = horizontalMatches.first {
                return match
            }
        }
        return current.fingerprint
    }

    private mutating func rememberHomeAnchor(_ slot: ScreenSetPlacement) {
        anchorSequence &+= 1
        homeAnchors[slot.key, default: [:]][slot.displayID] = (slot, anchorSequence)
    }

    private mutating func seedHomeAnchors(from configurations: [ScreenSetConfiguration]) {
        for config in configurations {
            for slot in config.slots {
                if homeAnchors[slot.key]?[slot.displayID] == nil {
                    rememberHomeAnchor(slot)
                }
            }
        }
    }

    public mutating func settle(
        on current: ScreenSetObservation,
        configurations: [ScreenSetConfiguration],
        live: [ScreenSetPlacement],
        keepMissingDisplay: String? = nil,
        afterWake: Bool = false,
        windowFrames: [ScreenSetWindowKey: CGRect] = [:]
    ) -> ScreenSetTransition {
        seedHomeAnchors(from: configurations)
        for slot in live { rememberHomeAnchor(slot) }

        let previous = observation
        let sameIDs = previous.fingerprint.displayIDs == current.fingerprint.displayIDs
        let present = Set(current.fingerprint.displayIDs)
        if let keepMissingDisplay, !current.mirroring, !present.contains(keepMissingDisplay) {
            sleepHeldDisplayID = keepMissingDisplay
        } else if !sameIDs || current.mirroring {
            sleepHeldDisplayID = nil
        }
        let scaleChanged = sameIDs && (previous.sizes != current.sizes || previous.scales != current.scales)
        let known = Set(configurations.map(\.fingerprint))
        let resolved = resolveConfiguredFingerprint(for: current, configurations: configurations)
        let event: ScreenSetEvent

        if sleepHeldDisplayID != nil {
            // Lid still closed after sleep: keep the pre-sleep memory key.
            // Do not alias this smaller display set to the full pre-sleep set
            // when its resolution changes; it has its own ordinary memory.
            event = sameIDs ? (scaleChanged ? .scale : .none) : .dropUnconfigured
        } else if current.mirroring {
            // A mirrored laptop-shaped desktop is not the laptop-only memory.
            event = .recover
            memoryFingerprint = nil
        } else if previous.mirroring {
            memoryFingerprint = resolved
            event = known.contains(resolved) ? .returnConfigured : .recover
        } else if sameIDs {
            // Neither a frontmost Settings app nor an origin change proves
            // an intentional reset. Keep the memory key, update actual geometry.
            event = scaleChanged ? .scale : .none
            if scaleChanged, let memoryFingerprint {
                scaleAliases[current.fingerprint] = memoryFingerprint
            }
        } else {
            memoryFingerprint = resolved
            event = ScreenSetPolicy.classify(
                previous: previous.fingerprint,
                current: resolved,
                configured: known,
                flags: ScreenSetClassifyFlags()
            )
        }
        observation = current
        let target = memoryFingerprint.flatMap { key in configurations.first { $0.fingerprint == key } }

        if event == .returnConfigured || event == .dropConfigured, let target {
            let keys = Set(target.slots.map(\.key))
            // A configured set is the whole target, never a union with the set
            // we just left. Departed displays' anchors stay in `homeAnchors`
            // so returning to an unconfigured intermediate set is order-independent.
            return transition(
                event: event,
                restore: target.slots,
                release: Set(live.filter { !keys.contains($0.key) }.map(\.key)),
                live: live, previous: previous, afterWake: afterWake, windowFrames: windowFrames
            )
        }

        let gone = live.filter { !present.contains($0.displayID) && $0.displayID != sleepHeldDisplayID }
        for slot in gone {
            displaced[slot.key] = slot
            rememberHomeAnchor(slot)
        }
        let managed = Set(live.map(\.key))
        let addedDisplays = present.subtracting(Set(previous.fingerprint.displayIDs))
        var returningByKey: [ScreenSetWindowKey: ScreenSetPlacement] = [:]
        if !current.mirroring && target == nil {
            for slot in displaced.values where present.contains(slot.displayID) && !managed.contains(slot.key) {
                returningByKey[slot.key] = slot
            }
            if !addedDisplays.isEmpty {
                for (key, perDisplay) in homeAnchors where !managed.contains(key) && returningByKey[key] == nil {
                    let candidates = perDisplay.values.filter { addedDisplays.contains($0.slot.displayID) }
                    if let best = candidates.max(by: { lhs, rhs in
                        if lhs.order != rhs.order { return lhs.order < rhs.order }
                        return lhs.slot.displayID > rhs.slot.displayID
                    }) {
                        returningByKey[key] = best.slot
                    }
                }
            }
        }
        let returning = returningByKey.values.sorted {
            if $0.bundleID != $1.bundleID { return $0.bundleID < $1.bundleID }
            return $0.windowNumber < $1.windowNumber
        }
        return transition(event: event, restore: returning, release: Set(gone.map(\.key)),
                          live: live, previous: previous, afterWake: afterWake, windowFrames: windowFrames)
    }

    private mutating func transition(
        event: ScreenSetEvent, restore: [ScreenSetPlacement], release: Set<ScreenSetWindowKey>,
        live: [ScreenSetPlacement], previous: ScreenSetObservation, afterWake: Bool,
        windowFrames: [ScreenSetWindowKey: CGRect]
    ) -> ScreenSetTransition {
        lastPlacements = Dictionary(uniqueKeysWithValues: live.filter { !release.contains($0.key) }.map { ($0.key, $0) })
        for slot in restore { lastPlacements[slot.key] = slot }
        let restoring = Set(restore.map(\.key))
        let present = Set(observation.fingerprint.displayIDs)
        var reasons: [ScreenSetWindowKey: ScreenSetRefreshReason] = [:]
        for slot in live {
            guard present.contains(slot.displayID), !release.contains(slot.key), !restoring.contains(slot.key) else { continue }
            if let reason = Self.refreshReason(slot: slot, previous: previous, current: observation,
                                               afterWake: afterWake, windowFrame: windowFrames[slot.key]) {
                reasons[slot.key] = reason
            }
        }
        return ScreenSetTransition(event: event, restore: restore, release: release,
                                   refresh: Set(reasons.keys), refreshReasons: reasons)
    }

    public static func refreshReason(slot: ScreenSetPlacement, previous: ScreenSetObservation,
                                     current: ScreenSetObservation, afterWake: Bool,
                                     windowFrame: CGRect?) -> ScreenSetRefreshReason? {
        // Display power and system sleep can invalidate the live hidden
        // presentation without changing a single display metric. Wake is
        // an explicit repair boundary; a duplicate awake observation isn't.
        if afterWake { return .wake }
        guard let before = previous.displays.first(where: { $0.id == slot.displayID }),
              let after = current.displays.first(where: { $0.id == slot.displayID }),
              let edge = DisplayEdge(rawValue: slot.edge) else { return .missingGeometry }
        // Repeated observations and unrelated display changes must not
        // rewrite stable windows. Changed adjacency or geometry still does.
        if before.frame != after.frame || before.visibleFrame != after.visibleFrame { return .displayFrame }
        if previous.scales[slot.displayID] != current.scales[slot.displayID] { return .scale }
        if let frame = windowFrame, frame.width > 0, frame.height > 0,
           [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) {
            return DisplayEdgePolicy.collapseStrategy(at: edge, of: before, windowFrame: frame, in: previous.displays)
                != DisplayEdgePolicy.collapseStrategy(at: edge, of: after, windowFrame: frame, in: current.displays)
                ? .windowSegment : nil
        }
        // Without saved window bounds, retain the complete adjacency
        // intervals. A whole-edge Boolean loses changes on partial seams.
        return DisplayEdgePolicy.sharedIntervals(at: edge, of: before, in: previous.displays)
            != DisplayEdgePolicy.sharedIntervals(at: edge, of: after, in: current.displays)
            ? .sharedIntervals : nil
    }

    public mutating func didRestore(_ slot: ScreenSetPlacement) {
        displaced.removeValue(forKey: slot.key)
    }

    /// A reveal, pin, or recollapse must not overwrite the other members of a
    /// configuration, including slots whose AX restoration is still pending.
    /// Only the changed window's placement is updated. The first deliberate
    /// capture on an unconfigured set also remembers the carried stashes.
    public mutating func recording(
        _ slot: ScreenSetPlacement,
        live: [ScreenSetPlacement],
        configurations: [ScreenSetConfiguration]
    ) -> [ScreenSetConfiguration] {
        guard let memoryFingerprint, !observation.mirroring,
              observation.fingerprint.displayIDs.contains(slot.displayID) else { return configurations }
        guard lastPlacements[slot.key] != slot else { return configurations }
        lastPlacements[slot.key] = slot
        rememberHomeAnchor(slot)
        displaced.removeValue(forKey: slot.key)
        var result = configurations
        if let index = result.firstIndex(where: { $0.fingerprint == memoryFingerprint }) {
            if let member = result[index].slots.firstIndex(where: { $0.key == slot.key }) {
                result[index].slots[member] = slot
            } else {
                result[index].slots.append(slot)
            }
        } else {
            let present = Set(observation.fingerprint.displayIDs)
            var slots = live.filter { present.contains($0.displayID) && $0.key != slot.key }
            slots.append(slot)
            result.append(ScreenSetConfiguration(fingerprint: memoryFingerprint, slots: slots))
        }
        return result
    }

    public mutating func forgetting(
        _ key: ScreenSetWindowKey,
        everywhere: Bool,
        configurations: [ScreenSetConfiguration]
    ) -> [ScreenSetConfiguration] {
        displaced.removeValue(forKey: key)
        lastPlacements.removeValue(forKey: key)
        if everywhere {
            homeAnchors.removeValue(forKey: key)
        } else {
            let present = Set(observation.fingerprint.displayIDs)
            if var anchors = homeAnchors[key] {
                for id in present { anchors.removeValue(forKey: id) }
                if anchors.isEmpty { homeAnchors.removeValue(forKey: key) }
                else { homeAnchors[key] = anchors }
            }
        }
        var result = configurations
        for index in result.indices where everywhere || result[index].fingerprint == memoryFingerprint {
            result[index].slots.removeAll { $0.key == key }
        }
        // An intentionally empty configured set is still a remembered choice.
        return result
    }
}
