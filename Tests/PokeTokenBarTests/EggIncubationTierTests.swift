import XCTest
@testable import PokeTokenBar

final class EggIncubationTierTests: XCTestCase {
    func testTierBoundaries() {
        let cases: [(Double, EggIncubationTier)] = [
            (0, .early), (0.399, .early), (0.4, .moving), (0.699, .moving),
            (0.7, .sounds), (0.899, .sounds), (0.9, .imminent), (1.0, .imminent),
            (1.3, .imminent), (-0.1, .early),
        ]
        for (progress, expected) in cases {
            XCTAssertEqual(EggIncubationTier.tier(progress: progress), expected, "progress \(progress)")
        }
    }

    func testWobbleIntervals() {
        XCTAssertNil(EggIncubationTier.early.wobbleInterval)
        XCTAssertEqual(EggIncubationTier.moving.wobbleInterval, .seconds(20))
        XCTAssertEqual(EggIncubationTier.sounds.wobbleInterval, .seconds(8))
        XCTAssertEqual(EggIncubationTier.imminent.wobbleInterval, .seconds(3))
    }

    func testTierCopyLocalizedInAllLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            let texts = EggIncubationTier.allCases.map { $0.text(l) }
            XCTAssertTrue(texts.allSatisfy { !$0.isEmpty }, "\(lang)")
            XCTAssertEqual(Set(texts).count, 4, "\(lang) tiers must be distinct")
        }
    }

    func testCelebrationTextUsesSubjectNames() {
        let from = CelebrationSubject(speciesID: 4, form: nil, isShiny: false, name: "Salamèche")
        let to = CelebrationSubject(speciesID: 5, form: nil, isShiny: false, name: "Reptincel")
        let l = L(.fr)
        let evolve = CelebrationKind.evolve(from: from, to: to)
        let done = l.celebrationText(.evolveDone, kind: evolve)
        XCTAssertTrue(done?.contains("Salamèche") == true && done?.contains("Reptincel") == true)
        XCTAssertTrue(l.celebrationText(.evolveAnnounce, kind: evolve)?.contains("Salamèche") == true)
        XCTAssertNil(l.celebrationText(.none, kind: evolve))
        let hatch = CelebrationKind.hatch(to: to)
        XCTAssertEqual(l.celebrationText(.hatchOh, kind: hatch), l.celebrationHatchOh)
        XCTAssertTrue(l.celebrationText(.hatchDone, kind: hatch)?.contains("Reptincel") == true)
        // ko particles: consonant-final subject takes 이, vowel-final target takes 로
        let koDone = L(.ko).celebrationEvolveDone(from: "리자몽", to: "피카츄")
        XCTAssertEqual(koDone, "축하해요! 리자몽이 피카츄로 진화했어요!")
        XCTAssertEqual(L(.ko).celebrationEvolveDone(from: "피카츄", to: "리자몽"), "축하해요! 피카츄가 리자몽으로 진화했어요!")
        // mismatches
        XCTAssertNil(l.celebrationText(.hatchOh, kind: evolve))
        XCTAssertNil(l.celebrationText(.evolveDone, kind: hatch))
        XCTAssertNil(l.celebrationText(.evolveAnnounce, kind: hatch))
        XCTAssertNil(l.celebrationText(.hatchDone, kind: evolve))
        XCTAssertNil(l.celebrationText(.hatchDone, kind: .dittoReveal(shiny: false)))
        XCTAssertNil(l.celebrationText(.hatchOh, kind: .dittoReveal(shiny: true)))
    }
}
