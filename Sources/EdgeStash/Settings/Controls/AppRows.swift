import AppKit
import EdgeStashLogic
import SwiftUI

/// One managed application inside the Apps page: identity on the first line,
/// glass-tint chips and snap-side on the second, and an inline note when
/// the Dock currently blocks part of the chosen coverage.
struct StashAppRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let app: AppEntry
    let colorName: String
    let snapSide: String
    let blockedDockSide: String?
    let allStashedDock: AllStashedDockAction?
    let onColorChange: (String) -> Void
    let onSnapSideChange: (String) -> Void
    let onAllStashedDockChange: (AllStashedDockAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                appBadge

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(SettingsTheme.TypeRole.body)
                        .lineLimit(1)
                    Text(app.id)
                        .font(SettingsTheme.TypeRole.mono)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                FieldMenu(
                    title: snapSideLabel(snapSide),
                    minWidth: snapFieldWidth,
                    leadingImage: edgeGlyphImage(side: snapSide, colorScheme: colorScheme),
                    alignment: .trailing,
                    choices: snapSideChoices.map { key in
                        let usable = edgeIsFree(key, dockSide: blockedDockSide)
                        return MenuChoice(
                            title: snapSideLabel(key),
                            image: edgeGlyphImage(side: key, colorScheme: colorScheme, enabled: usable),
                            isSelected: key == snapSide,
                            isEnabled: usable
                        ) {
                            onSnapSideChange(key)
                        }
                    }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                GlassTintPicker(colorName: colorName, onColorChange: onColorChange)

                if let allStashedDock {
                    HStack(alignment: .center, spacing: 12) {
                        Text(L10n.appsAllStashedDock)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        FieldMenu(
                            title: allStashedDockLabel(allStashedDock),
                            minWidth: allStashedDockFieldWidth,
                            alignment: .trailing,
                            choices: AllStashedDockAction.allCases.map { action in
                                MenuChoice(
                                    title: allStashedDockLabel(action),
                                    isSelected: action == allStashedDock
                                ) {
                                    onAllStashedDockChange(action)
                                }
                            }
                        )
                    }
                }

                if let note = dockConflictNote(for: snapSide, dockSide: blockedDockSide) {
                    Label {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(SettingsTheme.ColorToken.rail)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(SettingsTheme.ColorToken.rail)
                    }
                }
            }
            .padding(.leading, 41)
        }
    }

    private var appBadge: some View {
        Group {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 30, height: 30)
    }
}
