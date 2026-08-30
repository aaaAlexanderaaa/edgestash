import AppKit
import ApplicationServices

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CInt

@_silgen_name("CGSSetWindowAlpha")
func CGSSetWindowAlpha(_ cid: CInt, _ wid: CInt, _ alpha: Float) -> CGError

enum StashSurface {
    static func frontmostWindow(atQuartz point: CGPoint) -> (windowID: UInt32, pid: pid_t)? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? UInt32,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else {
                continue
            }
            let frame = CGRect(
                x: bounds["X"] as? CGFloat ?? 0,
                y: bounds["Y"] as? CGFloat ?? 0,
                width: bounds["Width"] as? CGFloat ?? 0,
                height: bounds["Height"] as? CGFloat ?? 0
            )
            if frame.contains(point) {
                return (windowID, pid)
            }
        }
        return nil
    }

    @discardableResult
    static func setAlpha(windowID: UInt32, alpha: Float) -> Bool {
        CGSSetWindowAlpha(CGSMainConnectionID(), CInt(windowID), alpha) == .success
    }

    /// Whether the window is on the currently active Space of its display.
    /// Parked slide-stash windows keep a lip on screen, so they list on their
    /// own Space and vanish from the list on any other.
    static func isOnScreen(windowID: UInt32, pid: pid_t) -> Bool {
        onScreenBounds(windowID: windowID, pid: pid) != nil
    }

    /// Whether the (Quartz) point is over another on-screen window of the same
    /// process. Screen-sized background windows and the session's own window
    /// do not count as siblings.
    static func isPointerInSiblingWindow(
        pid: pid_t,
        excluding windowID: UInt32?,
        atQuartz point: CGPoint
    ) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let screenFrames = NSScreen.screens.map(\.frame)
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let id = info[kCGWindowNumber as String] as? UInt32,
                  id != windowID,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else {
                continue
            }
            let frame = CGRect(
                x: bounds["X"] as? CGFloat ?? 0,
                y: bounds["Y"] as? CGFloat ?? 0,
                width: bounds["Width"] as? CGFloat ?? 0,
                height: bounds["Height"] as? CGFloat ?? 0
            )
            // Screen-sized windows are desktop backgrounds, not siblings;
            // frame sizes compare directly across the two coordinate systems.
            let isScreenSizedBackground = screenFrames.contains { screen in
                frame.width >= screen.width * 0.98 && frame.height >= screen.height * 0.98
            }
            if isScreenSizedBackground { continue }
            if frame.contains(point) { return true }
        }
        return false
    }

    static func onScreenBounds(windowID: UInt32, pid: pid_t) -> CGRect? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowNumber as String] as? UInt32) == windowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else {
                continue
            }
            return CGRect(
                x: bounds["X"] as? CGFloat ?? 0,
                y: bounds["Y"] as? CGFloat ?? 0,
                width: bounds["Width"] as? CGFloat ?? 0,
                height: bounds["Height"] as? CGFloat ?? 0
            )
        }
        return nil
    }
}
