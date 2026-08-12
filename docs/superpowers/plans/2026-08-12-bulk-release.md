# 골라서 한 번에 보내기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 박스에서 여러 마리를 골라 한 번에 박사에게 보낸다.

**Architecture:** B(박사에게 보내기) 위에 얹는 얇은 층이다. 스토어 규칙은 그대로 두고 `mutate`
한 번으로 여러 마리를 처리하는 함수 하나를 더하고, 박스에 선택 모드를 넣는다. 확인 규칙은 단일
보내기의 `releaseConfirmSteps` 를 배치 전체에 걸쳐 **최댓값으로 접어** 재사용한다 — 규칙을 두 번
적지 않는다.

**Tech Stack:** Swift 6 / SwiftPM / SwiftUI / XCTest. 외부 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-08-11-professor-and-vouchers-design.md` 의 **C 절**.
A·B 절은 이미 구현돼 있다 — 건드리지 않는다.

## Global Constraints

- **커밋 메시지는 영어. 코드 주석은 한국어** — 주변 주석과 같은 밀도·어투로. *왜* 를 적는다.
- **사용자에게 보이는 문자열은 전부 `L.t(ko, en, ja)`** (`Sources/PokeDexBar/Core/Localization.swift`).
- **빌드 경고 0.** `swift build` 만으로는 테스트 타깃을 안 짓는다 — **`swift build --build-tests`** 로 확인한다.
- **`.help()` 툴팁 금지** — 이 앱의 팝오버 안에서는 안 뜬다(실사용 확인).
- **실제 세이브 파일(`~/Library/Application Support/PokeDexBar/`) 접근 금지 in tests.**
- **파트너 판정은 `store.releaseValue(individual) == nil` 하나만 쓴다.** 화면이 조건을 따로 적으면
  스토어와 갈린다 — 이 기능에서 실제로 한 번 났다.
- 테스트: `swift test --filter BulkReleaseTests` / 전체는 `swift test`.

---

## File Structure

| 파일 | 책임 |
|---|---|
| `Sources/PokeDexBar/Player/PlayerStore+Professor.swift` **(수정)** | `releaseManyToProfessor` 를 더한다. |
| `Sources/PokeDexBar/UI/BulkRelease.swift` **(신규)** | 배치의 확인 단계와 위험한 개체 고르기 — 순수 함수만. 뷰 없이 테스트한다. |
| `Sources/PokeDexBar/UI/BoxTabView.swift` **(수정)** | 선택 모드, 헤더 버튼, 칸 토글, 확인 바. |
| `Sources/PokeDexBar/Core/Localization.swift` **(수정)** | ko/en/ja 문구. |
| `Tests/PokeDexBarTests/BulkReleaseTests.swift` **(신규)** | 두 태스크의 테스트가 여기 모인다. |

---

## Task 1: 여러 마리를 한 번에 보내는 동작

**Files:**
- Create: `Sources/PokeDexBar/UI/BulkRelease.swift`
- Modify: `Sources/PokeDexBar/Player/PlayerStore+Professor.swift` (`releaseToProfessor` 아래)
- Test: `Tests/PokeDexBarTests/BulkReleaseTests.swift` (신규)

**Interfaces:**
- Consumes: `PlayerStore.releaseValue(_:) -> Int?` (파트너면 nil), `ReleaseBalance.maxPoints`,
  `IndividualDetailView.releaseConfirmSteps(shiny:grade:) -> Int`
- Produces:
  - `@discardableResult func PlayerStore.releaseManyToProfessor(individualIDs: [UUID]) -> Int`
  - `static func BulkRelease.confirmSteps(for individuals: [Individual]) -> Int`
  - `static func BulkRelease.risky(_ individuals: [Individual]) -> [Individual]`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`Tests/PokeDexBarTests/BulkReleaseTests.swift` 를 새로 만든다.

```swift
import XCTest
@testable import PokeDexBar

