import AppKit
import EdgeStashLogic

enum StashAppearanceRole: Equatable {
    case rail(kind: StashOverlayKind, edge: DisplayEdge, enabled: Bool)
    case disc
    case halo(DisplayEdgePreviewKind)
}

/// Desktop appearance host. Thin rails and the Settings halo always paint;
/// only the 28pt Glass pin may embed runtime-gated system glass. A 5pt strip
/// paints its material inside the existing geometry.
final class StashAppearanceSurface: NSView {
    private var role: StashAppearanceRole = .disc
    private var tint = NSColor.controlAccentColor
    private var material: StashMaterial = .glass
    private var highlightPoint: CGPoint?
    private var systemGlass: NSView?
    private var installedRole: StashAppearanceRole?

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

    func apply(role: StashAppearanceRole, tint: NSColor, material: StashMaterial = .glass) {
        self.role = role
        self.tint = tint
        self.material = material
        syncSystemGlass()
        needsDisplay = true
    }

    func highlight(at point: CGPoint?) {
        guard highlightPoint != point else { return }
        highlightPoint = point
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        layoutSystemGlass()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if systemGlass == nil {
                StashGlassPainter.paint(role: role, tint: tint, in: bounds, material: material)
                if let highlightPoint {
                    StashMaterialPainter.highlight(glassFrame, at: highlightPoint)
                    drawSeamGapIfNeeded()
                }
                return
            }
            drawSeamGapIfNeeded()
        }
    }

    private func drawSeamGapIfNeeded() {
        let gap: CGRect?
        switch role {
        case let .rail(kind, edge, _) where kind == .seamBeacon:
            let rail = StashGeometryPolicy.visibleRailRect(kind: kind, edge: edge, in: bounds)
            gap = StashGeometryPolicy.seamInnerGapRect(in: rail)
        case let .halo(kind) where kind == .systemMinimize || kind == .disabled:
            gap = StashGeometryPolicy.seamInnerGapRect(in: bounds.insetBy(dx: 0, dy: 4))
        default:
            gap = nil
        }
        guard let gap, gap.height > 0 else { return }
        StashGlassPainter.punchGap(gap)
    }

    private var usesSystemGlass: Bool {
        if case .disc = role, material == .glass, #available(macOS 26.0, *) {
            return NSClassFromString("NSGlassEffectView") != nil
        }
        return false
    }

    private func syncSystemGlass() {
        if !usesSystemGlass {
            systemGlass?.removeFromSuperview()
            systemGlass = nil
            installedRole = nil
            return
        }
        if installedRole == role, systemGlass != nil {
            updateSystemGlassTint()
            layoutSystemGlass()
            return
        }
        systemGlass?.removeFromSuperview()
        systemGlass = nil
        guard #available(macOS 26.0, *),
              let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type else { return }
        let glass = glassClass.init(frame: .zero)
        guard ["setStyle:", "setCornerRadius:", "setTintColor:"].allSatisfy({
            glass.responds(to: NSSelectorFromString($0))
        }) else { return }
        // NSGlassEffectViewStyleRegular is zero. Resolve the same native view
        // and properties at runtime so the macOS 12 deployment target can
        // also be compiled with an SDK predating this optional pin surface.
        glass.setValue(NSNumber(value: 0), forKey: "style")
        glass.setValue(NSNumber(value: Double(cornerRadius)), forKey: "cornerRadius")
        glass.setValue(tint.withAlphaComponent(strength), forKey: "tintColor")
        addSubview(glass)
        systemGlass = glass
        installedRole = role
        layoutSystemGlass()
    }

    private func updateSystemGlassTint() {
        guard let glass = systemGlass else { return }
        glass.setValue(tint.withAlphaComponent(strength), forKey: "tintColor")
        glass.setValue(NSNumber(value: Double(cornerRadius)), forKey: "cornerRadius")
    }

    private func layoutSystemGlass() {
        guard let systemGlass else { return }
        systemGlass.frame = glassFrame
        systemGlass.layer?.cornerRadius = cornerRadius
    }

    private var strength: CGFloat {
        switch role {
        case let .rail(kind, _, enabled):
            return StashGeometryPolicy.tintStrength(kind: kind, enabled: enabled)
        case .disc:
            return 1
        case let .halo(kind):
            return StashGeometryPolicy.haloTintStrength(kind: kind)
        }
    }

    private var cornerRadius: CGFloat {
        switch role {
        case .disc:
            return bounds.width / 2
        case .rail, .halo:
            return StashGeometryPolicy.barCornerRadius
        }
    }

    private var glassFrame: CGRect {
        switch role {
        case let .rail(kind, edge, _):
            return StashGeometryPolicy.visibleRailRect(kind: kind, edge: edge, in: bounds)
        case .disc:
            return bounds.insetBy(dx: 2, dy: 2)
        case .halo:
            return bounds.insetBy(dx: 0, dy: 4)
        }
    }
}

