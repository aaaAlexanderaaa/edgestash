import AppKit
import EdgeStashLogic
import QuartzCore

/// The floating pin control for an expanded stash. Lifecycle is a small
/// explicit phase machine (hidden → revealing → shown → hiding) so teardown
/// paths can call `conceal()` without the window having to intercept its own
/// `orderOut` to stay consistent.
final class StashPinWindow: NSPanel {
    var onToggle: (() -> Void)?

    private let button = StashPinButton()
    private var phase = Phase.hidden
    private var latestFrames: PinControlFrames?

    private enum Phase {
        case hidden
        case revealing
        case shown
        case hiding
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PinControlPolicy.buttonSize, height: PinControlPolicy.buttonSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        level = .mainMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        button.onToggle = { [weak self] in self?.onToggle?() }
        button.autoresizingMask = [.width, .height]
        contentView = button
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }

    func update(
        frames: PinControlFrames,
        visible: Bool,
        pinned: Bool,
        accent: NSColor,
        reduceMotion: Bool
    ) {
        button.apply(pinned: pinned, accent: accent)
        latestFrames = frames
        if visible {
            surface(frames: frames, reduceMotion: reduceMotion)
        } else {
            tuckAway(frames: frames, reduceMotion: reduceMotion)
        }
    }

    /// Hard teardown: no animation, phase reset. Engine paths that tear the
    /// session down call this instead of ordering the panel out themselves.
    func conceal() {
        phase = .hidden
        alphaValue = 0
        super.orderOut(nil)
    }

    private func surface(frames: PinControlFrames, reduceMotion: Bool) {
        switch phase {
        case .shown:
            setFrame(frames.buttonFrame, display: true)
            alphaValue = 1
        case .revealing:
            setFrame(frames.buttonFrame, display: true)
        case .hiding, .hidden:
            phase = .revealing
            alphaValue = 0
            setFrame(frames.hiddenFrame, display: false)
            orderFront(nil)
            glide(
                to: frames.buttonFrame,
                alpha: 1,
                span: StashMotionPolicy.pinRevealSpan(reduceMotion: reduceMotion),
                settling: { [weak self] in
                    guard let self, self.phase == .revealing else { return }
                    self.phase = .shown
                }
            )
        }
    }

    private func tuckAway(frames: PinControlFrames, reduceMotion: Bool) {
        switch phase {
        case .hidden:
            break
        case .hiding:
            break
        case .revealing, .shown:
            phase = .hiding
            glide(
                to: frames.hiddenFrame,
                alpha: 0,
                span: StashMotionPolicy.pinRetireSpan(reduceMotion: reduceMotion),
                settling: { [weak self] in
                    guard let self, self.phase == .hiding else { return }
                    self.conceal()
                }
            )
        }
    }

    /// Departures accelerate, arrivals decelerate — the standard screen-edge
    /// motion pairing — so the timing function follows the direction.
    private func glide(to frame: CGRect, alpha: CGFloat, span: TimeInterval, settling: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = span
            context.timingFunction = CAMediaTimingFunction(name: alpha > 0 ? .easeOut : .easeIn)
            animator().alphaValue = alpha
            animator().setFrame(frame, display: true)
        }, completionHandler: settling)
    }
}

private final class StashPinButton: NSView {
    var onToggle: (() -> Void)?
    private var pinned = false
    private var accent = NSColor.systemOrange
    private var pressed = false
    private var hovered = false
    private let glass = StashGlassSurface()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
    }

    func apply(pinned: Bool, accent: NSColor) {
        self.pinned = pinned
        self.accent = accent
        glass.apply(role: .disc, tint: accent)
        needsDisplay = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(pinned ? L10n.pinRelease : L10n.pinPlace)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        pressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        needsDisplay = true
        if inside { onToggle?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let symbol = pinned ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let tinted = image.tinted(with: pinned ? NSColor.white : accent)
        let size = CGSize(width: 14, height: 14)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        tinted.draw(in: CGRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: pressed ? 0.7 : 1)
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let copy = copy() as? NSImage ?? self
        copy.lockFocus()
        color.set()
        let bounds = NSRect(origin: .zero, size: copy.size)
        bounds.fill(using: .sourceAtop)
        copy.unlockFocus()
        copy.isTemplate = false
        return copy
    }
}
