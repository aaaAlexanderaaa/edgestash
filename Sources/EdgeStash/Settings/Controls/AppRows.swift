import AppKit
import EdgeStashLogic
import SwiftUI

struct AppIdentityIcon: View {
    let app: AppEntry
    var body: some View {
        Group {
            if let icon = app.icon { Image(nsImage: icon).resizable() }
            else { Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary) }
        }
        .accessibilityHidden(true)
    }
}

/// Stable detail editor; switching enablement never reorders the app list.
struct StashAppRow: View {
    let app: AppEntry
    @ObservedObject var preferences: Preferences
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsBehavior = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                AppIdentityIcon(app: app).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Text(app.id).font(SettingsTheme.TypeRole.mono).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Toggle(L10n.text("apps.enable"), isOn: Binding(
                    get: { preferences.stashActive(bundleID: app.id) },
                    set: { preferences.applyAppStash(bundleID: app.id, stashOn: $0,
                                                      tint: preferences.tintKey(for: app.id)) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            StashAppearanceEditor(app: app, preferences: preferences)
            SettingsCard {
                DisclosureGroup(isExpanded: $showsBehavior) {
                    behaviorFields.padding(.top, 12)
                } label: {
                    Text(L10n.text("apps.behaviorDetails")).font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(.bottom, 2)
    }

    private var behaviorFields: some View {
        let side = preferences.snapPreference(for: app.id)
        let dockSide = preferences.resolvedDockSide()
        let action = preferences.allStashedDockAction(for: app.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("apps.stashEdges")).font(.subheadline)
                Spacer(minLength: 8)
                FieldMenu(title: snapSideLabel(side), minWidth: snapFieldWidth,
                          leadingImage: edgeGlyphImage(side: side, colorScheme: colorScheme),
                          alignment: .trailing,
                          choices: snapSideChoices.map { key in
                    MenuChoice(title: snapSideLabel(key),
                               image: edgeGlyphImage(side: key, colorScheme: colorScheme,
                                                     enabled: edgeIsFree(key, dockSide: dockSide)),
                               isSelected: key == side, isEnabled: edgeIsFree(key, dockSide: dockSide)) {
                        preferences.applySnapSide(bundleID: app.id, snapSide: key)
                    }
                })
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.appsAllStashedDock).font(.subheadline)
                FieldMenu(title: allStashedDockLabel(action), minWidth: allStashedDockFieldWidth,
                          choices: AllStashedDockAction.allCases.map { choice in
                    MenuChoice(title: allStashedDockLabel(choice), isSelected: choice == action) {
                        preferences.setAllStashedDockAction(choice, bundleID: app.id)
                    }
                })
            }
            if let note = dockConflictNote(for: side, dockSide: dockSide) {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
