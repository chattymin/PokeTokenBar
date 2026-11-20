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
        }
        XCTAssertEqual(profiles.map(\.wobbles), [1, 2, 3, 4])
        XCTAssertEqual(profiles.map(\.revealAt), [1.0, 1.5, 2.2, 3.0])
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
    func testPokemonIsPulledInThenTheBallWobblesThreeTimesAndRevealsTheEgg() {
        let start = GraduationEffect.frame(at: 0)
        XCTAssertEqual(start.monOpacity, 1); XCTAssertEqual(start.monScale, 1); XCTAssertEqual(start.eggOpacity, 0)
        let absorbing = GraduationEffect.frame(at: 0.6)
        XCTAssertGreaterThan(absorbing.monRed, 0.9, "빨려 들어가며 붉게 물든다")
        XCTAssertLessThan(absorbing.monScale, 0.8)
        XCTAssertGreaterThan(absorbing.ballOpen, 0.9, "덮개가 열려 있다")
        XCTAssertEqual(GraduationEffect.frame(at: 0.8).monOpacity, 0, "볼에 들어간 뒤엔 안 보인다")
        XCTAssertEqual(GraduationEffect.frame(at: 0.9).ballOpen, 0, "닫힌 뒤 흔들린다")
        XCTAssertEqual(GraduationEffect.wobbleStarts.count, 3)
        for s in GraduationEffect.wobbleStarts {
            let u = GraduationEffect.wobbleLength
            XCTAssertGreaterThan(GraduationEffect.frame(at: s + u * 0.25).ballTilt, 10)
            XCTAssertLessThan(GraduationEffect.frame(at: s + u * 0.75).ballTilt, -10)
        }
        XCTAssertGreaterThan(GraduationEffect.frame(at: GraduationEffect.clickAt + 0.1).sparkle, 0, "딸깍 반짝임")
        let end = GraduationEffect.frame(at: GraduationEffect.duration)
        XCTAssertEqual(end.eggOpacity, 1, accuracy: 1e-9); XCTAssertEqual(end.ballOpacity, 0, accuracy: 1e-9)
    }

    func testReduceMotionFadesWithoutWobble() {
        for t in stride(from: 0.0, through: GraduationEffect.reducedDuration, by: 0.05) {
            let f = GraduationEffect.frame(at: t, reduceMotion: true)
            XCTAssertEqual(f.ballTilt, 0); XCTAssertEqual(f.monScale, 1); XCTAssertEqual(f.monPull, 0)
            XCTAssertEqual(f.ballScale, 1)
        }
        XCTAssertEqual(GraduationEffect.frame(at: 0.75, reduceMotion: true).monOpacity, 0)
        XCTAssertEqual(GraduationEffect.frame(at: GraduationEffect.reducedDuration, reduceMotion: true).eggOpacity, 1,
                       accuracy: 1e-9)
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
            XCTAssertTrue(s.hasPendingHatch)
        }
    }

    /// 알을 사서 지금 개체를 놓아주면 그 개체의 대기 연출도 버린다(새 알 위에서 옛 진화가 재생되지 않게).
    func testReleasingForAFreshEggDropsPendingCelebrations() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("celebration-release-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let active = #"{"baseID":1,"pathIDs":[1],"plannedPathIDs":[1,2,3],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":3}"#
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":5000000000,\"lastDate\":\"d1\",\"active\":\(active),\"dex\":[]}"
        try Data(json.utf8).write(to: url)
        let s = CompanionStore(provider: StubProvider(value: linear(1, count: 3)), clock: { now }, fileURL: url,
                               rng: SeededRNG(seed: 3), dittoDisguiseRollingEnabled: false)
        tick(s, tokens: 0)
        for _ in 0..<200 where s.currentLine == nil { await Task.yield() }
        s.applyUsage(s.threshold)
        XCTAssertEqual(s.pendingCelebrations, [.evolve])
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertTrue(s.pendingCelebrations.isEmpty)
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

    /// 졸업은 앞서 대기 중인 진화를 버린다 — 몬스터볼 연출이 최종 모습을 보여 준다.
    func testGraduationDropsPendingEvolves() async {
        let s = store(linear(1, count: 3))
        await s.hatch(baseID: 1)
        let shiny = s.currentIsShiny
        XCTAssertEqual(s.consumeCelebration(), .hatch(shiny: shiny, rarity: .common))
        XCTAssertFalse(s.hasPendingHatch)
        s.applyUsage(10_000_000_000)
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.pendingCelebrations, [.graduate(speciesID: 3, shiny: shiny, form: nil)])
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
        await s.hatch(baseID: 1)
        let thresholds = (0..<5).map { _ -> Int in let t = s.threshold; s.applyUsage(t); return t }
        XCTAssertEqual(thresholds.count, 5)
        XCTAssertEqual(s.state.active?.stageIndex, 5)
        XCTAssertEqual(s.pendingCelebrations.count, CompanionStore.celebrationQueueCap)
        XCTAssertEqual(s.pendingCelebrations, Array(repeating: .evolve, count: CompanionStore.celebrationQueueCap),
                       "가장 오래된 부화가 밀려난다")
    }

    /// 꺼낸 연출은 다시 나오지 않는다(팝오버 재오픈·헤더 재마운트에도 1회).
    func testConsumingIsOneTime() async {
        let s = store(linear(1, count: 2))
        XCTAssertNil(s.consumeCelebration())
        await s.hatch(baseID: 1)
        let seq = s.celebrationSeq
        XCTAssertTrue(s.hasPendingHatch)
        XCTAssertNotNil(s.consumeCelebration())
        XCTAssertNil(s.consumeCelebration())
        XCTAssertNil(s.celebration)
        XCTAssertFalse(s.hasPendingHatch)
        XCTAssertEqual(s.celebrationSeq, seq, "꺼내기는 새 연출 신호가 아니다")
    }
}

// MARK: 칸의 "직전 모습"(순수)

final class CelebrationSpriteBeforeTests: XCTestCase {
    typealias Sprite = CompanionHeader.CelebrationSprite

    func testSpriteBeforeEachCelebration() {
        let current = Sprite(speciesID: 3, shiny: false, form: nil, back: true)
        XCTAssertEqual(CompanionHeader.spriteBefore(nil, current: current), current)
        XCTAssertEqual(CompanionHeader.spriteBefore(.dittoReveal(shiny: true), current: current), current)
        XCTAssertEqual(CompanionHeader.spriteBefore(.hatch(shiny: true, rarity: .rare), current: current),
                       Sprite(speciesID: nil), "부화 전엔 알")
        XCTAssertEqual(CompanionHeader.spriteBefore(.evolve, current: current), current)
        XCTAssertEqual(CompanionHeader.spriteBefore(.graduate(speciesID: 9, shiny: false, form: nil), current: current),
                       Sprite(speciesID: 9), "졸업 전엔 졸업하는 포켓몬")
    }
}
