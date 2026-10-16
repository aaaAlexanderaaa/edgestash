import EdgeStashLogic
import SwiftUI

struct AppsPage: View {
    @ObservedObject var appCatalog: AppCatalog
    @ObservedObject var preferences: Preferences
    @Environment(\.settingsPageWidth) private var pageWidth
    @State private var searchText = ""
    @State private var selectedBundleID: String?
    @State private var showsDefaults = false

    private var visibleApps: [AppEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appCatalog.apps }
        return appCatalog.apps.filter {
            $0.name.localizedStandardContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedApp: AppEntry? {
        visibleApps.first { $0.id == selectedBundleID } ?? visibleApps.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(tab: .apps)
            DisclosureGroup(isExpanded: $showsDefaults) {
                StripDefaultsCard(appCatalog: appCatalog, preferences: preferences)
                    .padding(.top, 8)
            } label: {
                Text(L10n.appsDefaultsCard).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, SettingsTheme.Space.page)
            .padding(.bottom, 16)

            HStack(alignment: .top, spacing: 16) {
                applicationList
                    .frame(width: pageWidth < 620 ? 150 : 178)
                ScrollView {
                    if let app = selectedApp {
                        StashAppRow(app: app, preferences: preferences)
                            .id(app.id)
                    } else {
                        SettingsEmptyState(symbol: "sidebar.left", message: L10n.text("apps.selectApp"))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, SettingsTheme.Space.page)
            .padding(.bottom, SettingsTheme.Space.page)
        }
        .onAppear {
            selectedBundleID = selectedApp?.id
        }
        .onChange(of: visibleApps.map(\.id)) { _ in
            if !visibleApps.contains(where: { $0.id == selectedBundleID }) {
                selectedBundleID = visibleApps.first?.id
            }
        }
    }

    private var applicationList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.appsSearch, text: $searchText).textFieldStyle(.plain)
            }
            .font(.subheadline)
            .padding(8)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 7))

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(visibleApps) { app in
                        HStack(spacing: 2) {
                            TickBox(isOn: Binding(
                                get: { preferences.stashActive(bundleID: app.id) },
                                set: { preferences.applyAppStash(bundleID: app.id, stashOn: $0,
                                                                  tint: preferences.tintKey(for: app.id)) }
                            ))
                            .accessibilityLabel(L10n.text("apps.enable") + " " + app.name)
                            Button { selectedBundleID = app.id } label: {
                                HStack(spacing: 7) {
                                    AppIdentityIcon(app: app).frame(width: 22, height: 22)
                                    Text(app.name).font(.subheadline).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedApp?.id == app.id ? .isSelected : [])
                        }
                        .padding(.horizontal, 5)
                        .background(selectedApp?.id == app.id ? Color.accentColor.opacity(0.12) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if visibleApps.isEmpty {
                        SettingsEmptyState(symbol: "magnifyingglass", message: appCatalog.apps.isEmpty
                            ? L10n.appsEmptyHint : L10n.appsSearchEmpty)
                    }
                }
            }
            Text(L10n.appsListNote)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct StripDefaultsCard: View {
    @ObservedObject var appCatalog: AppCatalog
    @ObservedObject var preferences: Preferences

    var body: some View {
        let enabledApps = appCatalog.apps.filter { preferences.stashActive(bundleID: $0.id) }
        let edgeState = uniformEdgeChoice(among: enabledApps)
        let sharedEdgeChoice = edgeState.choice
        let dockSide = preferences.resolvedDockSide()
        let probedDockSide = Preferences.detectedDockSide()

        SettingsCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(L10n.appsUniformEdges)
                                .font(.headline)
                            NoteBadge(note: L10n.appsUniformEdgesNote)
                        }
                        Text(L10n.appsUniformEdgesApply)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    FieldMenu(
                        title: edgeState.isMixed ? L10n.text("apps.edgesMixed") : snapSideLabel(sharedEdgeChoice),
                        minWidth: defaultsFieldWidth,
                        leadingImage: edgeGlyphImage(side: sharedEdgeChoice, colorScheme: colorScheme),
                        alignment: .trailing,
                        choices: snapSideChoices.map { key in
                            let usable = edgeIsFree(key, dockSide: dockSide)
                            return MenuChoice(
                                title: snapSideLabel(key),
                                image: edgeGlyphImage(side: key, colorScheme: colorScheme, enabled: usable),
                                isSelected: !edgeState.isMixed && key == sharedEdgeChoice,
                                isEnabled: usable
                            ) {
                                preferences.applyGlobalSnapSide(key)
                            }
                        }
                    )
                }

                if !edgeState.isMixed,
                   let note = dockConflictNote(for: sharedEdgeChoice, dockSide: dockSide) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(SettingsTheme.ColorToken.rail)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.appsAvoidDock)
                            .font(.headline)
                        Text(L10n.appsAvoidDockNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    FieldMenu(
                        title: dockModeTitle(
                            preferences.dockClearance,
                            usedSide: preferences.dockClearance == .automatic ? probedDockSide : nil
                        ),
                        minWidth: defaultsFieldWidth,
                        alignment: .trailing,
                        choices: DockClearanceMode.allCases.map { mode in
                            MenuChoice(
                                title: dockModeOptionRow(mode, probedSide: probedDockSide),
                                isSelected: preferences.dockClearance == mode
                            ) {
                                preferences.setDockClearance(mode)
                            }
                        }
                    )
                }
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private struct UniformEdgeState {
        let choice: String
        let isMixed: Bool
    }

    private func uniformEdgeChoice(among apps: [AppEntry]) -> UniformEdgeState {
        let choices = Set(apps.map { preferences.snapPreference(for: $0.id) })
        if choices.count == 1, let only = choices.first {
            return UniformEdgeState(choice: only, isMixed: false)
        }
        return UniformEdgeState(choice: "both", isMixed: choices.count > 1)
    }
}
