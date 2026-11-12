// Current session methods are inserted by check-session-recovery.py. Native
// AX/UI, clock, coordinator guard and main-queue delivery are injected; this
// verifies adapter ordering, not physical multi-display or native AX completion.
import Foundation
import EdgeStashLogic

enum ReplayClock { static var now: TimeInterval = 100 }
final class DispatchQueue {
    static let main = DispatchQueue()
    var pending: [() -> Void] = []
    func async(execute work: @escaping () -> Void) { pending.append(work) }
    func drain() {
        let ready = pending
        pending = []
        ready.forEach { $0() }
    }
}

struct Read<Value> { var value: Value? }
let kAXMinimizedAttribute = "AXMinimized"
typealias CGDirectDisplayID = UInt32
enum StashAX {
    static var minimized: Bool? = false
    static var currentFrame = CGRect(x: 1440, y: 50, width: 500, height: 400)
    static var writes: [Bool] = []
    static var frameWrites = 0
    static func isMinimized(_ element: Int) -> Bool? { minimized }
    static func canSetMinimized(_ element: Int) -> Bool { true }
    static func windowID(of element: Int) -> UInt32? { 42 }
    static func requestMinimized(_ element: Int, _ value: Bool) -> Bool {
        writes.append(value)
        return true
    }
    static func setMinimized(_ element: Int, _ value: Bool) -> Bool {
        writes.append(value)
        minimized = value
        return true
    }
    static func setFrame(_ element: Int, _ value: CGRect) -> Bool {
        frameWrites += 1
        currentFrame = value
        return true
    }
    static func frame(of element: Int) -> CGRect? { currentFrame }
    static func boolResult(_ element: Int, _ name: String) -> Read<Bool> { Read(value: minimized) }
    static func frameResult(of element: Int) -> Read<CGRect> { Read(value: currentFrame) }
    static func isFullScreen(_ element: Int) -> Bool? { false }
}
struct StashRecoverySurface { var windowID: UInt32; var pid: Int32; var alpha: Float? }
enum StashSurface {
    static var observedAlpha: Float = 1
    static func allWindows() -> [StashRecoverySurface]? {
        [StashRecoverySurface(windowID: 42, pid: 555, alpha: observedAlpha)]
    }
    static func setAlpha(windowID: UInt32, alpha: Float) -> Bool { true }
}
enum StashRescue {
    static var saves = 0
    @discardableResult
    static func persist(session: StashSession) -> Bool { saves += 1; return true }
}
enum StashFocusReturn { static func remember(excluding pid: Int32) {} }
enum NSScreen { static let screens = [1] }
final class NSWorkspace {
    static let shared = NSWorkspace()
    let accessibilityDisplayShouldReduceMotion = false
}
enum DisplayCatalog {
    static let primary = DisplayGeometry(id: "primary", frame: CGRect(x: 0, y: 0, width: 1440, height: 1080))
    static let external = DisplayGeometry(id: "external", frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))
    static func adjacencyGeometries(screens: [Int] = NSScreen.screens) -> [DisplayGeometry] { [primary, external] }
    static func screen(withID id: String, screens: [Int] = NSScreen.screens) -> Int? { 1 }
    static func displayID(for screen: Int) -> UInt32? { 1 }
    static func primaryHeight(screens: [Int]) -> CGFloat { 1080 }
}
enum Motion { case slide }
struct Appearance { let resolvedMotion = Motion.slide }
final class Preferences {
    static let shared = Preferences()
    func appearance(for bundleID: String) -> Appearance { Appearance() }
}
enum PreparationError: Error { case disabledFullScreen }
final class DisplaySpaceTransport {
    static let shared = DisplaySpaceTransport()
    var preparations = 0
    var confirmations = 0
    func availability(for displayID: UInt32) -> SeamSpaceAvailability { .ready(spaceID: 1) }
    func confirmsDestination(windowID: UInt32, displayID: UInt32, targetSpaceID: UInt64) -> Bool {
        confirmations += 1
        return true
    }
    func prepareMinimizedWindow(windowID: UInt32, for displayID: UInt32,
                                completion: @escaping (Result<UInt64, PreparationError>) -> Void) {
        preparations += 1
        completion(.success(1))
    }
}
final class ScreenSetCoordinator {
    static var isApplying = false
    static var blocksUserGeometry: Bool { isApplying }
    static let active: ScreenSetCoordinator? = ScreenSetCoordinator()
    var cancellations = 0
    func cancelRestoration(of session: StashSession) { cancellations += 1 }
}
enum ScreenSetApplicationResult: Equatable { case succeeded, waitingForControl, waitingForPersistence, blockedSpace, failed }
final class PinWindow { func conceal() {} }
final class Animator { func cancel() {} }

