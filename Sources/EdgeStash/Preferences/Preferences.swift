import AppKit
import Combine
import EdgeStashLogic
import Foundation
import ServiceManagement

final class Preferences: ObservableObject {
    static let shared = Preferences()

    /// Hover gate defaults: 60pt of exit hysteresis on each axis, a 150ms
    /// reveal delay in the fast hover-intent band, and a 500pt ceiling that
    /// stays well inside a third of a common display width.
    static let defaultGateSpanX: CGFloat = 60
    static let defaultGateSpanY: CGFloat = 60
    static let maxGateSpanX: CGFloat = 500
    static let maxGateSpanY: CGFloat = 500
    static let defaultRevealDelayMS: Int = 150

    /// Chromatic tokens share one saturation and brightness so a new hue is
    /// just a token. Saturation is high enough that the color still reads as
    /// itself after the glass plate and wash.
    private static let stripColorWheel: [String: CGFloat] = [
        "azure": 207,
        "moss": 140,
        "crimson": 356,
        "amber": 32,
        "violet": 268,
        "rose": 334,
        "gold": 48
    ]
    private static let stripSaturation: CGFloat = 0.78
    private static let stripBrightness: CGFloat = 0.96

    @Published var appProfiles: [String: AppStashProfile] {
        didSet { persistUserChange(notify: PreferenceSignal.didChange) }
    }

    @Published var gateSpanX: CGFloat = defaultGateSpanX {
        didSet {
            let clamped = Self.bounded(gateSpanX, ceiling: Self.maxGateSpanX)
            if gateSpanX != clamped {
                gateSpanX = clamped
                return
            }
            persistUserChange(notify: PreferenceSignal.didChange)
        }
    }

    @Published var gateSpanY: CGFloat = defaultGateSpanY {
        didSet {
            let clamped = Self.bounded(gateSpanY, ceiling: Self.maxGateSpanY)
            if gateSpanY != clamped {
                gateSpanY = clamped
                return
            }
            persistUserChange(notify: PreferenceSignal.didChange)
        }
    }

    @Published var revealDelayMS: Int = defaultRevealDelayMS {
        didSet { persistUserChange(notify: PreferenceSignal.didChange) }
    }

    @Published var transientChordModifiers: UInt? {
        didSet { persistUserChange(notify: PreferenceSignal.didChange) }
    }

    @Published var transientChordKeyCode: UInt16? {
        didSet { persistUserChange(notify: PreferenceSignal.didChange) }
    }

    @Published var openAtLogin: Bool = false {
        didSet { persistUserChange() }
    }

    @Published var menuBarItemVisible: Bool = true {
        didSet { persistUserChange(notify: PreferenceSignal.menuBarVisibilityDidChange) }
    }

    @Published var decoratesSlides: Bool = true {
        didSet { persistUserChange(notify: PreferenceSignal.didChange) }
    }

    @Published var mergesStrips: Bool = true {
        didSet { persistUserChange(notify: PreferenceSignal.didChange) }
    }

    @Published var advisedStripOverload: Bool = false {
        didSet { persistUserChange() }
    }

    @Published var advisedSeamRevealLimitation: Bool = false {
        didSet { persistUserChange() }
    }

    @Published var mutedMultiWindowAdvice: Bool = false {
        didSet { persistUserChange() }
    }

    @Published var language: Int = 0 {
        didSet { persistUserChange(notify: PreferenceSignal.languageDidChange) }
    }

    @Published var dockClearanceRawValue: String = DockClearanceMode.automatic.rawValue {
        didSet { persistUserChange(notify: PreferenceSignal.didChange) }
    }

    @Published var displayEdgePreferences: [String: DisplayEdgeSelection] = [:] {
        didSet { persistUserChange(notify: PreferenceSignal.didChange) }
    }

    @Published var ghostedWindowIDs: [String] = [] {
        didSet { persistUserChange() }
    }

    @Published var rescueDossiers: [RescueDossier] = [] {
        didSet { persistUserChange() }
    }

