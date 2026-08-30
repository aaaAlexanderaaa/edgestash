import AppKit
import EdgeStashLogic

@_silgen_name("ESDisplaySpaceTransportAvailable")
private func ESDisplaySpaceTransportAvailable() -> Bool
@_silgen_name("ESCurrentSpaceForDisplay")
private func ESCurrentSpaceForDisplay(_ displayID: UInt32) -> UInt64
@_silgen_name("ESSpaceType")
private func ESSpaceType(_ spaceID: UInt64) -> Int32
@_silgen_name("ESWindowSpaceMembership")
private func ESWindowSpaceMembership(_ windowID: UInt32, _ spaceID: UInt64) -> Int32
@_silgen_name("ESMoveWindowToSpace")
private func ESMoveWindowToSpace(_ windowID: UInt32, _ spaceID: UInt64) -> Bool

enum DisplaySpacePreparationError: Error, Equatable {
    case unavailable
    case disabledFullScreen
    case membershipUnreadable
    case moveRejected
    case destinationChanged
    case confirmationTimedOut
}

/// Runtime-gated bridge for one ordered operation: keep the foreign window
/// minimized, resolve the owning display's current ordinary user Space, move
/// when needed, and confirm membership before the caller can deminimize.
final class DisplaySpaceTransport {
    static let shared = DisplaySpaceTransport()

    private static let pollInterval: TimeInterval = 0.01
    private static let confirmationTimeout: TimeInterval = 1.0

    var isAvailable: Bool { ESDisplaySpaceTransportAvailable() }

    func availability(for displayID: CGDirectDisplayID) -> SeamSpaceAvailability {
        guard isAvailable else { return .unavailable }
        let spaceID = ESCurrentSpaceForDisplay(displayID)
        let type = spaceID == 0 ? nil : ESSpaceType(spaceID)
        return SpaceChangePolicy.seamAvailability(
            transportAvailable: true,
            currentSpaceID: spaceID == 0 ? nil : spaceID,
            currentSpaceType: type
        )
    }

    func prepareMinimizedWindow(
        windowID: UInt32,
        for displayID: CGDirectDisplayID,
        completion: @escaping (Result<UInt64, DisplaySpacePreparationError>) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let availability = availability(for: displayID)
        guard case let .ready(targetSpaceID) = availability else {
            completion(.failure(
                availability == .disabledFullScreen ? .disabledFullScreen : .unavailable
            ))
            return
        }

        let membership = ESWindowSpaceMembership(windowID, targetSpaceID)
        let preparation = SpaceChangePolicy.seamRevealPreparation(
            availability: availability,
            membershipQuerySucceeded: membership >= 0,
            windowOnTargetSpace: membership == 1
        )
        switch preparation {
        case .reveal:
            let currentSpaceID = ESCurrentSpaceForDisplay(displayID)
            guard SpaceChangePolicy.mayCommitSeamReveal(
                targetSpaceID: targetSpaceID,
                currentDisplaySpaceID: currentSpaceID,
                membershipConfirmed: true
            ) else {
                completion(.failure(.destinationChanged))
                return
            }
            completion(.success(targetSpaceID))
        case .refuse:
            completion(.failure(.membershipUnreadable))
        case .migrate:
            guard ESMoveWindowToSpace(windowID, targetSpaceID) else {
                completion(.failure(.moveRejected))
                return
            }
            pollForConfirmation(
                windowID: windowID,
                displayID: displayID,
                targetSpaceID: targetSpaceID,
                deadline: Date().addingTimeInterval(Self.confirmationTimeout),
                completion: completion
            )
        }
    }

    private func pollForConfirmation(
        windowID: UInt32,
        displayID: CGDirectDisplayID,
        targetSpaceID: UInt64,
        deadline: Date,
        completion: @escaping (Result<UInt64, DisplaySpacePreparationError>) -> Void
    ) {
        let membership = ESWindowSpaceMembership(windowID, targetSpaceID)
        let currentSpaceID = ESCurrentSpaceForDisplay(displayID)
        if SpaceChangePolicy.mayCommitSeamReveal(
            targetSpaceID: targetSpaceID,
            currentDisplaySpaceID: currentSpaceID,
            membershipConfirmed: membership == 1
        ) {
            completion(.success(targetSpaceID))
            return
        }
        guard currentSpaceID == targetSpaceID else {
            completion(.failure(.destinationChanged))
            return
        }
        guard membership == 0 else {
            completion(.failure(.membershipUnreadable))
            return
        }
        guard Date() < deadline else {
            completion(.failure(.confirmationTimedOut))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in
            self?.pollForConfirmation(
                windowID: windowID,
                displayID: displayID,
                targetSpaceID: targetSpaceID,
                deadline: deadline,
                completion: completion
            )
        }
    }
}