/// 골라서 한 번에 보내기.
@MainActor
final class BulkReleaseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bulk-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    private func make(_ grade: Grade, path: [Int], shiny: Bool = false) -> Individual {
        Individual(baseID: path.first ?? 1, speciesID: path.last ?? 1, pathIDs: path,
                   shiny: shiny, nature: .hardy, obtainedAt: now, grade: grade)
    }

    // MARK: 확인 단계 — 배치는 그 안에서 가장 엄한 규칙을 따른다

    /// 평범한 아이들만 있으면 한 번만 묻는다.
    func testAnOrdinaryBatchAsksOnce() {
        let batch = [make(.common, path: [1]), make(.rare, path: [25])]
        XCTAssertEqual(BulkRelease.confirmSteps(for: batch), 1)
    }

    /// **이로치가 하나라도 섞이면 배치 전체가 한 번 더 묻는다.** 20마리 중 이로치 하나가
    /// 딸려 나가는 것이 이 기능의 유일한 진짜 사고다.
    func testOneShinyMakesTheWholeBatchAskTwice() {
        let batch = [make(.common, path: [1]), make(.common, path: [4], shiny: true),
                     make(.common, path: [7])]
        XCTAssertEqual(BulkRelease.confirmSteps(for: batch), 2)
    }

    /// 전설도 마찬가지.
    func testOneLegendaryMakesTheWholeBatchAskTwice() {
        XCTAssertEqual(BulkRelease.confirmSteps(for: [make(.common, path: [1]),
                                                      make(.legendary, path: [150])]), 2)
    }

    /// **단일 보내기와 같은 규칙을 쓴다.** 규칙을 두 군데 적으면 갈린다 — 한 마리짜리 배치는
    /// 그 한 마리의 단계와 반드시 같아야 한다.
    func testASingleItemBatchMatchesTheSingleSendRule() {
        for grade in Grade.allCases {
            for shiny in [true, false] {
                let one = make(grade, path: [1], shiny: shiny)
                XCTAssertEqual(BulkRelease.confirmSteps(for: [one]),
                               IndividualDetailView.releaseConfirmSteps(shiny: shiny, grade: grade),
                               "\(grade) shiny=\(shiny)")
            }
        }
    }

    /// 빈 배치는 1 — 확인 화면 자체가 안 뜨지만, 0 을 돌려주면 호출부가 단계 비교에서 헷갈린다.
    func testAnEmptyBatchIsOneStep() {
        XCTAssertEqual(BulkRelease.confirmSteps(for: []), 1)
    }

    /// 이름으로 불러 줄 아이들 — 이로치와 전설만. 20개를 다 나열하면 아무도 안 읽는다.
    func testRiskyPicksOnlyShiniesAndLegendaries() {
        let plain = make(.common, path: [1])
        let shiny = make(.rare, path: [4], shiny: true)
        let legendary = make(.legendary, path: [150])
        XCTAssertEqual(BulkRelease.risky([plain, shiny, legendary, plain]).map(\.id),
                       [shiny.id, legendary.id])
        XCTAssertTrue(BulkRelease.risky([plain]).isEmpty)
    }

    // MARK: 한 번에 보내기

    /// 여러 마리가 한 번에 나가고 포인트는 개별 합과 같다.
    func testSendingSeveralPaysTheSumOfTheirValues() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        let a = make(.epic, path: [4, 5, 6]), b = make(.rare, path: [25])
        for individual in [keep, a, b] { store.addForTesting(individual) }
        store.setPartner(keep.id)

        let expected = store.releaseValue(a)! + store.releaseValue(b)!
        XCTAssertEqual(store.releaseManyToProfessor(individualIDs: [a.id, b.id]), expected)
        XCTAssertEqual(store.state.box.map(\.id), [keep.id])
        XCTAssertEqual(store.state.researchPoints, expected)
    }

    /// **파트너는 목록에 섞여 있어도 절대 안 나간다.** 화면이 못 고르게 돼 있지만 스토어가
    /// 마지막 방어선이다 — 파트너가 사라지면 시계·폼 상태가 통째로 없어진다.
    func testThePartnerIsNeverSentEvenIfListed() {
        let store = makeStore()
        let partner = make(.common, path: [1]), other = make(.common, path: [4])
        store.addForTesting(partner); store.addForTesting(other)
        store.setPartner(partner.id)

        let points = store.releaseManyToProfessor(individualIDs: [partner.id, other.id])
        XCTAssertEqual(points, store.releaseValue(other) ?? -1, "파트너 값이 합계에 섞였다")
        XCTAssertTrue(store.state.box.contains { $0.id == partner.id }, "파트너가 나갔다")
        XCTAssertFalse(store.state.box.contains { $0.id == other.id })
    }

    /// 없는 id 가 섞여 있어도 나머지는 나간다.
    func testUnknownIDsAreSkipped() {
        let store = makeStore()
        let keep = make(.common, path: [1]), send = make(.rare, path: [25])
        store.addForTesting(keep); store.addForTesting(send)
        store.setPartner(keep.id)

        XCTAssertEqual(store.releaseManyToProfessor(individualIDs: [UUID(), send.id]),
                       store.releaseValue(send) ?? -1)
        XCTAssertEqual(store.state.box.map(\.id), [keep.id])
    }

    /// 빈 목록은 아무 일도 안 일으킨다.
    func testAnEmptyListDoesNothing() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        store.addForTesting(keep)
        XCTAssertEqual(store.releaseManyToProfessor(individualIDs: []), 0)
        XCTAssertEqual(store.state.box.count, 1)
        XCTAssertEqual(store.state.researchPoints, 0)
    }

    /// 같은 id 가 두 번 들어와도 한 번만 나간다 — 값이 두 배로 잡히면 포인트가 공짜로 는다.
    func testADuplicateIDIsOnlyCountedOnce() {
        let store = makeStore()
        let keep = make(.common, path: [1]), send = make(.rare, path: [25])
        store.addForTesting(keep); store.addForTesting(send)
        store.setPartner(keep.id)

        XCTAssertEqual(store.releaseManyToProfessor(individualIDs: [send.id, send.id]),
                       store.releaseValue(send) ?? -1)
        XCTAssertEqual(store.state.box.map(\.id), [keep.id])
    }

    /// **부화 감면도 한 번에 정리된다.** 유일한 불꽃몸이 배치에 섞여 있으면 보낸 뒤 감면이 끝난다 —
    /// 단일 보내기와 같은 규칙이고, 감면 판정이 박스를 보므로 저절로 따라온다.
    func testSendingTheOnlyWarmPokemonInABatchEndsTheDiscount() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        let slugma = make(.common, path: [218]), other = make(.common, path: [4])
        for individual in [keep, slugma, other] { store.addForTesting(individual) }
        store.setPartner(keep.id)
        XCTAssertTrue(HatchSpeedup.present(in: store.state.box))

        store.releaseManyToProfessor(individualIDs: [slugma.id, other.id])
        XCTAssertFalse(HatchSpeedup.present(in: store.state.box), "보냈는데 감면이 남았다")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter BulkReleaseTests`
Expected: 컴파일 실패 — `cannot find 'BulkRelease' in scope`

- [ ] **Step 3: `BulkRelease.swift` 를 만든다**

```swift
import Foundation

