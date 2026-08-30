import XCTest
import PokeTokenBarShared
@testable import PokeTokenBar

/// Mac 이 폰/위젯에 보내는 한도 페이로드 빌더 — 라벨 접두어와 모델별(scoped) 매핑을 검증한다.
/// (TokenFormatter 가 app·shared 양쪽에 있어 두 모듈을 함께 import 하는 파일에서는 그 심볼을
/// 쓰지 않는다 — 여기선 L/LimitStatus/PhoneLimitStatus 만 참조해 모호성이 없다.)
@MainActor
final class PhoneLimitStatusBuilderTests: XCTestCase {
    func testPrefixesClaudeLabelsAndMapsScopedModels() {
        let json = """
        {"five_hour":{"utilization":2,"resets_at":"2099-01-01T00:00:00Z"},
         "seven_day":{"utilization":13},
         "limits":[
           {"kind":"session","percent":2},
           {"kind":"weekly_all","percent":13},
           {"kind":"weekly_scoped","percent":41,"resets_at":"2099-01-02T00:00:00Z","scope":{"model":{"display_name":"Fable"}}}]}
        """
        let limits = try! JSONDecoder().decode(LimitStatus.self, from: Data(json.utf8))
        let status = AppDelegate.phoneLimitStatus(limits: limits, codex: nil, opencodeGo: nil, l: L(.en))

        XCTAssertEqual(status.claude5h?.label, "Claude 5h")
        XCTAssertEqual(status.claudeWeekly?.label, "Claude Weekly")
        // session/weekly_all 은 레거시 행이 이미 표시하므로 scoped 에서 제외, Fable 만 남는다.
        XCTAssertEqual(status.claudeScoped?.count, 1)
        XCTAssertEqual(status.claudeScoped?.first?.label, "Claude Weekly Fable")
        XCTAssertEqual(status.claudeScoped?.first?.utilization, 41)
        XCTAssertNotNil(status.claudeScoped?.first?.resetsAt, "scoped 엔트리도 리셋 시각을 전달")
    }

    /// percent 가 없는 scoped 엔트리는 표시할 수 없으므로 제외한다.
    func testScopedEntryWithoutPercentSkipped() {
        let json = """
        {"five_hour":{"utilization":2},
         "limits":[
           {"kind":"weekly_scoped","scope":{"model":{"display_name":"Ghost"}}},
           {"kind":"weekly_scoped","percent":50,"scope":{"model":{"display_name":"Fable"}}}]}
        """
        let limits = try! JSONDecoder().decode(LimitStatus.self, from: Data(json.utf8))
        let status = AppDelegate.phoneLimitStatus(limits: limits, codex: nil, opencodeGo: nil, l: L(.en))
        XCTAssertEqual(status.claudeScoped?.map(\.label), ["Claude Weekly Fable"])
    }

