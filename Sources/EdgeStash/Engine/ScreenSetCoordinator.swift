import AppKit
import CoreGraphics
import EdgeStashLogic

/// Live reaction to screen-set events. Policy classification stays in
/// `ScreenSetPolicy`; this type only reads AppKit facts and moves windows.
final class ScreenSetCoordinator {
    /// True while a classified event is applying, so user-leave slot writes
    /// and live-placement snapshots do not run for coordinator-driven moves.
    private(set) static var isApplying = false
    /// True while asleep, waking, or waiting for a topology to stop changing.
    private(set) static var isQuiet = false

    static var blocksUserGeometry: Bool { isApplying || isQuiet }

    private var committedFingerprint: ScreenSetFingerprint?
    private var committedBackingScales: [String: CGFloat] = [:]
    private var committedFrameSizes: [String: CGSize] = [:]
    private var committedMirroring = false
    private var lastObservedFingerprint: ScreenSetFingerprint?
    private var sleepingOrWaking = false
    private var wakePass = false
    private var preSleepFingerprint: ScreenSetFingerprint?
    private var settleWork: DispatchWorkItem?
    private var settleScheduledAt: Date?
    private var settleDelay: TimeInterval = 0
    private var wakeSubsetSince: Date?
    private var knownBuiltinID: String?
    private var sessionSource: (() -> [StashSession])?
    var onSettled: (() -> Void)?
    private var displaced: [DisplacedPlacement] = []

    static weak var active: ScreenSetCoordinator?

    private struct DisplacedPlacement: Equatable {
        var windowNumber: UInt32
        var bundleID: String
        var displayID: String
        var edge: Int
    }

    func captureBaseline() {
        Self.active = self
        commit(Self.metrics())
        Self.isQuiet = false
    }

    func invalidate() {
        settleWork?.cancel()
        settleWork = nil
        sessionSource = nil
        onSettled = nil
        sleepingOrWaking = false
        wakePass = false
        Self.isQuiet = false
        Self.active = nil
    }

    func beginQuiet() {
        Self.isQuiet = true
    }

    func noteWillSleep() {
        enterSleep()
    }

    func noteScreensDidWake(sessions: @escaping () -> [StashSession]) {
        guard sleepingOrWaking else { return }
        noteDidWake(sessions: sessions)
    }

    func noteDidWake(sessions: @escaping () -> [StashSession]) {
        sessionSource = sessions
        if preSleepFingerprint == nil {
            preSleepFingerprint = committedFingerprint
        }
        sleepingOrWaking = true
        wakePass = true
        Self.isQuiet = true
        rememberObservation()
        scheduleSettle()
    }

    func noteTopologyChanged(sessions: @escaping () -> [StashSession]) {
        sessionSource = sessions
        if sleepingOrWaking && !wakePass {
            return
        }
        Self.isQuiet = true
        rememberObservation()
        scheduleSettle()
    }

    func forgetDisplaced(windowNumber: UInt32, bundleID: String) {
        displaced.removeAll {
            $0.windowNumber == windowNumber && $0.bundleID == bundleID
        }
    }

    private func enterSleep() {
        settleWork?.cancel()
        settleWork = nil
        settleScheduledAt = nil
        wakeSubsetSince = nil
        if !sleepingOrWaking {
            preSleepFingerprint = committedFingerprint
        }
        sleepingOrWaking = true
        wakePass = false
        Self.isQuiet = true
    }

    private func rememberObservation() {
        lastObservedFingerprint = Self.metrics().fingerprint
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
        let snapshot = Self.metrics()
        let elapsed = settleScheduledAt.map { Date().timeIntervalSince($0) } ?? 0
        let decision = ScreenSetSettlePolicy.decision(
            sleepingAndNotWakePass: sleepingOrWaking && !wakePass,
            currentMatchesLastObserved: snapshot.fingerprint == lastObservedFingerprint,
            elapsedSinceScheduled: elapsed,
            scheduledDelay: settleDelay
        )
        switch decision {
        case .ignoreSleepBlip:
            settleWork = nil
            return
        case .sleptThrough:
            enterSleep()
            return
        case .reschedule:
            lastObservedFingerprint = snapshot.fingerprint
            scheduleSettle()
        case .apply:
            settleWork = nil
            settleScheduledAt = nil
            if wakePass {
                finishWake(snapshot: snapshot)
            } else {
                apply(from: committedFingerprint, snapshot: snapshot)
            }
        }
    }

