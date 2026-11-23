import AppKit
import XCTest
@testable import PokeTokenBar

private func ids(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(ids) }
private func line(base: Int, tree: EvoNode, rarity: Rarity = .common) -> EvoLine {
    var names: [Int: [String: String]] = [:]
    for id in ids(tree) { names[id] = ["en": "P\(id)", "ko": "포\(id)"] }
    return EvoLine(baseID: base, tree: tree, rarity: rarity, names: names)
}
/// base → base+1 → … 선형 라인(단계 수 = count).
private func linear(_ base: Int, count: Int, rarity: Rarity = .common) -> EvoLine {
    var node = EvoNode(speciesID: base + count - 1, children: [])
    for id in (base..<(base + count - 1)).reversed() { node = EvoNode(speciesID: id, children: [node]) }
    return line(base: base, tree: node, rarity: rarity)
}
private let now = Date(timeIntervalSince1970: 1_700_000_000)
private let rarities: [Rarity] = [.common, .uncommon, .rare, .legendary]

// MARK: 연출 타이밍 표(순수)

final class HatchEffectProfileTests: XCTestCase {
    /// 등급이 오를수록 모든 신호가 단조롭게 커져야 플레이어가 "깨지는 모습"으로 등급을 배운다.
    func testProfilesGrowMonotonicallyWithRarity() {
        let profiles = rarities.map(HatchEffect.profile(for:))
        for (a, b) in zip(profiles, profiles.dropFirst()) {
            XCTAssertLessThan(a.duration, b.duration, "\(a.rarity)→\(b.rarity) 길이")
            XCTAssertLessThan(a.wobbles, b.wobbles, "흔들림 횟수")
            XCTAssertLessThan(a.cracks, b.cracks, "금 개수")
            XCTAssertLessThanOrEqual(a.glow, b.glow)
            XCTAssertLessThanOrEqual(a.wobbleDegrees, b.wobbleDegrees)
            XCTAssertLessThanOrEqual(a.flashTint, b.flashTint)
            XCTAssertLessThanOrEqual(a.flashPeak, b.flashPeak)
            XCTAssertLessThan(a.fragments, b.fragments, "껍질 조각")
            XCTAssertLessThan(a.sparkles, b.sparkles, "반짝이")
            XCTAssertLessThan(a.burst, b.burst, "폭발 크기")
        }
        XCTAssertEqual(profiles.map(\.wobbles), [1, 2, 3, 4])
        XCTAssertEqual(profiles.map(\.revealAt), [1.1, 1.6, 2.3, 3.1])
        XCTAssertEqual(profiles.map { $0.motes > 0 }, [false, false, false, true], "금빛 티끌은 전설만")
        XCTAssertLessThanOrEqual(profiles[3].burst, Double(CelebrationFX.overflow), "폭발이 빛 층을 넘지 않는다")
        XCTAssertEqual(profiles.map(\.rays), [false, false, false, true], "빛줄기는 전설만")
        XCTAssertEqual(profiles.map(\.leaksLight), [false, false, true, true])
        XCTAssertEqual(profiles[0].glow, 0, "커먼은 후광 없이 흰 섬광만")
        XCTAssertEqual(profiles[0].flashTint, 0)
        XCTAssertGreaterThan(profiles[3].pauseBeforeLast, 0, "전설은 마지막 흔들림 앞에서 뜸을 둔다")
        XCTAssertTrue(profiles.allSatisfy { $0.cracks <= HatchEffect.crackPaths.count })
    }

    func testWobblesAndCracksHappenBeforeTheReveal() {
        for r in rarities {
            let p = HatchEffect.profile(for: r)
            let starts = HatchEffect.wobbleStarts(p)
            XCTAssertEqual(starts.count, p.wobbles)
            XCTAssertEqual(starts, starts.sorted())
            let lastEnd = try! XCTUnwrap(starts.last) + HatchEffect.wobbleLength
            XCTAssertLessThanOrEqual(lastEnd, p.revealAt - HatchEffect.buildUp + 1e-9, "\(r): 마지막 흔들림 뒤 빛이 차오를 틈")
            let cracks = HatchEffect.crackTimes(p)
            XCTAssertEqual(cracks.count, p.cracks)
            XCTAssertTrue(cracks.allSatisfy { $0 + HatchEffect.crackGrowth < p.revealAt }, "\(r): 공개 전 금이 다 자란다")
            let before = HatchEffect.frame(p, at: p.revealAt - 0.01)
            XCTAssertFalse(before.revealed, "공개 전엔 알")
            XCTAssertEqual(before.crackProgress, Array(repeating: 1, count: p.cracks))
            XCTAssertTrue(HatchEffect.frame(p, at: p.revealAt).revealed, "섬광 최고조에 포켓몬")
            XCTAssertEqual(HatchEffect.frame(p, at: p.revealAt).flash, p.flashPeak, accuracy: 1e-9)
            XCTAssertEqual(HatchEffect.frame(p, at: 0).flash, 0)
            XCTAssertEqual(HatchEffect.frame(p, at: p.duration).flash, 0, accuracy: 1e-9, "꼬리 끝엔 섬광이 걷힌다")
            XCTAssertEqual(HatchEffect.frame(p, at: p.duration + 1).hatchlingScale, 1, accuracy: 0.01)
            // 흔들림 중엔 실제로 기운다.
            XCTAssertTrue(starts.allSatisfy {
                abs(HatchEffect.frame(p, at: $0 + HatchEffect.wobbleLength / 6).tilt) > 1
            })
        }
        let legend = HatchEffect.profile(for: .legendary)
        let s = HatchEffect.wobbleStarts(legend)
        XCTAssertGreaterThan(s[3] - s[2], s[2] - s[1] + 0.4, "전설: 마지막 앞 간격이 확연히 길다")
        XCTAssertGreaterThan(HatchEffect.frame(legend, at: legend.revealAt - 0.3).rays, 0.5)
        XCTAssertEqual(HatchEffect.frame(HatchEffect.profile(for: .rare), at: 2).rays, 0)
    }

