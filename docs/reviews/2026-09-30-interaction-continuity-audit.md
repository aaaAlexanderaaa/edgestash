# EdgeStash interaction continuity and edge-state review

Date: 2026-09-30. Baseline: `f28109a`; the working tree was clean at review start.
Authority: the current product, local-first, window-life, seam, glass-rail, and
behavior-grammar contracts. This follows the September 23 and September 29 reviews.
Source review, isolated event replays, and existing checks initially changed no
application code or contracts. The owner then requested repairs; their evidence
appears below. Findings and line numbers describe the pre-repair baseline.
This informative review is not an execution contract. Current rules live in
contracts. Translated from the original Chinese review under the English policy.

The main finding was that restoration and display memory already had substantial
guards, while pointer intent, merged rails, focus return, and input during
animation lacked shared arbitration. Eventual reveal success cannot establish
that hover was timely or a later click was honored. Identified paths could delay
reveal, undo explicit collapse, and interfere with the next operation's focus.
These warranted attention before changing animation duration.

## Evidence scope

- **Isolated reproduction:** compile the actual merge coordinator with real
  Foundation Timer, replacing window/painting adapters and avoiding cross-process
  AX. The collapse adapter completes immediately, exposing races in synchronous
  seam and Reduced Motion collapse; it does not prove identical slide timing.
- **Source confirmation:** establish entry points, guards, state, and call order.
  Actual system notifications and visible pixels were not measured.
- **Experience risk or unresolved rule:** describe permitted behavior, coverage
  gaps, and trade-offs without claiming reproduction on the owner's machine.

## Priority interaction defects

### Small pointer movement repeatedly delays merged hover

**Isolated reproduction, P1.** `StashMergeStripView.reportHover` reports the segment
ID on every `mouseMoved`. Even if unchanged, `StashMergeCoordinator.handleHover`
cancels the timer and waits the full `revealDelayMS` again. Dwell effectively
requires stillness rather than continuous presence in one target. The individual
rail's `beginHoverReveal` already had an idempotent pending-timer guard.

At the default 150ms, ten reports on one segment with approximately 40ms run-loop
intervals accumulated about 494ms without calling `mergeReveal`. After reports
stopped and another 200ms elapsed, one reveal occurred. This directly explains
sluggish merged rails and sensitivity to small pointer movement.

Repair: preserve a same-target deadline; cancel only on target change or exit.
Bind the timer to target and interaction generation and revalidate at delivery.
Add a timeline with continuous same-segment movement beyond dwell and one reveal.

Sources: `Sources/EdgeStash/Overlay/StashMergeCoordinator.swift:126`,
`Sources/EdgeStash/Overlay/StashMergeStrip.swift:172`, and
`Sources/EdgeStash/Engine/StashSessionWatch.swift:25`.

### An older hover timer can undo click-collapse

**Isolated reproduction, P1.** Merged `handleClick` did not cancel
`hoverTimers[key]`. `clickLocked` was checked only at timer creation; delivery
called `session.mergeReveal()` without checking the lock, current target, or
pressed mouse buttons.

Replay: begin expanded, schedule a 150ms hover, click-collapse after 30ms, complete
collapse immediately, then let the old timer reveal again. Synchronous seam and
Reduced Motion collapse allow this path. A normal 160ms merged slide may still
be busy when the timer fires, so the defect does not imply every hide mode rebounds.
Individual `handleMarkerClick` already cancelled its hover timer.

Repair: revoke hover before changing the click target; validate lock/generation
on delivery. Unify drag guards: positive-delay individual rails checked
`pressedMouseButtons == 0`, merged rails did not, and the zero-delay individual
path bypassed it. Passing an edge while dragging must not activate another window.

Sources: `StashMergeCoordinator.swift:139/144` and `StashSessionWatch.swift:25/54`.

### The previous collapse's focus callback can affect the next reveal

**Source-confirmed, P1.** After 300ms, `scheduleFocusRelease` checked only
`focusReleaseGeneration`. A new click/hover reveal did not increment it, and
`shutdown` did not invalidate it. September 29's foreground guard protected an
app switch, but reopening the same app's stash still satisfied
`frontmostPID == sourcePID`.

Sequence: successful collapse schedules return; another click/hover within 300ms
starts reveal; the old callback remains valid and can activate another app during
or after the new animation. Later `finishExpand` activates the subject again,
possibly producing two focus jumps. This path had not been tested with real AX.

