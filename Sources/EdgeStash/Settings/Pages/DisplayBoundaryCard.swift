import AppKit
import EdgeStashLogic
import SwiftUI

struct DisplayBoundarySettingsView: View {
    @ObservedObject var preferences: Preferences

    private var displays: [ConnectedDisplay] {
        _ = preferences.displayTopologyRevision
        return DisplayCatalog.connectedDisplays()
    }

    private var hasEnabledSharedBoundary: Bool {
        let geometries = DisplayCatalog.geometries()
        return displays.contains { display in
            let geometry = geometries.first { $0.id == display.id }
                ?? DisplayGeometry(id: display.id, frame: display.frame)
            let selection = preferences.displayEdgeSelection(for: display)
            return DisplayEdge.allCases.contains { edge in
                selection.isEnabled(edge) &&
                    DisplayEdgePolicy.collapseStrategy(
                        at: edge,
                        of: geometry,
                        in: geometries,
                        screensHaveSeparateSpaces: NSScreen.screensHaveSeparateSpaces
                    ) == .systemMinimize
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.displayIntro)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if displays.isEmpty {
                Text(L10n.displayNone)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
            } else {
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    DisplayBoundaryRow(
                        preferences: preferences,
                        display: display,
                        displayName: resolvedName(for: display, at: index)
                    )
                }

                if hasEnabledSharedBoundary {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "dock.rectangle")
                            .foregroundStyle(SettingsTheme.ColorToken.rail)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.displaySharedNote)
                                .font(.system(size: 12, weight: .semibold))
                            Text(L10n.displaySharedHowTo)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(L10n.displayOpenDockPane) {
                                openDesktopAndDockSettings()
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SettingsTheme.ColorToken.rail.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func openDesktopAndDockSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.dock") else { return }
        NSWorkspace.shared.open(url)
    }

    private func resolvedName(for display: ConnectedDisplay, at index: Int) -> String {
        let duplicateCount = displays.filter { $0.name == display.name }.count
        return duplicateCount > 1 ? "\(display.name) \(index + 1)" : display.name
    }
}

struct DisplayBoundaryRow: View {
    @ObservedObject var preferences: Preferences
    let display: ConnectedDisplay
    let displayName: String

    private var geometries: [DisplayGeometry] {
        DisplayCatalog.geometries()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .foregroundStyle(SettingsTheme.ColorToken.rail)
                Text(displayName)
                    .font(.system(size: 13, weight: .semibold))
                if display.isMain {
                    Text(L10n.displayPrimary)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
                Text("\(Int(display.frame.width)) × \(Int(display.frame.height))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                if preferences.displayEdgePreferences[display.id] != nil {
                    Button(L10n.displaySafeDefaults) {
                        preferences.resetDisplayEdgeSelection(displayID: display.id)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            }

            HStack(spacing: 24) {
                edgeToggle(.left, title: L10n.displayLeftEdge)
                edgeToggle(.right, title: L10n.displayRightEdge)
            }
            .padding(.leading, 28)
        }
        .padding(14)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func edgeToggle(_ edge: DisplayEdge, title: String) -> some View {
        let adjacency = DisplayEdgePolicy.adjacency(
            at: edge,
            of: DisplayGeometry(id: display.id, frame: display.frame),
            in: geometries
        )
        let isShared = adjacency != .outer
        let detail = edgeDetail(for: adjacency)

        HStack(spacing: 8) {
            Toggle("", isOn: binding(for: edge))
                .labelsHidden()
                .toggleStyle(.switch)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(isShared ? SettingsTheme.ColorToken.rail : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func edgeDetail(for adjacency: DisplayEdgeAdjacency) -> String {
        switch adjacency {
        case .outer:
            return L10n.displayOuterEdge
        case .partiallyShared:
            return NSScreen.screensHaveSeparateSpaces
                ? L10n.displayPartialSharedClipped
                : L10n.displayPartialShared
        case .fullyShared:
            return NSScreen.screensHaveSeparateSpaces
                ? L10n.displayFullySharedClipped
                : L10n.displayFullyShared
        }
    }

    private func binding(for edge: DisplayEdge) -> Binding<Bool> {
        Binding(
            get: {
                preferences.displayEdgeSelection(for: display).isEnabled(edge)
            },
            set: { enabled in
                preferences.setDisplayEdgeEnabled(enabled, edge: edge, display: display)
            }
        )
    }
}
