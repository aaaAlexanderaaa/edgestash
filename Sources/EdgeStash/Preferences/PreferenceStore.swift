import EdgeStashLogic
import Foundation

/// Names of the notifications the preference center posts. They stay inside
/// the app process.
enum PreferenceSignal {
    static let didChange = Notification.Name("EdgeStash.preferencesChanged")
    static let menuBarVisibilityDidChange = Notification.Name("EdgeStash.menuBarVisibilityChanged")
    static let languageDidChange = Notification.Name("EdgeStash.languageChanged")
}

/// Versioned local settings. Rescue records also have an independent journal
/// so decoding an ordinary preference cannot discard visibility recovery.
struct StoredDocument: Codable {
    /// Version 3 groups rescue facts into subject/placement and stores the
    /// recording time as a Date. Rescue storage is independent of settings.
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
    var advisedSeamRevealLimitation: Bool?
    var mutedMultiWindowAdvice: Bool?
    var languageID: Int?
    var dockClearance: String?
    var edgeMap: [String: DisplayEdgeSelection]?
    var ghosts: [String]?
    var rescues: [RescueDossier]?
    var screenSets: [StoredScreenSet]?
    var partiallyDecoded = false
    var unreadableRescues = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, apps, approachWidth, approachHeight, revealWaitMS, transientMods, transientKey
        case launchAtLogin, showsMenuBarToggle, decoratesSlides, mergesStrips, advisedStripOverload
        case advisedSeamRevealLimitation, mutedMultiWindowAdvice, languageID, dockClearance, edgeMap
        case ghosts, rescues, screenSets
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var partial = false
        func read<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            do { return try values.decodeIfPresent(type, forKey: key) }
            catch { partial = true; return nil }
        }
        version = read(Int.self, .version) ?? Self.currentVersion
        if let profiles = try? values.nestedContainer(keyedBy: StoreKey.self, forKey: .apps) {
            for key in profiles.allKeys {
                if let profile = try? profiles.decode(AppStashProfile.self, forKey: key) { apps[key.stringValue] = profile }
                else { partial = true }
            }
        } else if values.contains(.apps) { partial = true }
        approachWidth = read(CGFloat.self, .approachWidth)
        approachHeight = read(CGFloat.self, .approachHeight)
        revealWaitMS = read(Int.self, .revealWaitMS)
        transientMods = read(UInt.self, .transientMods)
        transientKey = read(UInt16.self, .transientKey)
        launchAtLogin = read(Bool.self, .launchAtLogin)
        showsMenuBarToggle = read(Bool.self, .showsMenuBarToggle)
        decoratesSlides = read(Bool.self, .decoratesSlides)
        mergesStrips = read(Bool.self, .mergesStrips)
        advisedStripOverload = read(Bool.self, .advisedStripOverload)
        advisedSeamRevealLimitation = read(Bool.self, .advisedSeamRevealLimitation)
        mutedMultiWindowAdvice = read(Bool.self, .mutedMultiWindowAdvice)
        languageID = read(Int.self, .languageID)
        dockClearance = read(String.self, .dockClearance)
        edgeMap = read([String: DisplayEdgeSelection].self, .edgeMap)
        ghosts = read([String].self, .ghosts)
        rescues = read([RescueDossier].self, .rescues)
        unreadableRescues = values.contains(.rescues) && rescues == nil
            && (try? values.decodeNil(forKey: .rescues)) != true
        screenSets = read([StoredScreenSet].self, .screenSets)
        partiallyDecoded = partial
    }
}

enum PreferenceStore {
    private static let ioLock = NSLock()
    private(set) static var lastSaveFailed = false
    private(set) static var rescueSaveFailed = false
    /// Main settings file; rescue journal and recovery copies share this local directory.
    static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("EdgeStash", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("store.json")
    }()

