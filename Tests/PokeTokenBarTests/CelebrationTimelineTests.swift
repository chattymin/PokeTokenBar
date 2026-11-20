import XCTest
@testable import PokeTokenBar

final class CelebrationTimelineTests: XCTestCase {
    func testAlternationScheduleIsGeometricAndSumsToFive() {
        let s = CelebrationTimeline.alternationIntervals
        XCTAssertEqual(s.count, 15)
        for i in 1..<s.count { XCTAssertLessThan(s[i], s[i - 1]) }
        XCTAssertEqual(s.first!, 0.83, accuracy: 0.005)
        XCTAssertEqual(s.last!, 0.083, accuracy: 0.005)
        XCTAssertEqual(s.reduce(0, +), 5.0, accuracy: 1e-9)
    }

    func testAlternationEndsOnTarget() {
        let tl = CelebrationTimeline(kind: .evolve, reduced: false, shiny: false)
        XCTAssertTrue(tl.frame(at: 7.39).showsTarget)
    }

    func testEvolveTextBoundaries() {
        let tl = CelebrationTimeline(kind: .evolve, reduced: false, shiny: false)
        XCTAssertEqual(tl.frame(at: 7.99).text, .evolveAnnounce)
        XCTAssertEqual(tl.frame(at: 8.0).text, .evolveDone)
        XCTAssertEqual(tl.frame(at: 12).text, .none)
        XCTAssertEqual(tl.textBoundaries, [8.0, 12.0])
    }

    func testCracksAppearOnePerShake() {
        let tl = CelebrationTimeline(kind: .hatch, reduced: false, shiny: false)
        XCTAssertEqual(tl.frame(at: 1.29).crackLevel, 0)
        XCTAssertEqual(tl.frame(at: 1.3).crackLevel, 1)
        XCTAssertEqual(tl.frame(at: 3.1).crackLevel, 2)
        XCTAssertEqual(tl.frame(at: 4.5).crackLevel, 3)
    }

    func testHatchEggGoneAfterShatter() {
        let tl = CelebrationTimeline(kind: .hatch, reduced: false, shiny: false)
        XCTAssertEqual(tl.frame(at: 6.0).eggOpacity, 0)
        XCTAssertEqual(tl.frame(at: 5.9).eggOpacity, 1)
    }

    func testReducedHasNoEffects() {
        for kind in [CelebrationTimeline.Kind.evolve, .hatch] {
            let tl = CelebrationTimeline(kind: kind, reduced: true, shiny: true)
            var t = 0.0
            while t <= 4.5 + 1e-9 {
                let f = tl.frame(at: t)
                XCTAssertEqual(f.raysAlpha, 0)
                XCTAssertEqual(f.haloAlpha, 0)
                XCTAssertNil(f.flashProgress)
                XCTAssertNil(f.orbsProgress)
                XCTAssertNil(f.sparkleProgress)
                XCTAssertEqual(f.whiteness, 0)
                t += 0.1
            }
        }
    }

    func testSkipTargets() {
        XCTAssertEqual(CelebrationTimeline(kind: .evolve, reduced: false, shiny: false).skipTarget, 7.4)
        XCTAssertEqual(CelebrationTimeline(kind: .hatch, reduced: false, shiny: false).skipTarget, 5.8)
        XCTAssertEqual(CelebrationTimeline(kind: .hatch, reduced: true, shiny: false).skipTarget, 1.2)
        XCTAssertEqual(CelebrationTimeline(kind: .evolve, reduced: true, shiny: false).skipTarget, 1.2)
    }

    func testShinySparklesOnlyWhenShiny() {
        for kind in [CelebrationTimeline.Kind.evolve, .hatch] {
            let plain = CelebrationTimeline(kind: kind, reduced: false, shiny: false)
            let shiny = CelebrationTimeline(kind: kind, reduced: false, shiny: true)
            var plainSeen = false, shinySeen = false
            var t = 0.0
            while t <= plain.total {
                if plain.frame(at: t).sparkleProgress != nil { plainSeen = true }
                if shiny.frame(at: t).sparkleProgress != nil { shinySeen = true }
                t += 0.05
            }
            XCTAssertFalse(plainSeen)
            XCTAssertTrue(shinySeen)
        }
    }

    func testTextChangesAtEveryBoundary() {
        for kind in [CelebrationTimeline.Kind.evolve, .hatch] {
            for reduced in [false, true] {
                let tl = CelebrationTimeline(kind: kind, reduced: reduced, shiny: false)
                XCTAssertFalse(tl.textBoundaries.isEmpty)
                for b in tl.textBoundaries {
                    XCTAssertNotEqual(tl.frame(at: b - 0.01).text, tl.frame(at: b).text, "\(kind) reduced=\(reduced) b=\(b)")
                }
            }
        }
    }

