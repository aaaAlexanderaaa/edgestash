import ApplicationServices
import CoreGraphics
import EdgeStashLogic
import Foundation

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

enum StashAXRead<Value> {
    case value(Value)
    case failure(AXError)
    var value: Value? { if case let .value(value) = self { return value }; return nil }
    var status: AXError { if case let .failure(error) = self { return error }; return .success }
}

enum StashAX {
    /// Bound synchronous cross-process AX IPCs so an unresponsive target app
    /// cannot freeze EdgeStash's main thread or disable the session event tap.
    static func configureDefaultTimeout(_ seconds: Float = 0.5) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds)
    }

    static func setTimeout(_ element: AXUIElement, seconds: Float) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    @discardableResult
    static func raise(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
    }

    static func read(_ element: AXUIElement, _ attribute: String) -> StashAXRead<CFTypeRef> {
        var value: CFTypeRef?
        let start = StashDiagnostics.isEnabled ? ProcessInfo.processInfo.systemUptime : nil
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        diagnoseResult(status, element: element, operation: "read", attribute: attribute, started: start)
        guard status == .success else { return .failure(status) }
        guard let value else { return .failure(.noValue) }
        return .value(value)
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        read(element, attribute).value
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, value: CFTypeRef) -> Bool {
        let start = StashDiagnostics.isEnabled ? ProcessInfo.processInfo.systemUptime : nil
        let status = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        diagnoseResult(status, element: element, operation: "write", attribute: attribute, started: start)
        return status == .success
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        boolResult(element, attribute).value
    }

    static func boolResult(_ element: AXUIElement, _ attribute: String) -> StashAXRead<Bool> {
        switch read(element, attribute) {
        case let .failure(error): return .failure(error)
        case let .value(value):
            if let flag = value as? Bool { return .value(flag) }
            if let number = value as? NSNumber { return .value(number.boolValue) }
            return .failure(.illegalArgument)
        }
    }

    @discardableResult
    static func setBool(_ element: AXUIElement, _ attribute: String, _ flag: Bool) -> Bool {
        set(element, attribute, value: flag as CFBoolean)
    }

    static func isStandardWindow(_ element: AXUIElement) -> Bool {
        string(element, kAXSubroleAttribute as String) == kAXStandardWindowSubrole
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        frameResult(of: element).value
    }

    static func frameResult(of element: AXUIElement) -> StashAXRead<CGRect> {
        let position = read(element, kAXPositionAttribute as String)
        guard case let .value(positionValue) = position else { return .failure(position.status) }
        let sizeRead = read(element, kAXSizeAttribute as String)
        guard case let .value(sizeValue) = sizeRead else { return .failure(sizeRead.status) }
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return .failure(.illegalArgument)
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return .failure(.illegalArgument)
        }
        let frame = CGRect(origin: origin, size: size)
        guard WindowRecoveryPolicy.isUsableFrame(frame) else { return .failure(.illegalArgument) }
        return .value(frame)
    }

    @discardableResult
    static func setPosition(_ element: AXUIElement, _ origin: CGPoint) -> Bool {
        setPositionStatus(element, origin) == .success
    }

    @discardableResult
    static func setPositionStatus(_ element: AXUIElement, _ origin: CGPoint) -> AXError {
        var point = origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        let start = StashDiagnostics.isEnabled ? ProcessInfo.processInfo.systemUptime : nil
        let status = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        diagnoseResult(status, element: element, operation: "write", attribute: kAXPositionAttribute as String, started: start)
        return status
    }

    @discardableResult
    static func setSize(_ element: AXUIElement, _ size: CGSize) -> Bool {
        var next = size
        guard let value = AXValueCreate(.cgSize, &next) else { return false }
        return set(element, kAXSizeAttribute as String, value: value)
    }

    /// Cross-display safe frame application. Disables AXEnhancedUserInterface
    /// temporarily (Chromium/Electron animation smoothing), moves before sizing
    /// when growing or crossing displays so AppKit does not clamp to the old
    /// display, and re-aligns position after resize.
    static func applyFrame(_ element: AXUIElement, _ frame: CGRect) -> (sized: Bool, moved: Bool) {
        guard WindowRecoveryPolicy.isUsableFrame(frame) else { return (false, false) }
        var pid: pid_t = 0
        var enhancedApp: AXUIElement?
        if AXUIElementGetPid(element, &pid) == .success, pid > 0 {
            let app = AXUIElementCreateApplication(pid)
            if bool(app, "AXEnhancedUserInterface") == true {
                if setBool(app, "AXEnhancedUserInterface", false) {
                    enhancedApp = app
                }
            }
        }
        defer {
            if let enhancedApp {
                _ = setBool(enhancedApp, "AXEnhancedUserInterface", true)
            }
        }

        let current = self.frame(of: element)
        let crossesOrGrows: Bool
        if let current {
            crossesOrGrows = frame.width > current.width + 1
                || frame.height > current.height + 1
                || abs(frame.minX - current.minX) > 200
                || abs(frame.minY - current.minY) > 200
        } else {
            crossesOrGrows = true
        }

        if crossesOrGrows {
            let movedFirst = setPosition(element, frame.origin)
            var sized = setSize(element, frame.size)
            var moved = setPosition(element, frame.origin) || movedFirst
            // Aspect-ratio flips (e.g. portrait <-> landscape) can clamp one
            // axis on the first resize before the window finishes relocating.
            if let after = self.frame(of: element),
               abs(after.width - frame.width) > 4 || abs(after.height - frame.height) > 4 {
                if setSize(element, frame.size) { sized = true }
                if setPosition(element, frame.origin) { moved = true }
            }
            return (sized, moved)
        }
        let sized = setSize(element, frame.size)
        let moved = setPosition(element, frame.origin)
        return (sized, moved)
    }

    @discardableResult
    static func setFrame(_ element: AXUIElement, _ frame: CGRect) -> Bool {
        let result = applyFrame(element, frame)
        return result.sized && result.moved
    }

    static func windows(of app: AXUIElement) -> [AXUIElement] {
        windowsResult(of: app).value ?? []
    }

    static func windowsResult(of app: AXUIElement) -> StashAXRead<[AXUIElement]> {
        switch read(app, kAXWindowsAttribute as String) {
        case let .failure(error): return .failure(error)
        case let .value(value):
            guard let windows = value as? [AXUIElement] else { return .failure(.illegalArgument) }
            return .value(windows)
        }
    }

    static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        copy(app, kAXFocusedWindowAttribute as String).map { $0 as! AXUIElement }
    }

    static func parent(of element: AXUIElement) -> AXUIElement? {
        copy(element, kAXParentAttribute as String).map { $0 as! AXUIElement }
    }

    static func windowID(of element: AXUIElement) -> UInt32? {
        var identifier: CGWindowID = 0
        let start = StashDiagnostics.isEnabled ? ProcessInfo.processInfo.systemUptime : nil
        let status = _AXUIElementGetWindow(element, &identifier)
        diagnoseResult(status, element: element, operation: "resolve", attribute: "windowNumber", started: start)
        guard status == .success, identifier != 0 else {
            return nil
        }
        return identifier
    }

    static func isMinimized(_ element: AXUIElement) -> Bool? {
        bool(element, kAXMinimizedAttribute as String)
    }

    static func isFullScreen(_ element: AXUIElement) -> Bool? {
        bool(element, "AXFullScreen")
    }

    static func canSetMinimized(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let start = StashDiagnostics.isEnabled ? ProcessInfo.processInfo.systemUptime : nil
        let status = AXUIElementIsAttributeSettable(element, kAXMinimizedAttribute as CFString, &settable)
        diagnoseResult(status, element: element, operation: "settable", attribute: kAXMinimizedAttribute as String, started: start)
        guard status == .success else {
            return false
        }
        return settable.boolValue
    }

    @discardableResult
    static func setMinimized(_ element: AXUIElement, _ minimized: Bool) -> Bool {
        guard requestMinimized(element, minimized) else { return false }
        if let observed = isMinimized(element) {
            if observed != minimized {
                StashDiagnostics.record("ax.minimize-mismatch", ["ax": String(CFHash(element)), "requested": minimized, "observed": observed])
            }
            return observed == minimized
        }
        return false
    }

    /// Submission acknowledgement only. Callers must confirm asynchronously
    /// before committing a hide; a stale false read is not rejection.
    static func requestMinimized(_ element: AXUIElement, _ minimized: Bool) -> Bool {
        guard canSetMinimized(element) else { return false }
        return setBool(element, kAXMinimizedAttribute as String, minimized)
    }

    static func roleAlive(_ element: AXUIElement) -> AXError {
        read(element, kAXRoleAttribute as String).status
    }

    private static func diagnoseResult(_ status: AXError, element: AXUIElement, operation: String,
                                       attribute: String, started: TimeInterval? = nil) {
        guard StashDiagnostics.isEnabled else { return }
        let elapsed = started.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
        // Diagnostic threshold only: one quarter of display stability's 1s;
        // no transport timeout or runtime behavior is changed.
        guard status != .success || elapsed >= 0.25 else { return }
        let key = "\(CFHash(element)):\(operation):\(attribute):\(status.rawValue)"
        StashDiagnostics.record(status == .success ? "ax.slow" : "ax.failure",
                                ["ax": String(CFHash(element)), "operation": operation,
                                 "attribute": attribute, "error": status.rawValue, "elapsed": elapsed], throttleKey: key)
    }
}
