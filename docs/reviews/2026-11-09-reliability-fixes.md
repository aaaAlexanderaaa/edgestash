---
doc_type: review
status: implemented_pending_owner_review
authority: informative
implementation: implemented
verification_status: partial
last_reconciled: 2026-11-09
---

# EdgeStash 0.1.9 reliability repairs and verification

This work repaired lost rescue records, environment recovery bypassing Space
checks, shortcut/Dock input misclassification, and missing accessibility actions.
Authority is the owner-accepted [recovery/input contract](../contracts/reliability-and-input-sources.md).
Delivery was 0.1.9 (10), an arm64 optimized diagnostic Release with local ad-hoc
signing. Lost stashes after macOS 27 three-display sleep and sustained WindowServer
load still needed field acceptance. This English translation preserves the
original review and release evidence.

## Implemented repairs

| Area | Resulting behavior |
|---|---|
| Rescue persistence | New hides require acknowledged saves. Two independent rescue files retain the latest complete set. Damaged preferences, unknown enums, or one malformed app profile cannot erase valid rescue. Read failure is not empty state; stale readers cannot overwrite unseen records, and same-process compare/save is serialized. Failures appear in existing System settings. |
| Environment recovery | Expanded seam restoration and seam-to-outer conversion share named reveal's Space preparation/commit. Refusal/commit failure retains minimized state and original intent; post-deminimize failure compensates. Old-target callbacks cannot complete a new target; same-target re-entry retains completion. |
| Minimize acknowledgement | Unknown readback is not success. Failed writes retain visibility debt; unavailable control uses bounded retry. Correct appearance with an unacknowledged rescue update retains recovery without desktop fallback. |
| Capture and shortcuts | Drag, app shortcut, and temporary shortcut share standard-window admission. Existing stashes own configured scope; ordinary capture happens only when none exists. Temporary shortcuts cannot capture dialogs/palettes. |
| Cmd-Tab and Dock | Arbitrary activation is no longer Cmd-Tab. A matching gesture and Command release are required; cancellation, other input, pointer activity, and expiry revoke it. Dock title fallback must be unique; focus paths require known app and actual window-identity change. |
| Expand all | An explicit Expand All Stashed Windows menu command replaces hardcoded Control-arrow inference. Automatic Mission Control, App Exposé, gestures, hot corners, and hardware-key expansion are not promised. |
| Accessibility/settings | Rails, merged segments, and pin expose press actions; pin exposes checked state. G/H/B labels are corrected. |
| Engineering verification | Corrected Cask minimum system, added native adapter checks and Actions, and enforced selected capability bans and AppKit separation in the expectation check. |

No networking, capture, new permission, or external implementation was added.
Save acknowledgement covers process-failure recovery, not arbitrary hardware
failure or sudden-power-loss durability.

## Verification at the time

The release machine used macOS/SDK 26.5 and full Xcode. Machine-readable scope:
[verification.json](evidence/2026-11-09-reliability/verification.json).

| Check | Result and scope |
|---|---|
| Expectation check | Passed full logic and reliability regressions; twelve anchors, one executable and eleven structural-only cardinalities. Isolated SwiftPM caches and `--disable-sandbox` addressed local sandbox restrictions without skipping contracts. |
| Native adapters | Passed actual persistence corruption, unknown fields, read-only directory, latest complete backup, stale reader, and concurrent-save cases, plus own-app AppKit accessibility actions. No foreign-window engine was started. |
| Input/recovery regressions | Passed mixed-window shortcut scope, Cmd-Tab commit/cancel, duplicate Dock titles, Space compensation, and stale callbacks after target changes. Injected system-write closures verify ordering, not native AX acceptance. |
| Distribution tooling | Ten tests passed with simulated signing/notarization services. |
| Native builds | Full Xcode Debug and diagnostic Release succeeded. |
| Package | `stage-app.sh Release --diagnostics`; staged/freshly extracted apps passed strict native signature checks and matched every app file, version, architecture, and flag. |
| CI | Workflow was added; remote execution had not yet occurred at initial verification. |

## Physical acceptance and next steps

Quit the running EdgeStash before opening `dist/EdgeStash.app`. Transfer
`dist/EdgeStash.zip` to another Mac. `dist/CURRENT.txt` records build details.

1. Reproduce macOS 27 three-display sleep/wake and confirm retained signal,
   expanded, and pin intent. Collect local diagnostics to distinguish unavailable
   control, Space refusal, real close, and process restart.
2. Check seam reveal, refused cross-Space recovery, and topology changes. Refusal
   must remain minimized rather than appear through fallback; healthy windows
   should avoid unnecessary environment movement.
3. Check Cmd-Tab commit/cancel, identical Dock titles, mixed ordinary/stashed app
   shortcuts, and VoiceOver. Unknown input source leaves stashes closed.
4. Turn remaining structural-only cardinalities into executable lifecycle evidence.
   Any full system-Mission-Control promise first needs reliable observation and
   an accepted contract.
5. Formal distribution still requires the owner's license choice, Developer ID,
   and notarization acceptance. Initial local delivery on November 9 was neither
   committed nor published. On November 10, the owner explicitly requested commit,
   build, push, and release through the existing v0.1.8 diagnostic prerelease
   channel, without claiming formal signed distribution.

## Publication recheck on 2026-11-10

Before publication, the contract/full logic check, native adapters, ten tooling
tests, and full Xcode Debug build passed again. The same staging script rebuilt
0.1.9 (10) diagnostic Release and verified app/ZIP. Final checksum and scope:
[release verification](evidence/2026-11-10-release/verification.json).

[v0.1.9](https://github.com/aaaAlexanderaaa/edgestash/releases/tag/v0.1.9) targeted
the diagnostic prerelease channel, preserving the stable entry. Notes explained
system-overview input limits, local ad-hoc signing/unnotarized status, and pending
macOS 27 three-display physical acceptance.
