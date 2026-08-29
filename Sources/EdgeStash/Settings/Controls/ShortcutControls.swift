import AppKit
import EdgeStashLogic
import SwiftUI

// MARK: - System chord reference

/// Well-known system chords used only to warn when a chosen per-app chord
/// duplicates one. Key codes are the fixed Carbon values. Entries render
/// glyph-first ("⌘C 拷贝") so the table reads like a key map rather than a
/// menu transcript, and the catalog is assembled per query so a language
/// switch re-renders without relaunch. The curation covers chords that are
/// active system-wide or in most apps; single-app menu chords (save, print,
/// new) are left out on purpose.
enum SystemChordCatalog {
    struct Entry {
        let modifiers: UInt
        let keyCode: UInt16
        let label: String
    }

    /// Modifier glyphs in canonical order, shared with the chord field.
    private static let modifierGlyphs: [(String, NSEvent.ModifierFlags)] = [
        ("⌃", .control), ("⌥", .option), ("⇧", .shift), ("⌘", .command)
    ]

    static func glyphs(for modifiers: UInt) -> String {
        modifierGlyphs
            .filter { modifiers & $0.1.rawValue != 0 }
            .map(\.0)
            .joined()
    }

    /// The reference table, regrouped by what the chord does.
    static func catalog() -> [Entry] {
        let cmd = NSEvent.ModifierFlags.command.rawValue
        let cmdShift = cmd | NSEvent.ModifierFlags.shift.rawValue
        let cmdOption = cmd | NSEvent.ModifierFlags.option.rawValue

        return [
            // Text editing
            Entry(modifiers: cmd, keyCode: 8, label: L10n.chordCopy),
            Entry(modifiers: cmd, keyCode: 9, label: L10n.chordPaste),
            Entry(modifiers: cmd, keyCode: 7, label: L10n.chordCut),
            Entry(modifiers: cmd, keyCode: 6, label: L10n.chordUndo),
            Entry(modifiers: cmdShift, keyCode: 6, label: L10n.chordRedo),
            Entry(modifiers: cmd, keyCode: 0, label: L10n.chordSelectAll),
            Entry(modifiers: cmd, keyCode: 3, label: L10n.chordFind),
            // Windows and apps
            Entry(modifiers: cmd, keyCode: 12, label: L10n.chordQuit),
            Entry(modifiers: cmd, keyCode: 13, label: L10n.chordClose),
            Entry(modifiers: cmd, keyCode: 4, label: L10n.chordHide),
            Entry(modifiers: cmd, keyCode: 46, label: L10n.chordMinimize),
            Entry(modifiers: cmd, keyCode: 50, label: L10n.chordSwitchWindow),
            Entry(modifiers: cmd, keyCode: 48, label: L10n.chordSwitchApp),
            // System-wide
            Entry(modifiers: cmd, keyCode: 49, label: L10n.chordSpotlight),
            Entry(modifiers: cmdShift, keyCode: 20, label: L10n.chordScreenshotFull),
            Entry(modifiers: cmdShift, keyCode: 21, label: L10n.chordScreenshotArea),
            Entry(modifiers: cmdShift, keyCode: 23, label: L10n.chordScreenshotPanel),
            Entry(modifiers: cmdOption, keyCode: 53, label: L10n.chordForceQuit)
        ]
    }

    /// The rendered chord for the system entry that matches, if any.
    static func clashNote(modifiers: UInt, keyCode: UInt16) -> String? {
        catalog().first { $0.modifiers == modifiers && $0.keyCode == keyCode }.map {
            "\(glyphs(for: $0.modifiers))\($0.label)"
        }
    }
}

let transientChordTarget = "stash.front.temporary"

/// Returns the display name of the owner whose chord would collide, or nil.
func chordConflictSource(
    modifiers: UInt,
    keyCode: UInt16,
    excluding owner: String?,
    preferences: Preferences,
    appEntries: [AppEntry]
) -> String? {
    if owner != transientChordTarget,
       preferences.transientChordModifiers.map(AppShortcutPolicy.normalizedModifiers)
        == AppShortcutPolicy.normalizedModifiers(modifiers),
       preferences.transientChordKeyCode == keyCode {
        return L10n.shortcutStashFront
    }

    for (ownerID, profile) in preferences.appProfiles {
        guard ownerID != owner,
              let chord = profile.chord,
              AppShortcutPolicy.normalizedModifiers(chord.mods)
                == AppShortcutPolicy.normalizedModifiers(modifiers),
              chord.key == keyCode else { continue }
        return chordOwnerName(for: ownerID, appEntries: appEntries)
    }
    return nil
}

func chordOwnerName(for bundleID: String, appEntries: [AppEntry]) -> String {
    if let match = appEntries.first(where: { $0.id == bundleID }) {
        return match.name
    }
    return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName ?? bundleID
}

// MARK: - Recorder

/// Owns the in-window key capture. One recording session at a time; Escape
/// cancels, any chord commits.
final class ChordRecorder: ObservableObject {
    static let shared = ChordRecorder()

    @Published private(set) var activeTarget: String?
    private var monitor: Any?
    private var commit: ((UInt, UInt16) -> Void)?

