---
doc_type: contract
status: current
authority: normative
implementation: complete
verification_status: compile-tested
last_reconciled: 2026-08-29
supersedes: []
---

# EdgeStash

## Purpose

Define EdgeStash as an independent macOS product and lock the scope of its
first version: preserve the implemented window-stashing behavior, include the
logical display map, edge halo, and seam beacon, and defer later product ideas.

## Product identity and ownership

- Product name: EdgeStash
- Bundle identifier: `top.whatif.edgestash`
- Product root: this git repository
- Source and visual assets: independently implemented for EdgeStash
- Publication terms: owned by this project and recorded in `LICENSE` when the
  owner selects the license

## Scope

### In scope

- A macOS menu-bar app that stashes selected application windows at display
  edges and restores them through markers, hover, shortcuts, or Dock activity
- Per-application enablement, appearance, edge selection, and shortcuts
- Exposed-edge slide-off presentation plus conditional shared-edge slide-off:
  WindowServer per-display clipping when displays have separate Spaces, with
  system minimization as the shared-desktop fallback
- Logical display arrangement map and real-display edge halo
- Shared-edge seam beacon
- Merged strips, pinning, focus return, launch-at-login, Spaces handling, and
  crash rescue
- Four Settings pages: Apps, Behavior, System, and About

### Out of scope

- Network access, telemetry, update feeds, screen capture, or window snapshots
- Rearranging displays from inside EdgeStash
- Features beyond the implemented first-version surface
- Importing external project scaffolding or policy checkers

## Architecture

- `Sources/EdgeStashLogic` owns AppKit-free geometry, state, lifecycle, Dock,
  shortcut, merged-strip, pin, and rescue policies.
- `Sources/EdgeStash/Engine` owns Accessibility discovery and live window
  sessions.
- `Sources/EdgeStash/Overlay` owns markers, halo, merged strips, pin, and transient
  effects.
- `Sources/EdgeStash/Preferences` owns persisted local settings.
- `Sources/EdgeStash/Settings` owns the SwiftUI configuration surface.
- `Tests/EdgeStashLogicTests.swift` verifies the policy layer as a standalone
  executable.

## States and triggers

| State | Entry trigger | Visible result | Exit trigger | Failure behavior |
|---|---|---|---|---|
| `untrusted` | Accessibility is unavailable | Settings remains usable; no window control | permission becomes available | do not start observers |
| `idle` | trusted engine sees an eligible window | window remains unmanaged | edge capture | no mutation |
| `collapsed-outer` | window reaches an exposed edge segment | window slides offscreen; outer marker remains | reveal action | restore the saved frame |
| `collapsed-seam` | window reaches a shared edge segment | with separate display Spaces the window slides behind the owning-display clip; otherwise macOS minimizes it; seam beacon remains | reveal action | restore rather than retain a stale strategy after display/Spaces changes |
| `expanded` | marker, shortcut, or Dock reveals a stash | window sits on its owning edge | pointer leaves or user collapses | pinning suppresses automatic collapse |

## Normative invariants

- **INV-1 — identity.** The app name is EdgeStash and the bundle identifier is
  `top.whatif.edgestash`.
- **INV-2 — independent implementation.** Product source, tests, documentation,
  and visual assets in this repository are the EdgeStash implementation.
- **INV-3 — version lock.** The first version contains the behavior already in
  this repository plus the logical arrangement/halo and seam-beacon surfaces.
- **INV-4 — local first.** The app does not use network, telemetry, screen
  capture, or window-content snapshot APIs.
- **INV-5 — permission boundary.** Settings does not start Accessibility
  observers. The engine starts only after trust is already present.
- **INV-6 — geometry safety.** Exposed segments slide offscreen. Shared
  segments use a distinct display-clipped slide only while
  `NSScreen.screensHaveSeparateSpaces` is true, otherwise they use system
  minimization. Their beacon stays wholly inside the owning display.
- **INV-7 — reduced motion.** Reduced-motion mode avoids slide decoration and
  uses immediate positioning or fades.
- **INV-8 — recovery.** Rescue records are cleared only after the corresponding
  visibility and frame restoration succeeds, or after the window is known to
  be gone.

## Required behaviors

- Settings opens on launch only when Accessibility is unavailable; otherwise
  it is opened from the menu bar item or by reopening the app.
