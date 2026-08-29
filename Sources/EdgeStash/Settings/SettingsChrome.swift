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
            RoundedRectangle(cornerRadius: SettingsTheme.Radius.card, style: .continuous)
                .fill(SettingsTheme.ColorToken.glass(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsTheme.Radius.card, style: .continuous)
                .stroke(SettingsTheme.ColorToken.hairline(for: colorScheme), lineWidth: 1)
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
                .font(.system(size: 22))
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

/// A circled info glyph that reveals a design note in a popover. The glyph
/// fills while the note is open and gains a hover halo; the popover carries a
/// rail-tinted spine on its leading edge. Every note popover in Settings
/// measures `SettingsSurfacePolicy.notePopoverWidth`, so notes read at a
/// consistent line length wherever they appear.
struct NoteBadge: View {
    let note: String
    @State private var showsNote = false
    @State private var hovered = false

    var body: some View {
        Button {
            showsNote.toggle()
        } label: {
            Image(systemName: showsNote ? "info.circle.fill" : "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    hovered || showsNote ? SettingsTheme.ColorToken.rail : Color.secondary
                )
                .padding(3)
                .background(
                    Circle()
                        .fill(SettingsTheme.ColorToken.rail.opacity(hovered ? 0.12 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .popover(isPresented: $showsNote, arrowEdge: .top) {
            Text(note)
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(width: SettingsSurfacePolicy.notePopoverWidth, alignment: .leading)
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.vertical, 10)
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(SettingsTheme.ColorToken.rail.opacity(0.55))
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
        }
    }
}

/// Pull-down for the interface language. Language names always render in
/// their own tongue; only the system-following row localizes.
struct InterfaceLanguagePicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: Int
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(languageDisplay(selection))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(width: 168, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsTheme.ColorToken.glass(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(SettingsTheme.ColorToken.hairline(for: colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(width: 168, alignment: .trailing)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                row(L10n.systemLangSystem, tag: 0)
                row(L10n.systemLangZh, tag: 1)
                row(L10n.systemLangEn, tag: 2)
            }
            .padding(9)
            .frame(width: 176)
        }
    }

    @ViewBuilder
    private func row(_ title: String, tag: Int) -> some View {
        Button {
            selection = tag
            isOpen = false
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if selection == tag {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ColorToken.rail)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selection == tag ? SettingsTheme.ColorToken.rail.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
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