/// 여러 마리를 한 번에 보낼 때의 판단들. **순수 함수만** 둔다 — 뷰 없이 테스트로 잠그기 위해서다.
/// 이 기능에서 화면이 스토어와 다른 조건을 적었다가 갈린 적이 있어, 판단은 전부 여기로 모은다.
enum BulkRelease {
    /// 이 배치를 보내기 전에 몇 번 확인하나.
    ///
    /// **배치는 그 안에서 가장 엄한 규칙을 따른다.** 20마리 중 이로치 한 마리가 딸려 나가는 것이
    /// 이 기능의 유일한 진짜 사고라, 하나라도 섞이면 배치 전체가 한 번 더 묻는다.
    ///
    /// 규칙 자체는 단일 보내기의 `releaseConfirmSteps` 를 그대로 쓴다 — 두 군데 적으면 갈린다.
    /// 빈 배치가 1인 것은 확인 화면이 안 뜨기 때문이 아니라, 0을 돌려주면 호출부의 단계 비교가
    /// 뜻을 잃기 때문이다.
    static func confirmSteps(for individuals: [Individual]) -> Int {
        individuals.reduce(1) { steps, individual in
            max(steps, IndividualDetailView.releaseConfirmSteps(shiny: individual.shiny,
                                                                grade: individual.grade))
        }
    }

