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
        "tab.apps.summary": "挑选可以贴边收纳的应用，并为各自的提示条配置颜色与不透明度。",
        "tab.behavior.summary": "设定提示条何时出现，以及允许使用哪些屏幕边界。",
        "tab.system.summary": "本机选项、界面语言与辅助功能授权。",
        "tab.about.summary": "认识 EdgeStash：它的能力与边界。",

        // Apps page
        "apps.autoColorNote": "「随系统」的颜色会跟着系统外观走：浅色外观用黑色，深色外观用白色。",
        "apps.emptyHint": "这里还没有应用。把想收纳的应用启动起来，它就会出现在列表里。",
        "apps.defaultsCard": "提示条默认值",
        "apps.uniformAlpha": "统一不透明度",
        "apps.uniformAlpha.note": "打开后，下方所有已启用的应用都会改用这个不透明度。",
        "apps.uniformEdges": "统一贴边侧",
        "apps.uniformEdges.note": "把收纳限制在这些屏幕边上，左右可以任选组合；被程序坞占着的一侧会自动停用，并在下面说明原因。",
        "apps.uniformEdges.apply": "打开后，下方所有已启用的应用都会改用这个贴边侧。",
        "apps.avoidDock": "避让程序坞",
        "apps.avoidDock.note": "自动判断程序坞在左、右还是下方，并让同侧的收纳让路。",

        // Sides
        "side.leftOnly": "只收左侧",
        "side.rightOnly": "只收右侧",
        "side.both": "左右都收",

        // Dock
        "dock.blockedLeft": "程序坞在左边，左侧收纳暂时让路",
        "dock.blockedRight": "程序坞在右边，右侧收纳暂时让路",
        "dock.sideLeft": "左侧",
        "dock.sideRight": "右侧",
        "dock.sideBottom": "底部",
        "dock.unknown": "未探测到",
        "dock.autoLabel": "自动探测",
        "dock.autoDetected": "自动探测 · %@",
        "dock.atLeft": "程序坞在左侧",
        "dock.atRight": "程序坞在右侧",
        "dock.atBottom": "程序坞在底部",

        // Behavior page
        "behavior.cardGuard": "误触防护",
        "behavior.revealDelay": "唤出延迟（悬停时长）",
        "behavior.revealDelay.note": "指针在屏幕边缘停留满此时长，收起的窗口才被唤出；等待中若按下鼠标键（例如去点滚动条），这次唤出作废。",
        "behavior.bufferX": "横向缓冲（X）",
        "behavior.bufferX.note": "窗口收起前，指针需要在横向上越过缓冲区这么远。",
        "behavior.bufferY": "纵向缓冲（Y）",
        "behavior.bufferY.note": "窗口收起前，指针需要在纵向上越过缓冲区这么远。",
        "behavior.cardShortcuts": "键盘快捷键",
        "behavior.shortcutsEmpty": "还没有启用任何应用；先到「应用」页打开一个。",
        "hover.reset": "重置",
        "hover.instant": "即刻响应",
        "hover.previewTitle": "缓冲效果预览（随数值即时更新）",
        "hover.previewCaption": "虚线框是加上缓冲之后的安全范围",
        "hover.sampleWindow": "示例窗口",

        // Display boundaries
        "display.card": "屏幕边界",
        "display.intro": "逐台显示器勾选允许收纳的左右两侧。暴露段滑出屏外；显示器锚定能力可用时，共用段交给 macOS 最小化，窗口真正离开屏幕。",
        "display.none": "没有探测到显示器",
        "display.sharedNote": "共用段交给系统最小化",
        "display.sharedUnavailable": "这台 Mac 当前没有可用的显示器锚定迁移能力；接缝区段不会收纳，以免窗口被错误地绑在某个桌面。外侧区段不受影响。此能力需要 macOS 26.4 或更高版本。",
        "display.sharedHowTo": "若最小化后的窗口在程序坞里成了独立缩略图，请到「系统设置 → 桌面与程序坞」开启「将窗口最小化成应用程序图标」（旧系统名称或有出入）。",
        "display.openDockPane": "打开「桌面与程序坞」",
        "display.primary": "主屏",
        "display.safeDefaults": "恢复稳妥默认",
        "display.leftEdge": "左侧边",
        "display.rightEdge": "右侧边",
        "display.outerEdge": "外侧边",
        "display.partialShared": "部分共用 · 按窗口所在段自动处理",
        "display.fullyShared": "完全共用 · 仅系统最小化",
        "display.partialSharedUnavailable": "部分共用 · 当前仅外侧段可收纳",
        "display.fullySharedUnavailable": "完全共用 · 当前不可收纳",

        // Arrangement map
        "map.card": "显示器排布（逻辑）",
        "map.intro": "以 macOS 的逻辑矩形画出每台显示器（不带边框厚度）。点某条左/右边，即可在真实屏幕上试那一侧的收纳效果。",
        "map.stateOff": "已停用",
        "map.stateOuter": "外侧滑条",
        "map.stateSeam": "接缝标记",

        // Shortcuts
        "shortcut.stashFront": "随手收起最前窗口",
        "shortcut.stashFront.note": "把当前最前面的窗口临时收向就近的屏幕边；再按一次立刻放回，把窗口从边上拖开也会结束这次临时收纳。",
        "shortcut.scopeAll": "一次作用于该应用的所有窗口",
        "shortcut.scopeAll.note": "关闭时，快捷键只处理最近操作的那一个窗口。",
        "shortcut.taken": "这组按键已经分给了「%@」，换一组吧。",
        "shortcut.systemClash": "系统把 %@ 也绑在同一组按键上，实际使用可能互相干扰。",

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
        "system.access.note": "收纳其他应用的窗口需要辅助功能权限。没有授权时 EdgeStash 照常运行、只是不碰别人的窗口；启动时不弹窗索权，也不截屏、不联网。",

        // Extras
        "system.cardExtras": "进阶表现",
        "system.effects": "展开与收起的动画",
        "system.effects.note": "窗口展开或收起时是否沿边缘播放一小段玻璃高光。",
        "system.merged": "合并长条",
        "system.merged.note": "同一条边上彼此重叠的提示条会拼成一根长条，长条分段、可逐段点选。",
        "merged.note.flourish": "合并状态下不再播放高光，把切换的延迟降到最低。",
        "merged.note.speed": "各家应用的窗口机制不同，收放速度也会略有差别。",
        "merged.note.tint": "给应用分配不同的颜色，合并后一眼就能分清每段是谁。",
        "merged.overload.title": "这根合并长条上的窗口太多了，连续切换可能一顿一顿的。",
        "merged.overload.body": "少堆几个，切换会更顺。",
        "merged.overload.ok": "知道了",

        // Alerts & menu
        "alert.rescue.title": "需要「辅助功能」权限",
        "alert.rescue.body": "上次退出时有窗口留在了屏幕外。EdgeStash 已经把它们重新显示出来；要把它们放回原位，还差辅助功能权限。",
        "alert.rescue.openSettings": "打开系统设置",
        "alert.rescue.later": "先不管",
        "menu.settings": "EdgeStash 设置…",
        "menu.quit": "退出 EdgeStash",

        // Multi-window tip
        "multiwindow.title": "这个应用的好几个窗口都收起来了",
        "multiwindow.body": "「%@」有不止一个窗口收着。点程序坞图标只会放出最近的那个；应用快捷键想在全部和最近之间选一个作用范围，去设置里调。",
        "multiwindow.later": "等会再说",
        "multiwindow.mute": "别再提醒",

        // Seam availability — first-time only; everyday words, no invented nouns.
        "seam.limitation.title": "现在打不开这扇窗口",
        "seam.fullscreenDisabled": "窗口没有丢，它还在边上。这台屏幕正在全屏使用某个应用；如果现在打开，会把你从全屏里拉出来。退出全屏之后，再把鼠标放到这条边上就可以打开。",
        "seam.revealFailed": "窗口没有丢，它还在边上。这台屏幕现在不能把窗口移过来，常见原因是正在全屏。退出全屏，或用三指滑回平时那一页之后，再把鼠标放到这条边上就可以打开。",

        // Pin
        "pin.release": "取消固定",
        "pin.place": "固定此窗口",

        // About
        "about.tagline": "一台 Mac、一个菜单栏图标，把窗口贴边收好的小工具。",
        "about.offlineLine": "离线运行，不联网、不截屏。",
        "about.cardPrivacy": "隐私",
        "about.privacy.body": "EdgeStash 的全部工作都在这台 Mac 上完成：不上传窗口内容、截图，也不记录使用习惯。",
        "about.privacy.ax": "控制别的应用的窗口依托系统辅助功能。授不授权、什么时候授，都由你在「系统」页决定；启动时不会弹窗，未授权时 EdgeStash 照常打开，只是不去动其他窗口。",

        // Palette labels
        "tint.adaptive": "随系统",
        "tint.ivory": "象牙",
        "tint.graphite": "石墨",
        "tint.amber": "琥珀",
        "tint.gold": "鎏金",
        "tint.azure": "湖蓝",
        "tint.moss": "苔绿",
        "tint.crimson": "绯红",
        "tint.violet": "堇紫",
        "tint.rose": "蔷薇",
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
        "tab.apps.summary": "Pick which apps may stash, then style each strip's color and opacity.",
        "tab.behavior.summary": "Choose when strips appear and which display edges are allowed.",
        "tab.system.summary": "Machine-wide options, interface language, and Accessibility access.",
        "tab.about.summary": "Meet EdgeStash: what it can do, and where it stops.",

        // Apps page
        "apps.autoColorNote": "The \"adaptive\" color tracks the system appearance: black in Light, white in Dark.",
        "apps.emptyHint": "No apps yet. Launch one you want to stash and it will appear here.",
        "apps.defaultsCard": "Strip defaults",
        "apps.uniformAlpha": "Shared opacity",
        "apps.uniformAlpha.note": "Switching this on retunes every enabled app below to the same opacity.",
        "apps.uniformEdges": "Shared edges",
        "apps.uniformEdges.note": "Restrict stashing to the chosen sides; left and right combine freely. A side the Dock occupies switches itself off, with a note below.",
        "apps.uniformEdges.apply": "Switching this on moves every enabled app below to the same edge choice.",
        "apps.avoidDock": "Stay clear of the Dock",
        "apps.avoidDock.note": "Works out where the Dock sits — left, right, or bottom — and keeps that side free.",

        // Sides
        "side.leftOnly": "Left side only",
        "side.rightOnly": "Right side only",
        "side.both": "Both sides",

        // Dock
        "dock.blockedLeft": "The Dock sits on the left; left-side stashing steps aside",
        "dock.blockedRight": "The Dock sits on the right; right-side stashing steps aside",
        "dock.sideLeft": "Left",
        "dock.sideRight": "Right",
        "dock.sideBottom": "Bottom",
        "dock.unknown": "No Dock found",
        "dock.autoLabel": "Auto probe",
        "dock.autoDetected": "Auto probe · %@",
        "dock.atLeft": "Dock on the left",
        "dock.atRight": "Dock on the right",
        "dock.atBottom": "Dock at the bottom",

        // Behavior page
        "behavior.cardGuard": "Mis-touch guard",
        "behavior.revealDelay": "Reveal delay (hover time)",
        "behavior.revealDelay.note": "The pointer must rest at the edge for this long before a stashed window returns; pressing a mouse button during the wait (say, to hit a scrollbar) cancels it.",
        "behavior.bufferX": "Horizontal buffer (X)",
        "behavior.bufferX.note": "Before a window tucks away, the pointer must clear the buffer by this much horizontally.",
        "behavior.bufferY": "Vertical buffer (Y)",
        "behavior.bufferY.note": "Before a window tucks away, the pointer must clear the buffer by this much vertically.",
        "behavior.cardShortcuts": "Keyboard shortcuts",
        "behavior.shortcutsEmpty": "Nothing is enabled yet — switch on an app in the Apps page first.",
        "hover.reset": "Reset",
        "hover.instant": "Immediate",
        "hover.previewTitle": "Buffer preview (updates live)",
        "hover.previewCaption": "The dashed outline marks the safe area once buffering applies",
        "hover.sampleWindow": "Example window",

        // Display boundaries
        "display.card": "Display edges",
        "display.intro": "Pick the stashable left and right sides of every display. Exposed segments slide offscreen; when display anchoring is available, shared segments use macOS minimization so stashed windows truly leave the screen.",
        "display.none": "No displays detected",
        "display.sharedNote": "Shared segments minimize",
        "display.sharedUnavailable": "Display-anchored migration is not available on this Mac. Shared seam segments will not stash, avoiding a window being tied to the wrong desktop; exposed outer segments still work. This capability requires macOS 26.4 or later.",
        "display.sharedHowTo": "If a minimized window keeps its own Dock thumbnail, enable \"Minimize windows into application icon\" under System Settings → Desktop & Dock (names differ slightly on older macOS).",
        "display.openDockPane": "Open Desktop & Dock",
        "display.primary": "Primary",
        "display.safeDefaults": "Back to safe defaults",
        "display.leftEdge": "Left edge",
        "display.rightEdge": "Right edge",
        "display.outerEdge": "Outer edge",
        "display.partialShared": "Partially shared · decided per segment",
        "display.fullyShared": "Fully shared · minimization only",
        "display.partialSharedUnavailable": "Partially shared · only exposed segments can stash now",
        "display.fullySharedUnavailable": "Fully shared · unavailable now",

        // Arrangement map
        "map.card": "Display layout (logical)",
        "map.intro": "Renders each display as its macOS logical rectangle, bezel excluded. Clicking a left or right side previews that side's stash behavior on the physical screen.",
        "map.stateOff": "Off",
        "map.stateOuter": "Outer strip",
        "map.stateSeam": "Seam marker",

        // Shortcuts
        "shortcut.stashFront": "Tuck away the front window",
        "shortcut.stashFront.note": "Sends the frontmost window to the nearest edge for now. Press again to return it; dragging it away from the edge ends the temporary stash too.",
        "shortcut.scopeAll": "Hit every window of the app at once",
        "shortcut.scopeAll.note": "When off, the shortcut only handles the window you touched last.",
        "shortcut.taken": "That chord already belongs to “%@”. Pick another.",
        "shortcut.systemClash": "The system binds %@ to the same chord; the two may fight in practice.",

        // System page
        "system.cardGeneral": "General",
        "system.launchAtLogin": "Launch at login",
        "system.menuBarIcon": "Keep the menu bar icon",
        "system.menuBarIcon.note": "With the icon hidden, reopening EdgeStash in Finder brings this window back.",
        "system.language": "Interface language",
        "system.lang.system": "Follow system",
        "system.lang.zh": "简体中文",
        "system.lang.en": "English",
        "system.cardAccess": "Access",
        "system.ax": "Accessibility",
        "system.granted": "Granted",
        "system.grant": "Grant",
        "system.access.note": "Touching other apps' windows needs Accessibility. Untrusted, EdgeStash still runs — it just leaves other windows alone. Launch never asks; nothing is captured or sent.",

        // Extras
        "system.cardExtras": "Finer points",
        "system.effects": "Expand & tuck animation",
        "system.effects.note": "Whether windows play a short glass sheen as they expand or tuck.",
        "system.merged": "Merged strip",
        "system.merged.note": "Strips overlapping on one edge join into a single segmented bar you can click segment by segment.",
        "merged.note.flourish": "Merged bars skip the flourish so switching stays instant.",
        "merged.note.speed": "Window plumbing differs per app, so tuck speed varies a little.",
        "merged.note.tint": "Give apps distinct colors so each segment reads at a glance.",
        "merged.overload.title": "Too many windows share this bar; rapid switching may stutter.",
        "merged.overload.body": "Stack fewer and switching stays smooth.",
        "merged.overload.ok": "Got it",

        // Alerts & menu
        "alert.rescue.title": "Accessibility permission required",
        "alert.rescue.body": "Some windows ended the last session off-screen. EdgeStash has made them visible again; putting them back needs Accessibility.",
        "alert.rescue.openSettings": "Open System Settings",
        "alert.rescue.later": "Later",
        "menu.settings": "EdgeStash Settings…",
        "menu.quit": "Quit EdgeStash",

        // Multi-window tip
        "multiwindow.title": "Several windows of this app are tucked away",
        "multiwindow.body": "“%@” has more than one window tucked away. Its Dock icon releases only the newest; whether the app shortcut frees everything or just the latest is a Settings choice.",
        "multiwindow.later": "Maybe later",
        "multiwindow.mute": "Don't remind me",

        // Seam availability — first-time only; everyday words, no invented nouns.
        "seam.limitation.title": "This window will not open here",
        "seam.fullscreenDisabled": "The window is still here, on this edge. This screen is in full screen, and opening the window now would pull you out of it. Leave full screen, then move the pointer to this edge to open it.",
        "seam.revealFailed": "The window is still here, on this edge. This screen cannot bring it back right now — usually because it is in full screen. Leave full screen, or swipe to the page you normally use, then move the pointer to this edge.",

        // Pin
        "pin.release": "Release",
        "pin.place": "Pin here",

        // About
        "about.tagline": "One Mac, one menu-bar icon: windows tucked neatly at the edges.",
        "about.offlineLine": "Runs offline: no network, no screen capture.",
        "about.cardPrivacy": "Privacy",
        "about.privacy.body": "Everything stays on this Mac: no window contents, screenshots, or usage traces leave it.",
        "about.privacy.ax": "Controlling other apps' windows rides on system Accessibility. You decide if and when on the System page; launch never asks, and untrusted EdgeStash simply opens without touching other windows.",

        // Palette labels
        "tint.adaptive": "Adaptive",
        "tint.ivory": "Ivory",
        "tint.graphite": "Graphite",
        "tint.amber": "Amber",
        "tint.gold": "Gilded",
        "tint.azure": "Azure",
        "tint.moss": "Moss",
        "tint.crimson": "Ruby",
        "tint.violet": "Violet",
        "tint.rose": "Rose",
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
    static var appsDefaultsCard: String { text("apps.defaultsCard") }
    static var appsUniformAlpha: String { text("apps.uniformAlpha") }
    static var appsUniformAlphaNote: String { text("apps.uniformAlpha.note") }
    static var appsUniformEdges: String { text("apps.uniformEdges") }
    static var appsUniformEdgesNote: String { text("apps.uniformEdges.note") }
    static var appsUniformEdgesApply: String { text("apps.uniformEdges.apply") }
    static var appsAvoidDock: String { text("apps.avoidDock") }
    static var appsAvoidDockNote: String { text("apps.avoidDock.note") }

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

    static var systemCardExtras: String { text("system.cardExtras") }
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
