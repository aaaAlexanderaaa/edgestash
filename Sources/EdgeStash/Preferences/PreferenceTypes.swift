import AppKit
import EdgeStashLogic

/// One persisted shortcut chord for an app.
struct AppChord: Codable, Equatable {
    var mods: UInt
    var key: UInt16
}

/// Per-application stash profile. The stored shape is EdgeStash's own
/// document format; there is no compatibility reader for other layouts.
struct AppStashProfile: Codable, Equatable {
    var stashOn: Bool
    var tint: String
    var alpha: Double?
    var sides: String?
    var chord: AppChord?
    var chordScope: AppShortcutWindowScope?

    init(
        stashOn: Bool,
        tint: String,
        alpha: Double? = nil,
        sides: String? = nil,
        chord: AppChord? = nil,
        chordScope: AppShortcutWindowScope? = nil
    ) {
        self.stashOn = stashOn
        self.tint = tint
        self.alpha = alpha
        self.sides = sides
        self.chord = chord
        self.chordScope = chordScope
    }
}

enum DockClearanceMode: String, CaseIterable {
    case automatic
    case left
    case right
    case bottom
}

enum InterfaceLanguage: Int {
    case system = 0
    case chinese = 1
    case english = 2
}

struct AppEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: NSImage?
    var isRunning: Bool
}

struct ConnectedDisplay: Identifiable, Equatable {
    let id: String
    let name: String
    let frame: CGRect
    let isMain: Bool
}

/// One geometry value in the local store: a bare point when the extent is
/// absent, a rectangle when present. One type for both keeps placement facts
/// uniform — every rescue fact is an origin carrying an optional extent.
struct StoredGeometry: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat?
    var height: CGFloat?

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
        width = nil
        height = nil
    }

    init(_ rect: CGRect) {
        x = rect.minX
        y = rect.minY
        width = rect.width
        height = rect.height
    }

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }

    var rect: CGRect? {
        guard let width, let height else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Who a rescue promise is about. The window number is the authoritative
/// handle while it stays valid; bundle and process identifiers cover the
/// relaunch case.
struct RescuedSubject: Codable, Equatable {
    var bundleID: String
    var processID: Int32
    var windowNumber: UInt32
}

/// Where the window sat when it was stashed, in Quartz coordinates.
struct RescuedPlacement: Codable, Equatable {
    var edge: Int
    var frame: StoredGeometry
    var display: StoredGeometry
}

/// A pending promise to bring a stashed window back after a crash. Cleared
/// only when the window is visible again in its recorded shape, or known to
/// be gone.
struct RescueDossier: Codable, Equatable {
    var subject: RescuedSubject
    var placement: RescuedPlacement
    /// Where the revealed window should park, clear of the edge marker.
    var landing: StoredGeometry
    var recordedAt: Date
}
