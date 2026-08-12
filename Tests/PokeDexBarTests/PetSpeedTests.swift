import XCTest
import SwiftUI
@testable import PokeDexBar

/// 오늘 사용량과 분당 토큰을 한 벌로 내놓는 스텁. 오늘치가 있어야 스냅샷이 생기므로 둘 다 준다.
private struct RateProvider: UsageProvider {
    let id: String
    let displayName: String
    let rate: Double

    init(id: String, rate: Double) {
        self.id = id
        self.displayName = id
        self.rate = rate
    }

    func fetchDaily() async throws -> DailyUsage? {
        DailyUsage(date: LocalUsageReader.todayKey(), inputTokens: 1_000, outputTokens: 0,
                   cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: 1_000, totalCost: 0)
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        var r = ProviderEnrichment()
        r.recentTokensPerMinute = rate
        r.blocksOK = true
        return r
    }
}

/// 토큰을 태우는 동안 플로팅 펫이 빨라진다.
@MainActor
final class PetSpeedTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: 짧은 창 — 지금 돌아가고 있나

    private func entry(_ secondsAgo: TimeInterval, tokens: Int) -> LocalUsageReader.Entry {
        let date = now.addingTimeInterval(-secondsAgo)
        return LocalUsageReader.Entry(id: UUID().uuidString, date: date, localDay: "2023-11-14",
                                      model: "test", input: tokens, output: 0,
                                      cacheWrite: 0, cacheRead: 0)
    }

    /// **창 안의 것만 센다.** 5시간 창(`activeBlock`)과 다른 값이어야 이 기능이 성립한다 —
    /// 30분 전에 크게 태우고 지금 쉬고 있으면 펫은 원래 속도로 돌아와 있어야 한다.
    func testOnlyTokensInsideTheWindowCount() {
        let inside = LocalUsageReader.recentRate(entries: [entry(60, tokens: 500_000)], now: now)
        let outside = LocalUsageReader.recentRate(entries: [entry(1800, tokens: 500_000)], now: now)

        XCTAssertEqual(inside, 100_000, accuracy: 1, "창 안(1분 전) 토큰이 안 잡혔다")
        XCTAssertEqual(outside, 0, accuracy: 1e-9, "창 밖(30분 전) 토큰이 지금 속도로 샜다")
    }

    /// **나누는 값은 창 길이지 첫 항목 이후 경과가 아니다.** 방금 한 건 찍힌 순간
    /// "1초 만에 50만" 으로 읽어 폭주로 착각하면, 한 번 부를 때마다 펫이 튄다.
    func testRateDividesByTheWindowNotByElapsedSinceTheFirstEntry() {
        // 1초 전 50만 한 건 — 경과(1초)로 나눴다면 분당 3천만이 된다.
        let rate = LocalUsageReader.recentRate(entries: [entry(1, tokens: 500_000)], now: now)

        XCTAssertEqual(rate, 100_000, accuracy: 1, "경과 시간으로 나눠 값이 튀었다")
    }

    /// 미래에 찍힌 엔트리(시계 어긋남)는 안 센다 — 창은 [now-window, now] 이다.
    func testEntriesInTheFutureAreIgnored() {
        XCTAssertEqual(LocalUsageReader.recentRate(entries: [entry(-60, tokens: 500_000)], now: now),
                       0, accuracy: 1e-9)
    }

    // MARK: 배속 사다리

    /// 실제 로그 분포에 못 박은 네 칸. 인접한 칸이 서로 **다른** 값을 내야 사다리가 의미가 있다.
    func testLadderGivesADistinctSpeedPerBand() {
        XCTAssertEqual(PetSpeed.multiplier(tokensPerMinute: 0), 1.0, accuracy: 1e-9, "유휴")
        XCTAssertEqual(PetSpeed.multiplier(tokensPerMinute: 200_000), 1.25, accuracy: 1e-9, "가벼움")
        XCTAssertEqual(PetSpeed.multiplier(tokensPerMinute: 1_200_000), 1.5, accuracy: 1e-9, "보통")
        XCTAssertEqual(PetSpeed.multiplier(tokensPerMinute: 3_000_000), 2.0, accuracy: 1e-9, "폭주")
    }

    /// **위로 열려 있어도 2배를 안 넘는다.** 상한이 없으면 원본 10프레임 GIF 가 형체를 잃는다.
    func testSpeedIsCappedAtTwo() {
        XCTAssertEqual(PetSpeed.multiplier(tokensPerMinute: 999_000_000), 2.0, accuracy: 1e-9)
    }

    /// 말이 안 되는 값은 유휴로 떨어진다 — 여기서 안 막으면 아래 `frameDelay` 가 0으로 나눈다.
    func testNonsenseRatesFallBackToIdle() {
        for bad in [-1.0, .nan, -Double.infinity] {
            XCTAssertEqual(PetSpeed.multiplier(tokensPerMinute: bad), 1.0, accuracy: 1e-9, "\(bad)")
        }
    }

    /// **설정을 끄면 폭주 중이어도 원래 속도.** 게이트가 한 곳에만 있다는 걸 잠근다.
    func testTheSettingOffPinsTheSpeedToIdle() {
        XCTAssertEqual(PetSpeed.multiplier(tokensPerMinute: 3_000_000, enabled: false),
                       1.0, accuracy: 1e-9)
        XCTAssertEqual(PetSpeed.multiplier(tokensPerMinute: 3_000_000, enabled: true),
                       2.0, accuracy: 1e-9, "켰는데도 안 빨라지면 대조군이 무의미하다")
    }

    // MARK: 프레임 간격

    /// 배속이 프레임 간격을 실제로 줄인다. 원본 0.1초 프레임이 2배에서 0.05초가 된다.
    func testSpeedShortensTheFrameDelay() {
        XCTAssertEqual(SpriteView.frameDelay(base: 0.1, floor: 0, speed: 2), 0.05, accuracy: 1e-9)
        XCTAssertEqual(SpriteView.frameDelay(base: 0.1, floor: 0, speed: 1), 0.1, accuracy: 1e-9)
    }

    /// **하한이 배속보다 세다.** 메뉴바처럼 fps 상한이 걸린 표면에 배속이 새 들어와도
    /// 상한을 못 넘는다(CLAUDE.md — 두 표면의 규율을 섞지 않는다).
    func testTheFpsFloorStillWinsOverSpeed() {
        XCTAssertEqual(SpriteView.frameDelay(base: 0.1, floor: 0.4, speed: 2), 0.4, accuracy: 1e-9)
    }

    /// 0배속이 들어와도 프레임 간격이 무한이 되지 않는다(펫이 얼어붙는 결함).
    func testZeroSpeedIsTreatedAsNormal() {
        XCTAssertEqual(SpriteView.frameDelay(base: 0.1, floor: 0, speed: 0), 0.1, accuracy: 1e-9)
        XCTAssertEqual(SpriteView.frameDelay(base: 0.1, floor: 0, speed: .nan), 0.1, accuracy: 1e-9)
    }

    // MARK: 스토어 배선

    private func makeStore(providers: [any UsageProvider] = [],
                           suite: String = UUID().uuidString) -> UsageStore {
        UsageStore(providers: providers, autoRefresh: false,
                   defaults: UserDefaults(suiteName: suite)!)
    }

    private func snapshot(_ id: String, rate: Double) -> ProviderSnapshot {
        ProviderSnapshot(providerID: id, displayName: id, today: nil, activeBlock: nil,
                         recentTokensPerMinute: rate, weekTotal: nil, monthTotal: nil,
                         fetchedAt: Date())
    }

    /// **전 프로바이더 합산.** 한 프로바이더에만 붙이면 Codex 전용 사용자의 펫이 영원히
    /// 느리다 — burn 이 예전에 정확히 이 회귀를 냈다(CLAUDE.md 확장 규약).
    func testBurnSumsEveryProvider() {
        let rate = UsageStore.burnPerMinute(
            snapshots: [snapshot("claude_code", rate: 300_000), snapshot("codex", rate: 400_000)],
            isStale: false)

        XCTAssertEqual(rate, 700_000, accuracy: 1, "합산이 아니라 한 프로바이더만 봤다")
    }

    /// **오래됐으면 0.** 새로고침이 멈춘 동안 마지막 값이 굳으면, 아무 일도 안 하는데 펫이
    /// 계속 뛴다. 같은 스냅샷으로 두 분기를 다 밟아 게이트가 늘 켜져 있지도, 꺼져 있지도
    /// 않다는 걸 함께 확인한다.
    func testAStaleSnapshotStopsDrivingTheSpeed() {
        let snaps = [snapshot("claude_code", rate: 3_000_000)]

        XCTAssertEqual(UsageStore.burnPerMinute(snapshots: snaps, isStale: false),
                       3_000_000, accuracy: 1, "신선한 값이 안 잡힌다")
        XCTAssertEqual(UsageStore.burnPerMinute(snapshots: snaps, isStale: true),
                       0, accuracy: 1e-9, "오래된 값이 펫을 계속 몰았다")
    }

    /// **프로바이더가 만든 값이 스토어까지 실제로 흐른다.** 위 순수 함수 테스트는 스냅샷을 손으로
    /// 지어내므로, enrichment → 스냅샷 배선이 통째로 끊겨도 통과한다. 여기서는 실제 새로고침을
    /// 돌려 프로바이더가 내놓은 분당 토큰이 `recentBurnPerMinute` 에 도착하는지 본다.
    func testTheRefreshCarriesEachProvidersRateIntoTheStore() async {
        let claude = RateProvider(id: "claude_code", rate: 300_000)
        let codex = RateProvider(id: "codex", rate: 400_000)
        let store = makeStore(providers: [claude, codex])

        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertEqual(store.recentBurnPerMinute, 700_000, accuracy: 1,
                       "프로바이더의 분당 토큰이 스토어까지 안 왔다")
    }

    /// **화면이 실제로 그 값을 쓴다.** 순수 함수가 다 맞아도 뷰가 안 부르면 아무 일도 안 난다 —
    /// 이 레포가 반복해서 겪은 결함 부류라 배선을 따로 잠근다.
    func testThePetReadsBothTheBurnRateAndTheSetting() async {
        let store = makeStore(providers: [RateProvider(id: "claude_code", rate: 3_000_000)])
        await store.refresh(scheduleEmptyRetry: false)

        store.floatingPetBurnSpeed = true
        XCTAssertEqual(FloatingPetView.speed(store), 2.0, accuracy: 1e-9, "폭주 중인데 원래 속도다")

        store.floatingPetBurnSpeed = false
        XCTAssertEqual(FloatingPetView.speed(store), 1.0, accuracy: 1e-9, "설정을 껐는데 여전히 빠르다")
    }

    /// **펫 스프라이트가 그 배속으로 실제로 그려진다.** 위 테스트는 `FloatingPetView.speed` 라는
    /// *함수* 만 본다 — 뷰가 그 값을 `SpriteView` 에 안 넘기면 계산은 다 맞는데 펫은 그대로다.
    /// 이 레포에서 반복해서 난 결함이 정확히 이 모양이라 그려서 확인한다.
    func testTheRenderedSpriteCarriesTheSpeed() async {
        let store = makeStore(providers: [RateProvider(id: "claude_code", rate: 3_000_000)])
        await store.refresh(scheduleEmptyRetry: false)
        let player = PlayerStore(fileURL: FileManager.default.temporaryDirectory
                                    .appendingPathComponent("pet-\(UUID().uuidString).json"),
                                 defaults: UserDefaults(suiteName: UUID().uuidString)!)
        player.seedForTesting(wallet: 0, slots: 1, eggs: 0, at: Date())

        func renderedSpeeds() -> [Double] {
            SpriteView.resetConstructedSpeeds()
            let host = NSHostingView(rootView: AnyView(
                FloatingPetView().environment(store).environment(player)))
            host.layoutSubtreeIfNeeded()
            return SpriteView.constructedSpeeds
        }

        store.floatingPetBurnSpeed = true
        XCTAssertEqual(renderedSpeeds(), [2.0], "폭주 중인데 스프라이트가 원래 속도로 그려졌다")

        store.floatingPetBurnSpeed = false
        XCTAssertEqual(renderedSpeeds(), [1.0], "설정을 껐는데 스프라이트가 여전히 빠르다")
    }

    /// 새 설정의 기본값과 저장. 껐다 켠 뒤 새 스토어가 그대로 읽어야 한다.
    func testTheSettingDefaultsOnAndPersists() {
        let suite = UUID().uuidString
        XCTAssertTrue(makeStore(suite: suite).floatingPetBurnSpeed, "기본은 켬")

        makeStore(suite: suite).floatingPetBurnSpeed = false
        XCTAssertFalse(makeStore(suite: suite).floatingPetBurnSpeed, "끈 게 저장 안 됐다")
    }

    /// 문구가 세 언어를 다 채운다.
    func testBurnSpeedStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            XCTAssertFalse(L(lang).floatingPetBurnSpeedLabel.isEmpty, "\(lang) 라벨")
            XCTAssertFalse(L(lang).floatingPetBurnSpeedHint.isEmpty, "\(lang) 힌트")
        }
    }
}
