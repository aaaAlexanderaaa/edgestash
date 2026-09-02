---
doc_type: surface-contract
surface: logical-display-and-seam-beacon
status: current
authority: normative
implementation: implemented
verification_status: partial
last_reconciled: 2026-09-02
supersedes: []
---

# Logical display map and seam beacon — surface contract

## Purpose and user outcome

The person who already stashes windows on several displays needs to see
**logical** desktop geometry — the rectangles macOS uses, not the physical
bezels — and to tell what a given edge will do. On a shared seam, system
minimization hides the window and a distinct seam beacon remains as the
findable placeholder. That placeholder is not the same object as an outer
slide-off strip.

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

### raw[6] — 2026-08-30

> 当前的实现方案并不真正隐藏APP，而且我鼠标靠近的时候它也不会把对应的应用
> 展示好。我举一个例子，现在一个 APP 有10个窗口，我把鼠标放到了其中一个，
> 结果它直接把10个窗口全部叫出来了。我把鼠标放到那个接壤的边界，它的唤出
> 并不灵敏。但是真正的边界上就是灵敏的。

Context: the owner's perceptual review of the raw[5] trial on real displays.
The clipped slide leaves the window on the owning display at 2% alpha —
ghost-visible and still hit-testable — so the trial is concluded and shared
segments return to system minimization. The same review found hover reveal
activating the whole app stack and the seam beacon insensitive to gentle
approaches; both are corrected with it.

### raw[7] — 2026-08-30

> 我要求显示器锚定，而非 Space 锚定。

> 显示但禁用：用户能看到收纳仍存在，但点击时说明当前全屏 Space 无法展开。

Context: the owner requires a minimized seam stash to follow the owning
display's current ordinary user Space. The owner accepted a visible disabled
beacon for native full-screen and split-full-screen Spaces and approved the
cross-process migration experiment before implementation.

### raw[8] — 2026-08-30

> 接缝之间的收纳的确做到了窗口最小化，但是我只能通过快捷键呼出，而非鼠标
> 唤出（在第一次唤出之后，就见不到信号条了）。同 Space 去反复唤出，它很
> 明显就会失败：唤出后它收回去就再也没有办法唤出了。

Context: owner perceptual review of the first repeated seam cycle. Read-only
live inspection matched the vanished marker to a target session that had been
released to `idle`, with no edge, presentation, display binding, or rescue
record. The shortcut appeared to work because it recaptured an idle window;
it did not prove the original seam session survived.

## Translated layer

### Outcomes

- **O1 — Logical map.** Settings shows connected displays as a system-like
  arrangement of logical frames, including stagger and shared vs exposed
  vertical segments.
  - from: raw[1]
- **O2 — Edge halo.** Selecting a logical edge lights that edge on the
  real display, previewing slide-off, minimize, or disabled.
  - from: raw[1], raw[6]
- **O3 — Seam beacon.** A shared-edge stash keeps a visible placeholder wholly
  inside the owning display's seam. The stashed window itself is minimized by
  the system, so it truly leaves the screen; the beacon answers full-panel
  hover, click, and an engine-level approach band that tolerates gentle
  approaches and slight overshoot past the seam.
  - from: raw[2], raw[3], raw[6]
- **O4 — No extra product.** No third new surface in this version.
  - from: raw[4]
- **O5 — Display-anchored reveal.** A seam stash belongs to its owning
  display. On an ordinary user Space, EdgeStash migrates the still-minimized
  window into that display's current Space, verifies membership, and only then
  restores and activates the one target window. It never activates first and
  never navigates back to the capture Space on failure.
  - from: raw[7]
- **O6 — Truthful full-screen state.** On native full-screen or split-full-
  screen Spaces the beacon remains visible but disabled. Hover cannot start a
  reveal dwell; clicking explains why the stash cannot be expanded there.
  - from: raw[7]
- **O7 — Repeatable pointer lifecycle.** A successful reveal does not consume
  the stash. After leave-collapse or click-collapse, the same display-anchored
  beacon is visible and pointer-reachable again, for repeated cycles without a
  shortcut recapture.
  - from: raw[8]

### Reachable states

