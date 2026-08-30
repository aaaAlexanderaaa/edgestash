import CoreGraphics
import Foundation

/// Leave-to-collapse rules for an expanded stash. Instant collapse on the
/// first outside sample reads as flicker when the pointer briefly crosses
/// another window, and a multi-window app collapses a window the user is
/// still effectively using. The reference product's proven numbers: collapse
/// only after the pointer has stayed outside continuously for 0.22s, and
/// count the same app's sibling windows as "inside" with a 1.5s
/// post-interaction grace so moving between an app's windows never reads as
/// leaving.
public enum LeaveCollapsePolicy {
    public static let outsideDwell: TimeInterval = 0.22
    public static let siblingInteractionGrace: TimeInterval = 1.5

    /// Whether the pointer currently counts as inside for collapse purposes:
    /// inside the geometric buffer, over a sibling window of the same app, or
    /// within the grace that follows a sibling interaction.
    public static func countsAsInside(
        geometricallyOutside: Bool,
        pointerInSibling: Bool,
        siblingFocused: Bool,
        lastSiblingInteractionAt: Date?,
        now: Date
    ) -> Bool {
        if !geometricallyOutside { return true }
        if pointerInSibling || siblingFocused { return true }
        if let lastSiblingInteractionAt,
           now.timeIntervalSince(lastSiblingInteractionAt) < siblingInteractionGrace {
            return true
        }
        return false
    }

    /// Collapse only once the pointer has stayed outside for the whole dwell.
    /// `outsideSince` is the first outside sample; nil means the pointer has
    /// not left yet.
    public static func shouldCollapse(
        outsideSince: Date?,
        now: Date
    ) -> Bool {
        guard let outsideSince else { return false }
        return now.timeIntervalSince(outsideSince) >= outsideDwell
    }
}
