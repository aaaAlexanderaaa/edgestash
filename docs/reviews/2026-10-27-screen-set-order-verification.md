---
doc_type: verification
status: complete_with_explicit_scope
authority: informative
verification_status: partial
last_reconciled: 2026-10-27
---

# Display connection order: executed verification

The owner asked whether sleep/wake and reconnect recovery overlooked variable
connection order when the final display set stays unchanged. Executed replays did
not reproduce final configured membership/display/edge/memory corruption from
order changes. An earlier answer cited missing coverage before executing it;
missing tests alone were not a demonstrated runtime defect or root cause.

No product runtime, wait duration, or retry budget changed. This English
translation preserves the historical scope of the October 27 verification.
Regression tests and adapter evidence were added.

## Shared policy verification

`Tests/ScreenSetOrderTests.swift` is registered in `EdgeStashLogicTests` and runs
through the expectation check.

- **18,432 three-display round-trip timelines passed.** Three remaining singleton
  choices; two removal orders and two addition orders; 64 combinations of configured
  intermediate subsets; eight intermediate-settle combinations; success, one-window
  failure, and all-window failure. Intermediate observations include origin shifts,
  provisional arrangements, mode changes, and wake flags. Each final configured
  triple must have exact membership/display/edge, unchanged configuration memories,
  and no restore/release/refresh from a duplicate final observation.
- **1,512 return paths across arbitrary nonempty subsets passed.** Each of seven
  configured destinations (three singletons, three pairs, one triple) follows three
  other nonempty sets before return.
- All six display enumeration permutations have equal observations/fingerprints.
  Wake-subset grace boundaries use the live shared policy. Intermediate memories
  deliberately relocate members and add extras that the final complete target
  must remove, checking equality rather than mere inclusion.

These call the actual `ScreenSetMemoryCoordinator`. In-memory desktop write results
are injected, so they do not establish AppKit ordering or native AX completion.

## Actual coordinator replay

[adapter-replay.swift](evidence/2026-10-27-screen-set-order/adapter-replay.swift) is
appended to unmodified live `ScreenSetCoordinator.swift` and compiled. It executes
actual apply, finishSettle, finishWake, and retryRestoration methods. Replaced
boundaries are display enumeration, session/AX results, preferences, and diagnostics;
coordinator decisions remain unchanged.

The original run passed **61 timelines and 266 assertions**:

- 48 round trips: both unplug/reconnect orders, configured intermediate present/
  absent, success/failure/control wait, and ordinary/wake application. No stale
  intermediate retries or session recovery remained; exact membership and every
  configuration memory matched.
- Ten power/settle cases: display-only versus system sleep, empty enumeration,
  both external arrival orders, subsets before/after grace, enumeration changing
  between notification and timer, and sleep-length timer overruns. Timer delivery
  and elapsed timestamps were injected, not decisions.
- Three retry cases: control readiness for both external orders, plus one real
  wall-clock 1/2/4-second failed-write budget. Duplicate observations spent no
  budget, healthy siblings were not repeated, exhaustion retained memory, and a
  later configured return restored the target.

Run on macOS with repository source and the local Swift toolchain:

```bash
python3 docs/reviews/evidence/2026-10-27-screen-set-order/run-adapter-replay.py
```

Current results go to `.build/screen-set-order-replay/result.json`. The archived
[adapter-result.json](evidence/2026-10-27-screen-set-order/adapter-result.json) retains
the October 27 result and input SHA-256 values; it is not proof for later source.
The 0.1.10 integration synchronizes injected boundaries with the newer coordinator,
adds six reliability timelines (67 total, 298 assertions), and adds this command
to CI. Fresh evidence is recorded separately from this historical JSON.

## Verification scope

The original expectation check passed: twelve declared presentation anchors and
the full logic suite. Presentation cardinality remained one executable and eleven
structural-only; this evidence did not promote those rows.

The replays support exact configured destinations for the tested display/failure
sequences. They do not prove stable physical display identity, exhaustive macOS 27
notification inputs, or successful real AX writes. Native `StashSession`, actual
pin/appearance/geometry restoration, and physical plug/unplug were not executed;
earlier physical acceptance remains open. Quiet increments ending in an
unconfigured set still retain members under the contract. This review does not
invent path-independent semantics for every unconfigured endpoint.