| State | Entry condition | Visible result | Available actions | Exit/error behavior |
|---|---|---|---|---|
| `map-empty` | no displays | existing “no display” copy | wait | n/a |
| `map-idle` | Behavior page, displays present | logical rectangles, shared segments marked | select a display or edge | n/a |
| `halo-preview` | an edge is selected in the map | halo on that real edge; map shows the same strategy | change selection; close Settings | halo ends when Settings closes or selection clears |
| `outer-strip` | window stashed on an exposed segment | current slide-off strip | hover / shortcut / named-stash activation in `docs/contracts/screen-set-and-window-life.md` | Dock app-icon click is not a reveal when the app has on-desktop windows |
| `seam-beacon-ready` | seam stash; owning display currently shows an ordinary user Space and the runtime transport is available | enabled beacon on the owning display; target stays minimized until migration is confirmed | approach band / hover / click / shortcut / named-stash activation in `docs/contracts/screen-set-and-window-life.md` starts one reveal transaction | successful reveal followed by re-collapse returns here with the same managed session; migration failure keeps the window minimized and disables the attempted reveal; beacon is gone only when the session genuinely ends |
| `seam-beacon-fullscreen-disabled` | owning display currently shows a native full-screen or split-full-screen Space | beacon remains visible with disabled treatment; target stays minimized | first encounter explains once; later clicks stay silent; hover does not dwell | returning to an ordinary user Space restores `seam-beacon-ready` after reconciliation |
| `seam-unavailable` | OS is older than macOS 26.4 or required runtime capabilities are absent | shared-seam capture is unavailable; no Space-anchored fallback is created | use an exposed outer edge | capability is re-evaluated at launch; existing recovery records remain recoverable |
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
| `restore-from-beacon` | enabled seam beacon | full-panel hover or approach-band dwell (same delay family as outer strip) | `seam-beacon-ready` | resolve owning display current Space; if ordinary, move while minimized when necessary; confirm membership; then deminimize, restore frame, and activate | any pre-confirmation failure is fail-closed; a Space change before commit cancels the transaction and re-minimizes an already deminiaturized window; never activate or switch to the capture Space |
| `repeat-seam-cycle` | revealed seam window | pointer leaves the interaction and sibling grace region, or marker click requests collapse | `expanded` and unpinned | minimize as the same managed session; restore the same display-anchored beacon and approach band | delayed AX notifications owned by the completed EdgeStash transaction cannot release the session |
| `explain-fullscreen-disabled` | disabled seam beacon | click, or a failed reveal | `seam-beacon-fullscreen-disabled` | the first time this limitation is encountered, show a one-time explanation in everyday language; later attempts stay silent | window remains minimized; no dwell, migration, or activation |

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
- abnormality[beacon-on-neighbor]: state=closed:2026-08-30; evidence=owner review raw[6] plus INV-6 rewrite; guard=shared segments always minimize, so no window ever slides toward a neighbor; description=Seam beacon must stay on the owning display and must not slide the real window onto the neighbor
- abnormality[reveal-old-space]: state=pending-owner:2026-09-26; evidence=logic-tested plus Debug build and accepted cross-process trial; guard=keep minimized, resolve owning display current ordinary Space, move if needed, confirm membership and unchanged display destination, then deminimize/activate; description=A seam reveal must never navigate back to its capture Space
- abnormality[first-reveal-consumes-session]: state=pending-live-e2e:2026-08-30; evidence=owner reproduction plus read-only live inspection; notification policy and 100-cycle logic guard passed with Debug/Release builds; guard=current AX value plus phase/ownership/in-flight classification; description=A successful seam reveal must not turn the managed session idle or remove its beacon before the next pointer reveal
- abnormality[space-change-after-demini]: state=pending-live-e2e:2026-08-30; evidence=deterministic code-path proof plus exact logic regressions and Debug build; guard=phase/current-AX cancellation policy re-minimizes a deminiaturized collapsed target and clears all transaction gates; description=A Space change after deminimization but before expand commit must not strand busy/restoring state or leave a visible window in a collapsed session

## Verification matrix

| State | Range/environment | Functional | Structural geometry | Brief/design direction | Perceptual | Accessibility | Independent review (high-risk only) |
|---|---|---|---|---|---|---|---|
| `map-idle` | 3-display stagger like the owner screenshot | pending | pending | pending | pending | pending | owner look |
| `halo-preview` | outer / partial / full share | pending | pending | pending | pending | pending | owner look |
| `seam-beacon-ready` | same-Space repeated cycles and cross-ordinary-Space reveal | display migration, repeated notification lifecycle, and post-deminimize Space cancellation logic-tested + Debug build | display id is durable anchor | accepted | failed on prior build; fixed build pending live E2E and owner re-look | enabled state compile-tested | owner re-look: repeated pointer reveal and no Space jump |
| `seam-beacon-fullscreen-disabled` | native full-screen / split-full-screen | type-4 refusal logic-tested + Debug build | beacon stays on owning display | accepted | pending | disabled state compile-tested | owner re-look: visible, no dwell, click explains |
| `reduce-motion` | system setting on | pending | pending | pending | pending | pending | owner look |