- Display topology changes release stashes whose presentation strategy is no
  longer valid.
- The Behavior map and live engine use the same display-adjacency policy and
  the same current separate-Spaces input.
- The halo ignores mouse events and clears when Settings leaves Behavior or
  closes.
- Overlapping same-edge markers may fuse, and an expanded stash may be pinned.
- Preferences remain machine-local.

## Failure, recovery, and intervention

- If Accessibility is lost, restore managed windows where possible, preserve
  unresolved rescue records, and suspend the live engine.
- If shared-edge minimization fails after positioning, restore the prior frame.
- If display topology or the effective separate-Spaces mode changes the
  presentation kind, release the stash instead of reusing stale hidden geometry.
- If a topology change invalidates a stash, restore it instead of preserving a
  stale offscreen state.
- If work expands past the first-version scope, stop and record a new owner
  request before implementation.

## Acceptance evidence

| Outcome | Verification | Durable evidence |
|---|---|---|
| Independent EdgeStash identity | bundle and source review | `Sources/Info.plist`, this contract |
| Local-only capability boundary | forbidden-API search | `docs/contracts/local-first.md` |
| Geometry and lifecycle rules | logic executable | `swift run EdgeStashLogicTests` |
| Complete macOS target | Debug build | `EdgeStash.xcodeproj` |
| Multi-display presentation | owner review on real displays | pending perceptual review |

## Reconciliation log

- **2026-08-29 — first version implemented:** identity shell, Settings rail,
  live engine, markers, logical map, halo, seam beacon, merged strips, pin, rescue,
  Spaces handling, and original app icon compile in the independent product
  repository.
- **2026-08-29 — ownership corrected:** the contract records EdgeStash as
  an independent implementation whose publication license belongs to this
  project.
- **2026-08-29 — parameters re-derived:** every tunable (rescue matching,
  Dock hit depth, merged-strip geometry and overload rule, pin control, rescue
  offsets, hover defaults, slider, panel sizing, palette, keys, data shapes,
  and product copy) follows a recorded rationale — system geometry, HIG
  metrics, or proportional rules — documented in source comments at each
  definition site.
- **2026-08-29 — persistence shape:** settings persist as a single versioned
  JSON document under Application Support with EdgeStash's own field names,
  no flat key map, and no compatibility readers; stale defaults entries from
  pre-release builds are swept at launch by prefix.
- **2026-08-29 — motion and geometry derivations:** the slide uses one
  symmetric quintic easing, an AX write budget of one write per refresh tick
  under a hard ceiling, a stall allowance for blocked writes capped at a
  fraction of the duration, and error-triggered size locks. The Dock hit
  corridor is assembled from measurements — the depth macOS reserves plus the
  Dock window's server-reported extent — and the Dock side itself is detected
  from the gap between full and usable frames. Geometry constants derive from
  EdgeStash's marker metrics (capture band, edge lip, composited panel bleed),
  and the expand/collapse flourish is a gradient beam and ripple ring with no
  particle emitter. Verified by `swift run EdgeStashLogicTests` and a clean
  typecheck of the app target.
- **2026-08-29 — controls and schemas re-derived:** the Settings tuning
  control is a continuous stepped track (4pt capsule on the half-grid, 16pt
  HIG-minimum thumb, stop grid anchored at the range's lower bound, no
  per-step marks) replacing the former ruler control; note popovers render
  from one uniform width owned by `SettingsSurfacePolicy.notePopoverWidth`;
  accessory-app text-chord routing installs a table-driven main menu with
  untitled entries; the slide animator carries motion in one immutable
  `Slide` value and keeps only pacing state, with spans, easing, budgets, and
  stall refunds owned by `StashMotionPolicy`; rescue records persist as
  grouped dossiers (`subject`, `placement`, `landing`) over a single
  `StoredGeometry` point-or-rect type, moving the store document to version 3
  where an undecodable document starts the reader fresh — still no
  compatibility readers. Verified by `swift run EdgeStashLogicTests` and a
  Debug build of the app target.
- **2026-08-29 — conditional shared-edge slide:** shared segments now use a
  separately modeled WindowServer-clipped slide whenever
  `NSScreen.screensHaveSeparateSpaces` is true. The shared-desktop path keeps
  system minimization, topology reconciliation distinguishes the two slide
  presentations, and the seam beacon remains inside its owning display.
