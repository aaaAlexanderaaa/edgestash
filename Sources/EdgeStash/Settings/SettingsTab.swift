import SwiftUI

enum SettingsTab: String, CaseIterable {
    case apps
    case behavior
    case system
    case about

    var iconName: String {
        switch self {
        case .apps: return "square.grid.2x2"
        case .behavior: return "hand.draw"
        case .system: return "slider.horizontal.3"
        case .about: return "book.closed"
        }
    }

    var displayName: String {
        switch self {
        case .apps: return L10n.tabApps
        case .behavior: return L10n.tabBehavior
        case .system: return L10n.tabSystem
        case .about: return L10n.tabAbout
        }
    }

    var jobLine: String {
        switch self {
        case .apps: return L10n.tabAppsSummary
        case .behavior: return L10n.tabBehaviorSummary
        case .system: return L10n.tabSystemSummary
        case .about: return L10n.tabAboutSummary
        }
    }
}
