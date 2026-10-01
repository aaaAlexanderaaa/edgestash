import CoreGraphics
import Foundation

public enum HoverRevealPolicy {
    /// A mouse-up during a click reveal is still the same visit. It cannot
    /// arm a second reveal that would overwrite a newer explicit target.
    public static func shouldBegin(
        phase: StashSessionPhase, isBusy: Bool, markerSuppressed: Bool,
        clickLocked: Bool, buttonPressed: Bool
    ) -> Bool {
        phase == .collapsed && !isBusy && !markerSuppressed && !clickLocked && !buttonPressed
    }
}

/// Every named reveal entry point participates in the same merged selection.
/// Record requests, not animation completions: an older reveal finishing late
/// must not regain preference over a newer request for another member.
public struct MergeRevealSelection {
    private var preferredID: String?

    public init() {}

    public mutating func request(_ id: String) {
        preferredID = id
    }

    public func active(expandedIDs: Set<String>, hoveredID: String?, pinnedID: String? = nil) -> String? {
        MergeGroupPolicy.activeAfterReconcile(
            expandedIDs: expandedIDs, preferred: pinnedID ?? preferredID ?? hoveredID
        )
    }
}

public struct HoverRevealTicket: Equatable {
    public let targetID: String
    public let generation: UInt
    public let deadline: Date
}

/// One hover visit owns one dwell. Motion inside the same target is not a
/// fresh arrival; clicking, dragging, leaving, and changing targets invalidate
/// its scheduled work. The native timer is only an adapter for this state.
public struct HoverRevealCoordinator {
    public private(set) var hoveredID: String?
    public private(set) var pending: HoverRevealTicket?
    private var clickLockedID: String?
    private var revealedForVisit = false
    private var generation: UInt = 0

    public init() {}

    public mutating func updateTarget(
        _ targetID: String?, now: Date, delay: TimeInterval,
        buttonPressed: Bool
    ) -> HoverRevealTicket? {
        if targetID != hoveredID {
            cancelPending()
            hoveredID = targetID
            revealedForVisit = false
            clickLockedID = nil
        }
        if buttonPressed {
            if pending != nil { cancelPending() }
            return nil
        }
        guard let targetID, clickLockedID != targetID,
              !revealedForVisit, pending == nil else { return nil }
        generation &+= 1
        let ticket = HoverRevealTicket(
            targetID: targetID, generation: generation,
            deadline: now.addingTimeInterval(max(0, delay))
        )
        pending = ticket
        return ticket
    }

    public mutating func click(targetID: String, collapsing: Bool) {
        cancelPending()
        hoveredID = targetID
        clickLockedID = collapsing ? targetID : nil
        revealedForVisit = true
    }

    public mutating func consume(
        _ ticket: HoverRevealTicket, now: Date, buttonPressed: Bool
    ) -> String? {
        guard pending == ticket, hoveredID == ticket.targetID else { return nil }
        if buttonPressed {
            cancelPending()
            return nil
        }
        guard now >= ticket.deadline, clickLockedID != ticket.targetID else { return nil }
        pending = nil
        revealedForVisit = true
        return ticket.targetID
    }

    private mutating func cancelPending() {
        generation &+= 1
        pending = nil
    }
}

public struct FocusReturnTicket: Equatable {
    fileprivate let generation: UInt
    fileprivate let phase: StashSessionPhase
}

/// Focus return belongs to the operation that earned it. A newer operation
/// or direct interaction cancels both an already-scheduled return and the
/// right to schedule one when an older animation eventually completes.
public struct FocusReturnCoordinator {
    private var generation: UInt = 0
    private var maySchedule = false
    private var pending: FocusReturnTicket?

    public init() {}

    public mutating func beginOperation() {
        cancel()
        maySchedule = true
    }

    public mutating func cancel() {
        generation &+= 1
        maySchedule = false
        pending = nil
    }

    public mutating func schedule(phase: StashSessionPhase) -> FocusReturnTicket? {
        guard maySchedule, phase == .collapsed || phase == .expanded else { return nil }
        maySchedule = false
        let ticket = FocusReturnTicket(generation: generation, phase: phase)
        pending = ticket
        return ticket
    }

    public mutating func consume(
        _ ticket: FocusReturnTicket, phase: StashSessionPhase, busy: Bool
    ) -> Bool {
        guard pending == ticket else { return false }
        pending = nil
        return phase == ticket.phase && !busy
    }
}

/// Front-to-back WindowServer metadata. Transparent parked stashes and
/// non-document overlays must not become pointer targets.
public struct WindowSurfaceHit {
    public let windowID: UInt32
    public let pid: Int32
    public let frame: CGRect
    public let layer: Int
    public let alpha: CGFloat

    public init(windowID: UInt32, pid: Int32, frame: CGRect, layer: Int = 0, alpha: CGFloat = 1) {
        self.windowID = windowID
        self.pid = pid
        self.frame = frame
        self.layer = layer
        self.alpha = alpha
    }
}

public enum WindowSurfacePolicy {
    public static func frontmostWindow(at point: CGPoint, in windows: [WindowSurfaceHit]) -> WindowSurfaceHit? {
        windows.first { $0.layer == 0 && $0.alpha > 0 && $0.frame.contains(point) }
    }

    public static func isPointerInSiblingWindow(
        pid: Int32, excluding windowID: UInt32?, at point: CGPoint,
        in windows: [WindowSurfaceHit]
    ) -> Bool {
        guard let hit = frontmostWindow(at: point, in: windows) else { return false }
        return hit.pid == pid && hit.windowID != windowID
    }
}

public struct StashPresentationRequest: Equatable {
    public let expanded: Bool
    public let fromDock: Bool
    public let merged: Bool

    public init(expanded: Bool, fromDock: Bool = false, merged: Bool = false) {
        self.expanded = expanded
        self.fromDock = fromDock
        self.merged = merged
    }
}

/// Finish the current owned write before applying the newest requested
/// appearance. Keep one target rather than replaying every intermediate click.
public struct StashPresentationCoordinator {
    public private(set) var revision: UInt = 0
    private var active: StashPresentationRequest?
    private var pending: StashPresentationRequest?

    public init() {}

    public func desiredExpanded(phase: StashSessionPhase) -> Bool {
        pending?.expanded ?? active?.expanded ?? (phase == .expanded)
    }

    public mutating func begin(_ request: StashPresentationRequest) {
        revision &+= 1
        active = request
        pending = nil
    }

    public mutating func queue(_ request: StashPresentationRequest) -> Bool {
        guard let active else { return false }
        revision &+= 1
        pending = request.expanded == active.expanded ? nil : request
        return true
    }

    public mutating func complete() -> StashPresentationRequest? {
        let next = pending
        cancel()
        return next
    }

    public mutating func discardPending() {
        revision &+= 1
        pending = nil
    }

    public mutating func cancel() {
        revision &+= 1
        active = nil
        pending = nil
    }
}
