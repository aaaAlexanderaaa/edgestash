# Behavior grammar and the expectation check

This contract exists so EdgeStash states its own runtime behavior explicitly,
and so an agent (or a person) can verify code against that statement before
committing — instead of only running unit tests and declaring victory when the
build is green.

Running tests proves "the code does what the tests say." It does not prove "the
app does only what it is supposed to, the number of times it is supposed to."
The multi-window advice banner re-appearing every few seconds was green on every
unit test and still a bad experience. The grammar closes that gap.

## The grammar

Every runtime **effect** the app can produce — a popup, an overlay, an alert, a
system-facing mutation — is one production:

```
Effect ::= Trigger × Guards → Action @ Cardinality   [Suppression]
```

- **Trigger** — the event or call chain that can start it (a timer tick, a
  Space change, a hotkey, a drag, a preference change).
- **Guards** — the predicates that must hold (mostly `*Policy` checks in
  `Sources/EdgeStashLogic`).
- **Action** — the observable effect (present/hide a window, post, move/minimize
  a window).
- **Cardinality** — how many times / how often it may fire: once-per-launch,
  once-per-machine, per-session, every N seconds, and so on.
- **Suppression** — the dedup/mute/quiet state that enforces the cardinality,
  and *where it lives*.

The set of declared productions **is** the product's expected behavior. Anything
else is a deviation.

## The four deviations (all are failures)

An implementation is non-conforming — and the check fails — when any of these is
true. Each one is resolved deliberately, as either a code fix or a change to the
declared expectation (update this file):

1. **Should do, does not** — a declared effect has no implementation anchor
   (removed or renamed without updating the grammar).
2. **Should not do, does** — an effect is produced that no production declares
   (a new popup/overlay/alert appears out of the grammar).
3. **Does too much** — an effect fires more often than its declared cardinality
   (the banner re-presenting on every Space change is this class).
4. **Does too little** — a declared effect is gated so it can never fire when it
   should.

Classes 1–2 are checked structurally by the expectation checker against the
manifest below. Classes 3–4 are checked by executable behavioral property tests
in the AppKit-free layer (see `MultiWindowTipCoordinator` and its tests in
`Tests/EdgeStashLogicTests.swift`), which drive scripted event timelines and
assert the declared cardinality.

## The expectation check

`./scripts/check-expectations.sh` is the standing gate. It:

1. Scans `Sources/EdgeStash/**` for every user-facing presentation primitive
   (`orderFront`, `orderFrontRegardless`, `makeKeyAndOrderFront`, `EdgeAlert.run`,
   `runModal`) and requires each call site's enclosing `file:symbol` to be a
   declared anchor in the manifest — catching deviation classes 1 and 2.
2. Runs `swift run EdgeStashLogicTests`, which includes the cardinality property
   tests — catching deviation classes 3 and 4 for behavior whose decision logic
   lives in `EdgeStashLogic`.

It runs on Linux with no macOS dependency. Perceptual sign-off (how a surface
actually looks and animates on screen) is still an owner review on a Mac; the
grammar covers *whether and how often* an effect fires, not its pixels.

Run it whenever code is considered ready to commit:

```bash
./scripts/check-expectations.sh
```

## Extending the grammar

When you add or change a user-facing effect: add or edit its production in the
manifest, and — if its decision logic is not already in `EdgeStashLogic` — move
that logic into a headless coordinator/policy and cover its cardinality with a
property test. The single knob for the multi-window advice re-entry decision is
`MultiWindowTipCoordinator.renotifyOnReentryWithinLaunch` (currently `false`:
the advice is once-per-launch).

## Manifest (machine-readable)

The checker parses the pipe-separated rows between the markers below. Columns:
`effect_id | kind | anchor_file | anchor_symbol | cardinality | suppression | trigger`.

<!-- BEGIN grammar-manifest -->
```text
multi_window_tip | popup | Sources/EdgeStash/Overlay/StashMultiWindowTip.swift | present | once-per-launch | MultiWindowTipCoordinator.quietUntilRelaunch + Preferences.mutedMultiWindowAdvice | syncSessions 5s tick and post-capture
seam_limitation_explanation | popup | Sources/EdgeStash/Overlay/StashMarkerWindow.swift | showDisabledExplanation | once-per-machine | Preferences.advisedSeamRevealLimitation | click a disabled seam beacon
merge_overload_alert | alert | Sources/EdgeStash/Overlay/StashMergeCoordinator.swift | presentOverloadWarning | once-per-process | warnedOverload + Preferences.advisedStripOverload | reconcile when merge groups overload
rescue_needs_accessibility_alert | alert | Sources/EdgeStash/AppDelegate.swift | notifyPendingRescueNeedsAccessibility | once-per-launch | pending-dossier presence | launch with pending rescue and no Accessibility trust
modal_alert_engine | alert | Sources/EdgeStash/AppDelegate.swift | run | on-demand | caller-gated | EdgeAlert.run callers
settings_window | window | Sources/EdgeStash/AppDelegate.swift | showSettings | on-demand | user-invoked | menu, dock reopen, or launch without trust
settings_halo_preview | overlay | Sources/EdgeStash/Overlay/EdgeHaloWindow.swift | show | per-space-preview | HaloPreviewPolicy and settings visibility | Behavior tab edge selection
slide_sheen | overlay | Sources/EdgeStash/Overlay/StashEffectOverlay.swift | present | per-animation | StashMotionPolicy.shouldEmitVisualEffects | slide collapse or expand
stash_marker | overlay | Sources/EdgeStash/Overlay/StashMarkerWindow.swift | present | per-session | markerSuppressed and markerHiddenForSpace | session collapse or marker refresh
merge_strip | overlay | Sources/EdgeStash/Overlay/StashMergeStrip.swift | present | per-group | Preferences.mergesStrips and MergeGroupPolicy | merge reconcile
pin_control | overlay | Sources/EdgeStash/Overlay/StashPinWindow.swift | surface | hover-polled | PinControlPolicy.shouldShowControl | 0.1s leave timer while expanded
color_tint_picker | popup | Sources/EdgeStash/Settings/Controls/ColorMenus.swift | present | on-demand | user-invoked | settings custom color selection
```
<!-- END grammar-manifest -->
