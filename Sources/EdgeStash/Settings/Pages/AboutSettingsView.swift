import AppKit
import SwiftUI

struct AboutPage: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.3"

    var body: some View {
        SettingsPageScaffold(tab: .about) {
            SettingsCard {
                HStack(alignment: .top, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("EdgeStash")
                                .font(.title2.weight(.semibold))
                            Text("v\(appVersion)")
                                .font(SettingsTheme.TypeRole.mono)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        Text(L10n.aboutTagline)
                            .font(.subheadline)
                        Text(L10n.aboutOfflineLine)
                            .font(SettingsTheme.TypeRole.job)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsCard(L10n.aboutCardPrivacy) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.aboutPrivacyBody)
                    Text(L10n.aboutPrivacyAx)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
