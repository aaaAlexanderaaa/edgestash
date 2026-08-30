import AppKit
import EdgeStashLogic

/// Desktop placeholder for a collapsed stash. Outer strip and seam beacon share
/// restore actions but draw as distinct presentations.
///
/// The whole panel is the hover and click target; the drawn pill is only the
/// visible affordance. A pill-sized target is unhittable at a seam, where the
/// pointer cannot be slammed into a bezel and a gentle approach crosses a
/// two-point strip in a single event.
final class StashMarkerWindow: NSPanel {
    var onHoverEntered: (() -> Void)?
    var onHoverExited: (() -> Void)?
    var onClicked: (() -> Void)?

    private let markView = StashMarkerView()
    private var pointerInside = false
    private var interactionEnabled = true
    private var disabledExplanation = ""
    private var currentEdge: DisplayEdge = .left
    private var explanationPanel: NSPanel?
    private var explanationTimer: Timer?
    /// A fade-out completion fires after its animation group even when a new
    /// present has already started; the generation guard keeps a stale
    /// completion from ordering out a re-presented panel.
    private var fadeGeneration = 0

    /// Placeholder frame until the first present; sized from the marker
    /// metrics so the placeholder already matches real geometry.
    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: StashGeometryPolicy.outerPanelWidth,
                height: 240
            ),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        level = .mainMenu
        // The marker is a permanent signal above every app's windows:
        // canJoinAllSpaces + fullScreenAuxiliary keep it visible on any Space
        // (including full-screen apps), and stationary keeps the system from
        // sweeping it aside during full-screen transitions.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = markView
        markView.autoresizingMask = [.width, .height]
        markView.addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(
        kind: StashOverlayKind,
        edge: DisplayEdge,
        color: NSColor,
        frame: CGRect,
        title: String,
        enabled: Bool,
        disabledExplanation: String,
        reduceMotion: Bool
    ) {
        fadeGeneration += 1
        if interactionEnabled, !enabled, pointerInside {
            onHoverExited?()
        }
        interactionEnabled = enabled
        self.disabledExplanation = disabledExplanation
        currentEdge = edge
        markView.apply(kind: kind, edge: edge, color: color, title: title, enabled: enabled)
        setFrame(frame, display: true)
        fade(visible: true, reduceMotion: reduceMotion)
        orderFront(nil)
    }

    func dismiss(reduceMotion: Bool) {
        pointerInside = false
        dismissExplanation()
        fadeGeneration += 1
        let generation = fadeGeneration
        fade(visible: false, reduceMotion: reduceMotion) { [weak self] in
            guard let self, self.fadeGeneration == generation else { return }
            self.orderOut(nil)
        }
    }

    override func mouseEntered(with event: NSEvent) { reconcilePointer(inside: true) }
    override func mouseMoved(with event: NSEvent) { reconcilePointer(inside: true) }

    override func mouseExited(with event: NSEvent) {
        reconcilePointer(inside: false)
    }

    override func mouseDown(with event: NSEvent) {
        reconcilePointer(inside: true)
        if interactionEnabled {
            onClicked?()
        } else {
            showDisabledExplanation()
        }
    }

    private func reconcilePointer(inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        guard interactionEnabled else { return }
        if inside {
            onHoverEntered?()
        } else {
            onHoverExited?()
        }
    }

    func showDisabledExplanation() {
        guard !disabledExplanation.isEmpty else { return }
        guard SpaceChangePolicy.shouldPresentSeamLimitationExplanation(
            alreadyAdvised: Preferences.shared.advisedSeamRevealLimitation
        ) else { return }
        Preferences.shared.advisedSeamRevealLimitation = true
        dismissExplanation()

        let width: CGFloat = 360
        let inset: CGFloat = 16
        let title = NSTextField(labelWithString: L10n.seamLimitationTitle)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.drawsBackground = false
        title.isBezeled = false
        let body = NSTextField(wrappingLabelWithString: disabledExplanation)
        body.font = .systemFont(ofSize: 13, weight: .regular)
        body.textColor = .secondaryLabelColor
        body.drawsBackground = false
        body.isBezeled = false
        let bodySize = body.sizeThatFits(NSSize(width: width - inset * 2, height: 400))
        let titleHeight: CGFloat = 20
        let height = inset + titleHeight + 8 + bodySize.height + inset
        title.frame = CGRect(x: inset, y: height - inset - titleHeight, width: width - inset * 2, height: titleHeight)
        body.frame = CGRect(x: inset, y: inset, width: width - inset * 2, height: bodySize.height)

        let plate = StashLimitationPlateView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        plate.addSubview(title)
        plate.addSubview(body)

        let panel = NSPanel(
            contentRect: plate.bounds,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .mainMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = plate

        let screen = self.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) })
        let visible = screen?.visibleFrame ?? frame.insetBy(dx: -width, dy: -height)
        let preferredX = currentEdge == .left ? frame.maxX + 10 : frame.minX - width - 10
        let origin = CGPoint(
            x: min(max(preferredX, visible.minX + 8), visible.maxX - width - 8),
            y: min(max(frame.midY - height / 2, visible.minY + 8), visible.maxY - height - 8)
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        explanationPanel = panel
        explanationTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            self?.dismissExplanation()
        }
    }

    private func dismissExplanation() {
        explanationTimer?.invalidate()
        explanationTimer = nil
        explanationPanel?.orderOut(nil)
        explanationPanel = nil
    }

    /// Arrivals get a beat to read as intentional; departures are quicker so
    /// the placeholder never lingers.
    private func fade(visible: Bool, reduceMotion: Bool, completion: (() -> Void)? = nil) {
        let duration: TimeInterval
        if reduceMotion {
            duration = 0.08
        } else {
            duration = visible ? 0.2 : 0.14
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            animator().alphaValue = visible ? 1 : 0
        }, completionHandler: completion)
    }
}

private final class StashLimitationPlateView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            StashGlassPainter.paintCapsule(bounds.insetBy(dx: 1, dy: 1), tint: .white, strength: 0.72)
        }
    }
}

private final class StashMarkerView: NSView {
    private var kind: StashOverlayKind = .outerStrip
    private var edge: DisplayEdge = .left
    private var fill = NSColor.white
    private var title = ""
    private var enabled = true
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

    func apply(kind: StashOverlayKind, edge: DisplayEdge, color: NSColor, title: String, enabled: Bool) {
        self.kind = kind
        self.edge = edge
        self.fill = color
        self.title = title
        self.enabled = enabled
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        setAccessibilityEnabled(enabled)
        glass.apply(role: .rail(kind: kind, edge: edge, enabled: enabled), tint: color)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard kind == .seamBeacon, !enabled else { return }
        let mark = StashGeometryPolicy.visibleRailRect(kind: kind, edge: edge, in: bounds)
        guard !mark.isEmpty else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let badge = CGRect(x: mark.midX - 4, y: mark.midY - 4, width: 8, height: 8)
            NSColor.disabledControlTextColor.withAlphaComponent(0.72).setStroke()
            let path = NSBezierPath(ovalIn: badge)
            path.lineWidth = 1.25
            path.stroke()
            let slash = NSBezierPath()
            slash.move(to: CGPoint(x: badge.minX + 1.5, y: badge.minY + 1.5))
            slash.line(to: CGPoint(x: badge.maxX - 1.5, y: badge.maxY - 1.5))
            slash.lineWidth = 1.1
            slash.stroke()
        }
    }
}
