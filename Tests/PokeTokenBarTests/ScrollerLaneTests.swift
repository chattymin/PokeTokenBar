import XCTest
@testable import PokeTokenBar

/// The popover's vertical scroll views keep macOS's thin overlay scroller, which floats over the right
/// edge of the content while scrolling. Each one must pad its content with `.reservesScrollerLane()`
/// so the scroller never sits on right-aligned numbers, prices, or buttons.
final class ScrollerLaneTests: XCTestCase {
    /// Files whose vertical ScrollView already clears the scroller with its own padding.
    /// SettingsView pads its content 16pt on every side.
    private static let exempt: Set<String> = ["SettingsView.swift"]

    func testEveryPopoverVerticalScrollViewReservesTheScrollerLane() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
            .appendingPathComponent("Sources/PokeTokenBar/UI")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: ui, includingPropertiesForKeys: nil))
        var checked = 0
        var offenders: [String] = []

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard !Self.exempt.contains(url.lastPathComponent) else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            for site in Self.verticalScrollViews(in: source) {
                checked += 1
                if !site.reservesLane { offenders.append("\(url.lastPathComponent):\(site.line)") }
            }
        }

        // Home, Shop, Bag, catch log, Pokémon detail — guards against a vacuous pass if the scan breaks.
        XCTAssertGreaterThanOrEqual(checked, 5)
        XCTAssertTrue(offenders.isEmpty, """
            Vertical ScrollViews in the popover must apply .reservesScrollerLane() to their content,
            or the overlay scroller covers right-aligned content. Missing at: \(offenders.joined(separator: ", "))
            """)
    }

    func testScannerFindsTheLaneOnlyInsideTheScrollViewsOwnContent() {
        let source = """
            ScrollView {
                VStack { Text("a") }
                    // comment
                    .reservesScrollerLane()
            }
            .frame(height: 520)

            ScrollView {
                VStack { Text("b") }
            }
            .reservesScrollerLane()

            ScrollView(.horizontal) { HStack { } }

            ScrollView { Text("\\(x) .reservesScrollerLane()") }

            ScrollView { Text(\"\"\"
                .reservesScrollerLane()
                \"\"\") }

            ScrollViewReader { proxy in }
            """
        let sites = Self.verticalScrollViews(in: source)
        XCTAssertEqual(sites.map(\.line), [1, 8, 15, 17])
        // Padding outside the ScrollView pads the scroller too, so it doesn't count; neither does a string.
        XCTAssertEqual(sites.map(\.reservesLane), [true, false, false, false])
    }

    // MARK: - Scanner

    struct Site: Equatable {
        let line: Int
        let reservesLane: Bool
    }

    /// Finds each vertical `ScrollView` and reports whether `.reservesScrollerLane()` is applied inside its
    /// trailing closure. Comments and string literals are blanked first so they can't satisfy the check.
    static func verticalScrollViews(in source: String) -> [Site] {
        let chars = Array(blankingCommentsAndStrings(source))
        let keyword = Array("ScrollView")
        var sites: [Site] = []
        var i = 0
        while i + keyword.count <= chars.count {
            let isMatch = Array(chars[i..<i + keyword.count]) == keyword
                && (i == 0 || !isIdentifier(chars[i - 1]))
                && (i + keyword.count == chars.count || !isIdentifier(chars[i + keyword.count]))
            guard isMatch else { i += 1; continue }
            var j = skipWhitespace(chars, i + keyword.count)
            var horizontal = false
            if j < chars.count, chars[j] == "(" {
                let end = matching(chars, j)
                horizontal = String(chars[j...end]).contains(".horizontal")
                j = skipWhitespace(chars, end + 1)
            }
            guard j < chars.count, chars[j] == "{" else { i += keyword.count; continue }
            let close = matching(chars, j)
            if !horizontal {
                let line = chars[..<i].filter { $0 == "\n" }.count + 1
                let body = String(chars[j...close])
                sites.append(Site(line: line, reservesLane: body.contains(".reservesScrollerLane()")))
            }
            i += keyword.count
        }
        return sites
    }

    private static func isIdentifier(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    private static func skipWhitespace(_ chars: [Character], _ start: Int) -> Int {
        var i = start
        while i < chars.count, chars[i].isWhitespace { i += 1 }
        return i
    }

    /// Index of the bracket closing the one at `open`. Runs on blanked source, so no string handling is needed.
    private static func matching(_ chars: [Character], _ open: Int) -> Int {
        let (o, c): (Character, Character) = chars[open] == "(" ? ("(", ")") : ("{", "}")
        var depth = 0
        for i in open..<chars.count {
            if chars[i] == o { depth += 1 }
            if chars[i] == c { depth -= 1; if depth == 0 { return i } }
        }
        return chars.count - 1
    }

    /// Replaces comments and the contents of string literals with spaces, keeping newlines so line numbers
    /// stay valid. Interpolations are blanked with the string — they never hold view modifiers.
    private static func blankingCommentsAndStrings(_ source: String) -> String {
        let chars = Array(source)
        var out = chars
        var i = 0
        while i < chars.count {
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if chars[i] == "/", next == "/" {
                while i < chars.count, chars[i] != "\n" { out[i] = " "; i += 1 }
            } else if chars[i] == "/", next == "*" {
                while i < chars.count, !(chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "/") {
                    if chars[i] != "\n" { out[i] = " " }
                    i += 1
                }
                if i + 1 < chars.count { out[i] = " "; out[i + 1] = " "; i += 2 }
            } else if chars[i] == "\"", next == "\"", i + 2 < chars.count, chars[i + 2] == "\"" {
                i += 3   // multi-line literal: blank everything up to the closing triple quote
                while i + 2 < chars.count, !(chars[i] == "\"" && chars[i + 1] == "\"" && chars[i + 2] == "\"") {
                    if chars[i] != "\n" { out[i] = " " }
                    i += 1
                }
                i += 3
            } else if chars[i] == "\"" {
                i += 1
                var depth = 0   // interpolation nesting: `\(` opens, `)` at depth 1 closes
                while i < chars.count {
                    if depth == 0, chars[i] == "\"" { break }
                    if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == "(" { depth += 1; out[i] = " "; out[i + 1] = " "; i += 2; continue }
                    if depth == 0, chars[i] == "\\" { out[i] = " "; if i + 1 < chars.count { out[i + 1] = " " }; i += 2; continue }
                    if depth > 0, chars[i] == "(" { depth += 1 }
                    if depth > 0, chars[i] == ")" { depth -= 1 }
                    if chars[i] != "\n" { out[i] = " " }
                    i += 1
                }
                i += 1   // closing quote
            } else {
                i += 1
            }
        }
        return String(out)
    }
}
