import Foundation
import CoreGraphics
import EdgeStashLogic

func runScreenSetOrderTests(_ expect: (Bool, String) -> Void) {
    // MARK: screen_set connection order preserves the configured destination.
    // Each intermediate observation can settle separately or be coalesced into
    // the next one. These are policy replays, not physical display/AX evidence.
    let displays = (0..<3).map { index in
        DisplayGeometry(id: "screen-\(index)",
                        frame: CGRect(x: index * 1920, y: 0, width: 1920, height: 1080))
    }
    func observation(_ mask: Int, variant: Int = 0) -> ScreenSetObservation {
        let connected = displays.enumerated().compactMap { index, display -> DisplayGeometry? in
            guard mask & (1 << index) != 0 else { return nil }
            var frame = display.frame
            switch variant {
            case 1: frame.origin.x += 80; frame.origin.y += 40
            case 2: frame.origin.x = 3840 - frame.minX
            case 3: frame.origin.y -= 360; frame.size.height = 1440
            default: break
            }
            return DisplayGeometry(id: display.id, frame: frame)
        }
        return ScreenSetObservation(displays: variant % 2 == 0 ? connected : connected.reversed())
    }
    func placement(_ number: Int, on display: String, edge: Int = 1) -> ScreenSetPlacement {
        ScreenSetPlacement(windowNumber: UInt32(number), bundleID: "order.test", displayID: display, edge: edge)
    }
    let destination = observation(7)
    let desired = displays.enumerated().flatMap { index, display in
        [placement(index * 2 + 1, on: display.id), placement(index * 2 + 2, on: display.id, edge: 2)]
    }
    let fullConfiguration = ScreenSetConfiguration(fingerprint: destination.fingerprint, slots: desired)
    let expected = Dictionary(uniqueKeysWithValues: desired.map { ($0.key, $0) })
    var cases = 0
    var violation: String?

    // All 64 choices of which proper nonempty subsets have their own memory.
    // Subset memories deliberately relocate members and contain an extra that
    // the final configuration must release, rather than merely unioning lists.
    for configuredSubsets in 0..<64 {
        var configurations = [fullConfiguration]
        for mask in 1..<7 where configuredSubsets & (1 << (mask - 1)) != 0 {
            let subset = observation(mask)
            let first = subset.displays[0].id
            let slots = desired.filter { $0.windowNumber % 2 == 1 }.map {
                placement(Int($0.windowNumber), on: first, edge: 2)
            } + [placement(100 + mask, on: first)]
            configurations.append(ScreenSetConfiguration(fingerprint: subset.fingerprint, slots: slots))
        }
        for anchor in 0..<3 {
            let others = (0..<3).filter { $0 != anchor }
            for removedFirst in others {
                for addedFirst in others {
                    let masks = [7 & ~(1 << removedFirst), 1 << anchor,
                                 (1 << anchor) | (1 << addedFirst), 7]
                    // The last observation always settles. Each earlier one
                    // independently can be shorter or longer than the grace.
                    for settledIntermediates in 0..<8 {
                        for failureMode in 0..<3 {
                            cases += 1
                            var fixture = ScreenOrderFixture(baseline: destination,
                                                             configurations: configurations, live: desired)
                            let isWake = cases % 2 == 0
                            for (step, mask) in masks.enumerated() {
                                guard step == 3 || settledIntermediates & (1 << step) != 0 else { continue }
                                let failed: Set<ScreenSetWindowKey>
                                if step == 3 || failureMode == 0 {
                                    failed = []
                                } else if failureMode == 1 {
                                    failed = [desired[(cases + step) % desired.count].key]
                                } else {
                                    failed = Set(configurations.flatMap(\.slots).map(\.key))
                                }
                                _ = fixture.move(to: observation(mask), failing: failed, afterWake: isWake)
                                if step != 3 {
                                    // Provisional origin, arrangement and mode
                                    // changes must not rewrite any memory.
                                    _ = fixture.move(to: observation(mask, variant: 1 + cases % 3),
                                                     failing: failed, afterWake: isWake)
                                }
                                // Ordinary reveal/pin/collapse callbacks are
                                // not deliberate placement changes.
                                for slot in Array(fixture.live.values) { fixture.record(slot) }
                            }
                            if fixture.live != expected || fixture.configurations != configurations
                                || fixture.memory.memoryFingerprint != destination.fingerprint {
                                violation = violation ?? "subsets=\(configuredSubsets), anchor=\(anchor), remove=\(removedFirst), add=\(addedFirst), settled=\(settledIntermediates), failures=\(failureMode)"
                            }
                            let duplicate = fixture.move(to: destination)
                            if !duplicate.restore.isEmpty || !duplicate.release.isEmpty || !duplicate.refresh.isEmpty {
                                violation = violation ?? "duplicate final observation repeated a mutation after case \(cases)"
                            }
                        }
                    }
                }
            }
        }
    }
    expect(violation == nil, "all \(cases) three-display connection timelines restore exact destination membership and preserve every memory; first violation: \(violation ?? "none")")
    print("Screen-set order: \(cases) configured round-trip timelines, \(violation == nil ? "passed" : "FAILED")")

    // The eventual destination may be a configured singleton, pair or triple.
    // Visit every other nonempty subset before returning to that destination.
    var returnCases = 0
    var returnViolation: String?
    for targetMask in 1...7 {
        let target = observation(targetMask)
        let targetSlots = desired.filter { target.fingerprint.displayIDs.contains($0.displayID) }
        let targetConfiguration = ScreenSetConfiguration(fingerprint: target.fingerprint, slots: targetSlots)
        let targetExpected = Dictionary(uniqueKeysWithValues: targetSlots.map { ($0.key, $0) })
        for first in 1...7 where first != targetMask {
            for second in 1...7 where second != targetMask {
                for third in 1...7 where third != targetMask {
                    returnCases += 1
                    var fixture = ScreenOrderFixture(baseline: target, configurations: [targetConfiguration], live: targetSlots)
                    for mask in [first, second, third, targetMask] { _ = fixture.move(to: observation(mask)) }
                    if fixture.live != targetExpected || fixture.configurations != [targetConfiguration] {
                        returnViolation = returnViolation ?? "destination=\(targetMask), path=\([first, second, third, targetMask])"
                    }
                }
            }
        }
    }
    expect(returnViolation == nil, "all \(returnCases) nonempty-subset return paths restore their configured destination; first violation: \(returnViolation ?? "none")")
    print("Screen-set order: \(returnCases) singleton/pair/triple return timelines, \(returnViolation == nil ? "passed" : "FAILED")")

    // Input enumeration order is independently irrelevant to both the full
    // geometry observation and the memory key.
    for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
        let reordered = ScreenSetObservation(displays: order.map { displays[$0] })
        expect(reordered == destination && reordered.fingerprint == destination.fingerprint,
               "display enumeration permutation \(order) is the same observation and memory")
    }

    // A slow wake can really settle a subset; a quick one must wait. These
    // decisions use the live adapter's policy and exact current grace bounds.
    for subsetMask in 1..<7 {
        let subset = observation(subsetMask)
        let ids = Set(subset.fingerprint.displayIDs)
        let fullIDs = Set(destination.fingerprint.displayIDs)
        expect(ScreenSetSettlePolicy.wakeDecision(preSleepIDs: fullIDs, currentIDs: ids,
            currentIsConfigured: false, onlyBuiltinMissing: false,
            subsetHoldElapsed: ScreenSetSettlePolicy.wakeSubsetGrace - 0.01) == .waitLonger,
               "an incomplete wake subset still within grace waits for more displays")
        expect(ScreenSetSettlePolicy.wakeDecision(preSleepIDs: fullIDs, currentIDs: ids,
            currentIsConfigured: false, onlyBuiltinMissing: false,
            subsetHoldElapsed: ScreenSetSettlePolicy.wakeSubsetGrace) == .applyClassified,
               "a subset beyond grace is processed without forgetting the full destination")
    }
}

