---
doc_type: review
status: implemented_pending_native_verification
authority: informative
verification_status: partial
last_reconciled: 2026-11-11
---

# Stickies lost after wake and delayed minimize

The owner reports macOS 27.0.1, EdgeStash 0.1.10 and Stickies. After display
changes or sleep, repeated shortcuts cannot reopen notes; clicking a minimized
Dock tile reveals a note near the primary display's upper-left area.

The owner supplied `/root/tmptest/EdgeStash.zip`. Its two rotating JSONL files
contain 8,307 rows. Raw logs remain outside the repository. The
[analysis record](evidence/2026-11-11-stickies/log-analysis.json) records archive
and file hashes, timestamps and one-based source line references. The current
file's line 1493 identifies the 0.1.10 build 11 run starting at
2026-11-11 06:10:02 UTC. The older run's startup rotated out; its version is not
inferred from the newer run.

## Confirmed field sequence

At approximately 14:52 on November 11 in Beijing (06:52 UTC):

1. Recovery attempts to restore three outer-edge Stickies windows. Frame and
   opacity setters acknowledge the writes, but the immediate presentation
   readback still reports alpha 1, so recovery fails and uses desktop fallback.
2. Separately due retry batches restart their scatter allocation. Windows 1976,
   1978 and 1977 each eventually receive origin `(80, 80)` on the primary display
   (current log lines 2112, 2152 and 2180). This explains the common displaced
   location without requiring a minimized-coordinate rebind.
3. A shortcut attempts capture at a shared edge. The minimize request is accepted,
   but an immediate AX read still says false. The old code treats that mismatch
   as failed capture, releases membership and clears its rescue dossier.
4. The actual minimized=true notification arrives roughly 0.6 seconds later.
   The window is now idle in EdgeStash while physically minimized. Shortcuts
   cannot reveal it as a stash, and capture correctly excludes minimized windows.

For window 1976, the mismatch is at 06:52:18.519 (line 2163), rescue is already
cleared at 06:52:18.538 (2166), and actual minimize is observed at 06:52:19.143
(2169). The same ordering occurs for windows 1978 and 1977. The known 0.1.10 run
contains seven such sequences, with observed delays of 0.576–0.693 seconds.
Fourteen shortcuts in the 06:52:18–06:52:44 interval all report three idle
sessions and no collapsed or expanded stash.

Thirty-two collapsed recovery readbacks in that run report alpha 1 and fail;
one expanded readback succeeds. These logs cannot establish whether alpha was
stale metadata or zero opacity did not take effect. The repair continues to
require actual opacity confirmation; it does not treat setter acknowledgement
as proof of invisibility.

## Repairs

- Capture separates minimize submission from confirmation. An accepted write
  retains membership, restore geometry, rescue and the newest queued shortcut
  intent. The existing 0.5-second observation pass and AX notifications confirm
  completion within the existing 1.5-second settle bound, without repeating the
  write. Expiry retains the latest desired appearance for existing recovery.
- Cancelling an unconfirmed hide submits its inverse even on a false read and
  retains rescue through the settle bound. A failed release confirmation keeps
  the dossier instead of starting an unbounded inverse-write loop. Session
  removal or quit can stop observation, so persisted rescue is still necessary.
- Acknowledged recovery frame/opacity writes get bounded read-only confirmation.
  These checks preserve rebased geometry and do not spend another retry attempt.
  The ordinary geometry-refresh entry also registers its wait with the existing
  coordinator. Persistent mismatch still falls back and spends the existing
  bounded retry budget. Space migration and reveal compensation remain strict.
- The coordinator retains each fallback origin across separate retry batches.
  Changed desktop geometry replaces the allocation. Successful restoration,
  deliberate placement and forgetting a window release its allocation.
- Minimized or unreadable geometry cannot overwrite saved display, edge or size.
  Invalid frames cannot authorize AX frame writes. Valid negative coordinates
  on left/upper displays remain supported. Additional local diagnostic events
  identify failed seam preparation, commit and placement gates.

