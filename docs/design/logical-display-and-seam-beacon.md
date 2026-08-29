---
doc_type: surface-contract
surface: logical-display-and-seam-beacon
status: target
authority: normative
implementation: complete
contract_scope: future-ui
verification_status: compile-tested
last_reconciled: 2026-08-29
supersedes: []
---

# Logical display map and seam beacon — surface contract

## Purpose and user outcome

The person who already stashes windows on several displays needs to see
**logical** desktop geometry — the rectangles macOS uses, not the physical
bezels — and to tell what a given edge will do. On a shared seam, either a
display-clipped slide or its minimization fallback must still leave a findable
placeholder. That placeholder is not the same object as an outer slide-off
strip.

## Raw layer

### raw[1] — 2026-08-29

> 像系统一样展示显示器排列，来帮助用户评估到底哪部分是重叠部分，因为显示器
> 物理大小和在系统上被逻辑识别出来的大小是不一致的；同时增加一个逻辑区块的
> 辅助操作，直接在指定显示上通过边缘光晕来展示不同位置的处理方式

Context: owner attached the macOS 「排列显示器」 screenshot (three staggered
logical rectangles, menu bar on the primary).

### raw[2] — 2026-08-29

> 在接壤部分的通过最小化实现的边界收纳，需要同样有那个贴边的条的占位，否则
> 根本不知道还有什么东西被收纳了

Context: shared-edge minimize currently loses a trustworthy desktop marker.

### raw[3] — 2026-08-29

Owner chose dual language: exposed segments keep a real slide-off strip;
shared segments use a distinct, quieter seam beacon. A seam beacon must not
slide the real window onto the neighboring display.

### raw[4] — 2026-08-29

> 其他的后续的功能，除了我刚才声明的要做的两点以外，我们后续再做。

Context: these two items are the only new surfaces in this version.

### raw[5] — 2026-08-29

> 开启「显示器具有单独的空间」时，先利用 macOS 在显示器接缝处的按屏裁剪，
> 实现一个不依赖最小化的版本；关闭时仍需要安全回退。

Context: owner observed that manually parked cross-display windows are clipped
to the owning display and requested an implementation trial before retaining
minimization as the only shared-edge behavior.

## Translated layer

### Outcomes

- **O1 — Logical map.** Settings shows connected displays as a system-like
  arrangement of logical frames, including stagger and shared vs exposed
  vertical segments.
  - from: raw[1]
- **O2 — Edge halo.** Selecting a logical edge lights that edge on the
  real display, previewing slide-off, display-clipped slide, minimize, or
  disabled according to the current Spaces configuration.
  - from: raw[1], raw[5]
- **O3 — Seam beacon.** A shared-edge stash keeps a visible placeholder wholly
  inside the owning display's seam. With separate display Spaces the real
  window slides behind WindowServer's per-display clip; without them it uses
  system minimization.
  - from: raw[2], raw[3], raw[5]
- **O4 — No extra product.** No third new surface in this version.
  - from: raw[4]

### Reachable states

| State | Entry condition | Visible result | Available actions | Exit/error behavior |
|---|---|---|---|---|
| `map-empty` | no displays | existing “no display” copy | wait | n/a |
| `map-idle` | Behavior page, displays present | logical rectangles, shared segments marked | select a display or edge | n/a |
| `halo-preview` | an edge is selected in the map | halo on that real edge; map shows the same strategy | change selection; close Settings | halo ends when Settings closes or selection clears |
| `outer-strip` | window stashed on an exposed segment | current slide-off strip | hover / shortcut / Dock | unchanged current behavior |
| `seam-beacon` | window stashed on a shared segment | quieter beacon on the seam; target window is clipped-slide or minimized according to separate-Spaces state | hover / shortcut / Dock restores | strategy changes release the stash; beacon is gone when session ends |
| `reduce-motion` | system reduce motion | halo and beacon fade only; no slide decoration | same | n/a |

- from: raw[1], raw[2], raw[3]

### Layout and size contract

| Element/region | Width contract | Height contract | Overflow/scroll owner | Conditions |
|---|---|---|---|---|
| `arrangement-map` | page content width | scales logical frames to fit; preserves aspect and relative origin | page scroll if needed | `map-idle`, `halo-preview` |
| `logical-display` | proportional to `NSScreen.frame` | proportional to `NSScreen.frame` | none | map |
| `shared-segment-mark` | edge thickness on the map | length of the shared Y interval | none | partial or full share |
| `edge-halo` | thin band on the real display edge | length of the selected logical edge | none | `halo-preview` only |
| `seam-beacon` | thinner / lower contrast than outer strip | window's shared-segment span | none | `seam-beacon` |

- from: raw[1], raw[3]

The map uses **logical** `NSScreen.frame` (and the same adjacency math as
`DisplayEdgePolicy`). It does not draw physical inch sizes.

