import AppKit
import EdgeStashLogic
import SwiftUI

/// One-shot EdgeStash tip when an app has more than one collapsed stash.
/// Style comes from SettingsTheme.
final class StashMultiWindowTip {
    static let shared = StashMultiWindowTip()

    /// Panel width: a fixed readable measure, never wider than the display's
    /// usable width minus two side guards. The countdown covers a comfortable
    /// read of the message plus a few seconds of reaction time.
    private static let preferredWidth: CGFloat = 480
    private static let sideGuard: CGFloat = 48
    private static let bottomGuard: CGFloat = 32
    private static let readSeconds = 20

    private var panel: NSPanel?
    private var coordinator = MultiWindowTipCoordinator()
    private var expiry: Date?
    private var ticker: Timer?
    private var model = TipModel()

    func consider(appName: String, collapsedCount: Int) {
        apply(
            coordinator.onSync(
                collapsedCount: collapsedCount,
                suppressedPermanently: Preferences.shared.mutedMultiWindowAdvice
            ),
            appName: appName
        )
    }

    func resetForLaunch() {
        apply(coordinator.onRelaunch(), appName: nil)
    }

    func hideForSpaceChange() {
        apply(coordinator.onSpaceChange(), appName: nil)
    }

    private func present(appName: String) {
        model.title = L10n.multiwindowTitle
        model.message = L10n.multiwindowBody(appName)
        let root = TipView(
            model: model,
            onLater: { [weak self] in self?.close(.remindLater) },
            onNever: { [weak self] in self?.close(.neverAgain) }
        )
        let width = min(
            Self.preferredWidth,
            max(320, (NSScreen.main?.visibleFrame.width ?? Self.preferredWidth) - Self.sideGuard)
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 160)
        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(x: frame.midX - width / 2, y: frame.minY + Self.bottomGuard)
            )
        }
        panel.orderFront(nil)
        self.panel = panel

        // Countdown from a fixed deadline rather than a decrementing counter,
        // so throttled timer fires can never overstay the promised window.
        ticker?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let expiry = self.expiry else { return }
            let remaining = Int(expiry.timeIntervalSinceNow.rounded(.up))
            self.model.seconds = max(0, remaining)
            if remaining <= 0 {
                self.close(.timedOut)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private enum TipOutcome {
        /// Quiet until the next launch.
        case remindLater
        /// Quiet for good.
        case neverAgain
        /// The countdown ran out; no preference change.
        case timedOut
    }

    private func close(_ outcome: TipOutcome) {
        let dismissal: MultiWindowTipCoordinator.Dismissal
        switch outcome {
        case .neverAgain: dismissal = .neverAgain
        case .remindLater: dismissal = .remindLater
        case .timedOut: dismissal = .timedOut
        }
        apply(coordinator.onDismiss(dismissal), appName: nil)
    }

    /// Translate a coordinator decision into live presentation. All present/hide
    /// paths route through here so the tip's cardinality matches the grammar.
    private func apply(_ action: MultiWindowTipCoordinator.Action, appName: String?) {
        switch action {
        case .none:
            break
        case .present:
            guard let appName else { return }
            hide()
            model.seconds = Self.readSeconds
            expiry = Date().addingTimeInterval(TimeInterval(Self.readSeconds))
            present(appName: appName)
        case .hide:
            hide()
        case .hideAndMutePermanently:
            Preferences.shared.mutedMultiWindowAdvice = true
            hide()
        }
    }

    private func hide() {
        ticker?.invalidate()
        ticker = nil
        expiry = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class TipModel: ObservableObject {
    @Published var title = ""
    @Published var message = ""
    @Published var seconds = 20
}

private struct TipView: View {
    @ObservedObject var model: TipModel
    let onLater: () -> Void
    let onNever: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "rectangle.stack")
                    .foregroundStyle(SettingsTheme.ColorToken.rail)
                Text(model.title).font(.headline)
                Spacer()
                Text("\(model.seconds)s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(model.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L10n.multiwindowLater, action: onLater)
                Button(L10n.multiwindowMute, action: onNever)
                    .buttonStyle(.borderedProminent)
                    .tint(SettingsTheme.ColorToken.rail)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsTheme.ColorToken.glass(for: colorScheme).opacity(0.96))
    }
}
