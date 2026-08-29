import CoreGraphics
import Foundation

/// Motion rules for the stash slide.
///
/// The slide itself is one symmetric quintic smoothstep — zero velocity and
/// zero acceleration at both endpoints — traversed in opposite directions for
/// stash and reveal. Spans follow the "exits quicker than entries" screen-edge
/// convention: revealing a stash gets the longest span, collapsing a stash a
/// middle one, and motion inside a merged strip the shortest, since merged
/// strips trade decoration for snappy switching.
///
/// Every AX position write is a cross-process RPC into the owning app. The
/// animator therefore spends at most one write per refresh tick and never
/// exceeds a 90 writes-per-second ceiling — enough headroom above a 60Hz
/// display's refresh without letting a 120Hz link double the load on the
/// target's main run loop.
///
/// Time a write spends blocked pauses the animation clock: the blockage
/// lengthens the effective span rather than skipping position, capped at a
/// fraction of the span so a wedged target cannot stall a stash forever.
///
/// The locked size rides along on every third write instead of special
/// checkpoints, so any relayout the owning app performs is corrected within
/// three ticks wherever it happens, at a third of the extra IPC cost.
public enum StashMotionPolicy {
    public static let revealSpan: TimeInterval = 0.26
    public static let stashSpan: TimeInterval = 0.18
    public static let mergedSpan: TimeInterval = 0.16
    public static let maxWriteRate: Double = 90
    public static let stallFraction: CGFloat = 0.35
    public static let sizeWriteStride: Int = 3

    public static func span(
        reduceMotion: Bool,
        collapsing: Bool,
        merged: Bool = false
    ) -> TimeInterval {
        if reduceMotion { return 0 }
        if merged { return mergedSpan }
        return collapsing ? stashSpan : revealSpan
    }

    public static func shouldAnimate(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// Quintic smoothstep: `6t⁵ − 15t⁴ + 10t³`, symmetric about the midpoint.
    public static func easedProgress(_ progress: CGFloat) -> CGFloat {
        let t = min(max(progress, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// Clamped fraction of the span an elapsed interval represents. A span of
    /// zero (reduced motion) reads as complete. Callers feeding the result
    /// back into position writes keep their own monotonic view, because stall
    /// refunds shift the clock between ticks.
    public static func progress(elapsed: TimeInterval, span: TimeInterval) -> CGFloat {
        guard span > 0 else { return 1 }
        return CGFloat(min(max(elapsed, 0) / span, 1))
    }

    public static func interpolated(from start: CGFloat, to end: CGFloat, eased: CGFloat) -> CGFloat {
        start + (end - start) * eased
    }

    /// Minimum spacing between two AX writes given how far apart refresh
    /// ticks arrived: one write per tick, never tighter than the ceiling. A
    /// nil period (unknown refresh) falls back to the ceiling itself.
    public static func writeInterval(linkPeriod: TimeInterval?) -> TimeInterval {
        let ceiling = 1.0 / maxWriteRate
        guard let linkPeriod, linkPeriod > 0 else { return ceiling }
        return max(linkPeriod, ceiling)
    }

    /// Pause length for a write that blocked longer than its budget: the
    /// overage extends the effective span, bounded by the stall fraction.
    public static func stallPause(
        writeSeconds: TimeInterval,
        budget: TimeInterval,
        pausedSoFar: TimeInterval,
        span: TimeInterval
    ) -> TimeInterval {
        let overage = writeSeconds - budget
        guard overage > 0 else { return 0 }
        let headroom = span * stallFraction - pausedSoFar
        return max(0, min(overage, headroom))
    }

    /// Which writes carry the locked size: the first (before the owning app
    /// notices the move), the last (to win any deferred relayout), and every
    /// `sizeWriteStride`-th write in between.
    public static func shouldWriteSize(
        writeIndex: Int,
        finished: Bool
    ) -> Bool {
        if finished { return true }
        if writeIndex <= 0 { return true }
        return writeIndex % sizeWriteStride == 0
    }

    /// Pin control motion. Surfaces quicker than they leave: the reveal has a
    /// beat to read as intentional, the retire is shorter so the control
    /// never lingers over content.
    public static func pinRevealSpan(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.1 : 0.26
    }

    public static func pinRetireSpan(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.08 : 0.16
    }

    public static func shouldEmitVisualEffects(
        enabled: Bool,
        reduceMotion: Bool,
        mergedLocked: Bool
    ) -> Bool {
        enabled && !reduceMotion && !mergedLocked
    }
}
