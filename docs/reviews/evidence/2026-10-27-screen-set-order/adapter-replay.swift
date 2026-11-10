// Append this file to the unmodified live ScreenSetCoordinator.swift before
// compiling. The same-file extension reaches its private application methods.
// Only display enumeration, sessions/AX outcomes, preferences and diagnostics
// are replaced. This executes the real adapter's selection/retry/cancellation
// code, but does not claim physical display enumeration or native AX success.
import EdgeStashLogic

struct NSScreen {
    static var screens: [NSScreen] = []
    var geometry: DisplayGeometry
    var backingScaleFactor: CGFloat = 1
}

enum DisplayCatalog {
    static func adjacencyGeometries(screens: [NSScreen] = NSScreen.screens) -> [DisplayGeometry] { screens.map(\.geometry) }
    static func builtinIdentifier() -> String? { NSScreen.screens.first { $0.geometry.id == "A" }?.geometry.id }
    static func identifier(for screen: NSScreen, screens: [NSScreen]) -> String { screen.geometry.id }
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? { nil }
    static func show(_ displays: [DisplayGeometry]) { NSScreen.screens = displays.map { NSScreen(geometry: $0) } }
}

final class Preferences {
    static let shared = Preferences()
    var storedScreenSets: [ScreenSetConfiguration] = []
    func configuredFingerprints() -> Set<ScreenSetFingerprint> { Set(storedScreenSets.map(\.fingerprint)) }
}

enum StashDiagnostics {
    static let isEnabled = false
    static func record(_ event: String, _ fields: [String: Any]) {}
}

enum ScreenSetApplicationResult: Equatable { case succeeded, waitingForControl, waitingForPersistence, blockedSpace, failed }

final class StashSession {
    let windowID: UInt32?
    let bundleID: String
    var screenSetSlot: ScreenSetPlacement?
    var pendingScreenSetRecovery: ScreenSetRecoveryIntent?
    var pendingVisibleFallbackOrigin: CGPoint?
    var needsScreenSetRepair = false
    var awaitingWindowControl = false
    var usingSharedMinimize = false
    var restoreFrame: CGRect? = CGRect(x: 80, y: 80, width: 640, height: 480)
    var rescueDisplayFrame: CGRect? = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    var outcome: ScreenSetApplicationResult = .succeeded
    var attempts = 0
    var scatters = 0
    var shutdowns = 0
    var isManaged: Bool { screenSetSlot != nil }
    var isIdle: Bool { !isManaged }
    var recoveryIntent: ScreenSetRecoveryIntent? {
        pendingScreenSetRecovery ?? screenSetSlot.map { ScreenSetRecoveryIntent(placement: $0) }
    }

    init(_ slot: ScreenSetPlacement, managed: Bool) {
        windowID = slot.windowNumber
        bundleID = slot.bundleID
        screenSetSlot = managed ? slot : nil
    }

    func prepareForScreenSetChange() {}
    func shutdown(event: SessionLifecyclePolicy.Event) {
        shutdowns += 1
        screenSetSlot = nil
        usingSharedMinimize = false
    }
    func retainRecoveryIntent(_ intent: ScreenSetRecoveryIntent) { pendingScreenSetRecovery = intent; needsScreenSetRepair = true }
    func cancelPendingRecovery() {
        pendingScreenSetRecovery = nil
        needsScreenSetRepair = false
        ScreenSetCoordinator.active?.cancelRestoration(of: self)
    }
    func completePendingVisibleFallback() { pendingVisibleFallbackOrigin = nil }
    func reconcileScreenSetPresentation(inspectFirst: Bool) -> ScreenSetApplicationResult {
        attempts += 1
        if outcome == .blockedSpace || outcome == .waitingForPersistence, let intent = recoveryIntent {
            retainRecoveryIntent(intent)
        }
        if outcome == .succeeded { pendingScreenSetRecovery = nil; needsScreenSetRepair = false }
        return outcome
    }
    func applyScreenSetSlot(displayID: String, edge: DisplayEdge, intent: ScreenSetRecoveryIntent) -> ScreenSetApplicationResult {
        attempts += 1
        if outcome != .waitingForControl, let windowID {
            screenSetSlot = ScreenSetPlacement(windowNumber: windowID, bundleID: bundleID,
                                              displayID: displayID, edge: edge.rawValue)
        }
        if outcome == .blockedSpace || outcome == .waitingForPersistence { retainRecoveryIntent(intent) }
        if outcome == .succeeded { pendingScreenSetRecovery = nil; needsScreenSetRepair = false }
        return outcome
    }
    func leaveStash(to origin: CGPoint, preservingRecovery intent: ScreenSetRecoveryIntent?) {
        scatters += 1
        screenSetSlot = nil
        pendingScreenSetRecovery = intent
        needsScreenSetRepair = intent != nil
    }
    func diagnose(_ event: String, _ fields: [String: Any] = [:]) {}
}

