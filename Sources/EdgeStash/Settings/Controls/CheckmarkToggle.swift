import SwiftUI

/// System checkbox for per-app enablement. The previous custom tick path
/// used a Y scale as an X coordinate and sat on the trailing edge.
struct TickBox: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            EmptyView()
        }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .frame(width: 22, height: 22)
    }
}
