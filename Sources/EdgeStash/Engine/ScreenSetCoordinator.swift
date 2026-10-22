import AppKit
import CoreGraphics
import EdgeStashLogic

/// AppKit adapter for the tested screen-set memory coordinator. Observations
/// settle here; membership selection and memory writes stay in the logic layer.
final class ScreenSetCoordinator {
    /// True while a classified event is applying, so user-leave slot writes
    /// and live-placement snapshots do not run for coordinator-driven moves.
    private(set) static var isApplying = false
    /// True while asleep, waking, or waiting for a topology to stop changing.
    private(set) static var isQuiet = false

    static var blocksUserGeometry: Bool { isApplying || isQuiet }

    private var memory: ScreenSetMemoryCoordinator?
    private var committedFingerprint: ScreenSetFingerprint? { memory?.observation.fingerprint }
    private var lastObserved: ScreenSetObservation?
    private var power = ScreenSetPowerState()
    private var wakePass: Bool { power.isWaking }
    private var preSleepFingerprint: ScreenSetFingerprint?
    private var settleWork: DispatchWorkItem?
    private var settleScheduledAt: Date?
    private var settleDelay: TimeInterval = 0
    private var wakeSubsetSince: Date?
    private var knownBuiltinID: String?
    private var sessionSource: (() -> [StashSession])?
    private var restorationRetry = ScreenSetRestorationRetry()
    private var retryWork: DispatchWorkItem?
    var onSettled: ((_ validateBindings: Bool) -> Void)?

    static weak var active: ScreenSetCoordinator?

    func captureBaseline(sessions: @escaping () -> [StashSession]) {
        Self.active = self
        sessionSource = sessions
        let baseline = Self.metrics()
        memory = ScreenSetMemoryCoordinator(baseline: baseline)
        lastObserved = baseline
        knownBuiltinID = DisplayCatalog.builtinIdentifier()
        Self.isQuiet = false
    }

    func invalidate() {
        settleWork?.cancel()
        settleWork = nil
        retryWork?.cancel()
        retryWork = nil
        restorationRetry = ScreenSetRestorationRetry()
        sessionSource = nil
        onSettled = nil
        power.settled()
        preSleepFingerprint = nil
        wakeSubsetSince = nil
        settleScheduledAt = nil
        lastObserved = nil
        memory = nil
        Self.isQuiet = false
        Self.active = nil
    }

    func beginQuiet() {
        Self.isQuiet = true
        retryWork?.cancel()
        retryWork = nil
        sessionSource?().forEach { $0.prepareForScreenSetChange() }
    }

    func noteWillSleep() {
        diagnose("power.system-will-sleep")
        enterSleep()
    }

    func noteScreensDidWake(sessions: @escaping () -> [StashSession]) {
        // Display power can cycle without a system willSleep/didWake pair.
        // It still needs enumeration and a presentation refresh.
        noteDidWake(sessions: sessions, systemWake: false)
    }

    func noteScreensDidSleep() {
        diagnose("power.screens-did-sleep")
        power.screensDidSleep()
        if preSleepFingerprint == nil { preSleepFingerprint = committedFingerprint }
        beginQuiet()
        settleWork?.cancel()
        settleWork = nil
    }

    func noteDidWake(sessions: @escaping () -> [StashSession], systemWake: Bool = true) {
        diagnose(systemWake ? "power.system-did-wake" : "power.screens-did-wake")
        sessionSource = sessions
        power.didWake(systemWake: systemWake)
        beginQuiet()
        if preSleepFingerprint == nil {
            preSleepFingerprint = committedFingerprint
        }
        Self.isQuiet = true
        rememberObservation()
        scheduleSettle()
    }

    func noteTopologyChanged(sessions: @escaping () -> [StashSession]) {
        diagnose("screens.changed")
        sessionSource = sessions
        if power.blocksEnumeration {
            return
        }
        beginQuiet()
        rememberObservation()
        scheduleSettle()
    }

    func recordPlacement(of session: StashSession, sessions: [StashSession]) {
        guard !Self.blocksUserGeometry, !session.needsScreenSetRepair,
              !session.awaitingWindowControl, session.pendingScreenSetRecovery == nil,
              let slot = session.screenSetSlot else { return }
        guard !reconcileUnannouncedTopology() else { return }
        restorationRetry.remove(slot.key)
        let preferences = Preferences.shared
        guard let next = memory?.recording(slot, live: sessions.compactMap(\.screenSetSlot),
                                          configurations: preferences.storedScreenSets),
              next != preferences.storedScreenSets else { return }
        preferences.storedScreenSets = next
    }

