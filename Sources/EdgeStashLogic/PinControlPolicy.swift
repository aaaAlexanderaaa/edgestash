import CoreGraphics
import Foundation

public struct PinControlFrames: Equatable {
    public let buttonFrame: CGRect
    public let hiddenFrame: CGRect
    public let triggerRect: CGRect
    public let safeRect: CGRect

    public init(buttonFrame: CGRect, hiddenFrame: CGRect, triggerRect: CGRect, safeRect: CGRect) {
        self.buttonFrame = buttonFrame
        self.hiddenFrame = hiddenFrame
        self.triggerRect = triggerRect
        self.safeRect = safeRect
    }
}

/// Pin button for an expanded stash: parked half-embedded in the window's
/// top corner, sliding out onto whichever side of the stash has room. Pinned
/// windows do not auto-collapse on leave or Dock activation.
///
/// Metrics: the button is the HIG 28pt small-control size; the gap to the
/// window and the screen-edge padding are two 8pt grid units each; the parked
/// state buries exactly half the disc in the window edge so the peek reads
/// the same from both sides; the pointer reach around the travel path is one
/// grid unit. The top inset keeps the disc inside the title-bar band instead
/// of flush with glass.
public enum PinControlPolicy {
    public static let buttonSize: CGFloat = 28
    public static let sideGap: CGFloat = 16
    public static let minEdgePadding: CGFloat = 16
    public static let topInset: CGFloat = 4
    public static let pointerReach: CGFloat = 8
    public static let hiddenEmbedFraction: CGFloat = 0.5

    /// Where the control wants to sit: on the side away from the stash edge,
    /// so it never hovers over whatever the window reveals.
    private static func preferredSide(for stashEdge: DisplayEdge) -> DisplayEdge {
        stashEdge == .left ? .right : .left
    }

    private static func clearsOnLeft(_ window: CGRect, screen: CGRect) -> Bool {
        window.minX - sideGap - buttonSize >= screen.minX + minEdgePadding
    }

    private static func clearsOnRight(_ window: CGRect, screen: CGRect) -> Bool {
        window.maxX + sideGap + buttonSize <= screen.maxX - minEdgePadding
    }

    public static func frames(
        edge: DisplayEdge,
        windowAppKit: CGRect,
        screenAppKit: CGRect
    ) -> PinControlFrames {
        let preferred = preferredSide(for: edge)
        let fitsLeft = clearsOnLeft(windowAppKit, screen: screenAppKit)
        let fitsRight = clearsOnRight(windowAppKit, screen: screenAppKit)
        let side: DisplayEdge
        switch preferred {
        case .left:
            side = fitsLeft ? .left : .right
        case .right:
            side = fitsRight ? .right : .left
        }

        // Parked slot: half the disc buried in the window edge at the top.
        let restingY = windowAppKit.maxY - buttonSize - topInset
        let buriedDepth = buttonSize * hiddenEmbedFraction
        let slotX: CGFloat
        let placedX: CGFloat
        if side == .right {
            slotX = windowAppKit.maxX - buriedDepth
            placedX = windowAppKit.maxX + sideGap
        } else {
            slotX = windowAppKit.minX - buttonSize + buriedDepth
            placedX = windowAppKit.minX - sideGap - buttonSize
        }

        // Keep the placed slot on screen when the window abuts an edge.
        let placedXClamped = min(
            max(placedX, screenAppKit.minX + minEdgePadding),
            screenAppKit.maxX - buttonSize - minEdgePadding
        )
        let placedYClamped = min(
            max(restingY, screenAppKit.minY + minEdgePadding),
            screenAppKit.maxY - buttonSize - minEdgePadding
        )
        let placed = CGRect(x: placedXClamped, y: placedYClamped, width: buttonSize, height: buttonSize)
        let parked = CGRect(x: slotX, y: restingY, width: buttonSize, height: buttonSize)

        // The pointer's welcome mat: the travel corridor between parked and
        // placed, grown by the reach on every side.
        let corridor = parked.union(placed).insetBy(
            dx: -pointerReach,
            dy: -pointerReach
        )
        // The corner pad catches a pointer running along the top edge even
        // when the control itself is parked.
        let cornerSpan = buttonSize + sideGap + pointerReach
        let triggerRect: CGRect
        if side == .right {
            triggerRect = CGRect(
                x: windowAppKit.maxX - cornerSpan,
                y: windowAppKit.maxY - cornerSpan,
                width: cornerSpan,
                height: cornerSpan
            )
        } else {
            triggerRect = CGRect(
                x: windowAppKit.minX,
                y: windowAppKit.maxY - cornerSpan,
                width: cornerSpan,
                height: cornerSpan
            )
        }

        return PinControlFrames(
            buttonFrame: placed,
            hiddenFrame: parked,
            triggerRect: triggerRect,
            safeRect: corridor
        )
    }

    public static func shouldReveal(
        isPinned: Bool,
        mouseInTrigger: Bool,
        mouseInSafe: Bool
    ) -> Bool {
        isPinned || mouseInTrigger || mouseInSafe
    }

    public static func shouldShowControl(isExpanded: Bool, isPinned: Bool, isBusy: Bool) -> Bool {
        if isBusy { return false }
        return isPinned || isExpanded
    }

    public static func shouldAutoCollapse(isPinned: Bool) -> Bool {
        !isPinned
    }
}
