import ApplicationServices
import CoreGraphics
import Foundation

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout CGWindowID) -> AXError

enum StashAX {
    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        let value = copy(element, attribute)
        if let flag = value as? Bool { return flag }
        return (value as? NSNumber)?.boolValue
    }

    @discardableResult
    static func setBool(_ element: AXUIElement, _ attribute: String, _ flag: Bool) -> Bool {
        set(element, attribute, value: flag as CFBoolean)
    }

    static func isStandardWindow(_ element: AXUIElement) -> Bool {
        string(element, kAXSubroleAttribute as String) == kAXStandardWindowSubrole
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = copy(element, kAXPositionAttribute as String),
              let sizeValue = copy(element, kAXSizeAttribute as String) else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func setPosition(_ element: AXUIElement, _ origin: CGPoint) -> Bool {
        setPositionStatus(element, origin) == .success
    }

    @discardableResult
    static func setPositionStatus(_ element: AXUIElement, _ origin: CGPoint) -> AXError {
        var point = origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
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
        (copy(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    }

    static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        copy(app, kAXFocusedWindowAttribute as String).map { $0 as! AXUIElement }
    }

    static func parent(of element: AXUIElement) -> AXUIElement? {
        copy(element, kAXParentAttribute as String).map { $0 as! AXUIElement }
    }

    static func windowID(of element: AXUIElement) -> UInt32? {
        var identifier: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &identifier) == .success, identifier != 0 else {
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
        guard AXUIElementIsAttributeSettable(element, kAXMinimizedAttribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    @discardableResult
    static func setMinimized(_ element: AXUIElement, _ minimized: Bool) -> Bool {
        guard canSetMinimized(element) else { return false }
        guard setBool(element, kAXMinimizedAttribute as String, minimized) else { return false }
        if let observed = isMinimized(element) {
            return observed == minimized
        }
        return true
    }

    static func roleAlive(_ element: AXUIElement) -> AXError {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
    }
}