    /// 확인 화면에서 **이름으로 불러 줄** 아이들 — 이로치와 전설.
    /// 스무 마리를 다 나열하면 아무도 안 읽지만, 위험한 것만 부르면 읽힌다.
    static func risky(_ individuals: [Individual]) -> [Individual] {
        individuals.filter { $0.shiny || $0.grade == .legendary }
    }
}
```

- [ ] **Step 4: `releaseManyToProfessor` 를 더한다**

`Sources/PokeDexBar/Player/PlayerStore+Professor.swift` 의 `releaseToProfessor` **아래**:

```swift
    /// 여러 마리를 한 번에 보낸다. 보낼 수 없는 id(파트너·박스에 없는 개체)는 건너뛰고 나머지를
    /// 보내며, 돌려주는 값은 **실제로 보낸 만큼**의 포인트 합이다.
    ///
    /// **한 번의 `mutate`** 로 끝난다 — 마리마다 `releaseToProfessor` 를 부르면 저장이 스무 번
    /// 일어나고, 중간에 실패하면 절반만 나간 상태가 남는다.
    ///
    /// 파트너를 거르는 것은 화면이 아니라 여기다. 화면이 못 고르게 돼 있어도 마지막 방어선은
    /// 스토어여야 한다 — 파트너가 사라지면 함께한 시계와 폼 상태가 통째로 없어진다.
    @discardableResult
    func releaseManyToProfessor(individualIDs: [UUID]) -> Int {
        // 같은 id 가 두 번 들어와도 한 번만 — 값이 두 배로 잡히면 포인트가 공짜로 는다.
        var seen = Set<UUID>()
        let sendable = individualIDs.filter { seen.insert($0).inserted }
            .compactMap { id -> (UUID, Int)? in
                guard let individual = state.box.first(where: { $0.id == id }),
                      let points = releaseValue(individual) else { return nil }
                return (id, points)
            }
        guard !sendable.isEmpty else { return 0 }
        let total = sendable.reduce(0) { $0 + $1.1 }
        let ids = Set(sendable.map(\.0))
        mutate { s in
            s.box.removeAll { ids.contains($0.id) }
            s.researchPoints = min(ReleaseBalance.maxPoints, s.researchPoints + total)
        }
        return total
    }
