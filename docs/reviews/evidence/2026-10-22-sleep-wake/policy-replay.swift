// Baseline audit from 2026-10-22, not a standing regression gate or an OS
// reproduction. The invalid-reference input is injected; these assertions
// document the current destructive policy and should change with its repair.
import Foundation
import CoreGraphics
import EdgeStashLogic

let displays = (0..<3).map { DisplayGeometry(id: "display-\($0)", frame: CGRect(x: $0 * 1920, y: 0, width: 1920, height: 1080)) }
let observation = ScreenSetObservation(displays: displays)
let slots = (0..<3).map { ScreenSetPlacement(windowNumber: UInt32(101 + $0), bundleID: "test.app.\($0)", displayID: displays[$0].id, edge: 1) }
var configurations = [ScreenSetConfiguration(fingerprint: observation.fingerprint, slots: slots)]
var coordinator = ScreenSetMemoryCoordinator(baseline: observation)
var retry = ScreenSetRestorationRetry()
var live = slots
let time = Date(timeIntervalSince1970: 100)
for slot in slots {
    retry.failed(slot, now: time)
    let event = SessionLifecyclePolicy.syncEndEvent(stashActive: true, isTemporary: false, processStillRunning: true, windowRoleInvalid: true)
    precondition(event == .windowDestroyed)
    configurations = coordinator.forgetting(slot.key, everywhere: true, configurations: configurations)
    retry.remove(slot.key)
    live.removeAll { $0.key == slot.key }
}
let wake = coordinator.settle(on: observation, configurations: configurations, live: live, afterWake: true)
let noInvalidity = SessionLifecyclePolicy.syncEndEvent(stashActive: true, isTemporary: false, processStillRunning: true, windowRoleInvalid: false)
let systemMovedExpanded = StashSessionPolicy.externalGeometryAction(phase: .expanded, presentation: .slideOffscreen, frame: CGRect(x: 500, y: 200, width: 640, height: 480), displayID: displays[0].id, edge: .left, displays: displays, wasDragged: false)
let result: [String: Any] = [
    "scope": "policy replay only; cached AX invalidity is injected, not an observed macOS wake",
    "injectedCachedReferencesInvalid": true,
    "processesStillRunning": true,
    "layoutChanged": false,
    "beforeRememberedMembers": slots.count,
    "afterRememberedMembers": configurations.flatMap(\.slots).count,
    "afterLiveManagedMembers": live.count,
    "remainingRetries": retry.pending.count,
    "sameLayoutWakeRestores": wake.restore.count,
    "sameLayoutWakeRefreshes": wake.refresh.count,
    "nonInvalidRoleKeepsSession": noInvalidity == nil,
    "expandedSameDisplaySystemMoveWithoutDrag": String(describing: systemMovedExpanded)
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