    static func load(at url: URL = fileURL) -> StoredDocument {
        ioLock.lock()
        defer { ioLock.unlock() }
        var document = loadPreferences(at: url)
        lastSaveFailed = document.partiallyDecoded || document.unreadableRescues
        switch readRescues(at: url, legacy: document) {
        case let .available(records): document.rescues = records; rescueSaveFailed = false
        case .unavailable:
            rescueSaveFailed = true
            NSLog("[EdgeStash] Rescue journal unreadable; new hides are blocked")
        }
        return document
    }

    @discardableResult
    static func save(_ document: StoredDocument, at url: URL = fileURL) -> Bool {
        ioLock.lock()
        defer { ioLock.unlock() }
        let saved = acknowledgedSave {
            switch readData(at: url) {
            case let .available(previous):
                let decoded = try? JSONDecoder().decode(StoredDocument.self, from: previous)
                let suffix = decoded == nil || decoded?.partiallyDecoded == true ? "damaged" : "previous"
                try write(previous, to: sibling(url, "store.\(suffix).json"))
            case .unavailable: throw CocoaError(.fileReadUnknown)
            case .absent: break
            }
            try write(JSONEncoder().encode(document), to: url)
        }
        lastSaveFailed = !saved
        return saved
    }

    /// This acknowledgement, independent of ordinary settings, is the hide gate.
    @discardableResult
    static func saveRescues(_ records: [RescueDossier], replacing expected: [RescueDossier]? = nil,
                            at url: URL = fileURL) -> Bool {
        ioLock.lock()
        defer { ioLock.unlock() }
        let saved = acknowledgedSave {
            guard case let .available(current) = readRescues(at: url, legacy: loadPreferences(at: url)) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if let expected, current != expected {
                throw NSError(domain: "EdgeStash.RescueStoreChanged", code: 1)
            }
            let journal = sibling(url, "rescues.json")
            // Both copies must contain this complete acknowledged set, not
            // merely the preceding set which can lack the newest hidden window.
            let data = try JSONEncoder().encode(records)
            try write(data, to: sibling(url, "rescues.previous.json"))
            try write(data, to: journal)
        }
        rescueSaveFailed = !saved
        return saved
    }

    private enum RescueRead { case available([RescueDossier]), unavailable }
    private enum FileRead { case available(Data), absent, unavailable }

    private static func readData(at url: URL) -> FileRead {
        do { return .available(try Data(contentsOf: url)) }
        catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain,
               [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(failure.code) { return .absent }
            return .unavailable
        }
    }

    private static func readRescues(at url: URL, legacy: StoredDocument) -> RescueRead {
        var exists = false
        for name in ["rescues.json", "rescues.previous.json"] {
            let candidate = sibling(url, name)
            switch readData(at: candidate) {
            case .absent: continue
            case .unavailable: exists = true
            case let .available(data):
                exists = true
                if let records = try? JSONDecoder().decode([RescueDossier].self, from: data) {
                    return .available(records)
                }
            }
        }
        guard !exists, !legacy.unreadableRescues else { return .unavailable }
        return .available(legacy.rescues ?? [])
    }

    private static func loadPreferences(at url: URL) -> StoredDocument {
        let original = readData(at: url)
        for candidate in [url, sibling(url, "store.previous.json")] {
            if case let .available(data) = readData(at: candidate),
               var document = try? JSONDecoder().decode(StoredDocument.self, from: data) {
                if candidate != url { document.partiallyDecoded = true }
                return document
            }
        }
        var empty = StoredDocument()
        if case .absent = original {} else { empty.unreadableRescues = true }
        return empty
    }

    private static func sibling(_ url: URL, _ name: String) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(name)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard try Data(contentsOf: url) == data else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func acknowledgedSave(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            return true
        } catch {
            let failure = error as NSError
            NSLog("[EdgeStash] Local persistence failed: %@ %ld", failure.domain, failure.code)
            return false
        }
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

private struct StoreKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
