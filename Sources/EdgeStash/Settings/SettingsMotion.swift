import SwiftUI

enum SettingsMotion {
    static func reveal(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.28, dampingFraction: 0.86)
    }

    static func fade(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.12 : 0.25)
    }

    static func pageTransition(reduceMotion: Bool, fromRail: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: fromRail ? .leading : .trailing).combined(with: .opacity),
            removal: .opacity
        )
    }
}
