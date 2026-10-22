import Foundation
import CoreGraphics
import EdgeStashLogic

let number = kCGWindowNumber as String
let owner = kCGWindowOwnerPID as String
let alpha = kCGWindowAlpha as String
let withoutBounds: [[String: Any]] = [[number: NSNumber(value: 42), owner: NSNumber(value: 99), alpha: NSNumber(value: 0)]]
let decoded = StashSurface.recoveryWindows(from: withoutBounds)!
precondition(decoded.count == 1 && decoded[0].windowID == 42 && decoded[0].pid == 99 && decoded[0].alpha == 0)
let withoutAlpha = StashSurface.recoveryWindows(from: [[number: NSNumber(value: 42), owner: NSNumber(value: 99)]])!
precondition(withoutAlpha.count == 1 && withoutAlpha[0].alpha == nil)
precondition(StashSurface.recoveryWindows(from: [[number: NSNumber(value: 42)]]) == nil)
precondition(StashSurface.recoveryWindows(from: [])?.isEmpty == true)
let invalid = StashSurface.recoveryWindows(from: [[number: NSNumber(value: 42), owner: NSNumber(value: 99), alpha: NSNumber(value: Float.nan)]])!
precondition(invalid[0].alpha == nil)
print("Native metadata decoder passed: missing bounds retain identity, missing/NaN alpha stays unknown, incomplete identity is unavailable, successful empty stays empty")
