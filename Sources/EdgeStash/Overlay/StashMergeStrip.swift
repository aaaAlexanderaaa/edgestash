import AppKit
import EdgeStashLogic

struct StashMergeSegmentModel {
    let id: ObjectIdentifier
    let color: NSColor
    let title: String
    let icon: NSImage?
    let slotRect: CGRect
    let kind: StashOverlayKind
}

struct StashMergeStripModel {
    let windowFrame: CGRect
    let edge: DisplayEdge
    let trackRect: CGRect
    let hitRect: CGRect
    let segments: [StashMergeSegmentModel]
    let labelWindowFrame: CGRect
    let labelSegments: [StashMergeSegmentModel]
    let activeID: ObjectIdentifier?
    var hoveredID: ObjectIdentifier?
    var showsLabels: Bool
}

final class StashMergeStrip: NSPanel {
    var onHoverSegment: ((ObjectIdentifier?) -> Void)?
    var onClickSegment: ((ObjectIdentifier) -> Void)?

    private let content = StashMergeStripView()
    private let labels = StashMergeLabelsView()
    private let labelPanel: NSPanel
    private var model: StashMergeStripModel?

    init() {
        labelPanel = NSPanel(
            contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: MergeGroupPolicy.mouseOpaqueWidth,
                height: 200
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
        contentView = content
        content.autoresizingMask = [.width, .height]
        content.onHover = { [weak self] id in self?.onHoverSegment?(id) }
        content.onClick = { [weak self] id in self?.onClickSegment?(id) }
        labelPanel.isOpaque = false
        labelPanel.backgroundColor = .clear
        labelPanel.hasShadow = false
        labelPanel.ignoresMouseEvents = true
        labelPanel.level = .mainMenu
        labelPanel.collectionBehavior = collectionBehavior
        labelPanel.contentView = labels
        labels.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func orderOut(_ sender: Any?) {
        labelPanel.orderOut(sender)
        super.orderOut(sender)
    }

    func present(_ model: StashMergeStripModel) {
        self.model = model
        content.model = model
        if frame != model.windowFrame { setFrame(model.windowFrame, display: true) }
        orderFront(nil)
        if model.showsLabels {
            labels.model = model
            if labelPanel.frame != model.labelWindowFrame {
                labelPanel.setFrame(model.labelWindowFrame, display: true)
            }
            labelPanel.orderFront(nil)
        } else {
            labelPanel.orderOut(nil)
        }
    }

    func updateHover(_ id: ObjectIdentifier?) {
        guard var model, model.hoveredID != id else { return }
        model.hoveredID = id
        model.showsLabels = id != nil
        present(model)
    }

    func rearmHoverAfterMouseUp() {
        onHoverSegment?(segmentAtPointer())
    }

    func segmentAtPointer() -> ObjectIdentifier? {
        let local = content.convert(convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return content.hit(at: local)
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hit(at: point) != nil else { return nil }
        return super.hitTest(point) ?? self
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
                let strength: CGFloat = (active ? 1 : (hovered ? 0.75 : 0.5))
                    * (segment.kind == .seamBeacon ? 0.5 : 1)
                let rail = segment.slotRect.insetBy(dx: 0, dy: 1)
                StashGlassPainter.paintCapsule(
                    rail,
                    tint: segment.color,
                    strength: strength
                )
                if segment.kind == .seamBeacon {
                    StashGlassPainter.punchGap(StashGeometryPolicy.seamInnerGapRect(in: rail))
                }
            }
        }
    }

    private func reportHover(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHover?(hit(at: point))
    }

    func hit(at point: CGPoint) -> ObjectIdentifier? {
        guard let model, model.hitRect.contains(point) else { return nil }
        if let exact = model.segments.first(where: { $0.slotRect.insetBy(dx: -6, dy: 0).contains(point) }) {
            return exact.id
        }
        return model.segments.min {
            abs($0.slotRect.midY - point.y) < abs($1.slotRect.midY - point.y)
        }?.id
    }
}

/// Labels never share the interactive window's footprint. WindowServer sees
/// an always-narrow rail and an independent mouse-transparent decoration.
private final class StashMergeLabelsView: NSView {
    var model: StashMergeStripModel? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let model else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for segment in model.labelSegments {
                drawLabel(for: segment, edge: model.edge,
                          emphasized: segment.id == model.activeID || segment.id == model.hoveredID)
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

}
