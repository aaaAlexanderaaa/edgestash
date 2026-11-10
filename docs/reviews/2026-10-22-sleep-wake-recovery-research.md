---
doc_type: investigation
status: implemented_pending_owner_review
authority: informative
implementation: implemented
verification_status: partial
last_reconciled: 2026-10-22
---

# Lost stashes after wake: investigation and next-release scope

The owner confirmed a separate macOS 27 Mac with three displays. After display
power-off or sleep/wake, windows returned to the desktop and edge rails vanished.
App shortcuts recaptured one window at a time; apps without shortcuts required
manual recapture. No display-layout change was intentional. Testing needed a
Release delivery. This is an English translation of the original investigation;
quoted owner requests are translated and historical evidence remains historical.

The owner subsequently requested implementation. Identity, waiting, and fallback
semantics were first recorded in `docs/contracts/screen-set-and-window-life.md`,
then implemented. This document preserves the research baseline: current/proposed
below means the state at that time. Implementation and evidence appear at the end.
The physical failure was not closed. After the CLT scope, absent full Xcode, and
pending physical acceptance were explained, the owner requested publication.
Version v0.1.8 was delivered as a diagnostic prerelease using the existing GitHub
packages' ad-hoc signing, without an installable Homebrew Cask or a claim of
completed Developer ID/notarization distribution.

## Finding

The central repair is to keep temporary control-interface failure separate from
window death and permanent removal of stash intent. Stable display geometry,
valid AX references, and a responsive target app are different evidence. A fixed
extra delay or rewriting all windows does not establish them.

The strongest concrete gap was
`invalidUIElement → windowDestroyed → forget everywhere`. Independently, a
non-drag move of an expanded window away from an edge on the same display still
returned `detach`. Both are replayable code behavior; no field event log established
which occurred on the owner's machine.

## Primary material and comparable cases

