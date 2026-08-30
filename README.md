# EdgeStash

[中文说明](README_cn.md)

Stash a window at the edge of a display and bring it back when you need it. EdgeStash is a local-only macOS menu-bar app.

The published build is Apple Silicon only. Intel Macs are not supported.

## Outer edges and shared edges

A display has two kinds of edges, and EdgeStash treats them differently.

An **outer edge** does not touch another screen. The window can slide off that side and leave the desktop. A thin marker stays on the edge so you can hover or click it back.

A **shared edge** is the line where two screens meet — the gap between a laptop and an external display, for example. Sliding a window “off” that side would put it on the neighbor, or leave it sitting on the seam. So EdgeStash asks macOS to minimize the window. It actually leaves the screen, and a marker stays on the display that owned it.

That shared-edge path needs macOS 26.4. On an older system, outer edges still work; shared edges will not stash, so a window is not tied to the wrong desktop.

## Requirements

- Apple Silicon Mac
- macOS 12 or later for outer-edge stashing
- macOS 26.4 or later if you want to stash on a shared edge

## Install

1. Download `EdgeStash.zip` from [Releases](https://github.com/aaaAlexanderaaa/edgestash/releases/latest).
2. Unzip and move `EdgeStash.app` to Applications.
3. Open the app and grant Accessibility (System Settings → Privacy & Security → Accessibility). Settings opens on its own when permission is missing; after you grant it, reopen from the menu-bar item.
4. If macOS says the developer cannot be verified, Control-click the app and choose Open.

## Use

- Drag a window to a display edge and hold to stash it.
- Hover or click the marker to restore it.
- The menu-bar item opens Settings for apps, edges, appearance, and shortcuts.

## Privacy

Everything stays on this Mac. No network, no telemetry, no screen capture. Accessibility is used only to move and restore windows.

## Build from source

```bash
swift run EdgeStashLogicTests
./scripts/stage-app.sh
```

Quit any running EdgeStash, then open `dist/EdgeStash.app`. The zip is `dist/EdgeStash.zip`.