### Interaction map

| ID | Stable handle | Trigger/input | Precondition | Expected state delta | Focus/scroll result |
|---|---|---|---|---|---|
| `select-display` | logical rectangle | click | `map-idle` | that display selected | map stays put |
| `select-edge` | left/right edge of a rectangle | click | map visible | `halo-preview` for that edge | halo on the real screen |
| `clear-preview` | Settings close or deselect | click / close | `halo-preview` | halo removed | n/a |
| `restore-from-beacon` | seam beacon | hover (same delay family as outer strip) | `seam-beacon` | deminimize / expand | existing session rules |

- from: raw[1], raw[2], raw[3]

Existing left/right enable toggles stay. The map is the spatial explanation
and preview; it does not replace the persisted per-display edge preferences.

### Design direction and content

- Subject: logical multi-display geometry and stash strategy.
- Thesis: the map is the system arrangement view with stash semantics
  overlaid; the halo is a teaching light, not a third strip.
- Anchors: macOS 「排列显示器」, primary menu-bar mark, staggered frames,
  `DisplayEdgePolicy` outer / partially shared / fully shared.
- Rejected: dragging displays to rearrange (that is System Settings);
  making the seam beacon look identical to the outer strip; putting the
  only shared-edge affordance inside the map with nothing on the desktop.
- Vocabulary: 逻辑排列 / 接壤区段 / 外侧条 / 接缝信标 / 光晕预览.
- Reduced motion: 120ms fade; no slide on halo or beacon.
- Halo exists only while Settings is open and an edge is selected.
- from: raw[1], raw[3]

### Style and theming contract

- Style layer: `SettingsTheme` for the map chrome; beacon/halo consume
  published tokens (`rail` and a quieter sibling if one is added).
- Do not restate `#FC850C` at the call site.
- Light and dark.
- from: raw[1]

### Accessibility and input

- Map rectangles expose display name, main-display, and edge strategy.
- Halo is visual preview; strategy text stays on the map.
- Beacon is a control: name the stashed app; reduced-motion fade only.
- from: raw[1], raw[2]

### Responsive and browser support

| Container/viewport band | Layout state | Navigation/interaction changes | Required engines/inputs |
|---|---|---|---|
| settings page width ≥ 700 | map beside or above existing edge toggles | none | macOS 12+ AppKit + SwiftUI |
| settings page width < 700 | map stacks above toggles | same | same |
| one display | map shows a single frame; no shared marks | halo still works | same |

- from: raw[1]

This is not a web surface.

## Activated quality attributes

| Concern | Normative owner | Boundary/failure policy | Surface evidence |
|---|---|---|---|
| Privacy | `docs/contracts/local-first.md` | halo is an overlay, not a screenshot | no capture APIs |
| Version scope | `docs/contracts/edgestash.md` | only these two additions | plan review |
| Geometry truth | `DisplayEdgePolicy` | map and halo use the same adjacency | `EdgeStashLogicTests` plus map review |

## Known abnormality classes

- abnormality[halo-vs-strip]: state=pending; evidence=pending:2026-09-26; guard=pending; description=Halo must not be mistaken for an outer strip or a seam beacon
- abnormality[beacon-on-neighbor]: state=pending; evidence=pending:2026-09-26; guard=pending; description=Seam beacon must stay on the owning display and must not slide the real window onto the neighbor

## Verification matrix

| State | Range/environment | Functional | Structural geometry | Brief/design direction | Perceptual | Accessibility | Independent review (high-risk only) |
|---|---|---|---|---|---|---|---|
| `map-idle` | 3-display stagger like the owner screenshot | pending | pending | pending | pending | pending | owner look |
| `halo-preview` | outer / partial / full share | pending | pending | pending | pending | pending | owner look |
| `seam-beacon` | shared-edge clipped slide / minimize fallback | logic-tested | pending | complete | pending | pending | owner look |
| `reduce-motion` | system setting on | pending | pending | pending | pending | pending | owner look |

## Reconciliation log

- **2026-08-29 — target drafted:** translated raw[1]–[4]. Dual-strip
  language from the owner's choice (exposed = outer strip, shared = beacon).
- **2026-08-29 — code landed:** map, halo, and seam presentation compile;
  logic tests cover intervals, preview kind, and fitted slots. Interactive
  matrix still needs the owner on a multi-display Mac.
- **2026-08-29 — EdgeStash tree:** Behavior map, `ignoresMouseEvents` halo,
  outer strip, and seam beacon live in this repository. Halo clears when
  Settings leaves Behavior or the window closes. Owner look on a
  multi-display Mac is still required.
- **2026-08-29 — shared-edge trial:** raw[5] adds a WindowServer-clipped slide
  for shared seams while displays have separate Spaces. The minimization path
  remains the fallback for a shared desktop, and both continue to use the
  inside-only seam beacon.
