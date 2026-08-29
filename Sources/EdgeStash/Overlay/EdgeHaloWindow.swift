import AppKit
import EdgeStashLogic

/// Settings-only teaching light. Preview, not a strip or beacon.
final class EdgeHaloWindow: NSPanel {
    private let band = HaloBandView()

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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(kind: DisplayEdgePreviewKind, frame: CGRect, reduceMotion: Bool) {
        band.kind = kind
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

private final class HaloBandView: NSView {
    var kind: DisplayEdgePreviewKind = .slideOffscreen {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color: NSColor
            switch kind {
            case .disabled:
                color = NSColor.secondaryLabelColor.withAlphaComponent(0.35)
            case .slideOffscreen:
                color = SettingsTheme.ColorToken.railNSColor()
            case .systemMinimize:
                color = SettingsTheme.ColorToken.railNSColor().withAlphaComponent(0.55)
            }
            color.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 4), xRadius: 3, yRadius: 3).fill()
        }
    }
}
