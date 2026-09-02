---
doc_type: contract
status: target
authority: normative
implementation: implemented
verification_status: partial
last_reconciled: 2026-09-02
supersedes_clauses_of: docs/contracts/edgestash.md
---

# Screen sets and the life of a stashed window

## Purpose

Lock how a stashed window lives through ordinary Mac use: switching
apps, mixed on-desktop and stashed windows of the same app, sleep,
restart, and changing which displays are connected.

This target supersedes the first-version rules that treated a display
topology change as “release the stash and write the old frame back”,
and that treated a Dock app-icon click as a stash reveal. Hide
strategy (INV-6), display-anchored seam reveal (INV-9), and repeatable
seam lifecycle (INV-10) stay. Chrome stays in
`docs/design/glass-signal-and-repeatable-seam.md`.

## Product vocabulary

These words are the only ones this contract uses for the new model.
Do not invent others in later docs.

| Term | Meaning |
|---|---|
| **standard window** | An Accessibility standard window (document, Terminal, browser). Dialogs, settings panels, and floating palettes are not candidates. |
| **screen set** | The connected display identities plus their **relative** arrangement. A global origin shift that leaves who-is-left-of-whom unchanged is the same screen set. |
| **configured screen set** | EdgeStash has a remembered stash placement for that exact screen set: at least one standard window was stashed while that set was current, and that memory was not cancelled. |
| **stash placement** | Which standard windows were stashed on which display’s which edge in that screen set. |
| **on-desktop** | The window’s frame sits on an existing display’s desktop. Covered by another window still counts as on-desktop. |
| **stashed** | EdgeStash is managing the window on a display edge. Collapsed, temporarily open on the edge, and pinned are appearances of stashed, not other states. |
| **leave stash** | The window becomes an ordinary on-desktop window. It is no longer stashed. |
| **displaced** | The window left stash onto remaining displays because its owning display vanished and the remaining screen set is not configured. EdgeStash remembers the original edge so the window can return there when that display returns. |
| **scatter** | When two or more windows become on-desktop in one event, each receives a distinct origin. Stacking at one point is forbidden. |

A seam stash’s product location is **that display’s edge**, not the Dock.
The yellow traffic-light minimize is the Dock. The two stay distinct.

## Raw layer

### raw[1] — 2026-09-01

> 假如我有三个窗口，现在我用三个显示器，然后这三个窗口分别在三个显示器的不同的侧边隐藏，收纳。然后我因为要开会，我把显示器全部拔掉了，出去了。然后我又调了一次布局。等我坐回去的时候，我重新连回我三个显示器。结果布局又全部混乱掉了。然后我又要开一次会。我刚刚离开电脑的时候，我刚刚刚拔掉显示器的时候，好不容易配好的配置，拔掉显示器又全部乱掉了。

> 我拔掉显示器后，隐藏在侧边的东西，它不会弹回正中间，如果它没有被当前这一个屏幕布局所处理的话。

Context: three displays, three stashed windows; unplug for a meeting;
rearrange on the laptop; plug the three back; then unplug again. Both
placements were destroyed. A window whose owning display is gone stayed
at stale coordinates instead of becoming usable on a remaining display.

### raw[2] — 2026-09-01

> Terminal 开了5个窗口，有两个被收纳，有三个在台前。但是可能会被一些其他的应用给遮挡。我点击的时候，会把那几个收纳的也触发起来。这不应该，我只想要看到那三个本来在，就在台前，只是被遮挡，不在最前面的被显示出来，而不是触发一下那两个被收纳的窗口又弹出来。

Context: clicking the app (Dock) must raise on-desktop windows and must
not open stashed siblings.

### raw[3] — 2026-09-01

> 它表现出了一个现象，就是你在做这些所谓的用力或者考虑的时候，你没有考虑用户的正常使用场景。

Context: display-set changes and app activation are normal use, not
edge cases. Acceptance is everyday desktop life, not only the capture →
reveal cycle.

### raw[4] — 2026-09-02

Owner choices while defining windows, operations, and screen sets
(plain-language options; not implementation):

- Only standard windows can be stashed.
- Three-display and laptop-only are two screen sets. Returning to a
  set restores that set’s stash placement.
- A vanished display’s windows first become usable on remaining
  displays; when the original set returns they go back to the original
  edges.
- Adding a display without changing the relative arrangement of the
  displays already present is an increment: the new display is empty
  and existing windows are not touched. Removing that added display
  affects only windows on it.
