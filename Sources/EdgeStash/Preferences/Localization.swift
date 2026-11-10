import Foundation

/// EdgeStash's copy catalog.
///
/// Copy is addressed by stable dotted identifiers rather than by product
/// strings, so English wording can be revised without touching call sites.
/// The app always uses this catalog, including when a legacy language setting
/// or the system locale selected another language.
enum L10n {
    private static let en: [String: String] = [
        "apps.edgesMixed": "Set individually",
        "apps.behaviorDetails": "Stash edges & app switching",
        "apps.selectApp": "Select an app to adjust its behavior and appearance.",
        "apps.enable": "Enable edge stash",
        "apps.stashEdges": "Stash edges",
        "appearance.title": "Appearance & motion",
        "appearance.material": "Signal style",
        "appearance.tint": "Accent color",
        "appearance.motion": "Window motion",
        "appearance.seamNote": "Window motion applies to exposed edges. Shared edges use system minimization.",
        "appearance.preview": "Preview",
        "appearance.desktop": "Switch preview desktop brightness",
        "appearance.scene": "Preview scene",
        "appearance.outer": "Exposed edge",
        "appearance.seam": "Shared edge",
        "appearance.reduced": "System Reduce Motion is on.",
        "appearance.previewNote": "A local preview of this app’s style.",
        "appearance.replay": "Replay",
        "material.glass": "Glass",
        "material.glass.detail": "A translucent plate with a fine reflection, letting the desktop show through.",
        "material.enamel": "Enamel",
        "material.enamel.detail": "A rich, quiet color with a fine bright rim.",
        "material.glow": "Glow",
        "material.glow.detail": "A soft luminous center that falls off gently at its edges.",
        "material.prism": "Prism",
        "material.prism.detail": "Your accent color with a restrained two-tone reflection.",
        "motion.slide": "Slide",
        "motion.slide.detail": "Travel the full path into or out of the edge.",
        "motion.nudge": "Nudge",
        "motion.nudge.detail": "A short movement with a fade for a lighter transition.",
        "motion.fade": "Fade",
        "motion.fade.detail": "Fade in or out while staying in place.",

        // Tabs
        "tab.apps": "Apps",
        "tab.behavior": "Behavior",
        "tab.system": "System",
        "tab.about": "About",
        "tab.apps.summary": "Choose apps, then tune their stash behavior, signal style, and motion.",
        "tab.behavior.summary": "When windows stash and expand, and which screen edges are allowed.",
        "tab.system.summary": "Launch at login and Accessibility.",
        "tab.about.summary": "What EdgeStash does.",

        // Apps page
        "apps.autoColorNote": "\"Follow system\" is black in Light, white in Dark.",
        "apps.emptyHint": "Open the app you want to stash. It shows up here once it is running.",
        "apps.search": "Search apps",
        "apps.searchEmpty": "No open app matches that name.",
        "apps.listNote": "Only apps that are open right now. Closed apps do not appear. An app you already enabled stays in the list after you quit it.",
        "apps.defaultsCard": "Defaults",
        "apps.uniformEdges": "Default stash side",
        "apps.uniformEdges.note": "Left and right can be chosen separately. A side taken by the Dock turns itself off.",
        "apps.uniformEdges.apply": "Enabled apps below all use this side.",
        "apps.avoidDock": "Keep off the Dock",
        "apps.avoidDock.note": "Whichever side the Dock is on will not stash.",
        "apps.allStashedDock": "When every window is stashed, a Dock click",
        "apps.allStashedDock.leaveClosed": "Bring the app forward",
        "apps.allStashedDock.openMostRecent": "Open the most recent stash",
        "apps.allStashedDock.openOnPointerDisplay": "Open stashes on this display",
        "apps.allStashedDock.openAll": "Open all stashes",

        // Sides
        "side.leftOnly": "Left side only",
        "side.rightOnly": "Right side only",
        "side.both": "Both sides",

        // Dock
        "dock.blockedLeft": "Dock is on the left, so the left side is off for now",
        "dock.blockedRight": "Dock is on the right, so the right side is off for now",
        "dock.sideLeft": "Left",
        "dock.sideRight": "Right",
        "dock.sideBottom": "Bottom",
        "dock.unknown": "Not found",
        "dock.autoLabel": "Automatic",
        "dock.autoDetected": "Automatic · %@",
        "dock.atLeft": "Dock on the left",
        "dock.atRight": "Dock on the right",
        "dock.atBottom": "Dock at the bottom",

        // Behavior page
        "behavior.cardGuard": "Accidental stash",
        "behavior.revealDelay": "Expand delay",
        "behavior.revealDelay.note": "The pointer has to rest on the edge this long before the window expands. Clicking during the wait cancels it.",
        "behavior.bufferX": "Horizontal buffer",
        "behavior.bufferX.note": "The pointer has to move this far sideways off the window before it stashes.",
        "behavior.bufferY": "Vertical buffer",
        "behavior.bufferY.note": "The pointer has to move this far up or down off the window before it stashes.",
        "behavior.cardShortcuts": "Keyboard shortcuts",
        "behavior.shortcutsEmpty": "Enable an app on the Apps page first.",
        "hover.reset": "Reset",
        "hover.instant": "Instant",
        "hover.previewTitle": "Buffer preview",
        "hover.previewCaption": "The dashed line is the range after the buffer is added",
        "hover.sampleWindow": "Window",

        // Display boundaries
        "display.card": "Display edges",
        "display.intro": "Pick the left and right side of each display that may stash. Where two screens meet, the window is minimized.",
        "display.none": "No displays",
        "display.sharedNote": "Where screens meet, the window is minimized",
        "display.sharedUnavailable": "This Mac cannot stash at a screen seam yet (macOS 26.4 or later). Outer edges still work.",
        "display.sharedHowTo": "If a minimized window keeps its own Dock thumbnail, turn on \"Minimize windows into application icon\" under System Settings → Desktop & Dock.",
        "display.openDockPane": "Open Desktop & Dock",
        "display.primary": "Main",
        "display.safeDefaults": "Reset",
        "display.leftEdge": "Left",
        "display.rightEdge": "Right",
        "display.outerEdge": "Outer",
        "display.partialShared": "Partly shared · depends on where the window sits",
        "display.fullyShared": "Fully shared · window minimize only",
        "display.partialSharedUnavailable": "Partly shared · only the outer part can stash now",
        "display.fullySharedUnavailable": "Fully shared · cannot stash now",

        // Arrangement map
        "map.card": "Display arrangement",
        "map.intro": "Drawn at the sizes macOS uses. Click a left or right edge to preview that side on the real screen.",
        "map.stateOff": "Off",
        "map.stateOuter": "Slides off",
        "map.stateSeam": "Minimizes",

        // Shortcuts
        "shortcut.stashFront": "Stash the current window",
        "shortcut.stashFront.note": "The ordinary window with keyboard focus. Dialogs, full-screen and minimized windows are excluded.",
        "shortcut.scopeAll": "Toggle all stashed windows",
        "shortcut.scopeAll.note": "When off, toggle the most recent stash. With no stash, the shortcut captures an ordinary window.",
        "menu.expandAll": "Expand All Stashed Windows",
        "system.persistenceFailure": "Local settings or recovery information could not be fully read or saved. Windows stay visible when recovery information cannot be saved. Check available disk space and permissions for the EdgeStash settings directory.",
        "shortcut.taken": "That shortcut is already used by “%@”.",
        "shortcut.systemClash": "The system also uses %@ on this shortcut. They may clash.",

        // System page
        "system.cardGeneral": "General",
        "system.launchAtLogin": "Launch at login",
        "system.menuBarIcon": "Keep the menu bar icon",
        "system.menuBarIcon.note": "If the icon is hidden, reopen EdgeStash in Finder to get this window back.",
        "system.cardAccess": "Access",
        "system.ax": "Accessibility",
        "system.granted": "Granted",
        "system.grant": "Grant",
        "system.access.note": "Stashing other apps' windows needs Accessibility. Without it, Settings still works; other windows are left alone. Launch never asks. No screen capture. No network.",

        // Motion / merge (shown on Behavior)
        "system.effects": "Expand and stash animation",
        "system.effects.note": "A short sheen along the edge when a window moves.",
        "system.merged": "Merge glass side bars",
        "system.merged.note": "Bars stacked on the same edge become one bar you can click by segment.",
        "merged.note.flourish": "Merged bars skip the sheen so switching stays quick.",
        "merged.note.speed": "Different apps stash at slightly different speeds.",
        "merged.note.tint": "Different colors make each segment easy to tell apart.",
        "merged.overload.title": "Too many windows on this edge. Switching may hitch.",
        "merged.overload.body": "Fewer windows stays smoother.",
        "merged.overload.ok": "OK",

        // Alerts & menu
        "alert.rescue.title": "Accessibility is required",
        "alert.rescue.body": "Some windows were left off-screen last time. EdgeStash has shown them again; putting them back needs Accessibility.",
        "alert.rescue.openSettings": "Open System Settings",
        "alert.rescue.later": "Later",
        "menu.settings": "EdgeStash Settings…",
        "menu.quit": "Quit EdgeStash",

        // Multi-window tip
        "multiwindow.title": "This app has more than one window stashed",
        "multiwindow.body": "“%@” has more than one window stashed. The Dock icon only brings back the newest. Whether the app shortcut moves all of them or just the newest is in Settings.",
        "multiwindow.later": "Later",
        "multiwindow.mute": "Don't remind me",

        // Seam availability — first-time only; everyday words, no invented nouns.
        "seam.limitation.title": "This window will not open here",
        "seam.fullscreenDisabled": "The window is still on this edge. This screen is in full screen, and opening it now would pull you out. Leave full screen, then move the pointer to this edge.",
        "seam.revealFailed": "The window is still on this edge. This screen cannot bring it back right now — usually because it is in full screen. Leave full screen, or swipe back to the page you normally use, then move the pointer to this edge.",

        // Pin
        "pin.release": "Unpin",
        "pin.place": "Pin this window",

        // About
        "about.tagline": "Stash windows at the screen edge.",
        "about.offlineLine": "No network. No screen capture.",
        "about.cardPrivacy": "Privacy",
        "about.privacy.body": "Everything stays on this Mac. No window contents are uploaded, and nothing is logged about how you use it.",
        "about.privacy.ax": "Moving other apps' windows needs Accessibility. You grant it on the System page. Launch never asks.",

        // Palette labels (accessibility only)
        "tint.adaptive": "Follow system",
        "tint.ivory": "White",
        "tint.graphite": "Black",
        "tint.amber": "Yellow",
        "tint.gold": "Gold",
        "tint.azure": "Blue",
        "tint.moss": "Green",
        "tint.crimson": "Red",
        "tint.violet": "Purple",
        "tint.rose": "Pink",
        "tint.custom": "Custom color",

        // System chord reference
        "chord.undo": "Undo",
        "chord.redo": "Redo",
        "chord.cut": "Cut",
        "chord.copy": "Copy",
        "chord.paste": "Paste",
        "chord.selectAll": "Select All",
        "chord.find": "Find",
        "chord.close": "Close Window",
        "chord.minimize": "Minimize",
        "chord.hide": "Hide App",
        "chord.quit": "Quit App",
        "chord.switchApp": "Switch Apps",
        "chord.switchWindow": "Switch Windows",
        "chord.spotlight": "Spotlight",
        "chord.screenshotFull": "Screenshot",
        "chord.screenshotArea": "Capture Area",
        "chord.screenshotPanel": "Capture & Record",
        "chord.forceQuit": "Force Quit",
    ]

