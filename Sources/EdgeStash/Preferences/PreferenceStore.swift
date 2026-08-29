import EdgeStashLogic
import Foundation

/// Names of the notifications the preference center posts. They stay inside
/// the app process.
enum PreferenceSignal {
    static let didChange = Notification.Name("EdgeStash.preferencesChanged")
    static let menuBarVisibilityDidChange = Notification.Name("EdgeStash.menuBarVisibilityChanged")
    static let languageDidChange = Notification.Name("EdgeStash.languageChanged")
}

/// The machine-local store: one versioned JSON document under Application
/// Support. Fields are optional so a reader written against a later schema
/// still decodes an earlier document.
struct StoredDocument: Codable {
    /// Version 3 groups rescue facts into subject/placement and stores the
    /// recording time as a Date. The reader starts from an empty document
    /// when a stored one cannot be decoded; there is no compatibility path.
    static let currentVersion = 3

    var version: Int = StoredDocument.currentVersion
    var apps: [String: AppStashProfile] = [:]
    var approachWidth: CGFloat?
    var approachHeight: CGFloat?
    var revealWaitMS: Int?
    var transientMods: UInt?
    var transientKey: UInt16?
    var launchAtLogin: Bool?
    var showsMenuBarToggle: Bool?
    var decoratesSlides: Bool?
    var mergesStrips: Bool?
    var advisedStripOverload: Bool?
    var mutedMultiWindowAdvice: Bool?
    var languageID: Int?
    var dockClearance: String?
    var edgeMap: [String: DisplayEdgeSelection]?
    var ghosts: [String]?
    var rescues: [RescueDossier]?
}

enum PreferenceStore {
    /// Local first: the whole preference state lives in one file inside the
    /// EdgeStash Application Support directory, written atomically.
    static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("EdgeStash", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("store.json")
    }()

    static func load() -> StoredDocument {
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(StoredDocument.self, from: data) else {
            return StoredDocument()
        }
        return document
    }

    static func save(_ document: StoredDocument) {
        guard let data = try? JSONEncoder().encode(document) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    /// Pre-release EdgeStash builds experimented with flat defaults keys
    /// before the JSON document existed. The store never reads them; any
    /// entry left in the standard domain under one of those prefixes is dead
    /// weight, so launch sweeps it rather than enumerating keys one by one.
    static let staleKeyPrefixes: [String] = [
        "EdgeStash",
        "EdgeBar",
        "es."
    ]

    static func sweepStaleDefaultKeys(in defaults: UserDefaults) {
        let dictionary = defaults.dictionaryRepresentation()
        for key in dictionary.keys where staleKeyPrefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
