import Foundation

public enum LaunchAtLoginSync {
    public static func publishedState(actualStatus: Bool) -> Bool {
        actualStatus
    }

    public static func resolvedInitialStatus(queriedExists: Bool?, cachedStatus: Bool?) -> Bool {
        queriedExists ?? cachedStatus ?? false
    }

    public static func parseExistsOutput(_ output: String) -> Bool? {
        switch output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    public static func existsScript(itemName: String) -> String {
        let escaped = itemName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "tell application \"System Events\" to login item \"\(escaped)\" exists"
    }
}