Repair: assign focus work to an operation. New reveal, direct window interaction,
and session end invalidate old callbacks. Verify both operation and expected
phase rather than PID alone; test collapse followed by immediate reopen.

A separate owner decision concerned shortcut, show-all, and some Dock reveals
using `fromDock: true`, returning focus after 300ms even after clicking/typing in
the revealed app. Existing policy deliberately selected this behavior; a repair
could not silently remove it.

Sources: `StashSessionWatch.swift:147`, `StashSession.swift:744/985`, and
`Sources/EdgeStashLogic/ShortcutRuntimePolicy.swift:45`.

### Sibling-pointer detection ignores occlusion

**Isolated reproduction, P1.** `StashSurface.isPointerInSiblingWindow` scanned all
on-screen windows and accepted any same-PID sibling whose rectangle contained
the pointer. It did not determine the actual topmost pointer target. A browser
covering a Terminal sibling therefore counted as continued Terminal use. Each
100ms leave check refreshed `lastSiblingInteractionAt`, potentially retaining
an expanded stash indefinitely.

The metadata replay placed an unrelated window above a same-app sibling, both
covering the pointer. The original function with only its query replaced returned
`counts_as_inside = true`. This establishes the decision gap, not measured
WindowServer behavior.

Repair: identify the actual interactive topmost window, excluding covered,
invisible, stashed, and decorative windows. Preserve the accepted sibling grace
so the repair does not cause premature collapse between same-app windows.

Sources: `StashSurface.swift:62`, `StashSessionWatch.swift:273`, and
`Sources/EdgeStashLogic/LeaveCollapsePolicy.swift:18`.

### Input during animation can be discarded

**Source-confirmed, P2; target arbitration needed an accepted rule.** Both expand
and collapse returned while busy without preserving a target, queue, or reversal.
Rapid double-clicks, shortcuts, or switching from revealing A to merged segment B
could lose the later action. Merge arbitration considered only committed
`isExpanded`, excluding A while still revealing.

The missing element was operation targets and invalidation, not an unlimited
input queue. Prefer the last explicit click/shortcut target with at most one
pending target per session; define hover switching separately. Space/screen-set
changes retain cancellation priority over stale-coordinate work. Reversal versus
completion-then-replay is an experience choice requiring an accepted rule;
removing the busy guard alone is insufficient.

Sources: `StashSession.swift:633/750` and `StashMergeCoordinator.swift:59`.

## Remaining merged-surface and geometry gaps

| Issue | Evidence and experience impact | Proposed completion |
|---|---|---|
| Hover feedback did not update immediately | `handleHover` changed fields, but labels/highlights waited for `reconcile`. Isolated hover added zero `present` calls. Feedback could trail animation completion or the five-second sync. | Update presentation on target change without restarting dwell; clear labels immediately on exit. |
| Merging removed seam approach bands | Engine approach construction excluded `markerSuppressed`; merging suppressed all members. The 21pt panel lost the original 28pt inward + 12pt overshoot approach. `MergeMember` lacked hide type. | Define stable merged seam segments and target selection; extend the merge contract. |
| Labels enlarged the interactive panel | Resting width was 21pt, but `showingLabels` restored a 240–384pt window with `ignoresMouseEvents = false`. A nil view hitTest did not prove cross-process click-through. Replay confirmed 21 → 240pt. | Native click-through verification; keep a 21pt interactive panel and use a separate mouse-transparent label panel, matching the paint-only contract. |
| Merged rails lacked seam geometry | Uniform `edgeOverhang = 6` placed a left rail at desktop x `-2…3`, leaving 2pt outside its display; right was symmetric. The source could not distinguish outer from seam merge. | Define seam placement, density, and input; verify physical cross-display behavior without deleting intentional outer overhang. |
| Resize could leave saved geometry stale | Sessions observed moved/minimized/destroyed but not resized. Pin, merge, and marker geometry used `restoreFrame`; resize without moved left them stale. Later collapse reverted width changes of at most 15pt to `lockedWidth`. | Distinguish user resize from owned layout; update saved geometry and overlays without forcing old width. Test narrower/taller, pinned resize, scale, and zoom. |
| Recent-window tracking covered only some paths | `lastPreferredSession` changed on successful drag capture and `.openMostRecent`, excluding hover, merge, thumbnail, and shortcuts. Most-recent could select an older capture. | Define recent use versus recent capture and centralize updates; test capture A, capture B, use A, then Dock. |