## Reconciliation log

- **2026-09-02 — Dock app-icon is no longer an unconditional reveal:**
  named-stash activation is owned by
  `docs/contracts/screen-set-and-window-life.md`. Rail, beacon, approach,
  and INV-6/9/10 are unchanged.

- **2026-08-30 — glass chrome accepted as target, not current:** the owner
  rejected the 2pt quiet beacon as unfindable and asked every desktop
  overlay to use a tinted-glass family. A same-day 10pt /
  `NSGlassEffectView`-on-rail choice was superseded: thickness is 5pt and
  thin rails paint. That visual replacement lives in
  `docs/design/glass-signal-and-repeatable-seam.md` (`status: target`).
  This document remains `current` for map, halo-as-preview, INV-6 inset,
  and interaction until that target is implemented. The 2pt / lower-contrast
  width row above is the present look, not the accepted future look.

- **2026-08-30 — post-deminimize Space cancellation reopened:** review proved
  an unguarded interval after AX deminimization and before the deferred expand
  commit. A Space change must cancel by transaction state, re-minimize if the
  collapsed window is already visible, and always remove the busy gate.
  The AppKit-free classifier, runtime re-minimize/visibility-release paths,
  exact logic cases, and Debug build landed the same day; implementation is
  again `implemented`, with live AX and owner review still open.

- **2026-08-30 — first repeated cycle failed:** raw[8] proves that one
  successful reveal is insufficient acceptance. The seam session must survive
  its own minimize/deminiaturize notifications and return to
  `seam-beacon-ready` after each collapse. Implementation is reopened until the
  notification guard, repeated-cycle logic tests, live AX E2E, and owner
  perceptual re-look land. The code guard, 100-cycle logic regression, and
  Debug/Release builds landed the same day, so implementation is again
  `implemented`; the live and perceptual evidence remains open.

- **2026-08-30 — display anchoring accepted:** raw[7] supersedes the
  “minimized is spaceless” assumption. The display id remains the durable
  session anchor; the capture Space is not a reveal destination. Every
  EdgeStash-controlled reveal is an ordered transaction: keep minimized,
  resolve the owning display's current ordinary user Space, move if needed,
  confirm membership, then deminimize/restore/focus. Native full-screen and
  split-full-screen keep a visible disabled beacon with click explanation.
  The runtime bridge, ordered reveal transaction, final unchanged-destination gate,
  disabled beacon, logic tests, and Debug build have landed, so this surface
  is again `current` / `implemented`. The owner perceptual rows stay pending.

- **2026-08-29 — target drafted:** translated raw[1]–[4]. Dual-strip
  language from the owner's choice (exposed = outer strip, shared = beacon).
- **2026-08-29 — code landed:** map, halo, and seam presentation compile;
  logic tests cover intervals, preview kind, and fitted slots. Interactive
  matrix still needs the owner on a multi-display Mac.
- **2026-08-29 — EdgeStash tree:** Behavior map, `ignoresMouseEvents` halo,
  outer strip, and seam beacon live in this repository. Halo clears when
  Settings leaves Behavior or the window closes. Owner look on a
  multi-display Mac is still required.
- **2026-08-29 — shared-edge trial (superseded 2026-08-30):** raw[5] tried a
  WindowServer-clipped slide for shared seams while displays have separate
  Spaces. That trial is not current. Minimization remains the shared-edge
  hide; the beacon stays inside the owning display.
- **2026-08-30 — trial concluded by owner review:** raw[6] rejects the
  clipped slide (not a true hide: ghost-visible, hit-testable, still listed
  on-screen). Shared segments return to system minimization unconditionally;
  the beacon gains full-panel hover and an engine-level approach band with
  overshoot tolerance. Hover reveal activates the app after the dwell (the
  owner's windows are always full-screen or edge-tiled, so a passive present
  would surface underneath the frontmost window). `seam-beacon` perceptual
  rows await the owner's re-look.
- **2026-08-30 — lifecycle corrected:** this surface describes current UI, so
  `status` is `current` and `implementation` is `implemented`. Verification
  stays `partial` because the matrix's perceptual rows are still pending.
  Purpose no longer names the discarded clipped-slide trial as a live
  option.
