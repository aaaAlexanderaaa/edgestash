import CoreGraphics
import EdgeStashLogic

func runBackgroundObservationTests(_ expect: (Bool, String) -> Void) {
    // background_observation per-pass query bounds
    // Ninety stashes on three displays still perform three display queries
    // per poll. Every later poll must see the new Space/full-screen/error state.
    var totalReads = 0
    for poll in 0..<100 {
        var observations = SeamSpaceObservationBatch()
        var reads: [UInt32: Int] = [:]
        for window in 0..<90 {
            let displayID = UInt32(window % 3 + 1)
            let current: SeamSpaceAvailability
            switch poll % 3 {
            case 0: current = .ready(spaceID: UInt64(poll * 3) + UInt64(displayID))
            case 1: current = .disabledFullScreen
            default: current = .unavailable
            }
            let observed = observations.availability(for: displayID) {
                reads[displayID, default: 0] += 1
                totalReads += 1
                return current
            }
            expect(observed == current, "each poll reads the current state, including changed Space ids")
        }
        expect(reads == [1: 1, 2: 1, 3: 1], "display queries are bounded by displays, not stash count")
    }
    expect(totalReads == 300, "100 polls with 90 stashes make 300 display reads instead of 9000")

    var failedPass = SeamSpaceObservationBatch()
    _ = failedPass.availability(for: 7) { .unavailable }
    var nextPass = SeamSpaceObservationBatch()
    expect(nextPass.availability(for: 7) { .ready(spaceID: 88) } == .ready(spaceID: 88),
           "an unavailable observation never poisons the next poll")

    // A shared metadata list must preserve Space visibility and pointer
    // ownership as distinct questions: transparent slide windows stay listed.
    let frame = CGRect(x: 0, y: 0, width: 300, height: 200)
    let parked = WindowSurfaceHit(windowID: 5, pid: 11, frame: frame, alpha: 0)
    let visible = WindowSurfaceHit(windowID: 6, pid: 22, frame: frame)
    let snapshot = [parked, visible]
    expect(WindowSurfacePolicy.onScreenBounds(windowID: 5, pid: 11, in: snapshot) == frame,
           "a zero-alpha slide lip still proves presence on the current Space")
    expect(WindowSurfacePolicy.onScreenBounds(windowID: 5, pid: 22, in: snapshot) == nil,
           "metadata reuse still requires both the window id and its owner pid")
    expect(WindowSurfacePolicy.onScreenBounds(windowID: 7, pid: 11, in: snapshot) == nil,
           "an absent window cannot inherit another stash's Space visibility")
    expect(WindowSurfacePolicy.frontmostWindow(at: CGPoint(x: 50, y: 50), in: snapshot)?.windowID == 6,
           "transparent parked windows do not consume pointer ownership")
}