Sources respectively: `StashMergeCoordinator.swift:74/126`, `StashEngine.swift:280`,
`MergeGroupPolicy.swift:209/262`, `StashMergeStrip.swift:42/91`,
`StashSessionWatch.swift:165/216`, `StashSession.swift:673`, and
`StashEngine.swift:437/730/836`.

## Responsiveness requiring measurement

Default outer hover included 150ms dwell plus 260ms reveal, approximately 410ms
before completion without queueing or AX cost. Continuous leave used a 220ms
threshold sampled every 100ms: approximately 300ms after the first outside sample,
plus 180ms slide, or roughly 480–580ms from crossing the buffer under ordinary
scheduling. The 60pt buffer and 1.5s sibling grace determine when timing starts.
These are source-derived budgets, not owner-machine measurements.

Potentially larger stalls came from the shared main thread: animator AX position
and size writes, leave frame/focus reads, five-second discovery, Dock queries,
and screen recovery. A slow subject app can delay other stashes' input and timers.
`maxWriteRate = 90` bounded each animator's position cadence; every third tick
also wrote size, and multiple animators had no global RPC budget. Final success
does not establish smooth intermediate frames. No AX messaging timeout was set.
The local `AXUIElement.h` exposes that API but does not justify guessing the
system's default wait duration.

Measure input-to-feedback, input-to-first-visible-frame, per-call AX time, long
main-thread tasks, and concurrent animator count using local timings or development
signposts under existing privacy rules. Then assess per-process serialized writes,
coalesced queries, and budgets. Shorter animations cannot repair lost input or
remove cross-process waits on the main thread.

## Unclosed findings from the preceding reviews

- **App shortcut semantics:** an idle window was captured first even with managed
  windows, conflicting with the accepted all-stashes rule. The owner needed to
  select precedence, followed by matching contract, copy, and implementation.
- **Show-all coverage:** Control-Up/Down existed; trackpad, dedicated Mission
  Control key, and Dock show-all remained unverified. A policy function alone
  did not connect native inputs.
- **Dock identity:** same-title `first` selection was ambiguous. If the app was
  already frontmost, thumbnail intent could not depend solely on application
  activation. Actual Dock event ordering remained open.
- **Activation source:** no recent Dock click meant Cmd-Tab, without independent
  evidence for notifications/file drops. Default leave-closed reduced risk, but
  opening all-stashed settings could act on an incorrect source.
- **Batch focus:** global `rememberedPID` could be overwritten. One consumable
  owned-activation marker per bundle did not prove classification for repeated
  interleaved same-bundle activations or activations without callbacks.
- **Partial seam changes:** refresh used whole-edge adjacency while hide used the
  window interval; nonintersecting windows could receive unnecessary frame writes.
