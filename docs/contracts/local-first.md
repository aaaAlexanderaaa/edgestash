---
doc_type: contract
status: current
authority: normative
implementation: implemented
verification_status: partial
last_reconciled: 2026-10-22
---

# Local-first operation

## Purpose

Keep EdgeStash a machine-local tool.

## Scope

Process-wide capabilities for this repository.

## Source anchors

- The owner requires EdgeStash to remain entirely machine-local.
- Settings and runtime behavior must not depend on network or capture access.

## Ownership and boundary

This contract owns the capability ban.

## States and triggers

| State | Entry | Visible result |
|---|---|---|
| `untrusted` | Accessibility not granted | Settings opens; no snapping |
| `trusted` | User granted Accessibility | Snapping and hover work |
| `trust-lost` | Permission revoked at runtime | Engine suspends; Settings remains usable |

## Normative invariants

1. No `URLSession`, update feed, telemetry, or product-website open.
2. No Screen Recording permission and no window-content snapshot.
3. No cross-app IPC files or distributed notifications for product features.
4. Launch at login defaults to off.
5. Accessibility is optional for opening Settings.
6. Owner-run Debug and explicitly marked diagnostic Release builds may keep bounded, machine-local runtime diagnostics
   for sleep/wake investigation: power/display observations, per-window stash
   state, process/window identifiers, geometry, and API failure codes. No
   window titles, contents, keystrokes, screenshots, or automatic upload. The
   ordinary Release disables the writer and snapshot evaluation; this is diagnostic
   evidence, not usage telemetry. See `docs/runtime-diagnostics.md`.

## Failure, recovery, and intervention

If a new file imports a network or capture API, revert it.

## Acceptance evidence

- Search under `Sources` finds no `URLSession`,
  `CGWindowListCreateImage`, or `SCStream` (checked 2026-08-29).
- `CGWindowListCopyWindowInfo` reads metadata for Dock measurement, pointer
  ownership, current-Space marker visibility, focus return, and rescue checks:
  bounds, window id, owner pid, layer, and alpha, never window content.
  It is not a capture path.
- Settings opens without prompting; Grant Access is explicit on System.

## Promise register

None.

## Reconciliation log

- **2026-10-22:** owner accepted the recovery implementation and an optimized
  Release diagnostic package for the other physical Mac. The explicit package
  flag is applied before signing; ordinary Release keeps diagnostics off.
  Bounds, privacy and no-network/no-capture capabilities remain unchanged.

- **2026-10-21:** documented Debug-only local runtime evidence in response to
  the owner's sleep/wake failure and logging request. Two rotating files are
  capped at 2 MiB each, written on a serial utility queue; repeated identical
  AX failures are rate-limited. Release has no runtime diagnostic writer.

- **2026-10-14:** corrected the metadata-use inventory to include the existing
  pointer, Space-visibility, focus-return, and rescue checks. Sharing metadata
  within a synchronous Space rebuild adds no capture or network capability.

- **2026-08-29:** adopted as the local-first rule for the EdgeStash tree.
- **2026-08-29 — Settings host:** `Preferences` / Settings rail land with
  no network, capture, or AX observers. Accessibility is polled only on
  the System page. Launch at login still defaults off.
- **2026-08-29 — live engine:** AX observers live in `StashEngine` /
  `StashSession` only after trust is already present. Settings still does
  not start observers. Launch does not prompt. Halo is an overlay, not a
  screenshot.
- **2026-08-30 — lifecycle corrected:** capability bans were already in
  force; `implementation` is `implemented`. Verification stays `partial`
  because the forbidden-API search is a dated manual check, not a
  continuous enforced gate.
