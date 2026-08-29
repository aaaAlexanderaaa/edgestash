import AppKit
import Combine
import EdgeStashLogic
import SwiftUI

struct HaloPreviewTarget: Equatable {
    let displayID: String
    let edge: DisplayEdge
}

final class HaloController: ObservableObject {
    static let shared = HaloController()

    private var window: EdgeHaloWindow?
    @Published private(set) var target: HaloPreviewTarget?
    private var settingsTabIsBehavior = false
    private var settingsWindowVisible = false

    private init() {}

    func settingsVisibilityChanged(isVisible: Bool) {
        settingsWindowVisible = isVisible
        reconcile()
    }

    func settingsTabChanged(_ tab: SettingsTab) {
        settingsTabIsBehavior = tab == .behavior
        reconcile()
    }

    func select(displayID: String, edge: DisplayEdge) {
        settingsTabIsBehavior = true
        target = HaloPreviewTarget(displayID: displayID, edge: edge)
        reconcile()
    }

    func clear() {
        target = nil
        hideWindow()
    }

    private func reconcile() {
        if HaloPreviewPolicy.shouldForgetTarget(
            settingsTabIsBehavior: settingsTabIsBehavior,
            settingsWindowVisible: settingsWindowVisible
        ) {
            target = nil
            hideWindow()
            return
        }
        guard let target else {
            hideWindow()
            return
        }
        guard let screen = DisplayCatalog.screen(withID: target.displayID) else {
            hideWindow()
            return
        }
        let geometries = DisplayCatalog.adjacencyGeometries()
        guard let geometry = geometries.first(where: { $0.id == target.displayID }) else {
            hideWindow()
            return
        }
        let display = DisplayCatalog.connectedDisplays().first(where: { $0.id == target.displayID })
            ?? ConnectedDisplay(id: target.displayID, name: screen.localizedName, frame: screen.frame, isMain: false)
        let selection = Preferences.shared.displayEdgeSelection(for: display)
        let kind = DisplayArrangementPolicy.previewKind(
            at: target.edge,
            of: geometry,
            in: geometries,
            selection: selection,
            screensHaveSeparateSpaces: NSScreen.screensHaveSeparateSpaces
        )
        let frame = StashGeometryPolicy.haloBand(edge: target.edge, displayAppKit: screen.frame)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if window == nil {
            window = EdgeHaloWindow()
        }
        window?.show(kind: kind, frame: frame, reduceMotion: reduceMotion)
    }

    private func hideWindow() {
        window?.hide(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}
