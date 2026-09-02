import Foundation

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
        onlyBuiltinMissing _: Bool,
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
            // Any still-incomplete pre-sleep set is wake, not unplug. Do not
            // switch to a remembered laptop layout; that jumps stashes and
            // jumps them back when the dock finishes enumerating.
            return .keepPreSleep
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
