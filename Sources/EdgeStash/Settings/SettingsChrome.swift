import EdgeStashLogic
import SwiftUI

private struct SettingsPageWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = SettingsSurfacePolicy.idealWindowWidth - SettingsSurfacePolicy.railWidth
}

extension EnvironmentValues {
    var settingsPageWidth: CGFloat {
        get { self[SettingsPageWidthKey.self] }
        set { self[SettingsPageWidthKey.self] = newValue }
    }
}

struct SettingsPageHeader: View {
    let tab: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tab.displayName)
                .font(SettingsTheme.TypeRole.pageTitle)
            Text(tab.jobLine)
                .font(SettingsTheme.TypeRole.job)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsTheme.Space.page)
        .padding(.top, SettingsTheme.Space.page)
        .padding(.bottom, 12)
    }
}

struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.Space.row) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding(SettingsTheme.Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SettingsTheme.ColorToken.glass(for: colorScheme))
        )
    }
}

struct SettingsPageScaffold<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(tab: tab)
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsTheme.Space.card) {
                    content
                }
                .padding(.horizontal, SettingsTheme.Space.page)
                .padding(.bottom, SettingsTheme.Space.page)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsEmptyState: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

struct NoteBadge: View {
    let note: String
    @State private var showsNote = false

    var body: some View {
        Button {
            showsNote.toggle()
        } label: {
            Image(systemName: showsNote ? "info.circle.fill" : "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsNote, arrowEdge: .top) {
            Text(note)
                .font(.caption)
                .frame(width: SettingsSurfacePolicy.notePopoverWidth, alignment: .leading)
                .padding(12)
        }
    }
}

struct InterfaceLanguagePicker: View {
    @Binding var selection: Int

    var body: some View {
        Picker("", selection: $selection) {
            Text(L10n.systemLangSystem).tag(0)
            Text(L10n.systemLangZh).tag(1)
            Text(L10n.systemLangEn).tag(2)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 168, alignment: .trailing)
    }
}

struct SettingsFlagRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    @Binding var isOn: Bool
    var help: String? = nil

    var body: some View {
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
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

func languageDisplay(_ value: Int) -> String {
    switch value {
    case 1:
        return L10n.systemLangZh
    case 2:
        return L10n.systemLangEn
    default:
        return L10n.systemLangSystem
    }
}
