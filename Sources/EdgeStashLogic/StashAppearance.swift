import Foundation
import CoreGraphics

public enum StashMaterial: String, CaseIterable, Codable {
    case glass, enamel, glow, prism
}

public enum StashWindowMotion: String, CaseIterable, Codable {
    case slide, nudge, fade
}

/// Tokens are optional strings so older documents and unknown future values
/// retain the legacy presentation without making the whole document unreadable.
public struct StashAppearance: Codable, Equatable {
    public var material: String?
    public var motion: String?

    public init(material: String? = nil, motion: String? = nil) {
        self.material = material
        self.motion = motion
    }

    public var resolvedMaterial: StashMaterial { StashMaterial(rawValue: material ?? "") ?? .glass }
    public var resolvedMotion: StashWindowMotion { StashWindowMotion(rawValue: motion ?? "") ?? .slide }
    public static let newProfile = StashAppearance(material: "enamel", motion: "nudge")
}

/// A presentation only: endpoints come from the window policy. This value
/// cannot activate, minimize, select a Space, or commit a session phase.
public struct StashPresentationPlan {
    public enum Write: Equatable {
        case frame(CGRect)
        case position(CGPoint)
        case alpha(CGFloat)
    }

    public let motion: StashWindowMotion
    public let origin: CGPoint
    public let destination: CGPoint
    public let size: CGSize
    public let collapsing: Bool
    public let edge: DisplayEdge
    public static let nudgeDistance: CGFloat = 18

    public init(motion: StashWindowMotion, origin: CGPoint, destination: CGPoint,
                size: CGSize, collapsing: Bool, edge: DisplayEdge,
                reduceMotion: Bool, canSetOpacity: Bool) {
        self.motion = reduceMotion || !canSetOpacity ? .slide : motion
        self.origin = origin
        self.destination = destination
        self.size = size
        self.collapsing = collapsing
        self.edge = edge
    }

    public var changesOpacity: Bool { motion != .slide }
    public var movesDuringAnimation: Bool { motion != .fade }

    private var nearEdge: CGPoint {
        let anchor = collapsing ? origin : destination
        let dx = motion == .nudge ? Self.nudgeDistance * (edge == .left ? -1 : 1) : 0
        return CGPoint(x: anchor.x + dx, y: anchor.y)
    }

    public var preparation: [Write] {
        guard changesOpacity, !collapsing else { return [] }
        return [.alpha(0), .frame(CGRect(origin: nearEdge, size: size))]
    }

    public func sample(_ fraction: CGFloat) -> (position: CGPoint, alpha: CGFloat) {
        let t = StashMotionPolicy.easedProgress(fraction)
        let start = changesOpacity && !collapsing ? nearEdge : origin
        let end = changesOpacity && collapsing ? nearEdge : destination
        return (CGPoint(x: start.x + (end.x - start.x) * t,
                        y: start.y + (end.y - start.y) * t),
                changesOpacity ? (collapsing ? 1 - t : t) : 1)
    }

    public var completion: [Write] {
        let place = Write.frame(CGRect(origin: destination, size: size))
        guard changesOpacity else { return [place] }
        // Never move an opaque fading window to/from its parked destination.
        return collapsing ? [.alpha(0), place] : [place, .alpha(1)]
    }

    /// Shared by the native writer and failure-injection evidence. Stop on
    /// the first rejection; elapsed animation time is never success evidence.
    public static func perform(_ writes: [Write], using writer: (Write) -> Bool) -> Bool {
        for write in writes {
            guard writer(write) else { return false }
        }
        return true
    }
}
