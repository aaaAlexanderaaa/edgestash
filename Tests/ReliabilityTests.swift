import Foundation
import EdgeStashLogic

func runReliabilityTests(_ expect: (Bool, String) -> Void) {
    // reliability capture admission and explicit input identity.
    let frame = CGRect(x: 10, y: 10, width: 600, height: 400)
    func admission(standard: Bool = true, minimized: Bool? = false, fullscreen: Bool? = false,
                   numbered: Bool = true, geometry: CGRect? = frame) -> Bool {
        StashSessionPolicy.mayCapture(isStandard: standard, minimized: minimized,
            fullScreen: fullscreen, hasWindowNumber: numbered, frame: geometry)
    }
    expect(admission(), "a controllable ordinary standard window can be captured")
    expect(!admission(standard: false) && !admission(minimized: true) && !admission(fullscreen: true),
           "dialogs, yellow-minimized and full-screen windows never enter capture")
    expect(!admission(minimized: nil) && !admission(fullscreen: nil) && !admission(numbered: false)
        && !admission(geometry: nil) && !admission(geometry: .zero),
           "unreadable state or identity cannot authorize an irreversible hide")
    expect(AppShortcutPolicy.shouldCaptureIdleFrontWindow(hasIdleWindow: true, hasManagedWindow: false),
           "the first application chord can capture an ordinary window")
    expect(!AppShortcutPolicy.shouldCaptureIdleFrontWindow(hasIdleWindow: true, hasManagedWindow: true)
        && AppShortcutPolicy.targetExpanded(hasVisibleWindow: false, hasHiddenWindow: true) == true,
           "five-window app with two stashes opens those stashes without capturing the other three")
    for action in AllStashedDockAction.allCases {
        expect(StashActivationPolicy.decision(kind: .unknown, hasOnDesktopWindow: false,
            allStandardWindowsStashed: true, allStashedDock: action) == .doNotOpenStash,
               "notification or unknown activation never borrows the all-stashed Cmd-Tab policy")
    }
    var intent = CommandTabIntent()
    expect(!intent.consume(now: 9), "activation alone has no keyboard intent")
    intent.note(timestamp: 10)
    expect(!intent.consume(now: 10.05), "holding the switcher does not authorize an unrelated activation")
    intent.observe(keyCode: 55, modifiers: 0, timestamp: 10.1, isModifierChange: true)
    expect(intent.consume(now: 10.2), "an observed Cmd-Tab authorizes one activation")
    intent.note(timestamp: 10)
    expect(!intent.consume(now: 10.3), "a duplicate late event cannot rearm a consumed intent")
    intent.note(timestamp: 11)
    intent.observe(keyCode: 55, modifiers: 0, timestamp: 11.1, isModifierChange: true)
    expect(!intent.consume(now: 12) && !intent.consume(now: 12.1), "stale intent expires without reuse")
    intent.note(timestamp: 11.9)
    expect(!intent.consume(now: 12.2), "a key callback queued before an observed activation cannot authorize a later one")
    intent.observe(keyCode: 48, modifiers: 1 << 20, timestamp: 20)
    intent.observe(keyCode: 53, modifiers: 1 << 20, timestamp: 20.1)
    intent.observe(keyCode: 55, modifiers: 0, timestamp: 20.2, isModifierChange: true)
    expect(!intent.consume(now: 20.3), "Escape cancels Cmd-Tab before a notification activates another app")
    intent.observe(keyCode: 48, modifiers: 1 << 20, timestamp: 21)
    intent.cancel(timestamp: 21.1)
    intent.observe(keyCode: 55, modifiers: 0, timestamp: 21.2, isModifierChange: true)
    expect(!intent.consume(now: 21.3), "a newer pointer gesture also cancels switcher intent")
    intent.note(timestamp: 22)
    intent.observe(keyCode: 56, modifiers: 0, timestamp: 22.1, isModifierChange: true)
    expect(!intent.consume(now: 22.2), "an unrelated modifier change is not a Command-release commit")
    intent.observe(keyCode: 55, modifiers: 0, timestamp: 24, isModifierChange: true)
    expect(!intent.consume(now: 24.1), "a missed release cannot preserve an old switch indefinitely")
    expect(CommandTabIntent.matches(keyCode: 48, modifiers: 1 << 20)
        && CommandTabIntent.matches(keyCode: 48, modifiers: (1 << 20) | (1 << 17))
        && !CommandTabIntent.matches(keyCode: 125, modifiers: 1 << 18),
           "forward/reverse Cmd-Tab are explicit; an arrow chord is not proof of system show-all")

    func candidate(_ id: UInt32, title: String = "same", managed: Bool = true,
                   collapsed: Bool = true, seam: Bool = false) -> DockThumbnailCandidate {
        DockThumbnailCandidate(windowID: id, title: title, isManaged: managed,
                               isCollapsed: collapsed, systemMinimize: seam)
    }
    expect(DockThumbnailPolicy.fallbackWindow(title: "same", candidates: [candidate(1)]) == 1,
           "a unique outer-window title can identify a thumbnail fallback")
    for sibling in [candidate(2), candidate(2, managed: false), candidate(2, collapsed: false)] {
        expect(DockThumbnailPolicy.fallbackWindow(title: "same", candidates: [candidate(1), sibling]) == nil,
               "identical titles cannot open an additional window, including ordinary/open siblings")
    }
    expect(DockThumbnailPolicy.fallbackWindow(title: "same", candidates: [candidate(1, seam: true)]) == nil,
           "system-minimized tiles wait for their exact deminiaturization signal")
    expect(DockThumbnailPolicy.focusedWindow(beforeClick: 1, now: 2,
                requestedTitle: "same", observedTitle: "same") == 2,
           "a verified focus transition identifies the exact second window despite duplicate titles")
    expect(DockThumbnailPolicy.focusedWindow(beforeClick: 1, now: 1,
                requestedTitle: "same", observedTitle: "same") == nil
        && DockThumbnailPolicy.focusedWindow(beforeClick: nil, now: 2,
                requestedTitle: "same", observedTitle: "same") == nil,
           "unchanged or unreadable pre-click focus cannot be mistaken for thumbnail destination")

    // reliability seam commit: execute the same ordered adapter used by live
    // named reveals and recovery, injecting failures rather than asserting a plan.
    for expanded in [false, true] {
        expect(WindowRecoveryPolicy.requiresSpacePreparation(expanded: expanded, minimized: true,
            previous: .systemMinimize, next: .slideOffscreen, ownsMinimize: false),
               "seam-to-outer conversion still confirms the display Space before any deminimize")
    }
    expect(!WindowRecoveryPolicy.requiresSpacePreparation(expanded: false, minimized: true,
        previous: .systemMinimize, next: .systemMinimize, ownsMinimize: true),
           "a healthy collapsed seam does not require a migration or visibility write")
    func replay(fail: String? = nil, changedAt: Int? = nil, compensation: Bool = true)
        -> (SeamRevealCommitResult, [String]) {
        var trace: [String] = []
        var observations = 0
        func write(_ name: String) -> Bool { trace.append(name); return fail != name }
        let result = SeamRevealCommit.perform(confirmsDestination: {
            observations += 1; trace.append("confirm")
            return observations != changedAt
        }, restoreOpacity: { write("alpha") }, deminimize: { write("deminimize") },
           placeFrame: { write("frame") }, reminimize: { trace.append("compensate"); return compensation })
        return (result, trace)
    }
    let success = replay()
    expect(success.0 == .succeeded && success.1 == ["confirm", "alpha", "deminimize", "confirm", "frame", "confirm"],
           "no frame or visibility write precedes current ordinary-Space membership confirmation")
    let refused = replay(changedAt: 1)
    expect(refused.0 == .keptMinimized && refused.1 == ["confirm"],
           "a refused/full-screen destination does not deminimize, place, or activate")
    for failure in ["deminimize", "frame"] {
        let run = replay(fail: failure)
        expect(run.0 == .keptMinimized && run.1.last == "compensate",
               "an uncertain visibility/frame write compensates before any expand commit")
    }
    for check in [2, 3] {
        expect(replay(changedAt: check).0 == .keptMinimized,
               "a destination change during AX writes cancels both normal and recovery reveals")
    }
    expect(replay(fail: "frame", compensation: false).0 == .releaseRequired,
           "failed compensation explicitly takes visibility-restoring release")

    var preparation = SeamRecoveryPreparation()
    let first = ScreenSetPlacement(windowNumber: 42, bundleID: "test.app", displayID: "one", edge: 0)
    let second = ScreenSetPlacement(windowNumber: 42, bundleID: "test.app", displayID: "two", edge: 1)
    let oldTicket = preparation.begin(first)
    preparation.select(first)
    expect(preparation.state == .pending, "repeated same-target selection retains its live completion")
    preparation.select(second)
    expect(preparation.state == .idle && preparation.target == second,
           "changing restoration placement cancels pending state before re-entry")
    let newTicket = preparation.begin(second)
    expect(!preparation.complete(oldTicket, target: first, result: .prepared(10)),
           "old placement completion cannot strand or complete a newer target")
    expect(preparation.complete(newTicket, target: second, result: .prepared(20))
        && preparation.state == .prepared(20), "the replacement target owns the completion that resumes its budget")
    preparation.cancel()
    expect(!preparation.complete(newTicket, target: second, result: .prepared(20)),
           "an environment cancellation rejects even the most recent old callback")
}
