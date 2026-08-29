import SwiftUI

struct AppsPage: View {
    @ObservedObject var appCatalog: AppCatalog
    @ObservedObject var preferences: Preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAdaptiveTintNotice = false
    @State private var noticeDismissJob: DispatchWorkItem?

    var body: some View {
        SettingsPageScaffold(tab: .apps) {
            if showsAdaptiveTintNotice {
                Text(L10n.appsAutoColorNote)
                    .font(SettingsTheme.TypeRole.job)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SettingsTheme.ColorToken.rail.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.Radius.row, style: .continuous))
            }

            StripDefaultsCard(appCatalog: appCatalog, preferences: preferences)

            SettingsCard {
                if appCatalog.apps.isEmpty {
                    SettingsEmptyState(
                        symbol: "square.grid.2x2",
                        message: L10n.appsEmptyHint
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(appCatalog.apps.enumerated()), id: \.element.id) { index, app in
                            let isEnabled = preferences.stashActive(bundleID: app.id)
                            let tintToken = preferences.tintKey(for: app.id)
                            let opacity = preferences.tintAlpha(for: app.id)
                            let snapSide = preferences.snapPreference(for: app.id)

                            HStack(alignment: .top, spacing: 12) {
                                TickBox(
                                    isOn: Binding(
                                        get: { isEnabled },
                                        set: { preferences.applyAppStash(bundleID: app.id, stashOn: $0, tint: tintToken) }
                                    )
                                )
                                .padding(.top, 8)

                                StashAppRow(
                                    app: app,
                                    colorName: tintToken,
                                    opacity: opacity,
                                    snapSide: snapSide,
                                    blockedDockSide: preferences.resolvedDockSide(),
                                    onColorChange: { newColor in
                                        preferences.applyAppStash(bundleID: app.id, stashOn: isEnabled, tint: newColor)
                                        if newColor == "adaptive" {
                                            raiseAdaptiveTintNotice()
                                        }
                                    },
                                    onOpacityChange: { newOpacity in
                                        preferences.applyOpacity(bundleID: app.id, opacity: newOpacity)
                                    },
                                    onSnapSideChange: { newSnapSide in
                                        preferences.applySnapSide(bundleID: app.id, snapSide: newSnapSide)
                                    }
                                )
                                .opacity(isEnabled ? 1 : 0.72)
                            }
                            .padding(.vertical, 8)

                            if index != appCatalog.apps.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .onDisappear {
            noticeDismissJob?.cancel()
            noticeDismissJob = nil
        }
    }

    /// Picking the adaptive tint is the one choice that behaves differently
    /// per appearance, so say so once; the notice retires itself.
    private func raiseAdaptiveTintNotice() {
        noticeDismissJob?.cancel()
        let retire = DispatchWorkItem {
            withAnimation(SettingsMotion.fade(reduceMotion: reduceMotion)) {
                showsAdaptiveTintNotice = false
            }
        }
        noticeDismissJob = retire
        withAnimation(SettingsMotion.fade(reduceMotion: reduceMotion)) {
            showsAdaptiveTintNotice = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: retire)
    }
}

private struct StripDefaultsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var appCatalog: AppCatalog
    @ObservedObject var preferences: Preferences

    var body: some View {
        let enabledApps = appCatalog.apps.filter { preferences.stashActive(bundleID: $0.id) }
        let sharedAlpha = uniformAlpha(among: enabledApps)
        let edgeState = uniformEdgeChoice(among: enabledApps)
        let sharedEdgeChoice = edgeState.choice
        let dockSide = preferences.resolvedDockSide()
        let probedDockSide = Preferences.detectedDockSide()

        SettingsCard(L10n.appsDefaultsCard) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.appsUniformAlpha)
                            .font(.headline)
                        Text(L10n.appsUniformAlphaNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    FieldMenu(
                        title: opacityLabel(sharedAlpha),
                        minWidth: defaultsFieldWidth,
                        leadingImage: opacityGlyphImage(alpha: sharedAlpha, colorScheme: colorScheme),
                        alignment: .trailing,
                        choices: opacityStops.map { value in
                            MenuChoice(
                                title: opacityLabel(value),
                                image: opacityGlyphImage(alpha: value, colorScheme: colorScheme),
                                isSelected: value == sharedAlpha
                            ) {
                                preferences.applyGlobalOpacity(value)
                            }
                        }
                    )
                }

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
                        title: snapSideLabel(sharedEdgeChoice),
                        minWidth: defaultsFieldWidth,
                        leadingImage: edgeGlyphImage(side: sharedEdgeChoice, colorScheme: colorScheme),
                        alignment: .trailing,
                        choices: snapSideChoices.map { key in
                            let usable = edgeIsFree(key, dockSide: dockSide)
                            return MenuChoice(
                                title: snapSideLabel(key),
                                image: edgeGlyphImage(side: key, colorScheme: colorScheme, enabled: usable),
                                isSelected: key == sharedEdgeChoice,
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

    /// One value only when every enabled app agrees; disagreement falls back
    /// to full opacity rather than inventing a middle ground.
    private func uniformAlpha(among apps: [AppEntry]) -> Double {
        let values = Set(apps.map { preferences.tintAlpha(for: $0.id) })
        return values.count == 1 ? values.first ?? 1.0 : 1.0
    }

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
