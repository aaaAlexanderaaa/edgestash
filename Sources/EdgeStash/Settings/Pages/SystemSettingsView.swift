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
        }
        .onChange(of: preferences.openAtLogin) { newValue in
            preferences.updateLaunchAtLogin(newValue)
        }
        .onReceive(timer) { _ in
            axEnabled = AXIsProcessTrusted()
        }
    }
}
