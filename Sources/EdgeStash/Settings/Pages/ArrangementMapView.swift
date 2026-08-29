import AppKit
import EdgeStashLogic
import SwiftUI

struct ArrangementMapView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject private var halo = HaloController.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.settingsPageWidth) private var pageWidth

    private var displays: [ConnectedDisplay] {
        _ = preferences.displayTopologyRevision
        return DisplayCatalog.connectedDisplays()
    }

    private var geometries: [DisplayGeometry] {
        DisplayCatalog.geometries()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.mapIntro)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if displays.isEmpty {
                Text(L10n.displayNone)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                GeometryReader { proxy in
                    let slots = DisplayArrangementPolicy.fittedSlots(
                        displays: geometries,
                        canvas: proxy.size
                    )
                    ZStack(alignment: .topLeading) {
                        ForEach(displays) { display in
                            if let slot = slots.first(where: { $0.id == display.id }) {
                                displayTile(display: display, slot: slot)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onEnded { value in
                            if let hit = StashGeometryPolicy.hitMapEdge(at: value.location, slots: slots) {
                                halo.select(displayID: hit.displayID, edge: hit.edge)
                            }
                        }
                    )
                }
                .frame(height: mapHeight)
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var mapHeight: CGFloat {
        pageWidth < 700 ? 160 : 200
    }

    private func displayTile(display: ConnectedDisplay, slot: DisplayArrangementSlot) -> some View {
        let geometry = geometries.first { $0.id == display.id }
            ?? DisplayGeometry(id: display.id, frame: display.frame)
        let selection = preferences.displayEdgeSelection(for: display)
        let selected = halo.target

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(SettingsTheme.ColorToken.glass(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(SettingsTheme.ColorToken.hairline(for: colorScheme), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name)
                    .font(SettingsTheme.TypeRole.mono)
                    .lineLimit(1)
                if display.isMain {
                    Text(L10n.displayPrimary)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)

            ForEach(DisplayEdge.allCases, id: \.rawValue) { edge in
                let kind = DisplayArrangementPolicy.previewKind(
                    at: edge,
                    of: geometry,
                    in: geometries,
                    selection: selection,
                    screensHaveSeparateSpaces: NSScreen.screensHaveSeparateSpaces
                )
                edgeMark(
                    edge: edge,
                    slot: slot,
                    display: geometry,
                    kind: kind,
                    selected: selected?.displayID == display.id && selected?.edge == edge
                )
            }
        }
        .frame(width: slot.canvasFrame.width, height: slot.canvasFrame.height)
        .position(
            x: slot.canvasFrame.midX,
            y: slot.canvasFrame.midY
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: display, geometry: geometry, selection: selection))
    }

    @ViewBuilder
    private func edgeMark(
        edge: DisplayEdge,
        slot: DisplayArrangementSlot,
        display: DisplayGeometry,
        kind: DisplayEdgePreviewKind,
        selected: Bool
    ) -> some View {
        let shared = DisplayEdgePolicy.sharedIntervals(at: edge, of: display, in: geometries)
        let segments = DisplayArrangementPolicy.canvasSegments(
            worldIntervals: shared,
            display: display,
            slot: DisplayArrangementSlot(
                id: slot.id,
                canvasFrame: CGRect(origin: .zero, size: slot.canvasFrame.size)
            ),
            edge: edge,
            thickness: 4
        )
        let full = edge == .left
            ? CGRect(x: 0, y: 0, width: 4, height: slot.canvasFrame.height)
            : CGRect(x: slot.canvasFrame.width - 4, y: 0, width: 4, height: slot.canvasFrame.height)

        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(markColor(kind).opacity(selected ? 0.95 : 0.55))
                .frame(width: full.width, height: full.height)
                .offset(x: full.minX, y: full.minY)
            ForEach(Array(segments.enumerated()), id: \.offset) { _, rect in
                Rectangle()
                    .fill(SettingsTheme.ColorToken.railMuted)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .allowsHitTesting(false)
    }

    private func markColor(_ kind: DisplayEdgePreviewKind) -> Color {
        switch kind {
        case .disabled:
            return Color.secondary.opacity(0.45)
        case .slideOffscreen:
            return SettingsTheme.ColorToken.rail
        case .systemMinimize:
            return SettingsTheme.ColorToken.railMuted
        }
    }

    private func accessibilityLabel(
        for display: ConnectedDisplay,
        geometry: DisplayGeometry,
        selection: DisplayEdgeSelection
    ) -> String {
        let left = DisplayArrangementPolicy.previewKind(
            at: .left,
            of: geometry,
            in: geometries,
            selection: selection,
            screensHaveSeparateSpaces: NSScreen.screensHaveSeparateSpaces
        )
        let right = DisplayArrangementPolicy.previewKind(
            at: .right,
            of: geometry,
            in: geometries,
            selection: selection,
            screensHaveSeparateSpaces: NSScreen.screensHaveSeparateSpaces
        )
        let main = display.isMain ? L10n.displayPrimary : display.name
        return "\(main), \(strategyLabel(left)), \(strategyLabel(right))"
    }

    private func strategyLabel(_ kind: DisplayEdgePreviewKind) -> String {
        switch kind {
        case .disabled:
            return L10n.mapStateOff
        case .slideOffscreen:
            return L10n.mapStateOuter
        case .systemMinimize:
            return L10n.mapStateSeam
        }
    }
}
