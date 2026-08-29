import AppKit
import SwiftUI

/// Named strip tints. Tokens name the choice ("adaptive", "ivory", …);
/// chromatic tokens are rendered from one hue each over a shared
/// saturation/brightness pair, so adding a color means adding a token and a
/// hue — no hand-tuned RGB triples. Titles resolve through L10n at read time
/// so a language switch re-renders without relaunch.
enum SnapshotColorPalette {
    /// Wheel hues for the settings swatches, mirroring the generated pastels
    /// the strips themselves use.
    private static let chromaticTokens: [(key: String, hue: Double)] = [
        ("amber", 0.089),
        ("gold", 0.133),
        ("moss", 0.389),
        ("azure", 0.575),
        ("violet", 0.744),
        ("rose", 0.928),
        ("crimson", 0.989)
    ]
    private static let sharedSaturation: Double = 0.42
    private static let sharedBrightness: Double = 0.96

    static let tokens: [(key: String, color: Color)] = [
        ("adaptive", Color.gray),
        ("ivory", Color.white),
        ("graphite", Color.black)
    ] + chromaticTokens.map { spec in
        (spec.key, Color(hue: spec.hue, saturation: sharedSaturation, brightness: sharedBrightness))
    }

    static func title(for key: String) -> String {
        switch key {
        case "adaptive": return L10n.tintAdaptive
        case "ivory": return L10n.tintIvory
        case "graphite": return L10n.tintGraphite
        case "amber": return L10n.tintAmber
        case "gold": return L10n.tintGold
        case "moss": return L10n.tintMoss
        case "azure": return L10n.tintAzure
        case "crimson": return L10n.tintCrimson
        case "violet": return L10n.tintViolet
        case "rose": return L10n.tintRose
        default: return L10n.tintIvory
        }
    }

    private static let colorByToken: [String: Color] = {
        Dictionary(uniqueKeysWithValues: tokens.map { ($0.key, $0.color) })
    }()

    static func color(named key: String) -> Color {
        if key.hasPrefix("#"), let tint = NSColor(decodingColorCode: key) {
            return Color(tint)
        }
        return colorByToken[key] ?? .white
    }

    static func displayName(for key: String) -> String {
        if key.hasPrefix("#") {
            return L10n.tintCustom
        }
        return title(for: key)
    }
}

/// Presents the shared color panel and reports each committed choice as a
/// "#RRGGBB" token. The instance keeps itself alive until the panel closes so
/// the target/action pair stays valid.
final class CustomTintPicker: NSObject {
    private static var liveInstance: CustomTintPicker?
    private var commit: ((String) -> Void)?
    private var closeToken: NSObjectProtocol?

    func present(startingFrom base: NSColor, commit: @escaping (String) -> Void) {
        CustomTintPicker.liveInstance = self
        self.commit = commit

        let panel = NSColorPanel.shared
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(panelColorChanged))
        panel.color = base
        closeToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.retire(panel: panel)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func panelColorChanged(_ sender: NSColorPanel) {
        guard let code = sender.color.encodedColorCode else { return }
        commit?("#\(code)")
    }

    private func retire(panel: NSColorPanel) {
        if let closeToken {
            NotificationCenter.default.removeObserver(closeToken)
        }
        closeToken = nil
        panel.setTarget(nil)
        panel.setAction(nil)
        commit = nil
        CustomTintPicker.liveInstance = nil
    }
}

// MARK: - Menu plumbing

struct MenuChoice: Identifiable {
    var id: String { title }
    let title: String
    var image: NSImage? = nil
    var isSelected: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void
}

