import Foundation

/// AX and app discovery can lag a settled display observation. Retry only the
/// failed targets, at 1/2/4 seconds, then leave the usable fallback and memory.
/// A new environment replaces this queue; deliberate capture/death cancels a key.
public struct ScreenSetRestorationRetry {
    private var failures: [ScreenSetWindowKey: (slot: ScreenSetPlacement, count: Int, dueAt: Date?)] = [:]
    private static let delays: [TimeInterval] = [1, 2, 4]

    public init() {}

    /// A repeated observation in the same selected memory preserves pending
    /// targets without spending their timed retry attempts early. A changed
    /// target is a new placement and can be attempted immediately.
    public mutating func beginApplication(
        restoring slots: [ScreenSetPlacement], retainingPending: Bool
    ) -> [ScreenSetPlacement] {
        if !retainingPending { failures.removeAll() }
        return slots.filter { slot in
            guard let failed = failures[slot.key] else { return true }
            return failed.slot != slot
        }.sorted { ($0.bundleID, $0.windowNumber) < ($1.bundleID, $1.windowNumber) }
    }

    public var pending: [ScreenSetPlacement] {
        failures.values.filter { $0.dueAt != nil }.map(\.slot).sorted {
            ($0.bundleID, $0.windowNumber) < ($1.bundleID, $1.windowNumber)
        }
    }

    public func due(now: Date = Date()) -> [ScreenSetPlacement] {
        pending.filter { slot in
            failures[slot.key]?.dueAt.map { $0 <= now } == true
        }
    }

    public func nextDelay(now: Date = Date()) -> TimeInterval? {
        failures.values.compactMap(\.dueAt).min().map { max(0, $0.timeIntervalSince(now)) }
    }

    public mutating func failed(_ slot: ScreenSetPlacement, now: Date = Date()) {
        let count = failures[slot.key].map { $0.slot == slot ? $0.count : 0 } ?? 0
        let nextCount = count + 1
        let dueAt = nextCount <= Self.delays.count
            ? now.addingTimeInterval(Self.delays[nextCount - 1]) : nil
        failures[slot.key] = (slot, nextCount, dueAt)
    }

    public mutating func remove(_ key: ScreenSetWindowKey) {
        failures.removeValue(forKey: key)
    }
}

/// Screen power notifications are independent of system sleep. Only a real
/// system sleep authorizes retaining the missing built-in display on wake.
public struct ScreenSetPowerState {
    public private(set) var systemSleeping = false
    public private(set) var screensSleeping = false
    public private(set) var isWaking = false
    public private(set) var preservesClosedLid = false
    public var blocksEnumeration: Bool { systemSleeping || screensSleeping }

    public init() {}

    public mutating func systemWillSleep() {
        systemSleeping = true
        isWaking = false
        preservesClosedLid = true
    }

    public mutating func screensDidSleep() {
        screensSleeping = true
        isWaking = false
    }

    public mutating func didWake(systemWake: Bool) {
        systemSleeping = false
        screensSleeping = false
        isWaking = true
        preservesClosedLid = preservesClosedLid || systemWake
    }

    public mutating func settled() { self = ScreenSetPowerState() }
}

public enum ScreenSetSettleDecision: Equatable {
    /// Topology blips while the Mac is asleep must not classify as unplug.
    case ignoreSleepBlip
    /// The fingerprint moved again; wait for another quiet interval.
    case reschedule
    /// The timer fired after a wall-clock jump, so the Mac slept through it.
    case sleptThrough
    /// The observation has been stable long enough to classify.
    case apply
}

