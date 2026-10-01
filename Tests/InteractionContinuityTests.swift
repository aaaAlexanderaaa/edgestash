import CoreGraphics
import Foundation
import EdgeStashLogic

func runInteractionContinuityTests(_ expect: (Bool, String) -> Void) {
    // MARK: stash_interaction dwell and cancellation invariants.
    let start = Date(timeIntervalSince1970: 1_000)
    var hover = HoverRevealCoordinator()
    let first = hover.updateTarget("A", now: start, delay: 0.15, buttonPressed: false)!
    for offset in [0.02, 0.04, 0.08, 0.12, 0.14] {
        expect(hover.updateTarget("A", now: start.addingTimeInterval(offset), delay: 0.15,
                                  buttonPressed: false) == nil && hover.pending == first,
               "motion within one merge segment retains the original dwell deadline")
    }
    expect(hover.consume(first, now: start.addingTimeInterval(0.1), buttonPressed: false) == nil,
           "a dwell cannot reveal before its deadline")
    expect(hover.consume(first, now: start.addingTimeInterval(0.16), buttonPressed: false) == "A",
           "continuous same-target motion still reveals at the original deadline")
    expect(hover.updateTarget("A", now: start.addingTimeInterval(0.4), delay: 0.15,
                              buttonPressed: false) == nil,
           "one hover visit cannot repeatedly reopen a recollapsed stash")
    _ = hover.updateTarget(nil, now: start, delay: 0.15, buttonPressed: false)
    let stale = hover.updateTarget("A", now: start, delay: 0.15, buttonPressed: false)!
    hover.click(targetID: "A", collapsing: true)
    expect(hover.consume(stale, now: start.addingTimeInterval(1), buttonPressed: false) == nil,
           "a click-collapse invalidates the previously scheduled hover reveal")
    expect(hover.updateTarget("A", now: start.addingTimeInterval(1), delay: 0.15,
                              buttonPressed: false) == nil,
           "a pointer parked after click-collapse cannot rearm hover")
    _ = hover.updateTarget(nil, now: start, delay: 0.15, buttonPressed: false)
    let reentered = hover.updateTarget("A", now: start, delay: 0.15, buttonPressed: false)!
    let switched = hover.updateTarget("B", now: start.addingTimeInterval(0.05), delay: 0.15,
                                     buttonPressed: false)!
    let back = hover.updateTarget("A", now: start.addingTimeInterval(0.1), delay: 0.15,
                                 buttonPressed: false)!
    expect(hover.consume(reentered, now: start.addingTimeInterval(1), buttonPressed: false) == nil
           && hover.consume(switched, now: start.addingTimeInterval(1), buttonPressed: false) == nil
           && hover.consume(back, now: start.addingTimeInterval(1), buttonPressed: false) == "A",
           "A-B-A visits reject old callbacks even when the final target ID matches")

    var drag = HoverRevealCoordinator()
    expect(drag.updateTarget("A", now: start, delay: 0, buttonPressed: true) == nil,
           "zero-delay hover cannot reveal during a mouse press")
    let duringDrag = drag.updateTarget("A", now: start, delay: 0.15, buttonPressed: false)!
    expect(drag.consume(duringDrag, now: start.addingTimeInterval(1), buttonPressed: true) == nil,
           "pressing during a pending dwell cancels the reveal")
    let mouseUp = drag.updateTarget("A", now: start.addingTimeInterval(1), delay: 0.15,
                                   buttonPressed: false)!
    expect(mouseUp.deadline == start.addingTimeInterval(1.15),
           "mouse-up rearms the same target with a fresh dwell")

    // MARK: focus_return operation ownership invariants.
    var focus = FocusReturnCoordinator()
    focus.beginOperation()
    let collapse = focus.schedule(phase: .collapsed)!
    focus.beginOperation()
    expect(!focus.consume(collapse, phase: .collapsed, busy: false),
           "reveal immediately after collapse cancels the previous focus return")
    focus.cancel()
    expect(focus.schedule(phase: .expanded) == nil,
           "user input during animation prevents a late completion scheduling focus return")
    focus.beginOperation()
    let reveal = focus.schedule(phase: .expanded)!
    focus.cancel()
    expect(!focus.consume(reveal, phase: .expanded, busy: false),
           "input, pin, detach, and shutdown can invalidate an already scheduled focus return")
    focus.beginOperation()
    let changedPhase = focus.schedule(phase: .expanded)!
    expect(!focus.consume(changedPhase, phase: .idle, busy: false),
           "an ended or changed session cannot consume the former phase's focus return")
    focus.beginOperation()
    let healthy = focus.schedule(phase: .collapsed)!
    expect(focus.consume(healthy, phase: .collapsed, busy: false)
           && !focus.consume(healthy, phase: .collapsed, busy: false),
           "an unchanged successful operation returns focus at most once")

    // MARK: pointer_sibling visible ownership invariants.
    let frame = CGRect(x: 200, y: 200, width: 300, height: 200)
    let pointer = CGPoint(x: 250, y: 250)
    let sibling = WindowSurfaceHit(windowID: 3, pid: 11, frame: frame)
    let covering = WindowSurfaceHit(windowID: 2, pid: 22, frame: frame)
    expect(!WindowSurfacePolicy.isPointerInSiblingWindow(pid: 11, excluding: 1, at: pointer,
                                                        in: [covering, sibling]),
           "a covered sibling cannot keep a stash open while the pointer uses another app")
    expect(WindowSurfacePolicy.isPointerInSiblingWindow(pid: 11, excluding: 1, at: pointer,
                                                       in: [sibling, covering]),
           "an actually topmost sibling retains the accepted leave grace")
    let own = WindowSurfaceHit(windowID: 1, pid: 11, frame: frame)
    expect(!WindowSurfacePolicy.isPointerInSiblingWindow(pid: 11, excluding: 1, at: pointer,
                                                        in: [own, sibling]),
           "the stash's own window is not a sibling interaction")
    let transparent = WindowSurfaceHit(windowID: 4, pid: 11, frame: frame, alpha: 0)
    expect(!WindowSurfacePolicy.isPointerInSiblingWindow(pid: 11, excluding: 1, at: pointer,
                                                        in: [transparent, covering, sibling]),
           "fully transparent parked windows are not pointer targets")
    let overlay = WindowSurfaceHit(windowID: 5, pid: 99, frame: frame, layer: 24)
    expect(WindowSurfacePolicy.frontmostWindow(at: pointer, in: [overlay, sibling])?.windowID == 3,
           "desktop decoration does not replace the underlying document pointer target")

    // MARK: stash_presentation latest target invariants.
    var presentation = StashPresentationCoordinator()
    let open = StashPresentationRequest(expanded: true, fromDock: true)
    let close = StashPresentationRequest(expanded: false, merged: true)
    presentation.begin(open)
    expect(presentation.desiredExpanded(phase: .collapsed),
           "a reveal in flight counts as the open target for a second toggle")
    expect(presentation.queue(close) && !presentation.desiredExpanded(phase: .collapsed),
           "a click during reveal retains its requested collapse")
    expect(presentation.complete() == close,
           "successful reveal completion executes the retained collapse target")
    presentation.begin(open)
    _ = presentation.queue(close)
    _ = presentation.queue(open)
    expect(presentation.complete() == nil,
           "two additional toggles returning to the active target require no extra animation")
    presentation.begin(close)
    for _ in 0..<100 { _ = presentation.queue(open) }
    expect(presentation.complete() == open && presentation.complete() == nil,
           "repeated input coalesces into exactly one newest request")
    presentation.begin(close)
    _ = presentation.queue(open)
    presentation.cancel()
    expect(presentation.complete() == nil && !presentation.queue(open),
           "Space, screen-set, release, and failure cancellation discard queued appearance work")
    presentation.begin(open)
    _ = presentation.queue(close)
    presentation.discardPending()
    expect(presentation.desiredExpanded(phase: .collapsed) && presentation.complete() == nil,
           "Space change discards queued input while preserving an outer slide's owned completion")
    presentation.begin(open)
    _ = presentation.queue(close)
    _ = presentation.complete()
    let completionRevision = presentation.revision
    presentation.begin(close)
    _ = presentation.complete()
    expect(presentation.revision != completionRevision,
           "a synchronous newer operation supersedes a target retained by an older completion")

    // MARK: marker_mouse_up preserves explicit target invariants.
    var clickedReveal = StashPresentationCoordinator()
    var markerHover = HoverRevealCoordinator()
    clickedReveal.begin(open)
    let canRearm = HoverRevealPolicy.shouldBegin(
        phase: .collapsed, isBusy: true, markerSuppressed: false,
        clickLocked: false, buttonPressed: false
    )
    if canRearm {
        _ = markerHover.updateTarget("A", now: start, delay: 0.15, buttonPressed: false)
    }
    _ = clickedReveal.queue(close) // Shortcut after the click's mouse-up.
    if let ticket = markerHover.pending,
       markerHover.consume(ticket, now: start.addingTimeInterval(0.2), buttonPressed: false) != nil {
        _ = clickedReveal.queue(open)
    }
    expect(markerHover.pending == nil && clickedReveal.complete() == close,
           "click reveal -> mouse-up -> shortcut close keeps the close at animation completion")
    expect(HoverRevealPolicy.shouldBegin(
        phase: .collapsed, isBusy: false, markerSuppressed: false,
        clickLocked: false, buttonPressed: false
    ), "mouse-up after a drag can still arm a settled collapsed marker")

    // MARK: merge_reveal named entry point invariants.
    var selection = MergeRevealSelection()
    selection.request("B") // Earlier merged hover/click.
    expect(selection.active(expandedIDs: ["B"], hoveredID: nil) == "B",
           "leaving the rail while a requested reveal finishes keeps its selection")
    selection.request("A") // Accepted named reveal outside the merged rail.
    expect(selection.active(expandedIDs: ["A", "B"], hoveredID: "B") == "A",
           "a newer named reveal replaces the old merged target before reconciliation")
    var delayedReveal = StashPresentationCoordinator()
    delayedReveal.begin(close)
    _ = delayedReveal.queue(open)
    selection.request("A")
    selection.request("B") // Newer request while A waits for its collapse.
    let replay = delayedReveal.complete()
    expect(replay == open && selection.active(expandedIDs: ["A", "B"], hoveredID: "A") == "B",
           "replaying an earlier queued reveal does not record it as a newer group request")
    expect(selection.active(expandedIDs: ["A", "B"], hoveredID: nil, pinnedID: "A") == "A",
           "new reveal requests preserve the existing pinned-member priority")

    for edge in DisplayEdge.allCases {
        let members = ["A", "B"].map {
            MergeMember(id: $0, edge: edge, screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                        visibleMinY: 200, visibleMaxY: 600, windowHeight: 400, title: $0,
                        presentation: .systemMinimize)
        }
        let group = MergeGroupPolicy.groups(from: members)[0]
        let layout = MergeGroupPolicy.layout(group: group, labelWidths: [80, 80])!
        let desktopTrack = layout.trackRect.offsetBy(dx: layout.panelFrame.minX, dy: layout.panelFrame.minY)
        let compact = MergeGroupPolicy.presentation(layout: layout, showingLabels: false)
        expect(group.screenFrame.contains(desktopTrack) && group.screenFrame.contains(compact.windowFrame)
               && compact.windowFrame.width == MergeGroupPolicy.mouseOpaqueWidth,
               "merged seam rail and its 21pt interactive window stay on the owning display")
        expect(edge == .left ? desktopTrack.minX == 2 : desktopTrack.maxX == 1438,
               "merged seam glass retains the accepted two-point inward clearance")
    }
}