```

- [ ] **Step 5: 테스트가 통과하는지 확인한다**

Run: `swift test --filter BulkReleaseTests`
Expected: PASS (12개)

- [ ] **Step 6: 가드가 진짜 판별하는지 확인한다 (되돌리기 검사)**

`confirmSteps` 의 `reduce(1)` 를 `{ _, _ in 1 }` 로 잠시 바꿔 항상 1을 돌려주게 한다.

Run: `swift test --filter BulkReleaseTests`
Expected: `testOneShinyMakesTheWholeBatchAskTwice`·`testOneLegendaryMakesTheWholeBatchAskTwice`·
`testASingleItemBatchMatchesTheSingleSendRule` **이 실패해야 한다.** 확인했으면 되돌리고
`git diff` 로 되돌림이 완전한지 본다.

- [ ] **Step 7: 전체 테스트와 경고를 확인한다**

Run: `swift build --build-tests 2>&1 | grep -i warning; swift test`
Expected: 경고 출력 없음, 전체 PASS

- [ ] **Step 8: 커밋**

```bash
git add Sources/PokeDexBar/UI/BulkRelease.swift Sources/PokeDexBar/Player/PlayerStore+Professor.swift Tests/PokeDexBarTests/BulkReleaseTests.swift
git commit -m "feat: send several Pokemon to the Professor in one go"
```

---

## Task 2: 박스의 선택 모드와 확인 바

**Files:**
- Modify: `Sources/PokeDexBar/Core/Localization.swift`
- Modify: `Sources/PokeDexBar/UI/BoxTabView.swift` (`grid`, `boxHeader`, `BoxCell`)
- Test: `Tests/PokeDexBarTests/BulkReleaseTests.swift`

**Interfaces:**
- Consumes: `BulkRelease.confirmSteps(for:)`, `BulkRelease.risky(_:)`,
  `PlayerStore.releaseManyToProfessor(individualIDs:)`, `PlayerStore.releaseValue(_:) -> Int?`
- Produces: UI 만 — 이후 태스크 없음

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`BulkReleaseTests.swift` 에 더한다.

```swift
    // MARK: 선택 모드

    /// 고를 수 있는 아이인가 — **판정은 `releaseValue` 하나**다. 화면이 조건을 따로 적으면
    /// 스토어와 갈린다(이 기능에서 실제로 한 번 났다).
    func testOnlySendableIndividualsArePickable() {
        let store = makeStore()
        let partner = make(.common, path: [1]), other = make(.common, path: [4])
        store.addForTesting(partner); store.addForTesting(other)
        store.setPartner(partner.id)

        XCTAssertFalse(BoxTabView.isPickable(partner, store: store), "파트너를 고를 수 있다")
        XCTAssertTrue(BoxTabView.isPickable(other, store: store))
    }

    /// 고른 아이들의 합계 — 바에 적히는 값이다.
    func testPickedTotalIsTheSumOfTheirValues() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        let a = make(.epic, path: [4, 5, 6]), b = make(.rare, path: [25])
        for individual in [keep, a, b] { store.addForTesting(individual) }
        store.setPartner(keep.id)

        XCTAssertEqual(BoxTabView.pickedTotal([a, b], store: store),
                       store.releaseValue(a)! + store.releaseValue(b)!)
        XCTAssertEqual(BoxTabView.pickedTotal([], store: store), 0)
    }

    /// 화면이 실제로 일괄 경로에 닿아 있다 — 안 닿으면 고를 수는 있는데 보낼 수가 없다.
    func testTheBoxReachesTheBulkPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/BoxTabView.swift"), encoding: .utf8)
        XCTAssertTrue(text.contains("releaseManyToProfessor"), "박스에 일괄 보내기가 없다")
        XCTAssertTrue(text.contains("BulkRelease.confirmSteps"), "확인 단계 규칙을 안 쓴다")
        XCTAssertFalse(text.contains(".help("), "안 뜨는 툴팁이 들어왔다")
    }

    /// 문구가 세 언어를 다 채운다.
    func testBulkStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.bulkSelect.isEmpty, "\(lang)")
            XCTAssertFalse(l.bulkDone.isEmpty, "\(lang)")
            XCTAssertFalse(l.bulkPicked(3, 18).isEmpty, "\(lang)")
            XCTAssertFalse(l.bulkConfirm(3).isEmpty, "\(lang)")
            XCTAssertFalse(l.bulkConfirmRisky("파이리").isEmpty, "\(lang)")
        }
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter BulkReleaseTests`
Expected: 컴파일 실패 — `type 'BoxTabView' has no member 'isPickable'`

- [ ] **Step 3: 문구를 더한다**

`Sources/PokeDexBar/Core/Localization.swift` 의 `sendNow` **아래**:

```swift
    /// 박스의 선택 모드 — 여러 마리를 골라 한 번에 보낸다.
    var bulkSelect: String { t("선택", "Select", "えらぶ") }
    var bulkDone: String { t("완료", "Done", "おわり") }
    func bulkPicked(_ count: Int, _ points: Int) -> String {
        t("\(count)마리 · +\(points)P", "\(count) selected · +\(points)P",
          "\(count)ひき · +\(points)P")
    }
    func bulkConfirm(_ count: Int) -> String {
        t("\(count)마리를 보냅니다. 돌아오지 않아요.",
          "Sending \(count). This cannot be undone.",
          "\(count)ひきをおくります。もどってきません。")
    }
    /// 배치에 이로치·전설이 섞였을 때 **그 아이들만 이름으로** 불러 준다 — 스무 마리를 다
    /// 나열하면 아무도 안 읽는다.
    func bulkConfirmRisky(_ names: String) -> String {
        t("\(names)가 들어 있어요", "\(names) is in this batch", "\(names)がふくまれています")
    }
```

- [ ] **Step 4: 순수 판정을 `BoxTabView` 에 더한다**

`Sources/PokeDexBar/UI/BoxTabView.swift` 의 `progress(_:isFoundEggCandidate:)` **아래**:

```swift
    /// 이 개체를 골라 담을 수 있나. **판정은 `releaseValue` 하나** — 파트너면 nil 이다.
    /// 화면이 "파트너인가"를 따로 적으면 스토어와 갈린다.
    @MainActor static func isPickable(_ individual: Individual, store: PlayerStore) -> Bool {
        store.releaseValue(individual) != nil
    }

    /// 고른 아이들을 보내면 받을 포인트 합.
    @MainActor static func pickedTotal(_ individuals: [Individual], store: PlayerStore) -> Int {
        individuals.reduce(0) { $0 + (store.releaseValue($1) ?? 0) }
    }
