import XCTest
@testable import PokeTokenBar

final class SwiftUIIsolationTests: XCTestCase {
    func testEverySwiftUIViewAndAppIsMainActorIsolated() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
            .appendingPathComponent("Sources/PokeTokenBar")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            for index in lines.indices {
                let declaration = lines[index].trimmingCharacters(in: .whitespaces)
                let isStruct = declaration.hasPrefix("struct ")
                    || declaration.hasPrefix("private struct ")
                guard isStruct,
                      declaration.contains(": View") || declaration.contains(": App") else { continue }

                let previous = lines[..<index].reversed()
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty }
                if previous != "@MainActor" {
                    offenders.append("\(url.lastPathComponent):\(index + 1)")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            Swift 6.3 treats SwiftUI helper properties/closures as nonisolated unless the View/App boundary is explicit.
            Add @MainActor immediately above: \(offenders.joined(separator: ", "))
            """)
    }

    /// `@MainActor` XCTestCase 의 **동기** `setUp`/`tearDown` 은 릴리스 Swift 에서 nonisolated 로
    /// 취급돼, main-actor 프로퍼티를 만지면 컴파일 에러가 된다. 그래서 그런 클래스의 가변 저장
    /// 프로퍼티는 `nonisolated(unsafe)` 여야 한다(XCTest 는 인스턴스별 직렬 실행이라 안전).
    ///
    /// 이 스캔이 필요한 이유는 **규칙이 이미 있었는데 못 막았기 때문**이다. 같은 내용이
    /// `UsageStoreTests` 의 주석으로만 남아 있었고, 그 뒤에 추가된 `ICloudSaveMirrorTests` 가
    /// 그대로 어겼다 — 로컬 툴체인(6.3+)은 통과시키고 **CI(6.1.2)에서만** 빨개져서 푸시 전엔
    /// 아무 신호가 없었다. 산문 규칙은 그 파일을 읽는 사람에게만 작동한다.
    func testMainActorTestClassesKeepMutableFixturesNonisolated() throws {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: testsDir, includingPropertiesForKeys: nil))
        var offenders: [String] = []

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            for index in lines.indices where lines[index] == "@MainActor" {
                // `@MainActor` 바로 아래의 XCTestCase 선언만 대상.
                guard let declIndex = lines[(index + 1)...].indices.first(where: { !lines[$0].isEmpty }),
                      lines[declIndex].contains("class"),
                      lines[declIndex].contains(": XCTestCase") else { continue }

                // 클래스 본문 = 다음 최상위 선언 전까지.
                let bodyEnd = lines[(declIndex + 1)...].indices.first {
                    lines[$0] == "@MainActor" || lines[$0].hasPrefix("final class")
                        || lines[$0].hasPrefix("private final class")
                } ?? lines.endIndex

                // 동기 setUp/tearDown 이 없으면 이 부류의 문제가 없다 — async 오버라이드는 격리를 물려받는다.
                let hasSyncFixtureHook = lines[(declIndex + 1)..<bodyEnd].contains {
                    ($0.hasPrefix("override func setUp(") || $0.hasPrefix("override func tearDown("))
                        && !$0.contains("async")
                }
                guard hasSyncFixtureHook else { continue }

                for lineIndex in (declIndex + 1)..<bodyEnd {
                    let line = lines[lineIndex]
                    // 가변 저장 프로퍼티만 — `let` 상수와 계산 프로퍼티·함수는 대상이 아니다.
                    guard line.contains("var "), line.hasSuffix("!"),
                          !line.contains("nonisolated(unsafe)"), !line.contains("func ") else { continue }
                    offenders.append("\(url.lastPathComponent):\(lineIndex + 1)  \(line)")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            @MainActor XCTestCase 의 동기 setUp/tearDown 은 nonisolated 라 이 프로퍼티들을 못 만진다
            (로컬은 통과, CI 6.1.2 에서 컴파일 실패). `nonisolated(unsafe) private var ...` 로 선언하세요:
            \(offenders.joined(separator: "\n            "))
            """)
    }
}
