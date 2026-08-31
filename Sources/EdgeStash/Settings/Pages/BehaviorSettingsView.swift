import EdgeStashLogic
import SwiftUI

struct BehaviorSettingsView: View {
    @ObservedObject var appCatalog: AppCatalog
    @ObservedObject var preferences: Preferences

    var body: some View {
        SettingsPageScaffold(tab: .behavior) {
            HoverCard(preferences: preferences)
            AppearanceCard(preferences: preferences)
            ShortcutsCard(appCatalog: appCatalog, preferences: preferences)
            SettingsCard(L10n.mapCard) {
                ArrangementMapView(preferences: preferences)
            }
            SettingsCard(L10n.displayCard) {
                DisplayBoundarySettingsView(preferences: preferences)
            }
        }
    }
}

private struct HoverCard: View {
    @Environment(\.settingsPageWidth) private var pageWidth
    @ObservedObject var preferences: Preferences

    var body: some View {
        SettingsCard(L10n.behaviorCardGuard) {
            let stackPreview = SettingsSurfacePolicy.stackHoverPreview(pageWidth: pageWidth)
            VStack(alignment: .leading, spacing: 20) {
                DelayTuningRow(
                    title: L10n.behaviorRevealDelay,
                    value: $preferences.revealDelayMS,
                    description: L10n.behaviorRevealDelayNote
                )

                if stackPreview {
                    VStack(alignment: .leading, spacing: 20) {
                        toleranceSliders
                        visualizer
                    }
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        toleranceSliders
                            .frame(minWidth: 260)
                        visualizer
                    }
                }
            }
        }
    }

    private var toleranceSliders: some View {
        VStack(alignment: .leading, spacing: 20) {
            GateTuningRow(
                title: L10n.behaviorBufferX,
                value: $preferences.gateSpanX,
                description: L10n.behaviorBufferXNote,
                range: 0...Preferences.maxGateSpanX,
                step: 20,
                resetValue: Preferences.defaultGateSpanX
            )
            GateTuningRow(
                title: L10n.behaviorBufferY,
                value: $preferences.gateSpanY,
                description: L10n.behaviorBufferYNote,
                range: 0...Preferences.maxGateSpanY,
                step: 20,
                resetValue: Preferences.defaultGateSpanY
            )
        }
    }

    private var visualizer: some View {
        BufferPreview(xTol: preferences.gateSpanX, yTol: preferences.gateSpanY)
            .frame(minWidth: 220, minHeight: 220)
    }
}

private struct AppearanceCard: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 16) {
                SettingsFlagRow(
                    title: L10n.systemEffects,
                    subtitle: L10n.systemEffectsNote,
                    symbol: "sparkles",
                    isOn: $preferences.decoratesSlides
                )
                SettingsFlagRow(
                    title: L10n.systemMergedStrip,
                    subtitle: L10n.systemMergedStripNote,
                    symbol: "rectangle.split.3x1.fill",
                    isOn: $preferences.mergesStrips,
                    help: [
                        L10n.stripNoteTint,
                        L10n.stripNoteFlourish,
                        L10n.stripNoteSpeed
                    ].map { "· \($0)" }.joined(separator: "\n")
                )
            }
        }
    }
}

private struct ShortcutsCard: View {
    @ObservedObject var appCatalog: AppCatalog
    @ObservedObject var preferences: Preferences

    private var enabledApps: [AppEntry] {
        appCatalog.apps.filter { preferences.stashActive(bundleID: $0.id) }
    }

    var body: some View {
        SettingsCard(L10n.behaviorCardShortcuts) {
            VStack(alignment: .leading, spacing: 8) {
                TransientChordRow(preferences: preferences, appInfos: appCatalog.apps)

                if enabledApps.isEmpty {
                    SettingsEmptyState(
                        symbol: "keyboard.badge.ellipsis",
                        message: L10n.behaviorShortcutsEmpty
                    )
                } else {
                    ForEach(enabledApps) { app in
                        AppChordRow(
                            app: app,
                            preferences: preferences,
                            appInfos: appCatalog.apps
                        )
                    }
                }
            }
        }
    }
}
