import Foundation
import CoreGraphics
import EdgeStashLogic

@main
struct EdgeStashLogicTests {
    static func main() {
        var failed = 0

        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                fputs("FAIL: \(message)\n", stderr)
                failed += 1
            }
        }

        let hiddenLeft = CGRect(x: -799, y: 80, width: 800, height: 600)
        let visible = CGRect(x: 80, y: 80, width: 800, height: 600)
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let leftRecord = RescueMatching.Record(
            windowID: 42,
            edge: 1,
            visibleFrame: visible,
            displayFrame: display
        )

        func identify(_ record: RescueMatching.Record, among: [RescueMatching.Candidate])
            -> RescueMatching.Verdict {
            RescueMatching.identify(
                recordedNumber: record.windowID,
                recordedEdge: record.edge,
                recordedFrame: record.visibleFrame,
                recordedDisplay: record.displayFrame,
                among: among
            )
        }

        expect(
            identify(
                leftRecord,
                among: [
                    .init(windowID: 42, frame: hiddenLeft),
                    .init(windowID: 99, frame: hiddenLeft)
                ]
            ) == .matched(42),
            "the recorded window number wins even when another candidate looks hidden"
        )
        expect(
            identify(
                leftRecord,
                among: [
                    .init(windowID: nil, frame: hiddenLeft)
                ]
            ) == .unresolved,
            "missing windowID must not be treated as an exact match"
        )
        expect(
            identify(
                leftRecord,
                among: [
                    .init(windowID: 77, frame: hiddenLeft)
                ]
            ) == .matched(77),
            "a single plausible candidate can be adopted as the rescued window"
        )
        expect(
            identify(
                leftRecord,
                among: [
                    .init(windowID: 77, frame: hiddenLeft),
                    .init(windowID: 88, frame: hiddenLeft)
                ]
            ) == .unresolved,
            "two plausible candidates must not pick a window at random"
        )
        expect(
            identify(
                leftRecord,
                among: [
                    .init(windowID: 77, frame: visible)
                ]
            ) == .unresolved,
            "an on-screen window that is not the saved ID is not a fallback"
        )
        expect(
            RescueMatching.resemblesRecordedWindow(frame: hiddenLeft, record: leftRecord),
            "left-edge hidden frame with matching size is a plausible candidate"
        )
        expect(
            !RescueMatching.resemblesRecordedWindow(frame: visible, record: leftRecord),
            "visible on-screen frame is not a plausible hidden candidate"
        )
        expect(
            RescueMatching.recordIsSettled(
                moved: true,
                resized: true,
                alphaRestored: true,
                unminimized: true
            ),
            "rescue records clear only after visibility and frame restoration succeed"
        )
        expect(
            !RescueMatching.recordIsSettled(
                moved: false,
                resized: true,
                alphaRestored: true,
                unminimized: true
            ),
            "a size-only AX write must keep the rescue record"
        )
        expect(
            !RescueMatching.recordIsSettled(
                moved: true,
                resized: false,
                alphaRestored: true,
                unminimized: true
            ),
            "a position-only AX write must keep the rescue record"
        )
        expect(
            !RescueMatching.recordIsSettled(
                moved: true,
                resized: true,
                alphaRestored: false,
                unminimized: true
            ),
            "a failed alpha restore must keep the rescue record"
        )
        expect(
            !RescueMatching.recordIsSettled(
                moved: true,
                resized: true,
                alphaRestored: true,
                unminimized: false
            ),
            "a failed unminimize must keep the rescue record"
        )

        let rightRecord = RescueMatching.Record(
            windowID: 7,
            edge: 2,
            visibleFrame: CGRect(x: 1040, y: 0, width: 400, height: 400),
            displayFrame: display
        )
        expect(
            RescueMatching.resemblesRecordedWindow(
                frame: CGRect(x: 1439, y: 0, width: 402, height: 440),
                record: rightRecord
            ),
            "size drift inside the recorded-frame fraction stays eligible"
        )
        expect(
            !RescueMatching.resemblesRecordedWindow(
                frame: CGRect(x: 1439, y: 0, width: 402, height: 520),
                record: rightRecord
            ),
            "size drift beyond the recorded-frame fraction is rejected"
        )
        expect(
            !RescueMatching.resemblesRecordedWindow(
                frame: CGRect(x: 1380, y: 0, width: 400, height: 400),
                record: rightRecord
            ),
            "a window not flush with the display edge is not a rescue candidate"
        )
        expect(
            !RescueMatching.resemblesRecordedWindow(
                frame: CGRect(x: 1439, y: 400, width: 400, height: 400),
                record: rightRecord
            ),
            "a large vertical origin shift is rejected"
        )

        expect(
            SessionLifecyclePolicy.shouldRemoveManagerSession(for: .windowDestroyed),
            "closing a window must drop the manager session"
        )
        expect(
            !SessionLifecyclePolicy.shouldRemoveManagerSession(for: .miniaturized),
            "minimize must keep a regular session"
        )
        expect(
            SessionLifecyclePolicy.shouldRemoveManagerSession(for: .appDisabled),
            "disabling an app must remove its manager session"
        )
        expect(
            SessionLifecyclePolicy.syncEndEvent(
                stashActive: false,
                isTemporary: false,
                processStillRunning: true,
                windowRoleInvalid: false
            ) == .appDisabled,
            "periodic sync must drop a disabled non-temporary session"
        )
        expect(
            SessionLifecyclePolicy.syncEndEvent(
                stashActive: false,
                isTemporary: true,
                processStillRunning: true,
                windowRoleInvalid: false
            ) == nil,
            "periodic sync must keep a temporary session of a disabled app"
        )
        expect(
            SessionLifecyclePolicy.syncEndEvent(
                stashActive: true,
                isTemporary: false,
                processStillRunning: false,
                windowRoleInvalid: false
            ) == .appTerminated,
            "periodic sync must drop a session whose process is gone"
        )
        expect(
            SessionLifecyclePolicy.syncEndEvent(
                stashActive: true,
                isTemporary: false,
                processStillRunning: true,
                windowRoleInvalid: true
            ) == .windowDestroyed,
            "periodic sync must drop a session whose AX window is gone"
        )
        expect(
            SessionLifecyclePolicy.syncEndEvent(
                stashActive: true,
                isTemporary: false,
                processStillRunning: true,
                windowRoleInvalid: false
            ) == nil,
            "periodic sync must keep a live, enabled, still-valid session"
        )
        expect(
            SessionLifecyclePolicy.syncEndEvent(
                stashActive: false,
                isTemporary: false,
                processStillRunning: false,
                windowRoleInvalid: true
            ) == .appDisabled,
            "periodic sync classifies before it ends, so disable wins over gone-process"
        )
        expect(
            SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .windowDestroyed,
                restorePositionSucceeded: false,
                isFloating: false
            ),
            "destroyed windows must drop rescue records even if AX restore fails"
        )
        expect(
            !SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .appQuitting,
                restorePositionSucceeded: false,
                isFloating: false
            ),
            "quit must keep rescue records when restore fails"
        )
        expect(
            !SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .appDisabled,
                restorePositionSucceeded: false,
                isFloating: false
            ),
            "disabling an app must keep rescue records when restore fails"
        )
        expect(
            SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .appDisabled,
                restorePositionSucceeded: true,
                restoreAlphaSucceeded: true,
                isFloating: false
            ),
            "disabling an app clears rescue records after a successful restore"
        )
        expect(
            !SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .appDisabled,
                restorePositionSucceeded: true,
                restoreAlphaSucceeded: true,
                restoreUnminimizeSucceeded: false,
                isFloating: false
            ),
            "disabling an app must keep rescue records when unminimize fails"
        )
        expect(
            SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .appQuitting,
                restorePositionSucceeded: true,
                isFloating: false
            ),
            "quit must drop rescue records after a successful restore"
        )
        expect(
            !SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .appQuitting,
                restorePositionSucceeded: true,
                restoreAlphaSucceeded: false,
                isFloating: false
            ),
            "quit must keep rescue records when alpha restore fails"
        )
        expect(
            !SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .miniaturized,
                restorePositionSucceeded: false,
                isFloating: false
            ),
            "minimize must keep rescue records when position restore fails"
        )
        expect(
            SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .miniaturized,
                restorePositionSucceeded: true,
                isFloating: false
            ),
            "minimize must drop rescue records after a successful restore"
        )
        expect(
            !SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .miniaturized,
                restorePositionSucceeded: true,
                restoreAlphaSucceeded: false,
                isFloating: false
            ),
            "minimize must keep rescue records when alpha restore fails"
        )
        expect(
            SessionLifecyclePolicy.shouldRestoreVisibility(for: .miniaturized),
            "minimize must restore alpha/visibility"
        )
        expect(
            SessionLifecyclePolicy.shouldRestoreVisibility(for: .windowDestroyed) == false,
            "destroy does not need a visibility restore of a gone window"
        )
        expect(
            !SessionLifecyclePolicy.shouldRestoreVisibility(for: .detachedFromEdge),
            "dragging off the stash edge must keep the live window frame"
        )
        expect(
            SessionLifecyclePolicy.shouldRestoreAlpha(for: .detachedFromEdge),
            "a Mission Control drag off a collapsed stash must restore window alpha"
        )
        expect(
            SessionLifecyclePolicy.shouldClearDisplayBinding(for: .detachedFromEdge),
            "leaving a stash must forget the capture display so the next snap uses the window's new home"
        )
        expect(
            !SessionLifecyclePolicy.shouldClearDisplayBinding(for: .appQuitting),
            "quit restore keeps the recorded display until the window is back"
        )
        expect(
            !SessionLifecyclePolicy.shouldRemoveManagerSession(for: .detachedFromEdge),
            "a detached window stays as an idle session so it can snap again"
        )
        expect(
            SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .detachedFromEdge,
                restorePositionSucceeded: false,
                isFloating: false
            ),
            "manual detach owns the window; stash rescue records must drop"
        )

        expect(
            ManagedMinimizeNotificationPolicy.action(
                for: .miniaturized,
                phase: .collapsed,
                ownsCollapsedMinimize: true,
                revealInFlight: false,
                observedMinimized: true
            ) == .ignore,
            "the notification produced by an owned seam collapse must preserve the session"
        )
        expect(
            ManagedMinimizeNotificationPolicy.action(
                for: .miniaturized,
                phase: .collapsed,
                ownsCollapsedMinimize: false,
                revealInFlight: true,
                observedMinimized: false
            ) == .ignore,
            "the exact post-deminimize/pre-finish race must ignore the delayed collapse notification"
        )
        expect(
            ManagedMinimizeNotificationPolicy.action(
                for: .miniaturized,
                phase: .collapsed,
                ownsCollapsedMinimize: false,
                revealInFlight: true,
                observedMinimized: true
            ) == .ignore,
            "AX lag that still reports minimized during a seam reveal must not release the collapsed session"
        )
        expect(
            ManagedMinimizeNotificationPolicy.action(
                for: .miniaturized,
                phase: .collapsed,
                ownsCollapsedMinimize: false,
                revealInFlight: false,
                observedMinimized: true
            ) == .ignore,
            "a collapsed window that is still minimized is already parked; a late miniaturized notification cannot consume it"
        )
        expect(
            ManagedMinimizeNotificationPolicy.action(
                for: .miniaturized,
                phase: .expanded,
                ownsCollapsedMinimize: false,
                revealInFlight: false,
                observedMinimized: false
            ) == .ignore,
            "a delayed minimize notification after reveal must follow current AX state and stay harmless"
        )
        expect(
            ManagedMinimizeNotificationPolicy.action(
                for: .miniaturized,
                phase: .expanded,
                ownsCollapsedMinimize: false,
                revealInFlight: false,
                observedMinimized: nil
            ) == .ignore,
            "an unreadable AX minimized value cannot authorize destructive session release"
        )
        expect(
            ManagedMinimizeNotificationPolicy.action(
                for: .miniaturized,
                phase: .expanded,
                ownsCollapsedMinimize: false,
                revealInFlight: false,
                observedMinimized: true
            ) == .releaseSession,
            "a genuine external minimize of an expanded slide stash still releases the session"
        )
        expect(
            ManagedMinimizeNotificationPolicy.action(
                for: .miniaturized,
                phase: .expanded,
                ownsCollapsedMinimize: false,
                revealInFlight: false,
                observedMinimized: true,
                presentation: .systemMinimize
            ) == .recollapse,
            "minimize is the seam hide; an expanded seam window that miniaturizes must keep the session"
        )
        expect(
            ManagedMinimizeNotificationPolicy.action(
                for: .miniaturized,
                phase: .collapsed,
                ownsCollapsedMinimize: true,
                revealInFlight: false,
                observedMinimized: true,
                presentation: .systemMinimize
            ) == .ignore,
            "an owned seam collapse notification still cannot consume the session"
        )
        expect(
            ManagedMinimizeNotificationPolicy.action(
                for: .deminiaturized,
                phase: .collapsed,
                ownsCollapsedMinimize: true,
                revealInFlight: false,
                observedMinimized: false
            ) == .adoptSystemReveal,
            "a system-owned Dock restoration of a collapsed seam window is adopted"
        )
        expect(
            ManagedMinimizeNotificationPolicy.action(
                for: .deminiaturized,
                phase: .collapsed,
                ownsCollapsedMinimize: true,
                revealInFlight: true,
                observedMinimized: false
            ) == .ignore,
            "an EdgeStash reveal in flight owns its deminimize notification"
        )
        expect(
            ManagedMinimizeNotificationPolicy.action(
                for: .deminiaturized,
                phase: .collapsed,
                ownsCollapsedMinimize: true,
                revealInFlight: false,
                observedMinimized: true
            ) == .ignore,
            "a stale deminimize notification cannot reveal a window that is currently minimized"
        )

        var repeatedSeamSessionRemainsManaged = true
        for _ in 0..<100 {
            let ownedCollapse = ManagedMinimizeNotificationPolicy.action(
                for: .miniaturized,
                phase: .collapsed,
                ownsCollapsedMinimize: true,
                revealInFlight: false,
                observedMinimized: true
            )
            let delayedAfterReveal = ManagedMinimizeNotificationPolicy.action(
                for: .miniaturized,
                phase: .expanded,
                ownsCollapsedMinimize: false,
                revealInFlight: false,
                observedMinimized: false
            )
            if ownedCollapse == .releaseSession || delayedAfterReveal == .releaseSession {
                repeatedSeamSessionRemainsManaged = false
            }
        }
        expect(
            repeatedSeamSessionRemainsManaged,
            "100 owned collapse/reveal cycles must never consume the seam session"
        )

        // The 0.5s minimize poll and AX notifications are two observers of the
        // same hide. A poll that adopts "not minimized" during AX settle flips
        // the session to expanded; the delayed miniaturized notification then
        // looks like an external hide and used to release the beacon.
        expect(
            !SeamSessionDurabilityPolicy.shouldAdoptUnminimizedPoll(
                ownsCollapsedMinimize: true,
                elapsedSinceOwnedMinimize: 0.2,
                observedMinimized: false
            ),
            "AX lag right after an owned minimize must not be adopted as a Dock reveal"
        )
        expect(
            SeamSessionDurabilityPolicy.shouldAdoptUnminimizedPoll(
                ownsCollapsedMinimize: true,
                elapsedSinceOwnedMinimize: 1.6,
                observedMinimized: false
            ),
            "after settle, a still-unminimized collapsed seam window may be a missed Dock restore"
        )
        expect(
            !SeamSessionDurabilityPolicy.shouldAdoptUnminimizedPoll(
                ownsCollapsedMinimize: true,
                elapsedSinceOwnedMinimize: 2.0,
                observedMinimized: true
            ),
            "a poll that still sees minimized must not expand"
        )
        expect(
            !SeamSessionDurabilityPolicy.shouldAdoptUnminimizedPoll(
                ownsCollapsedMinimize: false,
                elapsedSinceOwnedMinimize: 2.0,
                observedMinimized: false
            ),
            "a session that no longer owns the hide cannot be expanded by the poll"
        )

        var deadlyPairKeepsSession = true
        for _ in 0..<100 {
            let pollDuringSettle = SeamSessionDurabilityPolicy.shouldAdoptUnminimizedPoll(
                ownsCollapsedMinimize: true,
                elapsedSinceOwnedMinimize: 0.4,
                observedMinimized: false
            )
            let lateMinimize = ManagedMinimizeNotificationPolicy.action(
                for: .miniaturized,
                phase: .expanded,
                ownsCollapsedMinimize: false,
                revealInFlight: false,
                observedMinimized: true,
                presentation: .systemMinimize
            )
            if pollDuringSettle || lateMinimize == .releaseSession {
                deadlyPairKeepsSession = false
            }
        }
        expect(
            deadlyPairKeepsSession,
            "100 poll-then-late-minimize sequences must keep a seam session"
        )

        expect(
            AppShortcutPolicy.resolvedScope(nil) == .allManagedWindows,
            "existing app settings must default dedicated shortcuts to all managed windows"
        )
        expect(
            AppShortcutPolicy.normalizedModifiers(
                AppShortcutPolicy.supportedModifierMask | (1 << 16) | (1 << 21) | (1 << 23)
            ) == AppShortcutPolicy.supportedModifierMask,
            "shortcut matching must discard Caps Lock, Function, and Numeric Pad flags"
        )
        expect(
            AppShortcutPolicy.resolvedScope(.recentWindow) == .recentWindow,
            "the per-app shortcut scope switch must preserve recent-window mode"
        )
        expect(
            AppShortcutPolicy.targetExpanded(
                hasVisibleWindow: true,
                hasHiddenWindow: true
            ) == false,
            "a mixed group must collapse all windows first"
        )
        expect(
            AppShortcutPolicy.targetExpanded(
                hasVisibleWindow: false,
                hasHiddenWindow: true
            ) == true,
            "a fully collapsed group must reveal all windows"
        )
        expect(
            AppShortcutPolicy.targetExpanded(
                hasVisibleWindow: true,
                hasHiddenWindow: false
            ) == false,
            "a floating app window must be collapsed by the first shortcut press"
        )
        expect(
            AppShortcutPolicy.targetExpanded(
                hasVisibleWindow: false,
                hasHiddenWindow: false
            ) == nil,
            "an app without windows has no shortcut target"
        )

        expect(
            LaunchAtLoginSync.publishedState(actualStatus: false) == false,
            "toggle must follow actual login-item status after a failed enable"
        )
        expect(
            LaunchAtLoginSync.publishedState(actualStatus: true) == true,
            "toggle must follow actual login-item status after a successful enable"
        )
        expect(
            LaunchAtLoginSync.resolvedInitialStatus(queriedExists: false, cachedStatus: true) == false,
            "startup must follow a missing login item, not a stale ON cache"
        )
        expect(
            LaunchAtLoginSync.resolvedInitialStatus(queriedExists: true, cachedStatus: false) == true,
            "startup must follow an existing login item, not a stale OFF cache"
        )
        expect(
            LaunchAtLoginSync.resolvedInitialStatus(queriedExists: nil, cachedStatus: true) == true,
            "startup may keep the cache only when the live query fails"
        )
        expect(
            LaunchAtLoginSync.resolvedInitialStatus(queriedExists: nil, cachedStatus: nil) == false,
            "startup stays off when there is no login item and no cache"
        )
        expect(
            LaunchAtLoginSync.parseExistsOutput("true\n") == true,
            "System Events true must parse as enabled"
        )
        expect(
            LaunchAtLoginSync.parseExistsOutput("false") == false,
            "System Events false must parse as disabled"
        )
        expect(
            LaunchAtLoginSync.parseExistsOutput("oops") == nil,
            "unrecognized login-item query output must not be treated as a real status"
        )
        expect(
            LaunchAtLoginSync.existsScript(itemName: "EdgeStash")
                .contains("login item \"EdgeStash\" exists"),
            "macOS 12 startup must query System Events for the EdgeStash login item"
        )

        let leftDisplay = DisplayGeometry(
            id: "left",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        let rightDisplay = DisplayGeometry(
            id: "right",
            frame: CGRect(x: 1920, y: 120, width: 1440, height: 900)
        )
        let sideBySideDisplays = [leftDisplay, rightDisplay]

        expect(
            DisplayEdgePolicy.hasAdjacentDisplay(
                at: .right,
                of: leftDisplay,
                in: sideBySideDisplays
            ),
            "the right edge of the left display must be detected as a shared boundary"
        )
        expect(
            DisplayEdgePolicy.hasAdjacentDisplay(
                at: .left,
                of: rightDisplay,
                in: sideBySideDisplays
            ),
            "the left edge of the right display must be detected as a shared boundary"
        )
        expect(
            !DisplayEdgePolicy.hasAdjacentDisplay(
                at: .left,
                of: leftDisplay,
                in: sideBySideDisplays
            ),
            "the outer left edge must remain available"
        )
        expect(
            DisplayEdgePolicy.adjacency(
                at: .right,
                of: leftDisplay,
                in: sideBySideDisplays
            ) == .partiallyShared,
            "different display heights must classify a shared edge as partial"
        )

        let defaultLeftSelection = DisplayEdgePolicy.defaultSelection(
            for: leftDisplay,
            in: sideBySideDisplays
        )
        expect(
            defaultLeftSelection == DisplayEdgeSelection(leftEnabled: true, rightEnabled: true),
            "safe defaults must enable exposed segments on a partially shared boundary"
        )

        let explicitPreferences = [
            leftDisplay.id: DisplayEdgeSelection(leftEnabled: false, rightEnabled: true)
        ]
        expect(
            DisplayEdgePolicy.resolvedSelection(
                for: leftDisplay,
                in: sideBySideDisplays,
                preferences: explicitPreferences
            ) == DisplayEdgeSelection(leftEnabled: false, rightEnabled: true),
            "an explicit per-display selection must override topology defaults"
        )

        let cornerOnlyDisplay = DisplayGeometry(
            id: "corner",
            frame: CGRect(x: 1920, y: 1080, width: 800, height: 600)
        )
        expect(
            !DisplayEdgePolicy.hasAdjacentDisplay(
                at: .right,
                of: leftDisplay,
                in: [leftDisplay, cornerOnlyDisplay]
            ),
            "displays touching only at one corner must not count as a shared boundary"
        )

        let portraitDisplay = DisplayGeometry(
            id: "portrait",
            frame: CGRect(x: 0, y: 0, width: 1080, height: 1920)
        )
        let landscapeDisplay = DisplayGeometry(
            id: "landscape",
            frame: CGRect(x: 1080, y: 420, width: 1920, height: 1080)
        )
        let mixedOrientationDisplays = [portraitDisplay, landscapeDisplay]
        expect(
            DisplayEdgePolicy.adjacency(
                at: .right,
                of: portraitDisplay,
                in: mixedOrientationDisplays
            ) == .partiallyShared,
            "a portrait edge beside a shorter landscape display must retain exposed segments"
        )
        expect(
            DisplayEdgePolicy.collapseStrategy(
                at: .right,
                of: portraitDisplay,
                windowFrame: CGRect(x: 380, y: 80, width: 700, height: 300),
                in: mixedOrientationDisplays
            ) == .slideOffscreen,
            "a window wholly inside the portrait display's exposed upper segment may slide away"
        )
        expect(
            DisplayEdgePolicy.collapseStrategy(
                at: .right,
                of: portraitDisplay,
                windowFrame: CGRect(x: 380, y: 300, width: 700, height: 300),
                in: mixedOrientationDisplays
            ) == .systemMinimize,
            "a window crossing into the physically shared segment must use system minimization"
        )
        expect(
            DisplayEdgePolicy.collapseStrategy(
                at: .right,
                of: portraitDisplay,
                windowFrame: CGRect(x: 380, y: 1560, width: 700, height: 300),
                in: mixedOrientationDisplays
            ) == .slideOffscreen,
            "a window wholly inside the portrait display's exposed lower segment may slide away"
        )

        let farLeftDisplay = DisplayGeometry(
            id: "far-left",
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        )
        let middleDisplay = DisplayGeometry(
            id: "middle",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        let farRightDisplay = DisplayGeometry(
            id: "far-right",
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        )
        let threeDisplays = [farLeftDisplay, middleDisplay, farRightDisplay]
        let middleBothEdgesEnabled = DisplayEdgePolicy.resolvedSelection(
            for: middleDisplay,
            in: threeDisplays,
            preferences: [
                middleDisplay.id: DisplayEdgeSelection(leftEnabled: true, rightEnabled: true)
            ]
        )

        expect(
            middleBothEdgesEnabled == DisplayEdgeSelection(leftEnabled: true, rightEnabled: true),
            "a user may explicitly enable both shared boundaries of the middle display"
        )
        expect(
            DisplayEdgePolicy.adjacency(
                at: .left,
                of: middleDisplay,
                in: threeDisplays
            ) == .fullyShared,
            "equal-height neighboring displays must classify the entire edge as shared"
        )
        expect(
            DisplayEdgePolicy.defaultSelection(
                for: middleDisplay,
                in: threeDisplays
            ) == DisplayEdgeSelection(leftEnabled: false, rightEnabled: false),
            "safe defaults must keep fully shared internal boundaries disabled"
        )

        expect(
            DisplayEdgePolicy.collapseStrategy(
                at: .left,
                of: middleDisplay,
                in: threeDisplays
            ) == .systemMinimize,
            "the middle display's left shared boundary must use system minimization"
        )
        expect(
            DisplayEdgePolicy.collapseStrategy(
                at: .right,
                of: middleDisplay,
                in: threeDisplays
            ) == .systemMinimize,
            "the middle display's right shared boundary must use system minimization"
        )
        expect(
            DisplayEdgePolicy.collapseStrategy(
                at: .left,
                of: farLeftDisplay,
                in: threeDisplays
            ) == .slideOffscreen,
            "the far-left physical boundary may continue using offscreen sliding"
        )
        expect(
            DisplayEdgePolicy.collapseStrategy(
                at: .right,
                of: farRightDisplay,
                in: threeDisplays
            ) == .slideOffscreen,
            "the far-right physical boundary may continue using offscreen sliding"
        )

        let idealPageWidth = SettingsSurfacePolicy.pageWidth(windowWidth: 920)
        let compactPageWidth = SettingsSurfacePolicy.pageWidth(windowWidth: 720)
        expect(
            idealPageWidth == 731,
            "a 920pt window minus the 188pt rail and 1pt divider is 731pt"
        )
        expect(
            !SettingsSurfacePolicy.stackHoverPreview(pageWidth: idealPageWidth),
            "the default 920pt settings window must keep hover sliders beside the visualizer"
        )
        expect(
            !SettingsSurfacePolicy.stackHoverPreview(pageWidth: 732),
            "a page that is exactly 920 minus rail must stay side-by-side"
        )
        expect(
            SettingsSurfacePolicy.stackHoverPreview(pageWidth: compactPageWidth),
            "the 720pt minimum window must stack the hover visualizer"
        )
        expect(
            SettingsSurfacePolicy.uniquedBundleIDsPreservingOrder(["a.b", "c.d", "a.b"]) == ["a.b", "c.d"],
            "duplicate bundle IDs must keep the first row only"
        )
        expect(
            SettingsSurfacePolicy.uniquedBundleIDsPreservingOrder(["one"]) == ["one"],
            "a single bundle ID stays as one row"
        )
        expect(
            SettingsSurfacePolicy.uniquedBundleIDsPreservingOrder([]) == [],
            "an empty running-app list stays empty"
        )

        let sharedOnLeftRight = DisplayEdgePolicy.sharedIntervals(
            at: .right,
            of: leftDisplay,
            in: sideBySideDisplays
        )
        expect(
            sharedOnLeftRight.count == 1
                && sharedOnLeftRight[0].lowerBound == 120
                && sharedOnLeftRight[0].upperBound == 1020,
            "partial share must expose the overlapping Y interval"
        )
        expect(
            DisplayEdgePolicy.sharedIntervals(
                at: .left,
                of: leftDisplay,
                in: sideBySideDisplays
            ).isEmpty,
            "an outer edge has no shared intervals"
        )
        expect(
            DisplayArrangementPolicy.previewKind(
                at: .left,
                of: leftDisplay,
                in: sideBySideDisplays,
                selection: DisplayEdgeSelection(leftEnabled: true, rightEnabled: true)
            ) == .slideOffscreen,
            "an enabled outer edge previews as slide-off"
        )
        expect(
            DisplayArrangementPolicy.previewKind(
                at: .right,
                of: leftDisplay,
                in: sideBySideDisplays,
                selection: DisplayEdgeSelection(leftEnabled: true, rightEnabled: true)
            ) == .slideOffscreen,
            "a partially shared edge keeps a slide preview on its exposed intervals"
        )
        expect(
            DisplayArrangementPolicy.previewKind(
                at: .right,
                of: leftDisplay,
                in: sideBySideDisplays,
                selection: DisplayEdgeSelection(leftEnabled: true, rightEnabled: false)
            ) == .disabled,
            "a disabled edge previews as disabled even when shared"
        )
        expect(
            DisplayArrangementPolicy.previewKind(
                at: .left,
                of: middleDisplay,
                in: threeDisplays,
                selection: middleBothEdgesEnabled
            ) == .systemMinimize,
            "a fully shared edge previews as minimize across its whole length"
        )

        let mapSlots = DisplayArrangementPolicy.fittedSlots(
            displays: sideBySideDisplays,
            canvas: CGSize(width: 400, height: 200),
            padding: 10
        )
        let leftSlot = mapSlots.first { $0.id == leftDisplay.id }
        let rightSlot = mapSlots.first { $0.id == rightDisplay.id }
        expect(mapSlots.count == 2, "two displays produce two map slots")
        expect(
            leftSlot != nil && rightSlot != nil && leftSlot!.canvasFrame.midX < rightSlot!.canvasFrame.midX,
            "logical left display must stay left of the neighbor on the map"
        )
        expect(
            leftSlot != nil && rightSlot != nil && leftSlot!.canvasFrame.height > rightSlot!.canvasFrame.height,
            "a taller logical display must draw taller on the map"
        )
        expect(
            DisplayArrangementPolicy.fittedSlots(
                displays: [],
                canvas: CGSize(width: 400, height: 200)
            ).isEmpty,
            "no displays produce an empty map"
        )

        expect(
            StashSessionPolicy.phase(after: .capture, from: .idle) == .captured,
            "idle accepts a capture into ownership"
        )
        expect(
            !StashSessionPolicy.isWindowDrag(
                from: CGRect(x: 10, y: 20, width: 800, height: 600),
                to: CGRect(x: 10.4, y: 20.4, width: 800, height: 600)
            ),
            "sub-point AX rounding after a click must not arm edge capture"
        )
        expect(
            StashSessionPolicy.isWindowDrag(
                from: CGRect(x: 10, y: 20, width: 800, height: 600),
                to: CGRect(x: 11, y: 20, width: 800, height: 600)
            ),
            "a deliberate one-point window translation is a capture drag"
        )
        expect(
            StashSessionPolicy.phase(after: .collapse, from: .captured) == .collapsed,
            "a captured window can collapse"
        )
        expect(
            StashSessionPolicy.phase(after: .expand, from: .captured) == .expanded,
            "a captured window can expand without collapsing first"
        )
        expect(
            StashSessionPolicy.phase(after: .expand, from: .collapsed) == .expanded,
            "collapsed reveals into expanded"
        )
        expect(
            StashSessionPolicy.phase(after: .collapse, from: .expanded) == .collapsed,
            "expanded can collapse again"
        )
        expect(
            StashSessionPolicy.phase(after: .release, from: .captured) == .idle,
            "release from captured returns to idle"
        )
        expect(
            StashSessionPolicy.phase(after: .release, from: .collapsed) == .idle,
            "release from collapsed returns to idle"
        )
        expect(
            StashSessionPolicy.phase(after: .release, from: .expanded) == .idle,
            "release from expanded returns to idle"
        )
        expect(
            StashSessionPolicy.phase(after: .collapse, from: .idle) == nil,
            "idle cannot collapse; the engine must capture first"
        )
        expect(
            StashSessionPolicy.phase(after: .expand, from: .idle) == nil,
            "idle cannot expand"
        )
        expect(
            StashSessionPolicy.phase(after: .capture, from: .collapsed) == nil,
            "an already-stashed window is not captured again"
        )
        expect(
            StashSessionPolicy.phase(after: .capture, from: .expanded) == nil,
            "an expanded stash is not recaptured"
        )

        expect(
            StashSessionPolicy.canCapture(
                edge: .left,
                snapSide: "both",
                blockedDockSide: nil,
                edgeEnabled: true
            ),
            "an enabled left edge with both-sides snap is capturable"
        )
        expect(
            !StashSessionPolicy.canCapture(
                edge: .right,
                snapSide: "left",
                blockedDockSide: nil,
                edgeEnabled: true
            ),
            "snap-side left must refuse the right edge"
        )
        expect(
            !StashSessionPolicy.canCapture(
                edge: .left,
                snapSide: "both",
                blockedDockSide: "left",
                edgeEnabled: true
            ),
            "a Dock-occupied left edge is not capturable"
        )
        expect(
            !StashSessionPolicy.canCapture(
                edge: .right,
                snapSide: "both",
                blockedDockSide: nil,
                edgeEnabled: false
            ),
            "a disabled display edge is not capturable"
        )
        expect(
            StashSessionPolicy.snapSideAllows(edge: .left, snapSide: "left"),
            "left-only snap allows the left edge"
        )
        expect(
            !StashSessionPolicy.snapSideAllows(edge: .left, snapSide: "right"),
            "right-only snap refuses the left edge"
        )

        expect(
            StashSessionPolicy.collapsePresentation(
                at: .left,
                of: farLeftDisplay,
                windowFrame: nil,
                in: threeDisplays
            ) == .slideOffscreen,
            "an outer edge presents as slide-off"
        )
        expect(
            StashSessionPolicy.collapsePresentation(
                at: .left,
                of: middleDisplay,
                windowFrame: nil,
                in: threeDisplays
            ) == .systemMinimize,
            "a fully shared seam presents as system minimize"
        )
        expect(
            StashSessionPolicy.collapsePresentation(
                at: .right,
                of: portraitDisplay,
                windowFrame: CGRect(x: 380, y: 80, width: 700, height: 300),
                in: mixedOrientationDisplays
            ) == .slideOffscreen,
            "an exposed segment of a partial share still slides off"
        )
        expect(
            StashSessionPolicy.collapsePresentation(
                at: .right,
                of: portraitDisplay,
                windowFrame: CGRect(x: 380, y: 300, width: 700, height: 300),
                in: mixedOrientationDisplays
            ) == .systemMinimize,
            "the shared segment of a partial share must minimize, not slide onto the neighbor"
        )
        expect(
            StashSessionPolicy.shouldReleaseAfterTopologyChange(
                current: .slideOffscreen,
                next: .systemMinimize,
                displayStillPresent: true
            ),
            "a seam that flips from slide-off to minimize must restore the window"
        )
        expect(
            StashSessionPolicy.shouldReleaseAfterTopologyChange(
                current: .systemMinimize,
                next: .slideOffscreen,
                displayStillPresent: true
            ),
            "a seam that stops being shared must release the minimized stash"
        )
        expect(
            !StashSessionPolicy.shouldReleaseAfterTopologyChange(
                current: .slideOffscreen,
                next: .slideOffscreen,
                displayStillPresent: true
            ),
            "an unchanged outer edge keeps its stash"
        )
        expect(
            StashSessionPolicy.shouldReleaseAfterTopologyChange(
                current: .slideOffscreen,
                next: .slideOffscreen,
                displayStillPresent: false
            ),
            "a disconnected display must restore its stashes"
        )
        expect(
            StashSessionPolicy.shouldRestorePriorFrame(didMoveToExpanded: true, minimizeSucceeded: false),
            "a failed shared-edge minimize must move the window back"
        )
        expect(
            !StashSessionPolicy.shouldRestorePriorFrame(didMoveToExpanded: true, minimizeSucceeded: true),
            "a successful minimize keeps the snapped frame"
        )
        expect(
            !StashSessionPolicy.shouldRestorePriorFrame(didMoveToExpanded: false, minimizeSucceeded: false),
            "if the window was never moved, there is nothing to restore"
        )
        expect(
            !FocusReturnPolicy.shouldReleaseAfterExpand(fromDock: false),
            "a user unminimize must not return focus to the previous app"
        )
        expect(
            FocusReturnPolicy.shouldReleaseAfterExpand(fromDock: true),
            "a Dock reveal may still release focus after expanding"
        )
        expect(
            StashSessionPolicy.shouldDetachAfterOffEdgeMove(isPinned: false, stillOnEdge: false),
            "an unpinned expanded window that leaves the edge is released"
        )
        expect(
            !StashSessionPolicy.shouldDetachAfterOffEdgeMove(isPinned: true, stillOnEdge: false),
            "a pinned window may be dragged off the edge without ending the session"
        )
        expect(
            !StashSessionPolicy.shouldDetachAfterOffEdgeMove(isPinned: false, stillOnEdge: true),
            "a window still on the stash edge stays managed"
        )
        expect(
            StashSessionPolicy.shouldReleaseCollapsedAfterExternalMove(
                isCollapsed: true,
                isBusy: false,
                stillParkedOnOwningEdge: false
            ),
            "Mission Control may drag a collapsed window off its parked edge; release it"
        )
        expect(
            !StashSessionPolicy.shouldReleaseCollapsedAfterExternalMove(
                isCollapsed: true,
                isBusy: true,
                stillParkedOnOwningEdge: false
            ),
            "an in-flight collapse slide is not an external move"
        )
        expect(
            !StashSessionPolicy.shouldReleaseCollapsedAfterExternalMove(
                isCollapsed: true,
                isBusy: false,
                stillParkedOnOwningEdge: true
            ),
            "a collapsed window that is still parked stays managed"
        )
        expect(
            StashSessionPolicy.shouldIgnoreGeometryMove(
                screenSetQuiet: true,
                owningDisplayConnected: true
            ),
            "a screen-set quiet period must not treat a system move as a user drag"
        )
        expect(
            StashSessionPolicy.shouldIgnoreGeometryMove(
                screenSetQuiet: false,
                owningDisplayConnected: false
            ),
            "a vanished owning display must not treat the system move as a user drag"
        )
        expect(
            !StashSessionPolicy.shouldDetachAfterOffEdgeMove(
                isPinned: false,
                stillOnEdge: false,
                owningDisplayConnected: false
            ),
            "an expanded stash whose display vanished stays managed until screen-set policy runs"
        )
        expect(
            !StashSessionPolicy.shouldReleaseCollapsedAfterExternalMove(
                isCollapsed: true,
                isBusy: false,
                stillParkedOnOwningEdge: false,
                screenSetQuiet: true
            ),
            "a collapsed stash must not release while the screen set is settling or sleeping"
        )
        expect(
            !FocusReturnPolicy.shouldReleaseAfterLeaveCollapse(didCollapse: false),
            "failed auto-collapse must not return focus to another app"
        )
        expect(
            !FocusReturnPolicy.shouldReleaseAfterLeaveCollapse(didCollapse: true),
            "leave collapse must not return focus before the slide finishes"
        )
        expect(
            FocusReturnPolicy.shouldReleaseAfterLeaveCollapse(didCollapse: true, slideFinished: true),
            "successful leave collapse may return focus after the slide finishes"
        )
        expect(
            MultiWindowTipPolicy.shouldPresent(
                collapsedCount: 2,
                suppressedPermanently: false,
                suppressedThisLaunch: false,
                alreadyVisible: false
            ),
            "two collapsed windows of one app show the multi-window tip"
        )
        expect(
            !MultiWindowTipPolicy.shouldPresent(
                collapsedCount: 1,
                suppressedPermanently: false,
                suppressedThisLaunch: false,
                alreadyVisible: false
            ),
            "a single collapsed window does not show the tip"
        )
        expect(
            !MultiWindowTipPolicy.shouldPresent(
                collapsedCount: 3,
                suppressedPermanently: true,
                suppressedThisLaunch: false,
                alreadyVisible: false
            ),
            "don't show again after the user chooses never"
        )

        expect(
            HaloPreviewPolicy.shouldClear(settingsTabIsBehavior: true, settingsWindowVisible: true) == false,
            "halo stays while Behavior is open"
        )
        expect(
            HaloPreviewPolicy.shouldClear(settingsTabIsBehavior: false, settingsWindowVisible: true),
            "halo ends when Settings leaves Behavior"
        )
        expect(
            HaloPreviewPolicy.shouldClear(settingsTabIsBehavior: true, settingsWindowVisible: false),
            "halo ends when the Settings window closes"
        )

        let primaryHeight: CGFloat = 900
        let appKit = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let quartz = StashGeometryPolicy.cgRect(fromAppKit: appKit, primaryHeight: primaryHeight)
        expect(quartz.minY == 0 && quartz.height == 900, "primary AppKit frame maps to quartz origin 0")
        expect(
            StashGeometryPolicy.appKitRect(fromQuartz: quartz, primaryHeight: primaryHeight) == appKit,
            "quartz and AppKit conversion must round-trip the primary frame"
        )

        let leftHidden = StashGeometryPolicy.visualHiddenOrigin(
            edge: .left,
            frame: CGRect(x: 0, y: 80, width: 800, height: 600),
            display: CGRect(x: 0, y: 0, width: 1440, height: 900),
            lockedWidth: 800
        )
        expect(
            leftHidden.x == 0 - 800 + StashGeometryPolicy.edgeLip,
            "slide-off keeps the two-point lip on the owning display"
        )
        let rightHidden = StashGeometryPolicy.visualHiddenOrigin(
            edge: .right,
            frame: CGRect(x: 640, y: 80, width: 800, height: 600),
            display: CGRect(x: 0, y: 0, width: 1440, height: 900),
            lockedWidth: 800
        )
        expect(
            rightHidden.x == 1440 - StashGeometryPolicy.edgeLip,
            "right slide-off keeps the lip inside the owning display"
        )

        expect(
            StashGeometryPolicy.barThickness == 5
                && StashGeometryPolicy.outerPanelWidth == 11
                && StashGeometryPolicy.seamPanelWidth == 9
                && StashGeometryPolicy.haloThickness == 5
                && StashGeometryPolicy.captureBand == 42,
            "glass rails are 5pt in 11/9pt panels; capture band stays 42 so snap feel does not widen"
        )
        expect(
            StashGeometryPolicy.tintStrength(kind: .outerStrip, enabled: true) == 1
                && StashGeometryPolicy.tintStrength(kind: .seamBeacon, enabled: true) == 0.5
                && StashGeometryPolicy.tintStrength(kind: .seamBeacon, enabled: false) == 0.28,
            "outer is full tint; seam is half; disabled seam is quieter still"
        )

        let seamLeft = StashGeometryPolicy.markerPanelFrame(
            kind: .seamBeacon,
            edge: .left,
            windowQuartz: CGRect(x: 0, y: 80, width: 800, height: 600),
            displayAppKit: CGRect(x: 0, y: 0, width: 1440, height: 900),
            primaryHeight: 900
        )
        expect(
            seamLeft.minX >= 0 && seamLeft.maxX <= 1440 && seamLeft.width == 9,
            "seam beacon must stay on the owning AppKit display as a 9pt panel"
        )
        let seamRail = StashGeometryPolicy.visibleRailRect(
            kind: .seamBeacon,
            edge: .left,
            in: CGRect(x: 0, y: 0, width: seamLeft.width, height: 200)
        )
        expect(
            seamRail.minX == 2 && seamRail.width == 5,
            "seam glass starts 2pt inside the seam and is 5pt thick"
        )
        let gap = StashGeometryPolicy.seamInnerGapRect(in: seamRail)
        expect(
            abs(gap.midX - seamRail.midX) < 0.01 && gap.width == 1 && gap.height > 0,
            "seam distinction is a 1pt slit down the long axis"
        )
        let outerLeft = StashGeometryPolicy.markerPanelFrame(
            kind: .outerStrip,
            edge: .left,
            windowQuartz: CGRect(x: 0, y: 80, width: 800, height: 600),
            displayAppKit: CGRect(x: 0, y: 0, width: 1440, height: 900),
            primaryHeight: 900
        )
        let outerRail = StashGeometryPolicy.visibleRailRect(
            kind: .outerStrip,
            edge: .left,
            in: CGRect(origin: .zero, size: outerLeft.size)
        )
        expect(
            outerLeft.width == 11 && outerRail.width == 5 && outerLeft.minX + outerRail.minX == 1,
            "outer glass keeps 1pt on-screen clearance in an 11pt panel"
        )
        let haloLeft = StashGeometryPolicy.haloBand(
            edge: .left,
            displayAppKit: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        expect(haloLeft.width == 5, "Settings halo previews the 5pt rail")
        let haloRight = StashGeometryPolicy.haloBand(
            edge: .right,
            displayAppKit: CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        )
        expect(
            haloRight.maxX == 1440 + 1920 && haloRight.minX >= 1440,
            "halo sits on the selected display edge and ignores mouse by window flag, not by sitting on a neighbor"
        )

        let captureDisplay = DisplayGeometry(id: "main", frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        expect(
            StashGeometryPolicy.preferredCaptureEdge(
                windowFrame: CGRect(x: 10, y: 80, width: 800, height: 600),
                display: captureDisplay,
                snapSide: "both",
                blockedDockSide: nil,
                selection: DisplayEdgeSelection(leftEnabled: true, rightEnabled: true)
            ) == .left,
            "a window against the left edge is capturable on the left"
        )
        expect(
            StashGeometryPolicy.preferredCaptureEdge(
                windowFrame: CGRect(x: 200, y: 80, width: 800, height: 600),
                display: captureDisplay,
                snapSide: "both",
                blockedDockSide: nil,
                selection: DisplayEdgeSelection(leftEnabled: true, rightEnabled: true)
            ) == nil,
            "a centered window is not a drag-to-edge capture"
        )
        expect(
            StashGeometryPolicy.nearestAllowedEdge(
                windowFrame: CGRect(x: 200, y: 80, width: 800, height: 600),
                display: captureDisplay,
                snapSide: "both",
                blockedDockSide: nil,
                selection: DisplayEdgeSelection(leftEnabled: true, rightEnabled: true)
            ) == .left,
            "a first-press shortcut still stashes a centered window to the nearer edge"
        )

        let hitSlots = [
            DisplayArrangementSlot(id: "a", canvasFrame: CGRect(x: 10, y: 10, width: 80, height: 40)),
            DisplayArrangementSlot(id: "b", canvasFrame: CGRect(x: 100, y: 20, width: 60, height: 30))
        ]
        let leftHit = StashGeometryPolicy.hitMapEdge(at: CGPoint(x: 12, y: 20), slots: hitSlots)
        expect(leftHit?.displayID == "a" && leftHit?.edge == .left, "map left-edge hit selects that display")
        let rightHit = StashGeometryPolicy.hitMapEdge(at: CGPoint(x: 158, y: 30), slots: hitSlots)
        expect(rightHit?.displayID == "b" && rightHit?.edge == .right, "map right-edge hit selects that display")
        expect(
            StashGeometryPolicy.hitMapEdge(at: CGPoint(x: 50, y: 20), slots: hitSlots) == nil,
            "the interior of a map rectangle is not an edge hit"
        )

        let dockScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let measuredBottom = DockHitPolicy.hitRect(
            screenFrame: dockScreen,
            side: "bottom",
            measurement: DockMeasurement(depth: 92)
        )
        expect(measuredBottom != nil && measuredBottom!.height == 92, "a measured Dock depth is used exactly")
        expect(
            (measuredBottom?.width ?? 0) < dockScreen.width,
            "an unmeasured Dock extent must not claim the full screen width"
        )
        let centeredRun = DockHitPolicy.hitRect(
            screenFrame: dockScreen,
            side: "bottom",
            measurement: DockMeasurement(depth: 92, extent: 600, extentMidpoint: 500)
        )
        expect(
            centeredRun?.minX == 200 && centeredRun?.maxX == 800,
            "a measured extent places the corridor around its midpoint"
        )
        expect(
            DockHitPolicy.hitRect(screenFrame: dockScreen, side: "top", measurement: DockMeasurement(depth: 92)) == nil,
            "an unknown Dock side has no hit rect"
        )
        let parkedBottom = DockHitPolicy.hitRect(
            screenFrame: dockScreen,
            side: "bottom",
            measurement: DockMeasurement(revealsOnApproach: true)
        )
        expect(
            parkedBottom != nil && parkedBottom!.height < measuredBottom!.height,
            "a parked Dock claims only the reveal sliver"
        )
        let unknownBottom = DockHitPolicy.hitRect(
            screenFrame: dockScreen,
            side: "bottom",
            measurement: DockMeasurement()
        )
        expect(
            unknownBottom != nil && unknownBottom!.height < dockScreen.height / 4 + 1,
            "an unmeasured depth falls back to a bounded fraction of the axis"
        )
        let leftDock = DockHitPolicy.hitRect(
            screenFrame: dockScreen,
            side: "left",
            measurement: DockMeasurement(depth: 70)
        )
        expect(
            leftDock != nil && leftDock!.minX == 0 && leftDock!.width == 70,
            "a left Dock corridor hugs the display edge at the measured depth"
        )

        expect(
            StashMotionPolicy.shouldAnimate(reduceMotion: false),
            "full motion animates the slide"
        )
        expect(
            !StashMotionPolicy.shouldAnimate(reduceMotion: true),
            "reduced motion jumps instead of sliding"
        )
        expect(StashMotionPolicy.span(reduceMotion: true, collapsing: false) == 0, "reduced motion duration is zero")
        expect(
            StashMotionPolicy.span(reduceMotion: false, collapsing: true, merged: true)
                == StashMotionPolicy.mergedSpan,
            "a merged strip uses the shorter merged span"
        )
        expect(
            StashMotionPolicy.easedProgress(0) == 0 && StashMotionPolicy.easedProgress(1) == 1,
            "the slide easing starts and ends on the endpoints"
        )
        expect(
            StashMotionPolicy.easedProgress(0.5) == 0.5,
            "the symmetric easing passes through the midpoint"
        )
        expect(
            StashMotionPolicy.easedProgress(0.25) < 0.25 && StashMotionPolicy.easedProgress(0.75) > 0.75,
            "the easing is slow at both ends and fast in the middle"
        )
        expect(
            StashMotionPolicy.interpolated(from: 0, to: 100, eased: 0.5) == 50,
            "eased interpolation is a linear mix of the endpoints"
        )
        expect(
            StashMotionPolicy.writeInterval(linkPeriod: nil) == 1.0 / StashMotionPolicy.maxWriteRate,
            "an unknown refresh period falls back to the write ceiling"
        )
        expect(
            StashMotionPolicy.writeInterval(linkPeriod: 1.0 / 120.0) == 1.0 / StashMotionPolicy.maxWriteRate,
            "a 120Hz link is capped at the write ceiling"
        )
        expect(
            StashMotionPolicy.writeInterval(linkPeriod: 1.0 / 48.0) == 1.0 / 48.0,
            "a slow link writes once per tick instead of faster"
        )
        expect(
            StashMotionPolicy.stallPause(
                writeSeconds: 0.01,
                budget: 1.0 / 90.0,
                pausedSoFar: 0,
                span: StashMotionPolicy.revealSpan
            ) == 0,
            "a write inside its budget pauses nothing"
        )
        let pause = StashMotionPolicy.stallPause(
            writeSeconds: 0.05,
            budget: 1.0 / 90.0,
            pausedSoFar: 0,
            span: StashMotionPolicy.revealSpan
        )
        expect(pause > 0, "a blocked write pauses the motion clock")
        let ceiling = StashMotionPolicy.revealSpan * StashMotionPolicy.stallFraction
        expect(
            StashMotionPolicy.stallPause(
                writeSeconds: 0.05,
                budget: 1.0 / 90.0,
                pausedSoFar: ceiling,
                span: StashMotionPolicy.revealSpan
            ) == 0,
            "pauses stop once the stall allowance is spent"
        )
        expect(
            StashMotionPolicy.shouldWriteSize(writeIndex: 0, finished: false),
            "the first write asserts the locked size"
        )
        expect(
            !StashMotionPolicy.shouldWriteSize(writeIndex: 1, finished: false)
                && !StashMotionPolicy.shouldWriteSize(writeIndex: 2, finished: false),
            "intermediate writes skip the size when on stride"
        )
        expect(
            StashMotionPolicy.shouldWriteSize(writeIndex: StashMotionPolicy.sizeWriteStride, finished: false),
            "every third write re-asserts the locked size"
        )
        expect(
            StashMotionPolicy.shouldWriteSize(writeIndex: 7, finished: true),
            "the final write always re-asserts the locked size"
        )

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let overlappingA = MergeMember(
            id: "a",
            edge: .left,
            screenFrame: screen,
            visibleMinY: 100,
            visibleMaxY: 400,
            windowHeight: 300,
            title: "Notes"
        )
        let overlappingB = MergeMember(
            id: "b",
            edge: .left,
            screenFrame: screen,
            visibleMinY: 300,
            visibleMaxY: 700,
            windowHeight: 400,
            title: "Mail"
        )
        let separateC = MergeMember(
            id: "c",
            edge: .left,
            screenFrame: screen,
            visibleMinY: 720,
            visibleMaxY: 860,
            windowHeight: 140,
            title: "Calendar"
        )
        let rightEdge = MergeMember(
            id: "d",
            edge: .right,
            screenFrame: screen,
            visibleMinY: 100,
            visibleMaxY: 400,
            windowHeight: 300,
            title: "Safari"
        )
        let fused = MergeGroupPolicy.groups(from: [overlappingA, overlappingB, separateC, rightEdge])
        expect(fused.count == 1, "only overlapping same-edge markers form a merged group")
        expect(
            fused.first.map { Set($0.members.map(\.id)) } == Set(["a", "b"]),
            "the fused pair is the overlapping pair"
        )
        expect(
            MergeGroupPolicy.groups(from: [overlappingA]).isEmpty,
            "a single marker is not a merged group"
        )
        expect(
            MergeGroupPolicy.suppressedIDs(in: fused) == Set(["a", "b"]),
            "individual markers hide while they belong to a merged group"
        )
        expect(
            !MergeGroupPolicy.shouldWarnOverload(fused),
            "two members do not trip the overload warning"
        )
        var crowd: [MergeMember] = []
        for index in 0..<12 {
            let offset = CGFloat(index * 8)
            crowd.append(
                MergeMember(
                    id: "w\(index)",
                    edge: .right,
                    screenFrame: screen,
                    visibleMinY: 100 + offset,
                    visibleMaxY: 460 + offset,
                    windowHeight: 360,
                    title: "App \(index)"
                )
            )
        }
        expect(
            MergeGroupPolicy.shouldWarnOverload(MergeGroupPolicy.groups(from: crowd)),
            "segments squeezed below a comfortable hit target should warn once"
        )
        var roomy: [MergeMember] = []
        for index in 0..<12 {
            let offset = CGFloat(index * 40)
            roomy.append(
                MergeMember(
                    id: "r\(index)",
                    edge: .right,
                    screenFrame: screen,
                    visibleMinY: 100 + offset,
                    visibleMaxY: 460 + offset,
                    windowHeight: 360,
                    title: "App \(index)"
                )
            )
        }
        expect(
            !MergeGroupPolicy.shouldWarnOverload(MergeGroupPolicy.groups(from: roomy)),
            "the same count with roomier segments does not warn"
        )
        let strip = MergeGroupPolicy.layout(group: fused[0], labelWidths: [80, 90])
        expect(strip != nil && strip!.segments.count == 2, "a fused pair lays out two segments")
        expect(
            strip != nil && strip!.panelFrame.height <= screen.height,
            "the merged panel stays on the owning display"
        )
        expect(
            strip != nil
                && strip!.mouseOpaqueFrame.width == MergeGroupPolicy.mouseOpaqueWidth
                && strip!.panelFrame.width >= MergeGroupPolicy.minimumPanelWidth,
            "mouse-opaque merge geometry is the 21pt hit band; 240pt is label reservation only"
        )
        expect(
            strip.flatMap { MergeGroupPolicy.hitSegment(at: CGPoint(x: $0.hitRect.maxX + 40, y: $0.hitRect.midY), layout: $0) } == nil,
            "a point in the reserved label column is not a merge hit"
        )
        let compact = strip.map { MergeGroupPolicy.presentation(layout: $0, showingLabels: false) }
        expect(
            compact != nil
                && compact!.windowFrame == strip!.mouseOpaqueFrame
                && compact!.windowFrame.width == MergeGroupPolicy.mouseOpaqueWidth
                && abs(compact!.hitRect.minX) < 0.01,
            "without labels the window collapses to the hit band"
        )
        let labeled = strip.map { MergeGroupPolicy.presentation(layout: $0, showingLabels: true) }
        expect(
            labeled != nil
                && labeled!.windowFrame == strip!.panelFrame
                && labeled!.hitRect == strip!.hitRect,
            "hover labels keep the reserved panel; hit rect stays panel-local"
        )
        expect(
            strip.map { MergeGroupPolicy.hitSegment(at: $0.segments[0].slotRect.origin, layout: $0) } == "a"
                || strip.map { MergeGroupPolicy.hitSegment(at: CGPoint(x: $0.segments[0].slotRect.midX, y: $0.segments[0].slotRect.midY), layout: $0) } != nil,
            "a point inside a segment slot selects that session"
        )
        expect(
            MergeGroupPolicy.activeAfterReconcile(expandedIDs: ["b", "a"], preferred: "b") == "b",
            "an already-expanded preferred session stays the active merged segment"
        )
        expect(
            MergeGroupPolicy.activeAfterReconcile(expandedIDs: ["a"], preferred: "missing") == "a",
            "a stale preferred id falls back to an expanded member"
        )

        let expandedWindow = CGRect(x: 0, y: 200, width: 800, height: 500)
        let pinFrames = PinControlPolicy.frames(
            edge: .left,
            windowAppKit: expandedWindow,
            screenAppKit: screen
        )
        expect(
            pinFrames.buttonFrame.maxX <= screen.maxX
                && pinFrames.buttonFrame.minX >= expandedWindow.maxX,
            "a left-edge stash parks the pin on the free right side"
        )
        expect(
            PinControlPolicy.shouldReveal(isPinned: true, mouseInTrigger: false, mouseInSafe: false),
            "a pinned window keeps the pin control visible"
        )
        expect(
            !PinControlPolicy.shouldReveal(isPinned: false, mouseInTrigger: false, mouseInSafe: false),
            "an unpinned window hides the pin until the mouse enters the corner"
        )
        expect(
            !PinControlPolicy.shouldAutoCollapse(isPinned: true),
            "a pinned stash must not collapse on leave"
        )
        expect(
            PinControlPolicy.shouldShowControl(isExpanded: true, isPinned: false, isBusy: false)
                && !PinControlPolicy.shouldShowControl(isExpanded: false, isPinned: false, isBusy: false),
            "the pin appears on an expanded stash, not a collapsed one"
        )

        expect(
            CarbonHotkeyPolicy.carbonModifiers(fromNSEvent: 1 << 20) == CarbonHotkeyPolicy.command,
            "Command maps to Carbon cmdKey"
        )
        expect(
            CarbonHotkeyPolicy.carbonModifiers(fromNSEvent: (1 << 20) | (1 << 17))
                == CarbonHotkeyPolicy.command | CarbonHotkeyPolicy.shift,
            "Command-Shift maps to Carbon cmdKey+shiftKey"
        )
        expect(
            CarbonHotkeyPolicy.carbonModifiers(fromNSEvent: (1 << 20) | (1 << 16))
                == CarbonHotkeyPolicy.command,
            "Caps Lock is stripped before Carbon registration"
        )

        expect(
            TemporaryShortcutPolicy.canBegin(
                frontBundleID: "com.apple.Notes",
                selfBundleID: "top.whatif.edgestash",
                isRegular: true
            ),
            "temporary shortcut may stash a front window that is not on the enabled list"
        )
        expect(
            !TemporaryShortcutPolicy.canBegin(
                frontBundleID: "top.whatif.edgestash",
                selfBundleID: "top.whatif.edgestash",
                isRegular: true
            ),
            "temporary shortcut must not stash EdgeStash itself"
        )
        expect(
            !TemporaryShortcutPolicy.shouldKeepAfterIdle(stashActive: false),
            "an unconfigured temporary session is discarded when it returns to idle"
        )
        expect(
            TemporaryShortcutPolicy.shouldKeepAfterIdle(stashActive: true),
            "a configured app keeps its session after a temporary chord"
        )

        expect(
            FocusReturnPolicy.shouldSchedule(settingsIsKey: false),
            "focus returns after a Dock reveal when Settings is not key"
        )
        expect(
            !FocusReturnPolicy.shouldSchedule(settingsIsKey: true),
            "do not hide or deactivate Settings to release focus"
        )
        expect(
            FocusReturnPolicy.isEligibleTarget(
                candidateBundleID: "com.apple.finder",
                selfBundleID: "top.whatif.edgestash",
                candidatePID: 2,
                sourcePID: 1,
                candidateIsCollapsedManaged: false
            ),
            "Finder is a valid focus-return target"
        )
        expect(
            !FocusReturnPolicy.isEligibleTarget(
                candidateBundleID: "com.apple.dock",
                selfBundleID: "top.whatif.edgestash",
                candidatePID: 3,
                sourcePID: 1,
                candidateIsCollapsedManaged: false
            ),
            "the Dock itself is not a content target"
        )
        expect(
            !FocusReturnPolicy.isEligibleTarget(
                candidateBundleID: "com.apple.Notes",
                selfBundleID: "top.whatif.edgestash",
                candidatePID: 4,
                sourcePID: 1,
                candidateIsCollapsedManaged: true
            ),
            "a still-collapsed managed window is not a focus-return target"
        )

        expect(
            AppShortcutPolicy.shouldCaptureIdleFrontWindow(
                hasIdleWindow: true,
                hasManagedWindow: true
            ),
            "a shortcut must still stash an idle window when another is already managed"
        )
        expect(
            !AppShortcutPolicy.shouldCaptureIdleFrontWindow(
                hasIdleWindow: false,
                hasManagedWindow: true
            ),
            "a shortcut with no idle window falls through to managed toggle"
        )
        expect(
            SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .accessibilityLost,
                restorePositionSucceeded: true,
                restoreAlphaSucceeded: true,
                isFloating: false
            ),
            "a successful restore after trust loss must clear the rescue dossier"
        )
        expect(
            !SessionLifecyclePolicy.shouldClearRescueRecords(
                for: .accessibilityLost,
                restorePositionSucceeded: false,
                isFloating: false
            ),
            "a failed restore after trust loss must keep the rescue dossier"
        )
        expect(
            SessionLifecyclePolicy.shouldUninstallObservers(for: .accessibilityLost),
            "trust loss must tear down per-window AX observers"
        )
        expect(
            SessionLifecyclePolicy.shouldRemoveManagerSession(for: .accessibilityLost),
            "trust loss must drop sessions so they are rediscovered after grant"
        )
        expect(
            SessionLifecyclePolicy.shouldRecoverOnSubjectLaunch(
                launchedBundleID: "com.example.safari",
                pendingSubjectBundleIDs: ["com.example.safari"]
            ),
            "a later app launch must retry pending rescue"
        )
        expect(
            !SessionLifecyclePolicy.shouldRecoverOnSubjectLaunch(
                launchedBundleID: "com.example.mail",
                pendingSubjectBundleIDs: ["com.example.safari"]
            ),
            "an unrelated app launch must not recover live collapsed dossiers"
        )
        expect(
            !SessionLifecyclePolicy.shouldRecoverOnSubjectLaunch(
                launchedBundleID: nil,
                pendingSubjectBundleIDs: ["com.example.safari"]
            ),
            "a launch without a bundle id must not sweep every pending dossier"
        )
        expect(
            !SessionLifecyclePolicy.shouldRestoreRescueRecord(
                processID: 77,
                windowNumber: 42,
                liveHolds: [
                    .init(processID: 77, windowNumber: 42)
                ]
            ),
            "a live managed session must keep its crash dossier until it ends"
        )
        expect(
            !SessionLifecyclePolicy.shouldRestoreRescueRecord(
                processID: 77,
                windowNumber: 42,
                liveHolds: [
                    .init(processID: 77, windowNumber: nil)
                ]
            ),
            "an unresolved live session of the same process still owns its dossier"
        )
        expect(
            SessionLifecyclePolicy.shouldRestoreRescueRecord(
                processID: 77,
                windowNumber: 42,
                liveHolds: [
                    .init(processID: 88, windowNumber: 42)
                ]
            ),
            "a relaunched process may restore the recorded window"
        )
        expect(
            SessionLifecyclePolicy.shouldRestoreRescueRecord(
                processID: 77,
                windowNumber: 99,
                liveHolds: [
                    .init(processID: 77, windowNumber: 42)
                ]
            ),
            "a sibling window of the same process may still be rescued"
        )
        expect(
            !SessionLifecyclePolicy.shouldRecoverOnPreferenceChange(),
            "preference updates must not run rescue against live collapsed sessions"
        )
        expect(
            SessionEventTapPolicy.shouldReenableTap(type: .tapDisabledByTimeout),
            "a timeout-disabled session tap must be turned back on"
        )
        expect(
            SessionEventTapPolicy.shouldReenableTap(type: .tapDisabledByUserInput),
            "a user-input-disabled session tap must be turned back on"
        )
        expect(
            !SessionEventTapPolicy.shouldReenableTap(type: .leftMouseDown),
            "ordinary mouse-down must not be treated as a tap-disable event"
        )
        expect(
            SessionMouseRelayPolicy.shouldAccept(
                kind: .down,
                buttonPressed: true,
                lastAccepted: nil
            ),
            "the first physical press must start a capture gesture"
        )
        expect(
            !SessionMouseRelayPolicy.shouldAccept(
                kind: .down,
                buttonPressed: true,
                lastAccepted: .down
            ),
            "tap and monitor copies of the same press must not restart the gesture"
        )
        expect(
            SessionMouseRelayPolicy.shouldAccept(
                kind: .up,
                buttonPressed: false,
                lastAccepted: .down
            ),
            "mouse-up must complete the press that started the gesture"
        )
        expect(
            !SessionMouseRelayPolicy.shouldAccept(
                kind: .up,
                buttonPressed: false,
                lastAccepted: .up
            ),
            "a leftover mouse-up must not abort in-flight capture retries"
        )
        expect(
            !SessionMouseRelayPolicy.shouldAccept(
                kind: .down,
                buttonPressed: false,
                lastAccepted: .up
            ),
            "a late tap mouse-down after release must not arm a new gesture"
        )
        expect(
            SessionMouseRelayPolicy.shouldAccept(
                kind: .down,
                buttonPressed: true,
                lastAccepted: .up
            ),
            "a real second press after release must start a new gesture"
        )

        let collapseLeft = DisplayGeometry(id: "L", frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let collapseRight = DisplayGeometry(id: "R", frame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
        expect(
            StashSessionPolicy.displayForCollapse(
                sessionDisplayID: "L",
                intersectionDisplayID: "R",
                displays: [collapseLeft, collapseRight]
            )?.id == "L",
            "collapse must keep the capture display when the frame straddles a seam"
        )
        expect(
            StashSessionPolicy.displayForCollapse(
                sessionDisplayID: nil,
                intersectionDisplayID: nil,
                displays: [collapseLeft, collapseRight]
            ) == nil,
            "a window that matches no display must not default to the first/primary screen"
        )
        expect(
            !StashSessionPolicy.captureRecheckDelays().isEmpty,
            "mouse-up capture must re-read the AX frame after it can settle"
        )
        expect(
            StashSessionPolicy.captureSessionIndex(
                hitWindowID: 42,
                hitPID: 7,
                sessions: [
                    .init(windowID: 42, pid: 7),
                    .init(windowID: 99, pid: 7)
                ]
            ) == 0,
            "an exact window number wins the capture hit"
        )
        expect(
            StashSessionPolicy.captureSessionIndex(
                hitWindowID: 42,
                hitPID: 7,
                sessions: [
                    .init(windowID: nil, pid: 7)
                ]
            ) == 0,
            "a unique idle session may capture even before AX reports a window number"
        )
        expect(
            StashSessionPolicy.captureSessionIndex(
                hitWindowID: 42,
                hitPID: 7,
                sessions: [
                    .init(windowID: nil, pid: 7),
                    .init(windowID: nil, pid: 7)
                ]
            ) == nil,
            "two window-number-less sessions of the same process must not guess"
        )
        expect(
            StashSessionPolicy.captureSessionIndex(
                hitWindowID: 42,
                hitPID: 7,
                sessions: [
                    .init(windowID: nil, pid: 7),
                    .init(windowID: 42, pid: 7)
                ]
            ) == 1,
            "an exact window number still wins when a sibling has no number yet"
        )
        expect(
            StashSessionPolicy.captureSessionIndex(
                hitWindowID: 42,
                hitPID: 7,
                sessions: [
                    .init(windowID: nil, pid: 8)
                ]
            ) == nil,
            "a missing window number on a different process is not a capture hit"
        )
        expect(
            MultiWindowTipPolicy.shouldMuteUntilRelaunch(after: .timedOut),
            "a timed-out multi-window tip must stay quiet until relaunch"
        )
        expect(
            MultiWindowTipPolicy.shouldMuteUntilRelaunch(after: .remindLater),
            "remind-later must mute the multi-window tip until relaunch"
        )
        expect(
            !MultiWindowTipPolicy.shouldMuteUntilRelaunch(after: .neverAgain),
            "never-again is a permanent preference, not a launch mute"
        )

        let pointerDisplay = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let capturedWindow = CGRect(x: 0, y: 80, width: 800, height: 600)
        expect(
            StashGeometryPolicy.pointerAllowsEdgeCapture(
                mouse: CGPoint(x: 400, y: 200),
                edge: .left,
                displayFrame: pointerDisplay,
                windowFrame: capturedWindow
            ),
            "a title-bar drag onto the edge must capture even when the pointer is over the window"
        )
        expect(
            StashGeometryPolicy.pointerAllowsEdgeCapture(
                mouse: CGPoint(x: 10, y: 10),
                edge: .left,
                displayFrame: pointerDisplay,
                windowFrame: capturedWindow
            ),
            "a pointer still on the bezel must keep allowing capture"
        )
        expect(
            !StashGeometryPolicy.pointerAllowsEdgeCapture(
                mouse: CGPoint(x: 900, y: 10),
                edge: .left,
                displayFrame: pointerDisplay,
                windowFrame: capturedWindow
            ),
            "a pointer far from both the window and the edge must not confirm capture"
        )
        expect(
            StashGeometryPolicy.owningDisplay(
                for: CGRect(x: -800, y: 80, width: 800, height: 600),
                in: [collapseLeft, collapseRight],
                preferredID: "L"
            )?.id == "L",
            "a fully off-screen window must not attach to a zero-overlap neighbor"
        )
        expect(
            StashGeometryPolicy.owningDisplay(
                for: CGRect(x: -800, y: 80, width: 800, height: 600),
                in: [collapseLeft, collapseRight]
            ) == nil,
            "an unmatched off-screen window must not fall back to the primary/middle display"
        )

        let seamLeftWindow = CGRect(x: 640, y: 80, width: 800, height: 600)
        let seamRightWindow = CGRect(x: 1440, y: 80, width: 800, height: 600)
        expect(
            StashGeometryPolicy.owningDisplay(
                for: seamLeftWindow,
                in: [collapseLeft, collapseRight]
            )?.id == "L",
            "a window sitting on the right side of the left display belongs to the left display"
        )
        expect(
            StashGeometryPolicy.owningDisplay(
                for: seamRightWindow,
                in: [collapseLeft, collapseRight]
            )?.id == "R",
            "a window sitting on the left side of the right display belongs to the right display"
        )

        let flippedOntoNeighbor = CGRect(x: 1438, y: 80, width: 800, height: 600)
        expect(
            StashGeometryPolicy.owningDisplay(
                for: flippedOntoNeighbor,
                in: [collapseLeft, collapseRight],
                preferredID: "L"
            )?.id == "L",
            "a window parked off the left display's right seam must keep the capture display"
        )
        expect(
            StashGeometryPolicy.owningDisplay(
                for: CGRect(x: 1600, y: 80, width: 800, height: 600),
                in: [collapseLeft, collapseRight],
                preferredID: "L"
            )?.id == "R",
            "moving a window fully onto another display must rebind ownership"
        )

        let parkedOffLeft = CGRect(
            x: collapseLeft.frame.minX - 800 + StashGeometryPolicy.edgeLip,
            y: 80,
            width: 800,
            height: 600
        )
        expect(
            StashGeometryPolicy.isStillOnStashEdge(
                frame: parkedOffLeft,
                display: collapseLeft.frame,
                edge: .left,
                presentation: .slideOffscreen
            ),
            "a window parked off the exposed edge with only its lip inside is still stashed"
        )
        expect(
            !StashGeometryPolicy.isStillOnStashEdge(
                frame: CGRect(x: 200, y: 80, width: 800, height: 600),
                display: collapseLeft.frame,
                edge: .left,
                presentation: .slideOffscreen
            ),
            "dragging the parked window inland is no longer parked"
        )
        expect(
            StashGeometryPolicy.isStillOnStashEdge(
                frame: CGRect(x: 200, y: 80, width: 800, height: 600),
                display: collapseLeft.frame,
                edge: .right,
                presentation: .systemMinimize
            ),
            "a minimized seam stash has no parked frame to verify"
        )
        expect(
            MultiWindowTipPolicy.shouldHideOnSpaceChange(),
            "Mission Control / space changes must dismiss the floating multi-window tip"
        )
        expect(
            MultiWindowTipPolicy.shouldDismiss(collapsedCount: 1),
            "the tip must hide once the app no longer has multiple collapsed windows"
        )
        expect(
            !MultiWindowTipPolicy.shouldDismiss(collapsedCount: 2),
            "two collapsed windows may keep a visible tip until it times out"
        )

        let pinWindow = CGRect(x: 100, y: 100, width: 400, height: 300)
        let leavePinFrames = PinControlPolicy.frames(
            edge: .left,
            windowAppKit: pinWindow,
            screenAppKit: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        expect(
            PinControlPolicy.pointerBlocksAutoCollapse(
                mouseAppKit: CGPoint(x: leavePinFrames.buttonFrame.midX, y: leavePinFrames.buttonFrame.midY),
                windowAppKit: pinWindow,
                gateSpanX: 32,
                gateSpanY: 32,
                triggerRect: leavePinFrames.triggerRect,
                safeRect: leavePinFrames.safeRect
            ),
            "moving onto the pin must not auto-collapse the expanded stash"
        )
        expect(
            HaloPreviewPolicy.shouldForgetTarget(
                settingsTabIsBehavior: false,
                settingsWindowVisible: true
            ),
            "leaving Behavior must forget the halo target, not only hide it"
        )
        expect(
            LaunchAtLoginSync.publishedState(enabled: false, requiresApproval: true),
            "a login item waiting for approval must keep the toggle on"
        )
        expect(
            CarbonHotkeyPolicy.shouldExcludeFromEventMonitor(carbonHandlerInstalled: true),
            "Carbon-backed chords skip the NSEvent path only when the handler is live"
        )
        expect(
            !CarbonHotkeyPolicy.shouldExcludeFromEventMonitor(carbonHandlerInstalled: false),
            "failed Carbon install must fall back to the NSEvent monitor"
        )
        expect(
            DockHitPolicy.shouldExpandActivatedApp(
                clickedBundleID: "com.apple.Safari",
                activatedBundleID: "com.apple.Notes",
                pointerStillInDock: true
            ) == false,
            "a Dock click for Safari must not expand Notes"
        )
        expect(
            DockHitPolicy.shouldExpandActivatedApp(
                clickedBundleID: nil,
                activatedBundleID: "com.apple.Safari",
                pointerStillInDock: true
            ),
            "when the Dock icon cannot be identified, expand only if the pointer is still on the Dock"
        )
        expect(
            RescueMatching.shouldSkipRestoreBecauseAlreadyVisible(
                frame: CGRect(x: 80, y: 80, width: 800, height: 600),
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ),
            "rescue must not teleport a window that is already fully on-screen"
        )
        expect(
            !RescueMatching.shouldSkipRestoreBecauseAlreadyVisible(
                frame: CGRect(x: -799, y: 80, width: 800, height: 600),
                display: CGRect(x: 0, y: 0, width: 1440, height: 900)
            ),
            "a parked off-screen window still needs rescue"
        )
        expect(
            !PreferencePublicationPolicy.shouldPublishSideEffects(isHydrating: true),
            "hydration must not post preference notifications that re-enter the singleton"
        )
        expect(
            PreferencePublicationPolicy.shouldPublishSideEffects(isHydrating: false),
            "after load, user-facing preference writes may persist and notify"
        )
        expect(
            SpaceChangePolicy.shouldPresentSeamLimitationExplanation(alreadyAdvised: false),
            "the first blocked seam reveal must explain why the window stays put"
        )
        expect(
            !SpaceChangePolicy.shouldPresentSeamLimitationExplanation(alreadyAdvised: true),
            "later blocked reveals stay silent; the disabled beacon is enough"
        )

        let approachLeft = DisplayGeometry(id: "AL", frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let approachRight = DisplayGeometry(id: "AR", frame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
        let approachDisplays = [approachLeft, approachRight]
        let leftSeamStash = SeamApproachSegment(
            id: "left-stash",
            displayID: "AL",
            edge: .right,
            minY: 100,
            maxY: 700
        )
        expect(
            SeamApproachPolicy.target(
                pointer: CGPoint(x: 1440 - SeamApproachPolicy.bandWidth, y: 400),
                segments: [leftSeamStash],
                displays: approachDisplays
            ) == "left-stash",
            "a gentle approach at the inner edge of the band reaches the seam beacon"
        )
        expect(
            SeamApproachPolicy.target(
                pointer: CGPoint(x: 1440 - 1, y: 400),
                segments: [leftSeamStash],
                displays: approachDisplays
            ) == "left-stash",
            "a pointer hugging the seam reaches the beacon"
        )
        expect(
            SeamApproachPolicy.target(
                pointer: CGPoint(x: 1440 + SeamApproachPolicy.overshoot, y: 400),
                segments: [leftSeamStash],
                displays: approachDisplays
            ) == "left-stash",
            "a slight overshoot past the seam still reaches the beacon"
        )
        expect(
            SeamApproachPolicy.target(
                pointer: CGPoint(x: 1440 + SeamApproachPolicy.overshoot + 1, y: 400),
                segments: [leftSeamStash],
                displays: approachDisplays
            ) == nil,
            "a pointer deep on the neighbor display is not an approach"
        )
        expect(
            SeamApproachPolicy.target(
                pointer: CGPoint(x: 1440 - SeamApproachPolicy.bandWidth - 1, y: 400),
                segments: [leftSeamStash],
                displays: approachDisplays
            ) == nil,
            "a pointer inland of the band does not reach the beacon"
        )
        expect(
            SeamApproachPolicy.target(
                pointer: CGPoint(x: 1440 - 1, y: 701),
                segments: [leftSeamStash],
                displays: approachDisplays
            ) == nil,
            "a pointer beyond the beacon's vertical span does not reach it"
        )
        let rightSeamStash = SeamApproachSegment(
            id: "right-stash",
            displayID: "AR",
            edge: .left,
            minY: 100,
            maxY: 700
        )
        expect(
            SeamApproachPolicy.target(
                pointer: CGPoint(x: 1440 + 6, y: 400),
                segments: [leftSeamStash, rightSeamStash],
                displays: approachDisplays
            ) == "right-stash",
            "when both sides of a seam host stashes, the display holding the pointer wins"
        )
        expect(
            SeamApproachPolicy.target(
                pointer: CGPoint(x: 1440 - 6, y: 400),
                segments: [leftSeamStash, rightSeamStash],
                displays: approachDisplays
            ) == "left-stash",
            "the owning side of the seam wins on its own display"
        )
        expect(
            SeamApproachPolicy.target(
                pointer: CGPoint(x: 1440, y: 400),
                segments: [leftSeamStash, rightSeamStash],
                displays: approachDisplays
            ) == "right-stash",
            "on the exact seam line the right display contains the pointer (maxX is exclusive)"
        )
        expect(
            SeamApproachPolicy.target(
                pointer: CGPoint(x: 1440 - 1, y: 400),
                segments: [leftSeamStash],
                displays: []
            ) == nil,
            "a segment whose display vanished has no band"
        )

        let leaveNow = Date()
        expect(
            LeaveCollapsePolicy.countsAsInside(
                geometricallyOutside: false,
                pointerInSibling: false,
                siblingFocused: false,
                lastSiblingInteractionAt: nil,
                now: leaveNow
            ),
            "inside the geometric buffer always counts as inside"
        )
        expect(
            LeaveCollapsePolicy.countsAsInside(
                geometricallyOutside: true,
                pointerInSibling: true,
                siblingFocused: false,
                lastSiblingInteractionAt: nil,
                now: leaveNow
            ),
            "the pointer over a sibling window of the same app is not leaving"
        )
        expect(
            LeaveCollapsePolicy.countsAsInside(
                geometricallyOutside: true,
                pointerInSibling: false,
                siblingFocused: true,
                lastSiblingInteractionAt: nil,
                now: leaveNow
            ),
            "a focused sibling window means the app is still in use"
        )
        expect(
            LeaveCollapsePolicy.countsAsInside(
                geometricallyOutside: true,
                pointerInSibling: false,
                siblingFocused: false,
                lastSiblingInteractionAt: leaveNow.addingTimeInterval(-1.0),
                now: leaveNow
            ),
            "the post-interaction grace still counts as inside"
        )
        expect(
            !LeaveCollapsePolicy.countsAsInside(
                geometricallyOutside: true,
                pointerInSibling: false,
                siblingFocused: false,
                lastSiblingInteractionAt: leaveNow.addingTimeInterval(-2.0),
                now: leaveNow
            ),
            "an expired sibling grace no longer blocks the leave"
        )
        expect(
            !LeaveCollapsePolicy.shouldCollapse(outsideSince: nil, now: leaveNow),
            "no outside sample means no collapse"
        )
        expect(
            !LeaveCollapsePolicy.shouldCollapse(
                outsideSince: leaveNow.addingTimeInterval(-0.1),
                now: leaveNow
            ),
            "a brief excursion outside the buffer must not collapse the window"
        )
        expect(
            LeaveCollapsePolicy.shouldCollapse(
                outsideSince: leaveNow.addingTimeInterval(-0.3),
                now: leaveNow
            ),
            "collapse only after the pointer stays outside for the whole dwell"
        )

        expect(
            !SpaceChangePolicy.shouldHideMarkerDuringSpaceTransition(
                presentation: .systemMinimize,
                isCollapsed: true
            ),
            "a collapsed seam beacon must not be dismissed for the 0.7s Space settle"
        )
        expect(
            SpaceChangePolicy.shouldHideMarkerDuringSpaceTransition(
                presentation: .slideOffscreen,
                isCollapsed: true
            ),
            "a slide-stash marker still hides during Space transition geometry"
        )
        expect(
            SpaceChangePolicy.shouldHideMarkerDuringSpaceTransition(
                presentation: .systemMinimize,
                isCollapsed: false
            ),
            "an expanded seam marker still rebuilds after a Space switch"
        )
        expect(
            SpaceChangePolicy.shouldShowMarker(
                presentation: .systemMinimize,
                windowOnActiveSpace: false,
                isCollapsed: true
            ),
            "a display-anchored seam beacon stays visible across Spaces"
        )
        expect(
            !SpaceChangePolicy.shouldShowMarker(
                presentation: .systemMinimize,
                windowOnActiveSpace: false,
                isCollapsed: false
            ),
            "an expanded seam window does not leave a foreign-Space beacon behind"
        )
        expect(
            SpaceChangePolicy.shouldShowMarker(
                presentation: .slideOffscreen,
                windowOnActiveSpace: true
            ),
            "a slide stash shows its marker on the Space that owns the parked window"
        )
        expect(
            !SpaceChangePolicy.shouldShowMarker(
                presentation: .slideOffscreen,
                windowOnActiveSpace: false
            ),
            "a slide stash's marker must not follow onto a foreign Space"
        )
        expect(
            SpaceChangePolicy.seamAvailability(
                transportAvailable: true,
                currentSpaceID: 42,
                currentSpaceType: 0
            ) == .ready(spaceID: 42),
            "an ordinary user Space is an enabled display-anchored destination"
        )
        expect(
            SpaceChangePolicy.seamAvailability(
                transportAvailable: true,
                currentSpaceID: 42,
                currentSpaceType: 4
            ) == .disabledFullScreen,
            "native full-screen keeps the beacon visible but disabled"
        )
        expect(
            SpaceChangePolicy.seamAvailability(
                transportAvailable: false,
                currentSpaceID: 42,
                currentSpaceType: 0
            ) == .unavailable,
            "missing runtime transport fails closed"
        )
        expect(
            !SpaceChangePolicy.shouldBeginSeamDwell(availability: .disabledFullScreen),
            "a disabled full-screen beacon cannot start a hover dwell"
        )
        expect(
            SpaceChangePolicy.seamRevealPreparation(
                availability: .ready(spaceID: 42),
                membershipQuerySucceeded: true,
                windowOnTargetSpace: true
            ) == .reveal,
            "same-Space membership needs no migration"
        )
        expect(
            SpaceChangePolicy.seamRevealPreparation(
                availability: .ready(spaceID: 42),
                membershipQuerySucceeded: true,
                windowOnTargetSpace: false
            ) == .migrate(to: 42),
            "a different-Space window migrates before reveal"
        )
        expect(
            SpaceChangePolicy.seamRevealPreparation(
                availability: .ready(spaceID: 42),
                membershipQuerySucceeded: false,
                windowOnTargetSpace: false
            ) == .refuse,
            "an unreadable membership refuses reveal rather than activating first"
        )
        expect(
            SpaceChangePolicy.seamRevealPreparation(
                availability: .disabledFullScreen,
                membershipQuerySucceeded: true,
                windowOnTargetSpace: false
            ) == .refuse,
            "native full-screen is never a migration target"
        )
        expect(
            SpaceChangePolicy.mayCommitSeamReveal(
                targetSpaceID: 42,
                currentDisplaySpaceID: 42,
                membershipConfirmed: true
            ),
            "confirmed membership may commit only while the display still shows the target Space"
        )
        expect(
            !SpaceChangePolicy.mayCommitSeamReveal(
                targetSpaceID: 42,
                currentDisplaySpaceID: 43,
                membershipConfirmed: true
            ),
            "a concurrent Space switch cancels reveal even after membership was confirmed"
        )
        expect(
            !SpaceChangePolicy.mayCommitSeamReveal(
                targetSpaceID: 42,
                currentDisplaySpaceID: 42,
                membershipConfirmed: false
            ),
            "the current display Space alone can never authorize deminimize"
        )
        expect(
            SpaceChangePolicy.pendingSeamRevealCancellation(
                phase: .collapsed,
                revealInFlight: false,
                observedMinimized: false
            ) == .none,
            "a Space change with no reveal transaction has nothing to cancel"
        )
        expect(
            SpaceChangePolicy.pendingSeamRevealCancellation(
                phase: .collapsed,
                revealInFlight: true,
                observedMinimized: true
            ) == .clearTransaction,
            "a pre-deminimize cancellation keeps the owned minimize and clears the transaction"
        )
        expect(
            SpaceChangePolicy.pendingSeamRevealCancellation(
                phase: .collapsed,
                revealInFlight: true,
                observedMinimized: false
            ) == .restoreCollapsedMinimizeThenClear,
            "the exact post-deminimize/pre-commit race must re-minimize before clearing"
        )
        expect(
            SpaceChangePolicy.pendingSeamRevealCancellation(
                phase: .collapsed,
                revealInFlight: true,
                observedMinimized: nil
            ) == .restoreCollapsedMinimizeThenClear,
            "an unreadable collapsed window state must fail closed by re-applying minimize"
        )
        expect(
            SpaceChangePolicy.pendingSeamRevealCancellation(
                phase: .expanded,
                revealInFlight: true,
                observedMinimized: false
            ) == .clearTransaction,
            "a committed expansion clears stale bookkeeping without re-minimizing the window"
        )

        let setLaptop = DisplayGeometry(
            id: "laptop",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        let setLeft = DisplayGeometry(
            id: "left",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        let setMiddle = DisplayGeometry(
            id: "middle",
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        )
        let setRight = DisplayGeometry(
            id: "right",
            frame: CGRect(x: 3840, y: 0, width: 1920, height: 1080)
        )
        let setAdded = DisplayGeometry(
            id: "added",
            frame: CGRect(x: 5760, y: 0, width: 1920, height: 1080)
        )
        let setLeftShifted = DisplayGeometry(
            id: "left",
            frame: CGRect(x: 80, y: 40, width: 1920, height: 1080)
        )
        let setMiddleShifted = DisplayGeometry(
            id: "middle",
            frame: CGRect(x: 2000, y: 40, width: 1920, height: 1080)
        )
        let setLeftSwapped = DisplayGeometry(
            id: "left",
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        )
        let setMiddleSwapped = DisplayGeometry(
            id: "middle",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        let setLeftScaled = DisplayGeometry(
            id: "left",
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440)
        )
        let setMiddleScaled = DisplayGeometry(
            id: "middle",
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        )

        let pairFingerprint = ScreenSetPolicy.fingerprint(displays: [setLeft, setMiddle])
        let shiftedPairFingerprint = ScreenSetPolicy.fingerprint(
            displays: [setLeftShifted, setMiddleShifted]
        )
        let swappedPairFingerprint = ScreenSetPolicy.fingerprint(
            displays: [setLeftSwapped, setMiddleSwapped]
        )
        let scaledPairFingerprint = ScreenSetPolicy.fingerprint(
            displays: [setLeftScaled, setMiddleScaled]
        )
        let threeFingerprint = ScreenSetPolicy.fingerprint(
            displays: [setLeft, setMiddle, setRight]
        )
        let fourFingerprint = ScreenSetPolicy.fingerprint(
            displays: [setLeft, setMiddle, setRight, setAdded]
        )
        let twoFingerprint = ScreenSetPolicy.fingerprint(displays: [setLeft, setMiddle])
        let laptopFingerprint = ScreenSetPolicy.fingerprint(displays: [setLaptop])
        let officeThreeFingerprint = ScreenSetPolicy.fingerprint(
            displays: [
                DisplayGeometry(id: "laptop", frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
                DisplayGeometry(id: "ext-a", frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080)),
                DisplayGeometry(id: "ext-b", frame: CGRect(x: 3360, y: 0, width: 1920, height: 1080))
            ]
        )

        expect(
            pairFingerprint == shiftedPairFingerprint,
            "an origin-shifted copy of the same two displays is the same screen set"
        )
        expect(
            pairFingerprint != swappedPairFingerprint,
            "swapping left and right of two displays is a different screen set"
        )
        expect(
            pairFingerprint == scaledPairFingerprint,
            "a resolution change that keeps who-is-left-of-whom must keep the fingerprint"
        )
        expect(
            ScreenSetPolicy.classify(
                previous: threeFingerprint,
                current: fourFingerprint,
                configured: [],
                flags: ScreenSetClassifyFlags(isSleepingOrWaking: true)
            ) == .sleep,
            "a sleep or wake flag is sleep even when the topology also changed"
        )
        expect(
            ScreenSetPolicy.classify(
                previous: threeFingerprint,
                current: fourFingerprint,
                configured: [],
                flags: ScreenSetClassifyFlags()
            ) == .increment,
            "adding a display without moving the existing three is increment when the four-set is not configured"
        )
        let returnEvent = ScreenSetPolicy.classify(
            previous: laptopFingerprint,
            current: officeThreeFingerprint,
            configured: [officeThreeFingerprint],
            flags: ScreenSetClassifyFlags()
        )
        expect(
            returnEvent == .returnConfigured,
            "laptop back to a remembered three-display set is returnConfigured"
        )
        expect(
            returnEvent != .increment,
            "laptop back to a remembered three-display set must not be increment"
        )
        expect(
            ScreenSetPolicy.classify(
                previous: threeFingerprint,
                current: twoFingerprint,
                configured: [threeFingerprint, twoFingerprint],
                flags: ScreenSetClassifyFlags()
            ) == .dropConfigured,
            "three configured displays down to a configured two-set is dropConfigured"
        )
        expect(
            ScreenSetPolicy.classify(
                previous: threeFingerprint,
                current: twoFingerprint,
                configured: [threeFingerprint],
                flags: ScreenSetClassifyFlags()
            ) == .dropUnconfigured,
            "three displays down to an unconfigured two-set is dropUnconfigured"
        )
        let scrambledTwo = ScreenSetPolicy.fingerprint(
            displays: [
                DisplayGeometry(id: "left", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                DisplayGeometry(id: "middle", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            ]
        )
        expect(
            ScreenSetPolicy.classify(
                previous: threeFingerprint,
                current: scrambledTwo,
                configured: [threeFingerprint],
                flags: ScreenSetClassifyFlags()
            ) == .dropUnconfigured,
            "a 3→2 unplug whose remaining frames overlap must drop, not cancel"
        )
        expect(
            ScreenSetPolicy.classify(
                previous: threeFingerprint,
                current: laptopFingerprint,
                configured: [threeFingerprint],
                flags: ScreenSetClassifyFlags()
            ) == .recover,
            "replacing three office displays with a different laptop identity keeps those memories"
        )
        expect(
            ScreenSetPolicy.classify(
                previous: twoFingerprint,
                current: threeFingerprint,
                configured: [],
                flags: ScreenSetClassifyFlags(mirrorChanged: true)
            ) == .cancel,
            "a hardware mirror change is cancel even when the ID count also changed"
        )
        expect(
            ScreenSetPolicy.classify(
                previous: threeFingerprint,
                current: ScreenSetPolicy.fingerprint(
                    displays: [
                        DisplayGeometry(id: "left", frame: CGRect(x: 3840, y: 0, width: 1920, height: 1080)),
                        DisplayGeometry(id: "middle", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)),
                        DisplayGeometry(id: "right", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                    ]
                ),
                configured: [threeFingerprint],
                flags: ScreenSetClassifyFlags()
            ) == .cancel,
            "the same three IDs with swapped left and right must cancel"
        )
        expect(
            ScreenSetPolicy.classify(
                previous: threeFingerprint,
                current: ScreenSetPolicy.fingerprint(
                    displays: [
                        DisplayGeometry(id: "left", frame: CGRect(x: 3840, y: 0, width: 1920, height: 1080)),
                        DisplayGeometry(id: "middle", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)),
                        DisplayGeometry(id: "right", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
                    ]
                ),
                configured: [threeFingerprint],
                flags: ScreenSetClassifyFlags(userRearrangeLikely: false)
            ) == .none,
            "a same-ID relation scramble without System Settings is not cancel"
        )
        expect(
            ScreenSetPolicy.classify(
                previous: pairFingerprint,
                current: pairFingerprint,
                configured: [],
                flags: ScreenSetClassifyFlags(scaleChanged: true)
            ) == .scale,
            "the same fingerprint with a scale flag is scale"
        )
        expect(
            ScreenSetPolicy.classify(
                previous: threeFingerprint,
                current: threeFingerprint,
                configured: [threeFingerprint],
                flags: ScreenSetClassifyFlags()
            ) == .none,
            "identical previous and current with no flags is none"
        )
        expect(
            ScreenSetPolicy.classify(
                previous: nil,
                current: threeFingerprint,
                configured: [threeFingerprint],
                flags: ScreenSetClassifyFlags()
            ) == .none,
            "the first observation only establishes a baseline"
        )
        expect(
            ScreenSetPolicy.departedDisplayIDs(
                previous: threeFingerprint,
                current: twoFingerprint
            ) == ["right"],
            "the display that left the three-set is the departed ID"
        )
        expect(
            ScreenSetPolicy.addedDisplayIDs(
                previous: threeFingerprint,
                current: fourFingerprint
            ) == ["added"],
            "the display that joined the three-set is the added ID"
        )

        let scatterDisplay = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let scatterSize = CGSize(width: 400, height: 300)
        let scatterOrigins = ScreenSetPolicy.scatterOrigins(
            count: 5,
            on: scatterDisplay,
            windowSize: scatterSize
        )
        expect(
            scatterOrigins.count == 5,
            "scatter must return one origin per window"
        )
        let scatterOriginsAreUnique = scatterOrigins.indices.allSatisfy { index in
            !scatterOrigins[(index + 1)...].contains(scatterOrigins[index])
        }
        expect(
            scatterOriginsAreUnique,
            "scatter origins must all be distinct"
        )
        expect(
            scatterOrigins.allSatisfy { origin in
                origin.x >= scatterDisplay.minX
                    && origin.y >= scatterDisplay.minY
                    && origin.x + scatterSize.width <= scatterDisplay.maxX
                    && origin.y + scatterSize.height <= scatterDisplay.maxY
            },
            "every scattered window must sit fully inside the display"
        )
        expect(
            ScreenSetPolicy.scatterOrigins(
                count: 0,
                on: scatterDisplay,
                windowSize: scatterSize
            ).isEmpty,
            "scatter of zero windows is empty"
        )
        let singleScatter = ScreenSetPolicy.scatterOrigins(
            count: 1,
            on: scatterDisplay,
            windowSize: scatterSize
        )
        expect(
            singleScatter.count == 1 && singleScatter[0] != .zero,
            "a single scatter origin is a comfortable on-desktop point, not the display corner"
        )

        expect(
            StashActivationPolicy.decision(
                kind: .dockAppIcon,
                hasOnDesktopWindow: true,
                allStandardWindowsStashed: false,
                allStashedDock: .openAll
            ) == .raiseOnDesktopOnly,
            "a Dock icon click with mixed on-desktop and stashed windows raises only the on-desktop windows"
        )
        expect(
            StashActivationPolicy.decision(
                kind: .dockAppIcon,
                hasOnDesktopWindow: false,
                allStandardWindowsStashed: true,
                allStashedDock: StashActivationPolicy.resolvedDockAction(nil)
            ) == .doNotOpenStash,
            "all stashed plus the default Dock action must leave stashes closed"
        )
        expect(
            StashActivationPolicy.decision(
                kind: .showAllWindows,
                hasOnDesktopWindow: true,
                allStandardWindowsStashed: false,
                allStashedDock: .leaveClosed
            ) == .openAllStashes,
            "show all windows opens every stash of that app"
        )
        expect(
            StashActivationPolicy.decision(
                kind: .dockWindowThumbnail,
                hasOnDesktopWindow: true,
                allStandardWindowsStashed: false,
                allStashedDock: .leaveClosed
            ) == .openThumbnail,
            "a Dock window thumbnail opens that one stash"
        )
        expect(
            StashActivationPolicy.resolvedDockAction(nil) == .leaveClosed,
            "a missing per-app Dock action defaults to leaveClosed"
        )
        expect(
            StashActivationPolicy.decision(
                kind: .commandTab,
                hasOnDesktopWindow: true,
                allStandardWindowsStashed: false,
                allStashedDock: .openAll
            ) == .raiseOnDesktopOnly,
            "Cmd-Tab with an on-desktop window must not open a stash"
        )
        expect(
            StashActivationPolicy.decision(
                kind: .dockAppIcon,
                hasOnDesktopWindow: false,
                allStandardWindowsStashed: true,
                allStashedDock: .openAll
            ) == .openAllStashes,
            "all stashed plus openAll opens every stash"
        )
        expect(
            StashActivationPolicy.decision(
                kind: .ownedReveal,
                hasOnDesktopWindow: false,
                allStandardWindowsStashed: true,
                allStashedDock: .openAll
            ) == .doNotOpenStash,
            "a rail, beacon, or shortcut reveal must not open sibling stashes"
        )
        expect(
            ShowAllWindowsKeyPolicy.matchesShowAll(
                keyCode: ShowAllWindowsKeyPolicy.downArrow,
                control: true,
                command: false,
                option: false
            ),
            "Control-Down is show-all for the frontmost app"
        )
        expect(
            ShowAllWindowsKeyPolicy.frontmostAppOnly(keyCode: ShowAllWindowsKeyPolicy.downArrow),
            "Control-Down addresses only the frontmost app"
        )
        expect(
            !ShowAllWindowsKeyPolicy.frontmostAppOnly(keyCode: ShowAllWindowsKeyPolicy.upArrow),
            "Control-Up is Mission Control and addresses every app with a stash"
        )
        expect(
            !ShowAllWindowsKeyPolicy.matchesShowAll(
                keyCode: ShowAllWindowsKeyPolicy.downArrow,
                control: true,
                command: true,
                option: false
            ),
            "Command-Control-Down is not show-all"
        )
        expect(
            DockItemPolicy.kind(
                subrole: DockItemPolicy.applicationSubrole,
                title: "Terminal",
                appLocalizedName: "Terminal"
            ) == .applicationIcon,
            "an application Dock item is the app icon"
        )
        expect(
            DockItemPolicy.kind(
                subrole: DockItemPolicy.minimizedWindowSubrole,
                title: "server.log",
                appLocalizedName: "Terminal"
            ) == .windowThumbnail,
            "a minimized Dock tile is that window's thumbnail"
        )
        expect(
            DockItemPolicy.kind(
                subrole: nil,
                title: "server.log",
                appLocalizedName: "Terminal"
            ) == .windowThumbnail,
            "a Dock title that is not the app name is a window thumbnail"
        )
        expect(
            ScreenSetSettlePolicy.decision(
                sleepingAndNotWakePass: true,
                currentMatchesLastObserved: true,
                elapsedSinceScheduled: 3,
                scheduledDelay: 3
            ) == .ignoreSleepBlip,
            "sleeping observations must not classify as unplug"
        )
        expect(
            ScreenSetSettlePolicy.decision(
                sleepingAndNotWakePass: false,
                currentMatchesLastObserved: false,
                elapsedSinceScheduled: 3,
                scheduledDelay: 3
            ) == .reschedule,
            "a fingerprint that moved again must wait for another quiet interval"
        )
        expect(
            ScreenSetSettlePolicy.decision(
                sleepingAndNotWakePass: false,
                currentMatchesLastObserved: true,
                elapsedSinceScheduled: 30,
                scheduledDelay: 3
            ) == .sleptThrough,
            "a settle timer that fires after a long jump is sleep, not drop"
        )
        expect(
            ScreenSetSettlePolicy.decision(
                sleepingAndNotWakePass: false,
                currentMatchesLastObserved: true,
                elapsedSinceScheduled: 3.1,
                scheduledDelay: 3
            ) == .apply,
            "a stable fingerprint after the delay may classify"
        )
        expect(
            ScreenSetSettlePolicy.delay(wakePass: false, isShrinkFromCommitted: true)
                > ScreenSetSettlePolicy.delay(wakePass: false, isShrinkFromCommitted: false),
            "a shrink waits longer so a late willSleep can still freeze the set"
        )
        expect(
            ScreenSetSettlePolicy.wakeMatchesPreSleep(
                preSleep: threeFingerprint,
                current: threeFingerprint
            ),
            "wake onto the pre-sleep set is sleep, not unplug"
        )
        expect(
            !ScreenSetSettlePolicy.wakeMatchesPreSleep(
                preSleep: threeFingerprint,
                current: laptopFingerprint
            ),
            "wake onto a different set is a real screen-set event"
        )
        expect(
            ScreenSetSettlePolicy.onlyBuiltinMissing(
                preSleepIDs: ["laptop", "ext-a", "ext-b"],
                currentIDs: ["ext-a", "ext-b"],
                builtinID: "laptop"
            ),
            "lid still closed after sleep is only the built-in missing"
        )
        expect(
            !ScreenSetSettlePolicy.onlyBuiltinMissing(
                preSleepIDs: ["laptop", "ext-a", "ext-b"],
                currentIDs: ["laptop"],
                builtinID: "laptop"
            ),
            "wake onto the laptop alone is not lid-still-closed"
        )
        expect(
            ScreenSetSettlePolicy.wakeDecision(
                preSleepIDs: ["laptop", "ext-a", "ext-b"],
                currentIDs: ["laptop"],
                currentIsConfigured: false,
                onlyBuiltinMissing: false,
                subsetHoldElapsed: 1
            ) == .waitLonger,
            "a smaller set right after wake must wait for enumeration"
        )
        expect(
            ScreenSetSettlePolicy.wakeDecision(
                preSleepIDs: ["laptop", "ext-a", "ext-b"],
                currentIDs: ["ext-a", "ext-b"],
                currentIsConfigured: false,
                onlyBuiltinMissing: true,
                subsetHoldElapsed: 5
            ) == .keepPreSleep,
            "wake with the lid still closed must not drop the pre-sleep placement"
        )
        expect(
            ScreenSetSettlePolicy.wakeDecision(
                preSleepIDs: ["laptop", "ext-a", "ext-b"],
                currentIDs: ["laptop"],
                currentIsConfigured: true,
                onlyBuiltinMissing: false,
                subsetHoldElapsed: 5
            ) == .keepPreSleep,
            "wake onto a remembered laptop-only set must not apply that layout"
        )
        expect(
            ScreenSetSettlePolicy.wakeDecision(
                preSleepIDs: ["laptop", "ext-a", "ext-b"],
                currentIDs: ["laptop", "ext-a", "ext-b"],
                currentIsConfigured: true,
                onlyBuiltinMissing: false,
                subsetHoldElapsed: 0
            ) == .sameSet,
            "wake onto the pre-sleep IDs is the same set"
        )

        if failed > 0 {
            fputs("\(failed) test(s) failed\n", stderr)
            exit(1)
        }
        print("All tests passed")
    }
}
