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
}
