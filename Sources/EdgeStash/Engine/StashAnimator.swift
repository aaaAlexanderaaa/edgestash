import ApplicationServices
import CoreVideo
import EdgeStashLogic
import Foundation

/// Drives one slide of a foreign window along the display link.
///
/// Everything that describes the motion rides in a single `Slide` value, so
/// the animator only keeps pacing state: when the next write may go out, how
/// far apart refresh ticks arrive, how much clock the target's slow writes
/// have consumed, and the highest fraction already presented. The link
/// callback only wakes the main queue; every AX write and the completion run
/// there, so a slide cannot race session teardown. All motion math — spans,
/// easing, write budgets, stall refunds — lives in StashMotionPolicy.
final class StashAnimator {
    /// One slide of one window, immutable for its lifetime.
    struct Slide {
        let target: AXUIElement
        let origin: CGPoint
        let destination: CGPoint
        let span: TimeInterval
        let size: CGSize
        /// Refund blocked-write time against the span via
        /// `StashMotionPolicy.stallPause`. Merged strips switch without it:
        /// switching latency matters more there than a finished glide.
        let refundsClock: Bool

        init(
            target: AXUIElement,
            origin: CGPoint,
            destination: CGPoint,
            span: TimeInterval,
            size: CGSize,
            refundsClock: Bool
        ) {
            self.target = target
            self.origin = origin
            self.destination = destination
            self.span = span
            self.size = size
            self.refundsClock = refundsClock
        }
    }

    private var link: CVDisplayLink?
    private var active: Slide?
    private var beganAt: CFAbsoluteTime = 0
    private var clockCredit: TimeInterval = 0
    private var nextWriteAt: CFAbsoluteTime = 0
    private var lastWakeAt: CFAbsoluteTime = 0
    private var wakeGap: TimeInterval = 0
    private var presentedFraction: CGFloat = 0
    private var writes = 0
    private var settled: (() -> Void)?

    /// Starts a slide, replacing any run in flight. A zero span (reduced
    /// motion) places the window directly and settles immediately.
    func begin(_ slide: Slide, onSettled: @escaping () -> Void) {
        abort()
        if slide.span <= 0 {
            _ = StashAX.setPosition(slide.target, slide.destination)
            _ = StashAX.setSize(slide.target, slide.size)
            onSettled()
            return
        }
        active = slide
        settled = onSettled
        beganAt = CFAbsoluteTimeGetCurrent()
        clockCredit = 0
        nextWriteAt = 0
        lastWakeAt = 0
        wakeGap = 0
        presentedFraction = 0
        writes = 0

        var created: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&created) == kCVReturnSuccess, let created else {
            _ = StashAX.setPosition(slide.target, slide.destination)
            _ = StashAX.setSize(slide.target, slide.size)
            finish()
            return
        }
        link = created
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context in
            let animator = Unmanaged<StashAnimator>.fromOpaque(context!).takeUnretainedValue()
            DispatchQueue.main.async {
                animator.wake()
            }
            return kCVReturnSuccess
        }
        CVDisplayLinkSetOutputCallback(created, callback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(created)
    }

    /// Drops the run in flight without settling: the completion belongs to a
    /// session that is already going away.
    func cancel() {
        abort()
    }

    /// Main-queue tick. Refresh ticks arrive irregularly across displays, so
    /// the gap between them is averaged into the period the write budget is
    /// derived from.
    private func wake() {
        guard active != nil else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if lastWakeAt > 0 {
            let gap = now - lastWakeAt
            wakeGap = wakeGap == 0 ? gap : (wakeGap + gap) / 2
        }
        lastWakeAt = now
        if advance(now: now) {
            finish()
        }
    }

    /// Presents the next frame; true once the slide has reached its end.
    private func advance(now: CFAbsoluteTime) -> Bool {
        guard let slide = active else { return true }
        let healthy = max(0, now - beganAt - clockCredit)
        let fraction = max(
            StashMotionPolicy.progress(elapsed: healthy, span: slide.span),
            presentedFraction
        )
        presentedFraction = fraction
        let finished = fraction >= 1

        let budget = StashMotionPolicy.writeInterval(linkPeriod: wakeGap > 0 ? wakeGap : nil)
        if !finished && now < nextWriteAt { return false }
        nextWriteAt = now + budget

        let eased = StashMotionPolicy.easedProgress(fraction)
        let position = CGPoint(
            x: StashMotionPolicy.interpolated(from: slide.origin.x, to: slide.destination.x, eased: eased),
            y: StashMotionPolicy.interpolated(from: slide.origin.y, to: slide.destination.y, eased: eased)
        )
        let writeBegan = CFAbsoluteTimeGetCurrent()
        _ = StashAX.setPositionStatus(slide.target, position)
        let writeSeconds = CFAbsoluteTimeGetCurrent() - writeBegan
        if slide.refundsClock {
            clockCredit += StashMotionPolicy.stallPause(
                writeSeconds: writeSeconds,
                budget: budget,
                pausedSoFar: clockCredit,
                span: slide.span
            )
        }
        if StashMotionPolicy.shouldWriteSize(writeIndex: writes, finished: finished) {
            _ = StashAX.setSize(slide.target, slide.size)
        }
        writes += 1
        return finished
    }

    private func finish() {
        haltLink()
        active = nil
        let handler = settled
        settled = nil
        handler?()
    }

    private func abort() {
        haltLink()
        active = nil
        settled = nil
    }

    private func haltLink() {
        if let link {
            CVDisplayLinkStop(link)
            self.link = nil
        }
    }
}
