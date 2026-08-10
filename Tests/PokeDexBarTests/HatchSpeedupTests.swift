import XCTest
@testable import PokeDexBar

/// 알을 빨리 깨우는 포켓몬 — 불꽃몸·마그마의무장·증기기관.
@MainActor
final class HatchSpeedupTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 0)

    private func makeStore() -> PlayerStore {
        PlayerStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("speed-\(UUID().uuidString).json"),
                    rng: SeededRNG(seed: 9), now: { [self] in clock },
                    defaults: UserDefaults(suiteName: "ptb-speed-\(UUID().uuidString)")!)
    }

    private func make(_ speciesID: Int) -> Individual {
        Individual(baseID: speciesID, speciesID: speciesID, pathIDs: [speciesID], nature: .hardy,
                   obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
    }

    /// 표가 특성 목록과 맞는지 — 대표 종 몇 개로 짚는다. 오타 하나면 그 종을 얻어도 감면이 안 걸리고,
    /// 값은 아무 데도 안 남아 원인이 안 보인다.
    func testTheTableHoldsTheRightSpecies() {
        for id in [77, 126, 218, 240, 323, 607, 837, 850] {      // 포니타·마그마·마그마그·마그비·폭타·불켜미·탄동·태우지네
            XCTAssertTrue(HatchSpeedup.species.contains(id), "\(id) 가 표에 없다")
        }
        XCTAssertFalse(HatchSpeedup.species.contains(25), "피카츄가 표에 있다")
        XCTAssertEqual(HatchSpeedup.species.count, 23)
    }

    /// **남은 시간만 줄어든다.** 지나간 시간은 안 건드린다 — 원작에서도 그 시점부터 카운터가
    /// 두 배로 도는 것이지 이미 걸은 걸음이 두 배로 쳐지지는 않는다.
    func testOnlyTheRemainingTimeIsHalved() {
        let now = Date(timeIntervalSince1970: 0)
        // 30분짜리를 20분 굴린 상태 — 남은 10분이 5분이 된다(유효 15분이 되어 이미 익지 않는다).
        let hatchesAt = now.addingTimeInterval(600)
        XCTAssertEqual(HatchSpeedup.halvedRemaining(hatchesAt: hatchesAt, now: now),
                       now.addingTimeInterval(300))
        // 이미 익은 알은 안 건드린다.
        let past = now.addingTimeInterval(-60)
        XCTAssertEqual(HatchSpeedup.halvedRemaining(hatchesAt: past, now: now), past)
    }

    /// 얻는 순간 진행 중인 알이 빨라진다.
    func testGettingOneSpeedsUpEggsAlreadyIncubating() throws {
        let store = makeStore()
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: clock)
        let egg = try XCTUnwrap(store.startEgg(grade: .legendary, speciesID: 25, shiny: false))
        let before = try XCTUnwrap(store.state.eggs.first { $0.id == egg.id }).remaining(at: clock)

        store.addForTesting(make(218))                       // 마그마그
        let after = try XCTUnwrap(store.state.eggs.first { $0.id == egg.id }).remaining(at: clock)
        XCTAssertEqual(after, before * 0.5, accuracy: 1)
    }

    /// **중첩 안 된다.** 두 번째 아이를 얻어도 남은 시간이 또 줄면 안 된다 — 원작 그대로다.
    func testASecondOneChangesNothing() throws {
        let store = makeStore()
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: clock)
        let egg = try XCTUnwrap(store.startEgg(grade: .legendary, speciesID: 25, shiny: false))
        store.addForTesting(make(218))
        let once = try XCTUnwrap(store.state.eggs.first { $0.id == egg.id }).remaining(at: clock)

        store.addForTesting(make(126))                       // 마그마 — 또 하나
        let twice = try XCTUnwrap(store.state.eggs.first { $0.id == egg.id }).remaining(at: clock)
        XCTAssertEqual(twice, once, accuracy: 0.5, "두 마리째에 또 줄었다")
    }

    /// 관계없는 종은 아무 영향이 없다.
    func testAnOrdinarySpeciesDoesNothing() throws {
        let store = makeStore()
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: clock)
        let egg = try XCTUnwrap(store.startEgg(grade: .legendary, speciesID: 25, shiny: false))
        let before = try XCTUnwrap(store.state.eggs.first { $0.id == egg.id }).remaining(at: clock)
        store.addForTesting(make(25))
        let after = try XCTUnwrap(store.state.eggs.first { $0.id == egg.id }).remaining(at: clock)
        XCTAssertEqual(after, before, accuracy: 0.5)
    }

    /// **그 뒤에 뽑는 알은 처음부터 절반이다.**
    func testLaterEggsStartHalved() throws {
        let store = makeStore()
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: clock)
        let plain = try XCTUnwrap(store.startEgg(grade: .legendary, speciesID: 25, shiny: false))
        let full = try XCTUnwrap(store.state.eggs.first { $0.id == plain.id }).remaining(at: clock)

        store.addForTesting(make(218))
        let fast = try XCTUnwrap(store.startEgg(grade: .legendary, speciesID: 26, shiny: false))
        XCTAssertEqual(try XCTUnwrap(store.state.eggs.first { $0.id == fast.id }).remaining(at: clock),
                       full * 0.5, accuracy: 1)
    }

    /// **실제로 얻는 경로 — 부화 — 로도 확인한다.**
    ///
    /// 이걸 안 쓰면 `addForTesting` 만 지나는 테스트가 되고, 부화 경로에서 순서가 깨져도 아무도
    /// 안 운다. 실제로 그랬다: 부화 쪽 순서를 일부러 뒤집었는데 일곱 개가 전부 통과했다.
    func testHatchingOneSpeedsUpTheOtherEggs() throws {
        let store = makeStore()
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: clock)
        // 마그마그가 든 알과, 함께 굴러가는 레전더리 알.
        let magma = try XCTUnwrap(store.startEgg(grade: .common, speciesID: 218, shiny: false))
        let other = try XCTUnwrap(store.startEgg(grade: .legendary, speciesID: 25, shiny: false))

        clock = clock.addingTimeInterval(3_600)       // 커먼(30분)은 익고 레전더리(24시간)는 아직
        let before = try XCTUnwrap(store.state.eggs.first { $0.id == other.id }).remaining(at: clock)
        XCTAssertGreaterThan(before, 0, "레전더리가 벌써 익었다 — 이 검사가 뜻이 없어진다")

        XCTAssertNotNil(store.claimHatch(eggID: magma.id, at: clock), "마그마그를 못 거뒀다")
        let after = try XCTUnwrap(store.state.eggs.first { $0.id == other.id }).remaining(at: clock)
        XCTAssertEqual(after, before * 0.5, accuracy: 1, "부화로 얻었는데 감면이 안 걸렸다")
    }

    /// **넣기 전에 재야 한다.** 넣은 뒤에 재면 방금 들어온 아이 때문에 항상 참이 되어
    /// 감면이 영영 안 걸린다 — 이 순서가 곧 결함의 형태다.
    func testTheCheckHappensBeforeTheIndividualArrives() throws {
        let store = makeStore()
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: clock)
        let egg = try XCTUnwrap(store.startEgg(grade: .epic, speciesID: 25, shiny: false))
        let before = try XCTUnwrap(store.state.eggs.first { $0.id == egg.id }).remaining(at: clock)
        store.addForTesting(make(837))                       // 탄동
        XCTAssertLessThan(try XCTUnwrap(store.state.eggs.first { $0.id == egg.id })
                            .remaining(at: clock), before, "감면이 안 걸렸다")
    }
}

