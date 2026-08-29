import AppKit
import EdgeStashLogic

struct StashMergeSegmentModel {
    let id: ObjectIdentifier
    let color: NSColor
    let title: String
    let icon: NSImage?
    let slotRect: CGRect
}

struct StashMergeStripModel {
    let panelFrame: CGRect
    let edge: DisplayEdge
    let trackRect: CGRect
    let hitRect: CGRect
    let segments: [StashMergeSegmentModel]
    let activeID: ObjectIdentifier?
    let hoveredID: ObjectIdentifier?
    let showsLabels: Bool
}

final class StashMergeStrip: NSPanel {
    var onHoverSegment: ((ObjectIdentifier?) -> Void)?
    var onClickSegment: ((ObjectIdentifier) -> Void)?

    private let content = StashMergeStripView()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        level = .mainMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = content
        content.onHover = { [weak self] id in self?.onHoverSegment?(id) }
        content.onClick = { [weak self] id in self?.onClickSegment?(id) }
    }

    override var canBecomeKey: Bool { false }

    func present(_ model: StashMergeStripModel) {
        content.model = model
        setFrame(model.panelFrame, display: true)
        orderFront(nil)
    }
}

private final class StashMergeStripView: NSView {
    var model: StashMergeStripModel? {
        didSet { needsDisplay = true }
    }
    var onHover: ((ObjectIdentifier?) -> Void)?
    var onClick: ((ObjectIdentifier) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseMoved(with event: NSEvent) { reportHover(event) }
    override func mouseEntered(with event: NSEvent) { reportHover(event) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let id = hit(at: point) {
            onClick?(id)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let model else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for segment in model.segments {
                let active = segment.id == model.activeID
                let hovered = segment.id == model.hoveredID
                let slot = segment.slotRect.insetBy(dx: -1, dy: 1)
                let alpha: CGFloat = active ? 0.95 : (hovered ? 0.75 : 0.45)
                segment.color.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: slot, xRadius: 2, yRadius: 2).fill()
                if model.showsLabels {
                    drawLabel(for: segment, edge: model.edge, emphasized: active || hovered)
                }
            }
        }
    }

    private func drawLabel(for segment: StashMergeSegmentModel, edge: DisplayEdge, emphasized: Bool) {
        let iconSize: CGFloat = 18
        let padding: CGFloat = 8
        let text = segment.title as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: contrastingLabel(on: segment.color)
        ]
        let textSize = text.size(withAttributes: attributes)
        let width = min(max(textSize.width + padding * 2 + iconSize + 6, 72), 140)
        let height: CGFloat = 28
        let x = edge == .left ? segment.slotRect.maxX + 10 : segment.slotRect.minX - 10 - width
        let y = segment.slotRect.midY - height / 2
        let capsule = CGRect(x: x, y: y, width: width, height: height)
        segment.color.withAlphaComponent(emphasized ? 0.92 : 0.72).setFill()
        NSBezierPath(roundedRect: capsule, xRadius: 14, yRadius: 14).fill()
        if let icon = segment.icon {
            icon.draw(
                in: CGRect(x: capsule.minX + 6, y: capsule.midY - iconSize / 2, width: iconSize, height: iconSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }
        text.draw(
            in: CGRect(
                x: capsule.minX + (segment.icon == nil ? padding : padding + iconSize),
                y: capsule.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            ),
            withAttributes: attributes
        )
    }

    private func contrastingLabel(on color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.6 ? NSColor.black.withAlphaComponent(0.85) : NSColor.white
    }

    private func reportHover(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHover?(hit(at: point))
    }

    private func hit(at point: CGPoint) -> ObjectIdentifier? {
        guard let model else { return nil }
        if let exact = model.segments.first(where: { $0.slotRect.insetBy(dx: -6, dy: 0).contains(point) }) {
            return exact.id
        }
        if model.hitRect.contains(point) {
            return model.segments.min {
                abs($0.slotRect.midY - point.y) < abs($1.slotRect.midY - point.y)
            }?.id
        }
        return nil
    }
}
