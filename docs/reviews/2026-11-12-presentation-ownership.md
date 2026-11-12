# Presentation ownership audit and 0.1.12 repair

The owner requested the five confirmed paths be repaired together, with shared
priority, regression coverage, diagnostics and a 0.1.12 prerelease. The normative
result is [presentation ownership](../contracts/presentation-ownership.md).

## Defects and resulting behavior

| Defect | Owner of the correction | Regression boundary |
|---|---|---|
| Recovery removed pending intent before asynchronous replay, so the second toggle read the old phase | `StashPresentationCoordinator` retains `deferred`; explicit no-ops supersede it | Actual recovery confirmation, another shortcut before queue drain, final phase and write count |
| Merged dwell overwrote a newer explicit close while a reveal was pending | One session admission policy; shared hover eligibility, revision and merged visit cancellation | Actual merged arming/firing and session reveal through delayed Space preparation |
| An unavailable expanded sibling fixed the entire app's shortcut direction | Immutable `StashCommandPlan` filters controllable members before choosing direction | Actual engine shortcut, three toggles, recent scope and skipped-member diagnostic |
| Whole-edge adjacency missed a change in the window's own segment | Screen-set coordinator supplies saved restore frames; memory compares per-window strategy | Actual coordinator reflow/increment, reverse change, duplicate and unchanged sibling |
| Reconciliation forced one expanded member and contradicted batch/cross-app commands | Merge projection emits no geometry command | Entire current merge coordinator, both animation completion orders, app A/B, show-all and pinned highlight |

Committed phase and desired target have distinct roles. Native operation identity
is separate from the revision of input: a newer queued request does not steal
the running operation's failure cleanup. Admission notifications, deferred
replay and animation/Space callbacks cannot execute a superseded operation.
Pin/control protection is checked again at execution. Pin changes are accepted
only when native work is settled and discard an older deferred target.

Merge geometry remains cached independently of momentary button/busy state.
Mouse-up does not wait for the next five-second reconciliation to recover its
approach band. The merged coordinator owns its own visit lock rather than
inheriting the suppressed individual marker's click lock.

## Verification

`Tests/InteractionContinuityTests.swift` covers one through eight toggles at every
recovery/completion split, both initial phases, passive priority, unavailable
members and operation ownership. `Tests/ScreenSetMemoryTests.swift` covers changed
and unchanged occupied segments, reverse topology and missing saved geometry.

`scripts/check-session-recovery.py` extracts the current session and engine
methods and compiles the entire current merge coordinator with injected native,
clock, UI and scheduler boundaries. It also exercises reentrant admission,
failure after queued input changes the revision, pinning before deferred replay,
and a stale animation callback after a replacement operation starts. Inputs are
hashed in its result. The screen-set adapter replay similarly compiles the
unmodified live coordinator with injected display/session outcomes.

See [release verification](evidence/2026-11-12-release-0.1.12/verification.json),
[session/command/merge replay](evidence/2026-11-12-release-0.1.12/session-recovery.json)
and [screen-set replay](evidence/2026-11-12-release-0.1.12/coordinator-replay.json).
Final full-Xcode CI evidence is linked in the published release body.

Local verification on the final app sources passed the expectation check, the
full logic suite (including 18,432 configured round trips and 1,512 subset-return
paths), 71 session/engine/merge replay assertions, 313 coordinator assertions
across 70 timelines, and 18 existing session-write assertions. Isolated native
adapter checks, ten distribution-tool tests, CLT Debug and diagnostic Release
builds also passed. The staged and freshly extracted app have eight identical
file entries and both pass strict signature integrity checks.

Five isolated negative controls deliberately hid deferred intent, included an
unavailable member in direction selection, restored merge sibling-closing,
removed stale-animation ownership, or removed the deferred pin check. Every
variant failed the corresponding replay assertions; production sources were
unchanged. Results are in
[negative controls](evidence/2026-11-12-release-0.1.12/negative-controls.json).

Independent implementation review prompted the separate operation identity,
execution-time pin check and reentrant/cancelled completion cases above. The
follow-up review found no concrete remaining prerelease blocker in the supplied
paths. Environment cancellation was cross-checked against the existing busy
cleanup and deferred-cancellation replay; physical pointer/AX behavior remains
outside that review's evidence.

These checks do not close the existing owner multi-display, physical macOS 27,
foreign-app AX timing or perceptual review rows. The earlier focus-return audit
and synchronous ordinary deminimize timing risks are outside these five fixes;
this release does not claim they were resolved.

## Investigation evidence in the package

The [diagnostic guide](../runtime-diagnostics.md) documents command IDs, skipped
members, request and operation ownership, accepted/refused input, stale replay,
merge projection and geometry refresh reasons. Existing privacy, rotation and
ordinary-Release disabling remain in force. No new UI production or background
timer was introduced.
