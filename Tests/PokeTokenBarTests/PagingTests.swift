import XCTest
@testable import PokeTokenBar

/// Every long list of the app is cut in pages alike (#183): the catch log, the team grids, the Pokédex's lots.
final class PagingTests: XCTestCase {
    func testAListIsCutInWholePagesTheLastOneShort() {
        let items = Array(0..<23)
        XCTAssertEqual(Paging.pageCount(items.count, size: 10), 3)
        XCTAssertEqual(Paging.slice(items, page: 0, size: 10), Array(0..<10))
        XCTAssertEqual(Paging.slice(items, page: 2, size: 10), [20, 21, 22])
        XCTAssertEqual(Paging.pageCount(0, size: 10), 1, "an empty list still has its one page")
    }

    func testAPageBeyondTheListFallsBackOnTheLastOne() {
        let items = Array(0..<12)
        // A filter left fewer pages than the one shown.
        XCTAssertEqual(Paging.clamped(5, count: items.count, size: 10), 1)
        XCTAssertEqual(Paging.slice(items, page: 5, size: 10), [10, 11])
        XCTAssertEqual(Paging.clamped(-1, count: items.count, size: 10), 0)
    }
}
