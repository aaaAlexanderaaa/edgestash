import CoreGraphics
import Foundation

public enum StashOverlayKind: Equatable {
    case outerStrip
    case seamBeacon
}

/// AppKit-free geometry for capture, slide-off, markers, and the Behavior halo.
/// Quartz (AX / CGWindow) Y grows down from the primary display top.
/// AppKit Y grows up from the primary display bottom.
public enum StashGeometryPolicy {
    /// Visible glass rail: a 5pt capsule. Outer and seam share this thickness.
    public static let barThickness: CGFloat = 5
    public static let barCornerRadius: CGFloat = barThickness / 2
    /// Transparent margin on each side of an outer rail so compositing does
    /// not clip the capsule.
    public static let glassRailSideMargin: CGFloat = 3
    /// Seam glass stays this far inside the owning-display seam.
    public static let seamGlassInset: CGFloat = 2
    /// 1pt slit down the long axis that marks a seam rail.
    public static let seamInnerGap: CGFloat = 1
    /// How far the outer glass sits inside the display edge.
    public static let outerOnScreenClearance: CGFloat = 1
    /// A parked window keeps a two-point lip inside the owning display so it
    /// stays composited and AX-addressable; a single point rounds away on
    /// scaled displays.
    public static let edgeLip: CGFloat = 2
    /// Marker panel windows: 5pt glass plus transparent margin.
    public static let outerPanelWidth: CGFloat = 11
    public static let seamPanelWidth: CGFloat = 9
    /// How far an outer panel overlaps into the display so the glass keeps
    /// `outerOnScreenClearance` on-screen and the rest hangs over the bezel.
    public static let insideOverlap: CGFloat = outerPanelWidth - glassRailSideMargin + outerOnScreenClearance
    public static let haloThickness: CGFloat = 5
    /// Marker panels stretch vertically past the stashed window by half the
    /// capture band plus the pill radius, so the hover target comfortably
    /// covers the pill yet neighboring markers' zones stay distinct.
    public static let panelBleed: CGFloat = captureBand / 2 + barCornerRadius + 1
    /// Capture depth is frozen at the historical 14×3 value so widening the
    /// glass rail does not change when a drag commits.
    public static let captureBand: CGFloat = 42
    public static let mapEdgeHitWidth: CGFloat = 10
    /// Extra pointer slop at the bezel. Title-bar drags leave the cursor over
    /// the window, so capture also accepts a pointer inside the window frame.
    public static let capturePointerSlop: CGFloat = 80

    public static func quartzOriginY(
        appKitY: CGFloat,
        height: CGFloat,
        primaryHeight: CGFloat
    ) -> CGFloat {
        primaryHeight - appKitY - height
    }

    public static func appKitOriginY(
        quartzY: CGFloat,
        height: CGFloat,
        primaryHeight: CGFloat
    ) -> CGFloat {
        primaryHeight - quartzY - height
    }

