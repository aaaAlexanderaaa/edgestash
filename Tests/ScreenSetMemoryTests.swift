import Foundation
import CoreGraphics
import EdgeStashLogic

/// Exercises the same coordinator used by the live adapter. Window operations
/// use an in-memory desktop, so this proves membership/memory, not AX success.
func runScreenSetMemoryTests(_ expect: (Bool, String) -> Void) {
    func display(_ id: String, _ x: CGFloat, _ y: CGFloat = 0, height: CGFloat = 1080) -> DisplayGeometry {
        DisplayGeometry(id: id, frame: CGRect(x: x, y: y, width: 1920, height: height))
    }
    func slot(_ number: UInt32, _ display: String, edge: Int = 1) -> ScreenSetPlacement {
        ScreenSetPlacement(windowNumber: number, bundleID: "test.app", displayID: display, edge: edge)
    }
    let desk = ScreenSetObservation(displays: [display("laptop", 0), display("external", 1920)])
    let laptop = ScreenSetObservation(displays: [display("laptop", 0)])
    let aDesk = slot(1, "external"), aLaptop = slot(1, "laptop")
    let b = slot(2, "laptop"), c = slot(3, "laptop")
    let deskConfig = ScreenSetConfiguration(fingerprint: desk.fingerprint, slots: [aDesk, b])
    let laptopConfig = ScreenSetConfiguration(fingerprint: laptop.fingerprint, slots: [aLaptop])

    // MARK: screen_set round-trip membership and memory invariants.
    do {
        var f = ScreenSetFixture(baseline: desk, configurations: [deskConfig, laptopConfig], live: [aDesk, b])
        let drop = f.move(to: laptop)
        expect(drop.event == .dropConfigured && f.members == [1], "configured shrink removes extras on surviving displays")
        f.record(aLaptop)
        expect(f.configuration(laptop) == laptopConfig, "appearance callbacks cannot import departed members")
        f.capture(c)
        let laptopEdited = f.configuration(laptop)
        for _ in 0..<100 {
            _ = f.move(to: desk)
            expect(f.members == [1, 2] && f.live[aDesk.key] == aDesk, "desk return restores exactly the desk's members and edges")
            f.record(b)
            expect(f.configuration(desk) == deskConfig, "desk reveal does not save a union of both configurations")
            _ = f.move(to: laptop)
            expect(f.members == [1, 3], "second unplug restores the separately edited laptop layout")
            f.record(aLaptop)
            expect(f.configuration(laptop) == laptopEdited, "repeated round trips preserve laptop memory")
        }
    }
    do {
        var f = ScreenSetFixture(baseline: desk, configurations: [deskConfig], live: [aDesk, b])
        _ = f.move(to: laptop)
        expect(f.members == [2], "unconfigured drop only displaces the vanished display's window")
        f.record(b)
        expect(f.configuration(laptop) == nil, "hover on an inherited stash does not configure a transient desktop")
        f.capture(c)
        expect(Set(f.configuration(laptop)?.slots.map(\.windowNumber) ?? []) == [2, 3], "first deliberate capture remembers carried stashes")
        _ = f.move(to: desk)
        expect(f.members == [1, 2], "return to desk excludes laptop-only capture")
        _ = f.move(to: laptop)
        expect(f.members == [2, 3], "laptop capture survives return and second unplug")
    }
    do {
        var f = ScreenSetFixture(baseline: laptop, configurations: [deskConfig, laptopConfig], live: [aLaptop])
        f.forget(aLaptop.key, everywhere: false)
        expect(f.configuration(laptop)?.slots.isEmpty == true, "empty configuration remains an explicit target")
        expect(f.configuration(desk) == deskConfig, "dragging out on laptop does not erase desk membership")
        _ = f.move(to: desk)
        expect(f.members == [1, 2], "desk membership returns after a laptop-only removal")
        _ = f.move(to: laptop)
        expect(f.members.isEmpty, "returning to empty laptop memory releases every extra stash")
        f.forget(aLaptop.key, everywhere: true)
        expect(f.configuration(desk)?.slots.contains(aDesk) == false, "window death forgets every memory")
    }
    do {
        var f = ScreenSetFixture(baseline: laptop, configurations: [deskConfig, laptopConfig], live: [aLaptop])
        _ = f.move(to: desk, failing: [aDesk.key])
        expect(f.members == [2], "failed restore has a usable unstashed fallback")
        f.record(b)
        f.capture(slot(2, "laptop", edge: 2))
        expect(f.configuration(desk)?.slots.contains(aDesk) == true, "another window's update preserves the failed target")
        _ = f.move(to: laptop)
        _ = f.move(to: desk)
        expect(f.members == [1, 2], "later return can retry a preserved failed target")
    }
    do {
        var f = ScreenSetFixture(baseline: desk, configurations: [deskConfig], live: [aDesk, b])
        let swapped = ScreenSetObservation(displays: [display("laptop", 1920), display("external", 0)])
        let outward = f.move(to: swapped)
        let back = f.move(to: desk)
        expect(outward.refresh == [aDesk.key, b.key] && back.refresh == [aDesk.key, b.key], "temporary relation change refreshes geometry in both directions")
        expect(f.coordinator.observation == desk && f.configuration(desk) == deskConfig, "live observation returns without changing intent")
        let shifted = ScreenSetObservation(displays: [display("laptop", 80, 40), display("external", 2000, 40)])
        expect(shifted.fingerprint == desk.fingerprint && shifted != desk, "settling compares full geometry, not just the memory fingerprint")
        expect(f.move(to: shifted).refresh == [aDesk.key, b.key], "global origin shift refreshes every retained stash")
    }
    do {
        let resized = ScreenSetObservation(displays: [display("laptop", 0), display("external", 1920, -360, height: 1440)])
        expect(resized.fingerprint != desk.fingerprint, "bottom-aligned resolution fixture changes origin relations")
        var f = ScreenSetFixture(baseline: desk, configurations: [deskConfig, laptopConfig], live: [aDesk, b])
        expect(f.move(to: resized).event == .scale && f.members == [1, 2], "resolution-induced relation change preserves membership")
        f.capture(c)
        expect(f.configurations.count == 2 && f.configuration(desk)?.slots.contains(c) == true, "scale writes keep the canonical memory key")
        _ = f.move(to: laptop)
        expect(f.move(to: resized).event == .returnConfigured && f.members == [1, 2, 3], "reconnect at the changed resolution resolves the original memory")
        expect(ScreenSetPolicy.classify(previous: desk.fingerprint, current: resized.fingerprint, configured: [desk.fingerprint], flags: ScreenSetClassifyFlags(scaleChanged: true)) == .scale, "scale beats the old frontmost-Settings rearrange hint")
        var absent = ScreenSetFixture(baseline: desk, configurations: [deskConfig, laptopConfig], live: [aDesk, b])
        _ = absent.move(to: laptop)
        expect(absent.move(to: resized).event == .returnConfigured && absent.members == [1, 2], "a display returning with a changed mode still finds its unambiguous memory")
    }
    do {
        var f = ScreenSetFixture(baseline: desk, configurations: [deskConfig, laptopConfig], live: [aDesk, b])
        let mirrored = ScreenSetObservation(displays: laptop.displays, mirroring: true)
        _ = f.move(to: mirrored)
        expect(f.members == [2], "projection does not load the laptop-only target")
        f.capture(c)
        expect(f.configurations == [deskConfig, laptopConfig], "mirrored desktop cannot overwrite normal memories")
        _ = f.move(to: desk)
        expect(f.members == [1, 2] && f.configuration(desk) == deskConfig, "ending projection restores the full desk target")
        let sameIDsMirror = ScreenSetObservation(displays: desk.displays, mirroring: true)
        _ = f.move(to: sameIDsMirror)
        expect(f.move(to: desk).event == .returnConfigured, "mirror exit restores even if visible display IDs did not change")
    }
    do {
        var f = ScreenSetFixture(baseline: desk, configurations: [], live: [aDesk])
        _ = f.move(to: laptop)
        expect(f.members.isEmpty, "missing owner is displaced even without a configured source")
        _ = f.move(to: desk)
        expect(f.live[aDesk.key] == aDesk, "unconfigured increment restores a displaced window when its display returns")
    }
    do {
        let before = Set(desk.fingerprint.displayIDs), after = Set(laptop.fingerprint.displayIDs)
        expect(ScreenSetSettlePolicy.wakeDecision(preSleepIDs: before, currentIDs: after, currentIsConfigured: true, onlyBuiltinMissing: false, subsetHoldElapsed: 1) == .waitLonger, "wake allows slow display enumeration")
        expect(ScreenSetSettlePolicy.wakeDecision(preSleepIDs: before, currentIDs: after, currentIsConfigured: true, onlyBuiltinMissing: false, subsetHoldElapsed: 5) == .applyClassified, "external absent after wake grace is a real drop")
        var f = ScreenSetFixture(baseline: desk, configurations: [deskConfig, laptopConfig], live: [aDesk, b])
        _ = f.move(to: laptop)
        expect(f.members == [1] && f.live[aLaptop.key] == aLaptop, "wake after unplug applies the usable laptop target")
        _ = f.move(to: desk)
        expect(f.members == [1, 2], "wake-after-unplug still preserves the original desk memory")
        let externalOnly = ScreenSetObservation(displays: [display("external", 0)])
        _ = f.move(to: externalOnly, keepMissing: "laptop")
        expect(f.members == [1, 2] && f.coordinator.memoryFingerprint == desk.fingerprint, "clamshell sleep retains built-in stash and pre-sleep memory")
    }
    do {
        let externalOnly = ScreenSetObservation(displays: [display("external", 0)])
        let externalConfig = ScreenSetConfiguration(fingerprint: externalOnly.fingerprint, slots: [slot(3, "external")])
        let configurations = [deskConfig, externalConfig]
        var f = ScreenSetFixture(baseline: desk, configurations: configurations, live: [aDesk, b])
        _ = f.move(to: externalOnly, keepMissing: "laptop")
        for _ in 0..<3 {
            let repeatObservation = f.move(to: externalOnly)
            expect(repeatObservation.release.isEmpty && repeatObservation.restore.isEmpty && f.members == [1, 2], "repeated closed-lid observations neither release held stashes nor load the external-only configuration")
        }
        let resized = ScreenSetObservation(displays: [display("external", 80, 40, height: 1440)])
        let scale = f.move(to: resized)
        expect(scale.event == .scale && scale.refresh == [aDesk.key] && f.members == [1, 2], "closed-lid scale refreshes the connected stash while retaining the built-in stash")
        _ = f.move(to: externalOnly)
        f.record(aDesk)
        expect(f.configurations == configurations && f.coordinator.memoryFingerprint == desk.fingerprint, "closed-lid geometry and appearance preserve the pre-sleep memory")
        _ = f.move(to: desk)
        expect(f.members == [1, 2], "opening the lid restores the full desk with the held member intact")
        let awakeDrop = f.move(to: externalOnly)
        expect(awakeDrop.event == .dropConfigured && f.members == [3], "a later awake lid close uses the external-only memory without a stale hold or cross-device scale alias")
    }
    do {
        let secondExternal = display("second-external", 3840)
        let three = ScreenSetObservation(displays: desk.displays + [secondExternal])
        let closedLid = ScreenSetObservation(displays: [display("external", 0), secondExternal])
        let third = slot(3, "second-external")
        let configuration = ScreenSetConfiguration(fingerprint: three.fingerprint, slots: [aDesk, b, third])
        let changedSets = [
            ScreenSetObservation(displays: [display("external", 0)]),
            ScreenSetObservation(displays: closedLid.displays + [display("new-external", 5760)]),
            ScreenSetObservation(displays: closedLid.displays, mirroring: true)
        ]
        for changed in changedSets {
            var f = ScreenSetFixture(baseline: three, configurations: [configuration], live: [aDesk, b, third])
            _ = f.move(to: closedLid, keepMissing: "laptop")
            _ = f.move(to: closedLid)
            let reflow = ScreenSetObservation(displays: [display("external", 3840), display("second-external", 0)])
            let rearranged = f.move(to: reflow)
            expect(rearranged.refresh == [aDesk.key, third.key] && f.members == [1, 2, 3], "rearranging the same external displays refreshes geometry without ending the clamshell hold")
            _ = f.move(to: closedLid)
            let transition = f.move(to: changed)
            expect(transition.release.contains(b.key) && !f.members.contains(2), "external connection or mirroring changes end the clamshell hold")
            expect(f.configuration(three) == configuration, "ending the clamshell hold preserves the departed memory")
        }
    }
    do {
        let frame = CGRect(x: 1920, y: 100, width: 800, height: 600)
        let original = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let temporary = CGRect(x: 0, y: -360, width: 1920, height: 1440)
        let moved = StashGeometryPolicy.screenSetFrame(frame: frame, previousDisplay: original, display: temporary, edge: .left)
        let restored = StashGeometryPolicy.screenSetFrame(frame: moved, previousDisplay: temporary, display: original, edge: .left)
        expect(restored == frame, "outward and return coordinate rebasing preserve display-relative position")
        let small = CGRect(x: 0, y: 0, width: 640, height: 480)
        expect(small.contains(StashGeometryPolicy.screenSetFrame(frame: frame, previousDisplay: original, display: small, edge: .right)), "scale keeps the entire requested frame on a small display")
    }
    do {
        let data = try! JSONEncoder().encode(deskConfig)
        expect((try? JSONDecoder().decode(ScreenSetConfiguration.self, from: data)) == deskConfig, "shared policy types retain the existing persisted shape")
    }
}