    func begin(targetID: String, onCommit: @escaping (UInt, UInt16) -> Void) {
        if activeTarget == targetID {
            end()
            return
        }
        end()
        activeTarget = targetID
        commit = onCommit
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.activeTarget != nil else { return event }
            switch event.keyCode {
            case 53: // Escape only cancels the capture.
                self.end()
                return nil
            default:
                let chord = event.modifierFlags.intersection([.control, .option, .shift, .command])
                guard !chord.isEmpty else { return event }
                self.commit?(chord.rawValue, event.keyCode)
                self.end()
                return nil
            }
        }
    }

    func end() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        activeTarget = nil
        commit = nil
    }
}

// MARK: - Chord field

/// Compact capsule showing the captured chord: modifier glyphs then the key
/// glyph, or an ellipsis while capturing.
struct ChordField: View {
    @Environment(\.colorScheme) private var colorScheme
    let modifiers: UInt?
    let keyCode: UInt16?
    let isCapturing: Bool
    let onTap: () -> Void
    let onClear: () -> Void

    private static let glyphOrder: [(String, NSEvent.ModifierFlags)] = [
        ("⌃", .control), ("⌥", .option), ("⇧", .shift), ("⌘", .command)
    ]

    private var isSet: Bool { modifiers != nil && keyCode != nil }

    var body: some View {
        HStack(spacing: 6) {
            Text(isSet ? chordGlyphs : (isCapturing ? "…" : "＋"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSet ? Color.white : Color.secondary.opacity(0.55))
                .padding(.horizontal, 7)
                .frame(minWidth: 34, minHeight: 21)
                .background(
                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                        .fill(isSet ? AnyShapeStyle(SettingsTheme.ColorToken.rail) : AnyShapeStyle(Color.primary.opacity(0.07)))
                )

            if isSet {
                Text(KeyGlyphs.label(for: keyCode!))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SettingsTheme.ColorToken.rail)
            }

            if isSet {
                Button(action: onClear) {
                    Image(systemName: "multiply.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCapturing ? SettingsTheme.ColorToken.rail.opacity(0.10) : SettingsTheme.ColorToken.glass(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isCapturing ? SettingsTheme.ColorToken.rail : Color.primary.opacity(0.12),
                            style: StrokeStyle(lineWidth: isCapturing ? 1.5 : 1, dash: isCapturing ? [4, 3] : [])
                        )
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var chordGlyphs: String {
        guard let modifiers else { return "" }
        return Self.glyphOrder
            .filter { modifiers & $0.1.rawValue != 0 }
            .map(\.0)
            .joined()
    }
}

// MARK: - Rows

/// Per-app chord editor shown inside the Apps list.
struct AppChordRow: View {
    let app: AppEntry
    @ObservedObject var preferences: Preferences
    let appInfos: [AppEntry]
    @ObservedObject private var recorder = ChordRecorder.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var complaint: ChordComplaint?
    @State private var drift: CGFloat = 0

    private var isCapturingHere: Bool {
        recorder.activeTarget == app.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text(app.name)
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                ChordField(
                    modifiers: preferences.appProfiles[app.id]?.chord?.mods,
                    keyCode: preferences.appProfiles[app.id]?.chord?.key,
                    isCapturing: isCapturingHere,
                    onTap: {
                        recorder.begin(targetID: app.id) { mods, code in
                            handleCommit(mods: mods, code: code)
                        }
                    },
                    onClear: {
                        preferences.clearChord(bundleID: app.id)
                        complaint = nil
                    }
                )
                .offset(x: drift)
            }

            scopeSwitch

            if let complaint {
                ComplaintLine(complaint: complaint)
            }
        }
        .animation(SettingsMotion.fade(reduceMotion: reduceMotion), value: complaint)
    }

    private var scopeSwitch: some View {
        HStack(spacing: 8) {
            Spacer()
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.shortcutScopeAll)
                    .font(.system(size: 11, weight: .medium))
                Text(L10n.shortcutScopeAllNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { preferences.chordScope(for: app.id) == .allManagedWindows },
                set: { all in
                    preferences.setShortcutWindowScope(
                        all ? .allManagedWindows : .recentWindow,
                        bundleID: app.id
                    )
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private func handleCommit(mods: UInt, code: UInt16) {
        if let owner = chordConflictSource(
            modifiers: mods,
            keyCode: code,
            excluding: app.id,
            preferences: preferences,
            appEntries: appInfos
        ) {
            complain(.taken(owner))
            return
        }
        if let note = SystemChordCatalog.clashNote(modifiers: mods, keyCode: code) {
            complaint = .systemReserved(note)
        } else {
            complaint = nil
        }
        preferences.setChord(bundleID: app.id, modifiers: mods, keyCode: code)
    }

    private func complain(_ value: ChordComplaint) {
        complaint = value
        jolt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation { complaint = nil }
        }
    }

    private func jolt() {
        guard !reduceMotion else { return }
        let path: [(TimeInterval, CGFloat)] = [(0, 8), (0.06, -6), (0.12, 4), (0.18, -2), (0.24, 0)]
        for (delay, offset) in path {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.05)) { drift = offset }
            }
        }
    }
}

/// The global "stash the frontmost window right now" chord.
struct TransientChordRow: View {
    @ObservedObject var preferences: Preferences
    let appInfos: [AppEntry]
    @ObservedObject private var recorder = ChordRecorder.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var complaint: ChordComplaint?
    @State private var drift: CGFloat = 0

