import XCTest
@testable import PokeTokenBar

/// `/stats` 인증 계약. 서버는 `*:7845`(모든 인터페이스)에 바인딩되고 Bonjour 로 광고까지 하므로,
/// 같은 네트워크의 누구나 도달할 수 있다는 전제에서 판정만이 유일한 방어선이다.
final class PhoneRequestRouterTests: XCTestCase {
    private let code = "ABCD2345"

    func testStatsRequiresThePairingCode() {
        XCTAssertEqual(
            route(authorization: nil),
            .unauthorized,
            "인증 헤더 없는 요청이 페이로드를 받으면 LAN 의 누구나 사용량을 읽는다")
    }

    func testStatsAcceptsTheCorrectCode() {
        XCTAssertEqual(route(authorization: "Bearer \(code)"), .payload)
    }

    func testStatsRejectsAWrongCode() {
        XCTAssertEqual(route(authorization: "Bearer WRONG123"), .unauthorized)
    }

    /// 길이만 같고 내용이 다른 코드 — 상수시간 비교가 길이 검사만 하고 끝나지 않는지.
    func testStatsRejectsASameLengthCode() {
        XCTAssertEqual(code.count, 8)
        XCTAssertEqual(route(authorization: "Bearer ZZZZ9999"), .unauthorized)
    }

    func testStatsRejectsANonBearerScheme() {
        XCTAssertEqual(route(authorization: "Basic \(code)"), .unauthorized)
        XCTAssertEqual(route(authorization: code), .unauthorized)
    }

    /// 코드가 아직 없을 때(생성 실패·저장소 초기화) 빈 문자열끼리 맞아떨어져 인증이 열리는 것이
    /// 이 부류의 전형적인 구멍이다. 빈 코드는 무엇으로도 통과시키지 않는다.
    func testEmptyPairingCodeRejectsEverything() {
        XCTAssertEqual(
            PhoneRequestRouter.route(requestLine: "GET /stats HTTP/1.1",
                                     authorization: "Bearer ",
                                     pairingCode: "",
                                     hasPayload: true),
            .unauthorized)
        XCTAssertEqual(
            PhoneRequestRouter.route(requestLine: "GET /stats HTTP/1.1",
                                     authorization: nil,
                                     pairingCode: "",
                                     hasPayload: true),
            .unauthorized)
    }

    /// 인증을 통과해도 아직 페이로드가 없으면 503 — 인증 분기가 503 을 삼키지 않는지.
    func testAuthorizedButNoPayloadYet() {
        XCTAssertEqual(
            PhoneRequestRouter.route(requestLine: "GET /stats HTTP/1.1",
                                     authorization: "Bearer \(code)",
                                     pairingCode: code,
                                     hasPayload: false),
            .noPayloadYet)
    }

    /// `/health` 는 개인 데이터가 없고, 폰이 "코드가 틀림"과 "Mac 이 안 보임"을 구분해야 해서 열어 둔다.
    func testHealthStaysOpen() {
        XCTAssertEqual(
            PhoneRequestRouter.route(requestLine: "GET /health HTTP/1.1",
                                     authorization: nil,
                                     pairingCode: code,
                                     hasPayload: true),
            .health)
    }

    func testUnknownPathAndMalformedRequestLine() {
        XCTAssertEqual(route(requestLine: "GET /secrets HTTP/1.1", authorization: "Bearer \(code)"), .notFound)
        XCTAssertEqual(route(requestLine: "GARBAGE", authorization: "Bearer \(code)"), .badRequest)
    }

    // MARK: Authorization 헤더 파싱

    func testAuthorizationHeaderIsCaseInsensitiveAndTrimmed() {
        let request = "GET /stats HTTP/1.1\r\nHost: mac.local\r\nauthorization:  Bearer \(code)  \r\n\r\n"
        XCTAssertEqual(PhoneRequestRouter.authorizationHeader(in: request), "Bearer \(code)")
    }

    func testAuthorizationHeaderIgnoresTheBody() {
        // 본문에 Authorization 처럼 보이는 줄이 있어도 헤더로 오인하지 않는다.
        let request = "GET /stats HTTP/1.1\r\nHost: mac.local\r\n\r\nAuthorization: Bearer \(code)"
        XCTAssertNil(PhoneRequestRouter.authorizationHeader(in: request))
    }

    // MARK: 코드 생성

    func testGeneratedCodesAreDistinctAndUseTheSafeAlphabet() {
        let codes = (0..<200).map { _ in PhonePairingCode.generate() }
        XCTAssertEqual(Set(codes).count, codes.count, "생성 코드가 겹치면 엔트로피가 없는 것이다")
        let allowed = Set(PhonePairingCode.alphabet)
        for generated in codes {
            XCTAssertEqual(generated.count, PhonePairingCode.length)
            XCTAssertTrue(generated.allSatisfy { allowed.contains($0) })
            // 손으로 옮겨 적는 코드라 혼동 문자는 알파벳에서 빠져 있어야 한다.
            XCTAssertFalse(generated.contains(where: { "ILOU".contains($0) }))
        }
    }

    // MARK: helpers

    private func route(requestLine: String = "GET /stats HTTP/1.1",
                       authorization: String?) -> PhoneRequestRouter.Outcome
    {
        PhoneRequestRouter.route(requestLine: requestLine,
                                 authorization: authorization,
                                 pairingCode: code,
                                 hasPayload: true)
    }
}