    /// 동작 줄이기: 흔들림·빛줄기·팝 없이 짧게, 그래도 등급색 후광·섬광은 남는다.
    func testReduceMotionKeepsOnlyGlowAndFlash() {
        for r in rarities {
            let p = HatchEffect.profile(for: r)
            XCTAssertLessThan(HatchEffect.duration(p, reduceMotion: true), p.duration)
            for t in stride(from: 0.0, through: HatchEffect.duration(p, reduceMotion: true), by: 0.05) {
                let f = HatchEffect.frame(p, at: t, reduceMotion: true)
                XCTAssertEqual(f.tilt, 0); XCTAssertEqual(f.rays, 0)
                XCTAssertEqual(f.hatchlingScale, 1); XCTAssertEqual(f.eggScale, 1)
            }
            let peak = HatchEffect.frame(p, at: HatchEffect.reducedRevealAt, reduceMotion: true)
            XCTAssertTrue(peak.revealed)
            XCTAssertEqual(peak.flash, p.flashPeak, accuracy: 1e-9)
            XCTAssertEqual(HatchEffect.frame(p, at: HatchEffect.reducedRevealAt - 0.01, reduceMotion: true).glow,
                           p.glow, accuracy: 0.01)
        }
    }
}

final class GraduationEffectTests: XCTestCase {
    /// 본가 회수 순서: 덮개 열림 → 흰 빛 → 붉은 실루엣 → 휘어진 빛줄기로 빨려 듦 → 닫힘 번쩍 → 한 번 튐 →
    /// 뜸을 둔 3번 흔들림(버튼 붉게) → 딸깍(버튼 꺼짐) → 볼이 사라지며 알.
    func testRecallFollowsTheGamesOrder() {
        let start = GraduationEffect.frame(at: 0)
        XCTAssertEqual(start.monOpacity, 1); XCTAssertEqual(start.monScale, 1); XCTAssertEqual(start.eggOpacity, 0)
        XCTAssertGreaterThan(GraduationEffect.frame(at: 0.46).monWhite, 0.9, "흰 빛을 맞는다")
        XCTAssertGreaterThan(GraduationEffect.frame(at: 0.6).ballOpen, 0.9, "덮개가 열려 있다")
        XCTAssertGreaterThan(GraduationEffect.frame(at: 0.75).monRed, 0.9, "붉은 빛 실루엣")
        let pulling = GraduationEffect.frame(at: 0.95)
        XCTAssertGreaterThan(pulling.beam, 0.9, "빛줄기")
        XCTAssertGreaterThan(pulling.monPull, 0.1); XCTAssertLessThan(pulling.monScale, 0.95)
        // 휘어진 길 — 가운데가 직선(포켓몬→볼)에서 벗어난다.
        XCTAssertGreaterThan(GraduationEffect.pullPoint(0.5).x, 0.1)
        XCTAssertEqual(GraduationEffect.frame(at: 1.25).monOpacity, 0, "볼에 들어간 뒤엔 안 보인다")
        XCTAssertEqual(GraduationEffect.frame(at: 1.35).ballOpen, 0, "닫혔다")
        XCTAssertGreaterThan(GraduationEffect.frame(at: 1.25).closeFlash, 0.5, "닫히며 번쩍")
        XCTAssertLessThan(GraduationEffect.frame(at: 1.6).ballDrop, -0.03, "한 번 튄다")
        XCTAssertEqual(GraduationEffect.frame(at: 1.75).ballDrop, 0, "바닥에 놓인다")
        XCTAssertEqual(GraduationEffect.wobbleStarts.count, 3)
        let gaps = zip(GraduationEffect.wobbleStarts.dropFirst(), GraduationEffect.wobbleStarts).map { $0 - $1 }
        XCTAssertTrue(gaps.allSatisfy { $0 > GraduationEffect.wobbleLength + 0.05 }, "흔들림 사이에 뜸")
        for s in GraduationEffect.wobbleStarts {
            let u = GraduationEffect.wobbleLength
            XCTAssertGreaterThan(GraduationEffect.frame(at: s + u * 0.25).ballTilt, 10)
            XCTAssertLessThan(GraduationEffect.frame(at: s + u * 0.75).ballTilt, -10)
            XCTAssertGreaterThan(GraduationEffect.frame(at: s + u * 0.5).buttonRed, 0.9, "흔들릴 때 버튼이 붉게")
            XCTAssertEqual(GraduationEffect.frame(at: s - 0.02).buttonRed, 0, "뜸 동안엔 꺼져 있다")
        }
        XCTAssertEqual(GraduationEffect.frame(at: GraduationEffect.clickAt - 0.01).buttonDark, 0)
        XCTAssertEqual(GraduationEffect.frame(at: GraduationEffect.clickAt + 0.1).buttonDark, 1, "딸깍 — 버튼이 꺼진다")
        let end = GraduationEffect.frame(at: GraduationEffect.duration)
        XCTAssertEqual(end.eggOpacity, 1, accuracy: 1e-9); XCTAssertEqual(end.ballOpacity, 0, accuracy: 1e-9)
    }

    func testReduceMotionFadesWithoutWobble() {
        for t in stride(from: 0.0, through: GraduationEffect.reducedDuration, by: 0.05) {
            let f = GraduationEffect.frame(at: t, reduceMotion: true)
            XCTAssertEqual(f.ballTilt, 0); XCTAssertEqual(f.monScale, 1); XCTAssertEqual(f.monPull, 0)
            XCTAssertEqual(f.ballScale, 1); XCTAssertEqual(f.beam, 0); XCTAssertEqual(f.ballDrop, 0)
        }
        XCTAssertEqual(GraduationEffect.frame(at: 0.75, reduceMotion: true).monOpacity, 0)
        XCTAssertEqual(GraduationEffect.frame(at: GraduationEffect.reducedDuration, reduceMotion: true).eggOpacity, 1,
                       accuracy: 1e-9)
    }
}

