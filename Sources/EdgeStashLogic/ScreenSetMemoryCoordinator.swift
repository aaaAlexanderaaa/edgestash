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

    public init(windowNumber: UInt32, bundleID: String, displayID: String, edge: Int) {
        self.windowNumber = windowNumber
        self.bundleID = bundleID
        self.displayID = displayID
        self.edge = edge
    }

    public var key: ScreenSetWindowKey {
        ScreenSetWindowKey(windowNumber: windowNumber, bundleID: bundleID)
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
}

/// Owns memory selection, complete membership reconciliation, and writes. The
/// macOS adapter only observes displays and executes the returned operations.
/// Environment changes never save a snapshot of their transient result.
public struct ScreenSetMemoryCoordinator {
    public private(set) var observation: ScreenSetObservation
    public private(set) var memoryFingerprint: ScreenSetFingerprint?
    private var scaleAliases: [ScreenSetFingerprint: ScreenSetFingerprint] = [:]
    private var displaced: [ScreenSetWindowKey: ScreenSetPlacement] = [:]
    private var lastPlacements: [ScreenSetWindowKey: ScreenSetPlacement] = [:]
    /// A closed-lid wake is still the pre-sleep configuration until display
    /// identities or mirroring change. Repeated geometry observations are not
    /// evidence that the held built-in display was unplugged while awake.
    private var sleepHeldDisplayID: String?

    public init(baseline: ScreenSetObservation) {
        observation = baseline
        memoryFingerprint = baseline.mirroring ? nil : baseline.fingerprint
    }

    public mutating func settle(
        on current: ScreenSetObservation,
        configurations: [ScreenSetConfiguration],
        live: [ScreenSetPlacement],
        keepMissingDisplay: String? = nil
    ) -> ScreenSetTransition {
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
        // A returning display may already have a new mode, so no same-ID scale
        // notification was observable. An unambiguous memory of these same
        // devices is still theirs; do not mistake that return for a new set.
        let sameDevices = known.filter { $0.displayIDs == current.fingerprint.displayIDs }
        let resolved = scaleAliases[current.fingerprint]
            ?? (known.contains(current.fingerprint) ? current.fingerprint : nil)
            ?? (sameDevices.count == 1 ? sameDevices.first : nil)
            ?? current.fingerprint
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
            // we just left. In particular, surviving displays can have extras.
            return transition(
                event: event,
                restore: target.slots,
                release: Set(live.filter { !keys.contains($0.key) }.map(\.key)),
                live: live
            )
        }

        let gone = live.filter { !present.contains($0.displayID) && $0.displayID != sleepHeldDisplayID }
        for slot in gone { displaced[slot.key] = slot }
        let managed = Set(live.map(\.key))
        let returning = current.mirroring || target != nil ? [] : displaced.values.filter {
            present.contains($0.displayID) && !managed.contains($0.key)
        }.sorted { $0.windowNumber < $1.windowNumber }
        return transition(event: event, restore: returning, release: Set(gone.map(\.key)), live: live)
    }

    private mutating func transition(
        event: ScreenSetEvent, restore: [ScreenSetPlacement], release: Set<ScreenSetWindowKey>, live: [ScreenSetPlacement]
    ) -> ScreenSetTransition {
        lastPlacements = Dictionary(uniqueKeysWithValues: live.filter { !release.contains($0.key) }.map { ($0.key, $0) })
        for slot in restore { lastPlacements[slot.key] = slot }
        let restoring = Set(restore.map(\.key))
        let present = Set(observation.fingerprint.displayIDs)
        let refresh = Set(live.filter {
            present.contains($0.displayID) && !release.contains($0.key) && !restoring.contains($0.key)
        }.map(\.key))
        return ScreenSetTransition(event: event, restore: restore, release: release, refresh: refresh)
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
        var result = configurations
        for index in result.indices where everywhere || result[index].fingerprint == memoryFingerprint {
            result[index].slots.removeAll { $0.key == key }
        }
        // An intentionally empty configured set is still a remembered choice.
        return result
    }
}
