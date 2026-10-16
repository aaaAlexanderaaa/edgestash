import ApplicationServices
import CoreVideo
import EdgeStashLogic
import Foundation

/// Executes one presentation plan of a foreign window along the display link.
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
        let span: TimeInterval
        /// Refund blocked-write time against the span via
        /// `StashMotionPolicy.stallPause`. Merged strips switch without it:
        /// switching latency matters more there than a finished glide.
        let refundsClock: Bool
        let plan: StashPresentationPlan
        let windowID: UInt32?

        init(
            target: AXUIElement,
            span: TimeInterval,
            refundsClock: Bool,
            plan: StashPresentationPlan,
            windowID: UInt32?
        ) {
            self.target = target
            self.span = span
            self.refundsClock = refundsClock
            self.plan = plan
            self.windowID = windowID
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
    private var settled: ((Bool) -> Void)?
    private var finalPlacementSucceeded = false

    /// Starts a slide, replacing any run in flight. A zero span (reduced
    /// motion) places the window directly and settles immediately.
    func begin(_ slide: Slide, onSettled: @escaping (Bool) -> Void) {
        abort()
        finalPlacementSucceeded = false
        guard perform(slide.plan.preparation, slide: slide) else {
            onSettled(false)
            return
        }
        if slide.span <= 0 {
            onSettled(perform(slide.plan.completion, slide: slide))
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
            finalPlacementSucceeded = perform(slide.plan.completion, slide: slide)
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

        if finished {
            // Elapsed time is not evidence that AX accepted the destination.
            // Size first, position last: a resize can itself adjust position.
            finalPlacementSucceeded = perform(slide.plan.completion, slide: slide)
            return true
        }

        let budget = StashMotionPolicy.writeInterval(linkPeriod: wakeGap > 0 ? wakeGap : nil)
        if !finished && now < nextWriteAt { return false }
        nextWriteAt = now + budget

        let sample = slide.plan.sample(fraction)
        let writeBegan = CFAbsoluteTimeGetCurrent()
        if slide.plan.changesOpacity {
            var writes: [StashPresentationPlan.Write] = []
            if slide.plan.movesDuringAnimation { writes.append(.position(sample.position)) }
            writes.append(.alpha(sample.alpha))
            guard perform(writes, slide: slide) else { return true }
        } else {
            _ = StashAX.setPositionStatus(slide.target, sample.position)
        }
        let writeSeconds = CFAbsoluteTimeGetCurrent() - writeBegan
        if slide.refundsClock {
            clockCredit += StashMotionPolicy.stallPause(
                writeSeconds: writeSeconds,
                budget: budget,
                pausedSoFar: clockCredit,
                span: slide.span
            )
        }
        if slide.plan.movesDuringAnimation && StashMotionPolicy.shouldWriteSize(writeIndex: writes, finished: finished) {
            _ = StashAX.setSize(slide.target, slide.plan.size)
        }
        writes += 1
        return finished
    }

    private func finish() {
        haltLink()
        active = nil
        let handler = settled
        settled = nil
        handler?(finalPlacementSucceeded)
    }

    private func perform(_ writes: [StashPresentationPlan.Write], slide: Slide) -> Bool {
        StashPresentationPlan.perform(writes) { write in
            switch write {
            case let .frame(frame): return StashAX.setFrame(slide.target, frame)
            case let .position(point): return StashAX.setPositionStatus(slide.target, point) == .success
            case let .alpha(alpha):
                guard let windowID = slide.windowID else { return false }
                return StashSurface.setAlpha(windowID: windowID, alpha: Float(alpha))
            }
        }
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
