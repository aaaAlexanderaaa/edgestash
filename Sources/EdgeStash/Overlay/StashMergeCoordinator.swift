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
    private var hovered: [String: ObjectIdentifier] = [:]
    private var clickLocked: [String: ObjectIdentifier] = [:]
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
            hovered.removeValue(forKey: stale)
            clickLocked.removeValue(forKey: stale)
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
            let preferred = expanded.contains(where: { lookup[$0]?.isPinned == true })
                ? group.members.first { lookup[$0.id]?.isPinned == true }?.id
                : hovered[key].map { sessionID($0) }
            let activeID = MergeGroupPolicy.activeAfterReconcile(expandedIDs: expanded, preferred: preferred)
            if let activeID {
                for member in group.members where member.id != activeID && lookup[member.id]?.isExpanded == true {
                    lookup[member.id]?.mergeHide()
                }
            }
            let showingLabels = hovered[key] != nil
            let presented = MergeGroupPolicy.presentation(layout: layout, showingLabels: showingLabels)
            let model = StashMergeStripModel(
                windowFrame: presented.windowFrame,
                edge: group.edge,
                trackRect: presented.trackRect,
                hitRect: presented.hitRect,
                segments: presented.segments.compactMap { slot in
                    guard let session = lookup[slot.id],
                          let member = group.members.first(where: { $0.id == slot.id }) else {
                        return nil
                    }
                    return StashMergeSegmentModel(
                        id: ObjectIdentifier(session),
                        color: Preferences.shared.stripColor(for: session.bundleID),
                        title: member.title,
                        icon: NSRunningApplication(processIdentifier: session.pid)?.icon,
                        slotRect: slot.slotRect
                    )
                },
                activeID: activeID.flatMap { lookup[$0] }.map { ObjectIdentifier($0) },
                hoveredID: hovered[key],
                showsLabels: showingLabels
            )
            overlay.onHoverSegment = { [weak self] id in
                self?.handleHover(id, key: key, lookup: lookup)
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
        hovered.removeAll()
        clickLocked.removeAll()
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
        hovered[key] = id
        hoverTimers[key]?.invalidate()
        guard let id, let session = session(id, in: lookup) else {
            clickLocked.removeValue(forKey: key)
            return
        }
        if clickLocked[key] == id { return }
        let delay = TimeInterval(Preferences.shared.revealDelayMS) / 1000
        hoverTimers[key] = Timer.scheduledTimer(withTimeInterval: max(delay, 0.05), repeats: false) { [weak session] _ in
            session?.mergeReveal()
        }
    }

    private func handleClick(
        _ id: ObjectIdentifier,
        key: String,
        lookup: [String: StashSession]
    ) {
        guard let session = session(id, in: lookup) else { return }
        if session.isExpanded {
            session.mergeHide()
            clickLocked[key] = id
        } else {
            clickLocked.removeValue(forKey: key)
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
