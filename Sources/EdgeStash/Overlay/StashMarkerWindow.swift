import AppKit
import EdgeStashLogic

/// Desktop placeholder for a collapsed stash. Outer strip and seam beacon share
/// restore actions but draw as distinct presentations.
///
/// All pointer events funnel through one reconciler that keeps the hover flag
/// in step with the visible mark, so a click landing directly on the mark
/// enters hover state through the same path as a move — there is no separate
/// click-time patch-up.
final class StashMarkerWindow: NSPanel {
    var onHoverEntered: (() -> Void)?
    var onHoverExited: (() -> Void)?
    var onClicked: (() -> Void)?

    private let markView = StashMarkerView()
    private var pointerInside = false

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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = markView
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
        reduceMotion: Bool
    ) {
        markView.apply(kind: kind, edge: edge, color: color, title: title)
        setFrame(frame, display: true)
        fade(visible: true, reduceMotion: reduceMotion)
        orderFront(nil)
    }

    func dismiss(reduceMotion: Bool) {
        pointerInside = false
        fade(visible: false, reduceMotion: reduceMotion) { [weak self] in
            self?.orderOut(nil)
        }
    }

    override func mouseEntered(with event: NSEvent) { reconcilePointer(with: event) }
    override func mouseMoved(with event: NSEvent) { reconcilePointer(with: event) }

    override func mouseExited(with event: NSEvent) {
        reconcilePointer(inside: false)
    }

    override func mouseDown(with event: NSEvent) {
        let point = markView.convert(event.locationInWindow, from: nil)
        reconcilePointer(at: point)
        guard markView.containsVisibleMark(point) else {
            super.mouseDown(with: event)
            return
        }
        onClicked?()
    }

    private func reconcilePointer(with event: NSEvent) {
        reconcilePointer(at: markView.convert(event.locationInWindow, from: nil))
    }

    private func reconcilePointer(at point: CGPoint) {
        reconcilePointer(inside: markView.containsVisibleMark(point))
    }

    private func reconcilePointer(inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        if inside {
            onHoverEntered?()
        } else {
            onHoverExited?()
        }
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

private final class StashMarkerView: NSView {
    private var kind: StashOverlayKind = .outerStrip
    private var edge: DisplayEdge = .left
    private var fill = NSColor.white
    private var title = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func apply(kind: StashOverlayKind, edge: DisplayEdge, color: NSColor, title: String) {
        self.kind = kind
        self.edge = edge
        self.fill = color
        self.title = title
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        needsDisplay = true
    }

    func containsVisibleMark(_ point: CGPoint) -> Bool {
        visibleMarkRect().contains(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let mark = visibleMarkRect()
        guard !mark.isEmpty else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch kind {
            case .outerStrip:
                let radius = StashGeometryPolicy.barCornerRadius
                let path = NSBezierPath(roundedRect: mark, xRadius: radius, yRadius: radius)
                fill.setFill()
                path.fill()
            case .seamBeacon:
                let glow = mark.insetBy(dx: -2, dy: -6)
                SettingsTheme.ColorToken.railNSColor().withAlphaComponent(0.22).setFill()
                NSBezierPath(roundedRect: glow, xRadius: 4, yRadius: 4).fill()
                fill.withAlphaComponent(0.55).setFill()
                NSBezierPath(roundedRect: mark, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
    }

    /// The pill lives inside the panel's on-screen overlap; the rest of the
    /// panel is transparent hover margin.
    private func visibleMarkRect() -> CGRect {
        let padding = StashGeometryPolicy.panelBleed
        let thickness: CGFloat = kind == .outerStrip
            ? StashGeometryPolicy.barThickness
            : 2
        let height = max(bounds.height - padding * 2, 16)
        let x = (bounds.width - thickness) / 2
        return CGRect(x: x, y: padding, width: thickness, height: height)
    }
}