    static func text(_ id: String) -> String {
        en[id] ?? id
    }

}

/// Named accessors so call sites read as prose and typos fail at compile time.
extension L10n {
    static var tabApps: String { text("tab.apps") }
    static var tabBehavior: String { text("tab.behavior") }
    static var tabSystem: String { text("tab.system") }
    static var tabAbout: String { text("tab.about") }
    static var tabAppsSummary: String { text("tab.apps.summary") }
    static var tabBehaviorSummary: String { text("tab.behavior.summary") }
    static var tabSystemSummary: String { text("tab.system.summary") }
    static var tabAboutSummary: String { text("tab.about.summary") }

    static var appsAutoColorNote: String { text("apps.autoColorNote") }
    static var appsEmptyHint: String { text("apps.emptyHint") }
    static var appsSearch: String { text("apps.search") }
    static var appsSearchEmpty: String { text("apps.searchEmpty") }
    static var appsListNote: String { text("apps.listNote") }
    static var appsDefaultsCard: String { text("apps.defaultsCard") }
    static var appsUniformEdges: String { text("apps.uniformEdges") }
    static var appsUniformEdgesNote: String { text("apps.uniformEdges.note") }
    static var appsUniformEdgesApply: String { text("apps.uniformEdges.apply") }
    static var appsAvoidDock: String { text("apps.avoidDock") }
    static var appsAvoidDockNote: String { text("apps.avoidDock.note") }
    static var appsAllStashedDock: String { text("apps.allStashedDock") }
    static var appsAllStashedDockLeaveClosed: String { text("apps.allStashedDock.leaveClosed") }
    static var appsAllStashedDockOpenMostRecent: String { text("apps.allStashedDock.openMostRecent") }
    static var appsAllStashedDockOpenOnPointerDisplay: String { text("apps.allStashedDock.openOnPointerDisplay") }
    static var appsAllStashedDockOpenAll: String { text("apps.allStashedDock.openAll") }