final class StashSession {
    let windowElement = 1
    var windowID: UInt32? = 42
    let pid: Int32 = 555
    let bundleID = "com.apple.Stickies"
    let pinWindow = PinWindow()
    let animator = Animator()
    var phase: StashSessionPhase = .collapsed
    var presentation: StashCollapsePresentation? = .systemMinimize
    var edge: DisplayEdge? = .left
    var displayID: String? = "external"
    var restoreFrame: CGRect? = CGRect(x: 1440, y: 50, width: 500, height: 400)
    var lockedWidth: CGFloat = 500
    var awaitingWindowControl = false
    var usingSharedMinimize = true
    var restoringShared = false
    var unconfirmedOwnedMinimize = false
    var lastOwnedMinimizeAt = Date.distantPast
    var busy = false
    var markerHiddenForSpace = false
    var lifecycleGeneration = 0
    var spaceRevealGeneration = 0
    var recoverySpacePreparation = SeamRecoveryPreparation()
    var pendingPresentation: (confirmation: WindowWriteConfirmation, phase: StashSessionPhase,
                              presentation: StashCollapsePresentation, frame: CGRect)?
    var pendingMinimize: (confirmation: WindowWriteConfirmation, next: StashSessionPhase, frame: CGRect, merged: Bool)?
    var pendingMinimizeRelease: WindowWriteConfirmation?
    var isExpanded: Bool { phase == .expanded }
    var isManaged: Bool { phase != .idle }
    var isPinned = false
    var rescueVisibleFrame: CGRect?
    var rescueDisplayFrame: CGRect? = DisplayCatalog.external.frame
    var ignoringGeometryNotifications = false
    var pendingScreenSetRecovery: ScreenSetRecoveryIntent?
    var pendingVisibleFallbackOrigin: CGPoint?
    var recoveryEpochActive = false
    var needsScreenSetRepair = false
    var externalGeometryWasDragged = false
    var outsideSince: Date?
    var lastSiblingInteractionAt: Date?
    var pendingGeometryDetach: DispatchWorkItem?
    var focusReturn = FocusReturnCoordinator()
    var presentationRequests = StashPresentationCoordinator()
    var desiredPresentationIsExpanded: Bool { presentationRequests.desiredExpanded(phase: phase) }
    var hoverDelayTimer: Timer?
    var leaveTimer: Timer?
    var onRevealRequested: ((StashSession) -> Void)?
    var onControlReady: ((StashSession) -> Void)?
    var onExpanded: ((StashSession) -> Void)?
    var onCollapsed: ((StashSession) -> Void)?
    var seamSpaceAvailability: SeamSpaceAvailability = .ready(spaceID: 1)
    var canBeginSeamReveal: Bool { true }
    var recoveryIntent: ScreenSetRecoveryIntent? {
        pendingScreenSetRecovery ?? screenSetSlot.map {
            ScreenSetRecoveryIntent(placement: $0, expanded: isExpanded, frame: restoreFrame,
                                    displayFrame: rescueDisplayFrame)
        }
    }
    var screenSetSlot: ScreenSetPlacement? {
        guard let displayID, let edge else { return nil }
        return ScreenSetPlacement(windowNumber: 42, bundleID: bundleID, displayID: displayID, edge: edge.rawValue)
    }
    func diagnose(_ event: String, _ fields: [String: Any] = [:]) {}
    func notifyChanged() {}
    func activateApp() {}
    func refreshPinControl() {}
    func showMarker(windowQuartz: CGRect) {}
    func startLeaveWatch() {}
    func scheduleFocusRelease() {}
    func cancelHoverReveal() { hoverDelayTimer?.invalidate(); hoverDelayTimer = nil }
    func owningDisplay(for frame: CGRect, screens: [Int], primaryHeight: CGFloat) -> (DisplayGeometry, Int)? {
        (DisplayCatalog.external, 1)
    }
    func playEffects(collapsing: Bool, merged: Bool, frame: CGRect, primaryHeight: CGFloat) {}
    func slide(from: CGPoint, to: CGPoint, collapsing: Bool, merged: Bool, completion: (Bool) -> Void) {
        _ = StashAX.setFrame(windowElement, CGRect(origin: to, size: restoreFrame!.size))
        completion(true)
    }
    func refreshCollapsePresentation() -> Bool { true }
    func retainRecoveryIntent(_ intent: ScreenSetRecoveryIntent) { pendingScreenSetRecovery = intent }
    func markWindowControlUnavailable() { awaitingWindowControl = true; busy = false }
    func shutdown(event: SessionLifecyclePolicy.Event) { fatalError("Unexpected shutdown in this replay") }
    func failSharedRevealAfterDeminimize() { fatalError("Unexpected placement failure") }
    func failSharedReveal(availability: SeamSpaceAvailability) { fatalError("Unexpected Space refusal") }
    func holdMinimizedRecovery(_ intent: ScreenSetRecoveryIntent, availability: SeamSpaceAvailability, waiting: Bool) {
        fatalError("Unexpected blocked recovery")
    }
    func repairMinimizedSession(on display: DisplayGeometry, frame: CGRect,
                                next: StashCollapsePresentation) -> ScreenSetApplicationResult {
        fatalError("Unexpected recovery migration")
    }

