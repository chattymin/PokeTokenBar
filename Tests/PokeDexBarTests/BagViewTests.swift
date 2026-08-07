import AppKit
import XCTest
@testable import PokeDexBar

/// 가방 — **가진 것을 보는 화면**. 상점에서 떼어 낸 이유가 그것이다: 도구 106종 중 살 수 있는
/// 건 7종뿐이라, 살 수 없는 것을 상점에 늘어놓으면 "왜 못 사지"가 된다.
@MainActor
final class BagViewTests: XCTestCase {
    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bag-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                           now: { Date(timeIntervalSince1970: 0) })
    }

    private func rows(_ store: PlayerStore) -> [BagTabView.Row] {
        BagTabView.sections(store).flatMap(\.rows)
    }

    /// 아무것도 없으면 모든 칸이 비어 있다 — 그때 화면은 빈 가방 안내를 낸다.
    func testAnEmptyBagHasNoRows() {
        XCTAssertTrue(rows(makeStore()).isEmpty)
    }

    /// **가진 것만** 나온다. 안 가진 걸 다 늘어놓으면 106줄이 되고, 무엇이 필요한지는
    /// 그 개체의 상세 화면이 훨씬 정확히 말해 준다.
    func testOnlyOwnedItemsAppear() {
        let store = makeStore()
        store.grantForTesting(EvolutionItem.magmarizer)
        store.grantForTesting(FormItem.griseousCore)
        let names = rows(store).map(\.name)
        XCTAssertEqual(Set(names), [EvolutionItem.magmarizer.label(.ko),
                                    FormItem.griseousCore.label(.ko)])
    }

    /// 도구·폼 도구는 **세 갈래 전부** 가방에 담겨야 한다 — 하나라도 빠지면 그 품목은 얻고도
    /// 어디서도 확인할 수 없다. 이 저장소가 반복해서 밟은 "기능은 있는데 화면이 없다"의 형태다.
    func testEveryItemFamilyReachesTheBag() {
        let store = makeStore()
        store.grantForTesting(EvolutionItem.fireStone)
        store.grantForTesting(FormItem.plateFire)
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(store.buy(ShopItem.expCandy))
        XCTAssertTrue(store.buy(ShopItem.shinyCharm))

        let sections = BagTabView.sections(store)
        let byTitle = Dictionary(uniqueKeysWithValues: sections.map { ($0.title, $0) })
        XCTAssertEqual(byTitle[store.l.bagConsumables]?.rows.first?.name,
                       ShopItem.expCandy.label(.ko))
        XCTAssertEqual(byTitle[ShopCategory.charm.title(.ko)]?.rows.first?.name,
                       ShopItem.shinyCharm.label(.ko))
        XCTAssertEqual(byTitle[store.l.shopEvolutionSection]?.rows.first?.name,
                       EvolutionItem.fireStone.label(.ko))
        XCTAssertEqual(byTitle[store.l.shopFormItemSection]?.rows.first?.name,
                       FormItem.plateFire.label(.ko))
    }

    /// 소모품은 개수를, 영구 보유형은 개수 대신 "보유 중"을 보여준다 — "×1" 이 붙어 있으면
    /// 쓰면 없어지는 물건으로 읽힌다.
    func testConsumablesShowCountsAndPermanentsDoNot() {
        let store = makeStore()
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(store.buy(ShopItem.expCandy))
        XCTAssertTrue(store.buy(ShopItem.expCandy))
        store.grantForTesting(EvolutionItem.fireStone)

        let byName = Dictionary(uniqueKeysWithValues: rows(store).map { ($0.name, $0.count) })
        XCTAssertEqual(byName[ShopItem.expCandy.label(.ko)], 2)
        XCTAssertEqual(byName[EvolutionItem.fireStone.label(.ko)], 0, "영구 보유형에 개수가 붙었다")
    }

    /// 수집 진행도는 도구 칸에만 붙는다 — 사탕을 "2/7" 로 세는 건 의미가 없다.
    func testProgressTotalsOnlyOnCollectibleSections() {
        let sections = BagTabView.sections(makeStore())
        let byTitle = Dictionary(uniqueKeysWithValues: sections.map { ($0.title, $0.total) })
        XCTAssertEqual(byTitle[L(.ko).shopEvolutionSection], EvolutionItem.allCases.count)
        XCTAssertEqual(byTitle[L(.ko).shopFormItemSection], FormItem.allCases.count)
        XCTAssertNil(byTitle[L(.ko).bagConsumables] ?? nil)
    }

    /// 빈 가방 안내는 세 언어 모두 있어야 한다.
    func testEmptyStateIsLocalized() {
        for text in [\L.bagEmptyTitle, \L.bagEmptyHint] as [KeyPath<L, String>] {
            let all = [AppLanguage.ko, .en, .ja].map { L($0)[keyPath: text] }
            XCTAssertEqual(Set(all).count, 3, all.description)
            XCTAssertFalse(all.contains { $0.isEmpty })
        }
    }
}

/// 탭 라벨은 팝오버 폭 안에 들어가야 한다. 탭이 하나 늘 때마다 세그먼트가 좁아지므로,
/// 가장 긴 언어(일본어)가 먼저 잘린다 — 실제로 `コレクション` 으로 12pt 넘쳤다.
@MainActor
final class TabBarWidthTests: XCTestCase {
    func testEveryLanguageFitsThePopoverWidth() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        for lang in AppLanguage.allCases {
            let l = L(lang)
            let labels = [l.home, l.box, l.collection, l.bag, l.shop]
            let text = labels.reduce(0.0) {
                $0 + ($1 as NSString).size(withAttributes: [.font: font]).width
            }
            // 세그먼트마다 좌우 여백이 붙는다 — 실측에 맞춘 보수적인 값.
            let needed = text + Double(labels.count) * 24
            XCTAssertLessThanOrEqual(needed, Double(PopoverMetrics.contentWidth),
                                     "\(lang) 탭이 \(Int(needed))pt 로 넘친다: \(labels)")
        }
    }
}