/// 부화 줄의 감면 표시 — 카운트다운만 짧아지면 왜 빨라졌는지 알 길이 없다.
@MainActor
final class HatchSpeedupBadgeTests: XCTestCase {
    /// 배지가 뜨는 조건이 곧 감면이 걸리는 조건이어야 한다. 둘이 갈라지면 표시가 거짓말을 한다 —
    /// 빨라졌는데 표시가 없거나, 표시만 있고 안 빨라지거나.
    func testTheBadgeAppearsExactlyWhenTheDiscountApplies() {
        let ordinary = [Individual(baseID: 25, speciesID: 25, pathIDs: [25], nature: .hardy,
                                   obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)]
        XCTAssertFalse(HatchSpeedup.present(in: []))
        XCTAssertFalse(HatchSpeedup.present(in: ordinary))
        let warmed = ordinary + [Individual(baseID: 218, speciesID: 218, pathIDs: [218],
                                           nature: .hardy,
                                           obtainedAt: Date(timeIntervalSince1970: 0), grade: .rare)]
        XCTAssertTrue(HatchSpeedup.present(in: warmed))
    }

    /// 배지와 설명이 세 언어 모두 채워져 있어야 한다.
    func testTheBadgeIsLocalized() {
        for text in [\L.eggWarmedBadge, \L.eggWarmedHint] as [KeyPath<L, String>] {
            let all = [AppLanguage.ko, .en, .ja].map { L($0)[keyPath: text] }
            XCTAssertEqual(Set(all).count, 3, all.description)
            XCTAssertFalse(all.contains { $0.isEmpty })
        }
    }

    /// 부화 줄이 배지를 실제로 그리는지 — 조건만 맞고 화면에 안 닿으면 이 저장소가
    /// 반복해서 밟은 "기능은 있는데 화면이 없다" 가 된다.
    func testTheEggRowActuallyDrawsIt() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/EggSlotsView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertTrue(text.contains("HatchSpeedup.present"), "부화 줄이 감면 여부를 안 본다")
        XCTAssertTrue(text.contains("eggWarmedBadge"), "배지 문구를 안 쓴다")
    }
}
