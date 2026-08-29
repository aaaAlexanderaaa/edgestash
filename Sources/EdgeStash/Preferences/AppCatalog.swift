import AppKit
import EdgeStashLogic
import Foundation

/// Catalog of stashable applications for the Apps page. Regular GUI apps
/// only; the app itself is excluded. Enabled apps sort to the top so the
/// list mirrors what the engine is actually watching.
final class AppCatalog: ObservableObject {
    @Published var apps: [AppEntry] = []

    private var eventTokens: [NSObjectProtocol] = []

    init() {
        reloadCatalog()
        let center = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            eventTokens.append(center.addObserver(
                forName: event,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reloadCatalog()
            })
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        eventTokens.forEach(center.removeObserver)
    }

    func reloadCatalog() {
        let ownBundle = Bundle.main.bundleIdentifier
        var claimed = Set<String>()
        var entries: [AppEntry] = []

        for candidate in NSWorkspace.shared.runningApplications {
            guard candidate.activationPolicy == .regular,
                  let bundleID = candidate.bundleIdentifier,
                  bundleID != ownBundle,
                  let title = candidate.localizedName,
                  claimed.insert(bundleID).inserted else {
                continue
            }
            entries.append(AppEntry(id: bundleID, name: title, icon: candidate.icon, isRunning: true))
        }

        for (bundleID, profile) in Preferences.shared.appProfiles where profile.stashOn {
            guard claimed.insert(bundleID).inserted else { continue }
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let name = url.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String }
                ?? url?.deletingPathExtension().lastPathComponent
                ?? bundleID
            let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            entries.append(AppEntry(id: bundleID, name: name, icon: icon, isRunning: false))
        }

        entries.sort(by: catalogOrder)
        apps = entries
    }

    /// Re-applies the enabled-first ordering to the current list, used when
    /// enablement changes without an app launch event.
    func promoteEnabledApps() {
        apps.sort(by: catalogOrder)
    }

    private func catalogOrder(_ lhs: AppEntry, _ rhs: AppEntry) -> Bool {
        let preferences = Preferences.shared
        let lhsOn = preferences.stashActive(bundleID: lhs.id)
        let rhsOn = preferences.stashActive(bundleID: rhs.id)
        if lhsOn != rhsOn {
            return lhsOn
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