final class EvolutionEffectTests: XCTestCase {
    func testSilhouetteAlternatesFasterAndEndsOnTheNewForm() {
        XCTAssertEqual(EvolutionEffect.frame(at: 0).whiteness, 0)
        XCTAssertEqual(EvolutionEffect.frame(at: EvolutionEffect.whitenEnd).whiteness, 1, accuracy: 1e-9)
        XCTAssertEqual(EvolutionEffect.frame(at: EvolutionEffect.whitenEnd).mix, 0, accuracy: 1e-9, "옛 모습에서 시작")
        XCTAssertEqual(EvolutionEffect.cycles(at: EvolutionEffect.alternateEnd), EvolutionEffect.alternationCycles,
                       accuracy: 1e-9)
        XCTAssertEqual(EvolutionEffect.frame(at: EvolutionEffect.alternateEnd).mix, 1, accuracy: 1e-9, "새 모습으로 끝난다")
        // mix 가 0.5 를 지나는 시각 사이 간격이 점점 짧아진다(느리게 시작해 빨라진다).
        var crossings: [TimeInterval] = []
        var previous = EvolutionEffect.frame(at: EvolutionEffect.whitenEnd).mix
        for t in stride(from: EvolutionEffect.whitenEnd, through: EvolutionEffect.alternateEnd, by: 0.002) {
            let m = EvolutionEffect.frame(at: t).mix
            if (previous - 0.5) * (m - 0.5) < 0 { crossings.append(t) }
            previous = m
        }
        XCTAssertEqual(crossings.count, 9, "옛↔새 4.5 주기")
        let gaps = zip(crossings.dropFirst(), crossings).map { $0 - $1 }
        XCTAssertTrue(zip(gaps, gaps.dropFirst()).allSatisfy { $0 > $1 }, "간격이 줄어든다: \(gaps)")
        XCTAssertFalse(EvolutionEffect.frame(at: EvolutionEffect.revealAt - 0.01).revealed)
        let reveal = EvolutionEffect.frame(at: EvolutionEffect.revealAt)
        XCTAssertTrue(reveal.revealed); XCTAssertEqual(reveal.flash, 1, accuracy: 1e-9)
        XCTAssertEqual(reveal.popScale, 0.6, accuracy: 1e-9, "기존 스프링 팝과 같은 0.6 에서 튀어나온다")
        let end = EvolutionEffect.frame(at: EvolutionEffect.duration)
        XCTAssertEqual(end.flash, 0, accuracy: 1e-9); XCTAssertEqual(end.whiteness, 0)
        // 무대가 어두워졌다가 공개 뒤 걷힌다.
        XCTAssertEqual(EvolutionEffect.frame(at: 1.0).dim, 1, accuracy: 1e-9)
        XCTAssertEqual(end.dim, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(EvolutionEffect.duration, 3, "BW 진화처럼 3초 남짓")
    }

    func testReduceMotionIsACrossfadeAndFlash() {
        for t in stride(from: 0.0, through: EvolutionEffect.duration(reduceMotion: true), by: 0.05) {
            let f = EvolutionEffect.frame(at: t, reduceMotion: true)
            XCTAssertEqual(f.oldScale, 1); XCTAssertEqual(f.newScale, 1); XCTAssertEqual(f.popScale, 1)
            XCTAssertEqual(f.whiteness, 0); XCTAssertEqual(f.dim, 0)
        }
        XCTAssertEqual(EvolutionEffect.frame(at: 0.25, reduceMotion: true).mix, 0.5, accuracy: 1e-9)
        XCTAssertTrue(EvolutionEffect.frame(at: EvolutionEffect.reducedRevealAt, reduceMotion: true).revealed)
        XCTAssertLessThan(EvolutionEffect.duration(reduceMotion: true), EvolutionEffect.duration)
    }
}

// MARK: 입자(순수 — 빛 층 안에 머무나·결정적인가)

final class CelebrationParticleTests: XCTestCase {
    private func assertInside(_ particles: [CelebrationFX.Particle], _ label: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        for p in particles where p.opacity > 0.01 {
            let r = (p.x * p.x + p.y * p.y).squareRoot() + p.size / 2
            XCTAssertLessThanOrEqual(r, Double(CelebrationFX.overflow) / 2 + 1e-9,
                                     "\(label): (\(p.x), \(p.y)) 가 빛 층 밖 — 잘린다", file: file, line: line)
        }
    }

    /// 칸 밖으로 넘치는 입자도 빛 층(`overflow` 배) 안에서 사라진다 — 헤더 오버레이·펫 빛 층 창에서 잘리지 않게.
    func testEveryParticleSystemStaysInsideTheLightLayer() {
        for t in stride(from: 0.0, through: 1.6, by: 0.02) {
            for r in rarities {
                let p = HatchEffect.profile(for: r)
                assertInside(CelebrationFX.debris(seed: UInt64(11 + p.fragments), count: p.fragments, at: t,
                                                  speed: 1.1...2.2, spread: 1.45, gravity: 2.6, drag: 3.0, life: 0.95,
                                                  origin: (0, -0.08)), "껍질 \(r)")
                assertInside(CelebrationFX.burst(seed: 53, count: p.sparkles, at: t, reach: p.burst / 2 * 0.85),
                             "반짝이 \(r)")
            }
            assertInside(CelebrationFX.risingMotes(seed: 31, count: 18, at: t, from: 0, until: 1.5), "티끌")
            assertInside(CelebrationFX.converging(seed: 7, count: 22, at: t, from: 0, until: 1.6), "모이는 빛")
            assertInside(CelebrationFX.debris(seed: 5, count: 5, at: t, speed: 1.5...1.9, spread: 0.95, gravity: 2.8,
                                              drag: 2.6, life: 0.62, origin: (0, 0.02), size: 0.13...0.16,
                                              shape: .star), "딸깍 별")
        }
    }

    func testParticlesAreDeterministicAndFadeOut() {
        let a = CelebrationFX.burst(seed: 3, count: 10, at: 0.3, reach: 0.8)
        XCTAssertEqual(a, CelebrationFX.burst(seed: 3, count: 10, at: 0.3, reach: 0.8), "같은 연출은 같은 배치")
        XCTAssertNotEqual(a, CelebrationFX.burst(seed: 4, count: 10, at: 0.3, reach: 0.8))
        XCTAssertTrue(CelebrationFX.burst(seed: 3, count: 10, at: 2, reach: 0.8).isEmpty, "수명이 끝나면 없다")
        XCTAssertTrue(CelebrationFX.debris(seed: 3, count: 10, at: -0.1, speed: 1...2).isEmpty, "터지기 전엔 없다")
        // 파편은 중력으로 떨어진다(나중이 더 아래).
        let early = CelebrationFX.debris(seed: 3, count: 6, at: 0.2, speed: 1...2, life: 2)
        let late = CelebrationFX.debris(seed: 3, count: 6, at: 0.8, speed: 1...2, life: 2)
        XCTAssertGreaterThan(late.map(\.y).reduce(0, +), early.map(\.y).reduce(0, +))
    }

