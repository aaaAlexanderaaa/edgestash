# 2026-10-20: sustained WindowServer load investigation

Status at investigation: a mechanism omitted by the preceding verification was
identified and field diagnostics delivered. The macOS 27 three-display failure
had no confirmed single cause; no release claimed it repaired. Translated from
the original Chinese investigation, preserving historical evidence and limits.

Owner scene: Release 0.1.6, macOS 27, three displays, multiple stashed windows,
and sustained WindowServer CPU usage. The exact trigger was unknown.

## Why preceding repairs did not close the issue

`a6e0379` (0.1.5) shared per-pass queries and skipped unchanged panel redraws,
frame, alpha, and ordering writes. Version 0.1.6 retained those repairs. Native
unchanged-update probes established no redundant adapter writes, but did not
measure target-system composition or prove that stashed apps stopped rendering.
Nudge/Fade changed transitions, not final outer-edge position or zero opacity.

Low EdgeStash CPU, no repeated `needsDisplay`, and passing logic tests therefore
did not establish resolution of this report.

## New native evidence: zero opacity can still count as visible

A standalone probe created and controlled only its own AppKit window. Each state
settled for 1.5 seconds; it checked actual frame, `occlusionState`, and WindowServer
metadata. It read no pixels and controlled no other app.

Local results: macOS 15.7.9, one 1920×1080 display at 60Hz.

| State | Actual placement matches experiment | Occlusion visible | On-screen metadata flag |
|---|---|---|---|
| 2pt lip inside display, CGS alpha=0 | Yes | Yes | Yes |
| Same position, AppKit alpha=0 | Yes | Yes | Yes |
| Fully outside all displays, alpha=1 | Yes | No | Yes |
| Fully outside all displays, alpha=0 | Yes | No | Yes |
| orderOut | Yes | No | No |
| System minimization | Yes | No | No |

Raw evidence: [occlusion-macos15.json](evidence/2026-10-20-windowserver/occlusion-macos15.json).
Source: [WindowServerDiagnostic.swift](../../scripts/WindowServerDiagnostic.swift).

Initial positioning encountered AppKit constraining the title bar onto the display.
The final probe overrode its own window's `constrainFrameRect` and emitted expected
and actual frames plus `geometryMatches` for every state. The table uses only
corrected results; the initial placement error is not lip/offscreen evidence.

This matches Apple's public definition: a fully transparent window can still be
considered visible, and apps should stop unnecessary work when genuinely occluded.
See [NSWindow.OcclusionState.visible](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.struct/visible)
and [Notify Your App When Visibility Changes](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/WorkWhenVisible.html).

**Inference, not owner-machine causal proof:** outer hiding retained a 2pt geometry
lip. Although visually hidden, apps throttling from occlusion state might continue
working and submitting graphics, with cost increasing by window count. Zero opacity
has no public guarantee of zero WindowServer cost. The experiment did not measure
foreign apps' rendering submissions or establish identical macOS 27 behavior.
The on-screen metadata flag cannot substitute for occlusion or composition evidence.

## Scope of the local CPU comparison

The developer's running EdgeStash was actually 0.1.5, started October 15, as the
thread-sample header showed. Its disk image had been replaced by 0.1.6. Reading
Info.plist alone would misidentify the process. Diagnostics therefore record start
time, disk version, `executableChangedSinceLaunch`, and a thread sample.

There were no rescue dossiers or desktop stash signals on this machine, only
Settings and menu-bar windows. A five-second sample found the main thread waiting
in its event loop, with no observed active display link. One four-second,
three-phase WindowServer comparison produced:

| Normal | EdgeStash SIGSTOP | Resumed |
|---|---|---|
| 36.7% | 37.9% | 36.7% |

Every pause observation reported EdgeStash state `T`, with no CPU-time increase;
after resume it reported `S`. Counts divide cumulative CPU-time differences by
monotonic elapsed time; 100% means one core.
[Normal](evidence/2026-10-20-windowserver/developer-baseline.json),
[paused](evidence/2026-10-20-windowserver/developer-engine-paused.json),
[resumed](evidence/2026-10-20-windowserver/developer-resumed.json).

This validates that the method distinguishes process execution and shows other
local display load. It did not reproduce the owner's stash scene or confirm or
exclude any target-machine hide path. Pausing does not remove static panels or
stop animation already submitted to the system.

## Code review and investigation priorities