- Going from three displays to two, the other two unmoved: if the
  two-display set is already configured, switch to it; if not, the
  missing display’s windows leave stash, scatter on the remaining two,
  and return to the original edges when the third display returns.
  Stashes on the remaining displays stay.
- Rearranging displays in System Settings cancels that screen set’s
  configuration. Every stashed window leaves stash and scatters on the
  desktop.
- Mirroring is the same cancel.
- Resolution or scale change alone keeps each stash on the same
  display and the same side.
- Sleep, including closing the lid to sleep while externals stay
  connected, does not move or open stashes. Wake, lid open or still
  closed, keeps the pre-sleep placement.
- Closing or opening the lid while remaining awake is the same class
  as unplugging or replugging one display.
- Restart, quit, and crash do not restore stash membership.
- Dock app icon when some windows are on-desktop: raise those; do not
  open stashed windows.
- Dock app icon when every window of that app is stashed: a per-app
  setting; default is bring the app forward and leave stashes closed.
- System “show all windows”: stashed windows count, and they all open.
- The app’s stash shortcut addresses every stashed window of that app.
- Clicking that window’s own Dock thumbnail opens that one stash.
- Cmd-` skips stashed windows.
- Cmd-H leaves stashes closed; showing the app again does not open them.
- Yellow minimize and stash are different. Yellow follows the system
  when the person clicks the app; stashes follow this contract.
- Drag back to the desktop, close the window, or turn off that app’s
  stash switch: the window is no longer stashed. Moving it to the
  other edge is still stashed.
- System-menu move to another still-connected display: still stashed,
  same side of the destination display.
- Full-screening a window that is temporarily open on an edge: leave
  stash; it becomes an ordinary full-screen window.
- Pinned windows follow the same screen-set and activation rules as
  other stashed windows.
- Whenever many windows become on-desktop in one event, scatter them.

## Translated layer

### Outcomes

- **O1 — Screen-set memory.** Each configured screen set keeps its own
  stash placement. Returning to a configured set restores that
  placement. The product does not remember ordinary on-desktop stacking
  of unstashed windows.
  - from: raw[1], raw[4]
- **O2 — Usable when the current set cannot host the edge.** A window
  whose owning display is gone does not stay at stale coordinates. It
  becomes an on-desktop window on a remaining display, scattered if
  several move at once, until a later rule returns it to an edge.
  - from: raw[1], raw[4]
- **O3 — Increment is quiet.** Adding a display that does not change
  the relative arrangement of the displays already present does not
  move existing windows or stashes. The new display starts empty.
  - from: raw[4]
- **O4 — Clicking the app is not opening a stash.** On-desktop windows
  of that app, including covered ones, come forward. Stashed windows
  stay stashed unless a rule below names them.
  - from: raw[2], raw[4]
- **O5 — Everyday desktop life is in scope.** Sleep, lid, plug, unplug,
  meeting-room projection, Cmd-Tab, Dock, Mission Control, and mixed
  on-desktop/stashed windows of one app are acceptance scenes, not
  afterthoughts.
  - from: raw[3]

### What a window is

A live window is exactly one value from each layer. The layers do not
overlap.

**Kind.** Standard window (stash candidate), other app window (not a
candidate), or not an app window (system UI, EdgeStash rails).

**Identity.** Each standard window is distinct. After close, quit,
crash, or restart, a later window is a new identity and does not
inherit stash membership.

**Location.** Exactly one of: on-desktop on an existing display; left
or right edge of an existing display; in the Dock because the person
used yellow minimize; not on any existing display (owning display gone
and not yet settled, or the window is closed).

**State.** Exactly one of: unstashed, or stashed. Covered-by-another-
window is z-order, not a state. Full screen, application hide, and
yellow minimize remain system states and stay distinct from stashed.

### What an operation is

An operation changes exactly one of those layers, or the environment
around an unchanged window.

| Family | Operations |
|---|---|
| Birth or death | New window; close; quit app; crash; restart the Mac |
| Move | Drag on the desktop; move to another display; move to another Space; snap to an edge; drag back from an edge; move to the other edge |
| System state | Yellow minimize; hide application; full screen; zoom |
| Stash state | Capture; open; pin; turn off that app’s stash switch |
| Front | Click this window; click the app (Dock or Cmd-Tab); show all windows; click that window’s thumbnail; stash shortcut |
| Environment | Plug or unplug; System Settings arrangement; sleep; restart; resolution or scale; projection or mirror; lid while awake |

### Screen-set events

Classify a display change as exactly one event. Relative arrangement
is who-is-left-of-whom, not the global origin.

| Event | When | Windows |
|---|---|---|
| `sleep` | System sleep, including lid-close-to-sleep while externals stay connected. Brief topology blips during sleep and wake are this event, not unplug. | No stash opens. No stash leaves. Wake, lid open or still closed, keeps the pre-sleep placement. |
| `increment` | One or more displays appear, and the relative arrangement of the displays that were already present is unchanged. | Existing stashes and on-desktop windows stay. The new display is empty. |
| `drop-configured` | One or more displays disappear, and the remaining connected set plus arrangement is already a configured screen set. | Switch to that remaining set’s stash placement. Keep the departed set’s placement so it can return. |
| `drop-unconfigured` | One or more displays disappear, the remaining relative arrangement is unchanged, and the remaining set is not configured. | Stashes on remaining displays stay. Windows whose owning display is gone leave stash, scatter on remaining displays, and are displaced until those displays return, at which they go back to the original edges. |
| `return-configured` | Connected displays again match a configured screen set (including the set left by `drop-configured`). | Restore that set’s stash placement. Displaced windows that belong to this set return to their edges. |
| `cancel` | The person rearranges the same displays in System Settings, or turns mirroring on or off. | That screen set’s configuration is discarded. Every stashed window leaves stash and scatters on existing displays. |
| `scale` | Resolution or scale changes; the screen set is otherwise the same. | Each stash stays on the same display and the same side. |
| `fresh` | The Mac restarts, or the subject app quits or crashes. | Do not restore stash membership. If a window would be off an existing display, scatter it on an existing display. |
| `lid-awake` | Lid closes or opens while the Mac stays awake. | Same class as `drop-*` / `increment` / `return-configured` for the built-in display. |

Pinned windows follow the same row as other stashed windows.

Lid-close-to-sleep is `sleep`, not `lid-awake`.

### Who may open a stash

| Action | Object | Opens a stash? |
|---|---|---|
| Hover or click the outer rail or seam beacon, or dwell in the seam approach band | That stashed window | Yes, that one |
| The app’s stash shortcut | Every stashed window of that app | Yes, all of that app’s stashes |
| Dock app icon or Cmd-Tab, and the app has at least one on-desktop window | The app’s on-desktop windows | No |
| Dock app icon or Cmd-Tab, and every window of that app is stashed | The app | No by default. Per-app setting may choose: still no; open the most recent stash; open stashes on the display the pointer is on; open all. Default is still no. |
| Click an on-desktop window of that app | That window | No |
| Click that window’s own Dock thumbnail | That window | Yes, that one |
| System “show all windows” (including a Dock / Mission Control all-windows presentation) | Every window of that app | Yes, every stash of that app opens |
| Cmd-` | On-desktop windows of that app | No. Stashed windows are not stops |
| Cmd-H, then show the app again | The application | No |
| Yellow minimize or its Dock restore | That yellow-minimized window | Follows the system. Does not open stashes |
| File drop on the Dock icon, or a notification for that app | The app or that file | No |

