import AppKit
import EdgeStashLogic

/// All painted material recipes, shared by desktop chrome and Settings.
/// Paint stays inside the existing footprint; appearance owns no windows.
enum StashMaterialPainter {
    static func paint(_ rect: CGRect, material: StashMaterial, tint: NSColor,
                      strength: CGFloat, circular: Bool = false) {
        if material == .glass {
            StashGlassPainter.paintCapsule(rect, tint: tint, strength: strength, circular: circular)
            return
        }
        guard !rect.isEmpty else { return }
        let radius = circular ? min(rect.width, rect.height) / 2 : StashGeometryPolicy.barCornerRadius
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let base = (tint.usingColorSpace(.sRGB) ?? tint).withAlphaComponent(1)
        let density = min(max(strength, 0), 1)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        switch material {
        case .enamel:
            base.withAlphaComponent(0.46 + 0.52 * density).setFill()
            path.fill()
            gradient(rect, colors: [NSColor.white.withAlphaComponent(0.30), .clear,
                                    NSColor.black.withAlphaComponent(0.17)], angle: 0)
        case .glow:
            base.withAlphaComponent(0.20 + 0.25 * density).setFill()
            path.fill()
            gradient(rect, colors: [base.withAlphaComponent(0.10),
                                    (base.blended(withFraction: 0.3, of: .white) ?? base).withAlphaComponent(0.60 * density + 0.2),
                                    base.withAlphaComponent(0.12)], angle: 0)
            gradient(rect, colors: [.clear, NSColor.white.withAlphaComponent(0.25 * density), .clear], angle: 90)
        case .prism:
            base.withAlphaComponent(0.38 + 0.45 * density).setFill()
            path.fill()
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let left = NSColor(hue: (hue + 0.92).truncatingRemainder(dividingBy: 1),
                               saturation: max(0.25, saturation * 0.75), brightness: 1, alpha: 0.5 * density)
            let right = NSColor(hue: (hue + 0.10).truncatingRemainder(dividingBy: 1),
                                saturation: max(0.3, saturation * 0.85), brightness: 1, alpha: 0.55 * density)
            gradient(rect, colors: [left, NSColor.white.withAlphaComponent(0.24), right], angle: 78)
        case .glass: break
        }
        NSGraphicsContext.restoreGraphicsState()
        let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 0.4, dy: 0.4), xRadius: radius, yRadius: radius)
        NSColor.white.withAlphaComponent(material == .enamel ? 0.55 : 0.30).setStroke()
        rim.lineWidth = 0.65
        rim.stroke()
    }

    static func highlight(_ rect: CGRect, at point: CGPoint) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5).addClip()
        let band = CGRect(x: rect.minX, y: point.y - 42, width: rect.width, height: 84)
        gradient(band, colors: [.clear, NSColor.white.withAlphaComponent(0.45), .clear], angle: 90)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func gradient(_ rect: CGRect, colors: [NSColor], angle: CGFloat) {
        NSGradient(colors: colors)?.draw(in: rect, angle: angle)
    }
}
