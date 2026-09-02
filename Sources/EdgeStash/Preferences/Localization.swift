import Foundation

/// EdgeStash's copy catalog.
///
/// Copy is addressed by stable dotted identifiers rather than by product
/// strings, so wording can be revised freely in either language without
/// touching call sites. Chinese and English text are both authored entries;
/// there is no fallback chain beyond the two tables.
enum L10n {
    private static let zh: [String: String] = [
        // Tabs
        "tab.apps": "应用",
        "tab.behavior": "行为",
        "tab.system": "系统",
        "tab.about": "关于",
        "tab.apps.summary": "勾选要贴边收纳的应用，并给玻璃侧边条选颜色。",
        "tab.behavior.summary": "什么时候收、什么时候展开，以及哪些屏幕边能用。",
        "tab.system.summary": "开机启动、语言、辅助功能权限。",
        "tab.about.summary": "EdgeStash 是做什么的。",

        // Apps page
        "apps.autoColorNote": "「随系统」浅色用黑，深色用白。",
        "apps.emptyHint": "先打开要收纳的应用，打开后会出现在这里。",
        "apps.search": "搜索应用",
        "apps.searchEmpty": "没有叫这个名字的已打开应用。",
        "apps.listNote": "只列出当前已打开的应用。没打开的加不进来。已经勾选过的关掉后也会留着。",
        "apps.defaultsCard": "默认",
        "apps.uniformEdges": "默认收纳方向",
        "apps.uniformEdges.note": "左右可以分开选。程序坞占着的那一侧会自动停用。",
        "apps.uniformEdges.apply": "下面已勾选的应用都改成这个方向。",
        "apps.avoidDock": "避开程序坞",
        "apps.avoidDock.note": "程序坞在哪一侧，那一侧就不收。",
        "apps.allStashedDock": "窗口全收着时点程序坞",
        "apps.allStashedDock.leaveClosed": "只带到前台",
        "apps.allStashedDock.openMostRecent": "打开最近一个",
        "apps.allStashedDock.openOnPointerDisplay": "打开当前这块屏上的",
        "apps.allStashedDock.openAll": "全部打开",

        // Sides
        "side.leftOnly": "仅左侧收纳",
        "side.rightOnly": "仅右侧收纳",
        "side.both": "两侧均收纳",

        // Dock
        "dock.blockedLeft": "程序坞在左边，左侧先不收",
        "dock.blockedRight": "程序坞在右边，右侧先不收",
        "dock.sideLeft": "左侧",
        "dock.sideRight": "右侧",
        "dock.sideBottom": "底部",
        "dock.unknown": "没找到",
        "dock.autoLabel": "自动",
        "dock.autoDetected": "自动 · %@",
        "dock.atLeft": "程序坞在左",
        "dock.atRight": "程序坞在右",
        "dock.atBottom": "程序坞在底",

        // Behavior page
        "behavior.cardGuard": "误触",
        "behavior.revealDelay": "展开延迟",
        "behavior.revealDelay.note": "鼠标在边上停这么久才展开。停的时候点了鼠标，这次不算。",
        "behavior.bufferX": "横向缓冲",
        "behavior.bufferX.note": "鼠标要横着离开窗口这么远，才会收起来。",
        "behavior.bufferY": "纵向缓冲",
        "behavior.bufferY.note": "鼠标要竖着离开窗口这么远，才会收起来。",
        "behavior.cardShortcuts": "键盘快捷键",
        "behavior.shortcutsEmpty": "先到「应用」里勾选一个。",
        "hover.reset": "重置",
        "hover.instant": "立刻",
        "hover.previewTitle": "缓冲预览",
        "hover.previewCaption": "虚线是加上缓冲之后的范围",
        "hover.sampleWindow": "窗口",

        // Display boundaries
        "display.card": "屏幕边界",
        "display.intro": "勾选每台显示器左右哪一侧可以收纳。两台屏幕挨着的那一侧，窗口会最小化。",
        "display.none": "没有显示器",
        "display.sharedNote": "挨着的那一侧用窗口最小化",
        "display.sharedUnavailable": "这台 Mac 还不能在屏幕接缝处收纳（需要 macOS 26.4 或更高）。外侧不受影响。",
        "display.sharedHowTo": "最小化之后如果程序坞里多出一个窗口缩略图，到「系统设置 → 桌面与程序坞」打开「将窗口最小化成应用程序图标」。",
        "display.openDockPane": "打开「桌面与程序坞」",
        "display.primary": "主屏",
        "display.safeDefaults": "恢复默认",
        "display.leftEdge": "左边",
        "display.rightEdge": "右边",
        "display.outerEdge": "外侧",
        "display.partialShared": "部分共用 · 窗口在哪一段就按哪一段处理",
        "display.fullyShared": "完全共用 · 只最小化窗口",
        "display.partialSharedUnavailable": "部分共用 · 现在只有外侧能收",
        "display.fullySharedUnavailable": "完全共用 · 现在不能收",

        // Arrangement map
        "map.card": "显示器排列",
        "map.intro": "按系统里的逻辑大小画。点左右边，真屏上会亮出那一侧怎么收。",
        "map.stateOff": "已关掉",
        "map.stateOuter": "外侧滑出",
        "map.stateSeam": "接缝最小化",

        // Shortcuts
        "shortcut.stashFront": "收起当前窗口",
        "shortcut.stashFront.note": "键盘焦点所在的那个窗口。",
        "shortcut.scopeAll": "这个应用的窗口一起收",
        "shortcut.scopeAll.note": "关掉则只动最近那个窗口。",
        "shortcut.taken": "这组按键已经给了「%@」。",
        "shortcut.systemClash": "系统和 %@ 用了同一组按键，可能会打架。",

        // System page
        "system.cardGeneral": "通用",
        "system.launchAtLogin": "登录时启动",
        "system.menuBarIcon": "保留菜单栏图标",
        "system.menuBarIcon.note": "图标收起后，在访达里重新打开 EdgeStash 就能回到这个窗口。",
        "system.language": "界面语言",
        "system.lang.system": "跟随系统",
        "system.lang.zh": "简体中文",
        "system.lang.en": "English",
        "system.cardAccess": "权限",
        "system.ax": "辅助功能",
        "system.granted": "已授权",
        "system.grant": "去授权",
        "system.access.note": "收纳别的应用的窗口需要辅助功能。没授权时设置还能用，只是不碰别人的窗口。启动不弹窗，不截屏，不联网。",

        // Motion / merge (shown on Behavior)
        "system.effects": "展开与收起的动画",
        "system.effects.note": "收放时边上闪一下高光。",
        "system.merged": "合并玻璃侧边条",
        "system.merged.note": "同一条边上叠在一起的，会收成一条，可以分段点。",
        "merged.note.flourish": "合并时不放高光，切换更快。",
        "merged.note.speed": "不同应用收放速度会差一点。",
        "merged.note.tint": "颜色不一样，合并之后才分得清是谁。",
        "merged.overload.title": "这条边上收的窗口太多，连着切会卡。",
        "merged.overload.body": "少堆几个会顺一些。",
        "merged.overload.ok": "知道了",

        // Alerts & menu
        "alert.rescue.title": "需要「辅助功能」权限",
        "alert.rescue.body": "上次退出时有窗口留在了屏幕外。EdgeStash 已经把它们重新显示出来；要放回原位，还差辅助功能权限。",
        "alert.rescue.openSettings": "打开系统设置",
        "alert.rescue.later": "先不管",
        "menu.settings": "EdgeStash 设置…",
        "menu.quit": "退出 EdgeStash",

        // Multi-window tip
        "multiwindow.title": "这个应用有多个窗口收着",
        "multiwindow.body": "「%@」收了不止一个窗口。点程序坞图标只放出最近那个。应用快捷键能收全部还是只收最近一个，在设置里改。",
        "multiwindow.later": "等会再说",
        "multiwindow.mute": "别再提醒",

        // Seam availability — first-time only; everyday words, no invented nouns.
        "seam.limitation.title": "现在打不开这个窗口",
        "seam.fullscreenDisabled": "窗口还在边上。这台屏幕正在全屏；现在打开会把你从全屏里拉出来。退出全屏后，再把鼠标放到这条边上就可以打开。",
        "seam.revealFailed": "窗口还在边上。这台屏幕现在不能把它移过来，常见原因是正在全屏。退出全屏，或滑回平时那一页之后，再把鼠标放到这条边上就可以打开。",

        // Pin
        "pin.release": "取消固定",
        "pin.place": "固定这个窗口",

        // About
        "about.tagline": "把窗口收到屏幕边上。",
        "about.offlineLine": "不联网，不截屏。",
        "about.cardPrivacy": "隐私",
        "about.privacy.body": "全部只在这台 Mac 上运行。不上传窗口内容，也不记你怎么用。",
        "about.privacy.ax": "要动别的应用的窗口，得开辅助功能。授不授都在「系统」页。启动不弹窗。",

        // Palette labels (accessibility only; chips have no visible names)
        "tint.adaptive": "随系统",
        "tint.ivory": "白",
        "tint.graphite": "黑",
        "tint.amber": "黄",
        "tint.gold": "金",
        "tint.azure": "蓝",
        "tint.moss": "绿",
        "tint.crimson": "红",
        "tint.violet": "紫",
        "tint.rose": "粉",
        "tint.custom": "自定颜色",

        // System chord reference (glyphs lead; terms follow macOS zh-CN wording)
        "chord.undo": "还原",
        "chord.redo": "重做",
        "chord.cut": "剪切",
        "chord.copy": "拷贝",
        "chord.paste": "粘贴",
        "chord.selectAll": "全选",
        "chord.find": "查找",
        "chord.close": "关闭窗口",
        "chord.minimize": "最小化",
        "chord.hide": "隐藏应用",
        "chord.quit": "退出应用",
        "chord.switchApp": "切换应用",
        "chord.switchWindow": "切换窗口",
        "chord.spotlight": "聚焦搜索",
        "chord.screenshotFull": "屏幕快照",
        "chord.screenshotArea": "区域快照",
        "chord.screenshotPanel": "快照与录屏",
        "chord.forceQuit": "强制退出",
    ]

