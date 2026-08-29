import CoreGraphics
import Foundation

/// AppKit-free settings layout and list-identity rules.
public enum SettingsSurfacePolicy {
    public static let railWidth: CGFloat = 188
    public static let idealWindowWidth: CGFloat = 920
    public static let minimumWindowWidth: CGFloat = 720
    /// Slack below 920 − 188 so a 1pt split divider does not force a stack.
    public static let stackHoverPreviewBelow: CGFloat = 700
    /// Width of a Settings note popover. A caption-size line measures about
    /// fifty characters here — long enough for the edge-behavior notes to
    /// wrap to two lines, short enough that the popover never spans the page
    /// column.
    public static let notePopoverWidth: CGFloat = 300

    public static func pageWidth(windowWidth: CGFloat, dividerWidth: CGFloat = 1) -> CGFloat {
        windowWidth - railWidth - dividerWidth
    }

    public static func stackHoverPreview(pageWidth: CGFloat) -> Bool {
        pageWidth < stackHoverPreviewBelow
    }

    public static func uniquedBundleIDsPreservingOrder(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
