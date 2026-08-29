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
    /// The visible pill of an outer marker: 5pt thick — half a finger-width
    /// at arm's length, thick enough to spot, thin enough to ignore — with a
    /// fully-rounded cap.
    public static let barThickness: CGFloat = 5
    public static let barCornerRadius: CGFloat = barThickness / 2
    /// A parked window keeps a two-point lip inside the owning display so it
    /// stays composited and AX-addressable; a single point rounds away on
    /// scaled displays.
    public static let edgeLip: CGFloat = 2
    /// Marker panel windows: wide enough to hold the pill plus a transparent
    /// approach margin, so the pill never sits against the window's own edge
    /// where compositing can clip it.
    public static let outerPanelWidth: CGFloat = 14
    public static let seamPanelWidth: CGFloat = 10
    /// How far a marker panel overlaps into the display: enough to keep the
    /// pill (plus a point of breathing room) on-screen, with the rest hanging
    /// over the bezel side of the edge.
    public static let insideOverlap: CGFloat = 6
    public static let haloThickness: CGFloat = 8
    /// Marker panels stretch vertically past the stashed window by half the
    /// capture band plus the pill radius, so the hover target comfortably
    /// covers the pill yet neighboring markers' zones stay distinct.
    public static let panelBleed: CGFloat = captureBand / 2 + barCornerRadius + 1
    /// A window is captured once its edge enters a band three marker-widths
    /// deep: wide enough to catch a confident drag, narrow enough that
    /// parking a window near an edge is not a commitment.
    public static let captureBand: CGFloat = outerPanelWidth * 3
    public static let mapEdgeHitWidth: CGFloat = 10

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
    /// edge. Shared edges use this path only when separate display Spaces are
    /// expected to clip the offscreen portion; the minimize fallback does not.
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

    /// The panel overlaps `insideOverlap` points into the display, so the
    /// pill drawn at the panel's inner edge sits fully on-screen with a point
    /// of clearance; shared-edge beacons sit flush inside instead.
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
}
