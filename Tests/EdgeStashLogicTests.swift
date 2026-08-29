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
            RescueMatching.recordIsSettled(moved: true, resized: true),
            "rescue records clear only after both position and size writes succeed"
        )
        expect(
            !RescueMatching.recordIsSettled(moved: false, resized: true),
            "a size-only AX write must keep the rescue record"
        )
        expect(
            !RescueMatching.recordIsSettled(moved: true, resized: false),
            "a position-only AX write must keep the rescue record"
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
            ) == .systemMinimize,
            "an enabled shared edge previews as minimize"
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
            !FocusReturnPolicy.shouldReleaseAfterLeaveCollapse(didCollapse: false),
            "failed auto-collapse must not return focus to another app"
        )
        expect(
            FocusReturnPolicy.shouldReleaseAfterLeaveCollapse(didCollapse: true),
            "successful leave collapse may return focus"
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

        let seamLeft = StashGeometryPolicy.markerPanelFrame(
            kind: .seamBeacon,
            edge: .left,
            windowQuartz: CGRect(x: 0, y: 80, width: 800, height: 600),
            displayAppKit: CGRect(x: 0, y: 0, width: 1440, height: 900),
            primaryHeight: 900
        )
        expect(
            seamLeft.minX >= 0 && seamLeft.maxX <= 1440,
            "seam beacon must stay on the owning AppKit display"
        )
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

        if failed > 0 {
            fputs("\(failed) test(s) failed\n", stderr)
            exit(1)
        }
        print("All tests passed")
    }
}
