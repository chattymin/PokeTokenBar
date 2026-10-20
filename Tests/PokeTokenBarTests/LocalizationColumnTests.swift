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

    /// A Korean character typed into the Japanese column (`は가네` for `はがね`) compiles and passes every
    /// placeholder check. Only the Korean column may hold Hangul, and no Latin-script column holds kana.
    func testHangulAndKanaStayInTheirColumns() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var calls = 0
        var offenders: [String] = []
        for file in Self.files {
            let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for columns in Self.translationCalls(in: source) {
                calls += 1
                for (index, text) in columns.enumerated() where index > 0 {
                    if text.unicodeScalars.contains(where: Self.isHangul) {
                        offenders.append("column \(index) contains Hangul: \(text)")
                    }
                    if index != 2, text.unicodeScalars.contains(where: Self.isKana) {
                        offenders.append("column \(index) contains kana: \(text)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(calls, 300, "the scanner must actually find the t(...) calls")
        XCTAssertEqual(offenders, [])
    }

    private static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        (0xAC00...0xD7A3).contains(scalar.value) || (0x1100...0x11FF).contains(scalar.value)
            || (0x3130...0x318F).contains(scalar.value)
    }

    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040...0x309F).contains(scalar.value) || (0x30A0...0x30FA).contains(scalar.value)
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

    func testScannerReadsMultilineLiterals() {
        let source = """
        var c: String {
            t(\"\"\"
              가
              \"\"\", \"\"\"
              c
              \"\"\", "う", "es", "fr", "pt", "de")
        }
        """
        let calls = Self.translationCalls(in: source)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?[0].trimmingCharacters(in: .whitespacesAndNewlines), "가")
        XCTAssertEqual(calls.first?[1].trimmingCharacters(in: .whitespacesAndNewlines), "c")
        XCTAssertEqual(calls.first?[2], "う")
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
                if chars[j] == "\"", j + 2 < chars.count, chars[j + 1] == "\"", chars[j + 2] == "\"" {
                    let (literal, end) = readMultilineLiteral(chars, from: j + 3)
                    literals.append(literal)
                    j = end + 3
                } else if chars[j] == "\"" {
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

    /// A `"""` literal ends at the next `"""`; none of the translations nests one in an interpolation.
    private static func readMultilineLiteral(_ chars: [Character], from start: Int) -> (String, Int) {
        var j = start
        while j + 2 < chars.count {
            if chars[j] == "\"" && chars[j + 1] == "\"" && chars[j + 2] == "\"" {
                return (String(chars[start..<j]), j)
            }
            j += 1
        }
        return (String(chars[start...]), chars.count)
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