    // INSERT_CURRENT_SESSION_METHODS
}

@main enum Replay {
    static func main() {
        var assertions = 0
        var failures: [String] = []
        func expect(_ value: Bool, _ message: String) {
            assertions += 1
            if !value { failures.append(message) }
        }
        func report() {
            let result: [String: Any] = ["assertions": assertions, "failures": failures,
                "scope": "Current session method bodies with injected AX/UI, clock, coordinator guard, main queue, animation and observer hooks; no native completion or physical display claim"]
            print(String(data: try! JSONSerialization.data(withJSONObject: result,
                                                          options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
        }
        func pendingRecovery(expanded: Bool = false, outer: Bool = false) -> StashSession {
            ReplayClock.now = 100
            DispatchQueue.main.pending = []
            ScreenSetCoordinator.isApplying = false
            StashAX.minimized = false
            StashAX.currentFrame = CGRect(x: 1440, y: 50, width: 500, height: 400)
            StashAX.writes = []
            StashAX.frameWrites = 0
            StashSurface.observedAlpha = expanded ? 0 : 1
            DisplaySpaceTransport.shared.preparations = 0
            DisplaySpaceTransport.shared.confirmations = 0
            let session = StashSession()
            if outer { session.edge = .right; session.presentation = .slideOffscreen; session.usingSharedMinimize = false }
            if expanded { session.phase = .expanded; session.usingSharedMinimize = false }
            let intent = session.recoveryIntent!
            expect(session.reconcileScreenSetPresentation() == .waitingForControl,
                   "accepted recovery writes wait for observed appearance")
            session.pendingScreenSetRecovery = intent
            session.recoveryEpochActive = true
            session.needsScreenSetRepair = true
            expect(session.busy && session.pendingPresentation != nil, "recovery confirmation owns the busy gate")
            return session
        }
        func confirm(_ session: StashSession) -> ScreenSetApplicationResult {
            ReplayClock.now = 100.624
            ScreenSetCoordinator.isApplying = true
            let result = session.reconcileScreenSetPresentation()
            ScreenSetCoordinator.isApplying = false
            return result
        }

        // MARK: session_recovery latest named request survives delayed minimize.
        let delayed = pendingRecovery()
        guard delayed.busy else { report(); exit(1) }
        let frameWrites = StashAX.frameWrites
        expect(delayed.expand(fromDock: true), "a shortcut queues during recovery")
        expect(delayed.phase == .collapsed && delayed.pendingPresentation != nil && StashAX.writes == [true],
               "stale false cannot commit an external Dock reveal or cancel the owned minimize")
        let target = delayed.pendingScreenSetRecovery!
        expect(delayed.applyScreenSetSlot(displayID: "external", edge: .left, intent: target) == .waitingForControl
               && StashAX.frameWrites == frameWrites && delayed.desiredPresentationIsExpanded,
               "same-target retry is read-only and preserves the queued shortcut")
        StashAX.minimized = true
        expect(confirm(delayed) == .succeeded && delayed.phase == .collapsed && !delayed.busy,
               "confirmation commits before replaying the shortcut")
        expect(DisplaySpaceTransport.shared.preparations == 0 && DispatchQueue.main.pending.count == 1,
               "a named reveal waits until the coordinator write guard ends")
        DispatchQueue.main.drain()
        expect(delayed.phase == .expanded && !delayed.busy && StashAX.writes == [true, false],
               "the delayed minimize is followed by the queued safe reveal")
        expect(DisplaySpaceTransport.shared.preparations == 1 && DisplaySpaceTransport.shared.confirmations == 3,
               "replay retains all Space preparation and commit gates")
        expect(ManagedMinimizeNotificationPolicy.action(for: .miniaturized, phase: delayed.phase,
            ownsCollapsedMinimize: delayed.usingSharedMinimize, revealInFlight: delayed.restoringShared,
            observedMinimized: StashAX.minimized, presentation: delayed.presentation) == .ignore,
               "the late minimize notification cannot recollapse the completed reveal")

        let toggled = pendingRecovery()
        expect(toggled.expand(fromDock: true) && toggled.collapse(), "opposite named requests are accepted while waiting")
        StashAX.minimized = true
        expect(confirm(toggled) == .succeeded, "the owned write still confirms after a toggle")
        DispatchQueue.main.drain()
        expect(toggled.phase == .collapsed && StashAX.writes == [true]
               && DisplaySpaceTransport.shared.preparations == 0, "the newest collapse cancels the older queued reveal")

        let expanded = pendingRecovery(expanded: true)
        expect(expanded.collapse() && expanded.expand(fromDock: true), "expanded recovery keeps one newest target too")
        StashSurface.observedAlpha = 1
        expect(confirm(expanded) == .succeeded, "expanded appearance confirms")
        DispatchQueue.main.drain()
        expect(expanded.phase == .expanded && StashAX.writes.isEmpty,
               "the newest expand cancels a queued collapse without a minimize")

        let expired = pendingRecovery(outer: true)
        expect(expired.expand(fromDock: true), "outer recovery also queues the named reveal")
        ReplayClock.now = 101.5
        expect(expired.reconcileScreenSetPresentation() == .failed && !expired.busy
               && expired.pendingPresentation == nil, "persistent opacity mismatch expires and clears the busy gate")
        DispatchQueue.main.drain()
        expect(expired.phase == .collapsed && !expired.desiredPresentationIsExpanded,
               "failed confirmation cannot replay an unverified transition")

        let superseded = pendingRecovery()
        _ = superseded.expand(fromDock: false)
        StashAX.minimized = true
        _ = confirm(superseded)
        expect(superseded.expand(fromDock: true), "a newer explicit action may run after confirmation")
        DispatchQueue.main.drain()
        expect(superseded.phase == .expanded && DisplaySpaceTransport.shared.preparations == 1,
               "revision ownership rejects the older deferred replay")

        let cancelled = pendingRecovery()
        _ = cancelled.expand(fromDock: true)
        cancelled.prepareForScreenSetChange()
        expect(cancelled.pendingPresentation == nil && !cancelled.busy
               && !cancelled.desiredPresentationIsExpanded && cancelled.unconfirmedOwnedMinimize,
               "environment cancellation clears pending input but retains unconfirmed visibility debt")

        let deferred = pendingRecovery()
        _ = deferred.expand(fromDock: true)
        StashAX.minimized = true
        _ = confirm(deferred)
        deferred.prepareForScreenSetChange()
        DispatchQueue.main.drain()
        expect(deferred.phase == .collapsed && DisplaySpaceTransport.shared.preparations == 0,
               "environment cancellation also rejects an already deferred replay")

        report()
        if !failures.isEmpty { exit(1) }
    }
}
