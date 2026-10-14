import AppKit
import ApplicationServices
import EdgeStashLogic

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CInt

@_silgen_name("CGSSetWindowAlpha")
func CGSSetWindowAlpha(_ cid: CInt, _ wid: CInt, _ alpha: Float) -> CGError

enum StashSurface {
    static func belongsToProcess(windowID: UInt32, pid: pid_t) -> Bool {
        let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]] ?? []
        return list.contains {
            ($0[kCGWindowNumber as String] as? UInt32) == windowID
                && ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
        }
    }

    static func frontmostWindow(atQuartz point: CGPoint) -> (windowID: UInt32, pid: pid_t)? {
        guard let hit = WindowSurfacePolicy.frontmostWindow(at: point, in: onScreenWindows()) else { return nil }
        return (hit.windowID, hit.pid)
    }

    /// Fresh, ordered metadata for a caller-owned synchronous observation pass.
    /// Never retain this across events or use it for rescue identity checks.
    static func onScreenWindows() -> [WindowSurfaceHit] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? UInt32,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else {
                return nil
            }
            let frame = CGRect(
                x: bounds["X"] as? CGFloat ?? 0,
                y: bounds["Y"] as? CGFloat ?? 0,
                width: bounds["Width"] as? CGFloat ?? 0,
                height: bounds["Height"] as? CGFloat ?? 0
            )
            return WindowSurfaceHit(
                windowID: windowID, pid: pid, frame: frame, layer: layer,
                alpha: info[kCGWindowAlpha as String] as? CGFloat ?? 1
            )
        }
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

    /// Only the topmost visible document window under the pointer counts.
    /// A sibling covered by another app cannot extend the leave grace.
    static func isPointerInSiblingWindow(
        pid: pid_t,
        excluding windowID: UInt32?,
        atQuartz point: CGPoint
    ) -> Bool {
        WindowSurfacePolicy.isPointerInSiblingWindow(
            pid: pid, excluding: windowID, at: point, in: onScreenWindows()
        )
    }

    static func onScreenBounds(windowID: UInt32, pid: pid_t) -> CGRect? {
        WindowSurfacePolicy.onScreenBounds(windowID: windowID, pid: pid, in: onScreenWindows())
    }
}