An EdgeStash-controlled open of a seam stash still follows INV-9. A
Dock app-icon click that does not open a stash must not run a seam
reveal transaction and must not activate the app a second time.

### How a window stops being stashed

The window is no longer stashed when the person drags it back onto the
desktop, closes it, or turns off that app’s stash switch.

Moving it to the other edge of the same display, or to the same side of
another still-connected display through the system menu, stays stashed.

Full-screening a window that is temporarily open on an edge leaves
stash. Exiting full screen does not put it back on the edge.

## Normative invariants

- **INV-L1 — one window, one membership.** Stash membership is per
  standard window, not per application.
- **INV-L2 — two values only.** Product location gained “this display’s
  left or right edge”. Product state gained “stashed”. They do not
  replace on-desktop, yellow-minimize, hide, or full screen.
- **INV-L3 — do not hand over an unnamed stash.** Opening a stash
  requires an action in the table above that says yes. Clicking the
  app is not that action unless a per-app all-stashed setting says so,
  or the person used show-all, a thumbnail, a rail, a beacon, or the
  stash shortcut.
- **INV-L4 — do not keep a stale off-set frame.** A window must not
  remain at coordinates that belong to a display that is not
  connected, except during `sleep`.
- **INV-L5 — screen sets are distinct.** A configured three-display set
  and a configured laptop-only set are two memories. Returning to
  either restores that memory. They are not one placement scaled down.
- **INV-L6 — increment does not rewrite the present.** An `increment`
  event does not move, open, or leave existing stashes.
- **INV-L7 — cancel discards that set only.** A `cancel` event discards
  the current screen set’s stash placement and puts every stashed
  window on-desktop, scattered. It does not invent a new edge.
