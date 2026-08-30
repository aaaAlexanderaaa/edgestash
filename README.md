# EdgeStash

把窗口收到屏幕边缘，需要时再唤出。这是一个只在本机运行的 macOS 菜单栏应用。

当前发布的安装包是 **Apple 芯片（M 系列）** 的单一构建，不包含 Intel。

## 系统要求

- Apple 芯片 Mac
- macOS 12 或更高
- 两块屏幕中间的**接缝收纳**需要 macOS 26.4 或更高。更早的系统仍可用屏幕外侧收纳；接缝处不会收，以免窗口被绑到错误的桌面。

## 安装

1. 从 [Releases](https://github.com/aaaAlexanderaaa/edgestash/releases/latest) 下载 `EdgeStash.zip`。
2. 解压，把 `EdgeStash.app` 放到「应用程序」。
3. 打开应用。第一次请授予**辅助功能**权限（系统设置 → 隐私与安全性 → 辅助功能）。没有权限时设置页会自己打开；授权之后从菜单栏图标再打开即可。
4. 若系统提示无法验证开发者：按住 Control 点击应用，选择「打开」。

## 用法

- 把窗口拖到屏幕外沿并停住，就会收进去。
- 屏幕外侧：窗口滑出屏幕，边上留一条提示。
- 两块屏幕的接缝：窗口最小化离开屏幕，边上留一条信标（需要 macOS 26.4）。
- 鼠标悬停或点击提示条 / 信标即可唤出。
- 菜单栏图标打开设置：选择应用、收纳边、外观和快捷键。

## 隐私

只在这台 Mac 上工作。不上网、不遥测、不截屏。辅助功能只用来移动和恢复窗口。

---

# English

Stash windows at a display edge and bring them back when you need them. EdgeStash is a local-only macOS menu-bar app.

The published build is **Apple Silicon only**. Intel Macs are not supported.

## Requirements

- Apple Silicon Mac
- macOS 12 or later
- **Seam stashing** between two displays needs macOS 26.4 or later. Older systems can still stash on an exposed outer edge. Shared seams stay off so a window is not tied to the wrong desktop.

## Install

1. Download `EdgeStash.zip` from [Releases](https://github.com/aaaAlexanderaaa/edgestash/releases/latest).
2. Unzip and move `EdgeStash.app` to Applications.
3. Open the app and grant **Accessibility** (System Settings → Privacy & Security → Accessibility). Settings opens on its own when permission is missing; after you grant it, reopen from the menu-bar item.
4. If macOS says the developer cannot be verified, Control-click the app and choose Open.

## Use

- Drag a window to a display edge and hold to stash it.
- Outer edge: the window slides offscreen and leaves a marker.
- Shared seam: the window minimizes off the screen and leaves a beacon (macOS 26.4+).
- Hover or click the marker or beacon to restore.
- The menu-bar item opens Settings for apps, edges, appearance, and shortcuts.

## Privacy

Everything stays on this Mac. No network, no telemetry, no screen capture. Accessibility is used only to move and restore windows.

## Build from source

```bash
swift run EdgeStashLogicTests
./scripts/stage-app.sh
```

Quit any running EdgeStash, then open `dist/EdgeStash.app`. The zip is `dist/EdgeStash.zip`.
