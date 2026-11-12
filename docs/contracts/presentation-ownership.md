---
doc_type: contract
status: current
authority: normative
implementation: implemented
verification_status: partial
last_reconciled: 2026-11-12
---

# Presentation ownership and operation priority

The owner requested the five audited consistency defects be fixed together for
0.1.12, with shared state, operation priority, regression evidence and local
diagnostics. This contract clarifies the existing newest-target and named-window
rules in `edgestash.md` and `screen-set-and-window-life.md`.

## One owner for a window's target

The committed phase is an observation of completed work. The desired appearance
belongs to the presentation coordinator, including while a completed operation
hands its newest pending request to the next main-queue turn. A toggle always
inverts that desired appearance. A newer explicit request supersedes an older
deferred request even when its target already matches the committed phase.

Only one native transition runs per window. New explicit requests coalesce to
one newest target. Completion can replay that target once, without recording it
as new user input. Failure, membership release and environment cancellation
invalidate both queued and deferred work. Recovery retains its existing bounded
readback, Space, identity and persistence gates.

The input revision and native operation identity are separate. Queueing input
does not transfer ownership of an in-flight write or its failure cleanup. Native
callbacks verify their operation before committing. A request callback that
supersedes admission prevents the original operation from starting. Phase and
busy are committed before completion notifications; a replay rechecks control
and pin protection before writing. Pin changes wait for a settled operation and
discard older deferred input.

## Input priority and scope

1. Environment/identity safety gates can refuse an operation. Refusal records a
   reason and cannot authorize a stale callback or an unverified AX write.
2. Explicit window, application and show-all commands set the newest target in
   their named scope. Batch direction and membership are selected from one
   snapshot before executing any member. A busy but controllable window accepts
   queued input; an unavailable member is skipped and logged, does not determine
   the batch direction, and does not block healthy siblings. Skipped commands
   are not silently replayed after control returns. Recent-window scope chooses
   among controllable managed members; it does not capture an idle sibling.
3. Hover and automatic leave-collapse can start only on a settled window with
   no owned or deferred transition. Hover uses the same admission rule for
   individual and merged rails. A dwell records the target's request revision;
   explicit input invalidates an older dwell, including a parked merged visit.
   A fresh pointer visit can start a new dwell after the operation settles.
4. Merge reconciliation is a presentation projection. It selects a highlight
   but emits no reveal or collapse commands. Clicking or hovering a segment
   addresses that window; it does not close unnamed siblings. Multiple expanded
   members are valid after a batch or separate named commands. Pins retain their
   protection from automatic/merged collapse and their highlight preference.
   The existing leave-collapse policy continues to apply independently.

## Display geometry

A retained window's hide strategy is derived from the occupied segment of its
own display edge. Reflow, increment and removal compare that same segment before
and after the observation, using saved restore geometry rather than minimized
AX bounds. If saved geometry is unavailable, changed shared intervals require a
conservative repair. Unchanged segments and duplicate observations stay quiet;
wake remains an explicit repair boundary. This does not change screen-set
membership, memory selection, fallback placement or retry budgets.

## Evidence and diagnostics

Regression evidence must include the recovery-to-main-queue handoff, old merged
dwell versus newer explicit input, unavailable siblings, batch expansion through
merge reconciliation, and partial-edge adjacency changes through the live
coordinator. Injected boundaries do not prove physical AX completion or owner
perceptual acceptance.

Diagnostic packages record source, target, request revision, admission or refusal,
active/pending/deferred state, replay disposition, batch members and skipped
members, and geometry refresh reasons. Existing bounded machine-local logging
and privacy rules apply; no titles, keystrokes, content, capture or network use.
