# Local WindowServer diagnostics

Use this standalone tool while multiple windows remain stashed and WindowServer
load stays high. It is diagnostic evidence, not a repaired EdgeStash build. Keep
the current scene; EdgeStash need not quit.

Extract `WindowServerDiagnostic.zip` and double-click `Run Diagnostic.command`.
It takes about fifty seconds. During measurement, avoid mouse/keyboard activity
and keep displays, Spaces, other apps, and playback unchanged. The second phase
pauses EdgeStash for about twelve seconds, temporarily disabling stash interaction,
then resumes it. Exit cleanup and an independent resume watchdog protect this
step. The tool does not change preferences, stash locations, or other apps' windows.

Results appear on the desktop in `EdgeStash-WindowServer-DATE-TIME`. Nothing is
automatically uploaded. No Screen Recording or Accessibility permission is
requested; window titles and pixels are not read. Evidence includes logical/pixel
display sizes, refresh rates, window numbers/geometry/alpha, stashed-app identity,
interval CPU measurements, and an EdgeStash thread sample. Samples may include
local paths. Provide the entire directory for comparison.

Run from the repository with Apple Command Line Tools:

```bash
./scripts/diagnose-windowserver.sh --pause-engine --occlusion-probe
```

Package an Apple Silicon version that needs no development tools:

```bash
./scripts/stage-windowserver-diagnostic.sh
```

## Reading the results

`baseline.json`, `engine-paused.json`, and `resumed.json` divide differences in
cumulative process CPU time by monotonic elapsed time; 100% is one CPU core.
These are not the long-term decayed values from `ps %cpu`. Each interval is two
seconds and includes process state; the paused interval should show `T`.
Short intervals vary considerably. Repeat the same scene; a single lower number
is insufficient causal evidence. Main processes matching rescue dossiers are
also measured. Renderer helpers and GPU work are outside this CPU count, so low
main-process usage does not exclude continued graphics submission.

- A sustained reduction during pause that returns after resume prioritizes
  EdgeStash's ongoing queries, writes, and animation work.
- Persistently high load during pause means main-process execution alone is
  insufficient. Static signals, graphics updates from other apps, and display
  composition remain possible. Pausing does not remove panels, and previously
  submitted Core Animation work may continue.
- `before.json` / `after.json` distinguish displays, EdgeStash panels, and candidate
  windows matching rescue dossiers. Dossiers are not proof of active sessions;
  missing metadata is not proof of minimization.
- The header of `EdgeStash.sample.txt` helps verify the loaded version. The disk
  version may differ; replacing the app does not establish process restart.
- `occlusion-probe.json` controls only the tool's own temporary window. It compares
  a zero-alpha 2pt outer lip, fully offscreen placement, orderOut, and minimization,
  recording whether actual geometry matches. `occlusionVisible` and
  `onScreenListFlag` are distinct observations. This does not prove that stashed
  apps respond to occlusion or identify the cause of WindowServer CPU usage.

The tool does not obtain the system WindowServer thread stack; that usually
requires administrator permission. If comparison remains inconclusive, sample
WindowServer in Activity Monitor while the problem persists and keep the report.
Do not end or force-quit WindowServer.

## Separating hide strategy from signal panels

First establish a repeatable baseline. Under the same display configuration,
stash only one outer-edge window, then only one seam window, then increase the
count. Use the same app with static content and unchanged Space, refresh rate,
and other apps. This distinguishes outer hiding, system minimization, panel count,
and display configuration. Quitting EdgeStash restores windows and clears sessions;
its before/after difference cannot be attributed solely to signal-panel cost.