    private static let en: [String: String] = [
        // Tabs
        "tab.apps": "Apps",
        "tab.behavior": "Behavior",
        "tab.system": "System",
        "tab.about": "About",
        "tab.apps.summary": "Choose which apps can stash, and pick a color for the glass side bar.",
        "tab.behavior.summary": "When windows stash and expand, and which screen edges are allowed.",
        "tab.system.summary": "Launch at login, language, and Accessibility.",
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
        "shortcut.stashFront.note": "The window that has keyboard focus.",
        "shortcut.scopeAll": "Stash every window of this app",
        "shortcut.scopeAll.note": "When off, only the most recent window moves.",
        "shortcut.taken": "That shortcut is already used by “%@”.",
        "shortcut.systemClash": "The system also uses %@ on this shortcut. They may clash.",

        // System page
        "system.cardGeneral": "General",
        "system.launchAtLogin": "Launch at login",
        "system.menuBarIcon": "Keep the menu bar icon",
        "system.menuBarIcon.note": "If the icon is hidden, reopen EdgeStash in Finder to get this window back.",
        "system.language": "Language",
        "system.lang.system": "Follow system",
        "system.lang.zh": "简体中文",
        "system.lang.en": "English",
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

    /// English wins unless the reader asked for Chinese (explicitly or via a
    /// zh system locale).
    private static var prefersEnglish: Bool {
        switch InterfaceLanguage(rawValue: Preferences.shared.language) ?? .system {
        case .chinese:
            return false
        case .english:
            return true
        case .system:
            guard let first = Locale.preferredLanguages.first else { return true }
            return !first.hasPrefix("zh")
        }
    }

    static func text(_ id: String) -> String {
        prefersEnglish ? (en[id] ?? zh[id] ?? id) : (zh[id] ?? en[id] ?? id)
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
    static var systemLanguage: String { text("system.language") }
    static var systemLangSystem: String { text("system.lang.system") }
    static var systemLangZh: String { text("system.lang.zh") }
    static var systemLangEn: String { text("system.lang.en") }
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
