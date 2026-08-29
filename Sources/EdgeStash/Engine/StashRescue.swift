import AppKit
import ApplicationServices
import EdgeStashLogic

/// Log-friendly reasons a recovery pass ran.
enum RescueTrigger {
    static let appLaunch = "launch"
    static let trustRegained = "trust.regained"
}

enum StashRescue {
    static func persist(session: StashSession) {
        guard let windowID = session.windowID,
              let visible = session.rescueVisibleFrame,
              let display = session.rescueDisplayFrame,
              let edge = session.edge else {
            return
        }
        let rest = StashGeometryPolicy.expandedOrigin(
            edge: edge,
            frame: visible,
            display: display,
            lockedWidth: visible.width
        )
        Preferences.shared.upsertRescueDossier(
            RescueDossier(
                subject: RescuedSubject(
                    bundleID: session.bundleID,
                    processID: session.pid,
                    windowNumber: windowID
                ),
                placement: RescuedPlacement(
                    edge: edge.rawValue,
                    frame: StoredGeometry(visible),
                    display: StoredGeometry(display)
                ),
                landing: StoredGeometry(rest),
                recordedAt: Date()
            )
        )
        Preferences.shared.addGhostedWindowID(pid: session.pid, windowID: windowID)
    }

    static func clear(processID: pid_t, windowNumber: UInt32?) {
        guard let windowNumber else { return }
        Preferences.shared.removeRescueDossier(processID: processID, windowNumber: windowNumber)
    }

    static func recoverPending(
        reason: String,
        liveHolds: [SessionLifecyclePolicy.LiveRescueHold] = []
    ) {
        let preferences = Preferences.shared
        guard preferences.hasPendingRescueDossiers() else { return }

        if !AccessibilityGrant.isTrusted(prompt: false) {
            for dossier in preferences.rescueDossiers {
                guard SessionLifecyclePolicy.shouldRestoreRescueRecord(
                    processID: dossier.subject.processID,
                    windowNumber: dossier.subject.windowNumber,
                    liveHolds: liveHolds
                ) else {
                    continue
                }
                _ = StashSurface.setAlpha(windowID: dossier.subject.windowNumber, alpha: 1)
            }
            NSLog("[EdgeStash] rescue \(reason): AX untrusted, alpha-only for \(preferences.rescueDossiers.count) dossier(s)")
            return
        }

        let queue = preferences.rescueDossiers.sorted { $0.recordedAt < $1.recordedAt }
        for dossier in queue {
            _ = recover(dossier, liveHolds: liveHolds)
        }
    }

    @discardableResult
    static func recover(
        _ dossier: RescueDossier,
        liveHolds: [SessionLifecyclePolicy.LiveRescueHold] = []
    ) -> Bool {
        guard SessionLifecyclePolicy.shouldRestoreRescueRecord(
            processID: dossier.subject.processID,
            windowNumber: dossier.subject.windowNumber,
            liveHolds: liveHolds
        ) else {
            return false
        }
        for pid in restorationTargets(for: dossier) {
            reviveApp(pid: pid)
            let appElement = AXUIElementCreateApplication(pid)
            guard let (element, windowID, frame) = locateRecordedWindow(in: appElement, dossier: dossier) else {
                continue
            }
            if let savedDisplay = dossier.placement.display.rect,
               RescueMatching.shouldSkipRestoreBecauseAlreadyVisible(frame: frame, display: savedDisplay) {
                _ = StashSurface.setAlpha(windowID: windowID, alpha: 1)
                Preferences.shared.removeRescueDossier(
                    processID: dossier.subject.processID,
                    windowNumber: dossier.subject.windowNumber
                )
                return true
            }
            let placement = placementFrame(for: dossier, current: frame)
            let alphaRestored = StashSurface.setAlpha(windowID: windowID, alpha: 1)
            let unminimized: Bool
            if StashAX.isMinimized(element) == false {
                unminimized = true
            } else {
                unminimized = StashAX.setMinimized(element, false)
            }
            let applied = StashAX.applyFrame(element, placement)
            if RescueMatching.recordIsSettled(
                moved: applied.moved,
                resized: applied.sized,
                alphaRestored: alphaRestored,
                unminimized: unminimized
            ) {
                Preferences.shared.removeRescueDossier(
                    processID: dossier.subject.processID,
                    windowNumber: dossier.subject.windowNumber
                )
                if pid != dossier.subject.processID {
                    Preferences.shared.removeRescueDossier(processID: pid, windowNumber: windowID)
                }
                return true
            }
        }
        return false
    }