    private func finishWake(snapshot: ScreenSetMetrics) {
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
            onlyBuiltinMissing: ScreenSetSettlePolicy.onlyBuiltinMissing(
                preSleepIDs: preIDs ?? [],
                currentIDs: currentIDs,
                builtinID: knownBuiltinID ?? DisplayCatalog.builtinIdentifier()
            ),
            subsetHoldElapsed: subsetHold
        )
        switch decision {
        case .sameSet:
            clearWake()
            refreshPresentStashes(sessions: sessionSource?() ?? [], snapshot: snapshot)
            commit(snapshot)
            Self.isQuiet = false
            onSettled?()
        case .waitLonger:
            sleepingOrWaking = true
            wakePass = true
            Self.isQuiet = true
            scheduleSettle()
        case .keepPreSleep:
            clearWake()
            refreshPresentStashes(sessions: sessionSource?() ?? [], snapshot: snapshot)
            commit(snapshot)
            Self.isQuiet = false
            onSettled?()
        case .restoreConfigured:
            clearWake()
            apply(from: baseline, snapshot: snapshot)
        case .increment:
            clearWake()
            apply(from: baseline, snapshot: snapshot)
        case .applyClassified:
            clearWake()
            apply(from: baseline, snapshot: snapshot)
        }
    }

    private func refreshPresentStashes(sessions: [StashSession], snapshot: ScreenSetMetrics) {
        let present = Set(snapshot.fingerprint.displayIDs)
        for session in sessions where session.isManaged {
            if let displayID = session.displayID, present.contains(displayID) {
                session.refreshCollapsePresentation()
            }
        }
    }

    private func clearWake() {
        sleepingOrWaking = false
        wakePass = false
        preSleepFingerprint = nil
        wakeSubsetSince = nil
    }

    private func apply(from previous: ScreenSetFingerprint?, snapshot: ScreenSetMetrics) {
        let current = snapshot.fingerprint
        let scaleChanged = previous == current
            && (committedBackingScales != snapshot.scales || committedFrameSizes != snapshot.sizes)
        let flags = ScreenSetClassifyFlags(
            isSleepingOrWaking: false,
            mirrorChanged: committedMirroring != snapshot.mirroring,
            scaleChanged: scaleChanged,
            userRearrangeLikely: Self.isDisplaySettingsFrontmost()
        )
        let event = ScreenSetPolicy.classify(
            previous: previous,
            current: current,
            configured: Preferences.shared.configuredFingerprints(),
            flags: flags
        )
        let sessions = sessionSource?() ?? []

        if event == .none || event == .sleep {
            if event == .none,
               let previous,
               previous.relations != current.relations,
               !flags.userRearrangeLikely {
                sessions.filter(\.isManaged).forEach { $0.refreshCollapsePresentation() }
                committedBackingScales = snapshot.scales
                committedFrameSizes = snapshot.sizes
                lastObservedFingerprint = current
                Self.isQuiet = false
                onSettled?()
                return
            }
            commit(snapshot)
            Self.isQuiet = false
            onSettled?()
            return
        }

        Self.isApplying = true
        defer {
            Self.isApplying = false
            commit(snapshot)
            Self.isQuiet = false
            onSettled?()
        }

        switch event {
        case .none, .sleep:
            break
        case .scale:
            sessions.filter(\.isManaged).forEach { $0.refreshCollapsePresentation() }
        case .increment:
            refreshPresentStashes(sessions: sessions, snapshot: snapshot)
        case .dropConfigured:
            applyDropConfigured(current: current, sessions: sessions)
            refreshPresentStashes(sessions: sessions, snapshot: snapshot)
        case .dropUnconfigured, .recover:
            applyDropUnconfigured(current: current, sessions: sessions)
            refreshPresentStashes(sessions: sessions, snapshot: snapshot)
        case .returnConfigured:
            applyReturnConfigured(current: current, sessions: sessions)
        case .cancel:
            if let previous {
                Preferences.shared.discardScreenSet(fingerprint: previous)
            }
            displaced.removeAll()
            scatterLeavingStash(sessions.filter(\.isManaged), on: Self.geometries())
        }
    }

    private func commit(_ snapshot: ScreenSetMetrics) {
        committedFingerprint = snapshot.fingerprint
        committedBackingScales = snapshot.scales
        committedFrameSizes = snapshot.sizes
        committedMirroring = snapshot.mirroring
        lastObservedFingerprint = snapshot.fingerprint
        if let builtin = DisplayCatalog.builtinIdentifier() {
            knownBuiltinID = builtin
        }
    }

    private func applyDropConfigured(
        current: ScreenSetFingerprint,
        sessions: [StashSession]
    ) {
        let remainingIDs = Set(current.displayIDs)
        let slots = Preferences.shared.slots(for: current)
        var toScatter: [StashSession] = []
        var consumed = Set<ObjectIdentifier>()

        for slot in slots {
            guard let edge = DisplayEdge(rawValue: slot.edge),
                  let session = session(matching: slot, in: sessions) else {
                continue
            }
            consumed.insert(ObjectIdentifier(session))
            if !session.applyScreenSetSlot(displayID: slot.displayID, edge: edge) {
                rememberDisplaced(
                    windowNumber: slot.windowNumber,
                    bundleID: slot.bundleID,
                    displayID: slot.displayID,
                    edge: slot.edge
                )
                toScatter.append(session)
            }
        }

        for session in sessions where session.isManaged && !consumed.contains(ObjectIdentifier(session)) {
            let displayGone = session.displayID.map { !remainingIDs.contains($0) } ?? true
            if displayGone {
                toScatter.append(session)
            }
        }
        scatterLeavingStash(toScatter, on: Self.geometries())
    }

    private func applyDropUnconfigured(
        current: ScreenSetFingerprint,
        sessions: [StashSession]
    ) {
        let remainingIDs = Set(current.displayIDs)
        var toScatter: [StashSession] = []
        for session in sessions where session.isManaged {
            if let displayID = session.displayID, remainingIDs.contains(displayID) {
                continue
            }
            rememberDisplaced(session: session)
            toScatter.append(session)
        }
        scatterLeavingStash(toScatter, on: Self.geometries())
    }

    private func applyReturnConfigured(current: ScreenSetFingerprint, sessions: [StashSession]) {
        let slots = Preferences.shared.slots(for: current)
        let presentIDs = Set(current.displayIDs)
        var toScatter: [StashSession] = []
        var restored = Set<SlotKey>()

        for slot in slots {
            guard let edge = DisplayEdge(rawValue: slot.edge) else { continue }
            let key = SlotKey(windowNumber: slot.windowNumber, bundleID: slot.bundleID)
            guard let session = session(matching: slot, in: sessions) else { continue }
            if presentIDs.contains(slot.displayID),
               session.applyScreenSetSlot(displayID: slot.displayID, edge: edge) {
                restored.insert(key)
                displaced.removeAll {
                    $0.windowNumber == slot.windowNumber && $0.bundleID == slot.bundleID
                }
            } else {
                rememberDisplaced(
                    windowNumber: slot.windowNumber,
                    bundleID: slot.bundleID,
                    displayID: slot.displayID,
                    edge: slot.edge
                )
                if session.isManaged {
                    toScatter.append(session)
                }
            }
        }

        for item in displaced where presentIDs.contains(item.displayID) {
            let key = SlotKey(windowNumber: item.windowNumber, bundleID: item.bundleID)
            guard !restored.contains(key),
                  let session = sessions.first(where: {
                      $0.bundleID == item.bundleID && $0.windowID == item.windowNumber
                  }),
                  let edge = DisplayEdge(rawValue: item.edge) else {
                continue
            }
            if session.applyScreenSetSlot(displayID: item.displayID, edge: edge) {
                restored.insert(key)
            } else if session.isManaged {
                toScatter.append(session)
            }
        }
        displaced.removeAll { restored.contains(SlotKey(windowNumber: $0.windowNumber, bundleID: $0.bundleID)) }
        scatterLeavingStash(toScatter, on: Self.geometries())
    }

    private func session(matching slot: StoredScreenSetSlot, in sessions: [StashSession]) -> StashSession? {
        sessions.first {
            $0.bundleID == slot.bundleID && $0.windowID == slot.windowNumber
        }
    }

    private func rememberDisplaced(session: StashSession, displayID: String? = nil, edge: Int? = nil) {
        guard let windowID = session.windowID else { return }
        rememberDisplaced(
            windowNumber: windowID,
            bundleID: session.bundleID,
            displayID: displayID ?? session.displayID ?? "",
            edge: edge ?? session.edge?.rawValue ?? DisplayEdge.left.rawValue
        )
    }

    private func rememberDisplaced(windowNumber: UInt32, bundleID: String, displayID: String, edge: Int) {
        guard !displayID.isEmpty else { return }
        displaced.removeAll { $0.windowNumber == windowNumber && $0.bundleID == bundleID }
        displaced.append(
            DisplacedPlacement(
                windowNumber: windowNumber,
                bundleID: bundleID,
                displayID: displayID,
                edge: edge
            )
        )
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

    private static func metrics(screens: [NSScreen] = NSScreen.screens) -> ScreenSetMetrics {
        let geometries = DisplayCatalog.adjacencyGeometries(screens: screens)
        let fingerprint = ScreenSetPolicy.fingerprint(displays: geometries)
        var scales: [String: CGFloat] = [:]
        var sizes: [String: CGSize] = [:]
        for screen in screens {
            let id = DisplayCatalog.identifier(for: screen, screens: screens)
            scales[id] = screen.backingScaleFactor
            sizes[id] = geometries.first { $0.id == id }?.frame.size ?? screen.frame.size
        }
        return ScreenSetMetrics(
            fingerprint: fingerprint,
            scales: scales,
            sizes: sizes,
            mirroring: isMirroring(screens: screens)
        )
    }

    private static func isDisplaySettingsFrontmost() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return id == "com.apple.systempreferences"
            || id == "com.apple.Settings"
            || id == "com.apple.preference.displays"
            || id.contains("Displays-Settings")
    }

    private static func isMirroring(screens: [NSScreen]) -> Bool {
        for screen in screens {
            if let displayID = DisplayCatalog.displayID(for: screen), CGDisplayIsInMirrorSet(displayID) != 0 {
                return true
            }
        }
        return false
    }

    private struct SlotKey: Hashable {
        var windowNumber: UInt32
        var bundleID: String
    }
}

private struct ScreenSetMetrics {
    var fingerprint: ScreenSetFingerprint
    var scales: [String: CGFloat]
    var sizes: [String: CGSize]
    var mirroring: Bool
}
