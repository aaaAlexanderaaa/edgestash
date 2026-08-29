import AppKit
import EdgeStashLogic
import SwiftUI

/// EdgeStash's single alert presenter: the app is transient, so every alert
/// floats above the frontmost app and activates EdgeStash first.
enum EdgeAlert {
    @discardableResult
    static func run(
        style: NSAlert.Style,
        title: String,
        detail: String,
        buttons: [String]
    ) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = detail
        for title in buttons {
            alert.addButton(withTitle: title)
        }
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var engine: StashEngine?
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installTextEditingChords()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMenuBarVisibilityChange),
            name: PreferenceSignal.menuBarVisibilityDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChange),
            name: PreferenceSignal.languageDidChange,
            object: nil
        )
        updateStatusBarVisibility()
        StashRescue.recoverPending(reason: RescueTrigger.appLaunch)
        if AccessibilityGrant.isTrusted(prompt: false) {
            startEngineIfTrusted()
        } else {
            showSettings()
            if Preferences.shared.hasPendingRescueDossiers() {
                notifyPendingRescueNeedsAccessibility()
            }
        }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.reconcileEngineTrust()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HaloController.shared.clear()
        engine?.shutdown()
        engine = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: SettingsSurfacePolicy.idealWindowWidth,
                    height: 640
                ),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "EdgeStash"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: SettingsSurfacePolicy.minimumWindowWidth, height: 580)
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView())
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        HaloController.shared.settingsVisibilityChanged(isVisible: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        HaloController.shared.settingsVisibilityChanged(isVisible: false)
        HaloController.shared.clear()
    }

    private func startEngineIfTrusted() {
        guard AccessibilityGrant.isTrusted(prompt: false) else { return }
        if engine == nil {
            engine = StashEngine()
        }
        engine?.start()
    }

    private func reconcileEngineTrust() {
        if AccessibilityGrant.isTrusted(prompt: false) {
            if engine?.isRunning != true {
                StashRescue.recoverPending(reason: RescueTrigger.trustRegained)
            }
            startEngineIfTrusted()
        } else {
            engine?.suspendTrustLost()
        }
    }

    private func notifyPendingRescueNeedsAccessibility() {
        let choice = EdgeAlert.run(
            style: .warning,
            title: L10n.alertRescueTitle,
            detail: L10n.alertRescueBody,
            buttons: [L10n.alertRescueOpenSettings, L10n.alertRescueLater]
        )
        if choice == .alertFirstButtonReturn {
            AccessibilityGrant.openSystemSettings()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func handleMenuBarVisibilityChange() {
        updateStatusBarVisibility()
    }

    @objc private func handleLanguageChange() {
        if statusItem != nil {
            statusItem?.menu = makeStatusMenu()
        }
    }

    private func updateStatusBarVisibility() {
        if Preferences.shared.menuBarItemVisible {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = item.button {
                    if #available(macOS 11.0, *) {
                        button.image = NSImage(
                            systemSymbolName: "rectangle.lefthalf.inset.filled.arrow.left",
                            accessibilityDescription: "EdgeStash"
                        )
                    } else {
                        button.title = "EdgeStash"
                    }
                }
                item.menu = makeStatusMenu()
                statusItem = item
            }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.menuSettings, action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L10n.menuQuit, action: #selector(quitApp), keyEquivalent: "q"))
        return menu
    }

    /// EdgeStash runs as an accessory app, so AppKit installs no main menu
    /// and the standard text chords (⌘Z, ⌘C, ⌘V …) never reach the text
    /// fields in Settings. This routing menu exists only to reconnect those
    /// chords to the system text actions. An accessory app never renders its
    /// main menu, so the entries carry no titles.
    private func installTextEditingChords() {
        let chords: [(textAction: Selector, key: String)] = [
            (textAction: #selector(UndoManager.undo), key: "z"),
            (textAction: #selector(UndoManager.redo), key: "Z"),
            (textAction: #selector(NSText.cut(_:)), key: "x"),
            (textAction: #selector(NSText.copy(_:)), key: "c"),
            (textAction: #selector(NSText.paste(_:)), key: "v"),
            (textAction: #selector(NSText.selectAll(_:)), key: "a")
        ]
        let routing = NSMenu()
        for chord in chords {
            let item = NSMenuItem(title: "", action: chord.textAction, keyEquivalent: chord.key)
            item.keyEquivalentModifierMask = .command
            routing.addItem(item)
        }
        let carrier = NSMenuItem()
        carrier.submenu = routing
        let main = NSMenu()
        main.addItem(NSMenuItem())  // reserves the app-menu slot
        main.addItem(carrier)
        NSApp.mainMenu = main
    }
}
