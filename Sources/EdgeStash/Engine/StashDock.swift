import AppKit
import ApplicationServices
import CoreGraphics
import EdgeStashLogic

enum StashDock {
    private static var lastDown: (at: Date, inDock: Bool, bundleID: String?, windowTitle: String?)?
    private static let intentWindow: TimeInterval = 0.8

    static func noteMouseDown(at point: CGPoint) {
        let inDock = isDockPoint(point)
        if inDock, let hit = hit(at: point) {
            lastDown = (Date(), true, hit.bundleID, hit.windowTitle)
        } else {
            lastDown = (Date(), inDock, nil, nil)
        }
    }

    static func hasRecentClick(now: Date = Date()) -> Bool {
        guard let lastDown, lastDown.inDock else { return false }
        return now.timeIntervalSince(lastDown.at) <= intentWindow
    }

    static func clickedBundleID() -> String? {
        lastDown?.bundleID
    }

    static func clickedWindowTitle() -> String? {
        lastDown?.windowTitle
    }

    static func consumeRecentClick() {
        lastDown = nil
    }

    /// Best-effort Dock identity: an app icon title matches the running name;
    /// a minimized tile or peek thumbnail uses the window title.
    private static func hit(at point: CGPoint) -> (bundleID: String?, windowTitle: String?)? {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == dockProcessBundleID
        }) else {
            return nil
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let quartzY = StashGeometryPolicy.quartzOriginY(
            appKitY: point.y,
            height: 1,
            primaryHeight: primaryHeight
        )
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(quartzY), &element) == .success,
              let element else {
            return nil
        }
        let running = NSWorkspace.shared.runningApplications
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let node = current else { break }
            let subrole = StashAX.string(node, kAXSubroleAttribute as String)
            let title = StashAX.string(node, kAXTitleAttribute as String)
            let matchedApp = title.flatMap { name in
                running.first { $0.localizedName == name }
            }
            switch DockItemPolicy.kind(
                subrole: subrole,
                title: title,
                appLocalizedName: matchedApp?.localizedName
            ) {
            case .applicationIcon:
                return (matchedApp?.bundleIdentifier, nil)
            case .windowThumbnail:
                return (matchedApp?.bundleIdentifier, title)
            case .other:
                break
            }
            current = StashAX.parent(of: node)
        }
        return nil
    }

    static func isDockPoint(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else {
            return false
        }
        guard let side = Preferences.shared.resolvedDockSide() else { return false }
        let measurement = measure(screen: screen, side: side)
        return DockHitPolicy.hitRect(
            screenFrame: screen.frame,
            side: side,
            measurement: measurement
        )?.contains(point) == true
    }

    /// Assembles the Dock measurement for one display. Depth is exact
    /// whenever the Dock is visible: it is the space macOS already reserves.
    /// Extent comes from the Dock's own window in the server's window list.
    static func measure(screen: NSScreen, side: String) -> DockMeasurement {
        var measurement = DockMeasurement()
        measurement.depth = reservedDepth(screen: screen, side: side)
        measurement.revealsOnApproach = measurement.depth == nil
        if let run = dockRun(screen: screen, side: side) {
            measurement.extent = run.extent
            measurement.extentMidpoint = run.midpoint
        }
        return measurement
    }

    /// Exact depth the visible Dock reserves on this side, read from the gap
    /// between the full screen frame and the usable visible frame. The bottom
    /// gap excludes the menu bar because the menu bar only shortens the frame
    /// from the top. A parked Dock reserves nothing and reports nil.
    private static func reservedDepth(screen: NSScreen, side: String) -> CGFloat? {
        switch side {
        case "bottom":
            let depth = screen.visibleFrame.minY - screen.frame.minY
            return depth > 1 ? depth : nil
        case "left", "right":
            let depth = screen.frame.width - screen.visibleFrame.width
            return depth > 1 ? depth : nil
        default:
            return nil
        }
    }

    private static let dockProcessBundleID = "com.apple.dock"

    /// Reads the Dock's on-screen footprint from the window server: the
    /// union of on-screen Dock-owned windows sitting below normal window
    /// level along the owning rail. Returns the run's length and midpoint
    /// along the owned axis, or nil when the server exposes nothing usable.
    private static func dockRun(screen: NSScreen, side: String) -> (extent: CGFloat, midpoint: CGFloat)? {
        guard side == "left" || side == "right" || side == "bottom" else { return nil }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        guard let windows = list as? [[String: Any]] else { return nil }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let railBand = dockRailBand(screen: screen, side: side)
        var union: CGRect?
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == dockProcessBundleID,
              let layer = window[kCGWindowLayer as String] as? Int, layer < 0,
              let rawBounds = window[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            let bounds = CGRect(
                x: rawBounds["X"] ?? 0,
                y: primaryHeight - (rawBounds["Y"] ?? 0) - (rawBounds["Height"] ?? 0),
                width: rawBounds["Width"] ?? 0,
                height: rawBounds["Height"] ?? 0
            )
            guard railBand.intersects(bounds) else { continue }
            union = union?.union(bounds) ?? bounds
        }
        guard let dockFrame = union else { return nil }
        if side == "bottom" {
            return (dockFrame.width, dockFrame.midX)
        }
        return (dockFrame.height, dockFrame.midY)
    }

    /// The strip of the display the Dock can occupy on its owning side, used
    /// only to decide which server windows belong to the rail.
    private static func dockRailBand(screen: NSScreen, side: String) -> CGRect {
        let frame = screen.frame
        let depth = reservedDepth(screen: screen, side: side) ?? 80
        switch side {
        case "bottom":
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: depth)
        case "left":
            return CGRect(x: frame.minX, y: frame.minY, width: depth, height: frame.height)
        default:
            return CGRect(x: frame.maxX - depth, y: frame.minY, width: depth, height: frame.height)
        }
    }
}
