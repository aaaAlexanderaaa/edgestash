// Current session methods are inserted by check-session-recovery.py. Native
// AX/UI, clock, coordinator guard and main-queue delivery are injected; this
// verifies adapter ordering, not physical multi-display or native AX completion.
import Foundation
import AppKit
import EdgeStashLogic

enum ReplayClock {
    static var now: TimeInterval = 100
    static var date: Date { Date(timeIntervalSince1970: now) }
}
enum NSEvent { static var pressedMouseButtons = 0 }
enum StashDiagnostics {
    static let isEnabled = true
    static var events: [(String, [String: Any])] = []
    static func record(_ event: String, _ fields: [String: Any]) { events.append((event, fields)) }
}
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
    static var saveHook: (() -> Bool)?
    @discardableResult
    static func persist(session: StashSession) -> Bool { saves += 1; return saveHook?() ?? true }
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
struct Appearance { let resolvedMotion = Motion.slide; let resolvedMaterial = StashMaterial.glass }
final class Preferences {
    static let shared = Preferences()
    var scope = AppShortcutWindowScope.allManagedWindows
    var mergesStrips = true
    var advisedStripOverload = true
    var revealDelayMS = 150
    func chordScope(for bundleID: String) -> AppShortcutWindowScope { scope }
    func stripColor(for bundleID: String) -> NSColor { .blue }
    func appearance(for bundleID: String) -> Appearance { Appearance() }
}
enum PreparationError: Error { case disabledFullScreen }
final class DisplaySpaceTransport {
    static let shared = DisplaySpaceTransport()
    var preparations = 0
    var confirmations = 0
    var delayedPreparations: [(Result<UInt64, PreparationError>) -> Void] = []
    var delayPreparation = false
    func availability(for displayID: UInt32) -> SeamSpaceAvailability { .ready(spaceID: 1) }
    func confirmsDestination(windowID: UInt32, displayID: UInt32, targetSpaceID: UInt64) -> Bool {
        confirmations += 1
        return true
    }
    func prepareMinimizedWindow(windowID: UInt32, for displayID: UInt32,
                                completion: @escaping (Result<UInt64, PreparationError>) -> Void) {
        preparations += 1
        if delayPreparation { delayedPreparations.append(completion) }
        else { completion(.success(1)) }
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
    var bundleID = "com.apple.Stickies"
    var mergeID: String { String(describing: ObjectIdentifier(self)) }
    var isIdle: Bool { phase == .idle }
    var isCollapsed: Bool { phase == .collapsed }
    var markerSuppressed = false
    var clickCollapseLockActive = false
    let applicationIcon: NSImage? = nil
    var mergeMember: MergeMember? {
        guard isManaged else { return nil }
        return MergeMember(id: mergeID, edge: edge!, screenFrame: DisplayCatalog.external.frame,
                           visibleMinY: 200, visibleMaxY: 600, windowHeight: 400, title: "Replay",
                           presentation: presentation ?? .slideOffscreen)
    }
    func setMarkerSuppressed(_ value: Bool) { markerSuppressed = value }
    func captureNearestAllowed() -> Bool { false }
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
    // INSERT_CURRENT_SESSION_STATE
    var hoverDelayTimer: Timer?
    var leaveTimer: Timer?
    var onPresentationRequested: ((StashSession, StashPresentationRequest) -> Void)?
    var onChanged: (() -> Void)?
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
    func diagnose(_ event: String, _ fields: [String: Any] = [:]) { StashDiagnostics.record(event, fields) }
    func notifyChanged() { onChanged?() }
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
    var delaySlide = false
    var pendingSlide: (() -> Void)?
    func slide(from: CGPoint, to: CGPoint, collapsing: Bool, merged: Bool, completion: @escaping (Bool) -> Void) {
        busy = true
        let finish = { [self] in
            _ = StashAX.setFrame(windowElement, CGRect(origin: to, size: restoreFrame!.size))
            completion(true)
        }
        if delaySlide { pendingSlide = finish } else { finish() }
    }
    func refreshCollapsePresentation() -> Bool { true }
    func replayMinimizeObservation() { confirmOwnedMinimize() }
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

// The actual models and entire merge coordinator are inserted, not reimplemented.
// INSERT_CURRENT_MERGE_MODELS
final class StashMergeStrip {
    var onHoverSegment: ((ObjectIdentifier?) -> Void)?
    var onClickSegment: ((ObjectIdentifier) -> Void)?
    var model: StashMergeStripModel?
    func orderOut(_ value: Any?) {}
    func present(_ model: StashMergeStripModel) { self.model = model }
    func updateHover(_ id: ObjectIdentifier?) {}
    func segmentAtPointer() -> ObjectIdentifier? { nil }
    func rearmHoverAfterMouseUp() {}
}
enum EdgeAlert {
    enum Style { case informational }
    static func run(style: Style, title: String, detail: String, buttons: [String]) {}
}
enum L10n {
    static let stripOverloadTitle = "", stripOverloadBody = "", stripOverloadOK = ""
}
// INSERT_CURRENT_MERGE_COORDINATOR
extension StashMergeCoordinator {
    func replayHover(_ session: StashSession) -> (String, HoverRevealTicket, UInt)? {
        guard let key = groupSessions.keys.first(where: { groupSessions[$0]?[session.mergeID] != nil }) else { return nil }
        handleHover(ObjectIdentifier(session), key: key, lookup: groupSessions[key]!)
        guard let ticket = interactions[key]?.pending else { return nil }
        return (key, ticket, session.presentationRequests.revision)
    }
    func replayFire(_ value: (String, HoverRevealTicket, UInt), session: StashSession) {
        fireHover(value.1, key: value.0, session: session, revision: value.2)
    }
    func replayLeave() {
        for key in Array(groupSessions.keys) { handleHover(nil, key: key, lookup: groupSessions[key]!) }
    }
}
final class EngineAdapter {
    var sessions: [StashSession]
    var presentationCommandSequence: UInt = 0
    let merged = StashMergeCoordinator()
    var lastPreferredSession: [String: ObjectIdentifier] = [:]
    init(_ sessions: [StashSession]) {
        self.sessions = sessions
        for session in sessions {
            session.onPresentationRequested = { [weak self] session, request in
                self?.merged.notePresentationRequest(session, request: request)
            }
            session.onChanged = { [weak self] in
                guard let self else { return }
                self.merged.reconcile(sessions: self.sessions)
            }
        }
        merged.reconcile(sessions: sessions)
    }
    func discoverEnabledWindows(bundleID: String) {}
    func preferredIdle(in group: [StashSession], bundleID: String) -> StashSession? { nil }
    func preferred(in group: [StashSession], bundleID: String) -> StashSession? { group.first }
    func shortcut(_ bundleID: String) { handleAppShortcut(bundleID) }
    func showAll() { applyShowAll(bundleIDs: Array(Set(sessions.map(\.bundleID)))) }
    // INSERT_CURRENT_ENGINE_METHODS
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
            DisplaySpaceTransport.shared.delayPreparation = false
            DisplaySpaceTransport.shared.delayedPreparations = []
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

        // MARK: presentation_ownership live handoff rejects lost toggles and explicit no-ops.
        let gap = pendingRecovery()
        gap.toggleFromShortcut()
        StashAX.minimized = true
        _ = confirm(gap)
        expect(gap.desiredPresentationIsExpanded, "deferred recovery target remains visible to the second toggle")
        gap.toggleFromShortcut()
        DispatchQueue.main.drain()
        expect(gap.phase == .collapsed && !gap.desiredPresentationIsExpanded && StashAX.writes == [true],
               "two toggles across the actual recovery/main-queue boundary end collapsed without another write")
        let explicit = pendingRecovery()
        _ = explicit.expand(fromDock: true)
        StashAX.minimized = true
        _ = confirm(explicit)
        expect(explicit.collapse(), "new explicit close is accepted even when the committed phase is already collapsed")
        DispatchQueue.main.drain()
        expect(explicit.phase == .collapsed && !explicit.presentationRequests.hasOutstandingRequest,
               "newer no-op close invalidates the older deferred reveal")

        func outer(_ app: String = "test.app") -> StashSession {
            let session = StashSession()
            session.bundleID = app
            session.edge = .right
            session.presentation = .slideOffscreen
            session.usingSharedMinimize = false
            return session
        }

        // MARK: command_scope live engine and entire merge projection preserve named targets.
        for reversed in [false, true] {
            let first = outer(), second = outer()
            first.delaySlide = true; second.delaySlide = true
            let engine = EngineAdapter([first, second])
            engine.shortcut("test.app")
            expect(first.desiredPresentationIsExpanded && second.desiredPresentationIsExpanded,
                   "one application command names both merged members before completion")
            for session in reversed ? [second, first] : [first, second] {
                let completion = session.pendingSlide
                session.pendingSlide = nil
                completion?()
                engine.merged.reconcile(sessions: engine.sessions)
            }
            expect(first.isExpanded && second.isExpanded && !first.busy && !second.busy,
                   "both merged members stay expanded under either completion order")
            first.delaySlide = false; second.delaySlide = false
            engine.shortcut("test.app")
            expect(first.isCollapsed && second.isCollapsed, "the next application command collapses both members")
            engine.merged.tearDown()
        }
        let crossA = outer("app.A"), crossB = outer("app.B")
        let cross = EngineAdapter([crossA, crossB])
        cross.shortcut("app.A")
        cross.shortcut("app.B")
        expect(crossA.isExpanded && crossB.isExpanded, "an app B command cannot collapse unnamed app A through merge reconciliation")
        cross.shortcut("app.A")
        cross.shortcut("app.B")
        cross.showAll()
        expect(crossA.isExpanded && crossB.isExpanded, "global show-all preserves every application's merged member")
        crossA.isPinned = true
        cross.merged.reconcile(sessions: cross.sessions)
        expect(crossB.isExpanded, "a pinned highlight does not turn projection into a sibling close command")
        cross.merged.tearDown()

        let unavailable = outer(), healthy = outer()
        unavailable.phase = .expanded
        unavailable.awaitingWindowControl = true
        let partial = EngineAdapter([unavailable, healthy])
        for expectedExpanded in [true, false, true] {
            partial.shortcut("test.app")
            expect(healthy.isExpanded == expectedExpanded && unavailable.isExpanded,
                   "each app shortcut advances the healthy sibling while the unavailable member remains untouched")
        }
        expect(StashDiagnostics.events.contains { $0.0 == "session.command-skipped" },
               "partial batch refusal is diagnosed instead of silently blocking the group")
        Preferences.shared.scope = .recentWindow
        partial.shortcut("test.app")
        expect(healthy.isCollapsed, "recent-window scope also chooses a controllable managed member")
        Preferences.shared.scope = .allManagedWindows
        partial.merged.tearDown()

        // MARK: merged_hover live timers cannot replace newer explicit intent.
        StashAX.minimized = true
        DisplaySpaceTransport.shared.delayPreparation = true
        let hovered = StashSession(), sibling = StashSession()
        NSEvent.pressedMouseButtons = 1
        let hoverEngine = EngineAdapter([hovered, sibling])
        expect(hoverEngine.merged.seamApproachSegments.count == 2
               && hoverEngine.merged.replayHover(hovered) == nil,
               "button-down reconciliation keeps approach geometry but cannot arm hover")
        NSEvent.pressedMouseButtons = 0
        hovered.clickCollapseLockActive = true
        guard let oldDwell = hoverEngine.merged.replayHover(hovered) else {
            expect(false, "settled merged window must arm a dwell"); report(); exit(1)
        }
        expect(!hovered.canBeginHoverReveal() && hovered.canBeginHoverReveal(merged: true),
               "merged visits use their own click lock after an individual marker becomes suppressed")
        _ = hovered.expand(fromDock: true)
        expect(hovered.busy && hoverEngine.merged.replayHover(hovered) == nil,
               "merged hover cannot rearm during an owned Space reveal")
        hovered.toggleFromShortcut()
        ReplayClock.now += 1
        hoverEngine.merged.replayFire(oldDwell, session: hovered)
        expect(!hovered.desiredPresentationIsExpanded && hovered.busy,
               "old merged dwell cannot overwrite the newer shortcut collapse")
        DisplaySpaceTransport.shared.delayPreparation = false
        let preparations = DisplaySpaceTransport.shared.delayedPreparations
        DisplaySpaceTransport.shared.delayedPreparations = []
        preparations.forEach { $0(.success(1)) }
        StashAX.minimized = true
        hovered.replayMinimizeObservation()
        expect(hovered.isCollapsed && !hovered.busy, "the preserved close actually completes after Space preparation")
        hoverEngine.merged.replayLeave()
        expect(hoverEngine.merged.replayHover(hovered) != nil, "a fresh settled pointer visit can reveal again")
        hoverEngine.merged.tearDown()

        let hoverA = outer("app.A"), explicitB = outer("app.B")
        let competing = EngineAdapter([hoverA, explicitB])
        let otherDwell = competing.merged.replayHover(hoverA)!
        competing.shortcut("app.B")
        ReplayClock.now += 1
        competing.merged.replayFire(otherDwell, session: hoverA)
        expect(hoverA.isCollapsed && explicitB.isExpanded,
               "explicit input for another merged member cancels the group's earlier pending dwell")
        competing.merged.tearDown()

        // MARK: presentation_ownership callbacks, failures and pins share operation identity.
        let reentrant = outer()
        let beforeReentrantWrites = StashAX.frameWrites
        reentrant.onPresentationRequested = { session, request in
            if request.expanded { _ = session.collapse() }
        }
        _ = reentrant.expand(fromDock: true)
        expect(reentrant.isCollapsed && !reentrant.busy && !reentrant.presentationRequests.hasOutstandingRequest
               && StashAX.frameWrites == beforeReentrantWrites,
               "a request callback superseding admission cannot execute the old reveal afterward")

        let refused = outer()
        refused.phase = .expanded
        StashRescue.saveHook = {
            StashRescue.saveHook = nil
            _ = refused.expand(fromDock: true)
            return false
        }
        expect(!refused.collapse() && refused.isExpanded && !refused.busy
               && !refused.presentationRequests.hasOutstandingRequest,
               "native refusal clears its operation and queued input even when input revision advanced")

        let pinnedDeferred = pendingRecovery(expanded: true)
        _ = pinnedDeferred.collapse(merged: true, source: .mergeClick)
        StashSurface.observedAlpha = 1
        _ = confirm(pinnedDeferred)
        pinnedDeferred.isPinned = true
        DispatchQueue.main.drain()
        expect(pinnedDeferred.isExpanded && pinnedDeferred.isPinned && !pinnedDeferred.busy
               && !pinnedDeferred.presentationRequests.hasOutstandingRequest,
               "execution rechecks pin protection before a deferred close can write")

        let replaced = outer()
        replaced.delaySlide = true
        _ = replaced.expand(fromDock: true)
        let oldCompletion = replaced.pendingSlide!
        replaced.prepareForScreenSetChange()
        _ = replaced.expand(fromDock: true)
        let newCompletion = replaced.pendingSlide!
        let newOperation = replaced.presentationRequests.operation
        oldCompletion()
        expect(replaced.busy && replaced.isCollapsed && replaced.presentationRequests.owns(operation: newOperation),
               "cancelled animation completion cannot consume a replacement operation")
        newCompletion()
        expect(replaced.isExpanded && !replaced.busy && !replaced.presentationRequests.hasOutstandingRequest,
               "the replacement operation alone may commit its final phase")

        report()
        if !failures.isEmpty { exit(1) }
    }
}