/// Screen-set notifications are not atomic. Unplug walks 3→2→1, wake
/// enumerates 1 then 3, and lid-sleep often reconfigures displays before
/// `willSleep`. Classify only after the fingerprint is quiet, and treat a
/// timer that overran as sleep rather than drop.
public enum ScreenSetSettlePolicy {
    /// Quiet interval after the last observation for grow, scale, and rearrange.
    public static let stabilityInterval: TimeInterval = 1.0
    /// Extra hold on a shrink so a late `willSleep` / screens-did-sleep can
    /// still freeze the set. A meeting unplug waits this long, then drops.
    public static let shrinkSleepGrace: TimeInterval = 2.0
    /// After wake, wait until enumeration stops before comparing to pre-sleep.
    public static let wakeStabilityInterval: TimeInterval = 2.0
    /// Extra hold when wake is still a subset of the pre-sleep set, so a
    /// dock that enumerates slowly is not treated as unplug.
    public static let wakeSubsetGrace: TimeInterval = 4.0
    /// A settle timer that fires this far past its delay slept through.
    public static let sleptThroughSlack: TimeInterval = 2.0
    /// AX moved can beat the screen-parameter notification. Hold a would-be
    /// user-leave until that notification has had a chance to quiet the set.
    public static let geometryDetachDeferral: TimeInterval = 0.8

    public static func delay(wakePass: Bool, isShrinkFromCommitted: Bool) -> TimeInterval {
        if wakePass { return wakeStabilityInterval }
        if isShrinkFromCommitted { return stabilityInterval + shrinkSleepGrace }
        return stabilityInterval
    }

    public static func isShrink(committedIDs: Set<String>?, currentIDs: Set<String>) -> Bool {
        guard let committedIDs else { return false }
        return currentIDs.isSubset(of: committedIDs) && currentIDs.count < committedIDs.count
    }

    public static func sleptThrough(elapsed: TimeInterval, scheduledDelay: TimeInterval) -> Bool {
        elapsed > scheduledDelay + sleptThroughSlack
    }

    public static func decision(
        sleepingAndNotWakePass: Bool,
        currentMatchesLastObserved: Bool,
        elapsedSinceScheduled: TimeInterval,
        scheduledDelay: TimeInterval
    ) -> ScreenSetSettleDecision {
        if sleepingAndNotWakePass { return .ignoreSleepBlip }
        if sleptThrough(elapsed: elapsedSinceScheduled, scheduledDelay: scheduledDelay) {
            return .sleptThrough
        }
        if !currentMatchesLastObserved { return .reschedule }
        return .apply
    }

    public static func wakeMatchesPreSleep(
        preSleep: ScreenSetFingerprint?,
        current: ScreenSetFingerprint
    ) -> Bool {
        preSleep == current
    }

    /// Only the built-in display left the pre-sleep set. Lid still closed
    /// after sleep is this, not unplug.
    public static func onlyBuiltinMissing(
        preSleepIDs: Set<String>,
        currentIDs: Set<String>,
        builtinID: String?
    ) -> Bool {
        guard let builtinID, preSleepIDs.contains(builtinID) else { return false }
        let departed = preSleepIDs.subtracting(currentIDs)
        return departed == [builtinID] && currentIDs.isSubset(of: preSleepIDs)
    }

    public static func wakeDecision(
        preSleepIDs: Set<String>?,
        currentIDs: Set<String>,
        currentIsConfigured: Bool,
        onlyBuiltinMissing: Bool,
        subsetHoldElapsed: TimeInterval
    ) -> ScreenSetWakeDecision {
        guard let preSleepIDs else { return .applyClassified }
        if preSleepIDs == currentIDs { return .sameSet }
        let isShrink = currentIDs.isSubset(of: preSleepIDs) && currentIDs.count < preSleepIDs.count
        let isGrow = currentIDs.isSuperset(of: preSleepIDs) && currentIDs.count > preSleepIDs.count
        if isGrow {
            return currentIsConfigured ? .restoreConfigured : .increment
        }
        if isShrink {
            if subsetHoldElapsed < wakeSubsetGrace { return .waitLonger }
            // Clamshell sleep keeps the built-in placement. A genuinely
            // unplugged external must become usable after enumeration settles.
            return onlyBuiltinMissing ? .keepPreSleep : .applyClassified
        }
        if currentIsConfigured { return .restoreConfigured }
        return .applyClassified
    }
}

public enum ScreenSetWakeDecision: Equatable {
    case sameSet
    /// Still a subset of pre-sleep; wait for more displays or the grace to end.
    case waitLonger
    /// Lid still closed: commit the smaller live set without scattering.
    case keepPreSleep
    case restoreConfigured
    case increment
    case applyClassified
}