- **Native boundaries:** Cmd-` skipping transparent windows, AX clamping, Space
  cancellation, fullscreen, clamshell wake, mirroring, and slow enumeration remained
  physical verification obligations.

## State ownership and recommended verification order

Keep one membership per window and the screen-set memory model while explicitly
assigning ownership to these layers:

| Layer | Required state or decision | Baseline deficiency |
|---|---|---|
| Interaction intent | Same-target dwell, explicit click/shortcut targets, no reveal during drag, exit rearming | Individual rails, approach, and merge owned different timers/locks. |
| Execution transaction | Operation ID, start/finish/cancel/failure, latest pending target, Space/screen cancellation priority | Phase plus busy could not retain the next intent. |
| Focus ownership | Which operation acquired focus, when return is valid, later input invalidation | Global PID and delayed session callbacks lacked shared ownership. |
| Actual use region | Topmost hit, sheets/menus/siblings, pin corridor, accepted resize geometry | Rectangle containment, stale `restoreFrame`, and PID were insufficient. |
| Overlay presentation | Outer/seam/merged/disabled, input region separate from paint-only labels | Merge lost hide type; hover could enlarge the real interactive panel. |

First repair defects already covered by accepted rules: stable same-target dwell,
click invalidation, stale focus work, immediate hover feedback, and covered-sibling
hits. Next define continuous click/shortcut targets, resize, merged seam approach,
and label click-through. Only then tune animation, AX scheduling, and grace from
measurements.

Minimum timelines: same-segment motion; A→B→A; held-button edge crossing; lingering
after click-collapse; reveal within 300ms of collapse; immediate click/typing after
reveal; a sibling covered by another app; clicks under labels; pure resize; two
shortcuts during reveal; Space change during seam preparation; and new intent
while the display environment is quiet. Check intent completion and stale-action
invalidation before final phase.

Sheets, system menus, open-file dialogs, drag/drop, secure input, run-loop tracking,
and slow app response also need native sequences. Missing combined evidence or a
dedicated enum alone does not prove incorrect implementation.

## Review-stage results

- All twelve presentation anchors were declared; one executable cardinality and
  eleven structural-only rows remained unchanged.
- Direct expectation checking could not complete because of the default 26.0
  SDK/compiler mismatch and restricted caches. The original script passed fully
  with the 15.5 SDK, temporary cache/scratch paths, and a temporary Swift wrapper
  adding `--disable-sandbox`. Repository scripts were unchanged.
- Isolated compilation and real Timer replays confirmed same-target delay, stale
  hover undoing click-collapse, and missing immediate feedback. Injected ordered
  metadata confirmed the sibling occlusion gap.
- `MergeGroupPolicy` replay confirmed the 21/240pt transition and rail overhang.
  No cross-process AX, real click-through, multi-display, owner perceptual, or
  app-target Debug verification was performed at this stage.
- Temporary replays were in `/private/tmp/edgestash-20260930-audit`; their window
  and drawing adapters were substitutes, not native end-to-end evidence. No new
  permissions, networking, capture, external code, or commit.

## Post-repair record

After owner authorization, the first two groups of definite interaction repairs
were implemented with product, window-life, glass-surface, and grammar updates.
Hide strategies and the existing Dock/shortcut focus-return choice stayed intact;
animation durations were not shortened to substitute for input repair.

| Issue | Repair | Evidence scope |
|---|---|---|
| Same-segment dwell restart and old-hover rebound | `HoverRevealCoordinator` preserves deadlines and invalidates tickets on target/click/drag; one reveal per visit. | Shared timelines plus the current native coordinator in isolated real-Timer replay. |
| Reveal at zero delay/while pressed, no mouse-up rearming | Both rail types check buttons; mouse-up re-evaluates; individual callbacks bind lifecycle. | Timelines and native entry review; real drag/drop remains open. |
| Old focus return affects newer action/input | `FocusReturnCoordinator` binds operation/phase; new action, pin, input, Space, screen-set, and end revoke callbacks and future scheduling rights. Schedule completed-operation work before coordinator notification. | Shared timelines and native wiring; cross-app timing remains open. |
| Covered sibling prevents collapse | Use front-to-back metadata and only the topmost visible layer-0 window; exclude zero alpha; remove a screen-size guess that rejected maximized documents. | Ordered metadata timelines; real WindowServer/sheet combinations remain open. |
| Animation loses a later target | `StashPresentationCoordinator` retains at most one newest target; toggle addresses target, not uncommitted phase. Replay after writes; clear on failure/environment/release; newer synchronous work wins. | Toggle, hundred-cycle merge, cancellation, and revision timelines; native AX animation remains open. |
| Delayed merge feedback and labels stealing clicks | Update on target change; interactive NSPanel always 21pt; separate mouse-transparent labels with coordinated hiding. | Coordinator replay and actual NSPanel properties/visibility; cross-app click-through remains open. |
| Merged seam loses approach, inset, and density | Retain hide type; derive approach segments from slots and use engine single-target selection; move seam group inside with 2pt inset, half tint, and inner gap. | Both-edge geometry and approach replay; physical pixels remain open. |
| Pure resize/small width changes are lost | Observe AXResized, accept settled gesture frame, update rescue/marker/merge/pin without redundant frame writes; remove 15pt fallback. | Full compile and wiring/write review; target-app resize remains open. |
| Recent-window selection misses actual use | Successful capture/expand and focused expanded-window use update recent selection; failed capture does not. | Native entry review and compilation; Dock identity remains limited below. |

Post-repair isolated replay in `/private/tmp/edgestash-20260930-fix` used the current
`StashMergeCoordinator.swift`, real Foundation Timer, and substituted sessions/overlays:

- About 492ms of same-segment movement revealed once within the default 150ms dwell;
  later movement did not reveal again.
- Hover while expanded, click-collapse after 30ms, then wait 200ms: still collapsed,
  zero reveal calls.
- A hover-target change immediately updated the drawing model and labels.
- Two merged seam members yielded two approach segments; selecting B revealed B once.

Actual AppKit surface replay compiled current merge-strip/glass source and created
only its own views/windows, avoiding external AX. After hover, the real rail was
21pt wide, labels 180pt wide, labels ignored mouse events, and rail could not become
key. Exit/orderOut hid labels. Optional pin glass used painted fallback on this
Mac; macOS 26 system glass was not exercised. Property checks do not establish
cross-app click-through or perceptual correctness.

Verification and delivery:

- Final expectation check passed: twelve anchors, one executable presentation
  cardinality, eleven structural-only. `Tests/InteractionContinuityTests.swift`
  was added to the existing executable suite without inflating coverage.
- Original staging scripts completed full CLT Debug/Release builds using the 15.5
  SDK and temporary caches to avoid the 26.0 mismatch. Repository build scripts
  were unchanged. Two existing notification-string cast warnings did not prevent
  matching; isolated four-notification replay routed moved/resized to geometry.
- Full Xcode was unavailable; CLT compilation did not close Xcode-project Debug.
- Release was staged at the three standard `dist` paths at
  `2026-09-30 09:12:03 +0800`. Signature, plist, ZIP, and whitespace checks passed.
  The owner was instructed to quit the running app before opening the staged app.

Still open at that time: shortcut capture/managed precedence; all native show-all
inputs; same-title Dock identity/order; activation source; the global focus-source
ledger; partial-adjacency refresh; Cmd-`, sheets/menus, Space/display/wake combined
sequences; slow AX and main-thread timing. Earlier evidence limits and owner
obligations remained. No new permissions, networking, content capture, external
code, or commit.

