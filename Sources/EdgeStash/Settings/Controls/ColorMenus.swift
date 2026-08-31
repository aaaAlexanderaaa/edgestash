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
    private static let sharedSaturation: Double = 0.78
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
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: alignment)
        }
        .frame(width: minWidth, alignment: alignment)
    }
}

/// A row of glass-rail chips. Each chip is painted with the same plate +
/// wash + specular as the desktop rail, so the color you tap is the color
/// you get after the glass lens.
struct GlassTintPicker: View {
    @Environment(\.colorScheme) private var colorScheme
    let colorName: String
    let onColorChange: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SnapshotColorPalette.tokens, id: \.key) { entry in
                glassChipButton(
                    key: entry.key,
                    tint: resolvedTint(for: entry.key),
                    selected: colorName == entry.key
                ) {
                    onColorChange(entry.key)
                }
            }
            glassChipButton(
                key: "custom",
                tint: customTint,
                selected: colorName.hasPrefix("#"),
                customMark: true
            ) {
                CustomTintPicker().present(startingFrom: customTint) { code in
                    onColorChange(code)
                }
            }
        }
    }

    private var customTint: NSColor {
        if colorName.hasPrefix("#"), let stored = NSColor(decodingColorCode: colorName) {
            return stored
        }
        return NSColor(srgbRed: 1, green: 0.78, blue: 0.16, alpha: 1)
    }

    private func resolvedTint(for key: String) -> NSColor {
        if key == "adaptive" {
            return colorScheme == .dark ? .white : .black
        }
        return NSColor(SnapshotColorPalette.color(named: key))
    }

    private func glassChipButton(
        key: String,
        tint: NSColor,
        selected: Bool,
        customMark: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(nsImage: glassRailChipImage(
                tint: tint,
                selected: selected,
                colorScheme: colorScheme,
                customMark: customMark
            ))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key == "custom" ? L10n.tintCustom : SnapshotColorPalette.title(for: key))
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

private func glyphCanvas(size: CGFloat, draw: (NSRect) -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    draw(NSRect(origin: .zero, size: image.size))
    image.unlockFocus()
    image.isTemplate = false
    return image
}

/// Mini glass rail painted with the live desktop recipe, on a mid-tone
/// desktop stand-in so the wash is readable.
func glassRailChipImage(
    tint: NSColor,
    selected: Bool,
    colorScheme: ColorScheme,
    customMark: Bool
) -> NSImage {
    let size = NSSize(width: 22, height: 36)
    let image = NSImage(size: size)
    image.lockFocus()
    let bounds = NSRect(origin: .zero, size: size)
    let desktop = colorScheme == .dark
        ? NSColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1)
        : NSColor(srgbRed: 0.42, green: 0.52, blue: 0.64, alpha: 1)
    let clip = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
    clip.addClip()
    desktop.setFill()
    NSBezierPath(rect: bounds).fill()

    let rail = bounds.insetBy(dx: 7, dy: 4)
    StashGlassPainter.paintCapsule(rail, tint: tint, strength: 1)

    if customMark {
        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: bounds.midX - 3.2, y: 7))
        mark.line(to: NSPoint(x: bounds.midX + 3.2, y: 7))
        NSColor.white.withAlphaComponent(0.85).setStroke()
        mark.lineWidth = 1.2
        mark.lineCapStyle = .round
        mark.stroke()
    }

    let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.6, dy: 0.6), xRadius: 5.4, yRadius: 5.4)
    ring.lineWidth = selected ? 2 : 1
    if selected {
        NSColor.controlAccentColor.setStroke()
    } else {
        NSColor.white.withAlphaComponent(colorScheme == .dark ? 0.22 : 0.28).setStroke()
    }
    ring.stroke()
    image.unlockFocus()
    image.isTemplate = false
    return image
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