- **INV-L8 — scatter.** Any event that puts two or more windows
  on-desktop at once assigns distinct origins.
- **INV-L9 — fresh day.** Restart, quit, and crash do not restore
  stash membership. They may still place a window onto an existing
  display so it is not lost off-screen.
- **INV-L10 — sleep is not unplug.** `sleep` is not classified as
  `drop-*`, `cancel`, or `fresh`.

## Required behaviors

- Persist stash placement per configured screen set, locally, in the
  existing preferences document family. Do not add network or capture
  APIs.
- Persist the per-app setting for “Dock / Cmd-Tab when every window is
  stashed”, defaulting to leave stashes closed.
- After `return-configured`, stashes sit on the remembered display
  edges. Presentation (slide versus minimize) is decided from the
  **current** adjacency, not from the remembered presentation kind.
- After `drop-unconfigured`, displaced windows are ordinary on-desktop
  windows until `return-configured` puts them back on the remembered
  edges.
- After `cancel` or `fresh`, there is no automatic return to an edge.
- A resolution-only change does not cancel a screen set and does not
  leave stash.
- Pin does not create a second screen-set policy.

## Failure, recovery, and intervention

- If a display change cannot be classified, prefer INV-L4 (usable on
  an existing display, scattered) over writing a stale frame. Do not
  open stashes as a recovery tactic.
- If restoring a configured set cannot place a window on its
  remembered display because that display is still missing, treat that
  window as displaced.
- If scatter cannot find a distinct origin, use the next unused origin
  on the same display; never reuse the last origin.
- INV-8 in `docs/contracts/edgestash.md` still clears a live rescue
  record after a successful on-desktop placement. It must not
  re-stash a window after `fresh`.

## Acceptance evidence

| Outcome | Verification | Durable evidence |
|---|---|---|
| Screen-set classification | logic executable | increment, drop-configured, drop-unconfigured, return-configured, cancel, scale, sleep, recover, settle/sleep-hold |
| Activation does not open unnamed stashes | logic executable plus Debug build | Dock / Cmd-Tab with mixed on-desktop and stashed windows; default all-stashed setting |
| Show-all opens every stash of that app | logic executable plus Debug build | owner scene: five Terminal windows, two stashed |
| Vanished display becomes usable | logic executable plus owner review | no stale off-set frames; scatter; return to edges when the set returns |
| Sleep versus lid-awake | owner review on a clamshell Mac | lid-sleep does not move stashes; lid-awake follows drop/increment |
| First-version topology-release and Dock-reveal rows | removed or pointed here | this contract |

Owner perceptual review on a multi-display Mac closes the usable-when-
gone and mixed-window activation rows. Logic tests and a Debug build
do not.

## Promise register

- promise[owner-screen-set-review]: due=2026-09-26; status=open;
  owner=product-owner; description=Owner review that three-display and
  laptop-only placements survive unplug/replug, that a vanished
  display’s windows appear usable and scatter, that clicking Terminal
  with mixed on-desktop and stashed windows does not open the stashes,
  and that lid-sleep does not move stashes.

## Reconciliation log

- **2026-09-02 — wake, settle, and owned-reveal guard:** topology
  changes wait until the fingerprint is quiet before classifying.
  Sleep freezes the committed set; a settle timer that fires after a
  wall-clock jump is sleep, not drop. Display-only sleep is not system
  sleep, so lid-awake can still classify.   Wake onto a
  subset of the pre-sleep set waits, then keeps the pre-sleep placement
  without switching to a remembered laptop layout. A shrink with scrambled remaining
  frames is drop, not cancel. Same-ID relation scramble without
  System Settings is not cancel. Hardware mirroring still cancels.
  System window-moved notifications defer leave-stash so a following
  screen-parameter change can claim the move. A rail, beacon, or
  shortcut activate is `ownedReveal` and does not open sibling
  stashes. Control-Down opens every stash of the frontmost app;
  Control-Up opens every stash of every managed app. A Dock item whose
  title is a window title opens that stash. Trackpad Mission Control
  and the Mission Control key are still not a detected path.

- **2026-09-02 — implementation landed:** screen-set classify, per-set
  placement memory, sleep vs unplug, Dock/Cmd-Tab activation, and
  Apps-page all-stashed Dock setting are in the app. Logic tests pass.
  Owner multi-display review is still required.

- **2026-09-02 — target accepted from owner choices:** everyday display
  and activation life is in first-version scope. Topology-release and
  unconditional Dock reveal in `docs/contracts/edgestash.md` are
  superseded by this document. Implementation has not started.
