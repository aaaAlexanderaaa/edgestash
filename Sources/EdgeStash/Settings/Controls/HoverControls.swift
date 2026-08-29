import SwiftUI

// MARK: - Shared tuning row

/// One tunable metric: title and explanation on the first line with the live
/// value in a trailing capsule, and a stepped track with an inline reset on
/// the second line.
private struct TuningRow: View {
    let title: String
    let description: String
    let valueText: String
    @Binding var rawValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(valueText)
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(SettingsTheme.ColorToken.rail)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)

            HStack(spacing: 10) {
                SteppedTrack(value: $rawValue, limits: range, increment: step)

                Button {
                    rawValue = defaultValue
                } label: {
                    Label(L10n.hoverReset, systemImage: "arrow.uturn.backward")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Public rows

struct DelayTuningRow: View {
    let title: String
    @Binding var value: Int
    let description: String

    var body: some View {
        TuningRow(
            title: title,
            description: description,
            valueText: value == 0 ? L10n.hoverInstant : "\(value) ms",
            rawValue: Binding(
                get: { Double(value) },
                set: { value = Int($0) }
            ),
            range: 0...2000,
            step: 100,
            defaultValue: Double(Preferences.defaultRevealDelayMS)
        )
    }
}

struct GateTuningRow: View {
    let title: String
    @Binding var value: CGFloat
    let description: String
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let resetValue: CGFloat

    var body: some View {
        TuningRow(
            title: title,
            description: description,
            valueText: "\(Int(value)) px",
            rawValue: Binding(
                get: { Double(value) },
                set: { value = CGFloat($0) }
            ),
            range: Double(range.lowerBound)...Double(range.upperBound),
            step: Double(step),
            defaultValue: Double(resetValue)
        )
    }
}

// MARK: - Buffer preview

/// Diagram for the hover gates: a stash rail sits on the left edge of a
/// sample screen, a sample window hangs off it, and the dashed outline shows
/// how far the pointer may stray before the stash collapses.
struct BufferPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let xTol: CGFloat
    let yTol: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.hoverPreviewTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(L10n.hoverPreviewCaption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(SettingsTheme.ColorToken.rail.opacity(0.9))

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                let cardWidth: CGFloat = 64
                let cardHeight: CGFloat = 100
                let railWidth: CGFloat = 9
                let cardLead = railWidth + 8
                let roomX = max(0, width - cardLead - cardWidth - 12)
                let roomY = max(0, height - cardHeight - 24)
                let growX = roomX * min(xTol / Preferences.maxGateSpanX, 1)
                let growY = roomY * min(yTol / Preferences.maxGateSpanY, 1)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.14))

                    // The owning display edge this window is stashed on.
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(SettingsTheme.ColorToken.rail.opacity(0.55))
                        .frame(width: railWidth)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 10)

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            SettingsTheme.ColorToken.rail.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.4, dash: [3, 3])
                        )
                        .frame(
                            width: cardWidth + growX,
                            height: cardHeight + growY * 2
                        )
                        .padding(.leading, cardLead - 4)

                    sampleWindowCard(width: cardWidth, height: cardHeight)
                        .padding(.leading, cardLead)
                }
                .frame(width: width, height: height)
            }
            .frame(height: 208)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
    }

    private func sampleWindowCard(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(SettingsTheme.ColorToken.rail.opacity(0.30))
                .frame(height: 12)
            Spacer()
            Text(L10n.hoverSampleWindow)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardSurface)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.16), radius: 3, x: 1, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var cardSurface: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(
                colors: [Color(red: 0.25, green: 0.28, blue: 0.33), Color(red: 0.17, green: 0.19, blue: 0.23)],
                startPoint: .top, endPoint: .bottom
            )
            : LinearGradient(
                colors: [Color(red: 0.99, green: 0.99, blue: 1.0), Color(red: 0.87, green: 0.89, blue: 0.93)],
                startPoint: .top, endPoint: .bottom
            )
    }
}
