import XCTest
@testable import PokeTokenBar

/// 페이스(균등 소진) 기준선의 순수 로직 — 창 길이 매핑, 경과율, 표시 모드 반전.
/// 렌더링 자체는 LimitProgressRenderingTests 가 뷰를 거쳐 검증한다.
final class LimitPaceTests: XCTestCase {
    private let fiveHour: TimeInterval = 5 * 3600
    private let sevenDay: TimeInterval = 7 * 24 * 3600

    // MARK: 창 길이 매핑 — 프로바이더마다 길이를 알리는 방식이 다르다

    func testWindowSpanFromCodexWindowDurationMinutes() {
        let cases: [(Int?, TimeInterval?)] = [
            (300, fiveHour),
            (10_080, sevenDay),
            (90, 5_400),
            (nil, nil),
            (0, nil),
            (-60, nil),
        ]
        for (mins, expected) in cases {
            XCTAssertEqual(
                CodexRateLimitWindow(usedPercent: 0, windowDurationMins: mins, resetsAt: nil).windowSpan,
                expected, "windowDurationMins=\(String(describing: mins))")
        }
    }

    /// window 필드가 비어도 bucketId 로 판정한다 — is5HourWindow/isWeeklyWindow 와 같은 규칙이어야
    /// 이름(행 제목)과 마커가 서로 다른 창을 가리키지 않는다.
    func testWindowSpanFromAntigravityBucket() {
        func bucket(_ window: String?, _ id: String) -> AntigravityQuotaBucket {
            AntigravityQuotaBucket(bucketId: id, displayName: "x", window: window, remainingFraction: 1)
        }
        XCTAssertEqual(bucket("5h", "gemini").windowSpan, fiveHour)
        XCTAssertEqual(bucket("weekly", "gemini").windowSpan, sevenDay)
        XCTAssertEqual(bucket(nil, "gemini-5h").windowSpan, fiveHour)
        XCTAssertEqual(bucket(nil, "gemini-weekly").windowSpan, sevenDay)
        XCTAssertNil(bucket(nil, "gemini").windowSpan)
        XCTAssertNil(bucket("monthly", "gemini").windowSpan)
    }

    func testWindowSpanFromOAuthLimitEntryKind() {
        func entry(_ kind: String?) -> OAuthLimitEntry {
            OAuthLimitEntry(kind: kind, group: nil, percent: nil, severity: nil,
                            resetsAt: nil, scope: nil, isActive: nil)
        }
        XCTAssertEqual(entry("session").windowSpan, fiveHour)
        XCTAssertEqual(entry("weekly_all").windowSpan, sevenDay)
        XCTAssertEqual(entry("weekly_scoped").windowSpan, sevenDay)
        XCTAssertNil(entry(nil).windowSpan)
        XCTAssertNil(entry("monthly").windowSpan)
    }

    // MARK: 경과율

    func testPaceFractionTracksElapsedPortionOfWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func pace(resetInSeconds: TimeInterval) -> Double? {
            UsageStore.paceFraction(
                resetsAt: now.addingTimeInterval(resetInSeconds), span: fiveHour, now: now)
        }
        XCTAssertEqual(try XCTUnwrap(pace(resetInSeconds: fiveHour)), 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(pace(resetInSeconds: fiveHour / 2)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(pace(resetInSeconds: fiveHour / 4)), 0.75, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(pace(resetInSeconds: 0)), 1, accuracy: 0.0001)
    }

    /// 5시간 창은 첫 요청 때 시작하므로 유휴 상태의 낡은 resets_at 이 그대로 남을 수 있다.
    /// 그 값을 clamp 해 그리면 "지금 막 시작/끝났다"는 거짓말이 되므로 마커를 아예 숨긴다.
    func testPaceFractionRejectsWindowsOutsideItsOwnSpan() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func pace(resetInSeconds: TimeInterval, span: TimeInterval = 5 * 3600) -> Double? {
            UsageStore.paceFraction(
                resetsAt: now.addingTimeInterval(resetInSeconds), span: span, now: now)
        }
        XCTAssertNil(pace(resetInSeconds: -1), "이미 지난 리셋 시각")
        XCTAssertNil(pace(resetInSeconds: fiveHour + 1), "창 길이보다 먼 리셋 시각")
        XCTAssertNil(pace(resetInSeconds: fiveHour / 2, span: 0), "길이 0")
        XCTAssertNil(pace(resetInSeconds: fiveHour / 2, span: -fiveHour), "음수 길이")
    }

    // MARK: 표시 모드 반전 — 채움과 마커가 같은 변환을 거쳐야 한다

    func testMarkerFractionMirrorsRemainingDisplayMode() throws {
        XCTAssertEqual(try XCTUnwrap(LimitProgressBar.markerFraction(pace: 0.25, mode: .used)),
                       0.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(LimitProgressBar.markerFraction(pace: 0.25, mode: .remaining)),
                       0.75, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(LimitProgressBar.markerFraction(pace: 1, mode: .remaining)),
                       0, accuracy: 0.0001)
        XCTAssertNil(LimitProgressBar.markerFraction(pace: nil, mode: .used))
        XCTAssertNil(LimitProgressBar.markerFraction(pace: nil, mode: .remaining))
    }
}