    /// 펫 말풍선은 연출이 공개하기 전엔 무엇이 나왔는지 말하지 않는다 — 공개(큐에서 빠짐) 뒤에 띄운다.
    @MainActor
    func testPetBubbleWaitsForTheRevealBeforeNamingTheResult() {
        XCTAssertTrue(FloatingPetController.shouldHoldEvent(pending: [.hatch(shiny: false, rarity: .legendary)]),
                      "알이 깨지기 전엔 부화한 포켓몬 이름을 말하지 않는다")
        XCTAssertTrue(FloatingPetController.shouldHoldEvent(pending: [
            .evolve(fromID: 4, toID: 5, shiny: false, form: nil, fromName: "파이리", rarity: .common)]))
        XCTAssertFalse(FloatingPetController.shouldHoldEvent(pending: [.graduate(speciesID: 6, shiny: false, form: nil)]),
                       "졸업은 감출 게 없다")
        XCTAssertFalse(FloatingPetController.shouldHoldEvent(pending: []), "공개가 끝나면 바로 띄운다")
    }

    /// 플로팅 펫의 빛 층 창은 펫 스프라이트 칸(펫 창 아래쪽 가운데) 중심에 overflow 배로 놓인다.
    @MainActor
    func testFloatingEffectPanelIsCenteredOnThePetSprite() {
        let pet = NSRect(x: 100, y: 200, width: 160, height: 200)   // 말풍선으로 키가 커진 펫 창
        let frame = FloatingPetController.effectFrame(petPanelFrame: pet, petSize: 128)
        XCTAssertEqual(frame.width, 128 * CelebrationFX.overflow, accuracy: 1e-9)
        XCTAssertEqual(frame.midX, pet.midX, accuracy: 1e-9)
        XCTAssertEqual(frame.midY, 200 + 64, accuracy: 1e-9, "스프라이트 칸 중심(창 아래쪽)")
    }
}

// MARK: 큐·페이로드(스토어)

@MainActor
final class CelebrationQueueTests: XCTestCase {
    private func store(_ line: EvoLine, seed: UInt64 = 7, ditto: Bool = false) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("celebration-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: StubProvider(value: line), clock: { now }, fileURL: url,
                              rng: SeededRNG(seed: seed), dittoDisguiseRollingEnabled: ditto)
    }

    private func tick(_ s: CompanionStore, tokens: Int) {
        s.update(todayTokensByProvider: ["test": tokens], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
    }

    /// 알이 깨지는 연출의 등급은 부화한 라인의 등급이다.
    func testHatchCarriesTheLineRarity() async {
        for r in rarities {
            let s = store(linear(1, count: 2, rarity: r))
            await s.hatch(baseID: 1)
            XCTAssertEqual(s.pendingCelebrations, [.hatch(shiny: s.currentIsShiny, rarity: r)])
            XCTAssertEqual(CelebrationPlayer.concealment(s.pendingCelebrations), .egg, "부화 전엔 알 문구로 가린다")
        }
    }

    /// 알을 사서 지금 개체를 놓아주면 **그 개체의** 대기 연출(마지막 졸업 뒤)만 버린다 — 앞선 개체의
    /// 부화·졸업은 도감에 남은 일이라 그대로 재생한다.
    func testReleasingForAFreshEggDropsOnlyTheReleasedIndividualsCelebrations() async {
        let s = store(linear(1, count: 3), seed: 11)
        tick(s, tokens: 0)
        tick(s, tokens: 9_000_000_000)          // 부화 이월로 즉시 졸업 → [부화1, 졸업1]
        await s.hatchIfNeeded()
        XCTAssertNil(s.state.active)
        tick(s, tokens: 9_010_000_000)          // 새 알 10M → 부화2(이월 5M, 진화 없음)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active)
        XCTAssertEqual(s.pendingCelebrations.count, 3)
        let before = Array(s.pendingCelebrations.prefix(2))
        guard case .graduate = before[1] else { return XCTFail("부화1 → 졸업1 → 부화2 여야 함") }
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertEqual(s.pendingCelebrations, before, "놓아준 개체의 부화만 빠진다")
    }

    /// 위장 메타몽(rare)은 위장 라인의 등급(common)으로 깨진다 — 연출이 정체를 누설하면 안 된다.
    func testDisguisedDittoHatchesWithTheDisguiseRarity() async throws {
        var seed: UInt64?
        for candidate: UInt64 in 0..<200_000 {
            var rng = SeededRNG(seed: candidate)
            _ = rng.next(); _ = rng.next()   // shiny, nature
            if rng.next() % PokemonOdds.dittoDisguiseDenominator == 0 { seed = candidate; break }
        }
        let s = store(linear(1, count: 3), seed: try XCTUnwrap(seed), ditto: true)
        await s.hatch(baseID: 1)
        XCTAssertNotNil(s.state.active?.dittoDisguise, "위장 롤이 맞아야 이 테스트가 의미 있다")
        XCTAssertEqual(s.pendingCelebrations, [.hatch(shiny: false, rarity: .common)],
                       "위장 중엔 이로치도 숨기고 등급도 위장 라인 그대로")
    }

    /// 졸업 연출은 졸업 직전 최종 종·이로치·형태를 싣는다(재생 땐 이미 새 알이다).
    func testGraduationCarriesTheFinalSpeciesShinyAndForm() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("celebration-burmy-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let active = #"{"baseID":412,"pathIDs":[412,413],"plannedPathIDs":[412,413],"stageIndex":1,"usedAtStage":0,"rarity":"common","totalForms":2,"isShiny":true,"form":"sandy"}"#
        let json = "{\"installBaselineSet\":true,\"lastDate\":\"d1\",\"active\":\(active),\"dex\":[]}"
        try Data(json.utf8).write(to: url)
        let burmy = line(base: 412, tree: EvoNode(speciesID: 412, children: [EvoNode(speciesID: 413, children: [])]))
        let s = CompanionStore(provider: StubProvider(value: burmy), clock: { now }, fileURL: url,
                               rng: SeededRNG(seed: 3), dittoDisguiseRollingEnabled: false)
        tick(s, tokens: 0)
        for _ in 0..<200 where s.currentLine == nil { await Task.yield() }
        XCTAssertNotNil(s.currentLine)
        s.applyUsage(10_000_000_000)
        XCTAssertNil(s.state.active, "졸업")
        XCTAssertEqual(s.pendingCelebrations, [.graduate(speciesID: 413, shiny: true, form: PokemonForm("sandy"))])
    }

    /// 한 번의 갱신에서 진화 2회 + 졸업 — 단계마다 전·후 종을 실은 진화가 순서대로, 졸업이 마지막.
    /// (진화를 합치지 않는다 — 사용자 결정. 상한 6 이 이 묶음을 다 담는다.)
    func testChainedEvolutionsAndGraduationQueueInOrder() async {
        let s = store(linear(1, count: 3))
        s.setLanguage(.en)
        await s.hatch(baseID: 1)
        let shiny = s.currentIsShiny
        XCTAssertEqual(s.consumeCelebration(), .hatch(shiny: shiny, rarity: .common))
        XCTAssertNil(CelebrationPlayer.concealment(s.pendingCelebrations))
        s.applyUsage(10_000_000_000)
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.pendingCelebrations, [
            .evolve(fromID: 1, toID: 2, shiny: shiny, form: nil, fromName: "P1", rarity: .common),
            .evolve(fromID: 2, toID: 3, shiny: shiny, form: nil, fromName: "P2", rarity: .common),
            .graduate(speciesID: 3, shiny: shiny, form: nil),
        ])
        // 졸업으로 라인이 비었어도 옛 단계 이름은 페이로드에 있어 정보 칸이 비지 않는다.
        XCTAssertNil(s.currentLine)
        XCTAssertEqual(CelebrationPlayer.concealment(s.pendingCelebrations), .subject(name: "P1", rarity: .common))
        s.consumeCelebration()
        XCTAssertEqual(CelebrationPlayer.concealment(s.pendingCelebrations), .subject(name: "P2", rarity: .common))
        s.consumeCelebration()
        XCTAssertNil(CelebrationPlayer.concealment(s.pendingCelebrations), "졸업은 가리지 않는다")
    }

