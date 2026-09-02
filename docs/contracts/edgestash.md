---
doc_type: contract
status: current
authority: normative
implementation: implemented
verification_status: partial
last_reconciled: 2026-09-02
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
  edges and restores them through markers, hover, shortcuts, and the
  named-stash activation paths in
  `docs/contracts/screen-set-and-window-life.md`
- Per-application enablement, appearance, edge selection, and shortcuts
- Exposed-edge slide-off presentation; shared-edge segments use system
  minimization so a stashed window truly leaves the screen
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
| `collapsed-seam` | window reaches a shared edge segment | macOS minimizes the window so it truly leaves the screen; the seam beacon remains | reveal action | display-set events follow `docs/contracts/screen-set-and-window-life.md`; do not write a stale off-set frame |
| `collapsed-seam-disabled` | a seam stash's owning display is currently showing a native full-screen or split-full-screen Space | the minimized window stays hidden; its beacon remains visible but disabled | the first encounter explains once; later clicks stay silent; switch the display back to an ordinary user Space | never activate the subject app or pull the user to the stash's former Space |
| `expanded` | a named-stash action opens a stash (rail, beacon, shortcut, thumbnail, show-all, or the per-app all-stashed setting) | window sits on its owning edge | pointer leaves or user collapses | pinning suppresses automatic collapse |

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
  segments use system minimization so the window truly leaves the screen.
  The seam beacon stays wholly inside the owning display. A clipped
  slide-through is not a permitted hide: the window would remain on the
  owning display, ghost-visible and hit-testable, and sliding fully through
  the seam would flip WindowServer ownership to the neighbor.
- **INV-7 — reduced motion.** Reduced-motion mode avoids slide decoration and
  uses immediate positioning or fades.
- **INV-8 — recovery.** Rescue records are cleared only after the corresponding
  visibility and frame restoration succeeds, or after the window is known to
  be gone. Restart, quit, and crash do not restore stash membership; see
  INV-L9 in `docs/contracts/screen-set-and-window-life.md`.
- **INV-9 — display-anchored seam reveal.** A seam stash is anchored to its
  owning display, not to the Space on which it was captured. Before EdgeStash
  deminimizes or activates the subject app, it must resolve that display's
  current ordinary user Space, move the still-minimized window there when
  needed, and confirm membership. A failed, timed-out, or unsupported move is
  fail-closed: the window remains minimized and EdgeStash does not activate it.
- **INV-10 — repeatable seam lifecycle.** Minimize is the seam hide. An
  EdgeStash-owned or system minimize of a seam-presented session must not
  release it: collapsed stays collapsed, and an expanded seam window that
  miniaturizes recollapses and keeps its beacon. A 0.5s AX poll must not
  treat settle lag as a Dock reveal. A Space change must not dismiss a
  collapsed seam beacon. After any successful seam reveal and automatic or
  deliberate re-collapse, the same beacon remains reachable by pointer and
  may repeat the cycle without requiring a shortcut to recapture. A
  genuinely external minimize may still release an expanded *slide*
  session.

## Required behaviors

- Settings opens on launch only when Accessibility is unavailable; otherwise
  it is opened from the menu bar item or by reopening the app.
- Display-set events (increment, drop, return, cancel, scale, sleep, fresh)
  follow `docs/contracts/screen-set-and-window-life.md`. The former rule that
  a topology change releases a stash and writes the old frame back is
  superseded.
- The Behavior map and live engine use the same display-adjacency policy.
- The halo ignores mouse events and clears when Settings leaves Behavior or
  closes.
- Overlapping same-edge markers may fuse, and an expanded stash may be pinned.
- Hover reveals a stash only after the reveal-delay dwell, and the reveal
  activates its app: the dwell is the intent gate, and a true hide (minimized
  or offscreen siblings) keeps activation from flooding other stashes forward.
- Marker, strip, and pin panels stay above other apps' windows as permanent
  signals: main-menu level, visible on every Space including full-screen, and
  stationary through full-screen transitions.
- Marker hover and click accept the whole marker panel, and a collapsed seam
  beacon is additionally reachable through an approach band inside the owning
  display with a small overshoot tolerance across the seam, because a pointer
  cannot be slammed into a seam the way it is slammed into a bezel.
- On macOS versions where the tested display-Space transport is available,
  every EdgeStash-controlled seam reveal path (approach, beacon hover/click,
  shortcut, merged strip, that window's Dock thumbnail, show-all, and a
  per-app setting that opens stashes when every window is stashed) follows
  INV-9. A Dock app-icon click or Cmd-Tab that does not open a stash is not
  a reveal path. The ordinary macOS Dock window thumbnail remains
  system-owned for Space switching.