enum StashGlassPainter {
    static func paint(role: StashAppearanceRole, tint: NSColor, in bounds: CGRect, material: StashMaterial = .glass) {
        switch role {
        case let .rail(kind, edge, enabled):
            let rail = StashGeometryPolicy.visibleRailRect(kind: kind, edge: edge, in: bounds)
            let strength = StashGeometryPolicy.tintStrength(kind: kind, enabled: enabled)
            StashMaterialPainter.paint(rail, material: material, tint: tint, strength: strength)
            if kind == .seamBeacon {
                punchGap(StashGeometryPolicy.seamInnerGapRect(in: rail))
            }
        case .disc:
            StashMaterialPainter.paint(bounds.insetBy(dx: 2, dy: 2), material: material, tint: tint, strength: 0.92, circular: true)
        case let .halo(kind):
            let band = bounds.insetBy(dx: 0, dy: 4)
            let strength = StashGeometryPolicy.haloTintStrength(kind: kind)
            StashMaterialPainter.paint(band, material: material, tint: tint, strength: strength)
            if kind == .systemMinimize || kind == .disabled {
                punchGap(StashGeometryPolicy.seamInnerGapRect(in: band))
            }
        }
    }

    static func paintCapsule(
        _ rect: CGRect,
        tint: NSColor,
        strength: CGFloat,
        circular: Bool = false
    ) {
        guard !rect.isEmpty else { return }
        let radius = circular ? min(rect.width, rect.height) / 2 : StashGeometryPolicy.barCornerRadius
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let rgb = (tint.usingColorSpace(.sRGB) ?? tint).withAlphaComponent(1)

        // Plate: let the desktop show through. A high-alpha fill is the gray box.
        NSColor.white.withAlphaComponent(0.10 + 0.06 * strength).setFill()
        path.fill()

        // Color after the glass lens: strong enough that a picked yellow
        // still reads as yellow, not a washed pastel. Still a wash, not a slab.
        rgb.withAlphaComponent((0.42 + 0.38 * strength) * max(0.72, tint.alphaComponent)).setFill()
        path.fill()

        // Specular sheen along the long axis so the plate reads as glass.
        if let sheen = NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(0.46 * strength + 0.12), 0),
            (NSColor.white.withAlphaComponent(0.08), 0.42),
            (NSColor.clear, 1)
        ) {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            sheen.draw(in: rect, angle: 8)
            NSGraphicsContext.restoreGraphicsState()
        }

        NSColor.white.withAlphaComponent(0.36 * strength + 0.14).setStroke()
        let highlight = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.45, dy: 0.45),
            xRadius: max(0.4, radius - 0.45),
            yRadius: max(0.4, radius - 0.45)
        )
        highlight.lineWidth = 0.6
        highlight.stroke()

        rgb.withAlphaComponent(0.16 + 0.10 * strength).setStroke()
        let rim = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        rim.lineWidth = 0.5
        rim.stroke()
    }

    static func punchGap(_ gap: CGRect) {
        guard gap.width > 0, gap.height > 0 else { return }
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setFill()
        NSBezierPath(roundedRect: gap, xRadius: 0.5, yRadius: 0.5).fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