    /// 부화 이월로 진화·졸업까지 가면: 이월 진화는 버리고(부화 공개가 덮는다) 부화 → 졸업.
    func testOverflowDropsEvolvesButKeepsHatchBeforeGraduation() async {
        let s = store(linear(1, count: 3), seed: 11)
        tick(s, tokens: 0)
        tick(s, tokens: 9_000_000_000)
        await s.hatchIfNeeded()
        XCTAssertNil(s.state.active, "이월로 즉시 졸업")
        let shiny = s.state.dex.last?.isShiny ?? false
        XCTAssertEqual(s.pendingCelebrations, [.hatch(shiny: shiny, rarity: .common),
                                               .graduate(speciesID: 3, shiny: shiny, form: nil)])
    }

    /// 상한을 넘으면 오래된 것부터 버린다 — 남는 건 지금 상태로 이어지는 최근 연출.
    func testQueueCapDropsTheOldestCelebrations() async {
        let s = store(linear(1, count: 9))
        s.setLanguage(.en)
        await s.hatch(baseID: 1)
        s.applyUsage(1_000_000_000_000)   // 진화 8 + 졸업 1 (+ 앞의 부화 1) = 10
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.pendingCelebrations.count, CompanionStore.celebrationQueueCap)
        XCTAssertEqual(s.pendingCelebrations.last, .graduate(speciesID: 9, shiny: s.state.dex[0].isShiny, form: nil))
        XCTAssertEqual(s.pendingCelebrations.first,
                       .evolve(fromID: 4, toID: 5, shiny: s.state.dex[0].isShiny, form: nil, fromName: "P4", rarity: .common))
        XCTAssertGreaterThanOrEqual(CompanionStore.celebrationQueueCap, 3, "진화 2회 + 졸업이 한 번에 들어가야 한다")
    }

    /// 꺼낸 연출은 다시 나오지 않는다(팝오버 재오픈·헤더 재마운트에도 1회).
    func testConsumingIsOneTime() async {
        let s = store(linear(1, count: 2))
        XCTAssertNil(s.consumeCelebration())
        await s.hatch(baseID: 1)
        let seq = s.celebrationSeq
        XCTAssertNotNil(s.consumeCelebration())
        XCTAssertNil(s.consumeCelebration())
        XCTAssertNil(s.celebration)
        XCTAssertEqual(s.celebrationSeq, seq, "꺼내기는 새 연출 신호가 아니다")
    }

    /// 위장 메타몽이 부화하고, 팝오버를 열기 전에 리빌 임계까지 가면 [부화, 리빌] 이 쌓인다. 재생 시점의
    /// 상태는 이미 메타몽이지만 위장 모습이 먼저 나와야 한다 — 부화 공개 = 위장체, 정보 칸 = 위장체 이름·등급.
    func testHatchThenDittoRevealShowsTheDisguiseFirst() async throws {
        var seed: UInt64?
        for candidate: UInt64 in 0..<200_000 {
            var rng = SeededRNG(seed: candidate)
            _ = rng.next(); _ = rng.next()   // shiny, nature
            if rng.next() % PokemonOdds.dittoDisguiseDenominator == 0 { seed = candidate; break }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("celebration-ditto-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let s = CompanionStore(provider: DittoOrLineProvider(line: linear(1, count: 3)), clock: { now }, fileURL: url,
                               rng: SeededRNG(seed: try XCTUnwrap(seed)), dittoDisguiseRollingEnabled: true)
        s.setLanguage(.en)
        await s.hatch(baseID: 1)
        XCTAssertNotNil(s.state.active?.dittoDisguise)
        s.applyUsage(s.threshold)                       // 첫 진화 임계 → 진화 대신 리빌
        for _ in 0..<200 where !(s.state.active?.dittoRevealed ?? false) { await Task.yield() }
        XCTAssertEqual(s.currentSpeciesID, PokemonOdds.dittoSpeciesID, "상태는 이미 메타몽")
        let shiny = s.state.active?.isShiny ?? false
        let disguise = CompanionStore.DittoDisguise(speciesID: 1, form: nil, name: "P1", rarity: .common)
        XCTAssertEqual(s.pendingCelebrations, [.hatch(shiny: false, rarity: .common),
                                               .dittoReveal(shiny: shiny, disguise: disguise)])

        let current = CelebrationPlayer.Sprite(speciesID: PokemonOdds.dittoSpeciesID, shiny: shiny)
        var player = CelebrationPlayer()
        player.startIfIdle(queue: s, current: current, reduceMotion: false, now: now)
        guard case .hatch(_, _, let reveal)? = player.active?.kind else { return XCTFail("부화부터") }
        XCTAssertEqual(reveal, CelebrationPlayer.Sprite(speciesID: 1), "부화 공개는 위장체(이로치 숨김)")
        XCTAssertEqual(CelebrationPlayer.concealment(s.pendingCelebrations), .egg)
        _ = player.advance(queue: s, now: now.addingTimeInterval(HatchEffect.profile(for: .common).revealAt))
        XCTAssertEqual(CelebrationPlayer.concealment(s.pendingCelebrations),
                       .subject(name: "P1", rarity: .common), "부화 공개 뒤에도 리빌 전까진 위장체 이름·등급")
        _ = player.advance(queue: s, now: now.addingTimeInterval(10))
        player.startIfIdle(queue: s, current: current, reduceMotion: false, now: now.addingTimeInterval(10))
        XCTAssertEqual(player.active?.kind, .dittoReveal(
            disguise: CelebrationPlayer.Sprite(speciesID: 1),
            ditto: CelebrationPlayer.Sprite(speciesID: PokemonOdds.dittoSpeciesID, shiny: shiny)))
        _ = player.advance(queue: s, now: now.addingTimeInterval(10 + DittoRevealEffect.revealAt))
        XCTAssertNil(CelebrationPlayer.concealment(s.pendingCelebrations), "리빌 순간부터 메타몽 정보")
    }
}

