import AppKit
import EdgeStashLogic
import QuartzCore

/// Expand/collapse decoration. Merged-strip hops skip this. Reduced motion fades nothing.
///
/// The flourish is a short sheen along the 5pt glass rail. It animates
/// opacity only, so it does not touch the moving window.
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

        layer.addSublayer(makeSheen(edge: edge, local: local, accent: accent, collapsing: collapsing))

        panel.orderFront(nil)
        let work = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
            self?.stop(immediate: true)
        }
        cleanup = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: work)
    }

    /// A 5pt capsule along the owning edge that flashes once, then fades.
    private func makeSheen(
        edge: DisplayEdge,
        local: CGPoint,
        accent: NSColor,
        collapsing: Bool
    ) -> CALayer {
        let thickness = StashGeometryPolicy.barThickness
        let length: CGFloat = 220
        let frame: CGRect
        switch edge {
        case .left:
            frame = CGRect(x: local.x, y: local.y - length / 2, width: thickness, height: length)
        case .right:
            frame = CGRect(x: local.x - thickness, y: local.y - length / 2, width: thickness, height: length)
        }
        let sheen = CALayer()
        sheen.frame = frame
        sheen.cornerRadius = StashGeometryPolicy.barCornerRadius
        sheen.backgroundColor = accent.withAlphaComponent(collapsing ? 0.55 : 0.4).cgColor
        sheen.opacity = 0

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = collapsing ? [0, 0.85, 0] : [0, 0.7, 0]
        fade.keyTimes = [0, 0.35, 1]
        fade.duration = collapsing ? 0.36 : 0.32
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        sheen.add(fade, forKey: "sheen")
        return sheen
    }
}