private struct ScreenOrderFixture {
    var memory: ScreenSetMemoryCoordinator
    var configurations: [ScreenSetConfiguration]
    var live: [ScreenSetWindowKey: ScreenSetPlacement]

    init(baseline: ScreenSetObservation, configurations: [ScreenSetConfiguration], live: [ScreenSetPlacement]) {
        memory = ScreenSetMemoryCoordinator(baseline: baseline)
        self.configurations = configurations
        self.live = Dictionary(uniqueKeysWithValues: live.map { ($0.key, $0) })
        _ = memory.settle(on: baseline, configurations: configurations, live: live)
    }

    mutating func move(to observation: ScreenSetObservation, failing: Set<ScreenSetWindowKey> = [],
                       afterWake: Bool = false) -> ScreenSetTransition {
        let plan = memory.settle(on: observation, configurations: configurations,
                                 live: Array(live.values), afterWake: afterWake)
        for key in plan.release { live.removeValue(forKey: key) }
        for slot in plan.restore {
            if failing.contains(slot.key) { live.removeValue(forKey: slot.key) }
            else { live[slot.key] = slot; memory.didRestore(slot) }
        }
        return plan
    }

    mutating func record(_ slot: ScreenSetPlacement) {
        configurations = memory.recording(slot, live: Array(live.values), configurations: configurations)
    }
}
