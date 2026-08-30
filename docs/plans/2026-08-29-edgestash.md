---
doc_type: plan
status: historical
authority: planning
last_reconciled: 2026-08-30
---

# EdgeStash Implementation Plan

**Goal:** Build EdgeStash (`top.whatif.edgestash`) as an independent macOS
menu-bar app for stashing windows at logical display edges, including a display
arrangement map, real-display halo, and shared-edge seam beacon.

**Architecture:** AppKit-free rules live in `EdgeStashLogic`. The app target
contains the Accessibility session engine, overlays, Settings, and persistence.
Settings uses a four-page rail. The halo is Settings-only. Shared-edge
minimization uses a distinct seam beacon.

**Tech stack:** Swift 5.9, macOS 12+, AppKit, SwiftUI, Swift Package Manager,
and an Xcode macOS app target.

## Global constraints

- Product name EdgeStash; bundle identifier `top.whatif.edgestash`.
- This repository contains the independent EdgeStash implementation.
- No network, telemetry, update feed, screen capture, or window snapshots.
- Settings must not start Accessibility observers.
- The halo ignores mouse events and ends when Settings leaves Behavior or
  closes.
- A seam beacon must not slide the real window onto a neighboring display.
- Reduced motion uses immediate positioning or fades.
- Do not import external scaffolding, reference code, or checkers.
- Do not commit unless the owner asks.

## File map

```text
.
  Package.swift
  Sources/EdgeStashLogic/     AppKit-free policy
  Sources/EdgeStash/          macOS app
  Tests/                      EdgeStashLogicTests
  docs/contracts/
  docs/design/
  docs/plans/
```

## Completed tasks

### Task 1: Logic package

- [x] Display edge and shared-interval policies
- [x] Display arrangement and map-fitting policies
- [x] Session lifecycle, rescue, Dock, shortcut, merged strips, pin, and motion rules
- [x] Standalone logic verification executable

### Task 2: App identity shell

- [x] `Info.plist`, `main.swift`, AppDelegate, and menu bar
- [x] Bundle identifier `top.whatif.edgestash`
- [x] Original application icon
- [x] Debug build of `EdgeStash.xcodeproj`

### Task 3: Preferences and Settings rail

- [x] Machine-local Preferences writer
- [x] Apps, Behavior, System, and About pages
- [x] EdgeStash-only identity and privacy copy
- [x] Responsive Settings layout and theme

### Task 4: Session engine

- [x] `idle → captured → collapsed/expanded` policy and tests
- [x] Accessibility discovery and per-window sessions
- [x] Drag-to-edge capture, hover reveal, Dock restore, and shortcuts
- [x] Crash rescue and permission-loss handling

### Task 5: Outer marker and seam beacon

- [x] Exposed-edge slide-off marker
- [x] Shared-edge system-minimize beacon
- [x] Distinct visual presentation with reduced-motion support

### Task 6: Arrangement map and halo

- [x] Logical display arrangement map
- [x] Shared-segment visualization
- [x] Preview-only, mouse-transparent halo on the real display

### Task 7: Merged strip and pin

- [x] Overlapping same-edge markers merge into a segmented strip
- [x] Expanded stashes expose a pin control
- [x] Display-link slide animation with reduced-motion handling
- [x] Dock geometry and magnification-aware hit detection
- [x] Carbon app shortcuts with NSEvent fallback
- [x] Previous-app focus return
- [x] Optional effects disabled while strips are merged and under reduced motion

### Task 8: Launch, rescue, Spaces, and guidance

- [x] Conditional Settings launch based on Accessibility trust
- [x] Pending-rescue alert and recovery after permission returns
- [x] Space-change overlay rebuild and topology-change release
- [x] Multi-window guidance for applications with several collapsed windows

## Verification

- `swift run EdgeStashLogicTests`
- Debug build of `EdgeStash.xcodeproj`
- Owner review on a multi-display Mac was still required when this plan's
  tasks were checked off. Remaining presentation acceptance is the owner
  re-review row in `docs/contracts/edgestash.md`. This document is the
  first-version task record, not current execution authority.