## Two repairs from independent review

The owner requested fixes for two combined-event defects confirmed by review:

- **Older merge preference undid a newer explicit reveal: repaired.**
  `MergeRevealSelection` owns unified selection. `onRevealRequested` notifies the
  engine for accepted immediate or queued requests. Dock, shortcut, and AX system
  unminimize use that entry point. Earlier queued replay uses
  `recordsRequest: false` and cannot overwrite a later window choice; pin priority
  retains its previous rule.
- **Mouse-up hover overwrote shortcut collapse: repaired.** `HoverRevealPolicy`
  checks phase and busy state both when native dwell is created and when delivered.
  Mouse-up cannot schedule another dwell after click starts reveal. A settled
  collapsed target still rearms normally after dragging.

Durable tests: `marker_mouse_up preserves explicit target invariants` and
`merge_reveal named entry point invariants` in `Tests/InteractionContinuityTests.swift`,
with matching product/grammar updates. These are interaction and combined-timeline
evidence, not promoted native presentation cardinality coverage.

Original review replays were rerun:

- `ReviewMouseUpFixed.swift` used actual marker methods, real Timer, and a 260ms
  busy reveal substitute. After shortcut, `desired_open=false` stayed false for
  200ms and pending collapse survived completion. Before the fix it became true
  and pending collapse disappeared.
- `ReviewPreferredFixed.swift` used the actual merge coordinator and substitute
  sessions. B revealed and left the rail, then explicit reveal A produced A
  expanded/B collapsed; previously the result was reversed.
- `ReviewRevealRequest.swift` used actual reveal/queue prologues, Dock/shortcut
  helpers, and pending replay, replacing AX execution/completion. All three named
  entries notified selection. Queued A replay after a B request emitted no second
  notification; B remained newest. The replay substitute initially omitted active
  request cleanup at completion; adding that missing adapter behavior resolved
  it. This was neither an app defect nor native AX end-to-end evidence.

The final expectation check passed again, as did full CLT Debug/Release staging.
Release was updated at **2026-09-30 11:35:16 +0800**, retaining the standard three
`dist` outputs. Signature, plist, ZIP, and whitespace checks passed. Full Xcode and
native multi-display review remained open. The owner was instructed to quit the
running app before opening the new app. No commit was made in that work.