    /// Processes that may own the recorded window now: the recorded process
    /// itself, plus any live process sharing the recorded bundle identifier
    /// (the app may have relaunched under a new pid). Original pid first.
    private static func restorationTargets(for dossier: RescueDossier) -> [pid_t] {
        let alive = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let original = alive.first { $0.processIdentifier == dossier.subject.processID }
        let bundleKin = alive.filter {
            $0.processIdentifier != dossier.subject.processID
                && $0.bundleIdentifier == dossier.subject.bundleID
        }

        var targets: [pid_t] = original.map { [$0.processIdentifier] } ?? []
        targets.append(contentsOf: bundleKin.map(\.processIdentifier))
        return targets
    }

    private static func reviveApp(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid), app.isHidden else { return }
        app.unhide()
    }

    /// Prefers the recorded window number; otherwise accepts a single
    /// plausible shape-match decided by the matching policy.
    private static func locateRecordedWindow(
        in appElement: AXUIElement,
        dossier: RescueDossier
    ) -> (element: AXUIElement, windowID: UInt32, frame: CGRect)? {
        guard let savedFrame = dossier.placement.frame.rect,
              let savedDisplay = dossier.placement.display.rect else {
            return nil
        }
        var sightings: [(AXUIElement, UInt32, CGRect)] = []
        var candidates: [RescueMatching.Candidate] = []
        for window in StashAX.windows(of: appElement) where StashAX.isStandardWindow(window) {
            guard let frame = StashAX.frame(of: window) else { continue }
            let windowID = StashAX.windowID(of: window)
            candidates.append(.init(windowID: windowID, frame: frame))
            if let windowID {
                sightings.append((window, windowID, frame))
            }
        }

        let verdict = RescueMatching.identify(
            recordedNumber: dossier.subject.windowNumber,
            recordedEdge: dossier.placement.edge,
            recordedFrame: savedFrame,
            recordedDisplay: savedDisplay,
            among: candidates
        )
        switch verdict {
        case .matched(let windowID):
            return sightings.first { $0.1 == windowID }.map { ($0.0, $0.1, $0.2) }
        case .unresolved:
            return nil
        }
    }

    /// Restored windows park one-sixteenth of the display width in from the
    /// stash edge (clamped to 24–120pt) so they sit clear of the edge marker
    /// on every display size, and keep a title-bar height of vertical guard
    /// below the menu bar.
    private static func edgeRestInset(for screenWidth: CGFloat) -> CGFloat {
        min(120, max(24, screenWidth / 16))
    }

    private static let titleBarGuard: CGFloat = 28

    private static func placementFrame(for dossier: RescueDossier, current: CGRect) -> CGRect {
        guard let visible = dossier.placement.frame.rect,
              let display = dossier.placement.display.rect else {
            return current
        }
        let screens = NSScreen.screens
        let primaryHeight = DisplayCatalog.primaryHeight(screens: screens)
        let screenFrame = screens.first {
            $0.frame.intersects(
                StashGeometryPolicy.appKitRect(fromQuartz: display, primaryHeight: primaryHeight)
                    .insetBy(dx: -StashGeometryPolicy.captureBand, dy: -StashGeometryPolicy.captureBand)
            )
        }.map {
            StashGeometryPolicy.cgRect(fromAppKit: $0.frame, primaryHeight: primaryHeight)
        } ?? display
        let width = savedDimension(visible.width, or: current.width)
        let height = savedDimension(visible.height, or: current.height)
        let restInset = edgeRestInset(for: screenFrame.width)
        let clampedY = min(
            max(dossier.landing.point.y, screenFrame.minY + titleBarGuard),
            max(screenFrame.minY, screenFrame.maxY - height - titleBarGuard)
        )
        let x: CGFloat
        if dossier.placement.edge == DisplayEdge.left.rawValue {
            x = screenFrame.minX + restInset
        } else {
            x = screenFrame.maxX - width - restInset
        }
        return CGRect(x: x, y: clampedY, width: width, height: height)
    }

    /// A stored dimension of zero or one is a placeholder, not a real size;
    /// fall back to what the window measures right now.
    private static func savedDimension(_ stored: CGFloat, or measured: CGFloat) -> CGFloat {
        stored > 1 ? stored : measured
    }
}
