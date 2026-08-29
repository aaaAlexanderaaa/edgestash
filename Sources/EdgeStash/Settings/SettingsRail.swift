import SwiftUI

struct SettingsRail: View {
    let tabs: [SettingsTab]
    @Binding var selectedTab: SettingsTab
    let showsEmbeddedTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsEmbeddedTitle {
                Text("EdgeStash")
                    .font(SettingsTheme.TypeRole.railTitle)
                    .padding(.leading, 22)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
            } else {
                Color.clear.frame(height: 8)
            }

            VStack(spacing: 4) {
                ForEach(tabs, id: \.self) { tab in
                    SettingsRailItem(tab: tab, selectedTab: $selectedTab)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsRailItem: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let tab: SettingsTab
    @Binding var selectedTab: SettingsTab
    @State private var isHovered = false

    private var isSelected: Bool { selectedTab == tab }

    var body: some View {
        Button {
            withAnimation(SettingsMotion.reveal(reduceMotion: reduceMotion)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 10) {
                Capsule(style: .continuous)
                    .fill(isSelected ? SettingsTheme.ColorToken.rail : Color.clear)
                    .frame(width: SettingsTheme.Radius.railMark, height: isSelected ? 22 : 10)

                Image(systemName: tab.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 22, height: 20)

                Text(tab.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? SettingsTheme.ColorToken.ink(for: colorScheme) : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: SettingsTheme.Radius.row, style: .continuous)
                    .fill(isSelected ? SettingsTheme.ColorToken.rail.opacity(0.14) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.Radius.row, style: .continuous))
        }
        .buttonStyle(SettingsRailButtonStyle())
        .onHover { isHovered = $0 }
        .accessibilityLabel(tab.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconTint: Color {
        if isSelected { return SettingsTheme.ColorToken.rail }
        if isHovered { return .primary.opacity(0.85) }
        return .secondary
    }
}

struct SettingsRailButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