    public static func cgRect(fromAppKit frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: quartzOriginY(appKitY: frame.minY, height: frame.height, primaryHeight: primaryHeight),
            width: frame.width,
            height: frame.height
        )
    }

    public static func appKitRect(fromQuartz frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: appKitOriginY(quartzY: frame.minY, height: frame.height, primaryHeight: primaryHeight),
            width: frame.width,
            height: frame.height
        )
    }

    public static func preferredCaptureEdge(
        windowFrame: CGRect,
        display: DisplayGeometry,
        snapSide: String,
        blockedDockSide: String?,
        selection: DisplayEdgeSelection
    ) -> DisplayEdge? {
        let scored = DisplayEdge.allCases.compactMap { edge -> (DisplayEdge, CGFloat)? in
            guard StashSessionPolicy.canCapture(
                edge: edge,
                snapSide: snapSide,
                blockedDockSide: blockedDockSide,
                edgeEnabled: selection.isEnabled(edge)
            ) else {
                return nil
            }
            switch edge {
            case .left:
                guard windowFrame.minX <= display.frame.minX + captureBand else { return nil }
                return (edge, (display.frame.minX + captureBand) - windowFrame.minX)
            case .right:
                guard windowFrame.maxX >= display.frame.maxX - captureBand else { return nil }
                return (edge, windowFrame.maxX - (display.frame.maxX - captureBand))
            }
        }
        return scored.max { lhs, rhs in
            if abs(lhs.1 - rhs.1) <= 1 {
                // A coin-flip band resolves toward the left edge, matching
                // reading order, so the outcome is stable across tiny drags.
                return lhs.0.rawValue > rhs.0.rawValue
            }
            return lhs.1 < rhs.1
        }?.0
    }

    public static func pointerAllowsEdgeCapture(
        mouse: CGPoint,
        edge: DisplayEdge,
        displayFrame: CGRect,
        windowFrame: CGRect,
        slop: CGFloat = capturePointerSlop
    ) -> Bool {
        if windowFrame.insetBy(dx: -1, dy: -1).contains(mouse) {
            return true
        }
        switch edge {
        case .left:
            return mouse.x <= displayFrame.minX + slop
        case .right:
            return mouse.x >= displayFrame.maxX - slop
        }
    }

    public static func owningDisplay(
        for frame: CGRect,
        in displays: [DisplayGeometry],
        preferredID: String? = nil
    ) -> DisplayGeometry? {
        let preferred = preferredID.flatMap { id in displays.first { $0.id == id } }
        if let preferred, parkedEdge(of: frame, in: preferred.frame) != nil {
            return preferred
        }
        if let home = displayContainingCenter(of: frame, in: displays) {
            return home
        }
        let overlaps = displays.compactMap { display -> (DisplayGeometry, CGFloat)? in
            let area = display.frame.intersection(frame)
            let size = area.width * area.height
            guard size.isFinite, size > 0 else { return nil }
            return (display, size)
        }
        if let preferred, overlaps.contains(where: { $0.0.id == preferred.id }) || overlaps.isEmpty {
            return preferred
        }
        if let best = overlaps.max(by: { $0.1 < $1.1 }) {
            return best.0
        }
        return nil
    }

    /// A window parked by a previous run shows only its edge lip: the sliver
    /// inside the owning display is lip-sized, hugging one edge, with the
    /// bulk of the window off-screen. Tolerance covers window-manager nudges
    /// between sessions.
    public static func parkedEdge(
        of frame: CGRect,
        in display: CGRect,
        overflowThreshold: CGFloat = 24,
        tolerance: CGFloat = 6
    ) -> DisplayEdge? {
        let visible = frame.intersection(display)
        guard !visible.isNull, visible.width.isFinite, visible.height.isFinite else { return nil }
        guard frame.width - visible.width > overflowThreshold else { return nil }
        let reach = edgeLip + tolerance
        guard visible.width <= reach else { return nil }
        if visible.maxX - display.minX <= reach { return .left }
        if display.maxX - visible.minX <= reach { return .right }
        return nil
    }

    public static func isStillOnStashEdge(
        frame: CGRect,
        display: CGRect,
        edge: DisplayEdge,
        presentation: StashCollapsePresentation
    ) -> Bool {
        switch presentation {
        case .slideOffscreen:
            return parkedEdge(of: frame, in: display) == edge
        case .systemMinimize:
            return true
        }
    }

    private static func displayContainingCenter(
        of frame: CGRect,
        in displays: [DisplayGeometry]
    ) -> DisplayGeometry? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let hits = displays.filter { $0.frame.contains(center) }
        if hits.count == 1 { return hits[0] }
        return hits.max { lhs, rhs in
            intersectionArea(frame, lhs.frame) < intersectionArea(frame, rhs.frame)
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let area = lhs.intersection(rhs)
        guard !area.isNull, area.width.isFinite, area.height.isFinite else { return 0 }
        return max(0, area.width * area.height)
    }

    /// Temporary / first-press shortcut: pick the nearest allowed edge even when
    /// the window is not already against it.
    public static func nearestAllowedEdge(
        windowFrame: CGRect,
        display: DisplayGeometry,
        snapSide: String,
        blockedDockSide: String?,
        selection: DisplayEdgeSelection
    ) -> DisplayEdge? {
        let scored = DisplayEdge.allCases.compactMap { edge -> (DisplayEdge, CGFloat)? in
            guard StashSessionPolicy.canCapture(
                edge: edge,
                snapSide: snapSide,
                blockedDockSide: blockedDockSide,
                edgeEnabled: selection.isEnabled(edge)
            ) else {
                return nil
            }
            switch edge {
            case .left:
                return (edge, abs(windowFrame.minX - display.frame.minX))
            case .right:
                return (edge, abs(windowFrame.maxX - display.frame.maxX))
            }
        }
        return scored.min { lhs, rhs in
            if abs(lhs.1 - rhs.1) < 0.5 {
                return lhs.0.rawValue < rhs.0.rawValue
            }
            return lhs.1 < rhs.1
        }?.0
    }

    public static func expandedOrigin(
        edge: DisplayEdge,
        frame: CGRect,
        display: CGRect,
        lockedWidth: CGFloat
    ) -> CGPoint {
        let width = lockedWidth > 0 ? lockedWidth : frame.width
        switch edge {
        case .left:
            return CGPoint(x: display.minX, y: frame.minY)
        case .right:
            return CGPoint(x: display.maxX - width, y: frame.minY)
        }
    }

    /// Leaves a narrow lip on the owning display so the marker can sit on the
    /// edge. Only exposed edges slide off; shared edges minimize instead, so
    /// a stashed window never parks its bulk on a neighboring display.
    public static func visualHiddenOrigin(
        edge: DisplayEdge,
        frame: CGRect,
        display: CGRect,
        lockedWidth: CGFloat
    ) -> CGPoint {
        let width = lockedWidth > 0 ? lockedWidth : frame.width
        switch edge {
        case .left:
            return CGPoint(x: display.minX - width + edgeLip, y: frame.minY)
        case .right:
            return CGPoint(x: display.maxX - edgeLip, y: frame.minY)
        }
    }

    public static func tintStrength(kind: StashOverlayKind, enabled: Bool) -> CGFloat {
        switch kind {
        case .outerStrip:
            return enabled ? 1 : 0.42
        case .seamBeacon:
            return enabled ? 0.5 : 0.28
        }
    }

    public static func haloTintStrength(kind: DisplayEdgePreviewKind) -> CGFloat {
        switch kind {
        case .slideOffscreen:
            return tintStrength(kind: .outerStrip, enabled: true)
        case .systemMinimize:
            return tintStrength(kind: .seamBeacon, enabled: true)
        case .disabled:
            return tintStrength(kind: .seamBeacon, enabled: false)
        }
    }

    public static func visibleRailRect(
        kind: StashOverlayKind,
        edge: DisplayEdge,
        in bounds: CGRect
    ) -> CGRect {
        let padding = panelBleed
        let height = max(bounds.height - padding * 2, 16)
        let y = bounds.minY + padding
        let x: CGFloat
        switch (kind, edge) {
        case (.outerStrip, _):
            x = bounds.minX + glassRailSideMargin
        case (.seamBeacon, .left):
            x = bounds.minX + seamGlassInset
        case (.seamBeacon, .right):
            x = bounds.maxX - seamGlassInset - barThickness
        }
        return CGRect(x: x, y: y, width: barThickness, height: height)
    }

    public static func seamInnerGapRect(in rail: CGRect) -> CGRect {
        let inset = min(8, max(0, rail.height / 6))
        return CGRect(
            x: rail.midX - seamInnerGap / 2,
            y: rail.minY + inset,
            width: seamInnerGap,
            height: max(0, rail.height - inset * 2)
        )
    }

    /// The panel overlaps `insideOverlap` points into the display, so the
    /// glass keeps `outerOnScreenClearance` on-screen; shared-edge rails sit
    /// flush inside instead.
    public static func markerPanelFrame(
        kind: StashOverlayKind,
        edge: DisplayEdge,
        windowQuartz: CGRect,
        displayAppKit: CGRect,
        primaryHeight: CGFloat
    ) -> CGRect {
        let height = max(windowQuartz.height, 24)
        let appKitY = appKitOriginY(
            quartzY: windowQuartz.minY,
            height: height,
            primaryHeight: primaryHeight
        )
        let panelWidth = kind == .outerStrip ? outerPanelWidth : seamPanelWidth
        let x: CGFloat
        switch (kind, edge) {
        case (.outerStrip, .left):
            x = displayAppKit.minX - panelWidth + insideOverlap
        case (.outerStrip, .right):
            x = displayAppKit.maxX - insideOverlap
        case (.seamBeacon, .left):
            x = displayAppKit.minX
        case (.seamBeacon, .right):
            x = displayAppKit.maxX - panelWidth
        }
        return CGRect(
            x: x,
            y: appKitY - panelBleed,
            width: panelWidth,
            height: height + panelBleed * 2
        )
    }

    public static func haloBand(
        edge: DisplayEdge,
        displayAppKit: CGRect,
        thickness: CGFloat = haloThickness
    ) -> CGRect {
        switch edge {
        case .left:
            return CGRect(
                x: displayAppKit.minX,
                y: displayAppKit.minY,
                width: thickness,
                height: displayAppKit.height
            )
        case .right:
            return CGRect(
                x: displayAppKit.maxX - thickness,
                y: displayAppKit.minY,
                width: thickness,
                height: displayAppKit.height
            )
        }
    }

    public static func hitMapEdge(
        at point: CGPoint,
        slots: [DisplayArrangementSlot],
        hitWidth: CGFloat = mapEdgeHitWidth
    ) -> (displayID: String, edge: DisplayEdge)? {
        for slot in slots {
            let frame = slot.canvasFrame
            let leftBand = CGRect(
                x: frame.minX - hitWidth,
                y: frame.minY,
                width: hitWidth * 2,
                height: frame.height
            )
            let rightBand = CGRect(
                x: frame.maxX - hitWidth,
                y: frame.minY,
                width: hitWidth * 2,
                height: frame.height
            )
            if leftBand.contains(point) { return (slot.id, .left) }
            if rightBand.contains(point) { return (slot.id, .right) }
        }
        return nil
    }
}

public enum HaloPreviewPolicy {
    public static func shouldClear(settingsTabIsBehavior: Bool, settingsWindowVisible: Bool) -> Bool {
        !settingsWindowVisible || !settingsTabIsBehavior
    }

    public static func shouldForgetTarget(settingsTabIsBehavior: Bool, settingsWindowVisible: Bool) -> Bool {
        shouldClear(
            settingsTabIsBehavior: settingsTabIsBehavior,
            settingsWindowVisible: settingsWindowVisible
        )
    }
}
