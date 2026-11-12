// The runner inserts selected current StashSession methods into this boundary
// harness. AX, UI, completion hooks and monotonic time are injected. This is
// adapter control-flow evidence, not native macOS behavior or full-session proof.
import Foundation
import EdgeStashLogic

enum ReplayClock { static var now: TimeInterval = 100 }
enum StashAX {
    static var minimized: Bool? = false
    static var acknowledged = true
    static var frame = CGRect(x: -498, y: 50, width: 500, height: 400)
    static var writes: [Bool] = []
    static func isMinimized(_ element: Int) -> Bool? { minimized }
    static func requestMinimized(_ element: Int, _ value: Bool) -> Bool {
        writes.append(value)
        return acknowledged
    }
    static func frame(of element: Int) -> CGRect? { frame }
}
struct StashRecoverySurface { var windowID: UInt32; var pid: Int; var alpha: Float? }
enum DisplayCatalog { static func screen(withID id: String) -> Int? { 1 } }
enum ScreenSetApplicationResult: Equatable { case succeeded, waitingForControl, waitingForPersistence, blockedSpace, failed }
final class ScreenSetCoordinator {
    static let active: ScreenSetCoordinator? = ScreenSetCoordinator()
    var waits = 0
    func waitForControl(of session: StashSession) { waits += 1 }
}
final class PinWindow { func conceal() {} }
final class StashSession {
    let windowElement = 1
    let windowID: UInt32? = 1976
    let pid = 555
    let pinWindow = PinWindow()
    var phase: StashSessionPhase = .captured
    var presentation: StashCollapsePresentation? = .systemMinimize
    var busy = true
    var awaitingWindowControl = false
    var edge: DisplayEdge? = .left
    var displayID: String? = "external"
    var isPinned = false
    var markerHiddenForSpace = false
    var restoreFrame: CGRect? = CGRect(x: 1440, y: -100, width: 500, height: 400)
    var rescueDisplayFrame: CGRect? = CGRect(x: 1440, y: -300, width: 1920, height: 1080)
    var pendingScreenSetRecovery: ScreenSetRecoveryIntent?
    var recoverySpacePreparation = SeamRecoveryPreparation()
    var presentationRequests = StashPresentationCoordinator()
    var desiredPresentationIsExpanded: Bool { presentationRequests.desiredExpanded(phase: phase) }
    var pendingMinimize: (confirmation: WindowWriteConfirmation, next: StashSessionPhase, frame: CGRect, merged: Bool)?
    var pendingPresentation: (confirmation: WindowWriteConfirmation, phase: StashSessionPhase,
                              presentation: StashCollapsePresentation, frame: CGRect)?
    var pendingMinimizeRelease: WindowWriteConfirmation?
    var unconfirmedOwnedMinimize = true
    var onControlReady: ((StashSession) -> Void)?
    var collapsed = 0
    var repaired = 0
    var releases = 0
    var pauses = 0
    var latestRequest: StashPresentationRequest?
    var surfaces = [StashRecoverySurface(windowID: 1976, pid: 555, alpha: 1)]
    var isIdle: Bool { phase == .idle }
    var screenSetSlot: ScreenSetPlacement? {
        ScreenSetPlacement(windowNumber: windowID!, bundleID: "com.apple.Stickies", displayID: displayID!, edge: edge!.rawValue)
    }
    func diagnose(_ event: String, _ fields: [String: Any] = [:]) {}
    func retainRecoveryIntent(_ intent: ScreenSetRecoveryIntent) { pendingScreenSetRecovery = intent }
    func markWindowControlUnavailable() { awaitingWindowControl = true; busy = false }
    func finishCollapse(next: StashSessionPhase, frame: CGRect, merged: Bool) {
        collapsed += 1; phase = next; busy = false; latestRequest = presentationRequests.complete()
    }
    func finishScreenSetRepair() { repaired += 1; pendingScreenSetRecovery = nil }
    func deferPendingPresentation(_ request: StashPresentationRequest?, revision: UInt) { latestRequest = request }
    func shutdown(event: SessionLifecyclePolicy.Event) { releases += 1 }
    func prepareForScreenSetChange(invalidateSpacePreparation: Bool) { pauses += 1 }
    func reconcileScreenSetPresentation(inspectFirst: Bool = false) -> ScreenSetApplicationResult {
        confirmScreenSetPresentation(readWindows: { self.surfaces })
    }

    // INSERT_CURRENT_SESSION_METHODS
}

