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
        // Always include the stable unit suffix when UUID is absent so
        // connecting a second identical monitor never renames the first one.
        let identifier = unitIdentifier(base: baseIdentifier, displayID: displayID)
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
        return screens.map { screen in
            let id = identifier(for: screen, screens: screens)
            let fallbackFull = StashGeometryPolicy.cgRect(fromAppKit: screen.frame, primaryHeight: primaryHeight)
            let cgFull: CGRect
            if let cgID = displayID(for: screen) {
                let direct = CGDisplayBounds(cgID)
                cgFull = (direct.width > 0 && direct.height > 0 && direct.minX.isFinite && direct.minY.isFinite)
                    ? direct : fallbackFull
            } else {
                cgFull = fallbackFull
            }
            // Menu-bar and Dock insets are relative deltas on the same screen,
            // making visibleFrame immune to primaryHeight transition lag.
            let topInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let bottomInset = max(0, screen.visibleFrame.minY - screen.frame.minY)
            let leftInset = max(0, screen.visibleFrame.minX - screen.frame.minX)
            let rightInset = max(0, screen.frame.maxX - screen.visibleFrame.maxX)
            let cgVisible = CGRect(
                x: cgFull.minX + leftInset,
                y: cgFull.minY + topInset,
                width: max(1, cgFull.width - leftInset - rightInset),
                height: max(1, cgFull.height - topInset - bottomInset)
            )
            return DisplayGeometry(id: id, frame: cgFull, visibleFrame: cgVisible)
        }
    }

    static func diagnosticDisplays(screens: [NSScreen] = NSScreen.screens) -> [[String: Any]] {
        let geometries = cgGeometries(screens: screens)
        return zip(screens, geometries).map { screen, geometry in
            let cgID = displayID(for: screen) ?? 0
            return [
                "id": geometry.id,
                "cgID": cgID,
                "vendor": cgID != 0 ? CGDisplayVendorNumber(cgID) : 0,
                "model": cgID != 0 ? CGDisplayModelNumber(cgID) : 0,
                "serial": cgID != 0 ? CGDisplaySerialNumber(cgID) : 0,
                "unit": cgID != 0 ? CGDisplayUnitNumber(cgID) : 0,
                "builtin": cgID != 0 && CGDisplayIsBuiltin(cgID) != 0,
                "scale": Double(screen.backingScaleFactor),
                "frame": [Double(geometry.frame.minX), Double(geometry.frame.minY),
                          Double(geometry.frame.width), Double(geometry.frame.height)],
                "visibleFrame": [Double(geometry.visibleFrame.minX), Double(geometry.visibleFrame.minY),
                                 Double(geometry.visibleFrame.width), Double(geometry.visibleFrame.height)]
            ]
        }
    }

    static func screen(withID id: String, screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { identifier(for: $0, screens: screens) == id }
    }

    static func builtinIdentifier(screens: [NSScreen] = NSScreen.screens) -> String? {
        screens.first { screen in
            displayID(for: screen).map { CGDisplayIsBuiltin($0) != 0 } ?? false
        }.map { identifier(for: $0, screens: screens) }
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
