# EdgeStash state-machine boundary review

Date: 2026-09-23. Scope: the working tree at review time, including the
September 22 display-restoration and opacity fixes. Translated from the original
Chinese review for the English project policy; all findings remain historical.

This review crosses window phase, hide strategy, asynchronous operations,
display environment, and window lifetime. The four phases
`idle → captured → collapsed → expanded` are insufficient by themselves.
A collapsed session may be expanding, already deminimized but uncommitted, or
waiting for display enumeration. Each requires different cancellation and recovery.

## Repaired gaps

| Boundary | Previous defect | Repair and evidence |
|---|---|---|
| Repeated display notifications and restoration failure | Applying the same target reset its failure count, potentially making bounded retries unlimited | Preserve the budget for the same memory and remove it after success; twenty duplicate observations permit only the initial attempt and three retries. Boundary tests. |
| Restart and display reconnection | Initial launch did not restore membership, but loaded old window numbers could later identify new windows as old members | Preserve configuration keys while clearing memberships in a new process; remove automatic capture based on a parked-looking frame. Boundary tests and call-site review. |
| Rescue and idle after failure | Idle phase, a manual drag, or an on-screen frame could authorize deleting rescue records | Require successful opacity and minimized-state restoration; preserve the dossier and fields needed to retry on failure. Boundary tests. |
| Rescue and reused PID/window number | Matching numbers could identify a window from a different process launch | Check bundle, launch time, and record time; without AX trust, also verify WindowServer ownership. A new process permits only the pre-existing conservative shape match. Boundary tests. |
| Animation completion and failed AX writes | Elapsed animation time committed collapsed/expanded state while discarding final write results | Report final write acknowledgement; failed hide restores visibility, failed reveal re-hides or releases. Source review and native compilation; real AX rejection injection remained open. |
| Seam reveal and an undelivered Space change | Generation checks rejected stale callbacks, but the final frame write after preparation lacked a destination check | Check current destination and membership before deminimization and after the frame write; compensate on failure. Policy tests and source review; native timing remained open. |
| Failed collapse and leave timer | The timer stopped, but synchronous collapse failure did not resume it | Restart leave observation for an expanded window; capture failure restores visibility and preserves unresolved records. Source review and compilation. |
| User drag and system move | Opposite-edge drags released membership, system moves of hidden windows erased memory, and pinned windows could not be dragged out | A shared action policy distinguishes detach, edge change, display change, and re-hide, after the drag settles. Boundary tests exercise the live policy. |
| Unrelated display increment and existing windows | Every window still received frame/opacity writes | Reconcile only coordinate, scale, adjacency, or cancelled-operation changes; otherwise resume observation. Boundary tests. |
| Transient unavailability without another Space notification | A failed seam query could leave its signal permanently disabled | Reuse the existing 0.5-second poll; update only when availability changes, without repeating the explanation. Source review and compilation. |

The first regression run reproduced ten failed assertions covering rescue,
pinned drags, and duplicate-notification budgets. Movement tests were then moved
to the shared action policy actually used by the runtime; unused older policies
were removed.

## Boundaries this evidence did not close

- At review time, show-all detection covered Control-Up/Control-Down, with no
  trackpad-gesture or dedicated Mission Control-key path. Policy tests cannot
  establish native input coverage. Reproducible native events are needed to
  avoid treating an ordinary Space switch as permission to open all stashes.
- Whether Cmd-` skips fully transparent windows parked at an edge still needs
  target-application testing. There was no dedicated keyboard-cycle interception;
  possible operating-system behavior was not counted as verified capability.
- Dock thumbnails still used titles. Identically named windows in one app could
  be ambiguous; precise multi-window identification needed real Dock AX identity.
- Slow enumeration, mirroring, clamshell wake, Space changes, and simultaneous
  AX writes require physical event sequences. Headless tests do not prove that
  the operating system accepted writes or that transparent windows have no pixels.
- This machine had only Apple Command Line Tools. Native compilation and signing
  were available; the full Xcode-project Debug gate remained open. The diagnostic
  executable lacked Accessibility authorization, so cross-process AX rejection
  injection was incomplete.

## Verification entry points

- `./scripts/check-expectations.sh`: declared presentation anchors and the full logic suite.
- `Tests/StateMachineBoundaryTests.swift`: failures, duplicates, lifetime, and movement boundaries.
- `Tests/ScreenSetMemoryTests.swift`: display round trips, mirroring, scale, and power state.
- `./scripts/stage-app.sh Debug` / `./scripts/stage-app.sh`: native Debug/Release builds and fixed delivery paths.

## Verification results at the time

- The final expectation check and full logic suite passed. All twelve presentation
  anchors were declared; one cardinality had executable evidence and eleven
  remained `structural-only`. This did not verify every presentation cardinality.
- Final native Debug and Release builds passed. The Release timestamp was
  `2026-09-23 08:13:13 +0800`, recorded in `dist/CURRENT.txt`.
- `codesign --verify --deep --strict`, `plutil -lint`, ZIP integrity, and
  `git diff --check` passed.
- The Xcode-project Debug build was attempted and could not run with only CLT.
  That gate and the native-event/multi-display review above remained open.

No networking, screen capture, external code, or new permissions were added.
No commit was made during this review.
