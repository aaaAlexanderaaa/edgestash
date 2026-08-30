---
doc_type: surface-contract
surface: glass-signal-and-repeatable-seam
status: target
authority: normative
implementation: in_progress
verification_status: pending
last_reconciled: 2026-08-30
supersedes_visual_clauses_of: docs/design/logical-display-and-seam-beacon.md
---

# Tinted glass signals and a surviving seam session — target surface

## Purpose and user outcome

The person who stashes windows needs a desktop signal that is easy to find,
reads as current macOS chrome, and does not vanish after the first seam
reveal. Shared-edge hide stays system minimization. The placeholder stays a
display-anchored control. What changes is the chrome: one 5-point tinted
glass family for every desktop overlay, with seam and outer still readable
as two densities of the same object.

This target does not replace INV-6, INV-9, or INV-10. It replaces the
current surface's "thinner / quieter 2-point beacon" visual clauses once
implemented.

## Raw layer

### raw[1] — 2026-08-30

> 我是在那个接缝的地方的信号条不见了，但是我外侧的条都是可见的。

Context: after a seam reveal and re-collapse the seam placeholder is gone;
exposed-edge strips remain. This is the INV-10 session-drop, not a default
hide.

### raw[2] — 2026-08-30

> 我可以允许接缝的信标和外侧条一样的宽，5PT也可以，10PT都可以。我觉得现在
> 的信号条所有都太丑了。它不像 Mac OS 那么的现代优雅，也不像 Mac OS 26一样
> 有透明玻璃质感的视觉效果。

Context: the owner accepted a shared 10-point thickness and asked every
visible desktop signal to use macOS 26 glass language.

### raw[3] — 2026-08-30

Owner choices during design:

- Do the lifecycle repair and the chrome change in one delivery.
- Restyle every desktop overlay: outer strip, seam beacon, merge strip, pin
  control, Settings halo, expand/collapse flourish.
- Same glass family, still distinguishable: outer denser and edge-hugging;
  seam same width, quieter, with an inner gap.
- Thin rails cannot host `NSGlassEffectView`: at 5–10pt it reads as a gray
  slab. Rails and the Settings halo paint a layered tinted plate. The 28pt
  pin disc may embed system Liquid Glass when the class resolves. Do not use
  `NSVisualEffectView`.
- Visible thickness is 5pt for both rails.
- The whole rail is washed with the app strip color, not filled as a slab.

## Translated layer

### Outcomes

- **O1 — Surviving seam session.** Capture → pointer or marker reveal →
  leave or click collapse → the same managed session and a visible,
  pointer-reachable seam rail remain. A shortcut must not be required to
  recapture.
  - from: raw[1]
- **O2 — One glass family.** Outer rail, seam rail, merge track, pin disc,
  Settings halo, and the expand/collapse sheen share one tinted-glass
  language.
  - from: raw[2], raw[3]
- **O3 — Readable distinction.** Outer and seam are the same 5pt capsule.
  Outer uses full tint wash and may peek the bezel. Seam uses about half
  wash plus a 1pt inner gap, stays wholly inside the owning display, and
  keeps 2pt of glass inset from the seam.
  - from: raw[3]
- **O4 — Painted rails; system glass only where it has area.** Rails, merge
  chips, and the halo paint a translucent plate + tint wash + specular.
  The 28pt pin disc may use `NSGlassEffectView` on macOS 26. Do not fall
  back to `NSVisualEffectView`.
  - from: raw[3]
- **O5 — Truthful halo.** The Settings halo is a 5pt preview of the two
  densities (full vs half-tint + gap). It remains a teaching light, not a
  third stash.
  - from: raw[3]

### Reachable states

Current interaction states in
`docs/design/logical-display-and-seam-beacon.md` stay. This target adds
chrome states only:

| State | Entry condition | Visible result | Available actions | Exit/error behavior |
|---|---|---|---|---|
| `glass-system` | pin disc on macOS 26 when `NSGlassEffectView` resolves | live Liquid Glass on the 28pt disc | same pin actions | if the class is missing, paint the disc |
| `glass-painted` | rails, halo, merge chips; or any surface without the class | layered tinted plate of the same size | same | never fall back to `NSVisualEffectView` or to the 2pt beacon |
| `outer-rail` | exposed-edge stash | 5pt full-wash capsule; 1pt on-screen clearance | hover / click / shortcut / Dock | unchanged collapse/reveal |
| `seam-rail` | shared-edge stash, session managed | 5pt half-wash capsule + 1pt inner gap; 2pt inset from the seam | approach band / hover / click | session drop is a defect, not a chrome state |
| `merge-rail` | two or more overlapping same-edge markers | 5pt tinted-glass segments | segment hover / click | suppressed individual rails stay hidden |
| `pin-glass` | expanded unpinned or pinned stash | 28pt tinted-glass disc | toggle pin | existing pin policy |
| `halo-preview-glass` | Behavior map edge selected | 5pt preview of outer or seam density | none (ignores mouse) | clears when Settings leaves Behavior |
| `flourish-sheen` | unmerged expand or collapse | short sheen along the 5pt rail | none | skipped when merged, reduced motion, or effects disabled |

- from: raw[2], raw[3]

### Layout and size contract

