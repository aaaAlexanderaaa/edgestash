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
    var onSettled: (() -> Void)?

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
        enterSleep()
    }

    func noteScreensDidWake(sessions: @escaping () -> [StashSession]) {
        // Display power can cycle without a system willSleep/didWake pair.
        // It still needs enumeration and a presentation refresh.
        noteDidWake(sessions: sessions, systemWake: false)
    }

    func noteScreensDidSleep() {
        power.screensDidSleep()
        if preSleepFingerprint == nil { preSleepFingerprint = committedFingerprint }
        beginQuiet()
        settleWork?.cancel()
        settleWork = nil
    }

    func noteDidWake(sessions: @escaping () -> [StashSession], systemWake: Bool = true) {
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
        sessionSource = sessions
        if power.blocksEnumeration {
            return
        }
        beginQuiet()
        rememberObservation()
        scheduleSettle()
    }

    func recordPlacement(of session: StashSession, sessions: [StashSession]) {
        guard !Self.blocksUserGeometry, let slot = session.screenSetSlot else { return }
        guard !reconcileUnannouncedTopology() else { return }
        restorationRetry.remove(slot.key)
        let preferences = Preferences.shared
        guard let next = memory?.recording(slot, live: sessions.compactMap(\.screenSetSlot),
                                          configurations: preferences.storedScreenSets),
              next != preferences.storedScreenSets else { return }
        preferences.storedScreenSets = next
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
        switch decision {
        case .waitLonger:
            Self.isQuiet = true
            scheduleSettle()
        case .keepPreSleep:
            clearWake()
            apply(snapshot: snapshot, keepMissingDisplay: knownBuiltinID)
        case .sameSet, .restoreConfigured, .increment, .applyClassified:
            clearWake()
            apply(snapshot: snapshot)
        }
    }

    private func clearWake() {
        power.settled()
        preSleepFingerprint = nil
        wakeSubsetSince = nil
    }

    private func apply(snapshot: ScreenSetObservation, keepMissingDisplay: String? = nil) {
        // An empty enumeration is not a desktop on which restoration can work.
        guard !snapshot.displays.isEmpty else { scheduleSettle(); return }
        let sessions = sessionSource?() ?? []
        let previousKey = memory?.memoryFingerprint
        let previousObservation = memory?.observation
        guard let plan = memory?.settle(
            on: snapshot,
            configurations: Preferences.shared.storedScreenSets,
            live: sessions.compactMap(\.screenSetSlot),
            keepMissingDisplay: keepMissingDisplay
        ) else { return }
        let sameMemory = previousKey != nil && previousKey == memory?.memoryFingerprint
        let targets = restorationRetry.beginApplication(
            restoring: plan.restore,
            retainingPending: sameMemory || previousObservation == snapshot
        ).filter { snapshot.fingerprint.displayIDs.contains($0.displayID) && !plan.release.contains($0.key) }

        Self.isApplying = true
        defer {
            Self.isApplying = false
            Self.isQuiet = false
            lastObserved = snapshot
            if let builtin = DisplayCatalog.builtinIdentifier() { knownBuiltinID = builtin }
            onSettled?()
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
                restorationRetry.failed(slot)
                continue
            }
            // Preserve the appearance (including pin) when it already belongs
            // to the target. Rebinding itself is synchronous, with no late
            // animation callback that can save a partly applied configuration.
            let succeeded = session.screenSetSlot == slot
                ? session.refreshCollapsePresentation()
                : session.applyScreenSetSlot(displayID: slot.displayID, edge: edge)
            applied.insert(slot.key)
            if succeeded {
                memory?.didRestore(slot)
                restorationRetry.remove(slot.key)
            }
            else {
                restorationRetry.failed(slot)
                toScatter.append(session)
            }
        }
        for session in sessions where session.isManaged {
            guard !toScatter.contains(where: { $0 === session }),
                  let slot = session.screenSetSlot,
                  !applied.contains(slot.key),
                  plan.refresh.contains(slot.key) || session.needsScreenSetRepair else { continue }
            if !session.refreshCollapsePresentation() {
                restorationRetry.failed(slot)
                toScatter.append(session)
            }
        }
        scatterLeavingStash(toScatter, on: snapshot.displays)
    }

    private func scheduleRestorationRetry() {
        retryWork?.cancel()
        guard let delay = restorationRetry.nextDelay() else { retryWork = nil; return }
        let work = DispatchWorkItem { [weak self] in self?.retryRestoration() }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func retryRestoration() {
        retryWork = nil
        guard !Self.blocksUserGeometry, !reconcileUnannouncedTopology(),
              let snapshot = memory?.observation else { return }
        let due = restorationRetry.due()
        guard !due.isEmpty else { scheduleRestorationRetry(); return }
        Self.isApplying = true
        defer {
            Self.isApplying = false
            onSettled?()
            scheduleRestorationRetry()
        }
        let sessions = sessionSource?() ?? []
        var failures: [StashSession] = []
        for slot in due {
            guard let edge = DisplayEdge(rawValue: slot.edge),
                  let session = sessions.first(where: { $0.bundleID == slot.bundleID && $0.windowID == slot.windowNumber }) else {
                restorationRetry.failed(slot)
                continue
            }
            if session.applyScreenSetSlot(displayID: slot.displayID, edge: edge) {
                memory?.didRestore(slot)
                restorationRetry.remove(slot.key)
            } else {
                restorationRetry.failed(slot)
                failures.append(session)
            }
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
            if let origin = origins[ObjectIdentifier(session)] {
                session.leaveStash(to: origin)
            } else if let fallback = displays.first {
                let origin = ScreenSetPolicy.scatterOrigins(
                    count: 1,
                    on: fallback.frame,
                    windowSize: session.restoreFrame?.size ?? CGSize(width: 640, height: 480)
                ).first ?? fallback.frame.origin
                session.leaveStash(to: origin)
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

}