/// 부화 라인은 주어진 것, 메타몽(132)을 물으면 메타몽 라인.
private struct DittoOrLineProvider: PokeProviding {
    let line: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        guard baseSpeciesID == PokemonOdds.dittoSpeciesID else { return line }
        return EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .rare,
                       names: [baseSpeciesID: ["en": "Ditto"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: line.baseID, captureRate: 255)] }
}

// MARK: 재생 규칙(순수 — 큐에서 언제 꺼내나·무엇을 가리나·끊기면 어떻게 되나)

@MainActor
final class CelebrationPlayerTests: XCTestCase {
    typealias Sprite = CelebrationPlayer.Sprite

    private func store(_ line: EvoLine, seed: UInt64 = 7) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("celebration-player-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: StubProvider(value: line), clock: { now }, fileURL: url,
                              rng: SeededRNG(seed: seed), dittoDisguiseRollingEnabled: false)
    }

    private func current(_ s: CompanionStore) -> Sprite {
        Sprite(speciesID: s.currentSpeciesID, shiny: s.currentIsShiny, form: s.currentForm)
    }

    /// 시작은 꺼내지 않는다. 공개 순간에 꺼내고(정보 칸도 그때 풀린다), 끝나면 다음 연출로.
    func testHatchIsConsumedAtTheRevealAndConcealedUntilThen() async {
        let s = store(linear(1, count: 2, rarity: .legendary))
        await s.hatch(baseID: 1)
        let p = HatchEffect.profile(for: .legendary)
        var player = CelebrationPlayer()
        player.startIfIdle(queue: s, current: current(s), reduceMotion: false, now: now)
        XCTAssertEqual(s.pendingCelebrations.count, 1, "시작했다고 꺼내지 않는다")
        XCTAssertEqual(player.nextDeadline, now.addingTimeInterval(p.revealAt))
        XCTAssertEqual(player.advance(queue: s, now: now.addingTimeInterval(1)), [])
        XCTAssertEqual(CelebrationPlayer.concealment(s.pendingCelebrations), .egg, "1초: 아직 가린다")
        let shiny = s.currentIsShiny
        XCTAssertEqual(player.advance(queue: s, now: now.addingTimeInterval(p.revealAt)),
                       [.revealed(.hatch(shiny: shiny, rarity: .legendary))])
        XCTAssertTrue(s.pendingCelebrations.isEmpty)
        XCTAssertNil(CelebrationPlayer.concealment(s.pendingCelebrations), "공개 순간부터 보인다")
        XCTAssertEqual(player.nextDeadline, now.addingTimeInterval(p.duration))
        XCTAssertEqual(player.advance(queue: s, now: now.addingTimeInterval(p.duration)), [.finished])
        XCTAssertNil(player.active)
    }

    /// [회귀] 공개 전에 팝오버가 닫히거나 탭이 바뀌어 헤더가 사라지면(= 플레이어 상태 소실) 다음 마운트가
    /// 같은 부화를 처음부터 다시 재생한다. 시작할 때 꺼내던 첫 구현은 여기서 연출 없이 결과만 보였다.
    func testInterruptionBeforeTheRevealReplaysOnTheNextMount() async {
        let s = store(linear(1, count: 2, rarity: .legendary))
        await s.hatch(baseID: 1)
        var first = CelebrationPlayer()
        first.startIfIdle(queue: s, current: current(s), reduceMotion: false, now: now)
        _ = first.advance(queue: s, now: now.addingTimeInterval(1))   // 전설 부화 1초 — 공개 전
        // 헤더 소실: first 를 버린다. 다시 연 헤더는 새 플레이어로 시작한다.
        XCTAssertEqual(CelebrationPlayer.concealment(s.pendingCelebrations), .egg, "닫혀 있는 동안에도 결과를 안 보인다")
        var second = CelebrationPlayer()
        XCTAssertEqual(second.idleSprite(queue: s, current: current(s)), Sprite(speciesID: nil), "칸은 알")
        second.startIfIdle(queue: s, current: current(s), reduceMotion: false, now: now.addingTimeInterval(60))
        guard case .hatch(let profile, _, _)? = second.active?.kind else { return XCTFail("부화를 다시 재생해야 한다") }
        XCTAssertEqual(profile.rarity, .legendary)
        XCTAssertEqual(second.active?.start, now.addingTimeInterval(60), "처음부터")
    }

    /// 공개 뒤에 끊기면 이미 꺼냈으므로 다시 나오지 않는다(남은 꼬리만 잃는다).
    func testInterruptionAfterTheRevealIsNotReplayed() async {
        let s = store(linear(1, count: 2))
        await s.hatch(baseID: 1)
        var first = CelebrationPlayer()
        first.startIfIdle(queue: s, current: current(s), reduceMotion: false, now: now)
        _ = first.advance(queue: s, now: now.addingTimeInterval(HatchEffect.profile(for: .common).revealAt + 0.1))
        XCTAssertTrue(s.pendingCelebrations.isEmpty)
        var second = CelebrationPlayer()
        second.startIfIdle(queue: s, current: current(s), reduceMotion: false, now: now.addingTimeInterval(60))
        XCTAssertNil(second.active, "다시 재생하지 않는다")
        XCTAssertEqual(second.idleSprite(queue: s, current: current(s)), current(s))
    }

    /// 졸업은 끝에 꺼낸다 — 중간에 끊기면 다음에 몬스터볼부터 다시.
    func testGraduationIsConsumedAtTheEnd() {
        let queue = FakeQueue([.graduate(speciesID: 7, shiny: true, form: nil), .hatch(shiny: false, rarity: .rare)])
        var player = CelebrationPlayer()
        let cur = Sprite(speciesID: nil, back: true)
        player.startIfIdle(queue: queue, current: cur, reduceMotion: false, now: now)
        XCTAssertEqual(player.active?.kind, .graduate(Sprite(speciesID: 7, shiny: true, back: true),
                                                     egg: Sprite(speciesID: nil, back: true)))
        XCTAssertEqual(player.advance(queue: queue, now: now.addingTimeInterval(2)), [])
        XCTAssertEqual(queue.pendingCelebrations.count, 2, "끝나기 전엔 남아 있다")
        XCTAssertEqual(CelebrationPlayer.concealment(queue.pendingCelebrations), .egg,
                       "졸업 자체는 안 가리지만 뒤의 부화 때문에 가린다")
        XCTAssertEqual(player.advance(queue: queue, now: now.addingTimeInterval(GraduationEffect.duration)),
                       [.revealed(.graduate(speciesID: 7, shiny: true, form: nil)), .finished])
        XCTAssertEqual(queue.pendingCelebrations, [.hatch(shiny: false, rarity: .rare)])
    }

    /// 재생 중 큐가 바뀌었으면(세이브 불러오기 등) 남의 연출을 꺼내지 않는다.
    func testDoesNotConsumeACelebrationItDidNotPlay() {
        let queue = FakeQueue([.evolve(fromID: 1, toID: 2, shiny: false, form: nil, fromName: "A", rarity: .common)])
        var player = CelebrationPlayer()
        player.startIfIdle(queue: queue, current: Sprite(speciesID: 2), reduceMotion: false, now: now)
        queue.pendingCelebrations = [.hatch(shiny: false, rarity: .common)]
        XCTAssertEqual(player.advance(queue: queue, now: now.addingTimeInterval(EvolutionEffect.revealAt)), [])
        XCTAssertEqual(queue.pendingCelebrations, [.hatch(shiny: false, rarity: .common)])
        XCTAssertEqual(player.advance(queue: queue, now: now.addingTimeInterval(EvolutionEffect.duration)), [.finished])
    }

    /// "항상 뒷모습" 이면 연출 속 스프라이트도 뒷모습(알 제외 — 알은 뒷모습이 없어 SpriteView 가 무시한다).
    func testSpritesKeepTheBackFacingPreference() {
        let queue = FakeQueue([.evolve(fromID: 1, toID: 2, shiny: true, form: nil, fromName: "A", rarity: .common)])
        var player = CelebrationPlayer()
        player.startIfIdle(queue: queue, current: Sprite(speciesID: 2, shiny: true, back: true),
                           reduceMotion: true, now: now)
        XCTAssertEqual(player.active?.kind, .evolve(from: Sprite(speciesID: 1, shiny: true, back: true),
                                                    to: Sprite(speciesID: 2, shiny: true, back: true)))
        XCTAssertEqual(player.active?.consumeAt, EvolutionEffect.reducedRevealAt, "동작 줄이기 타이밍")
    }
}

