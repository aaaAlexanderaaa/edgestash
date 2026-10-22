import AppKit
import ApplicationServices
import EdgeStashLogic

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CInt

@_silgen_name("CGSSetWindowAlpha")
func CGSSetWindowAlpha(_ cid: CInt, _ wid: CInt, _ alpha: Float) -> CGError

struct StashRecoverySurface {
    let windowID: UInt32
    let pid: pid_t
    let alpha: Float?
}

enum StashSurface {
    /// A nil inventory is unavailable, not a successful empty user session.
    static func allWindows() -> [StashRecoverySurface]? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        return recoveryWindows(from: list)
    }

    static func recoveryWindows(from list: [[String: Any]]) -> [StashRecoverySurface]? {
        var windows: [StashRecoverySurface] = []
        for info in list {
            guard let id = info[kCGWindowNumber as String] as? UInt32,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }
            // Ownership must not disappear just because a minimized window
            // cannot export bounds. Unknown alpha is not an observed value 1.
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.floatValue
            windows.append(StashRecoverySurface(windowID: id, pid: pid,
                                                 alpha: alpha.flatMap { $0.isFinite ? $0 : nil }))
        }
        return windows
    }

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
        let status = CGSSetWindowAlpha(CGSMainConnectionID(), CInt(windowID), alpha)
        if status != .success {
            StashDiagnostics.record("surface.alpha-failed", ["window": windowID, "alpha": alpha, "error": status.rawValue],
                                    throttleKey: "alpha:\(windowID):\(status.rawValue)")
        }
        return status == .success
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
