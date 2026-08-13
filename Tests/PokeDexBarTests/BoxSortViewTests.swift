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

    /// **선택 모드에서 정렬해도 고른 것이 화면에서도 유지된다** — 선택은 `Set<UUID>` 라
    /// 재배치와 무관해야 한다. 이전 버전은 `BoxTabView` 를 그리지도, 선택 모드에 들어가지도,
    /// `picked` 를 만지지도 않고 `store.sortBox` 만 다시 확인했다 — 그건
    /// `BoxTidyTests.testSortingRearrangesTheStoredBox` 가 이미 잠근 것이라, 선택 기능을
    /// 통째로 지워도 이 테스트는 그대로 통과했다. 그리드가 정렬 뒤 다시 그려질 때
    /// `BoxCell.constructed` 의 `picked` 가 여전히 참인지, 실제 렌더 경로로 확인한다.
    func testTidyingKeepsTheCurrentSelection() {
        let store = makeStore()
        let keep = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .hardy,
                              obtainedAt: now, grade: .common)
        let other = Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .hardy,
                               obtainedAt: now.addingTimeInterval(10), grade: .legendary)
        store.mutate { $0.box = [keep, other] }

        BoxCell.resetConstructed()
        BoxSortMenu.resetConstructed()
        let host = NSHostingView(rootView: AnyView(
            BoxTabView(store: store, lines: [:], onNeedLine: { _ in },
                       selection: .constant(nil), selecting: true)
                .frame(width: PopoverMetrics.width)))
        host.layoutSubtreeIfNeeded()

        // 선택 모드에서 두 칸을 탭한다 — `cellTap(selecting: true, …)` 은 `.toggle` 이다.
        for id in [keep.id, other.id] {
            guard let cell = BoxCell.constructed.first(where: { $0.id == id }) else {
                return XCTFail("칸이 안 그려졌다")
            }
            cell.onTap()
        }

        guard let recorded = BoxSortMenu.constructed.last else {
            return XCTFail("정렬 메뉴가 안 그려졌다")
        }
        recorded.action(.grade)
        XCTAssertEqual(store.state.box.map(\.id), [other.id, keep.id], "정렬 자체가 안 됐다")

        // 재정렬로 그리드가 다시 그려진다 — 이번에 그려진 칸들의 `picked` 를 본다.
        BoxCell.resetConstructed()
        host.layoutSubtreeIfNeeded()
        let stillPicked = Set(BoxCell.constructed.filter(\.picked).map(\.id))
        XCTAssertEqual(stillPicked, Set([keep.id, other.id]), "정렬 후 선택이 사라졌다")
    }

    /// 메뉴 라벨이 세 언어를 다 채운다.
    func testMenuLabelCoversAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            XCTAssertFalse(L(lang).boxSortMenu.isEmpty, "\(lang)")
        }
    }

    /// **`title` 이 실제로 쓰인다.** 아이콘만 있고 글자가 없는 메뉴라 VoiceOver 가 읽을 이름이
    /// 없었다 — `title` 이 시그니처에만 있고 아무 데도 안 쓰이면 `boxSortMenu` 문구도 죽은
    /// 코드가 된다. 툴팁(`.help(`)으로 돌아가면 안 된다 — 이 팝오버에서는 안 뜬다
    /// (`testTheBoxReachesTheBulkPath` 가 이미 이 파일 전체에서 그걸 지킨다).
    func testMenuTitleBecomesTheAccessibilityLabel() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/BoxTabView.swift"), encoding: .utf8)
        XCTAssertTrue(text.contains(".accessibilityLabel(title)"), "메뉴 제목이 접근성 레이블로 안 간다")
    }

    /// **"자리가 절대 안 움직인다"는 약속은 이제 거짓이다.** 정리 버튼이 자리를 옮기므로
    /// README 세 벌에서 그 문장이 사라져야 한다 — 문서가 조용히 거짓말하는 걸 막는 못이다.
    ///
    /// 부재만 보면 그 문단을 통째로 지워도 통과한다 — 그래서 새 약속("정리하기 전까지는 안
    /// 움직인다" + 정리 버튼 자체)이 실제로 **들어와 있는지**도 언어마다 하나씩 확인한다.
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
        let englishText = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(englishText.contains("a slot stays put until you tidy"),
                      "새 약속 문구가 영어 README 에 없다")
        let koreanText = try String(contentsOf: root.appendingPathComponent("README.ko.md"), encoding: .utf8)
        XCTAssertTrue(koreanText.contains("직접 정리하기 전까지는"),
                      "새 약속 문구가 한국어 README 에 없다")
        let japaneseText = try String(contentsOf: root.appendingPathComponent("README.ja.md"), encoding: .utf8)
        XCTAssertTrue(japaneseText.contains("じぶんでせいりするまで"),
                      "새 약속 문구가 일본어 README 에 없다")
    }
}