/// A compact pull-down field: optional leading glyph, title, hairline capsule
/// chrome.
struct FieldMenu: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var minWidth: CGFloat = 96
    var leadingImage: NSImage? = nil
    var alignment: Alignment = .leading
    let choices: [MenuChoice]

    var body: some View {
        Menu {
            ForEach(choices) { choice in
                Button {
                    choice.action()
                } label: {
                    fieldLabel(title: choice.title, image: choice.image)
                }
                .disabled(!choice.isEnabled)
            }
        } label: {
            HStack(spacing: 7) {
                if let leadingImage {
                    Image(nsImage: leadingImage)
                }
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: alignment)
        }
        .menuStyle(.borderlessButton)
        .menuIndicatorSuppressed()
        .frame(width: minWidth, alignment: alignment)
        .background(
            Capsule(style: .continuous)
                .fill(SettingsTheme.ColorToken.glass(for: colorScheme))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

/// Pull-down field specialized for a per-app strip tint; the glyph previews
/// the effective tint at the app's opacity.
struct StashColorField: View {
    @Environment(\.colorScheme) var colorScheme
    let colorName: String
    let opacity: Double
    let title: String
    let choices: [MenuChoice]

    var body: some View {
        Menu {
            ForEach(choices) { choice in
                Button {
                    choice.action()
                } label: {
                    fieldLabel(title: choice.title, image: choice.image)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(nsImage: swatchGlyph)
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .menuIndicatorSuppressed()
        .frame(width: colorFieldWidth, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(SettingsTheme.ColorToken.glass(for: colorScheme))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private var swatchGlyph: NSImage {
        let edge = colorScheme == .dark
            ? NSColor.white.withAlphaComponent(0.38)
            : NSColor.gray.withAlphaComponent(0.32)
        if colorName == "adaptive" {
            return autoModeSwatchImage(size: 14, alpha: opacity, edge: edge)
        }
        let base: NSColor
        if colorName.hasPrefix("#"), let tint = NSColor(decodingColorCode: colorName) {
            base = tint
        } else {
            base = NSColor(SnapshotColorPalette.color(named: colorName))
        }
        return tintedSwatchImage(size: 14, tint: base, alpha: opacity, edge: edge)
    }
}

@ViewBuilder
private func fieldLabel(title: String, image: NSImage?) -> some View {
    if let image {
        Label {
            Text(title)
        } icon: {
            Image(nsImage: image)
        }
    } else {
        Text(title)
    }
}

// MARK: - Glyph drawing

extension View {
    @ViewBuilder
    func menuIndicatorSuppressed() -> some View {
        if #available(macOS 13.0, *) {
            self.menuIndicator(.hidden)
        } else {
            self
        }
    }
}

/// Horizontal light/dark bands standing in for "see-through".
private func drawTransparencyStripes(in rect: NSRect, bandHeight: CGFloat = 3.2) {
    let faint = NSColor(white: 0.93, alpha: 1)
    let deep = NSColor(white: 0.78, alpha: 1)
    var y = rect.minY
    var index = 0
    while y < rect.maxY {
        (index.isMultiple(of: 2) ? faint : deep).setFill()
        NSBezierPath(rect: NSRect(
            x: rect.minX,
            y: y,
            width: rect.width,
            height: min(bandHeight, rect.maxY - y)
        )).fill()
        y += bandHeight
        index += 1
    }
}

private func glyphCanvas(size: CGFloat, draw: (NSRect) -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    draw(NSRect(origin: .zero, size: image.size))
    image.unlockFocus()
    image.isTemplate = false
    return image
}

private func strokeGlyphEdge(rect: NSRect, edge: NSColor, radius: CGFloat) {
    edge.setStroke()
    let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
    outline.lineWidth = 1
    outline.stroke()
}

private func glyphRadius(for size: CGFloat) -> CGFloat {
    size * 0.3
}

/// Solid tint at the app's opacity over transparency stripes, clipped to a
/// rounded square.
func tintedSwatchImage(size: CGFloat, tint: NSColor, alpha: Double, edge: NSColor) -> NSImage {
    glyphCanvas(size: size) { rect in
        let radius = glyphRadius(for: size)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        drawTransparencyStripes(in: rect)
        tint.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        strokeGlyphEdge(rect: rect, edge: edge, radius: radius)
    }
}

/// The "follow appearance" glyph: dark on the left half, light on the right.
func autoModeSwatchImage(size: CGFloat, alpha: Double, edge: NSColor) -> NSImage {
    glyphCanvas(size: size) { rect in
        let radius = glyphRadius(for: size)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        drawTransparencyStripes(in: rect)
        let halves = rect.divided(atDistance: rect.width / 2, from: .minXEdge)
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(rect: halves.slice).fill()
        NSColor.white.withAlphaComponent(alpha).setFill()
        NSBezierPath(rect: halves.remainder).fill()
        strokeGlyphEdge(rect: rect, edge: edge, radius: radius)
    }
}

/// Neutral glyph showing just an opacity level.
func opacityGlyphImage(size: CGFloat = 14, alpha: Double, colorScheme: ColorScheme) -> NSImage {
    let edge = colorScheme == .dark
        ? NSColor.white.withAlphaComponent(0.34)
        : NSColor.gray.withAlphaComponent(0.32)
    let ink = (colorScheme == .dark ? NSColor.white : NSColor.black)
    return glyphCanvas(size: size) { rect in
        let radius = glyphRadius(for: size)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        drawTransparencyStripes(in: rect)
        ink.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        strokeGlyphEdge(rect: rect, edge: edge, radius: radius)
    }
}

/// Six-hue ring marking the custom tint entry.
func spectrumWheelIcon(size: CGFloat = 14, colorScheme: ColorScheme) -> NSImage {
    glyphCanvas(size: size) { rect in
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height)
        let sliceCount = 24
        for slice in 0..<sliceCount {
            NSColor(
                hue: Double(slice) / Double(sliceCount),
                saturation: 0.72,
                brightness: 1,
                alpha: 1
            ).setFill()
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: CGFloat(slice) / CGFloat(sliceCount) * 360,
                endAngle: CGFloat(slice + 1) / CGFloat(sliceCount) * 360
            )
            wedge.close()
            wedge.fill()
        }
        let outlineEdge = colorScheme == .dark
            ? NSColor.white.withAlphaComponent(0.38)
            : NSColor.gray.withAlphaComponent(0.32)
        strokeGlyphEdge(rect: rect, edge: outlineEdge, radius: size / 2)
    }
}

/// Mini window with accent-filled bars marking the edges a stash may use.
func edgeGlyphImage(side: String, size: CGFloat = 14, colorScheme: ColorScheme, enabled: Bool = true) -> NSImage {
    glyphCanvas(size: size) { fullRect in
        let rect = fullRect.insetBy(dx: 1.4, dy: 1.4)
        let radius: CGFloat = 3
        let quiet = colorScheme == .dark
            ? NSColor.white.withAlphaComponent(enabled ? 0.22 : 0.11)
            : NSColor.black.withAlphaComponent(enabled ? 0.20 : 0.09)
        let loud = SettingsTheme.ColorToken.railNSColor(enabled: enabled)

        quiet.setStroke()
        let outline = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        outline.lineWidth = 1.2
        outline.stroke()

        let covered = sidesAdmitted(by: side)
        let barThickness: CGFloat = 2.6
        let verticalInset: CGFloat = 3.2
        loud.setFill()

        if covered.contains("left") {
            NSBezierPath(roundedRect: NSRect(
                x: rect.minX,
                y: rect.minY + verticalInset,
                width: barThickness,
                height: rect.height - verticalInset * 2
            ), xRadius: 1.3, yRadius: 1.3).fill()
        }
        if covered.contains("right") {
            NSBezierPath(roundedRect: NSRect(
                x: rect.maxX - barThickness,
                y: rect.minY + verticalInset,
                width: barThickness,
                height: rect.height - verticalInset * 2
            ), xRadius: 1.3, yRadius: 1.3).fill()
        }
    }
}
