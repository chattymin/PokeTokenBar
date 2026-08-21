import XCTest
import PokeTokenBarShared

/// Mac → iPhone 페이로드(PhoneLimitStatus) 스키마 회귀 — 새 필드는 구 버전과 양방향 호환돼야 한다.
/// TokenFormatter 가 app target 과 shared package 양쪽에 있어 import 를 섞으면 모호해지므로
/// shared 타입만 쓰는 테스트를 별도 파일로 둔다.
final class PhonePayloadCodableTests: XCTestCase {
    /// 구 Mac 이 보낸 페이로드(OpenCode Go·claudeScoped 필드 없음)도 폰 코드에서 깨지지 않는다 — nil 로 디코드.
    func testLimitStatusDecodesLegacyPayloadWithoutOpenCodeGo() throws {
        let legacy = Data("""
        {"claude5h":{"label":"5h Session","utilization":42,"resetsAt":null},
         "planDisplay":null}
        """.utf8)
        let status = try JSONDecoder().decode(PhoneLimitStatus.self, from: legacy)
        XCTAssertEqual(status.claude5h?.label, "5h Session")
        XCTAssertNil(status.claudeScoped)
        XCTAssertNil(status.opencodeGo5h)
        XCTAssertNil(status.opencodeGoWeekly)
        XCTAssertNil(status.opencodeGoMonthly)
    }

    /// 모델별(scoped) 주간 창 왕복 + orderedWindows 순서/포함 검증.
    func testLimitStatusRoundTripsScopedAndOrders() throws {
        let status = PhoneLimitStatus(
            claude5h: PhoneLimitWindow(label: "Claude 5h", utilization: 2, resetsAt: nil),
            claudeWeekly: PhoneLimitWindow(label: "Claude Weekly", utilization: 13, resetsAt: nil),
            claudeOpusWeekly: nil, claudeSonnetWeekly: nil,
            claudeScoped: [PhoneLimitWindow(label: "Claude Weekly Fable", utilization: 41, resetsAt: nil)],
            codexPrimary: PhoneLimitWindow(label: "Codex 5h", utilization: 61, resetsAt: nil),
            codexSecondary: nil,
            opencodeGo5h: PhoneLimitWindow(label: "Go 5h", utilization: 92, resetsAt: nil),
            opencodeGoWeekly: nil, opencodeGoMonthly: nil,
            planDisplay: "Max 20x")
        let decoded = try JSONDecoder().decode(
            PhoneLimitStatus.self, from: JSONEncoder().encode(status))
        XCTAssertEqual(decoded.claudeScoped?.map(\.label), ["Claude Weekly Fable"])
        XCTAssertEqual(decoded.orderedWindows.map(\.label),
                       ["Claude 5h", "Claude Weekly", "Claude Weekly Fable", "Codex 5h", "Go 5h"])
    }

    /// 프로바이더 그룹(위젯 파이+퍼센트 행용) — 제목·순서·빈 그룹 제외를 고정한다.
    func testLimitGroupsByProviderOmitEmpty() {
        let status = PhoneLimitStatus(
            claude5h: PhoneLimitWindow(label: "Claude 5h", utilization: 2, resetsAt: nil),
            claudeWeekly: PhoneLimitWindow(label: "Claude Weekly", utilization: 13, resetsAt: nil),
            claudeOpusWeekly: nil, claudeSonnetWeekly: nil,
            claudeScoped: [PhoneLimitWindow(label: "Claude Weekly Fable", utilization: 41, resetsAt: nil)],
            codexPrimary: nil, codexSecondary: nil,   // Codex 미사용 → 그룹 없음
            opencodeGo5h: PhoneLimitWindow(label: "Go 5h", utilization: 92, resetsAt: nil),
            opencodeGoWeekly: PhoneLimitWindow(label: "Go Weekly", utilization: 74, resetsAt: nil),
            opencodeGoMonthly: PhoneLimitWindow(label: "Go Monthly", utilization: 38, resetsAt: nil),
            planDisplay: nil)

        let groups = status.limitGroups
        XCTAssertEqual(groups.map(\.title), ["Claude", "Go"], "창 없는 프로바이더는 그룹 생성 안 함")
        XCTAssertEqual(groups[0].windows.count, 3, "Claude = 5h+주간+scoped(Fable)")
        XCTAssertEqual(groups[1].windows.map(\.label), ["Go 5h", "Go Weekly", "Go Monthly"])
        // 그룹 창 순서는 orderedWindows 와 동일 소스여야 한다(두 순서가 어긋나면 위젯/앱 불일치).
        XCTAssertEqual(groups.flatMap(\.windows).map(\.label), status.orderedWindows.map(\.label))
    }

    /// 새 필드 왕복 — Go 세 창이 인코딩·디코딩을 그대로 통과한다.
    func testLimitStatusRoundTripsOpenCodeGoWindows() throws {
        let status = PhoneLimitStatus(
            claude5h: nil, claudeWeekly: nil, claudeOpusWeekly: nil, claudeSonnetWeekly: nil,
            codexPrimary: nil, codexSecondary: nil,
            opencodeGo5h: PhoneLimitWindow(label: "Go 5h", utilization: 2, resetsAt: Date(timeIntervalSince1970: 1_785_000_000)),
            opencodeGoWeekly: PhoneLimitWindow(label: "Go Weekly", utilization: 41, resetsAt: nil),
            opencodeGoMonthly: PhoneLimitWindow(label: "Go Monthly", utilization: 20, resetsAt: nil),
            planDisplay: nil)
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(PhoneLimitStatus.self, from: data)
        XCTAssertEqual(decoded.opencodeGo5h?.label, "Go 5h")
        XCTAssertEqual(decoded.opencodeGo5h?.utilization, 2)
        XCTAssertEqual(decoded.opencodeGoWeekly?.label, "Go Weekly")
        XCTAssertEqual(decoded.opencodeGoMonthly?.utilization, 20)
    }
}