    func testHatchPostShatterFrames() {
        let tl = CelebrationTimeline(kind: .hatch, reduced: false, shiny: false)
        let a = tl.frame(at: 6.25)
        XCTAssertEqual(a.flashProgress!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(a.shardsTime!, 0.25, accuracy: 1e-9)
        XCTAssertEqual(a.eggOpacity, 0)
        let b = tl.frame(at: 6.5)
        XCTAssertEqual(b.targetOpacity, 1)
        XCTAssertEqual(b.scale, 1 + 2.9 * pow(-0.5, 3) + 1.9 * 0.25, accuracy: 1e-9)
        XCTAssertNil(tl.frame(at: 8.0).shardsTime)
    }

    /// The last alternation ends exactly where the burst starts, so every instant of the alternation phase
    /// falls inside one interval (no float-drift fallback is needed).
    func testAlternationEndsExactlyAtTheBurst() {
        XCTAssertEqual(CelebrationTimeline.alternationEnds.count, 15)
        XCTAssertEqual(CelebrationTimeline.alternationEnds.last, 7.4)
        let tl = CelebrationTimeline(kind: .evolve, reduced: false, shiny: false)
        let last = tl.frame(at: 7.4.nextDown)
        XCTAssertTrue(last.showsTarget, "the 15th swap lands on the target")
        XCTAssertEqual(last.scale, 1, accuracy: 1e-6, "grounded at the end of the last swap")
    }

    /// After `lastMotionTime` nothing the stage draws changes (only the caption, drawn elsewhere), so the
    /// stage's TimelineView can stop redrawing there; just before it, something still moves.
    func testNothingMovesAfterTheLastMotionTime() {
        let expected: [(CelebrationTimeline.Kind, Bool, Bool, TimeInterval)] = [
            (.evolve, false, false, 8.6), (.evolve, false, true, 9.5),
            (.hatch, false, false, 7.8), (.hatch, false, true, 8.0),
            (.evolve, true, false, 1.2), (.hatch, true, true, 1.2),
        ]
        func drawn(_ tl: CelebrationTimeline, _ t: TimeInterval) -> CelebrationFrame {
            var frame = tl.frame(at: t)
            frame.text = .none
            return frame
        }
        for (kind, reduced, shiny, end) in expected {
            let tl = CelebrationTimeline(kind: kind, reduced: reduced, shiny: shiny)
            let name = "\(kind) reduced=\(reduced) shiny=\(shiny)"
            XCTAssertEqual(tl.lastMotionTime, end, accuracy: 1e-9, name)
            XCTAssertLessThan(tl.lastMotionTime, tl.total, name)
            let still = drawn(tl, end)
            var t = end
            while t <= tl.total + 1e-9 {
                XCTAssertEqual(drawn(tl, t), still, "\(name) t=\(t)")
                t += 0.01
            }
            XCTAssertNotEqual(drawn(tl, end - 0.02), still, "\(name): still moving just before")
        }
    }

    /// R6: the seen point is the reveal: the done caption, or the end of the cross-fade (result fully shown).
    func testSeenTimeIsTheReveal() {
        let evolve = CelebrationTimeline(kind: .evolve, reduced: false, shiny: false)
        XCTAssertEqual(evolve.seenTime, 8.0)
        XCTAssertEqual(evolve.frame(at: evolve.seenTime).text, .evolveDone)
        XCTAssertEqual(evolve.frame(at: evolve.seenTime - 0.01).text, .evolveAnnounce)
        let hatch = CelebrationTimeline(kind: .hatch, reduced: false, shiny: false)
        XCTAssertEqual(hatch.seenTime, 6.4)
        XCTAssertEqual(hatch.frame(at: hatch.seenTime).text, .hatchDone)
        XCTAssertEqual(hatch.frame(at: hatch.seenTime - 0.01).text, .hatchOh)
        for kind in [CelebrationTimeline.Kind.evolve, .hatch] {
            let reduced = CelebrationTimeline(kind: kind, reduced: true, shiny: false)
            XCTAssertEqual(reduced.seenTime, 1.2)
            XCTAssertEqual(reduced.frame(at: reduced.seenTime).targetOpacity, 1, "fully shown")
            XCTAssertLessThan(reduced.frame(at: reduced.seenTime - 0.01).targetOpacity, 1)
        }
        for timeline in [evolve, hatch] { XCTAssertLessThan(timeline.seenTime, timeline.total, "the caption still holds") }
        XCTAssertNil(CelebrationTimeline(.dittoReveal(shiny: false), reduced: false))
    }

    func testClampingAndParity() {
        for kind in [CelebrationTimeline.Kind.evolve, .hatch] {
            let tl = CelebrationTimeline(kind: kind, reduced: false, shiny: false)
            XCTAssertEqual(tl.frame(at: -1), tl.frame(at: 0))
            XCTAssertEqual(tl.frame(at: tl.total + 5), tl.frame(at: tl.total))
        }
        XCTAssertFalse(CelebrationTimeline(kind: .evolve, reduced: false, shiny: false).frame(at: 2.4).showsTarget)
    }
}
