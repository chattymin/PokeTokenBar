import XCTest
@testable import PokeTokenBar

/// 이 요약의 계약은 두 가지다: 파서를 쓸 만큼 **구조가 보일 것**, 그리고 **값이 새지 않을 것**.
/// 두 번째가 더 중요하다 — 모르는 응답을 로그에 남기는 도구라서.
final class JSONKeyShapeTests: XCTestCase {
    private func shape(_ json: String) -> String {
        JSONKeyShape.describe(Data(json.utf8))
    }

    func testDescribesNestedKeysWithTypesButNoValues() {
        let result = shape("""
        {"currentTier":{"id":"free-tier","name":"Free"},"projectId":"secret-project-42"}
        """)
        XCTAssertEqual(result, "{currentTier{id:str,name:str},projectId:str}")
        XCTAssertFalse(result.contains("secret-project-42"), "값이 로그로 샜다")
        XCTAssertFalse(result.contains("free-tier"), "값이 로그로 샜다")
    }

    /// 숫자야말로 조심해야 한다 — 사용량·잔여량이 그대로 값이라, 타입만 남겨야 한다.
    func testNumbersAreReducedToTheirType() {
        let result = shape("""
        {"used":17,"limit":100,"resetsAt":"2026-01-01T00:00:00Z"}
        """)
        XCTAssertEqual(result, "{limit:num,resetsAt:str,used:num}")
        XCTAssertFalse(result.contains("17"))
        XCTAssertFalse(result.contains("100"))
    }

    /// 배열은 개수를 남긴다 — 버킷이 몇 개인지가 파서 설계에 필요한 '형태'이기 때문.
    func testArraysReportCountAndElementShape() {
        XCTAssertEqual(shape("""
        {"buckets":[{"id":"a","pct":10},{"id":"b","pct":20}]}
        """), "{buckets[2]{…}}")
        XCTAssertEqual(shape(#"{"buckets":[]}"#), "{buckets[0]}")
    }

    /// 깊이 제한이 있어야 응답이 깊어도 로그가 폭발하지 않는다.
    func testDepthIsBounded() {
        XCTAssertEqual(shape(#"{"a":{"b":{"c":{"d":1}}}}"#), "{a{b{…}}}")
    }

    func testNonJSONIsReportedRatherThanEchoed() {
        let result = JSONKeyShape.describe(Data("<html>you are not authorized</html>".utf8))
        XCTAssertEqual(result, "<JSON 아님>")
        XCTAssertFalse(result.contains("authorized"), "본문이 그대로 로그에 남았다")
    }

    func testNullAndBoolKeepTheirTypes() {
        XCTAssertEqual(shape(#"{"a":null,"b":true}"#), "{a:null,b:bool}")
    }
}
