---
doc_type: contract
status: current
authority: normative
implementation: implemented
verification_status: partial
last_reconciled: 2026-11-11
---

# Recovery safety and input identity

The owner accepted the 2026-11-09 review and requested its fixes. This contract
narrows the implementation of the existing recovery and named-input promises;
it adds no network, capture, permission, or alternate hide strategy.

## Recovery storage

- A window may become invisible only after its rescue dossier has an
  acknowledged atomic local save. A failed save leaves the window visible or
  retains its previously acknowledged hidden state; it cannot commit a new hide.
- Rescue records have an independent file in the existing EdgeStash Application
  Support directory. Ordinary preference decoding cannot discard them. Both
  journal copies contain the same complete latest acknowledged set, so damage
  to one cannot discard the newest hidden member. A stale in-memory reader
  cannot overwrite rescue records it has not observed.
- A damaged preferences document is preserved before replacement. Optional
  fields and individual application profiles decode independently; an unknown
  shortcut scope uses the existing default, rather than invalidating rescues.
- An unreadable existing rescue journal with no valid recovery copy blocks new
  hides. It is never overwritten with an assumed empty list. Actual persistence
  failures are reported in the existing System settings page and local logs.
- Acknowledgement protects recovery across process failure. It is not a claim
  that arbitrary storage hardware failure or sudden power loss cannot lose data.

## Capture and environment repair

- Drag, application shortcut, and temporary shortcut share the same admission
  boundary: an identified standard window, not a native full-screen or
  yellow-minimized window, with readable geometry. A temporary shortcut does
  not make dialogs or palettes eligible.
- An application shortcut operates its configured managed-window scope whenever
  that application has a stash. Only when it has no stash may it capture an
  eligible ordinary window. This resolves the previously undocumented idle-first
  precedence in favor of the accepted window-life contract.
- An acknowledged minimize write can complete asynchronously. Capture keeps
  membership, its acknowledged rescue dossier, visible restore geometry, and
  the newest queued presentation request while readback settles. The existing
  0.5-second observation pass checks the existing 1.5-second settle bound; it
  does not repeat the write. Confirmation commits the collapse and consumes
  the queued request. Expiry retains the newest desired appearance for the
  existing control-validation and bounded recovery path; it cannot release an
  unconfirmed hide as an ordinary idle window.
- Cancelling an unconfirmed owned hide submits its inverse even when an
  immediate AX read still says not minimized. That same read cannot clear the
  rescue dossier. The existing observation pass waits through the settle bound
  before confirming release. An unresolved release retains the dossier; the
  confirmation pass cannot create an unbounded inverse-write loop. Quit or
  session removal can end observation, so persisted rescue remains necessary.
- Recovery frame and opacity writes also require observed presentation. An
  acknowledged write gets the same bounded readback wait before fallback;
  those read-only checks do not repeat writes or consume another attempt.
  Persistent mismatch still fails. In particular, opacity 1 cannot stand in
  for confirmed opacity 0. Geometry refreshes outside the screen transaction
  use the same retry owner while confirmation is pending.
- Reopening an expanded seam window during environment repair obeys the same
  current-display ordinary-Space, minimized migration, membership confirmation,
  final recheck, and compensation gates as a named reveal. A refused destination
  leaves the window minimized with a reachable disabled signal and retains the
  original expanded/pinned recovery intent. It cannot use visible fallback to
  bypass the Space gate. Retries remain bounded by the existing coordinator.
  The same gate applies when a previously shared edge becomes exposed, including
  a collapsed window's conversion to transparent offscreen parking. Destination
  changes cancel pending preparation; same-target re-entry retains its completion.

## Input identity

- Application activation alone does not prove Cmd-Tab or a stash-opening intent.
  Unknown activation sources leave stashes closed. Cmd-Tab requires a recent
  observed matching key gesture and Command-release commit; Escape, a different
  key, pointer activity, and expiry cancel it. Owned activations and application
  unhide keep their existing suppression.
- A Dock title is not a window identity. A title fallback must be unique; system
  deminiaturization and verified focused-window observations address their exact
  managed window. Ambiguous title matches never open an additional stash.
- The existing menu may expose an explicit command to expand all stashes.
  System Mission Control/App Exposé inputs may only be mapped when a reliable
  native observation proves that action; a Space change or an arbitrary arrow
  chord is not such proof. Unsupported system inputs must be described honestly.

## Verification and presentation

Keep AppKit-free decisions in EdgeStashLogic. Verify failure/late-callback paths
through the adapters that execute them, as well as shared policy timelines.
The existing System window, marker, merged strip, and pin carry status and
accessibility actions; these changes add no presentation production. Native
multi-display/macOS 27 acceptance remains separate from builds and simulations.

Implementation and workspace verification are recorded in
[the 2026-11-09 reliability review](../reviews/2026-11-09-reliability-fixes.md).
Owner multi-display acceptance and native input-source acceptance remain open.
The 2026-11-11 Stickies field evidence and asynchronous-write repairs are recorded
in [the incident review](../reviews/2026-11-11-minimized-window-position.md).