    @Published private(set) var displayTopologyRevision: UInt = 0

    /// `didSet` on loaded fields must not notify while `shared` is still
    /// inside `dispatch_once`.
    private var isHydrating = false

    private init() {
        isHydrating = true
        defer { isHydrating = false }
        PreferenceStore.sweepStaleDefaultKeys(in: .standard)
        let stored = PreferenceStore.load()

        let loadedProfiles = stored.apps.mapValues { profile in
            var normalized = profile
            normalized.tint = Self.migratedTintToken(profile.tint)
            normalized.sides = Self.normalizeSnapSide(profile.sides)
            normalized.chord = profile.chord.map { chord in
                var updated = chord
                updated.mods = AppShortcutPolicy.normalizedModifiers(chord.mods)
                return updated
            }
            return normalized
        }
        self.appProfiles = loadedProfiles

        if let savedWidth = stored.approachWidth, savedWidth > 0 {
            self.gateSpanX = Self.bounded(savedWidth, ceiling: Self.maxGateSpanX)
        }
        if let savedHeight = stored.approachHeight, savedHeight > 0 {
            self.gateSpanY = Self.bounded(savedHeight, ceiling: Self.maxGateSpanY)
        }
        if let savedWait = stored.revealWaitMS {
            self.revealDelayMS = savedWait
        }
        if let savedMods = stored.transientMods {
            self.transientChordModifiers = savedMods
        }
        if let savedKey = stored.transientKey {
            self.transientChordKeyCode = savedKey
        }
        if let showsToggle = stored.showsMenuBarToggle {
            self.menuBarItemVisible = showsToggle
        }
        if let decorates = stored.decoratesSlides {
            self.decoratesSlides = decorates
        }
        if let merges = stored.mergesStrips {
            self.mergesStrips = merges
        }
        if let advised = stored.advisedStripOverload {
            self.advisedStripOverload = advised
        }
        if let advisedSeam = stored.advisedSeamRevealLimitation {
            self.advisedSeamRevealLimitation = advisedSeam
        }
        if let muted = stored.mutedMultiWindowAdvice {
            self.mutedMultiWindowAdvice = muted
        }
        if let savedLanguage = stored.languageID {
            self.language = savedLanguage
        } else {
            self.language = InterfaceLanguage.system.rawValue
        }
        if let rawMode = stored.dockClearance, DockClearanceMode(rawValue: rawMode) != nil {
            self.dockClearanceRawValue = rawMode
        }
        if let edgeMap = stored.edgeMap {
            self.displayEdgePreferences = DisplayCatalog.migratingLegacyPreferences(edgeMap)
        }
        if let ghosts = stored.ghosts {
            self.ghostedWindowIDs = ghosts
        }
        if let rescues = stored.rescues {
            self.rescueDossiers = rescues
        }

        loadLaunchAtLogin(storedLaunchFlag: stored.launchAtLogin)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func snapshot() -> StoredDocument {
        var stored = StoredDocument()
        stored.apps = appProfiles
        stored.approachWidth = gateSpanX
        stored.approachHeight = gateSpanY
        stored.revealWaitMS = revealDelayMS
        stored.transientMods = transientChordModifiers
        stored.transientKey = transientChordKeyCode
        stored.launchAtLogin = openAtLogin
        stored.showsMenuBarToggle = menuBarItemVisible
        stored.decoratesSlides = decoratesSlides
        stored.mergesStrips = mergesStrips
        stored.advisedStripOverload = advisedStripOverload
        stored.advisedSeamRevealLimitation = advisedSeamRevealLimitation
        stored.mutedMultiWindowAdvice = mutedMultiWindowAdvice
        stored.languageID = language
        stored.dockClearance = dockClearanceRawValue
        stored.edgeMap = displayEdgePreferences
        stored.ghosts = ghostedWindowIDs
        stored.rescues = rescueDossiers
        return stored
    }

    private func save() {
        PreferenceStore.save(snapshot())
    }

    private func persistUserChange(notify name: Notification.Name? = nil) {
        guard PreferencePublicationPolicy.shouldPublishSideEffects(isHydrating: isHydrating) else {
            return
        }
        save()
        if let name {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    /// Tint tokens name how a strip is colored: "adaptive" tracks the system
    /// appearance, "ivory"/"graphite" are fixed neutrals, wheel tokens map to
    /// generated pastels, and "#RRGGBB" is a user-picked exact color.
    func stripColor(for bundleID: String) -> NSColor {
        let token = tintKey(for: bundleID)
        if token == "adaptive" {
            return NSColor(name: nil) { appearance in
                Self.appearanceIsDark(appearance) ? .white : .black
            }
        }
        if let hue = Self.stripColorWheel[token] {
            return NSColor(
                hue: hue / 360,
                saturation: Self.stripSaturation,
                brightness: Self.stripBrightness,
                alpha: 1
            )
        }
        if token.hasPrefix("#"), let decoded = NSColor(decodingColorCode: token) {
            return decoded
        }
        if token == "graphite" { return .black }
        if token == "ivory" { return .white }
        return .white
    }

    /// Dark appearance detection via the system's own best-match ranking;
    /// an unknown appearance reads as light, the safer default for contrast.
    private static func appearanceIsDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    func addGhostedWindowID(pid: pid_t, windowID: UInt32) {
        let record = "\(pid):\(windowID)"
        if !ghostedWindowIDs.contains(record) {
            ghostedWindowIDs.append(record)
        }
    }

    func removeGhostedWindowID(pid: pid_t, windowID: UInt32) {
        let record = "\(pid):\(windowID)"
        ghostedWindowIDs.removeAll { $0 == record }
    }

    func upsertRescueDossier(_ dossier: RescueDossier) {
        if let index = rescueDossiers.firstIndex(where: {
            $0.subject.processID == dossier.subject.processID
                && $0.subject.windowNumber == dossier.subject.windowNumber
        }) {
            rescueDossiers[index] = dossier
        } else {
            rescueDossiers.append(dossier)
        }
    }

    func removeRescueDossier(processID: pid_t, windowNumber: UInt32) {
        rescueDossiers.removeAll {
            $0.subject.processID == processID && $0.subject.windowNumber == windowNumber
        }
        removeGhostedWindowID(pid: processID, windowID: windowNumber)
    }

    func hasPendingRescueDossiers() -> Bool {
        !rescueDossiers.isEmpty
    }

    func stashActive(bundleID: String) -> Bool {
        appProfiles[bundleID]?.stashOn ?? false
    }

    func tintKey(for bundleID: String) -> String {
        appProfiles[bundleID]?.tint ?? "adaptive"
    }

    func tintAlpha(for bundleID: String) -> Double {
        appProfiles[bundleID]?.alpha ?? 1.0
    }

    func snapPreference(for bundleID: String) -> String {
        Self.normalizeSnapSide(appProfiles[bundleID]?.sides)
    }

    func applyAppStash(bundleID: String, stashOn: Bool, tint: String) {
        let existing = appProfiles[bundleID]
        appProfiles[bundleID] = AppStashProfile(
            stashOn: stashOn,
            tint: tint,
            alpha: existing?.alpha,
            sides: Self.normalizeSnapSide(existing?.sides),
            chord: existing?.chord,
            chordScope: existing?.chordScope
        )
    }

    func applyOpacity(bundleID: String, opacity: Double) {
        guard var setting = appProfiles[bundleID] else { return }
        setting.alpha = opacity
        appProfiles[bundleID] = setting
    }

    func applySnapSide(bundleID: String, snapSide: String) {
        guard var setting = appProfiles[bundleID] else { return }
        setting.sides = Self.normalizeSnapSide(snapSide)
        appProfiles[bundleID] = setting
    }

    func applyGlobalOpacity(_ opacity: Double) {
        var updated = appProfiles
        for (key, var setting) in updated where setting.stashOn {
            setting.alpha = opacity
            updated[key] = setting
        }
        appProfiles = updated
    }

    func applyGlobalSnapSide(_ snapSide: String) {
        var updated = appProfiles
        let normalized = Self.normalizeSnapSide(snapSide)
        for (key, var setting) in updated where setting.stashOn {
            setting.sides = normalized
            updated[key] = setting
        }
        appProfiles = updated
    }

    var dockClearance: DockClearanceMode {
        DockClearanceMode(rawValue: dockClearanceRawValue) ?? .automatic
    }

    func setDockClearance(_ mode: DockClearanceMode) {
        dockClearanceRawValue = mode.rawValue
    }

    func resolvedDockSide() -> String? {
        switch dockClearance {
        case .automatic:
            return Self.detectedDockSide()
        case .left, .right, .bottom:
            return dockClearance.rawValue
        }
    }

    /// The Dock never sits at the top, so the side it occupies announces
    /// itself as the gap between a display's full frame and the frame macOS
    /// reports as usable. When displays disagree, the majority side wins.
    static func detectedDockSide(screens: [NSScreen] = NSScreen.screens) -> String? {
        var tallies: [String: Int] = [:]
        for screen in screens {
            let full = screen.frame
            let usable = screen.visibleFrame
            if usable.minY - full.minY > 1 {
                tallies["bottom", default: 0] += 1
            } else if usable.minX - full.minX > 1 {
                tallies["left", default: 0] += 1
            } else if full.maxX - usable.maxX > 1 {
                tallies["right", default: 0] += 1
            }
        }
        return tallies.max { $0.value < $1.value }?.key
    }

    func displayEdgeSelection(
        for display: ConnectedDisplay,
        screens: [NSScreen] = NSScreen.screens
    ) -> DisplayEdgeSelection {
        let geometries = DisplayCatalog.adjacencyGeometries(screens: screens)
        let geometry = geometries.first { $0.id == display.id }
            ?? DisplayGeometry(id: display.id, frame: display.frame)
        return DisplayEdgePolicy.resolvedSelection(
            for: geometry,
            in: geometries,
            preferences: displayEdgePreferences
        )
    }

    func setDisplayEdgeEnabled(
        _ enabled: Bool,
        edge: DisplayEdge,
        display: ConnectedDisplay,
        screens: [NSScreen] = NSScreen.screens
    ) {
        var selection = displayEdgeSelection(for: display, screens: screens)
        selection.setEnabled(enabled, for: edge)
        displayEdgePreferences[display.id] = selection
    }

    func resetDisplayEdgeSelection(displayID: String) {
        displayEdgePreferences.removeValue(forKey: displayID)
    }

    func setChord(bundleID: String, modifiers: UInt, keyCode: UInt16) {
        guard var setting = appProfiles[bundleID] else { return }
        setting.chord = AppChord(
            mods: AppShortcutPolicy.normalizedModifiers(modifiers),
            key: keyCode
        )
        appProfiles[bundleID] = setting
    }

    func clearChord(bundleID: String) {
        guard var setting = appProfiles[bundleID] else { return }
        setting.chord = nil
        appProfiles[bundleID] = setting
    }

    func chordScope(for bundleID: String) -> AppShortcutWindowScope {
        AppShortcutPolicy.resolvedScope(appProfiles[bundleID]?.chordScope)
    }

    func setShortcutWindowScope(_ scope: AppShortcutWindowScope, bundleID: String) {
        guard var setting = appProfiles[bundleID] else { return }
        setting.chordScope = scope
        appProfiles[bundleID] = setting
    }

    func setTransientChord(modifiers: UInt, keyCode: UInt16) {
        transientChordModifiers = AppShortcutPolicy.normalizedModifiers(modifiers)
        transientChordKeyCode = keyCode
    }

    func clearTransientChord() {
        transientChordModifiers = nil
        transientChordKeyCode = nil
    }

    func updateLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enable {
                    if service.status != .enabled {
                        try service.register()
                    }
                } else if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                }
            } catch {
                NSLog("[EdgeStash] SMAppService \(enable ? "register" : "unregister") failed: \(error)")
            }
            applyLaunchAtLogin(
                LaunchAtLoginSync.publishedState(
                    enabled: service.status == .enabled,
                    requiresApproval: service.status == .requiresApproval
                )
            )
        } else {
            let escapedPath = Self.appleScriptEscaped(Bundle.main.bundlePath)
            let script = enable
                ? "tell application \"System Events\" to make login item at end with properties {path:\"\(escapedPath)\", hidden:false, name:\"EdgeStash\"}"
                : "tell application \"System Events\" to delete login item \"EdgeStash\""
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                var succeeded = false
                do {
                    try process.run()
                    process.waitUntilExit()
                    succeeded = process.terminationStatus == 0
                } catch {
                    NSLog("[EdgeStash] osascript login item update failed: \(error)")
                }
                DispatchQueue.main.async {
                    self.applyLaunchAtLogin(
                        LaunchAtLoginSync.publishedState(actualStatus: succeeded ? enable : !enable)
                    )
                }
            }
        }
    }

    @objc private func handleScreenParametersChange() {
        DisplayCatalog.invalidateIdentifierCache()
        let migrated = DisplayCatalog.migratingLegacyPreferences(displayEdgePreferences)
        if migrated != displayEdgePreferences {
            displayEdgePreferences = migrated
        }
        displayTopologyRevision &+= 1
        postChange()
    }

    private func postChange() {
        NotificationCenter.default.post(name: PreferenceSignal.didChange, object: nil)
    }

    private func loadLaunchAtLogin(storedLaunchFlag: Bool?) {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            let enabled = LaunchAtLoginSync.publishedState(
                enabled: status == .enabled,
                requiresApproval: status == .requiresApproval
            )
            self.openAtLogin = enabled
        } else {
            let enabled = LaunchAtLoginSync.publishedState(
                actualStatus: LaunchAtLoginSync.resolvedInitialStatus(
                    queriedExists: Self.legacyLoginItemExists(),
                    cachedStatus: storedLaunchFlag
                )
            )
            self.openAtLogin = enabled
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        if openAtLogin != enabled {
            openAtLogin = enabled
        } else {
            save()
        }
    }

    /// Gates a stored span to the non-negative range below `ceiling`.
    private static func bounded(_ value: CGFloat, ceiling: CGFloat) -> CGFloat {
        max(0, min(value, ceiling))
    }

    /// Stash sides are named for what they admit: one side or both.
    /// Anything unrecognized reads as both.
    static func normalizeSnapSide(_ rawValue: String?) -> String {
        switch rawValue {
        case "left":
            return "left"
        case "right":
            return "right"
        default:
            return "both"
        }
    }

    /// Pre-release documents named tints with plain color words and a
    /// "custom_" hex prefix; the current token set renames both. Unknown
    /// tokens fall back to adaptive rather than guessing a color.
    static func migratedTintToken(_ rawValue: String?) -> String {
        guard let rawValue else { return "adaptive" }
        if rawValue.hasPrefix("custom_") {
            return "#" + rawValue.dropFirst("custom_".count)
        }
        let renamed: [String: String] = [
            "auto": "adaptive",
            "white": "ivory",
            "black": "graphite",
            "blue": "azure",
            "green": "moss",
            "red": "crimson",
            "yellow": "amber",
            "orange": "amber",
            "purple": "violet",
            "pink": "rose"
        ]
        return renamed[rawValue] ?? (rawValue.hasPrefix("#") ? rawValue : "adaptive")
    }

    private static func legacyLoginItemExists(itemName: String = "EdgeStash") -> Bool? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", LaunchAtLoginSync.existsScript(itemName: itemName)]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return LaunchAtLoginSync.parseExistsOutput(text)
        } catch {
            NSLog("[EdgeStash] osascript login item query failed: \(error)")
            return nil
        }
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