    func waitForControl(of session: StashSession) {
        guard let intent = session.recoveryIntent else { return }
        let target = restorationRetry.intent(for: intent.placement.key) ?? intent
        session.retainRecoveryIntent(target)
        restorationRetry.waitForControl(target.placement, intent: target)
        scheduleRestorationRetry()
    }

    func controlBecameReady(_ session: StashSession) {
        guard let number = session.windowID else { return }
        if session.pendingVisibleFallbackOrigin != nil {
            let applying = Self.isApplying
            Self.isApplying = true
            session.completePendingVisibleFallback()
            Self.isApplying = applying
        }
        let key = ScreenSetWindowKey(windowNumber: number, bundleID: session.bundleID)
        if let intent = restorationRetry.intent(for: key) { session.retainRecoveryIntent(intent) }
        restorationRetry.controlBecameReady(key)
        scheduleRestorationRetry()
    }

    func cancelRestoration(of session: StashSession) {
        guard let number = session.windowID else { return }
        restorationRetry.remove(ScreenSetWindowKey(windowNumber: number, bundleID: session.bundleID))
        scheduleRestorationRetry()
    }

    /// AX moved can arrive before the screen-parameter notification. Compare
    /// the whole observation before accepting it as a user's placement change.
    @discardableResult
    func reconcileUnannouncedTopology() -> Bool {
        guard let memory, let sessionSource, memory.observation != Self.metrics() else { return false }
        noteTopologyChanged(sessions: sessionSource)
        return true
    }

    func forgetPlacement(windowNumber: UInt32, bundleID: String, everywhere: Bool) {
        StashDiagnostics.record("memory.forget", ["window": windowNumber, "app": bundleID, "everywhere": everywhere])
        let preferences = Preferences.shared
        let key = ScreenSetWindowKey(windowNumber: windowNumber, bundleID: bundleID)
        restorationRetry.remove(key)
        guard let next = memory?.forgetting(key, everywhere: everywhere,
                                           configurations: preferences.storedScreenSets),
              next != preferences.storedScreenSets else { return }
        preferences.storedScreenSets = next
    }

    private func enterSleep() {
        beginQuiet()
        settleWork?.cancel()
        settleWork = nil
        settleScheduledAt = nil
        wakeSubsetSince = nil
        if preSleepFingerprint == nil {
            preSleepFingerprint = committedFingerprint
        }
        power.systemWillSleep()
        Self.isQuiet = true
    }

    private func rememberObservation() {
        lastObserved = Self.metrics()
    }

