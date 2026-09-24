import XCTest
@testable import PokeTokenBar

/// Every `ScrollView` lives inside the fixed-width popover. With "Show scroll bars: Always" (or a mouse
/// under "Automatically"), macOS uses legacy scrollers and SwiftUI reserves a ~16pt gutter for them, so
/// scrolling screens render narrower than the header/footer. `.hidden` does not remove that gutter;
/// `.never` (or the equivalent `showsIndicators: false`) does.
final class ScrollIndicatorTests: XCTestCase {
    func testEveryScrollViewOptsOutOfTheLegacyScrollerGutter() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
            .appendingPathComponent("Sources/PokeTokenBar")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: sources, includingPropertiesForKeys: nil))
        var scrollViewCount = 0
        var offenders: [String] = []

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for site in Self.scrollViewSites(in: source) {
                scrollViewCount += 1
                if !site.hidesIndicators { offenders.append("\(url.lastPathComponent):\(site.line)") }
            }
        }

        // Guards against a vacuous pass if the scan stops finding anything (path or parser drift).
        XCTAssertGreaterThan(scrollViewCount, 0)
        XCTAssertTrue(offenders.isEmpty, """
            ScrollViews inside the popover must apply .scrollIndicators(.never) (or showsIndicators: false);
            otherwise legacy scrollers reserve a gutter that narrows the content.
            Missing at: \(offenders.joined(separator: ", "))
            """)
    }

    func testScannerReadsTheModifierChainAfterTheClosingBrace() {
        let source = """
            ScrollView {
                VStack { Text("a") }
            }
            // comment between modifiers
            .scrollIndicators(.never)
            .frame(height: 520)

            ScrollView(.horizontal) {
                HStack { }
            }
            .frame(height: 20)
            .onAppear { let _ = ".scrollIndicators(.never)" }

            ScrollView(.horizontal, showsIndicators: false) { HStack { } }

            ScrollView { Text("x") }.scrollIndicators(.hidden)

            ScrollViewReader { proxy in }
            """
        let sites = Self.scrollViewSites(in: source)
        XCTAssertEqual(sites.map(\.line), [1, 8, 14, 16])
        XCTAssertEqual(sites.map(\.hidesIndicators), [true, false, true, false])
    }

    // MARK: - Scanner

    struct Site: Equatable {
        let line: Int
        let hidesIndicators: Bool
    }

    /// Finds each `ScrollView` initializer and reports whether its own arguments or the modifier chain
    /// directly after its trailing closure hide the indicators. Comments are blanked first so braces or
    /// modifier names inside them don't count.
    static func scrollViewSites(in source: String) -> [Site] {
        let chars = Array(blankingComments(source))
        let keyword = Array("ScrollView")
        var sites: [Site] = []
        var i = 0
        while i + keyword.count <= chars.count {
            let isMatch = Array(chars[i..<i + keyword.count]) == keyword
                && (i == 0 || !isIdentifier(chars[i - 1]))
                && (i + keyword.count == chars.count || !isIdentifier(chars[i + keyword.count]))
            guard isMatch else { i += 1; continue }
            let line = chars[..<i].filter { $0 == "\n" }.count + 1
            var j = skipWhitespace(chars, i + keyword.count)
            var hides = false
            if j < chars.count, chars[j] == "(" {
                let end = matching(chars, j)
                hides = String(chars[j...end]).replacingOccurrences(of: " ", with: "")
                    .contains("showsIndicators:false")
                j = skipWhitespace(chars, end + 1)
            }
            // A bare `ScrollView` reference (e.g. in a type position) has no trailing closure — skip it.
            guard j < chars.count, chars[j] == "{" else { i += keyword.count; continue }
            j = matching(chars, j) + 1
            // Walk `.modifier(args) { closure }` links until something else starts.
            while true {
                let dot = skipWhitespace(chars, j)
                guard dot < chars.count, chars[dot] == "." else { break }
                var k = dot + 1
                while k < chars.count, isIdentifier(chars[k]) { k += 1 }
                let name = String(chars[dot + 1..<k])
                var args = ""
                k = skipWhitespace(chars, k)
                if k < chars.count, chars[k] == "(" {
                    let end = matching(chars, k)
                    args = String(chars[k...end])
                    k = end + 1
                }
                let brace = skipWhitespace(chars, k)
                if brace < chars.count, chars[brace] == "{" { k = matching(chars, brace) + 1 }
                if name == "scrollIndicators", args.contains(".never") { hides = true }
                j = k
            }
            sites.append(Site(line: line, hidesIndicators: hides))
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

    /// Index of the bracket closing the one at `open`, ignoring brackets inside string literals.
    private static func matching(_ chars: [Character], _ open: Int) -> Int {
        let (o, c): (Character, Character) = chars[open] == "(" ? ("(", ")") : ("{", "}")
        var depth = 0
        var inString = false
        var i = open
        while i < chars.count {
            let ch = chars[i]
            if inString {
                if ch == "\\" { i += 2; continue }
                if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
            } else if ch == o {
                depth += 1
            } else if ch == c {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return chars.count - 1
    }

    /// Replaces `//` and `/* */` comments with spaces, keeping newlines so line numbers stay valid.
    private static func blankingComments(_ source: String) -> String {
        let chars = Array(source)
        var out = chars
        var i = 0
        var inString = false
        while i < chars.count {
            let ch = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if inString {
                if ch == "\\" { i += 2; continue }
                if ch == "\"" { inString = false }
                i += 1
            } else if ch == "\"" {
                inString = true
                i += 1
            } else if ch == "/", next == "/" {
                while i < chars.count, chars[i] != "\n" { out[i] = " "; i += 1 }
            } else if ch == "/", next == "*" {
                while i < chars.count, !(chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "/") {
                    if chars[i] != "\n" { out[i] = " " }
                    i += 1
                }
                if i < chars.count { out[i] = " "; out[i + 1] = " "; i += 2 }
            } else {
                i += 1
            }
        }
        return String(out)
    }
}
