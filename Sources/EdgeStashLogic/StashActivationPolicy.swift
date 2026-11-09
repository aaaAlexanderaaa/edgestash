import Foundation

public enum AllStashedDockAction: String, Codable, CaseIterable, Equatable {
    case leaveClosed
    case openMostRecent
    case openOnPointerDisplay
    case openAll
}

public enum AppActivationKind: Equatable {
    case dockAppIcon
    case commandTab
    case dockWindowThumbnail
    case showAllWindows
    case fileDropOrNotification
    case hideApp
    case unknown
    /// EdgeStash opened a stash and that activate() bounced back as
    /// `didActivateApplication`. Not a Dock / Cmd-Tab click.
    case ownedReveal
}

public enum StashActivationDecision: Equatable {
    case raiseOnDesktopOnly
    case doNotOpenStash
    case openMostRecent
    case openOnPointerDisplay
    case openAllStashes
    case openThumbnail
    case followSystem
}

public enum StashActivationPolicy {
    public static func resolvedDockAction(
        _ stored: AllStashedDockAction?
    ) -> AllStashedDockAction {
        stored ?? .leaveClosed
    }

    public static func decision(
        kind: AppActivationKind,
        hasOnDesktopWindow: Bool,
        allStandardWindowsStashed: Bool,
        allStashedDock: AllStashedDockAction
    ) -> StashActivationDecision {
        switch kind {
        case .dockAppIcon, .commandTab:
            if hasOnDesktopWindow {
                return .raiseOnDesktopOnly
            }
            guard allStandardWindowsStashed else { return .doNotOpenStash }
            switch allStashedDock {
            case .leaveClosed:
                return .doNotOpenStash
            case .openMostRecent:
                return .openMostRecent
            case .openOnPointerDisplay:
                return .openOnPointerDisplay
            case .openAll:
                return .openAllStashes
            }
        case .dockWindowThumbnail:
            return .openThumbnail
        case .showAllWindows:
            return .openAllStashes
        case .fileDropOrNotification, .hideApp, .ownedReveal, .unknown:
            return .doNotOpenStash
        }
    }
}

/// One show-all action may reveal windows from several apps before macOS sends
/// their activation notifications. Keep each owned activation independently so
/// an earlier app is not mistaken for a Dock or Cmd-Tab activation.
public struct OwnedActivationLedger {
    private var notedAt: [String: Date] = [:]

    public init() {}

    public mutating func note(bundleID: String, now: Date = Date()) {
        notedAt[bundleID] = now
    }

    public mutating func consume(
        bundleID: String, now: Date = Date(), window: TimeInterval = 1.2
    ) -> Bool {
        guard let at = notedAt.removeValue(forKey: bundleID) else { return false }
        return now.timeIntervalSince(at) <= window
    }
}

/// A workspace activation is not itself a keyboard gesture. Store only the
/// abstract intent's monotonic timestamp, never key contents or a diagnostic log.
public struct CommandTabIntent {
    private var lastEvent: TimeInterval = -.infinity
    private var pending: TimeInterval?
    private var lastConsumption: TimeInterval = -.infinity
    private var switching = false
    public init() {}

    public static func matches(keyCode: UInt16, modifiers: UInt) -> Bool {
        let flags = AppShortcutPolicy.normalizedModifiers(modifiers)
        return keyCode == 48 && flags & (1 << 20) != 0
            && flags & ((1 << 18) | (1 << 19)) == 0
    }

    public mutating func note(timestamp: TimeInterval) {
        guard timestamp > lastEvent, timestamp > lastConsumption else { return }
        lastEvent = timestamp
        switching = true
        pending = nil
    }

    public mutating func cancel(timestamp: TimeInterval) {
        guard timestamp >= lastEvent else { return }
        switching = false
        pending = nil
        lastEvent = timestamp
        lastConsumption = max(lastConsumption, timestamp)
    }

    public mutating func observe(keyCode: UInt16, modifiers: UInt, timestamp: TimeInterval,
                                 isModifierChange: Bool = false) {
        if !isModifierChange {
            if Self.matches(keyCode: keyCode, modifiers: modifiers) { note(timestamp: timestamp) }
            else { cancel(timestamp: timestamp) }
        } else if (keyCode == 54 || keyCode == 55), modifiers & (1 << 20) == 0,
                  switching, timestamp > lastEvent {
            // Releasing Command commits the switch; Escape/pointer activity
            // can cancel it before then. A held switch is not an activation.
            let recent = timestamp - lastEvent <= 0.8
            switching = false
            lastEvent = timestamp
            pending = timestamp > lastConsumption && recent ? timestamp : nil
        }
    }

    public mutating func consume(now: TimeInterval) -> Bool {
        lastConsumption = max(lastConsumption, now)
        guard let timestamp = pending else { return false }
        pending = nil
        return (0...0.8).contains(now - timestamp)
    }
}

public struct DockThumbnailCandidate {
    public let windowID: UInt32
    public let title: String
    public let isManaged: Bool
    public let isCollapsed: Bool
    public let systemMinimize: Bool
    public init(windowID: UInt32, title: String, isManaged: Bool, isCollapsed: Bool, systemMinimize: Bool) {
        self.windowID = windowID; self.title = title; self.isManaged = isManaged
        self.isCollapsed = isCollapsed; self.systemMinimize = systemMinimize
    }
}

public enum DockThumbnailPolicy {
    public static func focusedWindow(beforeClick: UInt32?, now: UInt32?,
                                      requestedTitle: String, observedTitle: String?) -> UInt32? {
        guard let beforeClick, let now, beforeClick != now,
              !requestedTitle.isEmpty, requestedTitle == observedTitle else { return nil }
        return now
    }

    /// Minimized tiles are restored by the system's exact AX notification.
    /// Count every title match, including ordinary and already-open siblings.
    public static func fallbackWindow(title: String, candidates: [DockThumbnailCandidate]) -> UInt32? {
        let matches = candidates.filter { $0.title == title }
        guard !title.isEmpty, matches.count == 1, let candidate = matches.first,
              candidate.isManaged, candidate.isCollapsed, !candidate.systemMinimize else { return nil }
        return candidate.windowID
    }
}
