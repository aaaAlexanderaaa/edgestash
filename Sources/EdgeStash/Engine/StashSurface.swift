import AppKit
import ApplicationServices

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CInt

@_silgen_name("CGSSetWindowAlpha")
func CGSSetWindowAlpha(_ cid: CInt, _ wid: CInt, _ alpha: Float) -> CGError

enum StashSurface {
    @discardableResult
    static func setAlpha(windowID: UInt32, alpha: Float) -> Bool {
        CGSSetWindowAlpha(CGSMainConnectionID(), CInt(windowID), alpha) == .success
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
