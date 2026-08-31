import SwiftUI

let snapSideChoices: [String] = ["left", "right", "both"]

let defaultsFieldWidth: CGFloat = 176
let snapFieldWidth: CGFloat = 172

func snapSideLabel(_ key: String) -> String {
    switch key {
    case "left":
        return L10n.sideLeftOnly
    case "right":
        return L10n.sideRightOnly
    default:
        return L10n.sideBoth
    }
}

/// The sides a choice admits, used for Dock-conflict arithmetic.
func sidesAdmitted(by key: String) -> Set<String> {
    switch key {
    case "left": return ["left"]
    case "right": return ["right"]
    default: return ["left", "right"]
    }
}

func edgeIsFree(_ key: String, dockSide: String?) -> Bool {
    guard let dockSide else { return true }
    return !sidesAdmitted(by: key).contains(dockSide)
}

func dockConflictNote(for key: String, dockSide: String?) -> String? {
    guard let dockSide, sidesAdmitted(by: key).contains(dockSide) else {
        return nil
    }
    return dockSide == "left" ? L10n.dockBlockedLeft : L10n.dockBlockedRight
}

func dockSideLabel(_ side: String?) -> String {
    switch side {
    case "left":
        return L10n.dockSideLeft
    case "right":
        return L10n.dockSideRight
    case "bottom":
        return L10n.dockSideBottom
    default:
        return L10n.dockUnknown
    }
}

/// The picker's current-value title and its option rows intentionally differ:
/// the title shows the side as it will actually be used (falling back to the
/// live probe when the mode is automatic), while the automatic row advertises
/// the probe result.
func dockModeTitle(_ mode: DockClearanceMode, usedSide: String?) -> String {
    dockModeText(mode, side: usedSide)
}

func dockModeOptionRow(_ mode: DockClearanceMode, probedSide: String?) -> String {
    dockModeText(mode, side: probedSide)
}

private func dockModeText(_ mode: DockClearanceMode, side: String?) -> String {
    switch mode {
    case .automatic:
        guard let side else { return L10n.dockAutoLabel }
        return L10n.dockAutoDetected(side)
    case .left:
        return L10n.dockAtLeft
    case .right:
        return L10n.dockAtRight
    case .bottom:
        return L10n.dockAtBottom
    }
}
