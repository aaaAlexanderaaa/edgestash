import SwiftUI

struct SettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var appCatalog = AppCatalog()
    @ObservedObject private var preferences = Preferences.shared
    @State private var selectedTab: SettingsTab = .apps

    private let railTabs = SettingsTab.allCases

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .apps:
            AppsPage(appCatalog: appCatalog, preferences: preferences)
        case .behavior:
            BehaviorSettingsView(appCatalog: appCatalog, preferences: preferences)
        case .system:
            SystemSettingsView(preferences: preferences)
        case .about:
            AboutPage()
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsRail(
                tabs: railTabs,
                selectedTab: $selectedTab,
                showsEmbeddedTitle: true
            )
            .frame(width: SettingsTheme.Space.railWidth)

            Divider()

            pageHost
        }
        .frame(minHeight: 580, idealHeight: 640)
        .id(preferences.language)
        .onAppear {
            HaloController.shared.settingsVisibilityChanged(isVisible: true)
            HaloController.shared.settingsTabChanged(selectedTab)
        }
        .onChange(of: selectedTab) { tab in
            HaloController.shared.settingsTabChanged(tab)
        }
        .onDisappear {
            appCatalog.promoteEnabledApps()
            HaloController.shared.settingsVisibilityChanged(isVisible: false)
        }
    }

    private var pageHost: some View {
        GeometryReader { geo in
            detailContent
                .id(selectedTab)
                .transition(SettingsMotion.pageTransition(reduceMotion: reduceMotion, fromRail: true))
                .animation(SettingsMotion.reveal(reduceMotion: reduceMotion), value: selectedTab)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .environment(\.settingsPageWidth, geo.size.width)
        }
        .background(SettingsTheme.ColorToken.pageBackground(for: colorScheme).ignoresSafeArea())
    }
}