```

- [ ] **Step 5: 선택 상태와 헤더 버튼을 더한다**

`@State private var page = 0` **아래**:

```swift
    /// 선택 모드인가. 모드 밖에서는 칸을 누르면 지금처럼 상세로 간다 —
    /// **되돌릴 수 없는 조작으로 가는 문은 눌러서 연다.**
    @State private var selecting = false
    /// 골라 담은 아이들. 페이지를 넘겨도 유지된다 — 30칸을 넘겨 정리하는 것이 이 기능의 이유다.
    @State private var picked: Set<UUID> = []
    /// 확인이 몇 단계까지 진행됐나. 0 이면 아직 안 눌렀다.
    @State private var bulkStep = 0
```

`boxHeader` 의 오른쪽 페이지 버튼 **뒤**에 더한다:

```swift
            Button(selecting ? l.bulkDone : l.bulkSelect) {
                selecting.toggle()
                // 모드를 나가면 담은 것도 확인 단계도 비운다 — 다음에 열었을 때 지난 선택이
                // 남아 있으면 무엇을 보내는지 모르는 채로 누르게 된다.
                if !selecting { picked = []; bulkStep = 0 }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.accentColor)
```

- [ ] **Step 6: 칸 탭을 모드에 따라 가른다**

`grid` 안 `BoxCell(...)` 의 `partnerBadge:` 인자 뒤에 `picked:` 를 더하고, `onTap` 을 바꾼다:

```swift
                        BoxCell(individual: individual,
                                isPartner: individual.id == store.state.partnerID,
                                ribbon: individual.ribbon(at: store.currentDate()),
                                canEvolve: readyToEvolve(individual),
                                partnerBadge: l.partnerBadge,
                                picked: selecting && picked.contains(individual.id),
                                fillFrame: fillFrame) {
                            if selecting {
                                // 못 고르는 아이(파트너)를 눌러도 아무 일도 안 일어난다.
                                guard Self.isPickable(individual, store: store) else { return }
                                if picked.contains(individual.id) {
                                    picked.remove(individual.id)
                                } else {
                                    picked.insert(individual.id)
                                }
                                bulkStep = 0   // 담은 것이 바뀌면 확인은 처음부터
                            } else {
                                selection = individual.id
                            }
                        }
```

`BoxCell` 에 프로퍼티와 `init` 인자를 더한다. `let canEvolve: Bool` 선언 **아래**에 넣는다:

```swift
    /// 선택 모드에서 담긴 상태인가. 모드 밖에서는 항상 false 다.
    let picked: Bool
```

`init` 시그니처의 `partnerBadge: String,` 뒤에 `picked: Bool = false,` 를 더하고 본문에
`self.picked = picked` 를 더한다. `body` 의 `ZStack` 안, 진화 배지 블록 **뒤**에:

```swift
                    if picked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                            .offset(x: 3, y: -2)
                    }
```

그리고 담긴 칸이 눈에 띄게 `.background` 를 바꾼다 — `isPartner` 를 보던 자리를:

```swift
            .background(picked ? Color.accentColor.opacity(0.30)
                               : (isPartner ? Color.accentColor.opacity(0.22)
                                            : Color.secondary.opacity(0.16)),
                        in: RoundedRectangle(cornerRadius: 7))