extension StashSession {
    static func run(_ expect: (Bool, String) -> Void) {
        let frame = CGRect(x: 1440, y: -100, width: 500, height: 400)
        func capturing() -> StashSession {
            ReplayClock.now = 100
            StashAX.minimized = false
            StashAX.acknowledged = true
            StashAX.writes = []
            let session = StashSession()
            session.pendingMinimize = (WindowWriteConfirmation(now: 100), .collapsed, frame, false)
            session.presentationRequests.begin(StashPresentationRequest(expanded: false))
            return session
        }
        let capture = capturing()
        for time in [100.0, 100.5] {
            ReplayClock.now = time
            _ = capture.reconcilePendingWindowWrites()
            expect(capture.busy && capture.phase == .captured && capture.collapsed == 0,
                   "stale false retains managed capture and busy gate")
        }
        _ = capture.presentationRequests.queue(StashPresentationRequest(expanded: true))
        ReplayClock.now = 100.624
        StashAX.minimized = true
        _ = capture.reconcilePendingWindowWrites()
        expect(capture.collapsed == 1 && !capture.busy && !capture.unconfirmedOwnedMinimize,
               "late actual minimize commits exactly once")
        expect(capture.latestRequest?.expanded == true && StashAX.writes.isEmpty,
               "confirmation forwards latest request without repeating hide")

        let expired = capturing()
        _ = expired.presentationRequests.queue(StashPresentationRequest(expanded: true))
        ReplayClock.now = 101.5
        _ = expired.reconcilePendingWindowWrites()
        expect(expired.awaitingWindowControl && !expired.busy && expired.releases == 0,
               "expiry hands control to recovery without releasing")
        expect(expired.pendingScreenSetRecovery?.expanded == true && expired.unconfirmedOwnedMinimize,
               "expiry preserves latest reveal intent and visibility debt")

        let recovery = StashSession()
        recovery.phase = .collapsed
        recovery.pendingPresentation = (WindowWriteConfirmation(now: 100), .collapsed, .slideOffscreen, StashAX.frame)
        ReplayClock.now = 100.5
        let originalRestore = recovery.restoreFrame
        let oldIntent = ScreenSetRecoveryIntent(placement: recovery.screenSetSlot!, frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        expect(recovery.applyScreenSetSlot(displayID: "external", edge: .left, intent: oldIntent) == .waitingForControl,
               "opaque recovery readback waits")
        expect(recovery.restoreFrame == originalRestore && recovery.pauses == 0 && recovery.phase == .collapsed,
               "read-only retry cannot reset rebased geometry or phase")
        var ready = 0
        recovery.onControlReady = { _ in ready += 1 }
        _ = recovery.reconcilePendingWindowWrites()
        expect(ready == 1 && recovery.repaired == 0, "existing observation resumes the retry owner")
        let waits = ScreenSetCoordinator.active!.waits
        expect(recovery.refreshCollapsePresentation() && ScreenSetCoordinator.active!.waits == waits + 1,
               "ordinary geometry refresh accepts pending confirmation and registers its owner")
        recovery.surfaces[0].alpha = 0
        ReplayClock.now = 101
        expect(recovery.applyScreenSetSlot(displayID: "external", edge: .left, intent: oldIntent) == .succeeded
               && recovery.repaired == 1 && recovery.pendingPresentation == nil,
               "matching appearance finishes recovery")

        recovery.pendingPresentation = (WindowWriteConfirmation(now: 100), .collapsed, .slideOffscreen, StashAX.frame)
        recovery.surfaces[0].alpha = 1
        ReplayClock.now = 101.5
        expect(recovery.confirmScreenSetPresentation(readWindows: { recovery.surfaces }) == .failed
               && recovery.pendingPresentation == nil, "persistent opacity mismatch still fails boundedly")

        let release = capturing()
        release.pendingMinimize = nil
        expect(!release.releaseOwnedMinimize() && StashAX.writes == [false],
               "inverse write is submitted even with false readback and cannot clear debt immediately")
        ReplayClock.now = 100.624
        _ = release.reconcilePendingWindowWrites()
        expect(release.releases == 0 && release.unconfirmedOwnedMinimize, "release waits through full settle bound")
        expect(release.applyScreenSetSlot(displayID: "external", edge: .left) == .waitingForControl,
               "restoration cannot race a pending inverse write")
        ReplayClock.now = 101.5
        _ = release.reconcilePendingWindowWrites()
        expect(release.releases == 1 && !release.unconfirmedOwnedMinimize,
               "settled visible state permits release cleanup")

        let failedRelease = capturing()
        failedRelease.pendingMinimize = nil
        _ = failedRelease.releaseOwnedMinimize()
        ReplayClock.now = 101.5
        StashAX.minimized = true
        _ = failedRelease.reconcilePendingWindowWrites()
        _ = failedRelease.reconcilePendingWindowWrites()
        expect(failedRelease.releases == 0 && failedRelease.unconfirmedOwnedMinimize && StashAX.writes == [false],
               "failed inverse confirmation retains debt without an automatic write loop")

        let rejected = capturing()
        rejected.pendingMinimize = nil
        StashAX.acknowledged = false
        expect(!rejected.releaseOwnedMinimize() && rejected.pendingMinimizeRelease == nil
               && rejected.unconfirmedOwnedMinimize, "rejected inverse retains debt")
    }
}

@main enum Replay {
    static func main() {
        var assertions = 0
        var failures: [String] = []
        StashSession.run { condition, message in
            assertions += 1
            if !condition { failures.append(message) }
        }
        let result: [String: Any] = ["scope": "Selected live StashSession method bodies with injected AX, UI, completion hooks and monotonic time; not full native execution",
                                   "assertions": assertions, "failures": failures]
        print(String(data: try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
        if !failures.isEmpty { exit(1) }
    }
}
