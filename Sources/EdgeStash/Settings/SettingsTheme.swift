import AppKit
import EdgeStashLogic
import SwiftUI

/// EdgeStash Settings visual language. Interactive accents follow the user's
/// system accent color, which is the platform-appropriate brand treatment for
/// a settings surface; only the neutral surfaces (ink, glass, bezel,
/// hairline) are EdgeStash-owned and sit on a fixed gray ramp.
enum SettingsTheme {
    enum ColorToken {
        static let rail = Color(.controlAccentColor)
        static let railMuted = Color(.controlAccentColor).opacity(0.55)
        static let ink = Color(NSColor.labelColor)
        static let glass = Color(NSColor.controlBackgroundColor)
        static let bezel = Color(NSColor.windowBackgroundColor)
        static let hairline = Color(NSColor.separatorColor)

        static func ink(for scheme: ColorScheme) -> Color {
            _ = scheme
            return Color(NSColor.labelColor)
        }

        static func glass(for scheme: ColorScheme) -> Color {
            _ = scheme
            return Color(NSColor.controlBackgroundColor)
        }

        static func pageBackground(for scheme: ColorScheme) -> Color {
            _ = scheme
            return Color(NSColor.windowBackgroundColor)
        }

        static func hairline(for scheme: ColorScheme) -> Color {
            _ = scheme
            return Color(NSColor.separatorColor)
        }

        static func railNSColor(enabled: Bool = true) -> NSColor {
            NSColor.controlAccentColor.withAlphaComponent(enabled ? 0.95 : 0.28)
        }
    }

    enum Radius {
        static let card: CGFloat = 12
        static let row: CGFloat = 8
        static let railMark: CGFloat = 2
    }

    enum Space {
        static let page: CGFloat = 28
        static let card: CGFloat = 16
        static let row: CGFloat = 12
        static let railWidth: CGFloat = SettingsSurfacePolicy.railWidth
        static let idealPageWidth: CGFloat = SettingsSurfacePolicy.idealWindowWidth - railWidth
    }

    enum TypeRole {
        static let railTitle = Font.headline
        static let pageTitle = Font.headline
        static let job = Font.caption
        static let body = Font.body
        static let mono = Font.system(.caption, design: .monospaced)
    }
}