extension ScreenSetCoordinator {
    func replayApply(_ displays: [DisplayGeometry], afterWake: Bool = false) {
        DisplayCatalog.show(displays)
        beginQuiet()
        apply(snapshot: Self.metrics(), afterWake: afterWake)
        // No run loop is driven in this replay. Retries are invoked explicitly.
        retryWork?.cancel()
        retryWork = nil
    }
    var replayPending: [ScreenSetPlacement] { restorationRetry.pending }
    func replayBudget(_ key: ScreenSetWindowKey) -> Int? { restorationRetry.writeAttemptsRemaining(for: key) }
    func replayRetry() { retryRestoration(); retryWork?.cancel(); retryWork = nil }
    var replaySettleDelay: TimeInterval { settleDelay }
    var replayHasWakeBaseline: Bool { preSleepFingerprint != nil }
    func replayFireSettle(subsetGraceElapsed: Bool = false, overran: Bool = false) {
        // Inject timer delivery and elapsed timestamps, leaving every live
        // finishSettle/finishWake decision and its scheduling code unchanged.
        if subsetGraceElapsed {
            wakeSubsetSince = Date().addingTimeInterval(-ScreenSetSettlePolicy.wakeSubsetGrace)
        }
        settleScheduledAt = Date().addingTimeInterval(-settleDelay
            - (overran ? ScreenSetSettlePolicy.sleptThroughSlack + 1 : 0))
        finishSettle()
        settleWork?.cancel()
        settleWork = nil
        retryWork?.cancel()
        retryWork = nil
    }
}

@main
struct AdapterReplay {
    static func main() throws {
        var assertions = 0
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            assertions += 1
            if !condition { failures.append(message) }
        }
        let displays = ["A", "B", "C"].enumerated().map {
            DisplayGeometry(id: $0.element, frame: CGRect(x: $0.offset * 1920, y: 0, width: 1920, height: 1080))
        }
        let allSlots = displays.enumerated().map {
            ScreenSetPlacement(windowNumber: UInt32($0.offset + 1), bundleID: "adapter.test", displayID: $0.element.id, edge: 1)
        }
        let full = ScreenSetConfiguration(fingerprint: ScreenSetObservation(displays: displays).fingerprint, slots: allSlots)
        let extra = ScreenSetPlacement(windowNumber: 99, bundleID: "adapter.test", displayID: "A", edge: 2)
        var timelines = 0
        var retryTimelines = 0
        var powerTimelines = 0

        for order in [[1, 2], [2, 1]] {
            for removal in [[1, 2], [2, 1]] {
                for configuredIntermediate in [false, true] {
                    for failure in [ScreenSetApplicationResult.succeeded, .failed, .waitingForControl] {
                        for waking in [false, true] {
                            timelines += 1
                            DisplayCatalog.show(displays)
                            Preferences.shared.storedScreenSets = [full]
                            let sessions = allSlots.map { StashSession($0, managed: true) } + [StashSession(extra, managed: false)]
                            let coordinator = ScreenSetCoordinator()
                            coordinator.captureBaseline { sessions }
                            let pair = [displays[0], displays[order[0]]]
                            if configuredIntermediate {
                                let relocated = ScreenSetPlacement(windowNumber: 2, bundleID: "adapter.test", displayID: "A", edge: 2)
                                Preferences.shared.storedScreenSets += [ScreenSetConfiguration(
                                    fingerprint: ScreenSetObservation(displays: pair).fingerprint, slots: [relocated, extra])]
                            }
                            let memories = Preferences.shared.storedScreenSets
                            coordinator.replayApply(displays.enumerated().filter { $0.offset != removal[0] }.map(\.element), afterWake: waking)
                            coordinator.replayApply([displays[0]], afterWake: waking)
                            sessions.forEach { $0.outcome = failure }
                            coordinator.replayApply(pair, afterWake: waking)
                            sessions.forEach { $0.outcome = .succeeded }
                            coordinator.replayApply(displays.reversed(), afterWake: waking)
                            let live = Dictionary(uniqueKeysWithValues: sessions.compactMap(\.screenSetSlot).map { ($0.key, $0) })
                            check(live == Dictionary(uniqueKeysWithValues: allSlots.map { ($0.key, $0) }), "final membership case \(timelines)")
                            check(Preferences.shared.storedScreenSets == memories, "memory changed case \(timelines)")
                            check(coordinator.replayPending.isEmpty, "stale intermediate retry case \(timelines)")
                            check(sessions.allSatisfy { $0.pendingScreenSetRecovery == nil }, "stale session recovery case \(timelines)")
                            coordinator.invalidate()
                        }
                    }
                }
            }
        }