    static var sideLeftOnly: String { text("side.leftOnly") }
    static var sideRightOnly: String { text("side.rightOnly") }
    static var sideBoth: String { text("side.both") }

    static var dockBlockedLeft: String { text("dock.blockedLeft") }
    static var dockBlockedRight: String { text("dock.blockedRight") }
    static var dockSideLeft: String { text("dock.sideLeft") }
    static var dockSideRight: String { text("dock.sideRight") }
    static var dockSideBottom: String { text("dock.sideBottom") }
    static var dockUnknown: String { text("dock.unknown") }
    static var dockAutoLabel: String { text("dock.autoLabel") }
    static func dockAutoDetected(_ side: String) -> String {
        String(format: text("dock.autoDetected"), side)
    }
    static var dockAtLeft: String { text("dock.atLeft") }
    static var dockAtRight: String { text("dock.atRight") }
    static var dockAtBottom: String { text("dock.atBottom") }

    static var behaviorCardGuard: String { text("behavior.cardGuard") }
    static var behaviorRevealDelay: String { text("behavior.revealDelay") }
    static var behaviorRevealDelayNote: String { text("behavior.revealDelay.note") }
    static var behaviorBufferX: String { text("behavior.bufferX") }
    static var behaviorBufferXNote: String { text("behavior.bufferX.note") }
    static var behaviorBufferY: String { text("behavior.bufferY") }
    static var behaviorBufferYNote: String { text("behavior.bufferY.note") }
    static var behaviorCardShortcuts: String { text("behavior.cardShortcuts") }
    static var behaviorShortcutsEmpty: String { text("behavior.shortcutsEmpty") }
    static var hoverReset: String { text("hover.reset") }
    static var hoverInstant: String { text("hover.instant") }
    static var hoverPreviewTitle: String { text("hover.previewTitle") }
    static var hoverPreviewCaption: String { text("hover.previewCaption") }
    static var hoverSampleWindow: String { text("hover.sampleWindow") }

