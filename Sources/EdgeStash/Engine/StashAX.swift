import ApplicationServices
import CoreGraphics
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
        return .value(CGRect(origin: origin, size: size))
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

    static func applyFrame(_ element: AXUIElement, _ frame: CGRect) -> (sized: Bool, moved: Bool) {
        (setSize(element, frame.size), setPosition(element, frame.origin))
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
        guard canSetMinimized(element) else { return false }
        guard setBool(element, kAXMinimizedAttribute as String, minimized) else { return false }
        if let observed = isMinimized(element) {
            if observed != minimized {
                StashDiagnostics.record("ax.minimize-mismatch", ["ax": String(CFHash(element)), "requested": minimized, "observed": observed])
            }
            return observed == minimized
        }
        return true
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