    private var isCapturingHere: Bool {
        recorder.activeTarget == transientChordTarget
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingBadge
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.shortcutStashFront)
                    .font(.callout)
                Text(L10n.shortcutStashFrontNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 14)

            ChordField(
                modifiers: preferences.transientChordModifiers,
                keyCode: preferences.transientChordKeyCode,
                isCapturing: isCapturingHere,
                onTap: {
                    recorder.begin(targetID: transientChordTarget) { mods, code in
                        if let owner = chordConflictSource(
                            modifiers: mods,
                            keyCode: code,
                            excluding: transientChordTarget,
                            preferences: preferences,
                            appEntries: appInfos
                        ) {
                            complaint = .taken(owner)
                            jolt()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                withAnimation { complaint = nil }
                            }
                            return
                        }
                        complaint = SystemChordCatalog.clashNote(modifiers: mods, keyCode: code)
                            .map(ChordComplaint.systemReserved)
                        preferences.setTransientChord(modifiers: mods, keyCode: code)
                    }
                },
                onClear: {
                    preferences.clearTransientChord()
                    complaint = nil
                }
            )
            .offset(x: drift)
        }
        .animation(SettingsMotion.fade(reduceMotion: reduceMotion), value: complaint)
    }

    private var leadingBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.07))
            VStack(spacing: 2) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 10, weight: .semibold))
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 7, height: 6)
            }
        }
    }

    private func jolt() {
        guard !reduceMotion else { return }
        let path: [(TimeInterval, CGFloat)] = [(0, 8), (0.06, -6), (0.12, 4), (0.18, -2), (0.24, 0)]
        for (delay, offset) in path {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.05)) { drift = offset }
            }
        }
    }
}

// MARK: - Feedback

enum ChordComplaint: Equatable {
    case taken(String)
    case systemReserved(String)

    var message: String {
        switch self {
        case .taken(let owner):
            return L10n.shortcutTaken(owner)
        case .systemReserved(let note):
            return L10n.shortcutSystemClash(note)
        }
    }

    var isBlocking: Bool {
        switch self {
        case .taken: return true
        case .systemReserved: return false
        }
    }
}

private struct ComplaintLine: View {
    let complaint: ChordComplaint

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: complaint.isBlocking ? "xmark.circle" : "exclamationmark.triangle")
                .font(.caption)
            Text(complaint.message)
                .font(.caption)
        }
        .foregroundStyle(complaint.isBlocking ? AnyShapeStyle(.red) : AnyShapeStyle(.orange))
    }
}

// MARK: - Key glyph lookup

/// Human labels for key codes. Tables are assembled from physical row
/// orderings rather than one flat literal.
enum KeyGlyphs {
    private static let base: [UInt16: String] = {
        var map: [UInt16: String] = [:]
        func pair(_ code: UInt16, _ glyph: String) { map[code] = glyph }

        // Home row and friends, physical order.
        let letterRows: [(codes: [UInt16], glyphs: [Character])] = [
            ([12, 13, 14, 15, 17, 16, 32, 34, 31, 35], Array("QWERTYUIOP")),
            ([0, 1, 2, 3, 5, 4, 6, 7, 8, 9], Array("ASDFHGZXCV")),
            ([38, 40, 37, 11, 45, 46], Array("JKL;NM"))
        ]
        for row in letterRows where row.codes.count == row.glyphs.count {
            for (code, glyph) in zip(row.codes, row.glyphs) {
                pair(code, String(glyph))
            }
        }

        // Digits, including the keyboard's shifted 5/6 quirk.
        let digitGlyphs = Array("1234567890")
        let digitCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        for (code, glyph) in zip(digitCodes, digitGlyphs) {
            pair(code, String(glyph))
        }

        // Punctuation and editing keys.
        let punctuation: [(UInt16, String)] = [
            (27, "-"), (24, "="), (33, "["), (30, "]"), (39, "'"), (41, ";"),
            (42, "\\"), (43, ","), (44, "/"), (47, "."), (50, "`"),
            (49, "Space"), (48, "Tab"), (36, "↩"), (51, "⌫"), (53, "Esc")
        ]
        for (code, glyph) in punctuation { pair(code, glyph) }

        // Function keys arrive out of order on the hardware; list them as-is.
        let functionKeys: [(UInt16, String)] = [
            (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"),
            (98, "F7"), (100, "F8"), (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12")
        ]
        for (code, glyph) in functionKeys { pair(code, glyph) }

        // Arrow cluster.
        pair(123, "←"); pair(124, "→"); pair(125, "↓"); pair(126, "↑")

        return map
    }()

    static func label(for code: UInt16) -> String {
        base[code] ?? "?"
    }
}
