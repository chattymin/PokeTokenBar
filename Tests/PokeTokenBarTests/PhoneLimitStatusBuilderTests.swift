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
}
