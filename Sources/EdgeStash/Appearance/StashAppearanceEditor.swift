import AppKit
import EdgeStashLogic
import SwiftUI

extension StashMaterial {
    var title: String { L10n.text("material." + rawValue) }
    var detail: String { L10n.text("material." + rawValue + ".detail") }
}

extension StashWindowMotion {
    var title: String { L10n.text("motion." + rawValue) }
    var detail: String { L10n.text("motion." + rawValue + ".detail") }
}

struct StashAppearanceEditor: View {
    let app: AppEntry
    @ObservedObject var preferences: Preferences
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var replay = 0
    @State private var seam = false
    @State private var darkDesktop = true

    private var appearance: StashAppearance { preferences.appearance(for: app.id) }
    private var material: StashMaterial { appearance.resolvedMaterial }
    private var motion: StashWindowMotion { appearance.resolvedMotion }

    var body: some View {
        SettingsCard(L10n.text("appearance.title")) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel(L10n.text("appearance.material"))
                    HStack(spacing: 6) {
                        ForEach(StashMaterial.allCases, id: \.rawValue) { choice in
                            materialButton(choice)
                        }
                    }
                    Text(material.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        sectionLabel(L10n.text("appearance.tint"))
                        Spacer(minLength: 4)
                        Text(SnapshotColorPalette.displayName(for: preferences.tintKey(for: app.id)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    GlassTintPicker(colorName: preferences.tintKey(for: app.id), material: material) { token in
                        preferences.applyAppStash(bundleID: app.id,
                            stashOn: preferences.stashActive(bundleID: app.id), tint: token)
                    }
                    if preferences.tintKey(for: app.id) == "adaptive" {
                        Text(L10n.appsAutoColorNote).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel(L10n.text("appearance.motion"))
                    HStack(spacing: 6) {
                        ForEach(StashWindowMotion.allCases, id: \.rawValue) { choice in
                            Button { preferences.applyAppearance(bundleID: app.id, motion: choice) } label: {
                                Text(choice.title).font(.subheadline)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(motion == choice ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7)
                                        .stroke(motion == choice ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(motion == choice ? .isSelected : [])
                            .help(choice.detail)
                        }
                    }
                    Text(motion.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.text("appearance.seamNote")).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                preview
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.medium))
    }

    private func materialButton(_ choice: StashMaterial) -> some View {
        Button { preferences.applyAppearance(bundleID: app.id, material: choice) } label: {
            VStack(spacing: 5) {
                MaterialSwatch(material: choice, tint: preferences.stripColor(for: app.id))
                    .frame(height: 42).accessibilityHidden(true)
                Text(choice.title).font(.caption).lineLimit(1)
            }
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(material == choice ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: material == choice ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(material == choice ? .isSelected : [])
        .help(choice.detail)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                sectionLabel(L10n.text("appearance.preview"))
                Spacer()
                Button { darkDesktop.toggle() } label: {
                    Image(systemName: darkDesktop ? "moon.fill" : "sun.max.fill")
                }
                .buttonStyle(.plain)
                .help(L10n.text("appearance.desktop"))
                .accessibilityLabel(L10n.text("appearance.desktop"))
            }
            Picker(L10n.text("appearance.scene"), selection: $seam) {
                Text(L10n.text("appearance.outer")).tag(false)
                Text(L10n.text("appearance.seam")).tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            AppearancePreview(material: material, motion: motion, tint: preferences.stripColor(for: app.id),
                              title: app.name, seam: seam, dark: darkDesktop, reduceMotion: reduceMotion, replay: replay)
                .frame(height: 158)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            HStack {
                Text(reduceMotion ? L10n.text("appearance.reduced") : L10n.text("appearance.previewNote"))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { replay += 1 } label: {
                    Label(L10n.text("appearance.replay"), systemImage: "play.fill").font(.caption)
                }
                .controlSize(.small)
            }
        }
        .padding(.top, 2)
    }
}

private struct MaterialSwatch: NSViewRepresentable {
    let material: StashMaterial
    let tint: NSColor
    func makeNSView(context: Context) -> MaterialSwatchView { MaterialSwatchView() }
    func updateNSView(_ view: MaterialSwatchView, context: Context) {
        view.material = material; view.tint = tint; view.needsDisplay = true
    }
}

private final class MaterialSwatchView: NSView {
    var material: StashMaterial = .glass
    var tint = NSColor.controlAccentColor
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for index in 0..<3 {
                let height: CGFloat = index == 1 ? 34 : 24
                let rect = CGRect(x: bounds.midX + CGFloat(index - 1) * 11 - 2.5,
                                  y: bounds.midY - height / 2, width: 5, height: height)
                StashMaterialPainter.paint(rect, material: material, tint: tint, strength: index == 1 ? 1 : 0.55)
            }
        }
    }
}

private struct AppearancePreview: NSViewRepresentable {
    let material: StashMaterial
    let motion: StashWindowMotion
    let tint: NSColor
    let title: String
    let seam: Bool
    let dark: Bool
    let reduceMotion: Bool
    let replay: Int
    func makeNSView(context: Context) -> AppearancePreviewView { AppearancePreviewView() }
    func updateNSView(_ view: AppearancePreviewView, context: Context) {
        view.configure(material: material, motion: motion, tint: tint, title: title,
                       seam: seam, dark: dark, reduceMotion: reduceMotion, replay: replay)
    }
    static func dismantleNSView(_ view: AppearancePreviewView, coordinator: ()) { view.stop() }
}

/// This timer exists only during an explicit, bounded Settings replay. It
/// samples the real motion policy and never writes to a foreign window.
private final class AppearancePreviewView: NSView {
    private var material: StashMaterial = .glass
    private var motion: StashWindowMotion = .slide
    private var tint = NSColor.controlAccentColor
    private var title = ""
    private var seam = false
    private var dark = true
    private var reduced = false
    private var replay = 0
    private var timer: Timer?
    private var began = Date.distantPast
    private var elapsed: TimeInterval = 0

    func configure(material: StashMaterial, motion: StashWindowMotion, tint: NSColor, title: String,
                   seam: Bool, dark: Bool, reduceMotion: Bool, replay: Int) {
        let changed = self.material != material || self.motion != motion || self.tint != tint
            || self.title != title || self.seam != seam || self.dark != dark || reduced != reduceMotion
        if changed { stop() }
        self.material = material; self.motion = motion; self.tint = tint; self.title = title
        self.seam = seam; self.dark = dark; reduced = reduceMotion
        if self.replay != replay {
            stop(); self.replay = replay; began = Date(); elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.elapsed = Date().timeIntervalSince(self.began)
                if self.elapsed >= 1.25 { self.stop() }
                self.needsDisplay = true
            }
        }
        needsDisplay = true
    }

    func stop() { timer?.invalidate(); timer = nil; elapsed = 0; needsDisplay = true }
    deinit { timer?.invalidate() }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let top = dark ? NSColor(srgbRed: 0.14, green: 0.21, blue: 0.27, alpha: 1)
                : NSColor(srgbRed: 0.81, green: 0.85, blue: 0.85, alpha: 1)
            let bottom = dark ? NSColor(srgbRed: 0.22, green: 0.30, blue: 0.34, alpha: 1)
                : NSColor(srgbRed: 0.69, green: 0.77, blue: 0.80, alpha: 1)
            NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: 28)
            let size = CGSize(width: max(120, bounds.width * 0.66), height: 106)
            let expanded = CGPoint(x: bounds.maxX - size.width - 18, y: 24)
            let hidden = CGPoint(x: bounds.maxX - 2, y: 24)
            var position = expanded
            var alpha: CGFloat = 1
            if timer != nil {
                let collapsing = elapsed < 0.68
                let start = collapsing ? expanded : hidden
                let end = collapsing ? hidden : expanded
                let span = StashMotionPolicy.span(reduceMotion: reduced, collapsing: collapsing)
                let fraction = StashMotionPolicy.progress(elapsed: collapsing ? elapsed : elapsed - 0.68, span: span)
                if seam {
                    alpha = collapsing ? 0 : 1
                } else {
                    let plan = StashPresentationPlan(motion: motion, origin: start, destination: end, size: size,
                                                     collapsing: collapsing, edge: .right,
                                                     reduceMotion: reduced, canSetOpacity: true)
                    let sample = plan.sample(fraction)
                    position = sample.position; alpha = collapsing && fraction >= 1 ? 0 : sample.alpha
                }
            }
            drawWindow(CGRect(origin: position, size: size), alpha: alpha)
            let rail = CGRect(x: bounds.maxX - 9, y: 20, width: 5, height: 118)
            // Isolate the clear seam gap from this view's desktop backdrop.
            // Live rails already draw into a transparent overlay layer.
            let context = NSGraphicsContext.current?.cgContext
            context?.beginTransparencyLayer(auxiliaryInfo: nil)
            StashMaterialPainter.paint(rail, material: material, tint: tint, strength: seam ? 0.5 : 1)
            if seam { StashGlassPainter.punchGap(StashGeometryPolicy.seamInnerGapRect(in: rail)) }
            context?.endTransparencyLayer()
        }
    }

    private func drawWindow(_ rect: CGRect, alpha: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        (dark ? NSColor(srgbRed: 0.16, green: 0.18, blue: 0.20, alpha: alpha)
              : NSColor.white.withAlphaComponent(alpha * 0.94)).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(alpha * 0.25).setStroke(); path.lineWidth = 0.7; path.stroke()
        for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.withAlphaComponent(alpha * 0.8).setFill()
            NSBezierPath(ovalIn: CGRect(x: rect.minX + 10 + CGFloat(i) * 10, y: rect.maxY - 16, width: 5, height: 5)).fill()
        }
        let ink = (dark ? NSColor.white : NSColor.black).withAlphaComponent(alpha * 0.8)
        (title as NSString).draw(in: CGRect(x: rect.minX + 10, y: rect.maxY - 46, width: rect.width - 20, height: 18),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: ink])
        for i in 0..<3 {
            ink.withAlphaComponent(alpha * 0.12).setFill()
            NSBezierPath(roundedRect: CGRect(x: rect.minX + 10, y: rect.maxY - 60 - CGFloat(i) * 12,
                                             width: (rect.width - 24) * (i == 2 ? 0.6 : 1), height: 4),
                         xRadius: 2, yRadius: 2).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