        // Last display arrives while an earlier restore is waiting for control.
        // Only discovery should resume it; duplicates must retain its budget,
        // and retry completion must not reapply successful sibling windows.
        for order in [[1, 2], [2, 1]] {
            DisplayCatalog.show([displays[0]])
            Preferences.shared.storedScreenSets = [full]
            let sessions = allSlots.map { StashSession($0, managed: false) }
            let coordinator = ScreenSetCoordinator()
            coordinator.captureBaseline { sessions }
            coordinator.replayApply([displays[0], displays[order[0]]])
            sessions[order[0]].outcome = .waitingForControl
            coordinator.replayApply(displays, afterWake: true)
            let key = allSlots[order[0]].key
            check(coordinator.replayPending == [allSlots[order[0]]], "only final unavailable control waits")
            for _ in 0..<4 { coordinator.replayApply(displays) }
            check(coordinator.replayBudget(key) == 4, "duplicate notifications spend no waiting write budget")
            let siblingAttempts = sessions.enumerated().filter { $0.offset != order[0] }.map { $0.element.attempts }
            sessions[order[0]].outcome = .succeeded
            coordinator.controlBecameReady(sessions[order[0]])
            coordinator.replayRetry()
            check(Dictionary(uniqueKeysWithValues: sessions.compactMap(\.screenSetSlot).map { ($0.key, $0) })
                == Dictionary(uniqueKeysWithValues: allSlots.map { ($0.key, $0) }), "ready control restores final membership")
            check(siblingAttempts == sessions.enumerated().filter { $0.offset != order[0] }.map { $0.element.attempts }, "retry leaves successful siblings alone")
            check(coordinator.replayPending.isEmpty, "successful control retry clears its queue")
            retryTimelines += 1
            coordinator.invalidate()
        }

        // Exercise the real power/settle entry points, not just apply(). Empty
        // enumeration, rapid arrival, and an intermediate subset that survives
        // the wake grace all end at the same remembered three-screen target.
        for order in [[1, 2], [2, 1]] {
            for systemSleep in [false, true] {
                for slow in [false, true] {
                    powerTimelines += 1
                    DisplayCatalog.show(displays)
                    Preferences.shared.storedScreenSets = [full]
                    let sessions = allSlots.map { StashSession($0, managed: true) }
                    let coordinator = ScreenSetCoordinator()
                    coordinator.captureBaseline { sessions }
                    coordinator.noteScreensDidSleep()
                    if systemSleep { coordinator.noteWillSleep() }
                    DisplayCatalog.show([])
                    coordinator.noteDidWake(sessions: { sessions }, systemWake: systemSleep)
                    coordinator.replayFireSettle()
                    check(coordinator.replayHasWakeBaseline && ScreenSetCoordinator.isQuiet,
                          "empty enumeration retains the wake baseline case \(powerTimelines)")
                    DisplayCatalog.show([displays[0]])
                    coordinator.noteTopologyChanged { sessions }
                    coordinator.replayFireSettle()
                    check(sessions.allSatisfy { $0.scatters == 0 }, "wake grace scatters no windows")
                    if slow {
                        coordinator.replayFireSettle(subsetGraceElapsed: true)
                        check(sessions[1].scatters == 1 && sessions[2].scatters == 1,
                              "expired grace makes genuinely absent display windows usable")
                    }
                    DisplayCatalog.show([displays[0], displays[order[0]]])
                    coordinator.noteTopologyChanged { sessions }
                    if slow { coordinator.replayFireSettle() }
                    DisplayCatalog.show(displays.reversed())
                    coordinator.noteTopologyChanged { sessions }
                    coordinator.replayFireSettle()
                    check(Dictionary(uniqueKeysWithValues: sessions.compactMap(\.screenSetSlot).map { ($0.key, $0) })
                        == Dictionary(uniqueKeysWithValues: allSlots.map { ($0.key, $0) }),
                          "power timeline restores the configured final membership case \(powerTimelines)")
                    check(Preferences.shared.storedScreenSets == [full], "power timeline never overwrites memory")
                    check(!ScreenSetCoordinator.isQuiet && !coordinator.replayHasWakeBaseline,
                          "complete final enumeration ends wake")
                    if !slow { check(sessions.allSatisfy { $0.scatters == 0 }, "rapid enumeration never releases a stash") }
                    coordinator.invalidate()
                }
            }
        }

