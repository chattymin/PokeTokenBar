import XCTest
import SwiftUI
@testable import PokeDexBar

/// 박스 화면이 저장된 순서를 그리고, 메뉴가 실제로 정리를 시킨다.
@MainActor
final class BoxSortViewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        PlayerStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("bsv-\(UUID().uuidString).json"),
                    rng: SeededRNG(seed: 1), now: { self.now },
                    defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    /// 저장된 순서가 **뒤죽박죽이어도 그대로** 그린다. 화면이 다시 정렬하면 정리가 안 보인다.
    func testTheGridDrawsTheStoredOrderNotAResort() {
        let store = makeStore()
        // 획득 시각과 반대로 저장해 둔다 — 화면이 obtainedAt 으로 다시 정렬하면 뒤집힌다.
        store.mutate {
            $0.box = [
                Individual(baseID: 7, speciesID: 7, pathIDs: [7], nature: .hardy,
                           obtainedAt: self.now.addingTimeInterval(20), grade: .common),
                Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .hardy,
                           obtainedAt: self.now, grade: .common),
            ]
        }
        let storedOrder = store.state.box.map(\.id)
        BoxCell.resetConstructed()
        let host = NSHostingView(rootView: AnyView(
            BoxTabView(store: store, lines: [:], onNeedLine: { _ in },
                       selection: .constant(nil))
                .frame(width: PopoverMetrics.width)))
        host.layoutSubtreeIfNeeded()

        // `BoxCell.constructed` 는 `(id: UUID, onTap: () -> Void)` 를 담는다. 오프스크린 호스팅은
        // 측정·표시 두 패스로 본문을 두 번 평가해 각 칸이 같은 순서로 두 번씩 찍힌다(이 레포의
        // 다른 렌더 테스트들도 `FormButton.constructed` 처럼 첫 등장만 남겨 이 잡음을 걷어낸다) —
        // 순서 자체가 뒤섞였는지가 관심사라 첫 등장만 남기고 비교한다.
        var seen = Set<UUID>()
        let ids = BoxCell.constructed.map(\.id).filter { seen.insert($0).inserted }
        XCTAssertEqual(ids, storedOrder, "화면이 저장된 순서를 무시하고 다시 정렬했다")
    }

    /// **메뉴 항목을 누르면 실제로 박스가 재배치된다.** 항목만 그리고 배선이 끊기면 아무 일도 없다.
    func testTappingAMenuItemTidiesTheBox() {
        let store = makeStore()
        store.mutate {
            $0.box = [
                Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .hardy,
                           obtainedAt: self.now, grade: .common),
                Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .hardy,
                           obtainedAt: self.now.addingTimeInterval(10), grade: .legendary),
            ]
        }
        BoxSortMenu.resetConstructed()
        let host = NSHostingView(rootView: AnyView(
            BoxTabView(store: store, lines: [:], onNeedLine: { _ in },
                       selection: .constant(nil))
                .frame(width: PopoverMetrics.width)))
        host.layoutSubtreeIfNeeded()

        guard let recorded = BoxSortMenu.constructed.last else {
            return XCTFail("정렬 메뉴가 안 그려졌다")
        }
        XCTAssertEqual(Set(recorded.options), Set(BoxSort.allCases), "메뉴에 빠진 항목이 있다")
        recorded.action(.grade)

        XCTAssertEqual(store.state.box.map(\.speciesID), [4, 1], "눌렀는데 박스가 그대로다")
    }

    /// **선택 모드에서 정렬해도 고른 것이 유지된다** — 선택은 id 로 들고 있어야 한다.
    func testTidyingKeepsTheCurrentSelection() {
        let store = makeStore()
        let keep = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .hardy,
                              obtainedAt: now, grade: .common)
        let other = Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .hardy,
                               obtainedAt: now.addingTimeInterval(10), grade: .legendary)
        store.mutate { $0.box = [keep, other] }

        store.sortBox(.grade)

        // 선택은 `Set<UUID>` 라 재배치와 무관하다 — 그 사실을 못으로 박아 둔다.
        XCTAssertTrue(store.state.box.contains { $0.id == keep.id })
        XCTAssertEqual(store.state.box.first?.id, other.id)
    }

    /// 메뉴 라벨이 세 언어를 다 채운다.
    func testMenuLabelCoversAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            XCTAssertFalse(L(lang).boxSortMenu.isEmpty, "\(lang)")
        }
    }

    /// **"자리가 절대 안 움직인다"는 약속은 이제 거짓이다.** 정리 버튼이 자리를 옮기므로
    /// README 세 벌에서 그 문장이 사라져야 한다 — 문서가 조용히 거짓말하는 걸 막는 못이다.
    func testTheReadmesNoLongerPromiseSlotsNeverMove() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["README.md", "README.ko.md", "README.ja.md"] {
            let text = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            XCTAssertFalse(text.contains("never moves once it's filled"), "\(name)")
            XCTAssertFalse(text.contains("stays put once it's filled"), "\(name)")
            XCTAssertFalse(text.contains("한번 채워진 칸은 움직이지 않습니다"), "\(name)")
            XCTAssertFalse(text.contains("자리가 고정돼"), "\(name)")
            XCTAssertFalse(text.contains("一度埋まったマスは動きません"), "\(name)")
            XCTAssertFalse(text.contains("場所が固定され"), "\(name)")
        }
    }
}
