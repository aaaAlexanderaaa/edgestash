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
        case .fileDropOrNotification, .hideApp, .ownedReveal:
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

/// Control-Down is App Exposé for the frontmost app; Control-Up is Mission
/// Control. Trackpad and the Mission Control key are not this mapping.
public enum ShowAllWindowsKeyPolicy {
    public static let downArrow: UInt16 = 125
    public static let upArrow: UInt16 = 126

    public static func matchesShowAll(
        keyCode: UInt16,
        control: Bool,
        command: Bool,
        option: Bool
    ) -> Bool {
        guard control, !command, !option else { return false }
        return keyCode == downArrow || keyCode == upArrow
    }

    public static func frontmostAppOnly(keyCode: UInt16) -> Bool {
        keyCode == downArrow
    }
}