    /// scoped 창이 없으면 배열이 아니라 nil 로 보내 폰의 빈-상태 판정을 단순화한다.
    func testNoScopedEntriesYieldsNil() {
        let limits = try! JSONDecoder().decode(
            LimitStatus.self, from: Data(#"{"five_hour":{"utilization":2}}"#.utf8))
        let status = AppDelegate.phoneLimitStatus(limits: limits, codex: nil, opencodeGo: nil, l: L(.en))
        XCTAssertNil(status.claudeScoped)
        XCTAssertEqual(status.claude5h?.label, "Claude 5h")
    }

    /// Codex·Go 라벨도 프로바이더 접두어를 갖는다(폰 카드에서 서로 구분되도록).
    func testCodexAndGoLabelsCarryProviderPrefix() {
        let codex = try! JSONDecoder().decode(CodexRateLimitStatus.self, from: Data(
            #"{"rateLimits":{"primary":{"usedPercent":61,"windowDurationMins":300},"secondary":{"usedPercent":40,"windowDurationMins":10080}}}"#.utf8))
        let go = try! JSONDecoder().decode(OpenCodeGoLimitStatus.self, from: Data(
            #"{"usage":{"rolling":{"status":"ok","percent":92},"weekly":{"status":"ok","percent":74},"monthly":{"status":"ok","percent":38}}}"#.utf8))
        let status = AppDelegate.phoneLimitStatus(limits: nil, codex: codex, opencodeGo: go, l: L(.en))
        XCTAssertEqual(status.codexPrimary?.label, "Codex 5h")
        XCTAssertEqual(status.codexSecondary?.label, "Codex Weekly")
        XCTAssertEqual(status.opencodeGo5h?.label, "Go 5h")
        XCTAssertEqual(status.opencodeGoWeekly?.label, "Go Weekly")
        XCTAssertEqual(status.opencodeGoMonthly?.label, "Go Monthly")
    }

    func testAllNilLimitsYieldEmptyStatus() {
        let status = AppDelegate.phoneLimitStatus(limits: nil, codex: nil, opencodeGo: nil, l: L(.en))
        XCTAssertNil(status.claude5h)
        XCTAssertNil(status.claudeScoped)
        XCTAssertTrue(status.orderedWindows.isEmpty)
    }

    /// Codex 리셋 시각은 최대 사용률 창의 resetsAt 을 짝지어 보낸다 (이전엔 항상 nil → 폰 카운트다운 불가).
    func testCodexWindowsCarryResetDates() {
        let codex = try! JSONDecoder().decode(CodexRateLimitStatus.self, from: Data(
            #"{"rateLimits":{"primary":{"usedPercent":61,"windowDurationMins":300,"resetsAt":4102444800},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":4102531200}}}"#.utf8))
        let status = AppDelegate.phoneLimitStatus(limits: nil, codex: codex, opencodeGo: nil, l: L(.en))
        XCTAssertEqual(status.codexPrimary?.resetsAt, Date(timeIntervalSince1970: 4_102_444_800))
        XCTAssertEqual(status.codexSecondary?.resetsAt, Date(timeIntervalSince1970: 4_102_531_200))
    }

    /// Antigravity 버킷은 그룹(Gemini / Claude & GPT)·창 순서대로 평탄화되고 라벨에 접두어가 붙는다.
    func testAntigravityBucketsFlattenWithGroupLabels() {
        let agy = AntigravityRateLimitStatus(groups: [
            AntigravityQuotaGroup(displayName: "Gemini models", buckets: [
                AntigravityQuotaBucket(bucketId: "gemini-5h", displayName: "5h", window: "5h",
                                       resetTime: "2099-01-01T00:00:00Z", remainingFraction: 0.25),
                AntigravityQuotaBucket(bucketId: "gemini-weekly", displayName: "weekly", window: "weekly",
                                       remainingFraction: 0.9),
            ]),
            AntigravityQuotaGroup(displayName: "Claude/GPT", buckets: [
                AntigravityQuotaBucket(bucketId: "3p-5h", displayName: "5h", window: "5h", remainingFraction: 0.5),
            ]),
        ])
        let status = AppDelegate.phoneLimitStatus(limits: nil, codex: nil, opencodeGo: nil, antigravity: agy, l: L(.en))
        XCTAssertEqual(status.antigravity?.map(\.label),
                       ["Antigravity Gemini 5h", "Antigravity Gemini Weekly", "Antigravity Claude & GPT 5h"])
        let utilizations = status.antigravity?.map(\.utilization) ?? []
        XCTAssertEqual(utilizations.count, 3)
        for (got, want) in zip(utilizations, [75.0, 10.0, 50.0]) { XCTAssertEqual(got, want, accuracy: 0.001) }
        XCTAssertNotNil(status.antigravity?.first?.resetsAt)
        XCTAssertEqual(status.limitGroups.map(\.title), ["Antigravity"])
        XCTAssertEqual(status.orderedWindows.count, 3, "orderedWindows 에 Antigravity 창이 포함돼야 위젯/앱에 보인다")
    }

    /// 버킷이 하나도 없으면 antigravity 는 nil (빈 그룹 헤더가 폰에 생기지 않게).
    func testAntigravityWithoutBucketsIsNil() {
        let agy = AntigravityRateLimitStatus(groups: [AntigravityQuotaGroup(displayName: "Gemini models")])
        let status = AppDelegate.phoneLimitStatus(limits: nil, codex: nil, opencodeGo: nil, antigravity: agy, l: L(.en))
        XCTAssertNil(status.antigravity)
    }

    /// Mac 임계값이 그대로 실려 폰·위젯 색 규칙이 Mac 과 일치한다.
    func testThresholdsForwarded() {
        let status = AppDelegate.phoneLimitStatus(limits: nil, codex: nil, opencodeGo: nil,
                                                  warnThreshold: 50, critThreshold: 80, l: L(.en))
        XCTAssertEqual(status.effectiveWarnThreshold, 50)
        XCTAssertEqual(status.effectiveCritThreshold, 80)
        XCTAssertEqual(status.tier(for: 79), .warning)
        XCTAssertEqual(status.tier(for: 80), .critical)
        XCTAssertEqual(status.tier(for: 49), .normal)
    }

    /// 예측이 없고 burn 도 0 이면 nil; 예측만 있으면 tokensPerMinute 는 nil 로 보낸다.
    func testBurnForecastMapping() {
        XCTAssertNil(AppDelegate.phoneBurnForecast(forecast: nil, tokensPerMinute: 0))
        let onlyBurn = AppDelegate.phoneBurnForecast(forecast: nil, tokensPerMinute: 1200)
        XCTAssertNil(onlyBurn?.depletionDate)
        XCTAssertEqual(onlyBurn?.tokensPerMinute, 1200)
        let at = Date(timeIntervalSince1970: 4_102_444_800)
        let full = AppDelegate.phoneBurnForecast(
            forecast: UsageStore.FiveHourForecast(depletionDate: at, beforeReset: true), tokensPerMinute: 0)
        XCTAssertEqual(full?.depletionDate, at)
        XCTAssertTrue(full?.beforeReset ?? false)
        XCTAssertNil(full?.tokensPerMinute)
    }
    // MARK: 한도 이력 → 폰

    private func historyStore(_ samples: [(window: String, utilization: Double)],
                              spacing: TimeInterval = 1800) -> LimitHistoryStore {
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-phone-history-\(UUID().uuidString).json")
        let store = LimitHistoryStore(fileURL: file, now: { clock })
        for sample in samples {
            store.record(providerID: "claude_code", windows: [(sample.window, sample.utilization)])
            clock = clock.addingTimeInterval(spacing)
        }
        return store
    }

    /// 파생된 창·요약이 그대로 폰 시리즈가 된다. 폰은 창 분할 규칙을 재구현하지 않는다.
    func testPhoneHistoryCarriesDerivedWindowsAndSummary() {
        let store = historyStore([
            ("five_hour", 10), ("five_hour", 55), ("five_hour", 92),   // 창 1 (peak 92)
            ("five_hour", 1), ("five_hour", 40),                       // 리셋 → 창 2 (peak 40)
        ])
        let series = AppDelegate.phoneLimitHistory(store, warnThreshold: 80, l: L(.en))

        XCTAssertEqual(series.count, 1, "seven_day 는 기록이 없어 시리즈를 만들지 않는다")
        XCTAssertEqual(series[0].label, "Claude 5h")
        XCTAssertEqual(series[0].windows.map(\.peak), [92, 40], "오래된 창이 먼저")
        XCTAssertEqual(series[0].peak, 92)
        XCTAssertEqual(series[0].atOrAbove, 1, "warnThreshold 80 이상은 92 하나")
        XCTAssertFalse(series[0].hasTruncated)
    }

    /// `atOrAbove` 는 Mac 이 페이로드에 싣는 warnThreshold 로 세야 한다 — 폰이 다시 세면 어긋난다.
    func testPhoneHistoryCountsAgainstTheGivenThreshold() {
        let store = historyStore([
            ("five_hour", 10), ("five_hour", 55),
            ("five_hour", 1), ("five_hour", 40),
        ])
        XCTAssertEqual(AppDelegate.phoneLimitHistory(store, warnThreshold: 50, l: L(.en))[0].atOrAbove, 1)
        XCTAssertEqual(AppDelegate.phoneLimitHistory(store, warnThreshold: 30, l: L(.en))[0].atOrAbove, 2)
    }

    /// 두 창 종류가 모두 있으면 라이브 행과 같은 순서·라벨로 나간다.
    func testPhoneHistoryLabelsMatchTheLiveRows() {
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-phone-history-\(UUID().uuidString).json")
        let store = LimitHistoryStore(fileURL: file, now: { clock })
        for pair in [(10.0, 60.0), (55.0, 61.0), (1.0, 62.0)] {
            store.record(providerID: "claude_code",
                         windows: [("five_hour", pair.0), ("seven_day", pair.1)])
            clock = clock.addingTimeInterval(1800)
        }
        let series = AppDelegate.phoneLimitHistory(store, warnThreshold: 80, l: L(.en))
        XCTAssertEqual(series.map(\.label), ["Claude 5h", "Claude Weekly"])
        // 주간은 rolling 상승만 있었으므로 리셋 없이 한 창이어야 한다.
        XCTAssertEqual(series[1].windows.count, 1)
    }

    /// 완료된 창이 없으면 시리즈를 만들지 않고, 상태의 history 는 nil 이어야 한다 —
    /// 빈 배열을 보내면 폰이 "이력 있음" 카드를 띄우고 빈 차트를 그린다.
    func testEmptyHistoryIsOmittedFromTheStatus() {
        let empty = historyStore([])
        XCTAssertTrue(AppDelegate.phoneLimitHistory(empty, warnThreshold: 80, l: L(.en)).isEmpty)

        let status = AppDelegate.phoneLimitStatus(
            limits: nil, codex: nil, opencodeGo: nil,
            history: AppDelegate.phoneLimitHistory(empty, warnThreshold: 80, l: L(.en)),
            l: L(.en))
        XCTAssertNil(status.history, "빈 배열은 nil 로 정규화된다")
    }

    /// 관측 공백(앱 미실행)이 섞인 창은 그 사실을 폰까지 들고 가야 한다 — 최고치가 하한이라는 뜻이다.
    func testTruncatedWindowsSurviveToThePhone() {
        // 6시간 초과 간격 = 관측 공백 → 양쪽 창이 truncated 로 표시된다.
        let store = historyStore([("five_hour", 20), ("five_hour", 70)], spacing: 12 * 3600)
        let series = AppDelegate.phoneLimitHistory(store, warnThreshold: 80, l: L(.en))
        XCTAssertTrue(series[0].hasTruncated)
        XCTAssertEqual(series[0].windows.filter(\.truncated).count, series[0].windows.count)
    }

}
