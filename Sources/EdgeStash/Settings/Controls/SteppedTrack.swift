import SwiftUI

/// A continuous capsule track with a protruding round thumb, quantized to a
/// step value.
///
/// Design derivation: the track is 4pt thick — half the 8pt layout grid — and
/// the thumb is a 16pt disc, the smallest control size HIG recognizes, which
/// keeps the whole control at thumb height. The thumb travels the width minus
/// one diameter so its center tracks the pointer exactly. Quantization counts
/// stops from the range's lower bound rather than snapping the absolute value,
/// so a range that does not begin on a step multiple still lands on interior
/// stops instead of clamping to its ends. There are deliberately no per-step
/// marks: the delay row alone spans 21 stops, where marks would read as
/// noise — the exact value lives in the capsule beside the row title.
struct SteppedTrack: View {
    @Binding var value: Double
    let limits: ClosedRange<Double>
    var increment: Double
    var tint: Color = SettingsTheme.ColorToken.rail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engaged = false

    private static let trackThickness: CGFloat = 4
    private static let thumbDiameter: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - Self.thumbDiameter)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: Self.trackThickness)
                Capsule(style: .continuous)
                    .fill(tint.opacity(engaged ? 1 : 0.85))
                    .frame(
                        width: Self.trackThickness / 2 + travel * fraction,
                        height: Self.trackThickness
                    )
                thumb
                    .offset(x: travel * fraction)
            }
            .frame(height: Self.thumbDiameter)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { gesture in
                        engaged = true
                        let centered = (gesture.location.x - Self.thumbDiameter / 2) / travel
                        value = Self.stop(
                            at: min(max(centered, 0), 1),
                            within: limits,
                            by: increment
                        )
                    }
                    .onEnded { _ in engaged = false }
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: engaged)
        }
        .frame(height: Self.thumbDiameter)
    }

    private var fraction: Double {
        Self.progress(of: value, within: limits)
    }

    private var thumb: some View {
        Circle()
            .fill(tint)
            .overlay(
                Circle().strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5)
            )
            .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
            .shadow(
                color: tint.opacity(engaged ? 0.35 : 0.18),
                radius: engaged ? 2.5 : 1.5,
                y: 0.5
            )
    }

    private static func progress(of value: Double, within limits: ClosedRange<Double>) -> Double {
        let span = limits.upperBound - limits.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - limits.lowerBound) / span, 0), 1)
    }

    /// Maps a 0…1 track position onto the nearest stop of an even grid that
    /// starts at the lower bound and ends at the upper bound.
    private static func stop(
        at position: Double,
        within limits: ClosedRange<Double>,
        by increment: Double
    ) -> Double {
        let span = limits.upperBound - limits.lowerBound
        guard span > 0, increment > 0 else { return limits.lowerBound }
        let stops = max(1, (span / increment).rounded())
        let index = (position * stops).rounded()
        return limits.lowerBound + index * (span / stops)
    }
}
