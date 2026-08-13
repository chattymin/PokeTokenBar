import XCTest
@testable import PokeDexBar

/// 박스 정리 — 일곱 개의 재배치 명령.
final class BoxSortTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// 축 하나만 갈리는 개체를 만든다. **나머지는 전부 같게 둬야** 무엇이 정렬했는지 알 수 있다.
    private func make(_ name: String, order: Int,
                      level: Int = 1, grade: Grade = .common, species: Int = 25,
                      shiny: Bool = false, partnerSeconds: Int = 0,
                      disguisedAs: Int? = nil) -> Individual {
        var individual = Individual(baseID: species, speciesID: species, pathIDs: [species],
                                    shiny: shiny, nature: .hardy,
                                    exp: GrowthRate.mediumFast.totalExp(at: level),
                                    obtainedAt: epoch.addingTimeInterval(Double(order)),
                                    grade: grade, growthRate: .mediumFast)
        individual.partnerSeconds = partnerSeconds
        individual.disguisedAs = disguisedAs
        return individual
    }

    private func order(_ sort: BoxSort, _ box: [Individual]) -> [Int] {
        sort.apply(to: box, at: epoch).map(\.speciesID)
    }

    /// 획득순 — 오래된 것부터. 이것이 **유일한 되돌리기**라 언제나 정확해야 한다.
    func testObtainedPutsTheOldestFirst() {
        let box = [make("c", order: 30, species: 3), make("a", order: 10, species: 1),
                   make("b", order: 20, species: 2)]
        XCTAssertEqual(order(.obtained, box), [1, 2, 3])
    }

    /// 레벨 — 양방향. 두 방향이 실제로 뒤집히는지 한 픽스처로 함께 본다.
    func testLevelSortsBothWays() {
        let box = [make("mid", order: 10, level: 50, species: 2),
                   make("low", order: 20, level: 5, species: 1),
                   make("high", order: 30, level: 90, species: 3)]
        XCTAssertEqual(order(.levelHigh, box), [3, 2, 1])
        XCTAssertEqual(order(.levelLow, box), [1, 2, 3])
    }

    /// 등급 — 레전더리부터. `Grade` 는 `Comparable` 이 아니므로 `rank` 가 순서를 정한다.
    func testGradePutsLegendaryFirst() {
        let box = [make("c", order: 10, grade: .common, species: 1),
                   make("l", order: 20, grade: .legendary, species: 4),
                   make("r", order: 30, grade: .rare, species: 2),
                   make("e", order: 40, grade: .epic, species: 3)]
        XCTAssertEqual(order(.grade, box), [4, 3, 2, 1])
        let ranks: [Grade] = [.common, .rare, .epic, .legendary]
        XCTAssertEqual(ranks.map(\.rank), [0, 1, 2, 3])
    }

    /// 도감번호 — 낮은 번호부터.
    func testDexSortsByNumber() {
        let box = [make("c", order: 10, species: 133), make("a", order: 20, species: 4),
                   make("b", order: 30, species: 25)]
        XCTAssertEqual(order(.dex, box), [4, 25, 133])
    }

    /// **위장한 메타몽은 보이는 번호 자리에 선다.** 진짜 번호(132)로 정렬하면 뮤로 보이는
    /// 아이가 132번 자리에 서서, 눌러 확인하기 전에 정체가 샌다.
    ///
    /// `b` 를 132(진짜)와 151(위장) **사이**의 140에 둔다 — 두 번호가 100/200처럼 양 끝
    /// 바깥에 있으면 어느 번호로 정렬해도 같은 자리에 떨어져 이 테스트가 아무것도 못 잡는다.
    /// 140을 사이에 둬야 진짜 번호로 정렬했을 때(ditto가 b보다 앞)와 위장 번호로 정렬했을
    /// 때(ditto가 b보다 뒤)의 순서가 실제로 갈린다.
    func testDexUsesTheNumberOnScreenSoADisguiseHolds() {
        // 메타몽(132)이 뮤(151)로 위장 중.
        let ditto = make("ditto", order: 10, species: 132, disguisedAs: 151)
        let box = [ditto, make("a", order: 20, species: 100), make("b", order: 30, species: 140)]

        let sorted = BoxSort.dex.apply(to: box, at: epoch)
        XCTAssertEqual(sorted.map(\.speciesID), [100, 140, 132],
                       "위장한 메타몽이 진짜 번호(132) 자리에 섰다 — 정체가 샌다")
    }

    /// 이로치 먼저. **위장 중이면 이로치로 안 센다** — 같은 이유(정체가 샌다).
    ///
    /// `hidden` 은 이로치로 안 세어지므로 `plain` 과 같은 키(비이로치)로 묶인다 — 둘의 순서는
    /// 이로치 여부가 아니라 획득순 폴백이 정한다(`hidden` 이 더 먼저 들어왔으니 앞).
    /// 여기서 확인하는 건 "앞으로 안 나온다" 는 것: `open`(진짜 이로치)보다 뒤에 있어야 한다.
    func testShinyPutsShiniesFirstAndDoesNotCountADisguisedOne() {
        var hidden = make("hidden", order: 10, species: 1, shiny: true, disguisedAs: 151)
        hidden.shiny = true
        let box = [make("plain", order: 20, species: 2),
                   hidden,
                   make("open", order: 30, species: 3, shiny: true)]

        XCTAssertEqual(order(.shiny, box), [3, 1, 2],
                       "위장한 이로치가 앞으로 나와 정체를 흘렸다")
    }

    /// 리본 — 높은 것부터, 리본 없음은 맨 뒤.
    func testRibbonPutsTheHighestFirstAndNoRibbonLast() {
        let box = [make("none", order: 10, species: 1),
                   make("bond", order: 20, species: 2,
                        partnerSeconds: Ribbon.bond.requiredPartnerSeconds),
                   make("kinship", order: 30, species: 3,
                        partnerSeconds: Ribbon.kinship.requiredPartnerSeconds)]
        XCTAssertEqual(order(.ribbon, box), [3, 2, 1])
    }

    /// **동률은 획득순으로 떨어진다.** 이차 키가 없으면 같은 등급 여럿의 배치가 호출마다
    /// 달라지고, 그 배치가 이제 디스크에 저장되므로 열 때마다 박스가 뒤섞여 보인다.
    func testTiesFallBackToObtainedOrder() {
        let box = [make("c", order: 30, grade: .rare, species: 3),
                   make("a", order: 10, grade: .rare, species: 1),
                   make("b", order: 20, grade: .rare, species: 2)]
        XCTAssertEqual(order(.grade, box), [1, 2, 3])
    }

    /// **1차·2차 키까지 동률이면 `id` 가 갈라야 한다.** 리뷰가 `id.uuidString < …` 를 `false` 로
    /// 바꿔도 22개 테스트가 전부 통과했다 — 모든 픽스처가 `obtainedAt` 까지는 서로 달라서 이
    /// 세 번째 키가 한 번도 안 밟혔다. `ScreenshotGenerator` 처럼 `obtainedAt` 까지 같은 개체가
    /// 실제로 있으므로(픽스처 무관하게), 등급까지 같은 둘을 만들어 이 키를 직접 밟는다. 두 번
    /// 정렬해 같은 배치가 나오는지, 그 배치가 `uuidString` 순인지를 확인한다.
    func testTiesAtEveryKeyFallBackToUUIDStringOrder() {
        let sameInstant = epoch.addingTimeInterval(10)
        let low = Individual(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                             baseID: 1, speciesID: 1, pathIDs: [1], nature: .hardy,
                             obtainedAt: sameInstant, grade: .rare)
        let high = Individual(id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
                              baseID: 2, speciesID: 2, pathIDs: [2], nature: .hardy,
                              obtainedAt: sameInstant, grade: .rare)
        let box = [high, low]   // 일부러 uuidString 역순으로 넣는다.

        let once = BoxSort.grade.apply(to: box, at: epoch)
        let twice = BoxSort.grade.apply(to: once, at: epoch)
        XCTAssertEqual(once.map(\.id), twice.map(\.id), "같은 동률 배치가 호출마다 달라진다")
        XCTAssertEqual(once.map(\.id), [low.id, high.id], "동률 폴백이 uuidString 순이 아니다")
    }

    /// 같은 입력을 두 번 정렬하면 같은 배치. 그리고 이미 정렬된 것을 또 정렬해도 안 흔들린다.
    func testSortingIsStableAndIdempotent() {
        let box = (0..<12).map { make("x\($0)", order: $0, grade: .rare, species: 100 + $0) }
        let once = BoxSort.grade.apply(to: box, at: epoch)
        let twice = BoxSort.grade.apply(to: once, at: epoch)
        XCTAssertEqual(once.map(\.id), twice.map(\.id))
        XCTAssertEqual(once.map(\.id), BoxSort.grade.apply(to: box, at: epoch).map(\.id))
    }

    /// 빈 박스와 한 마리짜리 박스에서 안 죽는다.
    func testEmptyAndSingleBoxesAreFine() {
        for sort in BoxSort.allCases {
            XCTAssertEqual(sort.apply(to: [], at: epoch).count, 0, "\(sort)")
            XCTAssertEqual(sort.apply(to: [make("only", order: 1)], at: epoch).count, 1, "\(sort)")
        }
    }

    /// 정렬은 **누구도 잃거나 복제하지 않는다** — 재배치일 뿐이다.
    func testEverySortKeepsExactlyTheSameIndividuals() {
        let box = (0..<20).map {
            make("x\($0)", order: $0, level: $0 * 5,
                 grade: Grade.allCases[$0 % 4], species: 1 + $0)
        }
        let ids = Set(box.map(\.id))
        for sort in BoxSort.allCases {
            let result = sort.apply(to: box, at: epoch)
            XCTAssertEqual(result.count, box.count, "\(sort) 가 마릿수를 바꿨다")
            XCTAssertEqual(Set(result.map(\.id)), ids, "\(sort) 가 개체를 바꿔치기했다")
        }
    }

    /// 문구가 세 언어를 다 채운다.
    func testLabelsCoverAllThreeLanguages() {
        for sort in BoxSort.allCases {
            for lang in AppLanguage.allCases {
                XCTAssertFalse(sort.label(lang).isEmpty, "\(sort) \(lang)")
            }
        }
    }
}
