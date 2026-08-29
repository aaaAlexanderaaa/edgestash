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
        static let ink = Color(red: 34.0 / 255.0, green: 37.0 / 255.0, blue: 44.0 / 255.0)
        static let glass = Color(red: 240.0 / 255.0, green: 242.0 / 255.0, blue: 246.0 / 255.0)
        static let bezel = Color(red: 28.0 / 255.0, green: 30.0 / 255.0, blue: 35.0 / 255.0)
        static let hairline = Color(red: 205.0 / 255.0, green: 210.0 / 255.0, blue: 218.0 / 255.0)

        static func ink(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(red: 238.0 / 255.0, green: 240.0 / 255.0, blue: 244.0 / 255.0) : ink
        }

        static func glass(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(red: 32.0 / 255.0, green: 34.0 / 255.0, blue: 39.0 / 255.0) : glass
        }

        static func pageBackground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(NSColor.windowBackgroundColor) : glass
        }

        static func hairline(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.12) : hairline
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
        static let railTitle = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let pageTitle = Font.system(size: 15, weight: .semibold)
        static let job = Font.system(size: 12)
        static let body = Font.system(size: 13)
        static let mono = Font.system(size: 11, design: .monospaced)
    }
}
