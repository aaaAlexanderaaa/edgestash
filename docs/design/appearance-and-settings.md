---
doc_type: surface-contract
status: target
authority: normative
implementation: implemented
verification_status: partial
last_reconciled: 2026-10-16
supersedes_visual_clauses_of: docs/design/glass-signal-and-repeatable-seam.md
---

# Appearance and a list/detail settings editor

The owner accepted the interactive list/detail study and its material/motion
direction on 2026-10-16. This target replaces the glass-only visual clauses;
the existing window, screen-set, Space, permission, and recovery contracts stay
authoritative. The study is a design reference, not native verification.

## Settings and persistence

Apps has a compact searchable application list and a stable detail editor.
Selecting an app does not enable it. Switching its enable toggle does not
reorder the list under the pointer. Empty/search states remain reachable.
The detail editor groups stash behavior, appearance, and a local preview.
Disabled apps can be configured before enabling. Other settings pages retain
their existing actions. Chinese and English expose the same choices.

Material, emphasis color, and exposed-edge window motion are separate per-app
preferences. Materials are Glass (existing translucent plate), Enamel (dense
color with a fine rim), Glow (soft luminous center), and Prism (a restrained
chromatic reflection around the chosen base color). Motion choices are Slide,
Nudge (18pt outward movement with fade), and Fade (stationary opacity).
Missing/unknown stored material or motion keeps the legacy Glass/Slide behavior.
A newly created profile starts with Enamel/Nudge. Editing another field must
preserve these preferences and every existing shortcut/Dock setting.

The preview paints the same material recipe and samples the same motion plan
as desktop chrome. It acts only on its own miniature; it cannot stash or move
another app. It runs once per explicit replay, never continuously. System
Reduce Motion gives an immediate window transition and suppresses decoration.

## Desktop appearance

All materials retain the accepted 5pt visible rail, panel/hit geometry, seam
inset, quieter seam density, clear inner gap, disabled-seam semantics, pin
actions, and narrow merge hit window. Each merged segment uses its app's
material. Pin and the bounded reveal/collapse sheen follow that material.
The Behavior map's context-free halo remains neutral Glass.

Idle chrome is static. Pointer presence may brighten the local rail without
changing hover intent, timers, or dwell. A reveal/collapse can produce one
bounded sheen in the existing overlay; merged transitions, reduced motion,
and disabled effects suppress it. No new overlay, idle clock, capture API,
network dependency, or permission is introduced. Non-Glass materials paint;
only the Glass pin may use the existing runtime-gated system glass view.

## Presentation boundary

AppKit-free appearance types and an immutable presentation plan live in
EdgeStashLogic. AppKit drawing lives in Sources/EdgeStash/Appearance. The
existing StashAnimator executes the plan; StashSession alone owns phase,
activation, queued intent, screen ownership, minimization, and recovery.

Slide retains its full physical path. Nudge/Fade only change the presentation
of an exposed-edge transition: revealing hides before repositioning near the
expanded frame; collapsing fades before parking at the same physical hidden
destination. Hidden alpha remains exactly zero. A checked final frame and
opacity are required before success. Any failed write uses existing failure
recovery; cancellation never commits a phase. Without an identified window
for opacity writes, use Slide. Reduce Motion keeps the immediate path.
Shared seams still use system minimization and the existing confirmed Space
transport; their window motion is not replaced by these choices.

## Acceptance

- Headless evidence covers physical endpoints, monotonic opacity, reduced
  motion, fallback, hide-before-reposition ordering, and failed-write rejection.
- The expectation check must retain all declared presentation anchors and
  cardinalities. Local preview adds no presentation window.
- A native build and isolated native painter/settings review verify layout
  and rendering. Full Xcode Debug validation is separately required when the
  toolchain is available.
- Owner review remains necessary for 5pt perceptual quality, actual foreign
  window transitions, and multi-display/Space cycles. Passing the headless
  suite is not that review.

## Delivery evidence — 2026-10-16

- `./scripts/check-expectations.sh` passed: all 12 existing presentation
  anchors remain declared; one cardinality is executable and eleven remain
  structural-only. The new appearance-plan suite passed alongside the existing
  state, interaction, screen-set, and observation suites.
- Debug and Release native builds passed using `./scripts/stage-app.sh` with
  Apple Command Line Tools. The Xcode project parses and includes the new
  sources, but full Xcode is absent; its separate Debug build gate stays open.
- A disposable native probe rendered the actual Apps page in Chinese/English,
  light/dark, at 720/920pt widths and 640/960pt heights. The narrow grid wraps
  without clipping; app identity, style, motion, preview, and secondary behavior
  hierarchy were inspected. This is offscreen app-owned rendering, not capture
  of another app or live interaction/AX evidence.
- The same probe used an isolated JSON store to verify decoding an old profile,
  retaining legacy Glass/Slide, preserving shortcut/edge/Dock fields while
  changing color or enablement, independent material/motion edits, round-trip
  persistence, and configuring a disabled new profile. It did not start the AX
  engine or write to any foreign window.
- Owner perceptual review, live foreign-window failure/cancellation behavior,
  and multi-display/Space review remain open. No claim of zero regression in
  those environments follows from these checks.