| Element/region | Width contract | Height contract | Overflow/scroll owner | Conditions |
|---|---|---|---|---|
| `glass-rail` | 5pt visible capsule; corner radius 2.5pt | stashed window height plus existing panel bleed | none | `outer-rail`, `seam-rail` |
| `outer-panel` | 11pt (5pt glass + 3pt transparent margin each side) | rail height | none | outer; panel may peek the bezel so the glass keeps 1pt on-screen clearance |
| `seam-panel` | 9pt, flush inside the owning display | rail height | none | seam; glass starts 2pt inside the seam |
| `seam-inner-gap` | 1pt clear along the long axis | most of the capsule height | none | seam and minimize halo only |
| `merge-track` | 5pt (`MergeGroupPolicy.trackWidth`) | union of member spans | none | `merge-rail` |
| `pin-disc` | 28pt (HIG small control) | 28pt | none | `pin-glass` |
| `edge-halo` | 5pt | selected logical edge length | none | `halo-preview-glass` |
| `approach-band` | unchanged: 28pt inside + 12pt overshoot | window span plus panel bleed | none | collapsed seam only |

- from: raw[3]

The approach band and full-panel hit testing do not shrink to the 5pt
capsule. The capsule is the visible affordance; the panel and band remain
the hit geometry.

### Interaction map

Interaction IDs in the current surface stay (`restore-from-beacon`,
`repeat-seam-cycle`, halo select/clear, pin, merge segment hover/click).
This target does not add a new trigger. It requires `repeat-seam-cycle` to
leave a visible `seam-rail` in `glass-painted` (or `glass-system` on the pin).

### Design direction and content

- Subject: desktop stash chrome on current macOS.
- Thesis: one tinted-glass rail family; density and an inner gap tell seam
  from outer; hide strategy does not change.
- Anchors: painted translucent plate + specular + app-color wash; INV-6
  inset; `NSGlassEffectView` only on the 28pt pin disc.
- Rejected: 2pt quiet beacon as the findable signal; `NSVisualEffectView`;
  `NSGlassEffectView` on a 5–10pt rail (reads as a gray slab); making seam
  and outer identical objects; using glass on Settings pages; capturing
  pixels to fake glass.
- Vocabulary: 玻璃轨 / 外侧密度 / 接缝密度 / 内侧缝.
- Reduced motion: 120ms fade on rails and halo; no flourish sheen.
- from: raw[2], raw[3]

### Style and theming contract

- App strip color is a wash over a translucent plate, not an opaque fill.
- Outer density uses the color at full wash strength.
- Seam density uses about half that strength plus the 1pt inner gap.
- Disabled seam keeps the plate, further quiets the wash, and keeps the
  existing first-time explanation. Hover still cannot start a dwell.
- Do not restate a hex at the call site.
- Light and dark follow the painted plate; the pin disc follows system
  glass when present.
- from: raw[3]

### Accessibility and input

- Each rail remains a named control: the stashed app.
- Pin remains a toggle.
- Halo stays visual-only; strategy copy stays on the map.
- from: raw[2]

## Architecture

- `EdgeStashLogic` owns thickness, panel frames, seam inset, inner-gap
  geometry, minimize-poll settle, Space-transition hide, and notification
  classification.
- `Sources/EdgeStash` owns one glass-rail host. Rails and halo always
  paint. The pin disc embeds `NSGlassEffectView` when the class resolves.
- Overlay panels stay clear, nonactivating, main-menu level, join-all-
  Spaces, stationary.
- Pin, halo, and merge consume the same host. The flourish stays a
  short-lived overlay and only paints a sheen.
- Delivery is one plan with two tracks: INV-10 must be re-proved live
  (the workspace classifier is not accepted evidence). Chrome work follows
  so the surviving seam session has a 5pt rail to show.

## Failure, recovery, and intervention

- If `NSGlassEffectView` is absent, paint the pin disc. Do not use
  `NSVisualEffectView`. Do not revert to 2pt.
- Thin rails stay painted even when the system class exists. Owner
  review rejected `NSGlassEffectView` on a 10pt rail as a gray box.
- If a seam session releases after a completed EdgeStash cycle, that is an
  INV-10 defect. Chrome must not hide it.
- Glass sampling is the system compositor. Product code must not call
  screen-capture or window-content snapshot APIs.

## Acceptance evidence

| Outcome | Verification | Durable evidence |
|---|---|---|
| 5pt frames and seam inset | logic executable | `StashGeometryPolicy` / merge track cases |
| Notification classification, poll settle, and 100-cycle model | logic executable | keep green; includes poll-then-late-minimize |
| Repeatable live seam cycle | live AX E2E | capture → reveal → collapse → visible rail → second reveal |
| Painted rails; pin may use system glass | Debug build on the owner's Mac | thin-rail path paints; pin disc is runtime-gated |
| Chrome reads as one family, seam ≠ outer | owner perceptual review | 5pt tinted glass; inner gap readable; merge / pin / halo / sheen |
| True hide still true | owner perceptual review | minimized seam window leaves the screen |

## Promise register

- promise[glass-and-repeat-cycle]: due=2026-09-26; status=open;
  owner=product-owner; description=On a multi-display Mac running the
  delivery build: a seam stash survives reveal→collapse with a visible
  5pt glass rail; outer rails use the same family at full wash; merge,
  pin, halo, and sheen match; system minimization still hides the window.

## Reconciliation log

- **2026-08-30 — owner rejected 10pt gray-box glass:** after running the
  first glass build, the owner found the seam rail still vanished after
  one appearance, judged 10pt too wide, and rejected `NSGlassEffectView`
  on the thin rail as a cheap gray box. Thickness returns to 5pt. Rails
  paint a layered plate. Minimize of a seam session cannot release it;
  the 0.5s unminimized poll cannot adopt during settle; Space change
  cannot hide a collapsed seam beacon for the rebuild delay.

- **2026-08-30 — target accepted in conversation:** owner confirmed the
  missing seam signal is the post-reveal session drop, allowed a shared
  10pt width, and chose system Liquid Glass on macOS 26 with a painted
  fallback, tinted by app color, same-family distinction, and every
  desktop overlay in scope. The same-day run superseded the 10pt /
  system-glass-on-rail clauses.