private struct ScreenSetFixture {
    var coordinator: ScreenSetMemoryCoordinator
    var configurations: [ScreenSetConfiguration]
    var live: [ScreenSetWindowKey: ScreenSetPlacement]
    var members: Set<UInt32> { Set(live.values.map(\.windowNumber)) }

    init(baseline: ScreenSetObservation, configurations: [ScreenSetConfiguration], live: [ScreenSetPlacement]) {
        coordinator = ScreenSetMemoryCoordinator(baseline: baseline)
        self.configurations = configurations
        self.live = Dictionary(uniqueKeysWithValues: live.map { ($0.key, $0) })
        _ = coordinator.settle(on: baseline, configurations: configurations, live: live)
    }

    @discardableResult
    mutating func move(to observation: ScreenSetObservation, failing: Set<ScreenSetWindowKey> = [], keepMissing: String? = nil) -> ScreenSetTransition {
        let plan = coordinator.settle(on: observation, configurations: configurations, live: Array(live.values), keepMissingDisplay: keepMissing)
        for key in plan.release { live.removeValue(forKey: key) }
        for slot in plan.restore {
            if failing.contains(slot.key) { live.removeValue(forKey: slot.key) }
            else { live[slot.key] = slot; coordinator.didRestore(slot) }
        }
        return plan
    }

    mutating func capture(_ slot: ScreenSetPlacement) {
        live[slot.key] = slot
        record(slot)
    }

    mutating func record(_ slot: ScreenSetPlacement) {
        configurations = coordinator.recording(slot, live: Array(live.values), configurations: configurations)
    }

    mutating func forget(_ key: ScreenSetWindowKey, everywhere: Bool) {
        live.removeValue(forKey: key)
        configurations = coordinator.forgetting(key, everywhere: everywhere, configurations: configurations)
    }

    func configuration(_ observation: ScreenSetObservation) -> ScreenSetConfiguration? {
        configurations.first { $0.fingerprint == observation.fingerprint }
    }
}