```

> `BoxCell(` 호출부는 `BoxTabView.swift` 한 곳뿐이다. 인자를 더한 뒤
> `grep -rn "BoxCell(" Sources Tests` 로 그대로인지 확인한다.

- [ ] **Step 7: 확인 바를 더한다**

`grid` 의 `LazyVGrid { … }` **뒤**(같은 `VStack` 안)에 더한다:

```swift
            if selecting { bulkBar }
```

그리고 `readyToEvolve` 정의 **위**에:

```swift
    /// 고른 아이들을 한 번에 보내는 바. 단일 보내기와 같은 방식으로 **버튼 자리가 확인으로
    /// 바뀐다** — 이 앱에는 확인 다이얼로그 전례가 없고 팝오버 안에서는 `.help()` 조차 안 뜬다.
    @ViewBuilder
    private var bulkBar: some View {
        let chosen = store.state.box.filter { picked.contains($0.id) }
        let steps = BulkRelease.confirmSteps(for: chosen)
        VStack(alignment: .leading, spacing: 4) {
            if bulkStep > 0 {
                Text(l.bulkConfirm(chosen.count))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                // 위험한 아이들만 이름으로 — 스무 마리를 다 나열하면 아무도 안 읽는다.
                let names = BulkRelease.risky(chosen).map {
                    $0.displayName(speciesName: Self.speciesName($0, in: lines, store.language),
                                   store.language)
                }
                if !names.isEmpty {
                    Text(l.bulkConfirmRisky(names.joined(separator: " · ")))
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.orange)
                }
            }
            HStack(spacing: 6) {
                Text(l.bulkPicked(chosen.count, Self.pickedTotal(chosen, store: store)))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                Spacer()
                if bulkStep > 0 {
                    Button(l.sendCancel) { bulkStep = 0 }
                        .buttonStyle(.plain).font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Button(l.sendNow) {
                    if bulkStep < steps {
                        bulkStep += 1
                    } else {
                        store.releaseManyToProfessor(individualIDs: Array(picked))
                        // 모드에는 머무른다 — 정리는 보통 한 번에 안 끝나고, 보낸 직후가
                        // 다음 것을 고르기 가장 좋은 순간이다. 담은 것만 비운다.
                        picked = []
                        bulkStep = 0
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(chosen.isEmpty ? Color.secondary : Color.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(chosen.isEmpty ? Color.secondary.opacity(0.15) : Color.accentColor,
                            in: RoundedRectangle(cornerRadius: 5))
                .disabled(chosen.isEmpty)
            }
        }
        .padding(.horizontal, 4)
    }

    /// 종 이름 — 라인이 아직 없으면 번호로 떨어진다(`Individual.displayName` 이 정한 폴백 형식).
    @MainActor static func speciesName(_ individual: Individual, in lines: [Int: EvoLine],
                                       _ lang: AppLanguage) -> String {
        lines[individual.displayLineID]?.localizedName(individual.displaySpeciesID, lang)
            ?? "#\(individual.displaySpeciesID)"
    }
```

- [ ] **Step 8: 테스트가 통과하는지 확인한다**

Run: `swift test --filter BulkReleaseTests`
Expected: PASS (16개)

- [ ] **Step 9: 전체 테스트와 경고를 확인한다**

Run: `swift build --build-tests 2>&1 | grep -i warning; swift test`
Expected: 경고 출력 없음, 전체 PASS. 특히 `BoxViewTests` 가 그대로 통과해야 한다
(`BoxCell` 시그니처가 바뀌었다).

- [ ] **Step 10: 실제 앱으로 눈으로 확인한다**

```bash
PTB_DEV=1 ./scripts/build-app.sh && open "./build/PokeDexBar Dev.app"
```

확인할 것 — 박스 헤더에 「선택」이 있고 누르면 모드가 켜지는가, 모드에서 칸을 누르면 상세가
안 열리고 체크만 붙는가, 파트너는 안 담기는가, 페이지를 넘겨도 담은 것이 유지되는가, 바에
마릿수와 포인트가 맞게 뜨는가, 이로치나 전설을 담으면 확인이 한 번 더 뜨고 그 이름이 보이는가,
보낸 뒤 모드는 남고 선택만 비는가.

> **`PTB_DEV=1` 이 필수다.** 없으면 릴리스 구성으로 지어 `/Applications` 의 실제 앱과 같은
> 세이브를 쓴다. 실제 세이브는 어떤 경우에도 손으로 고치지 않는다.

- [ ] **Step 11: 커밋**

```bash
git add Sources/PokeDexBar/Core/Localization.swift Sources/PokeDexBar/UI/BoxTabView.swift Tests/PokeDexBarTests/BulkReleaseTests.swift
git commit -m "feat: pick several Pokemon in the Box and send them together"
```

---

## 배포 전에 (이 계획의 범위 밖)

C 는 B 와 같은 릴리스에 실으면 `assets/professor-banner.png` 가 이미 새 파일이라 추가 에셋이
필요 없다. 다만 선택 모드가 새 표면이므로 박스 스크린샷을 다시 찍을지는 배포 때 판단한다.
README ×3 과 랜딩도 그때 함께 간다.