| Evidence | Verified content | Scope |
|---|---|---|
| [Apple AXUIElement.h](https://developer.apple.com/documentation/applicationservices/axuielement_h) | `invalidUIElement` means the supplied AX reference is invalid; `cannotComplete` can reflect messaging failure, an unresponsive app, or waiting for input. | Neither establishes that sleep invalidated a reference or that the underlying window closed. |
| [Apple AX messaging timeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) | Timeouts may be global to the process or per AX object; per-object configuration does not automatically affect an equal object. | Supports measuring calls and controlled timeouts, not inventing a fixed wait. |
| [Rectangle #640](https://github.com/rxhanson/Rectangle/issues/640) | After sleep/login, the tool could still run but fail to obtain window IDs; similar Magnet reports appeared. | An older-system analogue, not macOS 27 root-cause proof or a reusable verified repair. |
| [yabai #2783](https://github.com/asmvik/yabai/issues/2783) | Wake lost autofocus; restarting recovered control but lost layout. | Illustrates the control-recovery/state-loss trade-off, not shared causality. |
| [yabai #2829](https://github.com/asmvik/yabai/issues/2829) | The reporter sampled main-thread AX waits affecting pointer taps. | Field evidence of synchronous AX blocking input; this project still needs timing. |
| [Hammerspoon AX documentation](https://www.hammerspoon.org/docs/hs.axuielement.html) | Apps may reject attribute changes; readback is needed for confirmation. | Supports separating API result, actual frame/minimized state, and session commit. |
| [AeroSpace #1216](https://github.com/nikitabobko/AeroSpace/issues/1216) | A maintainer described a 0.19.0 lock-screen/dead-window race losing whole workspace memberships, and slow AX responses mistaken for death. | A confirmed repaired failure class; implementation/display model differ, so no patch was imported. |
| [AeroSpace #2264](https://github.com/nikitabobko/AeroSpace/discussions/2264) | A September 2026 macOS 27 single-display report rediscovered five windows within 10ms after wake, losing workspace/fullscreen while apps reportedly stayed running. | Close system version without a topology change; reporter observation, not a maintainer-confirmed unique cause. |
| [AeroSpace #1875](https://github.com/nikitabobko/AeroSpace/discussions/1875) | A maintainer confirmed an offscreen-hiding race where state changed after asynchronous reading and saved position could be overwritten; a fix landed and users reported 0.20.3-Beta improvement. | Supports separating hidden coordinates from intent. EdgeStash has a different await flow, so this is not the same proven race. |
| [AeroSpace #2007](https://github.com/nikitabobko/AeroSpace/discussions/2007) | A report showed the manager PID changing around lock, with workspace memory lost after restart. | Record EdgeStash run identity. The post does not prove WindowServer killed the process. |

[Rectangle #1626](https://github.com/rxhanson/Rectangle/issues/1626) was also checked.
Although its title concerned Emacs after sleep, the reporter later said not every
sleep caused it and other apps worked. The maintainer was still separating Emacs
behavior from visible-frame issues; it was not treated as a proven general sleep
bug. No external reference implementation or checker was imported.

## Local replay evidence

Source: [policy-replay.swift](evidence/2026-10-22-sleep-wake/policy-replay.swift).
Result: [policy-replay.json](evidence/2026-10-22-sleep-wake/policy-replay.json).
It calls pre-repair `EdgeStashLogic` built during the October 22 investigation,
controls no actual window, and does not claim these injected events occurred on
macOS. The invalid-reference policy input is injected.

| Injected sequence/observation | Pre-repair result |
|---|---|
| Three processes alive, unchanged three-display layout, all cached references invalid | `syncEndEvent` returned `windowDestroyed` for all three. |
| Apply live shutdown removal with `forgetting(everywhere: true)` and remove retry | Membership dropped 3→0; pending retries dropped 3→0. |
| Wake settle again on the same layout | `restore=0`, `refresh=0`; unchanged-layout repair had no target left. |
| Same-process input without invalid role | Did not enter this death branch; not every AX error erased a window. |
| Expanded window moved to same-display center, `wasDragged=false` | `externalGeometryAction` still returned `detach`; this differs from the owner's all-collapsed scene. |

Pre-repair periodic-sync tests in `EdgeStashLogicTests.swift` explicitly expected
invalid role to return windowDestroyed. The same boolean conflated invalid control
reference with actual window death, hiding the semantic gap behind passing tests.

Key baseline locations:

- `StashEngine.swift:555` reduced role status to `windowRoleInvalid`, ended the
  session before discovery, and deduplicated fresh references only with `CFEqual`.
  It had no reference-replacement path preserving the session.
- `StashSession.swift:503` shutdown cleared phase/edge/pin/marker. The death path
  could clear rescue and remove placement from every screen set outside the
  coordinator.
- `StashAX.swift:90` converted both failed AXWindows queries and successful empty
  results to `[]`.
- `ScreenSetCoordinator.swift:323` scattered refresh failures and reached idle
  through `shutdown(.miniaturized)`; later restoration depended on surviving
  identity and bounded retries.
- `AppDelegate.swift:143` released the batch when trust was false. There was no
  evidence of actual sleep-time permission loss on the owner's machine.

`shutdown(.windowDestroyed)` itself does not restore frame/opacity. Invalid-reference
misclassification alone may therefore not explain every newly visible window.
System reconstruction/movement, visibility fallback, permission suspension, or
engine/app restart could contribute. Logs need process/run identity. If EdgeStash
restarted, INV-L9 already forbids reviving membership; investigate why it exited
rather than silently adding cross-process inheritance under a wake repair.

## Proposed changes at investigation time

### 1. Preserve query meaning

Add error-bearing AX results, initially for enumeration, role, frame, and minimized
state. `nil/false/[]` cannot simultaneously mean unavailable, absent, and successful
empty. Policy distinguishes successful observation, messaging failure/timeout,
invalid reference needing rediscovery/identity checks, and positively established
window/process death.

`cannotComplete` cannot become death. `invalidUIElement` should attempt rediscovery
before irreversible global forget. Even successful empty enumeration needs context:
user session, hidden/minimized state, and server ownership. Otherwise the repair
creates another false-removal path.

### 2. Replace AX binding while retaining stash identity

Separate the immutable `windowElement`/observer binding from the stash record.
A replacement must match app/PID launch identity, exact window number, and
WindowServer owner. Similar title/geometry cannot justify recapture.

Reinstall observers and use a separate binding generation to reject queued old
reference destroyed/moved/minimized notifications. Animation generation alone
cannot protect AX callbacks. Uncertainty retains pending confirmation; real close,
process death, and app disable clean up. New windows or reused numbers after
restart cannot inherit membership under INV-L9.

Death cannot mean merely absent from a list. Combine a valid destruction event,
complete successful fresh enumeration, server ownership, and process lifetime;
contradictory/unavailable evidence remains conservative. Absence from the on-screen
list is especially insufficient for minimized seam or other-Space windows.

### 3. Inspect wake, then repair per window

Keep settle and clamshell/unplug classification while checking each window's
control availability. Even unchanged-layout wake must inspect retained stashes.
Matching hidden/minimized/expanded presentation avoids placement writes; cancelled
transitions, actual geometry change, or lost hiding need repair. Expanded unpinned
windows always resume their leave watcher with fresh dwell, whether writes were
necessary or not.

Recovery is per window. A failed target cannot redo healthy siblings or reset an
entire app/set. Frame-write failure cannot erase placement, pin, or target state.
If safety requires visible desktop fallback, appearance and recovery intent remain
separate; a visibly present window cannot falsely remain logically collapsed.

Keep the initial attempt plus three 1/2/4-second write retries. Distinguish waiting
for fresh observation from real write failure and measure stages. Any longer wait
requires field evidence and a contract, not unbounded retry. User drag, detach,
close, or quit cancels the old automatic target.

### 4. Wake-time system movement is not user detach

Late AXMoved/AXResized during recovery cannot directly enter ordinary detach.
Use environment epoch, binding generation, fresh reads, and real gesture evidence.
Review expanded same-display non-drag detach independently. Prioritize wake repair
while retaining genuine desktop-drag release, avoiding unrelated daily-movement
changes.

### 5. Keep permission boundaries and record actual transitions

False AX trust immediately stops control. Do not suppress checks, alter TCC, or
automatically reauthorize. Record its order relative to power/wake/session events.
Separate pausing AX work from permanently forgetting intent. Any same-process
permission recovery requires renewed identity and explicit visibility rules after
real revocation. This independent branch was not changed on speculation.

### 6. Ship controlled diagnostics in Release

Separate diagnostics from optimization. An explicit diagnostic Release should
carry a package flag written before signing and log from launch. Ordinary Release
stays disabled. A test Mac should not need development tools, terminal environment
variables, or preference edits.

Keep bounded, asynchronous, rate-limited machine-local logs without titles,
contents, keyboard input, or network. Record lifecycle/state changes rather than
every successful frame write, limiting diagnostic overhead on the reported load.
Required evidence:

- Unique version/build and actual loaded binary identity; do not reuse 0.1.7 (8).
- EdgeStash PID, run ID, and start/stop, distinguishing in-process loss from restart
  with fresh semantics. Missing stop does not establish crash cause.
- Wake epoch; original stash/pin; reference generation; per-window recovery result.
- AX status/duration, including failed queries versus successful empty lists.
- Separate uncertain deferral, exact rebind, confirmed death, visible fallback,
  and actual forget reasons.
- Necessary before/after frame/minimized/alpha, separating API acknowledgement
  from matched appearance.
- Completed/waiting/exhausted recovery and which targets remain unfinished.

## Release order and acceptance

Implement the minimal identity-recovery path and Release diagnostics before
assuming full wake rewrites are a ready repair. If failure injection cannot verify
identity, publish diagnostics on existing behavior rather than hide unverified
behavior changes in evidence-only delivery.

Before implementation, record concrete identity/fallback/wait semantics in a
current or owner-accepted contract. Research alone does not accept a new appearance,
wait duration, or permission-recovery policy.

Minimum sequences using decisions shared by live adapters:

1. Unchanged-layout sleep/wake preserves collapsed/expanded/pinned intent, avoids
   unnecessary writes to healthy windows, and restores unpinned leave watching.
2. An invalid old reference plus an exact verified replacement preserves membership,
   pin, and placement; stale destroyed callbacks cannot end the new binding.
3. AXWindows messaging failure, no value, and successful empty stay distinct.
   Missing fresh observation cannot forget.
4. Real close, process exit, reused PID/window number, and app disable clean up;
   a new window cannot resurrect membership.
5. A single write failure leaves siblings intact, retains intent through fallback,
   and has a bounded budget unaffected by duplicate events.
6. User drag, quit, or detach during recovery cannot be undone by the old target.
7. Non-gesture system movement during wake does not detach; real drag still does;
   unpinning does not alter identity.
8. Empty displays, genuinely absent externals, clamshell built-in hold, mirroring,
   and scale round trips preserve existing contracts.
9. False trust stops control; logs record, rather than guess, its wake relation.
10. Optimized Release actually logs; disabled diagnostics do not evaluate snapshots;
    rotation is bounded and shipped ZIP version/signature/flags agree.

Run expectation checks and appropriate native builds after implementation. The
baseline replay demonstrated an old gap, not a passing repair, a real-machine
reproduction, or successful native AX rejection injection.

## ChatGPT cross-check

The owner authorized `chatgptbox.ask_chatgpt`. A generic mechanism question supplied
necessary symptoms and abstract control flow without source/local paths. The
completed consultation prioritized observation/control failure being promoted to
death and suggested separating session intent from AX handles. This agreed with
local replay but did not establish owner-scene cause.

Suggested AeroSpace #2264, #1875, and Amethyst #1282 were checked in original posts;
research then found the more direct #1216. For #888 only the three-display sleep
position-loss report was verified, so no unverified maintainer quotation was used.
Amethyst #1282 involved DisplayLink and a workaround disabling sleep; it was not
adopted as a repair.

Adopted directions: retain intent, verify identity and replace bindings, recover
per window, reject stale work, and collect structured Release evidence. Suggestions
not adopted directly:

- Title-assisted rebinding: no new title collection/dependence; unknown exact
  identity is not guessed.
- Unlimited low-frequency recovery after exhaustion: the existing budget is bounded.
- Prohibiting every desktop fallback: visibility/rescue safety still needs fallback
  while retaining intent; logical phase cannot justify an inaccessible window.
- Suppressing permission changes or automatic reauthorization prompts: violates
  permission/effect boundaries; record actual transitions first.
- Persisting/resurrecting memberships across EdgeStash restart: forbidden by fresh
  semantics and not an incidental wake repair.

No external reference code or system modifications from posts were imported.
Conclusions rely on original material, Apple semantics, and local replay; AI advice
served only as cross-checking and source discovery.

## Implementation and verification on 2026-10-22

Implemented:

- `WindowRecoveryPolicy` separates transport wait, unique exact rebind, and
  confirmed death. Discovery no longer maps invalid role directly to destruction.
  Missing process metadata is not a known restart; workspace-missing PIDs are
  cross-checked with zero-signal existence queries.
- Native sessions replace app/window AX references and observers. Callbacks verify
  binding and environment-lifecycle generations; rebind creates no idle duplicate.
- Same-layout wake observes minimized/frame/alpha, avoiding healthy placement
  writes. Lost control retains stash/pin/geometry for existing discovery. Missing
  observations cannot establish death.
- Recovery owns independent intent, preserved through visible idle fallback.
  Only failed writes consume initial-plus-three attempts; observation waits do
  not. Exhaustion cannot be reset by rebind/duplicates, and quick readiness cannot
  skip backoff. Drag, recapture, close/disable/quit, and new environments cancel
  targets. An unverified departing-display window retains a landing point until
  rebind can complete visibility fallback.
- An explicit pre-sign package flag enables optimized Release diagnostics; ordinary
  Release stays off. Version 0.1.8 (9) records loaded UUID, PID/run, AX errors/slow
  calls, identity decisions, before/after observations, remaining budget, and exhaustion.

Expectation check passed: all twelve anchors declared, unchanged one executable/
eleven structural-only presentation cardinalities, all logic tests passed.
`Tests/WindowRecoveryTests.swift` added shared-live-decision timelines for three
windows on an unchanged layout, invalid binding, real close/reused number, stale
callbacks, waits/exhaustion, retained pin/geometry, and read-only healthy wake.
Ten packaging tests covered optimized diagnostics, ordinary Release off, invalid
arguments/failure isolation, signing/notarization order, and ZIP metadata.

A native metadata-decoding probe passed: windows lacking bounds retain id/pid;
missing/non-numeric alpha stays unknown; incomplete identity is unavailable while
successful empty remains empty. Source:
`evidence/2026-10-22-sleep-wake/metadata-probe.swift`, compiled with live
`StashSurface.swift`, `StashDiagnostics.swift`, and current logic objects. It controls
no actual window and prevents filtered unreadable metadata becoming false absence.

CLT Debug and Release builds passed. Final `dist` was 0.1.8 (9), arm64, Release,
with diagnostics enabled. Staged and freshly extracted apps passed local signature
verification, matching plist/executable. Signing was ad-hoc, without Developer ID
or notarization. SHA-256, UUID, and scope are in
`evidence/2026-10-22-sleep-wake/verification.json`.
Optimized local probes checked flags on/off, disabled snapshot laziness, valid
Release-writer JSON, bounded rotation/current/previous logs, directory 0700/file
0600, and repeated-error rate limiting. They wrote only `.build`, never test events
to the user's log directory.

Full Xcode was absent; Xcode-project Debug returned the CLT-only error. These
checks neither prove actual AX notification/write success nor close the owner's
macOS 27 failure. Original baseline replays remain historical investigation
evidence, not regression proof for new code.

## Owner-authorized test publication

After package and verification scope were explained, the owner requested a release
(translated). [v0.1.8](https://github.com/aaaAlexanderaaa/edgestash/releases/tag/v0.1.8)
was published as a prerelease, preserving the stable-release entry. Notes included
actual evidence, log location, and physical reproduction steps. Full Xcode remained
open and CLT was not counted as satisfying it. Signing matched the earlier 0.1.7
ad-hoc test-distribution approach.
