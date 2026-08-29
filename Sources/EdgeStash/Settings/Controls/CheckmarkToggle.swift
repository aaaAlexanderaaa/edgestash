import SwiftUI

/// Rounded-square selection box with a stroke-drawn tick. Selecting springs
/// the tick in with a small scale pop; Reduce Motion and inactive windows
/// skip straight to the final state.
struct TickBox: View {
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovered = false

    private var windowIsEngaged: Bool {
        controlActiveState == .key || controlActiveState == .active
    }

    private var boxFill: Color {
        guard isOn else { return .clear }
        if windowIsEngaged {
            return SettingsTheme.ColorToken.rail
        }
        return colorScheme == .dark ? Color.primary.opacity(0.26) : Color.primary.opacity(0.24)
    }

    private var boxStroke: Color {
        if isOn { return .clear }
        let emphasis = isHovered ? 0.66 : 0.42
        return colorScheme == .dark ? Color.white.opacity(emphasis) : Color.black.opacity(emphasis * 0.8)
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(boxFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .stroke(boxStroke, lineWidth: 1.3)
                )
                .frame(width: 21, height: 21)
                .overlay {
                    if isOn {
                        TickMark()
                            .stroke(
                                .white,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .miter)
                            )
                            .frame(width: 12, height: 12)
                            .transition(
                                reduceMotion || !windowIsEngaged
                                    ? .identity
                                    : .scale(scale: 0.55, anchor: .center).combined(with: .opacity)
                            )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, blendDuration: 0.2), value: isOn)
    }
}

/// Tick drawn on a 12×12 design grid and scaled into whatever frame the
/// control gives it.
private struct TickMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 12
        let scaleY = rect.height / 12
        var path = Path()
        path.move(to: CGPoint(x: 1.8 * scaleX, y: 6.2 * scaleY))
        path.addLine(to: CGPoint(x: 4.6 * scaleX, y: 9.2 * scaleY))
        path.addLine(to: CGPoint(x: 10.4 * scaleY, y: 2.4 * scaleY))
        return path
    }
}
