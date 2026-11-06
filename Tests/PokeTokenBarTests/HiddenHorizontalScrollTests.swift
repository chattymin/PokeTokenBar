import XCTest

/// A horizontal ScrollView with hidden indicators only scrolls with a trackpad or Shift + mouse wheel.
/// A plain mouse wheel does nothing and nothing shows that more items exist, so filter chips past the
/// popover's edge could not be reached. Chip rows wrap with `WrappingHStack` instead.
final class HiddenHorizontalScrollTests: XCTestCase {
    /// Known sites, with how many each file may keep.
    /// PopoverView: `CapsuleTabBar` (provider and Claude account tabs) keeps tabs on one line on purpose.
    private static let allowed: [String: Int] = ["PopoverView.swift": 1]

    func testPopoverChipRowsDoNotHideOverflowInAHorizontalScrollView() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // PokeTokenBarTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo root
            .appendingPathComponent("Sources/PokeTokenBar/UI")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: ui, includingPropertiesForKeys: nil))
        var scanned = 0
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            scanned += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            let count = source.components(separatedBy: "ScrollView(.horizontal, showsIndicators: false)").count - 1
            if count > Self.allowed[url.lastPathComponent, default: 0] {
                offenders.append("\(url.lastPathComponent) (\(count))")
            }
        }
        XCTAssertGreaterThan(scanned, 5, "UI source scan found no files")
        XCTAssertTrue(offenders.isEmpty, """
            Horizontal ScrollViews with hidden indicators can't be scrolled with a mouse wheel. \
            Wrap chip rows with WrappingHStack instead: \(offenders.joined(separator: ", "))
            """)
    }
}
