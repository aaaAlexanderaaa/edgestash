import Foundation
import CoreGraphics
import EdgeStashLogic

func runStateMachineBoundaryTests(_ expect: (Bool, String) -> Void) {
    // MARK: state_machine failure and duplicate-event invariants.
    for event in [SessionLifecyclePolicy.Event.appQuitting, .appDisabled, .accessibilityLost, .miniaturized] {
        expect(!SessionLifecyclePolicy.shouldClearRescueRecords(
            for: event, restorePositionSucceeded: false,
            restoreAlphaSucceeded: false, restoreUnminimizeSucceeded: false,
            isFloating: true
        ), "idle after a failed release is not proof that the window became visible")
    }
    expect(!SessionLifecyclePolicy.shouldClearRescueRecords(
        for: .detachedFromEdge, restorePositionSucceeded: true,
        restoreAlphaSucceeded: false, isFloating: false
    ), "a user drag cannot clear rescue while the real window remains transparent")
    expect(!SessionLifecyclePolicy.shouldClearRescueRecords(
        for: .detachedFromEdge, restorePositionSucceeded: true,
        restoreUnminimizeSucceeded: false, isFloating: false
    ), "a detached seam still minimized needs its rescue record")
    expect(!SessionLifecyclePolicy.shouldRestoreAlpha(for: .appTerminated),
           "a dead process's recycled window number must not receive an alpha write")

    let slot = ScreenSetPlacement(windowNumber: 7, bundleID: "test.app", displayID: "external", edge: 1)
    let retryStart = Date(timeIntervalSince1970: 1_000)
    var retry = ScreenSetRestorationRetry()
    expect(retry.beginApplication(restoring: [slot], retainingPending: true) == [slot],
           "the first placement attempts immediately")
    retry.failed(slot, now: retryStart)
    for _ in 0..<20 {
        expect(retry.beginApplication(restoring: [slot], retainingPending: true).isEmpty,
               "duplicate observations cannot consume a scheduled retry")
    }
    expect(retry.nextDelay(now: retryStart) == 1 && retry.pending == [slot],
           "duplicate observations preserve the first retry and its budget")
    for (delay, elapsed) in [(2.0, 1.0), (4.0, 3.0)] {
        retry.failed(slot, now: retryStart.addingTimeInterval(elapsed))
        expect(retry.nextDelay(now: retryStart.addingTimeInterval(elapsed)) == delay,
               "timed failures advance the retry backoff")
    }
    retry.failed(slot, now: retryStart.addingTimeInterval(7))
    expect(retry.nextDelay(now: retryStart.addingTimeInterval(7)) == nil && retry.pending.isEmpty,
           "the initial attempt and three timed retries exhaust the budget")
    expect(retry.beginApplication(restoring: [slot], retainingPending: false) == [slot],
           "a genuinely different selected memory can begin a new restoration")

    var staggered = ScreenSetRestorationRetry()
    let secondSlot = ScreenSetPlacement(windowNumber: 17, bundleID: "test.app", displayID: "external", edge: 2)
    staggered.failed(slot, now: retryStart)
    staggered.failed(slot, now: retryStart.addingTimeInterval(1))
    staggered.failed(slot, now: retryStart.addingTimeInterval(3))
    staggered.failed(secondSlot, now: retryStart.addingTimeInterval(4))
    expect(staggered.nextDelay(now: retryStart.addingTimeInterval(4)) == 1
           && staggered.due(now: retryStart.addingTimeInterval(5)) == [secondSlot],
           "a newer short retry cannot spend another window's four-second retry early")
    staggered.remove(secondSlot.key)
    expect(staggered.beginApplication(restoring: [slot], retainingPending: true).isEmpty
           && staggered.nextDelay(now: retryStart.addingTimeInterval(6)) == 1
           && staggered.due(now: retryStart.addingTimeInterval(7)) == [slot],
           "a repeated observation keeps the original retry deadline")

    let laptop = DisplayGeometry(id: "laptop", frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    let external = DisplayGeometry(id: "external", frame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
    let one = ScreenSetObservation(displays: [laptop])
    let two = ScreenSetObservation(displays: [laptop, external])
    let left = ScreenSetPlacement(windowNumber: 8, bundleID: "test.app", displayID: "laptop", edge: 1)
    let right = ScreenSetPlacement(windowNumber: 9, bundleID: "test.app", displayID: "laptop", edge: 2)
    var memory = ScreenSetMemoryCoordinator(baseline: one)
    let increment = memory.settle(on: two, configurations: [], live: [left, right])
    expect(increment.event == .increment && increment.refresh == [right.key],
           "adding a neighbor leaves the unaffected outer edge alone but converts the newly shared edge")
    let duplicate = memory.settle(on: two, configurations: [], live: [left, right])
    expect(duplicate.event == .none && duplicate.refresh.isEmpty,
           "an unchanged display observation must not rewrite either window")

    var activations = OwnedActivationLedger()
    let activationTime = Date(timeIntervalSince1970: 100)
    activations.note(bundleID: "first.app", now: activationTime)
    activations.note(bundleID: "second.app", now: activationTime)
    expect(activations.consume(bundleID: "first.app", now: activationTime.addingTimeInterval(0.2))
           && activations.consume(bundleID: "second.app", now: activationTime.addingTimeInterval(0.3)),
           "show-all activations for different apps each remain classified as owned reveals")
    expect(!activations.consume(bundleID: "first.app", now: activationTime.addingTimeInterval(0.4)),
           "an owned activation is consumed at most once")
    expect(FocusReturnPolicy.shouldReturnFocus(sourcePID: 10, frontmostPID: 10),
           "collapse may return focus while its subject app is still frontmost")
    expect(!FocusReturnPolicy.shouldReturnFocus(sourcePID: 10, frontmostPID: 20)
           && !FocusReturnPolicy.shouldReturnFocus(sourcePID: 10, frontmostPID: nil),
           "a delayed focus-return callback cannot override a newer app switch")

    let old = [ScreenSetConfiguration(fingerprint: two.fingerprint, slots: [slot])]
    let fresh = ScreenSetMemoryCoordinator.startingFresh(old)
    expect(fresh.map(\.fingerprint) == old.map(\.fingerprint) && fresh.allSatisfy { $0.slots.isEmpty },
           "fresh launch retains configured screen sets without reusing dead window identities")
    var restarted = ScreenSetMemoryCoordinator(baseline: one)
    expect(restarted.settle(on: two, configurations: fresh, live: []).restore.isEmpty,
           "a recycled window number cannot inherit stash membership on the first replug after restart")

    func move(_ frame: CGRect, phase: StashSessionPhase = .expanded, dragged: Bool) -> ManagedGeometryAction {
        StashSessionPolicy.externalGeometryAction(
            phase: phase, presentation: .slideOffscreen, frame: frame,
            displayID: "laptop", edge: .left, displays: two.displays, wasDragged: dragged
        )
    }
    let center = CGRect(x: 200, y: 80, width: 480, height: 320)
    expect(move(CGRect(x: -478, y: 80, width: 480, height: 320), phase: .collapsed, dragged: false) == .none,
           "a correctly parked source window stays on its original display")
    expect(move(center, phase: .collapsed, dragged: false) == .repairHidden,
           "a late system nudge cannot delete a collapsed stash's placement")
    expect(move(center, phase: .collapsed, dragged: true) == .detach,
           "an actual Mission Control drag may release the hidden window")
    expect(move(CGRect(x: 960, y: 120, width: 480, height: 320), phase: .collapsed, dragged: true)
           == .rebind(displayID: "laptop", edge: .right),
           "a collapsed window dragged to the opposite edge keeps membership")
    expect(move(center, dragged: true) == .detach,
           "a visible window dragged onto the desktop leaves stash, including pinned windows")
    expect(move(CGRect(x: 960, y: 120, width: 480, height: 320), dragged: true) == .rebind(displayID: "laptop", edge: .right),
           "dragging to the opposite edge changes placement without losing membership")
    let destinationCenter = CGRect(x: 1640, y: 80, width: 480, height: 320)
    expect(move(destinationCenter, dragged: false) == .rebind(displayID: "external", edge: .left),
           "system move-to-display preserves the side despite its initially centered frame")
    expect(move(destinationCenter, phase: .collapsed, dragged: false)
           == .rebind(displayID: "external", edge: .left),
           "a system move of a collapsed window adopts the connected destination display")
    expect(StashSessionPolicy.externalGeometryAction(
        phase: .collapsed, presentation: .systemMinimize, frame: destinationCenter,
        displayID: "laptop", edge: .left, displays: two.displays, wasDragged: false
    ) == .rebind(displayID: "external", edge: .left),
           "a minimized seam window also adopts its system-selected destination")
    expect(move(CGRect(x: 962, y: 80, width: 480, height: 320), phase: .collapsed, dragged: true)
           == .rebind(displayID: "external", edge: .left),
           "a collapsed window's destination lip wins over its larger overlap with the old display")
    expect(move(destinationCenter, dragged: true) == .detach,
           "a desktop drag to another display is not a system-menu move")
    for (busy, quiet) in [(true, false), (false, true), (true, true)] {
        expect(StashSessionPolicy.externalGeometryAction(
            phase: .expanded, presentation: .slideOffscreen, frame: center,
            displayID: "laptop", edge: .left, displays: two.displays, wasDragged: true,
            isBusy: busy, screenSetQuiet: quiet
        ) == .none, "an in-flight operation or unsettled environment cannot commit a geometry-driven membership edit")
    }
    expect(StashSessionPolicy.externalGeometryAction(
        phase: .expanded, presentation: .slideOffscreen, frame: destinationCenter,
        displayID: "laptop", edge: .left, displays: [external], wasDragged: true
    ) == .none, "a missing owning display belongs to screen-set recovery, not user detach")

    // A prepared seam reveal can become stale while AX restores its frame.
    for membership in [true, false] {
        expect(!SpaceChangePolicy.mayCommitSeamReveal(targetSpaceID: 10, currentDisplaySpaceID: 11, membershipConfirmed: membership),
               "a changed display Space refuses commit even without a delivered notification")
    }
    for alpha in [true, false] {
        expect(!RescueMatching.recordIsSettled(moved: true, resized: true, alphaRestored: alpha, unminimized: false),
               "already-on-desktop geometry cannot settle a rescue while its seam window stays minimized")
    }

    let recordedAt = Date(timeIntervalSince1970: 100)
    expect(!RescueMatching.recordedProcessIsStillSame(bundleMatches: true, launchedAt: Date(timeIntervalSince1970: 101), recordedAt: recordedAt),
           "recycled PID from a later launch is not the recorded process")
    expect(!RescueMatching.recordedProcessIsStillSame(bundleMatches: false, launchedAt: Date(timeIntervalSince1970: 50), recordedAt: recordedAt),
           "a PID now owned by another app cannot receive rescue writes")
    expect(!RescueMatching.recordedProcessIsStillSame(bundleMatches: true, launchedAt: nil, recordedAt: recordedAt),
           "unknown process lifetime cannot authorize a number-only recovery")
    expect(RescueMatching.identify(
        recordedNumber: 7, recordedEdge: 1, recordedFrame: center,
        recordedDisplay: laptop.frame, among: [.init(windowID: 7, frame: center)],
        allowRecordedNumberMatch: false
    ) == .unresolved, "a new process's on-desktop window cannot be claimed by a recycled WindowServer number")
}
