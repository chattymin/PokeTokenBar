import XCTest
import PokeTokenBarShared

/// Mac → iPhone 페이로드(PhoneLimitStatus) 스키마 회귀 — 새 필드는 구 버전과 양방향 호환돼야 한다.
/// TokenFormatter 가 app target 과 shared package 양쪽에 있어 import 를 섞으면 모호해지므로
/// shared 타입만 쓰는 테스트를 별도 파일로 둔다.
final class PhonePayloadCodableTests: XCTestCase {
    /// 구 Mac 이 보낸 페이로드(OpenCode Go 필드 없음)도 폰 코드에서 깨지지 않는다 — nil 로 디코드.
    func testLimitStatusDecodesLegacyPayloadWithoutOpenCodeGo() throws {
        let legacy = Data("""
        {"claude5h":{"label":"5h Session","utilization":42,"resetsAt":null},
         "planDisplay":null}
        """.utf8)
        let status = try JSONDecoder().decode(PhoneLimitStatus.self, from: legacy)
        XCTAssertEqual(status.claude5h?.label, "5h Session")
        XCTAssertNil(status.opencodeGo5h)
        XCTAssertNil(status.opencodeGoWeekly)
        XCTAssertNil(status.opencodeGoMonthly)
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
