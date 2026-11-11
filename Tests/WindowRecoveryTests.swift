import Foundation
import CoreGraphics
import EdgeStashLogic

func runWindowRecoveryTests(_ expect: (Bool, String) -> Void) {
    // MARK: window_recovery transport, exact identity and callback lifetime.
    expect(!WindowRecoveryPolicy.processConfirmedGone(exists: nil, terminated: false,
                bundleMatches: nil, launchMatches: nil),
           "missing workspace/process observations do not confirm process death")
    expect(!WindowRecoveryPolicy.processConfirmedGone(exists: true, terminated: false,
                bundleMatches: true, launchMatches: nil),
           "an unavailable launch date is not a changed process lifetime")
    for (exists, terminated, bundle, launch) in [
        (false, false, true, true), (true, true, true, true),
        (true, false, false, true), (true, false, true, false)
    ] {
        expect(WindowRecoveryPolicy.processConfirmedGone(exists: exists, terminated: terminated,
                    bundleMatches: bundle, launchMatches: launch),
               "positive process death, changed bundle or changed launch identity ends the old session")
    }
    func binding(_ matches: Int = 0, owner: WindowOwnerObservation = .owned,
                 enumerated: Bool = true, destroyed: Bool = false,
                 sameLaunch: Bool = true) -> WindowBindingDecision {
        WindowRecoveryPolicy.bindingDecision(sameProcessLifetime: sameLaunch,
            enumerationSucceeded: enumerated, matchingReferences: matches,
            owner: owner, destructionNotified: destroyed)
    }
    expect(binding() == .wait, "an invalid cached AX reference cannot erase a live window's membership")
    expect(binding(1) == .rebind, "one fresh exact window number in the same process can replace a stale reference")
    expect(binding(2) == .wait, "ambiguous fresh references cannot be rebound by choosing the first one")
    expect(binding(1, owner: .unavailable) == .wait && binding(1, owner: .absent) == .wait,
           "fresh AX alone cannot authorize a write to an unverified surface")
    expect(binding(owner: .absent) == .wait && binding(owner: .unavailable, destroyed: true) == .wait,
           "WindowServer absence or unavailability alone does not prove window death")
    expect(binding(owner: .absent, enumerated: false, destroyed: true) == .wait,
           "failed or partially unreadable AX enumeration is not proof of window absence")
    expect(binding(owner: .absent, destroyed: true) == .confirmedGone,
           "a destruction notification corroborated by fresh AX and metadata absence confirms close")
    expect(binding(1, owner: .differentProcess) == .confirmedGone,
           "a number reused by another process cannot inherit the stash or receive writes")
    expect(binding(1, sameLaunch: false) == .wait,
           "unknown or changed process lifetime cannot authorize number-only rebinding")
    expect(binding(1, destroyed: true) == .rebind,
           "a premature destroyed notification loses to positive fresh same-window evidence")
    for (bindingGeneration, lifecycle, accepted) in [(4 as UInt, 7, true), (3, 7, false), (4, 6, false), (3, 6, false)] {
        expect(WindowRecoveryPolicy.acceptsCallback(binding: bindingGeneration, currentBinding: 4,
                    lifecycle: lifecycle, currentLifecycle: 7) == accepted,
               "only the current binding and environment may deliver an AX callback")
    }

    let display = DisplayGeometry(id: "one", frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    let observation = ScreenSetObservation(displays: [display])
    let slots = (1...3).map { ScreenSetPlacement(windowNumber: UInt32($0), bundleID: "test.app", displayID: "one", edge: 1) }
    let configuration = ScreenSetConfiguration(fingerprint: observation.fingerprint, slots: slots)
    var memory = ScreenSetMemoryCoordinator(baseline: observation)
    var configurations = [configuration]
    var live = slots
    // Three stale handles, with all subject processes/windows still alive.
    // Exercise the actual death decision and memory operation as a timeline.
    for slot in slots {
        if binding(owner: .absent, enumerated: false) == .confirmedGone {
            configurations = memory.forgetting(slot.key, everywhere: true, configurations: configurations)
            live.removeAll { $0.key == slot.key }
        }
    }
    let wake = memory.settle(on: observation, configurations: configurations, live: live, afterWake: true)
    expect(live.count == 3 && configurations == [configuration] && wake.refresh == Set(slots.map(\.key)),
           "same-layout wake retains all three memberships through failed AX observations")
    expect(slots.allSatisfy { _ in binding(1) == .rebind } && wake.release.isEmpty,
           "fresh exact references repair all three windows without shortcut recapture")

    // MARK: window_recovery control waits preserve appearance and write budget.
    let visible = CGRect(x: 0, y: 50, width: 500, height: 400)
    let intent = ScreenSetRecoveryIntent(placement: slots[0], expanded: true, pinned: true,
                                        frame: visible, displayFrame: display.frame)
    var retry = ScreenSetRestorationRetry()
    let start = Date(timeIntervalSince1970: 1000)
    retry.waitForControl(slots[0], intent: intent, now: start)
    expect(retry.writeAttemptsRemaining(for: slots[0].key) == 4,
           "waiting retains the unspent initial attempt and all three retries")
    for elapsed in [1.0, 30, 300] {
        retry.waitForControl(slots[0], intent: ScreenSetRecoveryIntent(placement: slots[0]),
                             now: start.addingTimeInterval(elapsed))
        expect(retry.due(now: start.addingTimeInterval(elapsed)).isEmpty && retry.nextDelay(now: start) == nil,
               "an unavailable control path spends no AX write attempts and starts no extra polling clock")
    }
    expect(retry.intent(for: slots[0].key) == intent,
           "idle visible fallback preserves the original expanded pin and geometry independently")
    retry.controlBecameReady(slots[0].key, now: start.addingTimeInterval(301))
    expect(retry.due(now: start.addingTimeInterval(301)) == [slots[0]],
           "existing discovery resumes the still-unspent initial attempt")
    for (attempt, delay) in [1.0, 2, 4].enumerated() {
        let time = start.addingTimeInterval(302 + Double(attempt) * 10)
        retry.failed(slots[0], now: time)
        expect(retry.writeAttemptsRemaining(for: slots[0].key) == 3 - attempt,
               "diagnostic remaining-attempt counts track only actual failed writes")
        expect(retry.nextDelay(now: time) == delay, "only failed write attempts spend the 1/2/4 second retry budget")
        retry.waitForControl(slots[0], intent: intent, now: time)
        retry.controlBecameReady(slots[0].key, now: time.addingTimeInterval(5))
        expect(retry.intent(for: slots[0].key) == intent, "rebinding between attempts retains appearance")
    }
    retry.failed(slots[0], now: start.addingTimeInterval(400))
    expect(retry.writeAttemptsRemaining(for: slots[0].key) == 0,
           "the fourth failed write explicitly reports exhausted recovery")
    for _ in 0..<3 {
        retry.waitForControl(slots[0], intent: intent)
        retry.controlBecameReady(slots[0].key)
        expect(retry.nextDelay() == nil && retry.pending.isEmpty,
               "rediscovery cannot rearm an exhausted window's write budget")
    }
    expect(retry.beginApplication(restoring: [slots[0]], retainingPending: true).isEmpty,
           "duplicate same-layout notifications cannot rearm exhausted recovery")
    retry.remove(slots[0].key)
    expect(retry.intent(for: slots[0].key) == nil,
           "drag, recapture, disable, confirmed close and shutdown cancel retained intent")
    var earlyReady = ScreenSetRestorationRetry()
    earlyReady.failed(slots[0], intent: intent, now: start)
    earlyReady.waitForControl(slots[0], intent: intent, now: start)
    expect(earlyReady.nextDelay(now: start) == nil, "control waits do not run a backoff timer")
    earlyReady.controlBecameReady(slots[0].key, now: start.addingTimeInterval(0.1))
    expect(earlyReady.due(now: start.addingTimeInterval(0.1)).isEmpty
           && earlyReady.due(now: start.addingTimeInterval(1)) == [slots[0]],
           "quickly readable control cannot bypass the previous failed write's backoff deadline")
    expect(!ScreenSetRecoveryIntent(placement: slots[0], expanded: false, pinned: true).pinned,
           "collapsed recovery cannot accidentally restore a visible pin")

    // MARK: window_recovery healthy wake performs no presentation writes.
    let hidden = CGRect(x: -498, y: 50, width: 500, height: 400)
    let appearances: [(StashSessionPhase, StashCollapsePresentation, CGRect, CGRect?, Bool?, Float?)] = [
        (.expanded, .slideOffscreen, visible, visible, false, 1),
        (.collapsed, .slideOffscreen, hidden, hidden, false, 0),
        (.collapsed, .systemMinimize, visible, nil, true, nil)
    ]
    let writesNeeded = appearances.filter { phase, presentation, expected, actual, minimized, alpha in
        !WindowRecoveryPolicy.presentationMatches(phase: phase, presentation: presentation,
            expectedFrame: expected, actualFrame: actual, minimized: minimized, alpha: alpha)
    }.count
    expect(writesNeeded == 0, "healthy expanded, outer-hidden and minimized seam appearances skip wake writes")
    for (frame, minimized, alpha) in [(visible, false, Float(0)), (hidden, true, 0), (hidden, false, 1)] {
        expect(!WindowRecoveryPolicy.presentationMatches(phase: .collapsed, presentation: .slideOffscreen,
            expectedFrame: hidden, actualFrame: frame, minimized: minimized, alpha: alpha),
               "frame, minimized state and alpha all participate in wake presentation validation")
    }
    expect(!WindowRecoveryPolicy.presentationMatches(phase: .expanded, presentation: .slideOffscreen,
        expectedFrame: visible, actualFrame: nil, minimized: nil, alpha: nil),
           "unreadable presentation never counts as a successful repair")
    expect(!WindowRecoveryPolicy.presentationMatches(phase: .idle, presentation: .systemMinimize,
        expectedFrame: visible, actualFrame: nil, minimized: true, alpha: nil),
           "idle fallback is not a successfully collapsed stash merely because it is minimized")
    let centered = CGRect(x: 220, y: 50, width: 500, height: 400)
    for dragged in [false, true] {
        expect(StashSessionPolicy.externalGeometryAction(phase: .expanded, presentation: .slideOffscreen,
            frame: centered, displayID: display.id, edge: .left, displays: [display],
            wasDragged: dragged, minimized: false, recovering: true) == (dragged ? .detach : .repairHidden),
               "wake's system geometry retains expanded membership; an actual drag still leaves stash")
    }

    // MARK: window_recovery minimized coordinates cannot replace saved placement.
    let external = DisplayGeometry(id: "external", frame: CGRect(x: 1440, y: -300, width: 1920, height: 1080))
    let desktop = ScreenSetObservation(displays: [display, external])
    let seamSlots = (1...3).map {
        ScreenSetPlacement(windowNumber: UInt32($0), bundleID: "com.apple.Stickies",
                           displayID: external.id, edge: DisplayEdge.left.rawValue)
    }
    let remembered = ScreenSetConfiguration(fingerprint: desktop.fingerprint, slots: seamSlots)
    var seamMemory = ScreenSetMemoryCoordinator(baseline: desktop)
    _ = seamMemory.settle(on: desktop, configurations: [remembered], live: seamSlots)
    // Replays both a post-wake notification and one arriving after recovery
    // has already settled. The coordinates are injected, not native AX proof.
    for recovering in [true, false] {
        for phase in [StashSessionPhase.collapsed, .expanded] {
            for minimized in [Optional(true), nil] {
                for mouseDown in [false, true] {
                    for frame in [CGRect(x: 48, y: 40, width: 400, height: 300),
                                  CGRect(x: 0, y: 0, width: 1, height: 1)] {
                        let action = StashSessionPolicy.externalGeometryAction(
                            phase: phase, presentation: .systemMinimize, frame: frame,
                            displayID: external.id, edge: .left, displays: desktop.displays,
                            wasDragged: mouseDown, minimized: minimized, recovering: recovering)
                        expect(action == .ignore,
                               "minimized or unreadable state cannot rebind, detach or resize from primary-screen bounds")
                        var live = seamSlots
                        var saved = [remembered]
                        if case let .rebind(id, edge) = action {
                            live[0].displayID = id
                            live[0].edge = edge.rawValue
                            saved = seamMemory.recording(live[0], live: live, configurations: saved)
                        }
                        expect(live == seamSlots && saved == [remembered],
                               "late minimized geometry cannot overwrite any Stickies screen-set member")
                    }
                }
            }
        }
    }
    for phase in [StashSessionPhase.collapsed, .expanded] {
        expect(StashSessionPolicy.externalGeometryAction(
            phase: phase, presentation: .slideOffscreen, frame: centered,
            displayID: external.id, edge: .left, displays: desktop.displays,
            wasDragged: false, minimized: false, recovering: true) == .repairHidden,
               "recovery owns a system-relocated hidden or expanded window across displays")
    }
    let invalidFrames = [
        CGRect.zero, CGRect(x: 0, y: 0, width: -300, height: 200),
        CGRect(x: CGFloat.nan, y: 0, width: 300, height: 200),
        CGRect(x: 0, y: CGFloat.infinity, width: 300, height: 200),
        CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 200)
    ]
    for frame in invalidFrames {
        expect(!WindowRecoveryPolicy.isUsableFrame(frame) && !WindowRecoveryPolicy.framesMatch(frame, frame),
               "invalid AX geometry is neither a usable frame nor successful placement evidence")
        expect(StashSessionPolicy.externalGeometryAction(
            phase: .expanded, presentation: .slideOffscreen, frame: frame,
            displayID: display.id, edge: .left, displays: desktop.displays,
            wasDragged: true, minimized: false) == .ignore,
               "invalid geometry cannot replace a saved visible frame even during pointer input")
    }
    expect(WindowRecoveryPolicy.isUsableFrame(CGRect(x: -1200, y: -700, width: 300, height: 200)),
           "real displays above or left of the primary keep their valid negative coordinates")

    // MARK: window_recovery accepted writes wait for observed completion.
    // Field trace: accepted AXMinimized(true), immediate false, then true
    // about 0.6s later. The pending capture remains a shortcut target throughout.
    let confirmation = WindowWriteConfirmation(now: 100)
    var requests = StashPresentationCoordinator()
    requests.begin(StashPresentationRequest(expanded: false))
    for elapsed in [0.0, 0.1, 0.5] {
        expect(confirmation.observe(matches: false, now: 100 + elapsed) == .waiting,
               "an acknowledged hide with stale readback cannot fail capture or clear its rescue")
        expect(!requests.desiredExpanded(phase: .captured),
               "a pending minimize stays managed with a collapse target until another named request")
    }
    expect(requests.queue(StashPresentationRequest(expanded: true, fromDock: true)),
           "a shortcut received before minimize completion queues a reveal rather than recapturing")
    expect(confirmation.observe(matches: true, now: 100.624) == .confirmed,
           "the observed Stickies completion can commit without another minimize write")
    expect(requests.complete()?.expanded == true,
           "confirmed minimize returns the queued reveal to the existing transition executor")
    expect(confirmation.observe(matches: false, now: 101.5) == .expired,
           "a persistently unconfirmed hide leaves the busy gate through bounded recovery")
    expect(confirmation.observe(matches: false, now: 120) == .expired,
           "unknown or mismatched readback cannot renew its own confirmation deadline")
    expect(!confirmation.hasSettled(now: 100.624) && confirmation.hasSettled(now: 101.5),
           "reversing an unconfirmed hide cannot clear rescue on an immediate stale false read")

    var readbackRetry = ScreenSetRestorationRetry()
    let repaired = slots[0]
    readbackRetry.waitForControl(repaired, intent: ScreenSetRecoveryIntent(placement: repaired), now: start)
    for elapsed in [0.5, 1.0] {
        let time = start.addingTimeInterval(elapsed)
        readbackRetry.controlBecameReady(repaired.key, now: time)
        expect(readbackRetry.due(now: time) == [repaired], "the existing poll resumes readback confirmation")
        readbackRetry.waitForControl(repaired, intent: ScreenSetRecoveryIntent(placement: repaired), now: time)
        expect(readbackRetry.writeAttemptsRemaining(for: repaired.key) == 4,
               "read-only settling does not spend another placement attempt")
    }
    readbackRetry.failed(repaired, now: start.addingTimeInterval(1.5))
    expect(readbackRetry.writeAttemptsRemaining(for: repaired.key) == 3,
           "expired readback consumes exactly the initial failed attempt")
    for (alpha, elapsed, expected) in [(Float(1), 0.0, WindowWriteConfirmation.Result.waiting),
                                      (1, 0.5, .waiting), (0, 1.0, .confirmed), (1, 1.5, .expired)] {
        let matches = WindowRecoveryPolicy.presentationMatches(phase: .collapsed, presentation: .slideOffscreen,
            expectedFrame: hidden, actualFrame: hidden, minimized: false, alpha: alpha)
        expect(confirmation.observe(matches: matches, now: 100 + elapsed) == expected,
               "opacity lag waits, real zero confirms, persistent opaque parking still fails")
    }

    // MARK: window_recovery separate retry batches retain distinct fallbacks.
    var layout = ScreenSetFallbackLayout()
    let threeDisplays = [display, external,
        DisplayGeometry(id: "portrait", frame: CGRect(x: -1080, y: -1156, width: 1080, height: 1920))]
    let sizes = [CGSize(width: 372, height: 89), CGSize(width: 300, height: 145), CGSize(width: 300, height: 81)]
    let initial = slots.enumerated().compactMap { layout.origin(for: $0.element.key, size: sizes[$0.offset], on: threeDisplays) }
    expect(initial.count == 3 && Set(initial.map { "\($0.x),\($0.y)" }).count == 3,
           "three first fallbacks receive distinct origins across the current displays")
    for index in [0, 1, 2, 2, 1, 2] {
        expect(layout.origin(for: slots[index].key, size: sizes[index], on: threeDisplays.reversed()) == initial[index],
               "one-window retry batches and reordered enumeration cannot restart scatter at the primary origin")
    }
    let single = slots.enumerated().compactMap { layout.origin(for: $0.element.key, size: sizes[$0.offset], on: [display]) }
    expect(single.count == 3 && Set(single.map { "\($0.x),\($0.y)" }).count == 3
           && single.allSatisfy { display.frame.contains($0) },
           "a genuine display drop replaces stale destinations with distinct remaining-desktop origins")
    for index in [2, 0, 1] {
        expect(layout.origin(for: slots[index].key, size: sizes[index], on: [display]) == single[index],
               "later single-display retries keep each window's own landing point")
    }
    let tiny = DisplayGeometry(id: "tiny", frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let crowded = slots.compactMap { layout.origin(for: $0.key, size: CGSize(width: 372, height: 145), on: [tiny]) }
    expect(crowded.count == 3 && Set(crowded.map { "\($0.x),\($0.y)" }).count == 3
           && crowded.allSatisfy { tiny.frame.contains($0) },
           "oversized windows still receive distinct title-bar origins on the remaining desktop")
}
