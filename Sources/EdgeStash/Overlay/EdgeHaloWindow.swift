import AppKit
import EdgeStashLogic

/// Settings-only teaching light. Preview, not a strip or beacon.
final class EdgeHaloWindow: NSPanel {
    private let band = StashGlassSurface()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = band
        band.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(kind: DisplayEdgePreviewKind, frame: CGRect, reduceMotion: Bool) {
        band.apply(role: .halo(kind), tint: SettingsTheme.ColorToken.railNSColor())
        setFrame(frame, display: true)
        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.12 : 0.22
            animator().alphaValue = 1
        }
    }

    func hide(reduceMotion: Bool) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0.12 : 0.18
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}