/// 테스트용 큐.
@MainActor
private final class FakeQueue: CelebrationQueue {
    var pendingCelebrations: [CompanionStore.Celebration]
    init(_ items: [CompanionStore.Celebration]) { pendingCelebrations = items }
    func consumeCelebration() -> CompanionStore.Celebration? {
        pendingCelebrations.isEmpty ? nil : pendingCelebrations.removeFirst()
    }
}

// MARK: 공유 재생(헤더 + 플로팅 펫)

@MainActor
final class CelebrationStageTests: XCTestCase {
    private final class Clock { var now = Date(timeIntervalSince1970: 1_700_000_000) }

    private func stage(_ line: EvoLine) async -> (CompanionStore, CelebrationStage, Clock) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("celebration-stage-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let store = CompanionStore(provider: StubProvider(value: line), clock: { now }, fileURL: url,
                                   rng: SeededRNG(seed: 7), dittoDisguiseRollingEnabled: false)
        let clock = Clock()
        let stage = store.celebrationStage!
        stage.schedulesTimers = false
        stage.clock = { clock.now }
        stage.reduceMotion = { false }
        await store.hatch(baseID: 1)
        return (store, stage, clock)
    }

    /// 아무 화면도 안 보면 시작하지 않고 큐에 남는다(팝오버 닫힘 + 펫 꺼짐).
    func testNothingPlaysWithoutAViewer() async {
        let (store, stage, _) = await stage(linear(1, count: 2, rarity: .rare))
        stage.kick()
        XCTAssertNil(stage.active)
        XCTAssertEqual(store.pendingCelebrations.count, 1)
    }

    /// 헤더와 펫이 함께 보면 재생은 하나 — 같은 시작 시각, 공개 때 정확히 한 번 꺼낸다. 한쪽이 사라져도 계속.
    func testTwoSurfacesShareOnePlaybackAndConsumeOnce() async {
        let (store, stage, clock) = await stage(linear(1, count: 2, rarity: .rare))
        let header = UUID(), pet = UUID()
        stage.attach(pet)
        let started = stage.active
        XCTAssertNotNil(started)
        clock.now += 0.5
        stage.attach(header)
        XCTAssertEqual(stage.active?.serial, started?.serial, "늦게 연 헤더도 같은 장면을 이어서 본다")
        XCTAssertEqual(stage.active?.start, started?.start)
        stage.detach(header)
        XCTAssertNotNil(stage.active, "펫이 아직 보고 있다")
        clock.now += HatchEffect.profile(for: .rare).revealAt
        stage.tick()
        XCTAssertTrue(store.pendingCelebrations.isEmpty, "공개 때 한 번 꺼냈다")
        clock.now += 5
        stage.tick()
        XCTAssertNil(stage.active)
        XCTAssertTrue(store.pendingCelebrations.isEmpty)
    }

    /// 공개 전에 보던 화면이 전부 사라지면 다음 시작은 처음부터(같은 연출을 다시).
    func testAllSurfacesGoneBeforeTheRevealReplaysFromTheStart() async {
        let (store, stage, clock) = await stage(linear(1, count: 2, rarity: .legendary))
        let header = UUID()
        stage.attach(header)
        clock.now += 1
        stage.tick()
        stage.detach(header)
        XCTAssertNil(stage.active)
        XCTAssertEqual(store.pendingCelebrations.count, 1, "아직 안 꺼냈다")
        clock.now += 60
        stage.attach(UUID())
        XCTAssertEqual(stage.active?.start, clock.now, "처음부터 다시")
    }

    func testAllSurfacesGoneAfterTheRevealDoesNotReplay() async {
        let (store, stage, clock) = await stage(linear(1, count: 2))
        let pet = UUID()
        stage.attach(pet)
        clock.now += HatchEffect.profile(for: .common).revealAt + 0.1
        stage.tick()
        stage.detach(pet)
        XCTAssertTrue(store.pendingCelebrations.isEmpty)
        stage.attach(UUID())
        XCTAssertNil(stage.active, "다시 재생하지 않는다")
    }

    /// 재생이 끝나면 다음 연출로 넘어간다(부화 → 졸업).
    func testFinishedCelebrationStartsTheNextOne() async {
        let (store, stage, clock) = await stage(linear(1, count: 1))
        store.applyUsage(10_000_000_000)   // 즉시 졸업 → [부화, 졸업]
        XCTAssertEqual(store.pendingCelebrations.count, 2)
        stage.attach(UUID())
        clock.now += 10
        stage.tick()   // 부화: 공개 + 끝
        guard case .graduate? = stage.active?.kind else { return XCTFail("졸업이 이어져야 한다") }
        XCTAssertEqual(stage.active?.start, clock.now)
    }

    /// 큐가 통째로 바뀌면(놓아주기·불러오기) 공개 전의 남 연출을 버린다.
    func testReplacedQueueAbandonsAStaleScene() async {
        let (store, stage, _) = await stage(linear(1, count: 2))
        stage.attach(UUID())
        XCTAssertNotNil(stage.active)
        store.consumeCelebration()   // store 가 큐를 바꿨다(applySave·buyFreshEgg 가 부르는 경로)
        stage.queueReplaced()
        XCTAssertNil(stage.active, "큐에서 사라진 연출을 끝까지 그리지 않는다")
    }

    /// 메뉴바·플로팅 펫은 공개 전 연출의 직전 모습을 붙든다 — 대표를 고정했으면 그대로.
    func testRepresentativeHoldsThePreRevealSprite() async {
        let (store, _, _) = await stage(linear(1, count: 2))
        XCTAssertEqual(store.representativeSubject.speciesID, 1)
        XCTAssertNil(store.heldRepresentativeSubject.speciesID, "부화 공개 전엔 알")
        XCTAssertTrue(store.floatingPetPlaysCelebrations)
        store.consumeCelebration()
        XCTAssertEqual(store.heldRepresentativeSubject.speciesID, 1)
    }
}