    static var displayCard: String { text("display.card") }
    static var displayIntro: String { text("display.intro") }
    static var displayNone: String { text("display.none") }
    static var displaySharedNote: String { text("display.sharedNote") }
    static var displaySharedUnavailable: String { text("display.sharedUnavailable") }
    static var displaySharedHowTo: String { text("display.sharedHowTo") }
    static var displayOpenDockPane: String { text("display.openDockPane") }
    static var displayPrimary: String { text("display.primary") }
    static var displaySafeDefaults: String { text("display.safeDefaults") }
    static var displayLeftEdge: String { text("display.leftEdge") }
    static var displayRightEdge: String { text("display.rightEdge") }
    static var displayOuterEdge: String { text("display.outerEdge") }
    static var displayPartialShared: String { text("display.partialShared") }
    static var displayFullyShared: String { text("display.fullyShared") }
    static var displayPartialSharedUnavailable: String { text("display.partialSharedUnavailable") }
    static var displayFullySharedUnavailable: String { text("display.fullySharedUnavailable") }

    static var mapCard: String { text("map.card") }
    static var mapIntro: String { text("map.intro") }
    static var mapStateOff: String { text("map.stateOff") }
    static var mapStateOuter: String { text("map.stateOuter") }
    static var mapStateSeam: String { text("map.stateSeam") }

    static var shortcutStashFront: String { text("shortcut.stashFront") }
    static var shortcutStashFrontNote: String { text("shortcut.stashFront.note") }
    static var shortcutScopeAll: String { text("shortcut.scopeAll") }
    static var shortcutScopeAllNote: String { text("shortcut.scopeAll.note") }
    static func shortcutTaken(_ owner: String) -> String {
        String(format: text("shortcut.taken"), owner)
    }
    static func shortcutSystemClash(_ note: String) -> String {
        String(format: text("shortcut.systemClash"), note)
    }

