import AppKit
import EdgeStashLogic
import QuartzCore

/// Expand/collapse decoration. Merged-strip hops skip this. Reduced motion fades nothing.
///
/// The flourish is two layers: a gradient beam that breathes along the edge
/// and one ripple ring that travels away from (collapse) or toward
/// (expand) the edge. Both animate opacity and geometry only, so the effect
/// composites without touching the moving window.
final class StashEffectOverlay {
    private let panel: NSPanel
    private var cleanup: DispatchWorkItem?

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // A click-through transient panel: no need to opt out of the window cycle,
// and it never needs to take part in Exposé drags.
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        let view = NSView()
        view.wantsLayer = true
        panel.contentView = view
    }

    func playCollapse(edge: DisplayEdge, point: CGPoint, color: NSColor, screen: NSScreen) {
        present(edge: edge, point: point, color: color, screen: screen, collapsing: true)
    }

    func playExpand(edge: DisplayEdge, point: CGPoint, color: NSColor, screen: NSScreen) {
        present(edge: edge, point: point, color: color, screen: screen, collapsing: false)
    }

    func stop(immediate: Bool = true) {
        cleanup?.cancel()
        cleanup = nil
        panel.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        if immediate {
            panel.orderOut(nil)
        }
    }

    private func present(
        edge: DisplayEdge,
        point: CGPoint,
        color: NSColor,
        screen: NSScreen,
        collapsing: Bool
    ) {
        stop(immediate: false)
        guard let layer = panel.contentView?.layer else { return }
        panel.setFrame(screen.frame, display: true)
        let local = CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY)
        let accent = color.usingColorSpace(.deviceRGB) ?? color

        layer.addSublayer(makeBeam(edge: edge, local: local, accent: accent, collapsing: collapsing))
        layer.addSublayer(makeRipple(local: local, accent: accent, collapsing: collapsing))

        panel.orderFront(nil)
        let work = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
            self?.stop(immediate: true)
        }
        cleanup = work
        // Longest flourish (0.34s) plus its fade tail, then the panel leaves.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// A horizontal gradient whose bright head sits at the screen edge and
    /// whose tail fades into the display. Collapse starts bright and dies
    /// out; expand starts faint and swells before handing off to the ripple.
    private func makeBeam(
        edge: DisplayEdge,
        local: CGPoint,
        accent: NSColor,
        collapsing: Bool
    ) -> CAGradientLayer {
        let beam = CAGradientLayer()
        let narrow: CGFloat = collapsing ? 24 : 16
        let wide: CGFloat = collapsing ? 150 : 210
        let tall: CGFloat = 76
        switch edge {
        case .left:
            beam.frame = CGRect(x: local.x, y: local.y - tall / 2, width: wide, height: tall)
            beam.startPoint = CGPoint(x: 0, y: 0.5)
            beam.endPoint = CGPoint(x: 1, y: 0.5)
        case .right:
            beam.frame = CGRect(x: local.x - wide, y: local.y - tall / 2, width: wide, height: tall)
            beam.startPoint = CGPoint(x: 1, y: 0.5)
            beam.endPoint = CGPoint(x: 0, y: 0.5)
        }
        beam.colors = [
            accent.withAlphaComponent(0.5).cgColor,
            accent.withAlphaComponent(0).cgColor
        ]
        beam.opacity = 0

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = collapsing ? 0.85 : 0.15
        fade.toValue = collapsing ? 0 : 0.65
        fade.duration = collapsing ? 0.3 : 0.24
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        beam.add(fade, forKey: "fade")

        let breathe = CABasicAnimation(keyPath: "bounds.size.width")
        breathe.fromValue = collapsing ? narrow : wide
        breathe.toValue = collapsing ? wide : narrow
        breathe.duration = 0.22
        beam.add(breathe, forKey: "breathe")
        return beam
    }

    /// One ring that leaves the edge with a collapsing stash and closes in
    /// on the restored window when it expands.
    private func makeRipple(
        local: CGPoint,
        accent: NSColor,
        collapsing: Bool
    ) -> CALayer {
        let ring = CAShapeLayer()
        let startRadius: CGFloat = collapsing ? 10 : 88
        let endRadius: CGFloat = collapsing ? 96 : 14
        let lineWidth: CGFloat = 3
        let bounds = CGRect(
            x: local.x - endRadius - lineWidth,
            y: local.y - endRadius - lineWidth,
            width: (endRadius + lineWidth) * 2,
            height: (endRadius + lineWidth) * 2
        )
        ring.frame = bounds
        ring.path = CGPath(
            ellipseIn: CGRect(
                x: lineWidth,
                y: lineWidth,
                width: bounds.width - lineWidth * 2,
                height: bounds.height - lineWidth * 2
            ),
            transform: nil
        )
        ring.strokeColor = accent.withAlphaComponent(0.6).cgColor
        ring.fillColor = NSColor.clear.cgColor
        ring.lineWidth = lineWidth

        let group = CAAnimationGroup()
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = startRadius / endRadius
        scale.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = collapsing ? 0.8 : 0.9
        fade.toValue = 0
        group.animations = [scale, fade]
        group.duration = collapsing ? 0.34 : 0.28
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        ring.add(group, forKey: "ripple")
        return ring
    }
}
