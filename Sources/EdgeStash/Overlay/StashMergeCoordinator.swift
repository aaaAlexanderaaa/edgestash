import AppKit
import EdgeStashLogic

final class StashMergeCoordinator {
    /// Capsule labels size to their text: 12pt semibold measure, 8pt of pad
    /// per side, clamped to a 64–144pt band so short names stay tappable and
    /// long ones truncate instead of stretching the strip.
    static func measuredLabelWidth(for title: String) -> CGFloat {
        let size = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ])
        return min(max(ceil(size.width) + 16, 64), 144)
    }

    private var overlays: [String: StashMergeStrip] = [:]
    private var hoverTimers: [String: Timer] = [:]
    private var interactions: [String: HoverRevealCoordinator] = [:]
    private var selections: [String: MergeRevealSelection] = [:]
    private var approachSegments: [String: [SeamApproachSegment]] = [:]
    private var approachGroups = Set<String>()
    private var groupSessions: [String: [String: StashSession]] = [:]
    var onPointerActivity: (() -> Void)?
    var seamApproachSegments: [SeamApproachSegment] { approachSegments.values.flatMap { $0 } }
    private var warnedOverload = false

    func reconcile(sessions: [StashSession]) {
        guard Preferences.shared.mergesStrips else {
            sessions.forEach { $0.setMarkerSuppressed(false) }
            tearDown()
            return
        }

        let members = sessions.compactMap(\.mergeMember)
        let groups = MergeGroupPolicy.groups(from: members)
        let suppressed = MergeGroupPolicy.suppressedIDs(in: groups)
        for session in sessions {
            session.setMarkerSuppressed(suppressed.contains(session.mergeID))
        }

        if !warnedOverload, MergeGroupPolicy.shouldWarnOverload(groups) {
            warnedOverload = true
            if !Preferences.shared.advisedStripOverload {
                Preferences.shared.advisedStripOverload = true
                presentOverloadWarning()
            }
        }

        let desiredKeys = Set(groups.map(groupKey))
        for stale in Set(overlays.keys).subtracting(desiredKeys) {
            overlays[stale]?.orderOut(nil)
            overlays.removeValue(forKey: stale)
            hoverTimers[stale]?.invalidate()
            hoverTimers.removeValue(forKey: stale)
            interactions.removeValue(forKey: stale)
            selections.removeValue(forKey: stale)
            approachSegments.removeValue(forKey: stale)
            approachGroups.remove(stale)
            groupSessions.removeValue(forKey: stale)
        }

        let lookup = Dictionary(uniqueKeysWithValues: sessions.map { ($0.mergeID, $0) })
        for group in groups {
            let key = groupKey(group)
            let overlay = overlays[key] ?? StashMergeStrip()
            overlays[key] = overlay
            let widths = group.members.map { member -> CGFloat in
                StashMergeCoordinator.measuredLabelWidth(for: member.title)
            }
            guard let layout = MergeGroupPolicy.layout(group: group, labelWidths: widths) else { continue }
            let expanded = Set(group.members.compactMap { member -> String? in
                lookup[member.id]?.isExpanded == true ? member.id : nil
            })
            let pinned = expanded.contains(where: { lookup[$0]?.isPinned == true })
                ? group.members.first { lookup[$0.id]?.isPinned == true }?.id
                : nil
            let activeID = (selections[key] ?? MergeRevealSelection()).active(
                expandedIDs: expanded, hoveredID: interactions[key]?.hoveredID, pinnedID: pinned
            )
            if let activeID {
                for member in group.members where member.id != activeID && lookup[member.id]?.isExpanded == true {
                    lookup[member.id]?.mergeHide()
                }
            }
            let hovered = interactions[key]?.hoveredID.flatMap { lookup[$0] }.map { ObjectIdentifier($0) }
            let presented = MergeGroupPolicy.presentation(layout: layout, showingLabels: false)
            let labelPresentation = MergeGroupPolicy.presentation(layout: layout, showingLabels: true)
            groupSessions[key] = Dictionary(uniqueKeysWithValues: group.members.compactMap { member in
                lookup[member.id].map { (member.id, $0) }
            })
            if group.members.contains(where: { $0.presentation == .systemMinimize }) {
                approachGroups.insert(key)
            } else {
                approachGroups.remove(key)
            }
            let primaryHeight = DisplayCatalog.primaryHeight(screens: NSScreen.screens)
            approachSegments[key] = presented.segments.enumerated().compactMap { index, slot in
                guard let session = lookup[slot.id], session.isCollapsed,
                      session.presentation == .systemMinimize, session.canBeginSeamReveal,
                      let displayID = session.displayID else { return nil }
                let desktop = slot.slotRect.offsetBy(dx: presented.windowFrame.minX, dy: presented.windowFrame.minY)
                return SeamApproachSegment(
                    id: slot.id, displayID: displayID, edge: group.edge,
                    minY: primaryHeight - desktop.maxY - (index == presented.segments.count - 1 ? MergeGroupPolicy.hitPad : 0),
                    maxY: primaryHeight - desktop.minY + (index == 0 ? MergeGroupPolicy.hitPad : 0)
                )
            }
            func segments(_ slots: [MergeSegmentLayout]) -> [StashMergeSegmentModel] {
                slots.compactMap { slot in
                    guard let session = lookup[slot.id],
                          let member = group.members.first(where: { $0.id == slot.id }) else { return nil }
                    return StashMergeSegmentModel(
                        id: ObjectIdentifier(session), color: Preferences.shared.stripColor(for: session.bundleID),
                        material: Preferences.shared.appearance(for: session.bundleID).resolvedMaterial,
                        title: member.title, icon: session.applicationIcon,
                        slotRect: slot.slotRect,
                        kind: session.presentation == .systemMinimize ? .seamBeacon : .outerStrip
                    )
                }
            }
            let model = StashMergeStripModel(
                windowFrame: presented.windowFrame,
                edge: group.edge,
                trackRect: presented.trackRect,
                hitRect: presented.hitRect,
                segments: segments(presented.segments),
                labelWindowFrame: labelPresentation.windowFrame,
                labelSegments: segments(labelPresentation.segments),
                activeID: activeID.flatMap { lookup[$0] }.map { ObjectIdentifier($0) },
                hoveredID: hovered,
                showsLabels: hovered != nil
            )
            overlay.onHoverSegment = { [weak self] id in
                guard let self else { return }
                if self.approachGroups.contains(key), let onPointerActivity = self.onPointerActivity {
                    onPointerActivity()
                } else {
                    self.handleHover(id, key: key, lookup: lookup)
                }
            }
            overlay.onClickSegment = { [weak self] id in
                self?.handleClick(id, key: key, lookup: lookup)
            }
            overlay.present(model)
        }
    }

    func tearDown() {
        hoverTimers.values.forEach { $0.invalidate() }
        hoverTimers.removeAll()
        overlays.values.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        interactions.removeAll()
        selections.removeAll()
        approachSegments.removeAll()
        approachGroups.removeAll()
        groupSessions.removeAll()
    }

    /// Uses the engine's one combined seam target selection, so a fused rail
    /// cannot independently open a second stash in an overlapping band.
    func updateSeamApproachTarget(_ targetID: String?) {
        for key in Array(approachGroups) {
            guard let lookup = groupSessions[key] else { continue }
            let target = targetID.flatMap { lookup[$0] }.map { ObjectIdentifier($0) }
            let panelTarget = overlays[key]?.segmentAtPointer()
            let selected: ObjectIdentifier?
            if let panelTarget, let session = session(panelTarget, in: lookup),
               !(session.isCollapsed && session.presentation == .systemMinimize) {
                selected = panelTarget
            } else {
                selected = target
            }
            handleHover(selected, key: key, lookup: lookup)
        }
    }

    func rearmHoverAfterMouseUp() {
        Array(overlays.values).forEach { $0.rearmHoverAfterMouseUp() }
    }

    /// Called for accepted requests from all native reveal paths, including
    /// Dock unminimize and shortcuts, before completion can reconcile the group.
    func noteRevealRequest(_ session: StashSession) {
        let id = session.mergeID
        for key in groupSessions.keys where groupSessions[key]?[id] != nil {
            selections[key, default: MergeRevealSelection()].request(id)
        }
    }

    /// Space transitions dismiss the fused strip, but must also release
    /// individual-marker suppression. `tearDown()` alone leaves
    /// `markerSuppressed` set, so `showMarker` no-ops and a merged collapsed
    /// seam beacon stays blank for `SpaceChangePolicy.rebuildDelay`.
    func resetForSpaceChange(sessions: [StashSession]) {
        tearDown()
        sessions.forEach { $0.setMarkerSuppressed(false) }
    }

    private func handleHover(
        _ id: ObjectIdentifier?,
        key: String,
        lookup: [String: StashSession]
    ) {
        var interaction = interactions[key] ?? HoverRevealCoordinator()
        let previous = interaction.hoveredID
        let delay = TimeInterval(Preferences.shared.revealDelayMS) / 1000
        let ticket = interaction.updateTarget(
            id.map(sessionID), now: Date(), delay: delay, buttonPressed: NSEvent.pressedMouseButtons != 0
        )
        interactions[key] = interaction
        if interaction.pending == nil {
            hoverTimers.removeValue(forKey: key)?.invalidate()
        }
        if interaction.hoveredID != previous { overlays[key]?.updateHover(id) }
        if let ticket, let id, let session = session(id, in: lookup) {
            armHover(ticket, key: key, session: session)
        }
    }

    private func armHover(_ ticket: HoverRevealTicket, key: String, session: StashSession) {
        hoverTimers.removeValue(forKey: key)?.invalidate()
        let delay = ticket.deadline.timeIntervalSinceNow
        if delay <= 0 {
            fireHover(ticket, key: key, session: session)
            return
        }
        hoverTimers[key] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self, weak session] _ in
            guard let session else { return }
            self?.fireHover(ticket, key: key, session: session)
        }
    }

    private func fireHover(_ ticket: HoverRevealTicket, key: String, session: StashSession) {
        guard var interaction = interactions[key], interaction.pending == ticket else { return }
        let now = Date()
        if now < ticket.deadline {
            armHover(ticket, key: key, session: session)
            return
        }
        let target = interaction.consume(ticket, now: now, buttonPressed: NSEvent.pressedMouseButtons != 0)
        interactions[key] = interaction
        hoverTimers.removeValue(forKey: key)?.invalidate()
        if target == session.mergeID, session.isManaged {
            noteRevealRequest(session)
            session.mergeReveal()
        }
    }

    private func handleClick(
        _ id: ObjectIdentifier,
        key: String,
        lookup: [String: StashSession]
    ) {
        guard let session = session(id, in: lookup) else { return }
        hoverTimers.removeValue(forKey: key)?.invalidate()
        var interaction = interactions[key] ?? HoverRevealCoordinator()
        let collapsing = session.desiredPresentationIsExpanded
        interaction.click(targetID: session.mergeID, collapsing: collapsing)
        interactions[key] = interaction
        overlays[key]?.updateHover(id)
        if collapsing {
            session.mergeHide()
        } else {
            noteRevealRequest(session)
            session.mergeReveal()
        }
    }

    private func session(_ id: ObjectIdentifier, in lookup: [String: StashSession]) -> StashSession? {
        lookup.values.first { ObjectIdentifier($0) == id }
    }

    private func sessionID(_ id: ObjectIdentifier) -> String {
        String(describing: id)
    }

    private func groupKey(_ group: MergeGroup) -> String {
        let ids = group.members.map(\.id).sorted().joined(separator: "|")
        return "\(group.edge.rawValue)-\(Int(group.screenFrame.minX))-\(ids)"
    }

    private func presentOverloadWarning() {
        DispatchQueue.main.async {
            EdgeAlert.run(
                style: .informational,
                title: L10n.stripOverloadTitle,
                detail: L10n.stripOverloadBody,
                buttons: [L10n.stripOverloadOK]
            )
        }
    }
}