    static var systemCardGeneral: String { text("system.cardGeneral") }
    static var systemLaunchAtLogin: String { text("system.launchAtLogin") }
    static var systemMenuBarIcon: String { text("system.menuBarIcon") }
    static var systemMenuBarIconNote: String { text("system.menuBarIcon.note") }
    static var systemCardAccess: String { text("system.cardAccess") }
    static var systemAx: String { text("system.ax") }
    static var systemGranted: String { text("system.granted") }
    static var systemGrant: String { text("system.grant") }
    static var systemAccessNote: String { text("system.access.note") }

    static var systemEffects: String { text("system.effects") }
    static var systemEffectsNote: String { text("system.effects.note") }
    static var systemMergedStrip: String { text("system.merged") }
    static var systemMergedStripNote: String { text("system.merged.note") }
    static var stripNoteFlourish: String { text("merged.note.flourish") }
    static var stripNoteSpeed: String { text("merged.note.speed") }
    static var stripNoteTint: String { text("merged.note.tint") }
    static var stripOverloadTitle: String { text("merged.overload.title") }
    static var stripOverloadBody: String { text("merged.overload.body") }
    static var stripOverloadOK: String { text("merged.overload.ok") }

    static var alertRescueTitle: String { text("alert.rescue.title") }
    static var alertRescueBody: String { text("alert.rescue.body") }
    static var alertRescueOpenSettings: String { text("alert.rescue.openSettings") }
    static var alertRescueLater: String { text("alert.rescue.later") }
    static var menuSettings: String { text("menu.settings") }
    static var menuQuit: String { text("menu.quit") }

    static var multiwindowTitle: String { text("multiwindow.title") }
    static func multiwindowBody(_ app: String) -> String {
        String(format: text("multiwindow.body"), app)
    }
    static var multiwindowLater: String { text("multiwindow.later") }
    static var multiwindowMute: String { text("multiwindow.mute") }

    static var seamLimitationTitle: String { text("seam.limitation.title") }
    static var seamFullscreenDisabled: String { text("seam.fullscreenDisabled") }
    static var seamRevealFailed: String { text("seam.revealFailed") }

    static var pinRelease: String { text("pin.release") }
    static var pinPlace: String { text("pin.place") }

    static var aboutTagline: String { text("about.tagline") }
    static var aboutOfflineLine: String { text("about.offlineLine") }
    static var aboutCardPrivacy: String { text("about.cardPrivacy") }
    static var aboutPrivacyBody: String { text("about.privacy.body") }
    static var aboutPrivacyAx: String { text("about.privacy.ax") }

    static var tintAdaptive: String { text("tint.adaptive") }
    static var tintIvory: String { text("tint.ivory") }
    static var tintGraphite: String { text("tint.graphite") }
    static var tintAmber: String { text("tint.amber") }
    static var tintGold: String { text("tint.gold") }
    static var tintAzure: String { text("tint.azure") }
    static var tintMoss: String { text("tint.moss") }
    static var tintCrimson: String { text("tint.crimson") }
    static var tintViolet: String { text("tint.violet") }
    static var tintRose: String { text("tint.rose") }
    static var tintCustom: String { text("tint.custom") }

    static var chordUndo: String { text("chord.undo") }
    static var chordRedo: String { text("chord.redo") }
    static var chordCut: String { text("chord.cut") }
    static var chordCopy: String { text("chord.copy") }
    static var chordPaste: String { text("chord.paste") }
    static var chordSelectAll: String { text("chord.selectAll") }
    static var chordFind: String { text("chord.find") }
    static var chordClose: String { text("chord.close") }
    static var chordMinimize: String { text("chord.minimize") }
    static var chordHide: String { text("chord.hide") }
    static var chordQuit: String { text("chord.quit") }
    static var chordSwitchApp: String { text("chord.switchApp") }
    static var chordSwitchWindow: String { text("chord.switchWindow") }
    static var chordSpotlight: String { text("chord.spotlight") }
    static var chordScreenshotFull: String { text("chord.screenshotFull") }
    static var chordScreenshotArea: String { text("chord.screenshotArea") }
    static var chordScreenshotPanel: String { text("chord.screenshotPanel") }
    static var chordForceQuit: String { text("chord.forceQuit") }
}