| Direction | Established facts | Missing evidence |
|---|---|---|
| Transparent outer windows still count as visible | `visualHiddenOrigin` retains a lip; collapse checks alpha=0; the native probe still reports visible. | Separate outer/seam paths on macOS 27 with controlled app content; measure client submissions and WindowServer stacks/graphics traces. |
| Static signals affect composition | Thin rail/merge surfaces paint themselves; permanent mainMenu/all-Spaces panels remain; only the glass pin can use system glass. | No redraw is not free composition. Compare panels present/absent with identical client updates. |
| Background observation or feedback loop | Five-second discovery; 0.5-second seam checks; Space queries shared per display, AX still per seam window. | Target-scene pause/resume and stacks; query-count tests do not establish system-call cost. |
| Expanded-window leave watch | A 0.1-second timer while expanded may read AX frame, window lists, and sibling focus; collapse invalidates it. | Whether expanded/pinned windows or rapid asynchronous geometry feedback persist in the failure. |
| Full-screen sheen panel | Paints only 5×220pt but reserves a display-sized panel; orderOut and layer removal within 0.42 seconds. | Transitional/resource cost, insufficient by itself to explain sustained idle load under normal cleanup. |

`StashAnimator` creates a display link on begin and stops it on finish/cancel;
no explicit idle animation clock was found. Space polling does not migrate windows;
migration belongs to named reveal. Pointer-motion seam approach must be measured
separately from true idle cost.

This investigation changed no hide, Space, activation, or material behavior.
The rejected seam clipped-slide experiment was not revived, and outer stashes
were not silently converted to minimization. Fully offscreen placement merits a
controlled experiment, but affects constraints, display ownership, Space reach,
external-geometry repair, and rescue. Removing the 2pt lip is not a one-constant
repair; material behavior still requires a current or owner-accepted contract.

## Field tool and next evidence

See the [diagnostic guide](../windowserver-diagnostic.md). The standalone tool is
not linked into the product, changes no preferences, requests no AX or recording
permission, reads no titles/content, and makes no network calls. The packaged
Apple Silicon executable runs without CLT.

1. Keep three displays and multiple stashes while high load persists; run the package.
2. Collect twelve-second normal/paused/resumed phases, process samples, and before/
   after window/display metadata. Main processes matching rescue dossiers are
   counted; renderer helpers and GPU activity need separate investigation.
3. Run the own-window occlusion probe from the same package on macOS 27. It does
   not alter real stashed windows.
4. If pause/resume has no reproducible difference, compare outer-only and seam-only
   stashes and increasing counts with the same display configuration and static
   app content. Quitting changes windows/content too, so its delta cannot isolate
   signal-panel cost.
5. If needed, collect a WindowServer thread sample and Instruments CPU/GPU trace
   while abnormal. Apple's [Metal developer workflows](https://developer.apple.com/documentation/xcode/metal-developer-workflows)
   describes correlating CPU, GPU, and memory with Metal System Trace. Ordinary
   CPU diagnostics did not measure CA commits, Metal presents, or GPU time.

Full Xcode was absent. WindowServer runs as a system user; ordinary `sample` lacked
permission and `sudo -n sample` required a password, so no system stack was obtained.
The tool requests/stores no password and never terminates WindowServer. Actual
field data was the remaining localization gap.

## Supporting investigation and verification

chatgptbox completed a general AppKit-mechanism consultation. An initial request
containing internal project context was rejected by automatic approval, and that
context was not sent. Subsequent questions concerned public API semantics and
general experimental methods. Advice was cross-checking only; facts rely on local
native observations and primary Apple material.

- Standalone native helper compiled; full diagnostic flow, geometry checks, and
  actual stop/resume passed.
- SIGTERM during pause exited the script with 143 and restored EdgeStash to `S`.
  The independent watchdog binds PID/start time against a killed script.
- Shell syntax and `git diff --check` passed.
- Expectation check passed: twelve anchors, one executable cardinality, eleven
  structural-only, full logic suite. A restricted first run hit SwiftPM cache/
  nested-sandbox limits; a normal-permission rerun passed. The grammar was not
  changed to conceal environment failure.
- Product window behavior stayed intact; release preparation bumped to 0.1.7 (8).
- CLT Debug/Release staging passed, with Release final. Full Xcode-project Debug
  remained unavailable; CLT did not close that gate.
- Seven distribution-tool tests passed at that time.
- Both app and diagnostic ZIPs matched extracted content and passed signature,
  arm64, and macOS 12 minimum checks. App version was 0.1.7 (8).
- Disposable own-process tests confirmed SIGTERM cleanup and SIGKILL watchdog
  resume without controlling the owner's stashed windows.
- Existing ad-hoc signing was retained; Developer ID, notarization, and Homebrew
  required credentials. Version 0.1.7 supplied diagnostics without claiming the
  macOS 27 three-display failure fixed.