// MARK: 칸의 "직전 모습"(순수)

final class CelebrationSpriteBeforeTests: XCTestCase {
    typealias Sprite = CelebrationPlayer.Sprite

    func testSpriteBeforeEachCelebration() {
        let current = Sprite(speciesID: 3, shiny: false, form: nil, back: true)
        XCTAssertEqual(CelebrationPlayer.spriteBefore(nil, current: current), current)
        XCTAssertEqual(CelebrationPlayer.spriteBefore(.hatch(shiny: true, rarity: .rare), current: current),
                       Sprite(speciesID: nil, back: true), "부화 전엔 알")
        XCTAssertEqual(CelebrationPlayer.spriteBefore(
                           .evolve(fromID: 1, toID: 2, shiny: true, form: PokemonForm("sandy"), fromName: "A", rarity: .common),
                           current: current),
                       Sprite(speciesID: 1, shiny: true, form: PokemonForm("sandy"), back: true), "진화 전엔 옛 모습")
        XCTAssertEqual(CelebrationPlayer.spriteBefore(.graduate(speciesID: 9, shiny: false, form: nil), current: current),
                       Sprite(speciesID: 9, back: true), "졸업 전엔 졸업하는 포켓몬")
        let disguise = CompanionStore.DittoDisguise(speciesID: 412, form: PokemonForm("sandy"), name: "B", rarity: .common)
        XCTAssertEqual(CelebrationPlayer.spriteBefore(.dittoReveal(shiny: true, disguise: disguise), current: current),
                       Sprite(speciesID: 412, shiny: false, form: PokemonForm("sandy"), back: true),
                       "리빌 전엔 위장체(이로치 숨김)")
    }
}
