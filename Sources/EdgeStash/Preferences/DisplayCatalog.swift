import AppKit
import ColorSync
import CoreGraphics
import EdgeStashLogic

enum DisplayCatalog {
    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
    private static var identifierCache: [CGDirectDisplayID: String] = [:]

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    static func identifier(
        for screen: NSScreen,
        screens: [NSScreen] = NSScreen.screens
    ) -> String {
        guard let displayID = displayID(for: screen) else {
            return fallbackIdentifier(for: screen)
        }
        if let cached = identifierCache[displayID] {
            return cached
        }

        if let uuidIdentifier = uuidIdentifier(for: displayID, prefix: "display:v3:") {
            identifierCache[displayID] = uuidIdentifier
            return uuidIdentifier
        }

        let baseIdentifier = hardwareIdentifier(for: displayID)
        let matchingDisplayCount = screens.reduce(into: 0) { count, candidate in
            guard let candidateID = self.displayID(for: candidate) else { return }
            if hardwareIdentifier(for: candidateID) == baseIdentifier {
                count += 1
            }
        }
        let identifier = matchingDisplayCount > 1
            ? unitIdentifier(base: baseIdentifier, displayID: displayID)
            : baseIdentifier
        identifierCache[displayID] = identifier
        return identifier
    }

    static func connectedDisplays(screens: [NSScreen] = NSScreen.screens) -> [ConnectedDisplay] {
        screens.map { screen in
            let displayID = displayID(for: screen)
            return ConnectedDisplay(
                id: identifier(for: screen, screens: screens),
                name: screen.localizedName,
                frame: screen.frame,
                isMain: displayID.map { CGDisplayIsMain($0) != 0 } ?? false
            )
        }
        .sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            if lhs.frame.minX != rhs.frame.minX { return lhs.frame.minX < rhs.frame.minX }
            return lhs.frame.minY > rhs.frame.minY
        }
    }

    static func geometries(screens: [NSScreen] = NSScreen.screens) -> [DisplayGeometry] {
        screens.map {
            DisplayGeometry(id: identifier(for: $0, screens: screens), frame: $0.frame)
        }
    }

    /// Quartz frames for adjacency / collapse policy. Settings map drawing
    /// keeps AppKit `geometries()` so the tiles match the desktop.
    static func adjacencyGeometries(screens: [NSScreen] = NSScreen.screens) -> [DisplayGeometry] {
        cgGeometries(screens: screens)
    }

    static func cgGeometries(screens: [NSScreen] = NSScreen.screens) -> [DisplayGeometry] {
        let primaryHeight = screens.first?.frame.height ?? 0
        return screens.map {
            DisplayGeometry(
                id: identifier(for: $0, screens: screens),
                frame: StashGeometryPolicy.cgRect(fromAppKit: $0.frame, primaryHeight: primaryHeight)
            )
        }
    }

    static func screen(withID id: String, screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { identifier(for: $0, screens: screens) == id }
    }

    static func primaryHeight(screens: [NSScreen] = NSScreen.screens) -> CGFloat {
        screens.first?.frame.height ?? 900
    }

    static func invalidateIdentifierCache() {
        identifierCache.removeAll()
    }

    static func migratingLegacyPreferences(
        _ preferences: [String: DisplayEdgeSelection],
        screens: [NSScreen] = NSScreen.screens
    ) -> [String: DisplayEdgeSelection] {
        var migrated = preferences
        var obsoleteKeys = Set<String>()
        let activeIdentifiers = Set(screens.map { identifier(for: $0, screens: screens) })

        for screen in screens {
            let stableIdentifier = identifier(for: screen, screens: screens)
            var aliases: [String] = []

            if let displayID = displayID(for: screen) {
                if let legacyUUID = uuidIdentifier(for: displayID) {
                    aliases.append(legacyUUID)
                }
                let baseIdentifier = hardwareIdentifier(for: displayID)
                aliases.append(baseIdentifier)
                aliases.append(unitIdentifier(base: baseIdentifier, displayID: displayID))
                aliases.append("fallback:\(screen.localizedName):\(displayID)")
            } else {
                aliases.append("fallback:\(screen.localizedName):unknown")
            }

            if migrated[stableIdentifier] == nil {
                for alias in aliases where alias != stableIdentifier {
                    if let selection = migrated[alias] {
                        migrated[stableIdentifier] = selection
                        break
                    }
                }
            }
            for alias in aliases where alias != stableIdentifier {
                obsoleteKeys.insert(alias)
            }
        }
        for key in obsoleteKeys where !activeIdentifiers.contains(key) {
            migrated.removeValue(forKey: key)
        }
        return migrated
    }

    private static func hardwareIdentifier(for displayID: CGDirectDisplayID) -> String {
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        let kind = CGDisplayIsBuiltin(displayID) != 0 ? "builtin" : "external"
        return "display:v2:\(vendor):\(model):\(serial):\(kind)"
    }

    private static func unitIdentifier(
        base: String,
        displayID: CGDirectDisplayID
    ) -> String {
        "\(base):unit:\(CGDisplayUnitNumber(displayID))"
    }

    private static func uuidIdentifier(
        for displayID: CGDirectDisplayID,
        prefix: String = ""
    ) -> String? {
        guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return nil
        }
        let uuid = unmanagedUUID.takeRetainedValue()
        return prefix + (CFUUIDCreateString(nil, uuid) as String)
    }

    private static func fallbackIdentifier(for screen: NSScreen) -> String {
        "fallback:v2:\(screen.localizedName)"
    }
}