The minimized-coordinate rebind defect was found before the archive arrived.
It is a separate code-level defect; the supplied logs do not show it causing
this incident. This review supersedes the earlier hypothesis that this defect
alone explained the owner's shortcut failure. Animation-clock failure is also
not established by these logs and is outside this change.

These changes implement the existing anchoring, ownership, rescue and scatter
contracts. They add no alternate hide strategy, presentation production,
permission, network access, or automatic log upload.

## Verification and limits

Executed with Swift 6.0.3 on Linux:

- The full logic executable passed, including delayed minimize, latest queued
  request, readback expiry, opacity mismatch, minimized geometry, invalid frames,
  inverse-write settle, and separate fallback batches. Existing coverage includes
  18,432 configured round trips and 1,512 subset-return timelines.
- A replay of the current coordinator passed 68 timelines and 306 assertions.
  It includes separately due fallback batches and cancellation during release.
  The [result](evidence/2026-11-11-stickies/coordinator-result.json) records source
  hashes and the Linux import/display-query substitutions.
- A [session replay](evidence/2026-11-11-stickies/run-session-write-replay.py)
  extracted six current session method bodies and passed 18 assertions. It
  checks pending minimize completion/expiry, latest intent, bounded inverse
  confirmation, normal refresh registration and preservation of rebased geometry
  during a read-only retry. AX, UI, completion hooks and monotonic time are
  injected; it does not execute full capture/shutdown or native callbacks. The
  [result](evidence/2026-11-11-stickies/session-result.json) records exact inputs.
- These supplementary runs used an external temporary CoreGraphics compatibility
  module exposing Foundation geometry and the existing policy's event constants.
  It is not product code and supplies no native CoreGraphics, AppKit or AX proof.
- `./scripts/check-expectations.sh` passes language/capability and presentation
  structure checks: 12 anchors, one executable cardinality and eleven explicitly
  structural-only cardinalities. Its unmodified logic build fails because Linux
  has no native `CoreGraphics` module. The required complete gate remains open.
- Edited native Swift sources pass syntax parsing, which is not macOS type
  checking. The required Xcode Debug build cannot run because `xcodebuild` is
  absent. No app or distribution ZIP has been staged.

Native verification must complete the expectation check and Xcode Debug build,
then exercise Stickies with delayed minimize, rapid repeated shortcuts, display
unplug/replug and display/system wake. In particular, repeated readbacks must
resolve whether opacity reaches zero on this macOS version. A bounded mismatch
still causes fallback; this patch is not evidence that the opacity symptom is
fully fixed. The owner build must use `scripts/stage-app.sh`; quit the running
EdgeStash before opening `dist/EdgeStash.app`. Distribution remains the app,
`dist/EdgeStash.zip` and `dist/CURRENT.txt` from that script.

## 0.1.11 release follow-up

The owner requested a repair and a non-latest Release build after a release
review reproduced a further request-ordering defect. Recovery submitted a
minimize and waited for readback without owning the session's busy gate. A
shortcut could cancel that wait, mistake a stale false read for a Dock restore,
and then recollapse when the already accepted minimize completed.

Recovery confirmation now owns the existing newest-target queue. It replays the
newest request after the synchronous coordinator commit; failure, environment
cancellation or newer input invalidates older callbacks. The existing Space
preparation and commit checks remain on the replayed reveal.

`python3 scripts/check-session-recovery.py` runs 35 assertions through 19 current
session method bodies, including the recovery entry, named requests, final
completion and Space-safe commit. AX/UI, clock, main queue, animation and observer
boundaries are injected. Removing the recovery busy gate makes the regression
fail. The check runs in CI. macOS expectation and native isolated-adapter checks
also passed locally, closing the earlier Linux-only build limitation for those
checks. Exact release build, archive and CI evidence is linked from
[the 0.1.11 notes](../releases/v0.1.11.md). Physical macOS 27 and opacity acceptance
remain open; none of this follow-up promotes them to verified.
