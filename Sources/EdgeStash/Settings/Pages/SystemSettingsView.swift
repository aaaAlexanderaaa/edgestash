import ApplicationServices
import SwiftUI

struct SystemSettingsView: View {
    @ObservedObject var preferences: Preferences
    @State private var axEnabled = AXIsProcessTrusted()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPageScaffold(tab: .system) {
            SettingsCard(L10n.systemCardGeneral) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(L10n.systemLaunchAtLogin, isOn: $preferences.openAtLogin)
                        .toggleStyle(.switch)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(L10n.systemMenuBarIcon, isOn: $preferences.menuBarItemVisible)
                            .toggleStyle(.switch)
                        if !preferences.menuBarItemVisible {
                            Text(L10n.systemMenuBarIconNote)
                                .font(SettingsTheme.TypeRole.job)
                                .foregroundStyle(SettingsTheme.ColorToken.rail)
                        }
                    }

                    HStack {
                        Text(L10n.systemLanguage)
                        Spacer()
                        InterfaceLanguagePicker(selection: $preferences.language)
                    }
                }
            }

            SettingsCard(L10n.systemCardAccess) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.systemAx)
                        Spacer()
                        if axEnabled {
                            Text(L10n.systemGranted)
                                .foregroundStyle(.green)
                        } else {
                            Button(L10n.systemGrant) {
                                _ = AccessibilityGrant.isTrusted(prompt: true)
                                AccessibilityGrant.openSystemSettings()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    Text(L10n.systemAccessNote)
                        .font(SettingsTheme.TypeRole.job)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(L10n.systemCardExtras) {
                VStack(alignment: .leading, spacing: 16) {
                    enhancementRow(
                        title: L10n.systemEffects,
                        subtitle: L10n.systemEffectsNote,
                        symbol: "sparkles",
                        isOn: $preferences.decoratesSlides
                    )

                    enhancementRow(
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
        .onChange(of: preferences.openAtLogin) { newValue in
            preferences.updateLaunchAtLogin(newValue)
        }
        .onReceive(timer) { _ in
            axEnabled = AXIsProcessTrusted()
        }
    }

    private func enhancementRow(
        title: String,
        subtitle: String,
        symbol: String,
        isOn: Binding<Bool>,
        help: String? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SettingsTheme.ColorToken.rail)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if let help {
                        NoteBadge(note: help)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