- The transport is enabled only on macOS 26.4 or later and only when all
  required runtime capabilities are present. Without it, shared-seam capture
  is disabled rather than silently reverting to Space-anchored minimization;
  exposed outer-edge slide stashes remain available.
- A native full-screen or split-full-screen Space is not a migration target.
  Its seam beacon is visibly disabled and cannot begin a hover dwell. The
  first time this limitation is encountered, a one-time explanation is
  shown; later clicks stay silent. Returning that display to an ordinary
  user Space re-enables the beacon after Space-change reconciliation.
- Same-Space seam interaction is repeatable: capture, pointer reveal, leave
  collapse, and pointer reveal again preserve one managed session and one
  reachable beacon across every completed cycle.
- Preferences remain machine-local.

## Failure, recovery, and intervention

- If Accessibility is lost, restore managed windows where possible, preserve
  unresolved rescue records, and suspend the live engine.
- If shared-edge minimization fails after positioning, restore the prior frame.
- If display-Space membership cannot be read, the destination is not an
  ordinary user Space, migration is rejected, or membership is not confirmed
  before the deadline, keep the subject window minimized and do not activate
  its application. Keep the beacon reachable in a disabled/error state.
- If the owning display changes Space after a reveal has deminiaturized the
  window but before the expand transaction commits, cancel the stale commit,
  re-minimize the window, and clear all reveal-in-flight blocking state. If
  re-minimization itself is rejected, take the visibility-restoring release
  path rather than retain a false collapsed or permanently busy state, and
  preserve the rescue record if visibility restoration also fails.
- If a display-set event changes whether an edge is exposed or shared,
  keep the window stashed on that display and that side when the event
  says to keep it, and choose slide versus minimize from the current
  adjacency. Do not write a stale off-set frame.
- If work expands past the first-version scope, stop and record a new owner
  request before implementation. Screen-set memory and activation-versus-
  stash are in first-version scope; their target is
  `docs/contracts/screen-set-and-window-life.md`.

## Acceptance evidence

| Outcome | Verification | Durable evidence |
|---|---|---|
| Independent EdgeStash identity | bundle and source review | `Sources/Info.plist`, this contract |
| Local-only capability boundary | forbidden-API search | `docs/contracts/local-first.md` |
| Geometry and lifecycle rules | logic executable | `swift run EdgeStashLogicTests` |
| Complete macOS target | Debug build | `EdgeStash.xcodeproj` |
| Display-anchored reveal transaction | logic executable plus Debug build | move/confirm/commit, full-screen refusal, and post-deminimize Space-cancellation guards passed 2026-08-30; owner multi-display review pending |
| Repeatable seam lifecycle | logic executable plus live AX E2E | notification classification and 100-cycle logic guard passed plus Debug/Release builds succeeded 2026-08-30; live AX E2E and owner re-review pending |
| Multi-display presentation | owner review on real displays | failed 2026-08-30; code corrected the same day; owner re-review still pending. Logic tests and a Debug build do not close this row. |

## Promise register

- promise[owner-multidisplay-rereview]: due=2026-09-26; status=open;
  owner=product-owner; description=Owner re-review on a multi-display Mac
  that a shared-edge stash truly hides, that hovering one of several
  stashes presents and activates exactly that window, and that a gentle
  seam approach reveals the beacon; additionally verify cross-Space reveal
  stays on the current display Space and native full-screen shows a disabled
  beacon with click explanation.
- promise[owner-screen-set-review]: due=2026-09-26; status=open;
  owner=product-owner; description=See
  `docs/contracts/screen-set-and-window-life.md`.

## Reconciliation log

- **2026-09-02 — screen-set life accepted as target:** everyday plug,
  unplug, sleep, and app activation are first-version acceptance, not
  later product. Topology-release and unconditional Dock reveal are
  superseded by `docs/contracts/screen-set-and-window-life.md`. Live
  code follows that target; owner multi-display review is still open.

- **2026-08-30 — seam durability and 5pt painted chrome:** the owner
  reproduced the vanished seam beacon again after several notification-
  classifier patches, judged 10pt too wide, and rejected thin-rail
  `NSGlassEffectView` as a gray box. INV-10 now forbids seam-session
  release on minimize, forbids poll-adopt during owned-minimize settle,
  and forbids Space-transition hide of a collapsed seam beacon. Chrome
  target is a 5pt painted plate; pin may still use system glass.

