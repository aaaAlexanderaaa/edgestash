# EdgeStash interaction and edge-state follow-up

Date: 2026-09-29. Scope: the uncommitted working tree at the time, following the
September 23 state-machine review. Translated from the original Chinese review;
findings and evidence describe that historical implementation.

Behavioral authority: `docs/contracts/edgestash.md`,
`docs/contracts/screen-set-and-window-life.md`, and
`docs/contracts/behavior-grammar.md`. Source and headless tests establish policy
and call paths, not native AX, Dock, Space, or multi-display experience.

## Repairs in this review

| Scenario | Finding and repair | Evidence |
|---|---|---|
| Duplicate display observations and failed restoration | Every observation immediately retried the same target, prematurely consuming the 1/2/4-second budget. `beginApplication` now retains an unchanged pending target without returning it early; `retryRestoration` owns timed retries. | `ScreenSetRestorationRetry`; twenty duplicate observations and three timed failures. |
| Duplicate observations and stable windows | Except for increment, the coordinator refreshed all present windows, repeatedly writing AX frame/alpha/minimized state for identical observations. Refresh is now required only for actual display frame, scale, or edge-adjacency changes; cancelled sessions still use `needsScreenSetRepair`. | `ScreenSetMemoryCoordinator.transition`; no-refresh assertions for identical observations. |
| Failed seam hover and the one-time explanation | Failed Space preparation or final validation automatically explained through `failSharedReveal`, including hover and 0.5-second polling. This interrupted pointer flow and consumed the explanation reserved for clicking a disabled signal. Failure still disables the marker; only marker click explains. | `StashSession.failSharedReveal`, `StashMarkerWindow.mouseDown`; presentation-anchor check. |
| Show-all across multiple apps | Owned activation retained only one global bundle. Interleaved A/B reveals could misclassify A's delayed callback as Dock/Cmd-Tab. Ownership is now recorded and consumed separately per bundle. | `OwnedActivationLedger`; interleaved callback tests. |
| Focus return after collapse | A 0.3-second callback could activate the remembered app after the user switched elsewhere. Return now requires the controlled app to remain frontmost; skipping also clears the old memory. | `FocusReturnPolicy.shouldReturnFocus`; unchanged/changed foreground cases. |

## Follow-up repairs on 2026-09-30

- Each failed restoration target now retains its own deadline. Duplicate display
  observations preserve remaining delay; the earliest timer retries only due
  targets. Interleaved one-second and four-second targets have independent tests.
- Collapsed windows resolve their destination display before deciding re-hide,
  change-edge, or detach. Cross-display hidden lips require positive-width
  overlap, avoiding false crossing at an exactly touching boundary.
- The complete expectation check passed using the 15.5 SDK and temporary SwiftPM
  sandbox arguments. Only CLT was installed; Xcode-project Debug and real
  multi-display AX review remained unavailable.

## Remaining gaps, ordered by experience impact

1. **Batch operations still shared one focus memory.** The global
   `StashFocusReturn.rememberedPID` could be overwritten by multi-app reveals and
   collapses; only the first delayed callback could consume it. The new foreground
   gate protected later app switches, but did not establish per-window focus
   return after show-all. Define native batch focus behavior before assigning
   ownership by operation batch.
2. **Show-all input coverage was incomplete.** The runtime observed only
   Control-Up/Control-Down. Trackpad gestures, the Mission Control key, and Dock
   show-all lacked reliable paths although the contract required them. Observe
   actual native events/AX identity before wiring them, so ordinary Space switches
   are not misclassified. Locations: `StashEngine.observeShowAllKeys` and
   `ShowAllWindowsKeyPolicy`.
3. **Dock thumbnail identity was uncertain.** `StashDock` read a title, and
   `StashEngine.applyActivation` selected the first same-title collapsed session.
   Duplicate documents or Terminal titles could open the wrong stash. Native Dock
   click/activation ordering was unverified. Locations: `StashDock.hit` and
   `StashEngine.applyActivation`.
4. **Shortcut precedence disagreed with the accepted contract.** The contract
   addressed every managed window of the app. If any idle window existed,
   `handleAppShortcut` captured one and returned, even when managed windows also
   existed. Tests explicitly preserved that behavior, but the contract did not
   declare it. The owner needed to choose existing-stash precedence or explicitly
   accept and expose desktop-window-first capture.
5. **Partial seam refresh was too broad.** `ScreenSetMemoryCoordinator` used
   adjacency of an entire edge to select refreshes. A new display touching a small
   interval could refresh other nonintersecting windows on that edge, although
   actual hide strategy already used each window's vertical interval. Refresh
   should use session geometry; unnecessary AX writes can cause visible jumps.

## Boundaries requiring native event sequences

- Repeated seam reveal/leave/reveal, Space changes concurrent with deminimization,
  full-screen-disabled markers, and compensation after rejected frame/minimize writes.
- Plug/unplug, clamshell, display-only power, and mirroring round trips; record
  notification order, enumeration, retry deadlines, and final AX frame/minimized/alpha.
- Whether Cmd-` skips transparent parked windows; no keyboard interception or
  native verification existed.
- Owner review of glass rails and focus behavior. Headless checks cannot establish
  a pixel-free lip, reachable markers, or continuous animation.

## Verification status at the time

- All twelve presentation anchors were declared; one cardinality was executable
  and eleven remained `structural-only`.
- The complete expectation check passed with `MacOSX15.5.sdk` and a temporary
  PATH wrapper adding `--disable-sandbox` to SwiftPM. Repository scripts were
  unchanged. The standalone logic suite also passed.
- Direct execution could not complete its behavioral portion: nested SwiftPM
  sandboxing was denied, and the default 26.0 SDK did not match the CLT compiler.
  These were environment failures, not failed behavioral assertions.
- Native Debug compilation with the 15.5 SDK lacked `NSGlassEffectView`; full
  Xcode was absent. The Xcode-project Debug gate remained open.
- No real AX or perceptual multi-display review was performed. No commit was
  made, and existing uncommitted changes were preserved.
