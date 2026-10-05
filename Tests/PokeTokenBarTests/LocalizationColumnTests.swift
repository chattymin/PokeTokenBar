import XCTest

/// `L.t(ko, en, ja, es, fr, pt, de)` is positional, so a string pasted into the neighbouring
/// column compiles and passes the placeholder checks. Spanish and Portuguese are the easiest pair
/// to mix up; scan every call in the source for markers that only one of them uses.
final class LocalizationColumnTests: XCTestCase {
    private static let files = [
        "Sources/PokeTokenBar/Core/Localization.swift",
        "Sources/PokeTokenBar/Core/LocalizationErrors.swift",
    ]
    private static let spanishOnly = ["ción", "¿", "¡"]
    private static let portugueseOnly = ["ção", "ções", "ões", "ã"]

    func testSpanishAndPortugueseColumnsAreNotSwapped() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var calls = 0
        var offenders: [String] = []
        for file in Self.files {
            let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for columns in Self.translationCalls(in: source) {
                calls += 1
                let es = columns[3], pt = columns[5]
                for marker in Self.spanishOnly where pt.contains(marker) {
                    offenders.append("pt contains Spanish \"\(marker)\": \(pt)")
                }
                for marker in Self.portugueseOnly where es.contains(marker) {
                    offenders.append("es contains Portuguese \"\(marker)\": \(es)")
                }
            }
        }
        XCTAssertGreaterThan(calls, 300, "the scanner must actually find the t(...) calls")
        XCTAssertEqual(offenders, [])
    }

    func testScannerReadsInterpolatedAndMultilineCalls() {
        let source = """
        var a: String { t("가", "a", "あ", "es \\(x) ción", "fr", "pt \\(f("q")) ção", "de") }
        func b() -> String {
            t("나",
              "b \\"quoted\\"", "い", "es", "fr", "pt", "de")
        }
        """
        let calls = Self.translationCalls(in: source)
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.first?[3], "es \\(x) ción")
        XCTAssertEqual(calls.first?[5], "pt \\(f(\"q\")) ção")
        XCTAssertEqual(calls.last?[1], "b \\\"quoted\\\"")
    }

    /// The seven string literals of every `t(` call, read with a small literal scanner that
    /// understands `\"` escapes and quotes nested inside `\( … )` interpolations.
    static func translationCalls(in source: String) -> [[String]] {
        let chars = Array(source)
        var calls: [[String]] = []
        var i = 0
        while i + 1 < chars.count {
            let startsCall = chars[i] == "t" && chars[i + 1] == "("
                && (i == 0 || !(chars[i - 1].isLetter || chars[i - 1].isNumber || chars[i - 1] == "_"))
            guard startsCall else { i += 1; continue }
            var j = i + 2
            var literals: [String] = []
            while literals.count < 7, j < chars.count {
                if chars[j] == "\"" {
                    let (literal, end) = readLiteral(chars, from: j + 1)
                    literals.append(literal)
                    j = end + 1
                } else if chars[j] == "," || chars[j].isWhitespace {
                    j += 1
                } else {
                    break
                }
            }
            if literals.count == 7 { calls.append(literals) }
            i = max(i + 2, j)
        }
        return calls
    }

    private static func readLiteral(_ chars: [Character], from start: Int) -> (String, Int) {
        var j = start
        var depth = 0
        var inNested = false
        while j < chars.count {
            let c = chars[j]
            if c == "\\" && j + 1 < chars.count {
                if chars[j + 1] == "(" && !inNested { depth += 1 }
                j += 2
                continue
            }
            if depth > 0 {
                if c == "\"" { inNested.toggle() }
                else if !inNested && c == "(" { depth += 1 }
                else if !inNested && c == ")" { depth -= 1 }
            } else if c == "\"" {
                return (String(chars[start..<j]), j)
            }
            j += 1
        }
        return (String(chars[start...]), chars.count)
    }
}
