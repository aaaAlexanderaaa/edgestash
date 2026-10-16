import CoreGraphics
import Foundation
import EdgeStashLogic

func runAppearancePresentationTests(_ expect: (Bool, String) -> Void) {
    // appearance presentation invariants — physical ownership is unchanged.
    let size = CGSize(width: 460, height: 520)
    for edge in [DisplayEdge.left, .right] {
        let expanded = CGPoint(x: edge == .left ? 8 : 970, y: 80)
        let parked = CGPoint(x: edge == .left ? -458 : 1438, y: 80)
        for motion in StashWindowMotion.allCases {
            for collapsing in [false, true] {
                let origin = collapsing ? expanded : parked
                let destination = collapsing ? parked : expanded
                let plan = StashPresentationPlan(motion: motion, origin: origin, destination: destination,
                                                 size: size, collapsing: collapsing, edge: edge,
                                                 reduceMotion: false, canSetOpacity: true)
                expect(plan.completion.contains(.frame(CGRect(origin: destination, size: size))),
                       "every style confirms the same physical endpoint")
                let first = plan.sample(0), last = plan.sample(1)
                if motion == .slide {
                    expect(first.position == origin && last.position == destination,
                           "legacy slide retains its entire path")
                    expect(plan.preparation.isEmpty && plan.completion.count == 1,
                           "legacy slide leaves visibility guards with the session")
                } else {
                    expect(first.alpha == (collapsing ? 1 : 0) && last.alpha == (collapsing ? 0 : 1),
                           "opacity reaches exact zero and one")
                    let distance = abs(last.position.x - first.position.x)
                    expect(distance == (motion == .nudge ? 18 : 0), "fade is stationary; nudge travels 18pt")
                    expect(first.position.y == expanded.y && last.position.y == expanded.y,
                           "material motion cannot change vertical placement")
                    if collapsing {
                        expect(plan.completion.first == .alpha(0), "hide before physical parking")
                    } else {
                        expect(plan.preparation.first == .alpha(0), "hide before reveal preparation")
                        expect(plan.completion.last == .alpha(1), "confirm final placement before exposing")
                    }
                    var previous = first.alpha
                    for step in 1...100 {
                        let alpha = plan.sample(CGFloat(step) / 100).alpha
                        expect((0...1).contains(alpha) && (collapsing ? alpha <= previous : alpha >= previous),
                               "opacity is bounded and monotonic")
                        previous = alpha
                    }
                }

                // Reject every individual external write in turn. Later writes
                // cannot run and no rejected sequence may report completion.
                for sequence in [plan.preparation, plan.completion] where !sequence.isEmpty {
                    for rejected in sequence.indices {
                        var visited = 0
                        let success = StashPresentationPlan.perform(sequence) { _ in
                            defer { visited += 1 }
                            return visited != rejected
                        }
                        expect(!success && visited == rejected + 1, "rejected frame/alpha short-circuits completion")
                    }
                    expect(StashPresentationPlan.perform(sequence) { _ in true }, "accepted sequence completes")
                }

                for (reduced, capable) in [(true, true), (false, false)] {
                    let fallback = StashPresentationPlan(motion: motion, origin: origin, destination: destination,
                                                         size: size, collapsing: collapsing, edge: edge,
                                                         reduceMotion: reduced, canSetOpacity: capable)
                    expect(fallback.motion == .slide && !fallback.changesOpacity && fallback.preparation.isEmpty,
                           "reduced motion or absent identity requires no opacity preparation")
                    expect(fallback.completion == [.frame(CGRect(origin: destination, size: size))],
                           "immediate/fallback placement retains the endpoint")
                }
            }
        }
    }

    let decoder = JSONDecoder()
    let legacy = try? decoder.decode(StashAppearance.self, from: Data("{}".utf8))
    let future = try? decoder.decode(StashAppearance.self, from: Data("{\"material\":\"future\",\"motion\":\"future\"}".utf8))
    expect(legacy?.resolvedMaterial == .glass && legacy?.resolvedMotion == .slide,
           "missing fields preserve legacy appearance")
    expect(future?.resolvedMaterial == .glass && future?.resolvedMotion == .slide,
           "unknown tokens cannot discard the settings document")
    let chosen = StashAppearance(material: "prism", motion: "fade")
    let encoded = try? JSONEncoder().encode(chosen)
    expect(encoded.flatMap { try? decoder.decode(StashAppearance.self, from: $0) } == chosen,
           "appearance survives a save/load round trip")
    expect(StashAppearance.newProfile.resolvedMaterial == .enamel
           && StashAppearance.newProfile.resolvedMotion == .nudge, "new profiles use the accepted default")
}