- **2026-08-30 — overlay chrome target accepted:** the owner asked every
  desktop signal (outer rail, seam rail, merge, pin, halo, flourish) to
  become one tinted-glass family. A same-day 10pt / `NSGlassEffectView`-
  on-rail choice was superseded after the first run (see the durability
  entry above). Hide strategy, INV-6/9, and the approach band do not
  change. The target surface is
  `docs/design/glass-signal-and-repeatable-seam.md`.

- **2026-08-30 — Space-change cancellation race reopened:** code review proved
  that a Space change between shared-window deminimization and the deferred
  expand commit invalidates the commit while the old cancellation guard can
  leave `busy` and `restoringShared` permanently set. INV-9 already requires a
  fail-closed transaction, so implementation is reopened for a phase/current-
  AX-state cancellation policy, re-minimize recovery, and regression tests.
  The policy, runtime compensation/fallback, exact logic cases, and Debug build
  landed the same day, returning `implementation` to `implemented` while live
  AX and owner repeated-Space-switch review remain pending.

- **2026-08-30 — repeated seam lifecycle reopened:** the owner reproduced a
  same-Space seam stash that reveals once, collapses, then loses its beacon and
  can only be recaptured by shortcut. Read-only live inspection found the
  target session had fallen from managed state to `idle`; its marker was
  ordered out and its display binding and rescue record were cleared. This
  violates INV-10 and reopens implementation for a notification-ownership
  guard, logic regression tests, and a live AX E2E.
  The code guard, 100-cycle logic regression, and Debug/Release builds landed
  the same day, returning `implementation` to `implemented`; verification
  remains `partial` until the live AX E2E and owner seam re-look pass.

- **2026-08-30 — accepted display-anchored seam target:** the owner rejected
  Space anchoring after reproducing a seam stash that could be revealed only
  by shortcut and that pulled the display back to the capture Space. Seam
  sessions now target the owning display's current ordinary user Space. A
  reveal transaction is move-while-minimized, confirm membership, then
  deminimize/restore/focus; activation is forbidden before confirmation.
  Native full-screen and split-full-screen Spaces keep a visible but disabled
  beacon whose click explains the limitation. The cross-process transport was
  accepted after a disposable cross-process migration trial. The runtime
  bridge, move/confirm/commit transaction, disabled beacon, logic guards, and
  Debug build landed the same day, returning this contract to `current` /
  `implemented`. Verification remains `partial`: owner perceptual review is
  still required.

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
- **2026-08-29 — conditional shared-edge slide (superseded 2026-08-30):** a
  WindowServer-clipped slide was tried for shared segments when displays have
  separate Spaces. That trial is not current behavior. See the 2026-08-30
  entries below.
- **2026-08-30 — owner perceptual review failed; clipped-slide trial
  discarded:** the owner's multi-display review rejected the clipped slide as
  not a true hide (ghost-visible, hit-testable, still listed on-screen),
  found hover reveal flooding the whole app forward through
  `activateIgnoringOtherApps`, and found the seam beacon insensitive to the
  gentle approaches a seam requires. Shared segments return to system
  minimization (INV-6). A collapsed seam beacon is reachable through
  full-panel hit testing plus an engine-level approach band with overshoot
  tolerance. A same-day present-without-activate hover trial was also
  discarded the same day (see the following hover entry). Verified at the
  logic and Debug-build layer; owner re-review on real displays is still
  pending.
- **2026-08-30 — reference hardening:** after comparing against the SideBar
  reference implementation, the owner approved four alignments: a singleton
  marker click-collapse lock with click-toggle semantics, removal of the
  marker fade-out/present race, a leave-collapse dwell (0.22s continuous
  outside) with same-app sibling grace (pointer over a sibling, focused
  sibling, or 1.5s post-interaction all count as inside), and a 0.7s
  Space-change settle before markers rebuild with per-Space visibility
  (slide-stash markers only on the owning Space; minimized seam beacons
  everywhere). Verified by `swift run EdgeStashLogicTests`, a Debug build,
  and a Bugbot pass. Those checks do not replace owner perceptual review.
- **2026-08-30 — hover reveal activates; markers are permanent signals:** the
  owner's windows are always full-screen or edge-tiled, so a
  present-without-activate reveal would surface underneath the frontmost
  app's window and be invisible at the exact moment it matters. Current
  hover behavior is: reveal after the reveal-delay dwell, and activate the
  app. Marker, strip, and pin panels use `stationary` so the stash signal
  stays on top through full-screen transitions. The activation flood from
  the owner's review stays structurally impossible while stashes are truly
  hidden (minimized or offscreen) and no reveal path cascades from mere app
  activation.