        for order in [[1, 2], [2, 1]] {
            DisplayCatalog.show(displays)
            Preferences.shared.storedScreenSets = [full]
            let sessions = allSlots.map { StashSession($0, managed: true) }
            let coordinator = ScreenSetCoordinator()
            coordinator.captureBaseline { sessions }
            DisplayCatalog.show([displays[0], displays[order[0]]])
            coordinator.noteTopologyChanged { sessions }
            check(coordinator.replaySettleDelay == ScreenSetSettlePolicy.stabilityInterval
                + ScreenSetSettlePolicy.shrinkSleepGrace, "unplug uses the shrink grace")
            // Enumeration changes before its timer fires, without another
            // delivered notification. The timer must observe and reschedule.
            DisplayCatalog.show([displays[0]])
            coordinator.replayFireSettle()
            check(sessions.allSatisfy { $0.scatters == 0 } && ScreenSetCoordinator.isQuiet,
                  "changed observation reschedules instead of applying stale enumeration")
            DisplayCatalog.show(displays)
            coordinator.noteTopologyChanged { sessions }
            coordinator.replayFireSettle(overran: true)
            check(coordinator.replayHasWakeBaseline && ScreenSetCoordinator.isQuiet,
                  "a timer delivered after a sleep-length overrun starts wake reconciliation")
            coordinator.replayFireSettle()
            check(sessions.allSatisfy { $0.isManaged && $0.scatters == 0 },
                  "rescheduled full enumeration preserves every stash")
            powerTimelines += 1
            coordinator.invalidate()
        }

        // Use real elapsed wall time for one failed-write budget: initial plus
        // the actual 1/2/4-second retries. No timestamp or retry state is patched.
        DisplayCatalog.show([displays[0]])
        Preferences.shared.storedScreenSets = [full]
        let failedSessions = allSlots.map { StashSession($0, managed: false) }
        let failedCoordinator = ScreenSetCoordinator()
        failedCoordinator.captureBaseline { failedSessions }
        failedSessions[1].outcome = .failed
        failedCoordinator.replayApply(displays)
        let failedKey = allSlots[1].key
        check(failedCoordinator.replayBudget(failedKey) == 3, "initial rejected write spends one attempt")
        for (delay, remaining) in [(1.05, 2), (2.05, 1), (4.05, 0)] {
            for _ in 0..<3 { failedCoordinator.replayApply(displays) }
            Thread.sleep(forTimeInterval: delay)
            failedCoordinator.replayRetry()
            check(failedCoordinator.replayBudget(failedKey) == remaining, "timed retry budget advances to \(remaining)")
        }
        check(failedCoordinator.replayPending.isEmpty && failedSessions[1].screenSetSlot == nil,
              "exhausted write leaves a visible fallback and no additional retry")
        check(failedSessions[0].attempts == 1 && failedSessions[2].attempts == 1,
              "failed-write retries do not repeat successful sibling writes")
        check(Preferences.shared.storedScreenSets == [full], "retry exhaustion preserves the complete memory")
        failedSessions[1].outcome = .succeeded
        failedCoordinator.replayApply([displays[0]])
        failedCoordinator.replayApply(displays)
        check(failedSessions.allSatisfy(\.isManaged), "a later screen-set return can restore the retained exhausted target")
        retryTimelines += 1
        failedCoordinator.invalidate()


