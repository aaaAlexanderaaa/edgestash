# Sleep and automatic collapse: diagnostic Release builds

Version 0.1.10 (11) retains explicit local diagnostics in the optimized Release
package. `blockedSpace` means environment recovery was refused by the current
Space safety gate. The window stays minimized, preserves its original expanded
or pinned recovery intent, and uses the existing bounded retry budget. It cannot
bypass refusal through a deminimized desktop fallback. Completing Space
preparation resumes that same budget without adding a background polling clock.
Physical macOS 27 multi-display wake and WindowServer acceptance remain open.

`waitingForPersistence` means appearance is already correct but a rescue update
has not received save acknowledgement. Recovery intent and the same bounded
budget remain; this neither reports completion nor triggers visible fallback.

Recovery first reads `~/Library/Application Support/EdgeStash/rescues.json`,
using a valid `rescues.previous.json` if damaged. Ordinary settings remain in
`store.json`. Before acknowledgement, both rescue copies contain the same latest
complete set, including the newest hidden window. Settings and rescue errors
remain independent; success in one cannot conceal failure in the other. Legacy
records migrate only when no independent journal exists. Keep these local files;
do not overwrite or delete unresolved rescue records. They contain no window
titles, document contents, or screenshots.

Earlier packages did not contain complete sleep, session, and automatic-collapse
logs, so they cannot reconstruct failures from before installation.
The [v0.1.8 test release](https://github.com/aaaAlexanderaaa/edgestash/releases/tag/v0.1.8)
introduced startup logging without a separate diagnostic tool. Since 0.1.8 (9),
diagnostics and optimization are independent:

```bash
./scripts/stage-app.sh Release --diagnostics
```

This package uses Release optimization. `dist/CURRENT.txt` must report both
`configuration: Release` and `diagnostics: true`. The package's
`EdgeStashRuntimeDiagnostics` flag is written to Info.plist before signing;
terminal launch, environment variables, and development tools are unnecessary.
Ordinary `./scripts/stage-app.sh Release` disables diagnostics; Debug enables them.

Quit the running EdgeStash, then open `dist/EdgeStash.app`. Use
`dist/EdgeStash.zip` on another machine; quit the old process before opening the
extracted app. Replacing a disk file does not restart an old process.
`app.start` records version, build, configuration, and the UUID of the actually
loaded Mach-O image to distinguish these cases.

1. Stash windows normally, then turn the display off or sleep and wake as usual.
   A display-layout change is unnecessary.
2. If the problem recurs, note the approximate time and the window/rail state.
   Shortcuts can still be used normally.
3. In Finder's Go to Folder, open `~/Library/Logs/EdgeStash/` and copy or compress
   the entire directory for analysis. Copy promptly: rotation replaces older logs.

Logs are line-delimited JSON: `runtime.jsonl` and `runtime.previous.jsonl`, each
capped at 2 MiB, approximately 4 MiB total. They survive app launches. Each event
includes wall time, uptime, EdgeStash PID, and the current run ID. Directory mode
is 0700 and new files use 0600. A serial utility queue writes logs and drains on
quit; Console need not be open. Disk failure is reported once to system logging.
An absent log entry does not prove that an event never arrived.

## Paths the evidence distinguishes

| Event | Purpose |
|---|---|
| `workspace.*` / `power.*` / `screens.*` | Distinguish system sleep from display power; record unchanged-layout wake, settle, restoration plans, and retries. |
| `session.role-check-failed` / `ax.failure` | AX error and target reference; an error alone no longer means window death. |
| `session.control-wait` / `session.binding-check` / `session.control-rebound` | Unavailable reference, enumeration success/failure/completeness, exact candidate count, server ownership, previous/current process launch time, waiting, and rebinding. |
| `session.stale-ax-callback` | Rejected notification from an old binding or environment; snapshots also include binding/lifecycle generations. |
| `session.recovery-observed` / `session.recovery-unchanged` | Pre-write frame/minimized/alpha and healthy windows that need no placement write. |
| `session.recovery-readback` | Whether post-write observations match the target; API success alone does not establish recovery. New builds include `confirmation` (`waiting`, `confirmed`, `expired`) and expected/observed frames. Waiting reuses the original write and attempt. |
| `session.minimize-confirmation` / `session.minimize-release-confirmation` | Delayed capture confirmation and settled cancellation of an unconfirmed hide. Session snapshots include pending confirmation flags and unconfirmed ownership. Added after 0.1.10. |
| `session.external-geometry` | Observed frame, minimized state and geometry decision. `ignore` prevents minimized bounds from overwriting the saved desktop location. |
| `session.seam-prepare-failed` / `session.seam-reveal-failed` | Exact preparation refusal and resulting availability for a named reveal. |
| `session.seam-commit-failed` / `session.seam-frame-rejected` | Commit stage, target display/Space, and expected versus observed frame. Separates deminimization failure, frame mismatch, changed destination, and failed compensation. Added after 0.1.10; old packages cannot emit these details. |
| `session.restore-result` / `session.refresh-result` / `session.retry-result` | `succeeded`, `waitingForControl`, `waitingForPersistence`, `blockedSpace`, or `failed`; `remainingAttempts` is the remaining write budget and becomes -1 after successful queue removal. |
| `session.scatter-fallback` / `session.fallback-waits-for-control` | Visible desktop fallback or deferral until a verified binding; intent is distinct from idle appearance. |
| `session.recovery-exhausted` | Initial recovery plus three retries failed; automatic writes stop while the original target remains. Space/persistence refusal retains its existing presentation rather than forcing desktop fallback. |
| `session.shutdown` / `session.shutdown-result` / `memory.forget` | Actual release reason, visibility restoration result, and whether memory was removed. |
| `session.leave-gate` / `session.auto-collapse` | Changes in automatic-collapse guards and attempts; the 0.1-second observer does not log every tick. |
| `shortcut.*` | Idle/collapsed/expanded counts at the gesture and whether an idle window was captured again. |
| `engine.trust-lost` / `engine.start` / `app.start` / `app.stop` | Permission suspension/recovery and app restart; a missing stop event alone does not prove crash cause. |

`ax.slow` records calls longer than 0.25 seconds; it changes logging, not the AX
timeout. An identical target/operation/attribute/error is logged at most once per
five seconds. Ordinary fast successful calls are not emitted per frame. Session
snapshots include the subject PID, process launch time, window number, geometry,
pin, hide strategy, leave watcher, recovery, and binding generations. No titles,
filenames, document contents, keystrokes, or pixels are collected. There is no
networking or automatic upload. Ordinary Release neither evaluates diagnostic
snapshots nor creates the diagnostic directory.

## Repair boundaries and verification

An invalid AX reference no longer globally forgets a window. Uncertain identity
retains intent and waits; a verified replacement binds to the same session rather
than creating an idle duplicate. Death requires process death, changed ownership,
or destruction corroborated by complete successful fresh enumeration and absent
server ownership. Missing process metadata alone does not mean exit. Actual
closure and disable still clean up memory.

Unchanged-layout wake observes healthy presentation before writing and resumes
the leave watcher for expanded unpinned windows. Failure fallback preserves the
original location, expanded/collapsed intent, and pin. Existing five-second
discovery resumes the same write budget when control returns; it cannot enable
unlimited rewrites. A real drag or recapture cancels the old target. Pre-sleep or
old-binding callbacks cannot overwrite new state.

Real permission revocation still suspends the engine. Quit/crash follows the
fresh-launch contract and does not revive membership. Start/run/UUID evidence
helps distinguish these cases; similar symptoms alone cannot establish cause.
Local CLT builds do not close the separate Xcode-project gate. Physical macOS 27
multi-display sleep acceptance remains open. Historical recovery evidence is in
`docs/reviews/2026-10-22-sleep-wake-recovery-research.md`.