    private func scheduleSettle() {
        settleWork?.cancel()
        let snapshot = Self.metrics()
        let delay = ScreenSetSettlePolicy.delay(
            wakePass: wakePass,
            isShrinkFromCommitted: ScreenSetSettlePolicy.isShrink(
                committedIDs: committedFingerprint.map { Set($0.displayIDs) },
                currentIDs: Set(snapshot.fingerprint.displayIDs)
            )
        )
        settleDelay = delay
        settleScheduledAt = Date()
        diagnose("screens.settle-scheduled", ["delay": delay])
        let work = DispatchWorkItem { [weak self] in
            self?.finishSettle()
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func finishSettle() {
        guard !power.screensSleeping else { return }
        let snapshot = Self.metrics()
        let elapsed = settleScheduledAt.map { Date().timeIntervalSince($0) } ?? 0
        let decision = ScreenSetSettlePolicy.decision(
            sleepingAndNotWakePass: power.blocksEnumeration,
            currentMatchesLastObserved: snapshot == lastObserved,
            elapsedSinceScheduled: elapsed,
            scheduledDelay: settleDelay
        )
        diagnose("screens.settle-decision", ["decision": String(describing: decision), "elapsed": elapsed])
        switch decision {
        case .ignoreSleepBlip:
            settleWork = nil
            return
        case .sleptThrough:
            enterSleep()
            // This callback is running, so enumeration can resume. Do not
            // require a future didWake that may already have been delivered.
            noteDidWake(sessions: sessionSource ?? { [] })
            return
        case .reschedule:
            lastObserved = snapshot
            scheduleSettle()
        case .apply:
            settleWork = nil
            settleScheduledAt = nil
            if wakePass {
                finishWake(snapshot: snapshot)
            } else {
                apply(snapshot: snapshot)
            }
        }
    }

    private func finishWake(snapshot: ScreenSetObservation) {
        // An empty enumeration cannot complete wake or consume its baseline.
        guard !snapshot.displays.isEmpty else { scheduleSettle(); return }
        let baseline = preSleepFingerprint ?? committedFingerprint
        let preIDs = baseline.map { Set($0.displayIDs) }
        let currentIDs = Set(snapshot.fingerprint.displayIDs)
        if ScreenSetSettlePolicy.isShrink(committedIDs: preIDs, currentIDs: currentIDs),
           wakeSubsetSince == nil {
            wakeSubsetSince = Date()
        }
        let subsetHold = wakeSubsetSince.map { Date().timeIntervalSince($0) } ?? 0
        let decision = ScreenSetSettlePolicy.wakeDecision(
            preSleepIDs: preIDs,
            currentIDs: currentIDs,
            currentIsConfigured: Preferences.shared.configuredFingerprints().contains(snapshot.fingerprint),
            onlyBuiltinMissing: power.preservesClosedLid && ScreenSetSettlePolicy.onlyBuiltinMissing(
                preSleepIDs: preIDs ?? [],
                currentIDs: currentIDs,
                builtinID: knownBuiltinID ?? DisplayCatalog.builtinIdentifier()
            ),
            subsetHoldElapsed: subsetHold
        )
        diagnose("power.wake-decision", ["decision": String(describing: decision), "subsetHold": subsetHold])
        switch decision {
        case .waitLonger:
            Self.isQuiet = true
            scheduleSettle()
        case .keepPreSleep:
            clearWake()
            apply(snapshot: snapshot, keepMissingDisplay: knownBuiltinID, afterWake: true)
        case .sameSet, .restoreConfigured, .increment, .applyClassified:
            clearWake()
            apply(snapshot: snapshot, afterWake: true)
        }
    }

    private func clearWake() {
        power.settled()
        preSleepFingerprint = nil
        wakeSubsetSince = nil
    }

    private func apply(snapshot: ScreenSetObservation, keepMissingDisplay: String? = nil, afterWake: Bool = false) {
        // An empty enumeration is not a desktop on which restoration can work.
        guard !snapshot.displays.isEmpty else { scheduleSettle(); return }
        let sessions = sessionSource?() ?? []
        let previousKey = memory?.memoryFingerprint
        let previousObservation = memory?.observation
        guard let plan = memory?.settle(
            on: snapshot,
            configurations: Preferences.shared.storedScreenSets,
            live: sessions.compactMap(\.screenSetSlot),
            keepMissingDisplay: keepMissingDisplay,
            afterWake: afterWake
        ) else { return }
        diagnose("screens.apply", ["afterWake": afterWake, "classification": String(describing: plan.event),
                                   "restoreCount": plan.restore.count, "refreshCount": plan.refresh.count,
                                   "releaseCount": plan.release.count])
        let sameMemory = previousKey != nil && previousKey == memory?.memoryFingerprint
        let targets = restorationRetry.beginApplication(
            restoring: plan.restore,
            retainingPending: sameMemory || previousObservation == snapshot
        ).filter { snapshot.fingerprint.displayIDs.contains($0.displayID) && !plan.release.contains($0.key) }
        for key in plan.release { restorationRetry.remove(key) }
        for session in sessions {
            guard let pending = session.pendingScreenSetRecovery,
                  restorationRetry.intent(for: pending.placement.key) == nil else { continue }
            session.cancelPendingRecovery()
        }

        Self.isApplying = true
        defer {
            Self.isApplying = false
            Self.isQuiet = false
            lastObserved = snapshot
            if let builtin = DisplayCatalog.builtinIdentifier() { knownBuiltinID = builtin }
            diagnose("screens.settled", ["pendingRetries": restorationRetry.pending.count])
            onSettled?(true)
            scheduleRestorationRetry()
        }
        var toScatter = sessions.filter { session in
            guard let number = session.windowID else { return false }
            return plan.release.contains(ScreenSetWindowKey(windowNumber: number, bundleID: session.bundleID))
        }
        var applied = Set<ScreenSetWindowKey>()
        for slot in targets {
            guard let edge = DisplayEdge(rawValue: slot.edge) else { continue }
            guard let session = sessions.first(where: { $0.bundleID == slot.bundleID && $0.windowID == slot.windowNumber }) else {
                restorationRetry.waitForControl(slot, intent: ScreenSetRecoveryIntent(placement: slot))
                continue
            }
            let intent = session.recoveryIntent.flatMap { $0.placement == slot ? $0 : nil }
                ?? ScreenSetRecoveryIntent(placement: slot, frame: session.restoreFrame, displayFrame: session.rescueDisplayFrame)
            let result = session.screenSetSlot == slot
                ? session.reconcileScreenSetPresentation(inspectFirst: afterWake)
                : session.applyScreenSetSlot(displayID: slot.displayID, edge: edge, intent: intent)
            applied.insert(slot.key)
            switch result {
            case .succeeded:
                memory?.didRestore(slot)
                restorationRetry.remove(slot.key)
            case .waitingForControl:
                session.retainRecoveryIntent(intent)
                restorationRetry.waitForControl(slot, intent: intent)
            case .failed:
                restorationRetry.failed(slot, intent: intent)
                toScatter.append(session)
            }
            diagnoseRecoveryResult("session.restore-result", session: session, slot: slot, result: result)
        }
        for session in sessions where session.isManaged {
            guard !toScatter.contains(where: { $0 === session }),
                  let slot = session.screenSetSlot,
                  !applied.contains(slot.key), restorationRetry.intent(for: slot.key) == nil,
                  plan.refresh.contains(slot.key) || session.needsScreenSetRepair else { continue }
            let intent = session.recoveryIntent ?? ScreenSetRecoveryIntent(placement: slot)
            let result = session.reconcileScreenSetPresentation(inspectFirst: afterWake)
            switch result {
            case .succeeded:
                break
            case .waitingForControl:
                session.retainRecoveryIntent(intent)
                restorationRetry.waitForControl(slot, intent: intent)
            case .failed:
                restorationRetry.failed(slot, intent: intent)
                toScatter.append(session)
            }
            diagnoseRecoveryResult("session.refresh-result", session: session, slot: slot, result: result)
        }
        scatterLeavingStash(toScatter, on: snapshot.displays)
    }

    private func diagnoseRecoveryResult(_ event: String, session: StashSession,
                                        slot: ScreenSetPlacement, result: ScreenSetApplicationResult) {
        session.diagnose(event, ["result": String(describing: result),
            "remainingAttempts": restorationRetry.writeAttemptsRemaining(for: slot.key) ?? -1])
        if result == .failed, restorationRetry.writeAttemptsRemaining(for: slot.key) == 0 {
            session.diagnose("session.recovery-exhausted")
        }
    }

    private func scheduleRestorationRetry() {
        retryWork?.cancel()
        guard let delay = restorationRetry.nextDelay() else { retryWork = nil; return }
        diagnose("screens.retry-scheduled", ["delay": delay, "pendingRetries": restorationRetry.pending.count])
        let work = DispatchWorkItem { [weak self] in self?.retryRestoration() }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func retryRestoration() {
        retryWork = nil
        guard !Self.blocksUserGeometry, !reconcileUnannouncedTopology(),
              let snapshot = memory?.observation else { return }
        let due = restorationRetry.due()
        diagnose("screens.retry", ["dueCount": due.count])
        guard !due.isEmpty else { scheduleRestorationRetry(); return }
        Self.isApplying = true
        defer {
            Self.isApplying = false
            onSettled?(false)
            scheduleRestorationRetry()
        }
        let sessions = sessionSource?() ?? []
        var failures: [StashSession] = []
        for slot in due {
            guard let edge = DisplayEdge(rawValue: slot.edge) else {
                restorationRetry.remove(slot.key)
                continue
            }
            let intent = restorationRetry.intent(for: slot.key) ?? ScreenSetRecoveryIntent(placement: slot)
            guard let session = sessions.first(where: { $0.bundleID == slot.bundleID && $0.windowID == slot.windowNumber }) else {
                restorationRetry.waitForControl(slot, intent: intent)
                continue
            }
            let result = session.applyScreenSetSlot(displayID: slot.displayID, edge: edge, intent: intent)
            switch result {
            case .succeeded:
                memory?.didRestore(slot)
                restorationRetry.remove(slot.key)
            case .waitingForControl:
                session.retainRecoveryIntent(intent)
                restorationRetry.waitForControl(slot, intent: intent)
            case .failed:
                restorationRetry.failed(slot, intent: intent)
                failures.append(session)
            }
            diagnoseRecoveryResult("session.retry-result", session: session, slot: slot, result: result)
        }
        scatterLeavingStash(failures, on: snapshot.displays)
    }

    private func scatterLeavingStash(_ sessions: [StashSession], on displays: [DisplayGeometry]) {
        let unique = sessions.reduce(into: [StashSession]()) { result, session in
            if !result.contains(where: { $0 === session }) {
                result.append(session)
            }
        }
        guard !unique.isEmpty else { return }
        let origins = Self.scatterOrigins(for: unique, on: displays)
        for session in unique {
            session.diagnose("session.scatter-fallback")
            if let origin = origins[ObjectIdentifier(session)] {
                let intent = session.windowID.flatMap {
                    restorationRetry.intent(for: ScreenSetWindowKey(windowNumber: $0, bundleID: session.bundleID))
                }
                session.leaveStash(to: origin, preservingRecovery: intent)
            } else if let fallback = displays.first {
                let origin = ScreenSetPolicy.scatterOrigins(
                    count: 1,
                    on: fallback.frame,
                    windowSize: session.restoreFrame?.size ?? CGSize(width: 640, height: 480)
                ).first ?? fallback.frame.origin
                let intent = session.windowID.flatMap {
                    restorationRetry.intent(for: ScreenSetWindowKey(windowNumber: $0, bundleID: session.bundleID))
                }
                session.leaveStash(to: origin, preservingRecovery: intent)
            }
        }
    }

    private static func scatterOrigins(
        for sessions: [StashSession],
        on displays: [DisplayGeometry]
    ) -> [ObjectIdentifier: CGPoint] {
        guard !sessions.isEmpty, !displays.isEmpty else { return [:] }
        var groups = Array(repeating: [StashSession](), count: displays.count)
        for (index, session) in sessions.enumerated() {
            groups[index % displays.count].append(session)
        }
        var result: [ObjectIdentifier: CGPoint] = [:]
        for (displayIndex, group) in groups.enumerated() where !group.isEmpty {
            let size = group.first?.restoreFrame?.size ?? CGSize(width: 640, height: 480)
            let origins = ScreenSetPolicy.scatterOrigins(
                count: group.count,
                on: displays[displayIndex].frame,
                windowSize: size
            )
            for (index, session) in group.enumerated() where index < origins.count {
                result[ObjectIdentifier(session)] = origins[index]
            }
        }
        return result
    }

    private static func geometries(screens: [NSScreen] = NSScreen.screens) -> [DisplayGeometry] {
        DisplayCatalog.adjacencyGeometries(screens: screens)
    }

    private static func metrics(screens: [NSScreen] = NSScreen.screens) -> ScreenSetObservation {
        var scales: [String: CGFloat] = [:]
        for screen in screens {
            scales[DisplayCatalog.identifier(for: screen, screens: screens)] = screen.backingScaleFactor
        }
        return ScreenSetObservation(
            displays: DisplayCatalog.adjacencyGeometries(screens: screens),
            scales: scales,
            mirroring: isMirroring(screens: screens)
        )
    }

    private static func isMirroring(screens: [NSScreen]) -> Bool {
        for screen in screens {
            if let displayID = DisplayCatalog.displayID(for: screen), CGDisplayIsInMirrorSet(displayID) != 0 {
                return true
            }
        }
        return false
    }

    private func diagnose(_ event: String, _ fields: @autoclosure () -> [String: Any] = [:]) {
        guard StashDiagnostics.isEnabled else { return }
        var row = fields()
        row["systemSleeping"] = power.systemSleeping
        row["screensSleeping"] = power.screensSleeping
        row["waking"] = power.isWaking
        row["quiet"] = Self.isQuiet
        row["applying"] = Self.isApplying
        row["displays"] = Self.metrics().displays.map { display in
            ["id": display.id, "frame": [Double(display.frame.minX), Double(display.frame.minY),
                                          Double(display.frame.width), Double(display.frame.height)]] as [String: Any]
        }
        StashDiagnostics.record(event, row)
    }

}
