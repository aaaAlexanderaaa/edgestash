---
doc_type: contract
status: current
authority: normative
implementation: implemented
verification_status: partial
last_reconciled: 2026-08-30
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

## Failure, recovery, and intervention

If a new file imports a network or capture API, revert it.

## Acceptance evidence

- Search under `Sources` finds no `URLSession`,
  `CGWindowListCreateImage`, or `SCStream` (checked 2026-08-29).
- `CGWindowListCopyWindowInfo` appears only in the Dock measurement: it
  reads window bounds, owner pid, and layer — window metadata, never
  content — and is not a capture path.
- Settings opens without prompting; Grant Access is explicit on System.

## Promise register

None.

## Reconciliation log

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