        // Reliability integration evidence: exercise the unmodified live
        // coordinator's handling of the two new outcomes. Session/AX remains
        // an injected boundary; no claim of native Space or storage completion.
        var reliabilityTimelines = 0
        for outcome in [ScreenSetApplicationResult.blockedSpace, .waitingForPersistence] {
            for retained in [false, true] {
                DisplayCatalog.show(retained ? displays : [displays[0]])
                Preferences.shared.storedScreenSets = [full]
                let sessions = allSlots.map { StashSession($0, managed: retained) }
                let coordinator = ScreenSetCoordinator()
                coordinator.captureBaseline { sessions }
                sessions[1].outcome = outcome
                coordinator.replayApply(displays, afterWake: retained)
                let key = allSlots[1].key
                check(sessions[1].attempts == 1 && coordinator.replayBudget(key) == 3,
                      "new outcome spends exactly one initial attempt: \(outcome), retained=\(retained)")
                check(sessions[1].pendingScreenSetRecovery?.placement == allSlots[1]
                    && sessions[1].screenSetSlot == allSlots[1] && sessions[1].scatters == 0,
                      "new outcome preserves logical membership/intent without scatter")
                let siblings = [sessions[0].attempts, sessions[2].attempts]
                for _ in 0..<3 { coordinator.replayApply(displays) }
                check(sessions[1].attempts == 1 && coordinator.replayBudget(key) == 3,
                      "duplicate observations cannot spend the new outcome's retry budget")
                if retained {
                    for (delay, remaining) in [(1.05, 2), (2.05, 1), (4.05, 0)] {
                        Thread.sleep(forTimeInterval: delay)
                        coordinator.replayRetry()
                        check(coordinator.replayBudget(key) == remaining && sessions[1].scatters == 0,
                              "blocked/persistence retry consumes bounded budget without desktop fallback")
                    }
                    check(sessions[1].attempts == 4 && coordinator.replayPending.isEmpty
                        && sessions[1].pendingScreenSetRecovery?.placement == allSlots[1],
                          "exhaustion retains intent with no extra scheduled retry")
                    check(Preferences.shared.storedScreenSets == [full], "exhaustion keeps configured memory")
                    sessions[1].outcome = .succeeded
                    coordinator.replayApply([displays[0]])
                    coordinator.replayApply(displays)
                    check(Dictionary(uniqueKeysWithValues: sessions.compactMap(\.screenSetSlot).map { ($0.key, $0) })
                        == Dictionary(uniqueKeysWithValues: allSlots.map { ($0.key, $0) })
                        && sessions.allSatisfy { $0.pendingScreenSetRecovery == nil }
                        && coordinator.replayPending.isEmpty && coordinator.replayBudget(key) == nil,
                          "later configured return restores exact placement and clears exhausted intent/budget")
                } else {
                    sessions[1].outcome = .succeeded
                    Thread.sleep(forTimeInterval: 1.05)
                    coordinator.replayRetry()
                    check(coordinator.replayPending.isEmpty && coordinator.replayBudget(key) == nil
                        && sessions[1].pendingScreenSetRecovery == nil,
                          "successful retry clears new outcome queue and retained intent")
                    check([sessions[0].attempts, sessions[2].attempts] == siblings && sessions[1].scatters == 0,
                          "new outcome retry leaves successful siblings and hidden target in place")
                }
                reliabilityTimelines += 1
                coordinator.invalidate()
            }
        }
        for hasIntent in [false, true] {
            DisplayCatalog.show(displays)
            Preferences.shared.storedScreenSets = [full]
            let session = StashSession(allSlots[0], managed: false)
            session.usingSharedMinimize = true
            if hasIntent { session.retainRecoveryIntent(ScreenSetRecoveryIntent(placement: allSlots[0])) }
            let coordinator = ScreenSetCoordinator()
            coordinator.captureBaseline { [session] }
            coordinator.controlBecameReady(session)
            check(session.shutdowns == (hasIntent ? 0 : 1) && !session.isManaged,
                  "ready control releases only a failed capture's debt and cannot recapture")
            check(hasIntent ? session.pendingScreenSetRecovery != nil : !session.usingSharedMinimize,
                  "ready control preserves a real recovery intent instead of releasing it")
            reliabilityTimelines += 1
            coordinator.invalidate()
        }

        let result: [String: Any] = [
            "reliabilityTimelines": reliabilityTimelines,
            "scope": "unmodified live ScreenSetCoordinator with injected display/session boundaries; no physical cable or native AX claim",
            "roundTripTimelines": timelines,
            "retryTimelines": retryTimelines,
            "powerAndSettleTimelines": powerTimelines,
            "assertions": assertions,
            "failures": failures
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if !failures.isEmpty { exit(1) }
    }
}
