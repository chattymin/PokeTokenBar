# 확정 알 교환권 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 더 진화할 곳이 없는 개체가 경험치를 모으면 자기 라인의 알을 하나 불러오는 교환권을 받는다.

**Architecture:** `EggVoucher`(baseID + grade)를 `PlayerState.eggVouchers` 배열에 쌓는다. 지급은
진화와 같은 방식으로 사용자가 누를 때 일어난다(`claimEggVoucher`) — 최종형 판정에 네트워크에서 오는
`EvoLine` 이 필요해 자동 지급 경로에서는 판정 자체가 불가능하기 때문이다. 사용은 기존
`startEgg` 에서 값 치르는 부분을 뗀 `placeEgg` 를 부른다.

**Tech Stack:** Swift 6 / SwiftPM / SwiftUI / XCTest. 외부 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-08-11-professor-and-vouchers-design.md` 의 **A 절**만 구현한다.
B 절(박사에게 보내기)은 이 계획의 범위가 **아니다**.

## Global Constraints

- **커밋 메시지는 영어.** 한국어로 지시받아도 커밋·PR 산출물은 영어로 쓴다 (`CLAUDE.md` 기여 언어 규약).
- **코드 주석은 한국어.** 이 저장소의 기존 주석과 같은 밀도·어투로 쓴다.
- **사용자에게 보이는 문자열은 전부 `L.t(ko, en, ja)` 로 3개 언어를 동시에 채운다.** `Sources/PokeDexBar/Core/Localization.swift`.
- **빌드 경고 0.** 경고가 하나라도 남으면 그 태스크는 완료가 아니다.
- **`PlayerState` 에 필드를 더하면 반드시 `init(from:)`(관대 디코더)에도 줄을 더한다.** 이 저장소가
  `disguisedAs`·`birthForm`·`formBroken` 으로 **세 번** 밟은 부류다 — 저장은 되는데 못 읽는다.
  합성 `encode(to:)` 는 자동으로 새 필드를 쓰지만 수동 `init(from:)` 은 자동으로 안 읽는다.
- **`SaveTransfer` 라는 타입은 이 코드베이스에 없다.** `CLAUDE.md` 가 값 범위 검증을 이야기하며
  그 이름을 쓰지만 소스에 존재하지 않고, 세이브 가져오기 경로도 없다(2026-08-11 확인). 값 범위
  검증은 `PlayerState.init(from:)` 안 `slots` 를 자르는 자리에서 한다.
- **실제 세이브 파일을 절대 건드리지 않는다.** 테스트는 `FileManager.default.temporaryDirectory`
  아래 임시 파일과 `#if DEBUG` 헬퍼(`addForTesting`)만 쓴다.
- **테스트 실행:** `swift test --filter EggVoucherTests` / 전체는 `swift test`.

---

## File Structure

| 파일 | 책임 |
|---|---|
| `Sources/PokeDexBar/Player/EggVoucher.swift` **(신규)** | 교환권이 무엇이고 언제 벌리는가 — 자료형과 임계 규칙. 저장·UI 를 모른다. |
| `Sources/PokeDexBar/Player/PlayerState.swift` **(수정)** | `eggVouchers` 필드 + 관대 디코딩 + 값 범위 검증. |
| `Sources/PokeDexBar/Player/PlayerStore+Eggs.swift` **(수정)** | `startEgg` 에서 슬롯 배치를 `placeEgg` 로 떼어낸다. |
| `Sources/PokeDexBar/Player/PlayerStore+Vouchers.swift` **(신규)** | 지급·사용 동작. `PlayerStore+Evolution.swift` 와 같은 모양. |
| `Sources/PokeDexBar/Core/Localization.swift` **(수정)** | ko/en/ja 문구. |
| `Sources/PokeDexBar/UI/IndividualDetailView.swift` **(수정)** | 진행 막대 + 받기 버튼. |
| `Sources/PokeDexBar/UI/BoxTabView.swift` **(수정)** | 칸 배지. |
| `Sources/PokeDexBar/UI/EggSlotsView.swift` **(수정)** | 빈 슬롯에서 쓰기. |
| `Tests/PokeDexBarTests/EggVoucherTests.swift` **(신규)** | 전 태스크의 테스트가 여기 모인다. |

---

## Task 1: 교환권 자료형과 저장

**Files:**
- Create: `Sources/PokeDexBar/Player/EggVoucher.swift`
- Modify: `Sources/PokeDexBar/Player/PlayerState.swift` (필드 선언부, `init(from:)`, 파일 끝 `Lossy*` 래퍼들 옆)
- Test: `Tests/PokeDexBarTests/EggVoucherTests.swift` (신규)

**Interfaces:**
- Consumes: `ExpBalance.threshold(grade:stageIndex:)`, `Grade`
- Produces:
  - `struct EggVoucher: Codable, Sendable, Equatable, Hashable { var baseID: Int; var grade: Grade }`
  - `static func EggVoucher.threshold(grade: Grade) -> Int`
  - `PlayerState.eggVouchers: [EggVoucher]`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`Tests/PokeDexBarTests/EggVoucherTests.swift` 를 새로 만든다.

```swift
import XCTest
@testable import PokeDexBar

/// 확정 알 교환권 — 더 진화할 곳이 없는 개체가 경험치를 모아 자기 라인의 알을 부른다.
@MainActor
final class EggVoucherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(seed: UInt64 = 1) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voucher-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: seed), now: { self.now })
    }

    // MARK: 임계

    /// **진화 임계와 같은 환율이다.** 최종진화체에 갇힌 경험치가 새 환율이 아니라
    /// 진화와 같은 값으로 다시 흐르게 하는 것이 이 기능의 요점이라, 등급 기본값을 그대로 쓴다.
    func testThresholdMatchesTheFirstEvolutionStep() {
        for grade in Grade.allCases {
            XCTAssertEqual(EggVoucher.threshold(grade: grade),
                           ExpBalance.threshold(grade: grade, stageIndex: 0),
                           "\(grade) 의 교환권 임계가 진화 기본값과 다르다")
        }
    }

    /// 표에 적힌 절대값 — 위 테스트는 두 식이 같이 틀려도 통과하므로 값 자체를 따로 못박는다.
    func testThresholdValues() {
        XCTAssertEqual(EggVoucher.threshold(grade: .common), 50_000_000)
        XCTAssertEqual(EggVoucher.threshold(grade: .rare), 100_000_000)
        XCTAssertEqual(EggVoucher.threshold(grade: .epic), 200_000_000)
        XCTAssertEqual(EggVoucher.threshold(grade: .legendary), 400_000_000)
    }

    // MARK: 저장

    /// **앱을 껐다 켜도 교환권이 남는다.** 관대 디코더에 줄을 안 더하면 저장은 되고 읽기만
    /// 빠져서 재기동마다 교환권이 사라진다 — 이 저장소가 세 번 밟은 부류다.
    func testVouchersSurviveARestart() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voucher-save-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        store.mutate { $0.eggVouchers = [EggVoucher(baseID: 4, grade: .epic),
                                         EggVoucher(baseID: 4, grade: .epic)] }

        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertEqual(reloaded.state.eggVouchers,
                       [EggVoucher(baseID: 4, grade: .epic), EggVoucher(baseID: 4, grade: .epic)],
                       "다시 켜니 교환권이 사라졌다")
    }

    /// 말이 안 되는 종 번호는 경계에서 버린다 — 관대 디코딩의 짝.
    /// **개수는 안 자른다**(도감·인벤토리와 같은 이유로, 항목을 자르면 데이터 손실이다).
    func testBogusVouchersAreDroppedButValidOnesSurvive() throws {
        let json = """
        {"eggVouchers":[{"baseID":0,"grade":"epic"},{"baseID":4,"grade":"epic"}]}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.eggVouchers, [EggVoucher(baseID: 4, grade: .epic)])
    }

    /// 한 장이 깨져도 나머지는 살아남는다 — 박스·알과 같은 원소 단위 관대 디코딩.
    func testOneMalformedVoucherDoesNotDropTheRest() throws {
        let json = """
        {"eggVouchers":[{"baseID":4},{"baseID":25,"grade":"common"}]}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.eggVouchers, [EggVoucher(baseID: 25, grade: .common)],
                       "깨진 한 장 때문에 전부 날아갔다")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter EggVoucherTests`
Expected: 컴파일 실패 — `cannot find 'EggVoucher' in scope`

- [ ] **Step 3: `EggVoucher.swift` 를 만든다**

```swift
import Foundation

/// 자기 라인의 알을 하나 불러오는 표.
///
/// **왜 있나:** 최종진화체는 경험치를 계속 버는데 쓸 데가 없다 — `evolutionChoices` 가 빈
/// 배열이라 `canEvolve` 가 참이 되어도 갈 곳이 없다. 다 키운 아이일수록 곁에 둘 이유가 없어지는,
/// 방향이 거꾸로 된 유인이었다. 이 표가 그 경험치를 다시 흐르게 한다.
///
/// **왜 등급을 같이 들고 다니나:** 종→등급 판정(`EggBalance` 의 종 등급)은 네트워크로 오는
/// 베이스 인덱스를 요구한다. 쓰는 시점에 그걸 요구하면 오프라인에서 교환권을 못 쓴다. 지급하는
/// 시점에는 개체가 손에 있으므로 `Individual.grade`(태어날 때 그 라인에서 정해진 값)를 받아 둔다.
struct EggVoucher: Codable, Sendable, Equatable, Hashable {
    /// 불러올 종 — 그 개체의 `baseID` 다. 리자몽은 파이리를, 라프라스는 라프라스를 부른다.
    var baseID: Int
    /// 알의 등급. 부화 시간이 여기서 나온다.
    var grade: Grade

    /// 교환권 한 장 값. **진화 한 단계와 같은 환율**(`stageIndex: 0` 의 기본값)이다 —
    /// 새 환율을 발명하지 않는 것이 요점이다. 최종형의 진화 임계(기본값 × 3)를 쓰지 않는 이유는,
    /// 그게 "갈 곳도 없는데 세 배를 내라"가 되기 때문이다.
    static func threshold(grade: Grade) -> Int {
        ExpBalance.threshold(grade: grade, stageIndex: 0)
    }

    /// 말이 되는 값인가. 관대 디코딩의 짝 — 종 번호가 1 미만이면 스프라이트도 이름도 없다.
    var isSane: Bool { baseID >= 1 }
}
```

- [ ] **Step 4: `PlayerState` 에 필드를 더한다**

`Sources/PokeDexBar/Player/PlayerState.swift` 의 `var inventory: [String: Int] = [:]` 선언 **아래**에
더한다:

```swift
    /// 확정 알 교환권. 장수는 원소 개수다 — 같은 종 두 장이면 원소가 둘.
    /// `inventory`(도구용 문자열 키)와 섞지 않는다 — 종 번호가 키인 다른 성격의 물건이라,
    /// 가방 탭이 모르는 키를 만나게 된다.
    var eggVouchers: [EggVoucher] = []
```

- [ ] **Step 5: 관대 디코더에 줄을 더한다**

같은 파일 `init(from decoder: Decoder)` 안, `inventory = value(.inventory, [:])` **바로 아래**:

```swift
        // 교환권도 박스·알과 같은 이유로 원소 단위 관대 디코딩한다 — 한 장이 깨졌다고 나머지
        // 교환권까지 통째로 날아가면 안 된다(한 장이 5000만 토큰어치다). 값 범위 검증(`isSane`)이
        // 짝으로 붙는다: 항목이므로 개수는 안 자르고, 말이 안 되는 원소만 버린다.
        let wrappedVouchers = (try? c.decode([LossyEggVoucher].self, forKey: .eggVouchers)) ?? []
        eggVouchers = wrappedVouchers.compactMap(\.voucher)
```

- [ ] **Step 6: `LossyEggVoucher` 래퍼를 더한다**

같은 파일 맨 아래, `private struct LossyEgg` **바로 뒤**:

```swift
/// `[EggVoucher]` 원소 단위 관대 디코딩 래퍼 — `LossyEgg` 와 같은 패턴에, 값 범위 검증을 겸한다.
private struct LossyEggVoucher: Decodable {
    let voucher: EggVoucher?
    init(from decoder: Decoder) throws {
        let decoded = try? EggVoucher(from: decoder)
        voucher = decoded?.isSane == true ? decoded : nil
    }
}
```

- [ ] **Step 7: 테스트가 통과하는지 확인한다**

Run: `swift test --filter EggVoucherTests`
Expected: PASS (4개 테스트)

- [ ] **Step 8: 전체 테스트와 경고를 확인한다**

Run: `swift build 2>&1 | grep -i warning; swift test`
Expected: 경고 출력 없음, 전체 PASS

- [ ] **Step 9: 커밋**

```bash
git add Sources/PokeDexBar/Player/EggVoucher.swift Sources/PokeDexBar/Player/PlayerState.swift Tests/PokeDexBarTests/EggVoucherTests.swift
git commit -m "feat: add the egg voucher type and persist it"
```

---

## Task 2: `startEgg` 에서 슬롯 배치를 떼어낸다

`startEgg` 은 본문에 `spentTokens += EggBalance.drawPrice` 를 포함한다. 교환권 경로가 그대로
부르면 교환권을 쓰고 토큰까지 낸다.

**Files:**
- Modify: `Sources/PokeDexBar/Player/PlayerStore+Eggs.swift:18-33`
- Test: `Tests/PokeDexBarTests/EggVoucherTests.swift`

**Interfaces:**
- Consumes: `PlayerStore.freeSlots`, `PlayerStore.canDraw`, `EggBalance.duration(_:)`, `HatchSpeedup.present(in:)`
- Produces:
  - `func placeEgg(grade: Grade, speciesID: Int, shiny: Bool) -> Egg?` — 값과 무관하게 슬롯에 넣는다
  - `func startEgg(grade: Grade, speciesID: Int, shiny: Bool) -> Egg?` — 시그니처·동작 그대로 유지

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`EggVoucherTests.swift` 에 `// MARK: 저장` 섹션 뒤로 더한다. `giveWallet` 은 아래 태스크들도 쓴다.

```swift
    // MARK: 슬롯 배치와 값 치르기의 분리

    /// 지갑을 채운다 — `update` 의 기준선을 잡고 그 위로 사용량을 올린다.
    private func giveWallet(_ store: PlayerStore, _ tokens: Int) {
        store.update(todayTokens: 0, todayDate: "d", hasUsageData: true)
        store.update(todayTokens: tokens, todayDate: "d", hasUsageData: true)
    }

    /// **`placeEgg` 는 값을 안 치른다.** 교환권 경로가 이걸 부른다 — `startEgg` 을 그대로
    /// 부르면 교환권을 쓰고 토큰까지 내게 된다.
    func testPlaceEggCostsNothing() {
        let store = makeStore()
        let before = store.state.spentTokens
        XCTAssertNotNil(store.placeEgg(grade: .common, speciesID: 4, shiny: false))
        XCTAssertEqual(store.state.spentTokens, before, "교환권 알에 토큰이 나갔다")
        XCTAssertEqual(store.state.eggs.count, 1)
    }

    /// **대조군 — `startEgg` 은 여전히 값을 치른다.** 떼어내다 상점 뽑기가 공짜가 되는 것이
    /// 이 변경에서 가장 그럴듯한 사고다.
    func testStartEggStillCharges() {
        let store = makeStore()
        giveWallet(store, EggBalance.drawPrice * 2)
        let before = store.state.spentTokens
        XCTAssertNotNil(store.startEgg(grade: .common, speciesID: 4, shiny: false))
        XCTAssertEqual(store.state.spentTokens, before + EggBalance.drawPrice,
                       "상점 뽑기가 공짜가 됐다")
    }

    /// 지갑이 비어도 `placeEgg` 는 된다 — 교환권이 값이기 때문이다.
    func testPlaceEggWorksWithAnEmptyWallet() {
        let store = makeStore()
        XCTAssertEqual(store.state.wallet, 0)
        XCTAssertNotNil(store.placeEgg(grade: .common, speciesID: 4, shiny: false))
    }

    /// 빈 슬롯이 없으면 둘 다 못 넣는다.
    func testPlaceEggNeedsAFreeSlot() {
        let store = makeStore()
        for _ in 0..<store.state.slots {
            XCTAssertNotNil(store.placeEgg(grade: .common, speciesID: 4, shiny: false))
        }
        XCTAssertNil(store.placeEgg(grade: .common, speciesID: 4, shiny: false))
    }

    /// **교환권 알도 부화 감면을 받는다.** 감면 계산이 `startEgg` 안에 있으므로, 떼어내면서
    /// 값 치르는 쪽에 남겨두기 쉬운 자리다.
    func testPlaceEggGetsTheHatchSpeedup() throws {
        let store = makeStore()
        // 마그마그(불꽃몸 계열)를 박스에 넣으면 감면이 걸린다.
        store.addForTesting(Individual(baseID: 218, speciesID: 218, pathIDs: [218],
                                       nature: .hardy, obtainedAt: now, grade: .common))
        let egg = try XCTUnwrap(store.placeEgg(grade: .common, speciesID: 4, shiny: false))
        XCTAssertEqual(egg.hatchesAt.timeIntervalSince(now),
                       EggBalance.duration(.common) * HatchSpeedup.multiplier,
                       accuracy: 1, "교환권 알이 감면을 못 받았다")
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter EggVoucherTests`
Expected: 컴파일 실패 — `value of type 'PlayerStore' has no member 'placeEgg'`

- [ ] **Step 3: `PlayerStore+Eggs.swift` 의 `startEgg` 을 둘로 나눈다**

`Sources/PokeDexBar/Player/PlayerStore+Eggs.swift` 의 `startEgg`(18~33행)를 통째로 아래로 바꾼다:

```swift
    /// 값과 무관하게 알을 슬롯에 넣는다. 빈 슬롯이 없으면 아무것도 하지 않고 nil.
    ///
    /// **값 치르기와 나뉘어 있는 이유:** 확정 알 교환권은 교환권이 값이라 토큰이 안 든다.
    /// 부화 감면은 여기 있으므로 어느 경로로 들어온 알이든 똑같이 받는다.
    @discardableResult
    func placeEgg(grade: Grade, speciesID: Int, shiny: Bool) -> Egg? {
        guard freeSlots > 0 else { return nil }
        let started = currentDate()
        // 알을 빨리 깨우는 아이를 이미 데리고 있으면 처음부터 절반으로 시작한다.
        let full = EggBalance.duration(grade)
        let span = HatchSpeedup.present(in: state.box) ? full * HatchSpeedup.multiplier : full
        let egg = Egg(grade: grade, speciesID: speciesID, shiny: shiny,
                      startedAt: started, hatchesAt: started.addingTimeInterval(span))
        mutate { $0.eggs.append(egg) }
        return egg
    }

    /// 값을 치르고 알을 슬롯에 넣는다. 재화가 모자라거나 빈 슬롯이 없으면 아무것도 하지 않고 nil.
    @discardableResult
    func startEgg(grade: Grade, speciesID: Int, shiny: Bool) -> Egg? {
        guard canDraw else { return nil }
        guard let egg = placeEgg(grade: grade, speciesID: speciesID, shiny: shiny) else { return nil }
        mutate { $0.spentTokens += EggBalance.drawPrice }
        return egg
    }
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `swift test --filter EggVoucherTests`
Expected: PASS (9개 테스트)

- [ ] **Step 5: 기존 알 테스트가 안 깨졌는지 확인한다**

Run: `swift test`
Expected: 전체 PASS. 특히 상점 뽑기·부화 관련 기존 테스트가 전부 통과해야 한다.

- [ ] **Step 6: 커밋**

```bash
git add Sources/PokeDexBar/Player/PlayerStore+Eggs.swift Tests/PokeDexBarTests/EggVoucherTests.swift
git commit -m "refactor: split egg placement from paying for it"
```

---

## Task 3: 지급과 사용

**Files:**
- Create: `Sources/PokeDexBar/Player/PlayerStore+Vouchers.swift`
- Test: `Tests/PokeDexBarTests/EggVoucherTests.swift`

**Interfaces:**
- Consumes: `EggVoucher.threshold(grade:)`, `PlayerStore.evolutionChoices(_:line:)`,
  `PlayerStore.placeEgg(grade:speciesID:shiny:)`, `PlayerStore.freeSlots`,
  `PlayerStore.nextRandomUnit()`, `EggBalance.rollShiny(_:hasCharm:)`
- Produces:
  - `func canClaimEggVoucher(_ individual: Individual, line: EvoLine) -> Bool`
  - `@discardableResult func claimEggVoucher(individualID: UUID, line: EvoLine) -> Bool`
  - `@discardableResult func redeemEggVoucher(baseID: Int) -> Egg?`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`EggVoucherTests.swift` 에 더한다.

```swift
    // MARK: 지급

    /// 파이리 → 리자드 → 리자몽 (일직선). 리자몽 노드에는 자식이 없다 = 최종형.
    private func charLine() -> EvoLine {
        EvoLine(baseID: 4,
                tree: EvoNode(speciesID: 4, children: [
                    EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])]),
                ]),
                rarity: .rare, names: [:])
    }

    /// 리자몽 한 마리를 박스에 넣고 돌려준다.
    private func charizard(_ store: PlayerStore, exp: Int) -> Individual {
        var individual = Individual(baseID: 4, speciesID: 6, pathIDs: [4, 5, 6],
                                    nature: .hardy, obtainedAt: now, grade: .epic)
        individual.exp = exp
        store.addForTesting(individual)
        return individual
    }

    /// **진화할 곳이 있으면 못 받는다.** 경험치는 진화에 쓰는 것이 먼저다.
    func testAnIndividualThatCanStillEvolveEarnsNothing() {
        let store = makeStore()
        var charmander = Individual(baseID: 4, speciesID: 4, pathIDs: [4],
                                    nature: .hardy, obtainedAt: now, grade: .epic)
        charmander.exp = EggVoucher.threshold(grade: .epic) * 10
        store.addForTesting(charmander)

        XCTAssertFalse(store.canClaimEggVoucher(charmander, line: charLine()))
        XCTAssertFalse(store.claimEggVoucher(individualID: charmander.id, line: charLine()))
        XCTAssertTrue(store.state.eggVouchers.isEmpty)
    }

    /// 최종형이어도 경험치가 모자라면 못 받는다.
    func testNotEnoughExpEarnsNothing() {
        let store = makeStore()
        let charizard = charizard(store, exp: EggVoucher.threshold(grade: .epic) - 1)
        XCTAssertFalse(store.canClaimEggVoucher(charizard, line: charLine()))
        XCTAssertFalse(store.claimEggVoucher(individualID: charizard.id, line: charLine()))
    }

    /// 최종형 + 경험치가 찼으면 받는다. **교환권은 `baseID` 를 가리킨다** — 리자몽이
    /// 부르는 것은 파이리 알이다. 이게 이 기능의 존재 이유(도감 구멍 메우기)다.
    func testAFullyEvolvedIndividualClaimsAVoucherForItsBase() {
        let store = makeStore()
        let charizard = charizard(store, exp: EggVoucher.threshold(grade: .epic))
        XCTAssertTrue(store.canClaimEggVoucher(charizard, line: charLine()))
        XCTAssertTrue(store.claimEggVoucher(individualID: charizard.id, line: charLine()))
        XCTAssertEqual(store.state.eggVouchers, [EggVoucher(baseID: 4, grade: .epic)])
    }

    /// **경험치는 임계만큼만 줄고 초과분은 남는다** — 진화의 이월과 같다.
    /// 이게 없으면 오래 비워 둔 사용자가 쌓아 둔 경험치를 한 장에 통째로 잃는다.
    func testExpCarriesOverSoVouchersCanBeClaimedInARow() {
        let store = makeStore()
        let threshold = EggVoucher.threshold(grade: .epic)
        let charizard = charizard(store, exp: threshold * 2 + 7)

        XCTAssertTrue(store.claimEggVoucher(individualID: charizard.id, line: charLine()))
        XCTAssertEqual(store.state.box.first { $0.id == charizard.id }?.exp, threshold + 7)

        XCTAssertTrue(store.claimEggVoucher(individualID: charizard.id, line: charLine()))
        XCTAssertEqual(store.state.box.first { $0.id == charizard.id }?.exp, 7)
        XCTAssertEqual(store.state.eggVouchers.count, 2)

        XCTAssertFalse(store.claimEggVoucher(individualID: charizard.id, line: charLine()))
        XCTAssertEqual(store.state.eggVouchers.count, 2, "경험치가 없는데 세 장째가 나왔다")
    }

    /// 박스에 없는 개체는 지급 대상이 아니다.
    func testClaimingForAnUnknownIndividualDoesNothing() {
        let store = makeStore()
        XCTAssertFalse(store.claimEggVoucher(individualID: UUID(), line: charLine()))
        XCTAssertTrue(store.state.eggVouchers.isEmpty)
    }

    // MARK: 사용

    /// **종이 확정이다 — 시드를 바꿔도 같은 종이 나온다.** 이 확정성이 기능의 이름 그 자체다.
    func testTheRedeemedEggIsAlwaysTheVouchersSpecies() {
        for seed in UInt64(1)...20 {
            let store = makeStore(seed: seed)
            store.mutate { $0.eggVouchers = [EggVoucher(baseID: 4, grade: .epic)] }
            let egg = store.redeemEggVoucher(baseID: 4)
            XCTAssertEqual(egg?.speciesID, 4, "시드 \(seed) 에서 다른 종이 나왔다")
            XCTAssertEqual(egg?.grade, .epic)
        }
    }

    /// 쓰면 한 장만 없어진다.
    func testRedeemingConsumesExactlyOneVoucher() {
        let store = makeStore()
        store.mutate { $0.eggVouchers = [EggVoucher(baseID: 4, grade: .epic),
                                         EggVoucher(baseID: 4, grade: .epic),
                                         EggVoucher(baseID: 25, grade: .common)] }
        XCTAssertNotNil(store.redeemEggVoucher(baseID: 4))
        XCTAssertEqual(store.state.eggVouchers,
                       [EggVoucher(baseID: 4, grade: .epic), EggVoucher(baseID: 25, grade: .common)])
    }

    /// 없는 교환권을 쓰려 하면 실패하고, 알도 안 생긴다.
    func testRedeemingAVoucherYouDoNotHaveFails() {
        let store = makeStore()
        XCTAssertNil(store.redeemEggVoucher(baseID: 4))
        XCTAssertTrue(store.state.eggs.isEmpty)
    }

    /// **슬롯이 꽉 차면 실패하고 교환권은 그대로 남는다.** 차감만 되고 알이 안 생기면
    /// 5000만 토큰어치가 조용히 증발한다.
    func testRedeemingWithNoFreeSlotKeepsTheVoucher() {
        let store = makeStore()
        store.mutate { $0.eggVouchers = [EggVoucher(baseID: 4, grade: .epic)] }
        for _ in 0..<store.state.slots {
            store.placeEgg(grade: .common, speciesID: 1, shiny: false)
        }
        XCTAssertNil(store.redeemEggVoucher(baseID: 4))
        XCTAssertEqual(store.state.eggVouchers, [EggVoucher(baseID: 4, grade: .epic)],
                       "알도 못 받고 교환권만 사라졌다")
    }

    /// **이로치는 확정이 아니다.** 종만 확정이다 — 이로치까지 확정이면 이로치 부적이 무의미해진다.
    /// 시드를 넓게 돌려 갈리는지 본다.
    func testShinyIsStillRolled() {
        var results = Set<Bool>()
        for seed in UInt64(1)...400 {
            let store = makeStore(seed: seed)
            store.mutate {
                $0.ownsShinyCharm = true      // 확률을 올려 400회 안에 양쪽이 나오게 한다
                $0.eggVouchers = [EggVoucher(baseID: 4, grade: .epic)]
            }
            if let egg = store.redeemEggVoucher(baseID: 4) { results.insert(egg.shiny) }
        }
        XCTAssertEqual(results, [true, false], "이로치가 굴려지지 않고 고정돼 있다")
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter EggVoucherTests`
Expected: 컴파일 실패 — `value of type 'PlayerStore' has no member 'canClaimEggVoucher'`

- [ ] **Step 3: `PlayerStore+Vouchers.swift` 를 만든다**

```swift
import Foundation

/// 확정 알 교환권 — 지급과 사용.
///
/// **자동으로 지급되지 않는다.** 진화와 같은 방식으로 배지가 뜨고 사용자가 누를 때 지급된다.
/// 이유는 두 가지다. ① 최종형인지 아는 데 `EvoLine` 이 필요한데 그건 네트워크로 오고 UI 가
/// 비동기로 싣는다 — 사용량 갱신 경로(`update`)에는 라인이 없어 판정 자체가 불가능하다. 거기서
/// 판정하려면 "최종형인가"를 세이브에 캐시해야 하는데, 그건 네트워크에서 파생된 값을 영속 상태에
/// 굳히는 일이라 라인 데이터가 바뀌면 조용히 틀어진다. ② 같은 자리에서 같은 경험치를 쓰는 일이
/// 진화는 클릭, 교환권은 자동으로 갈리면 안 된다.
///
/// **기다린다고 손해 보지 않는다** — 경험치는 계속 쌓이고 지급은 `exp -= 임계` 이므로,
/// 한 주 만에 열어도 쌓인 만큼 연속으로 받는다.
extension PlayerStore {
    /// 이 개체가 교환권을 받을 수 있나. 최종형 판정에 라인이 필요하다.
    func canClaimEggVoucher(_ individual: Individual, line: EvoLine) -> Bool {
        // 정체를 숨기고 있는 개체는 제외한다 — 받은 라인은 **겉모습의 것**이라 후보 판정이
        // 성립하지 않고, 교환권에 적히는 종 이름이 정체를 흘린다.
        // (`IndividualDetailView.choices` 가 진화에 대해 같은 판단을 한다.)
        guard individual.disguisedAs == nil else { return false }
        guard evolutionChoices(individual, line: line).isEmpty else { return false }
        return individual.exp >= EggVoucher.threshold(grade: individual.grade)
    }

    /// 교환권 지급. 경험치를 임계만큼 깎고 한 장을 더한다. 조건을 못 채우면 아무것도 하지 않고 false.
    @discardableResult
    func claimEggVoucher(individualID: UUID, line: EvoLine) -> Bool {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        let individual = state.box[index]
        guard canClaimEggVoucher(individual, line: line) else { return false }
        mutate { state in
            // 초과분은 남긴다 — 진화와 같은 이월이다. 통째로 0 으로 만들면 오래 비워 둔
            // 사용자가 쌓아 둔 경험치를 한 장 값에 전부 잃는다.
            state.box[index].exp -= EggVoucher.threshold(grade: individual.grade)
            state.eggVouchers.append(EggVoucher(baseID: individual.baseID,
                                                grade: individual.grade))
        }
        return true
    }

    /// 교환권으로 알을 건다. 빈 슬롯이 없거나 그 종의 교환권이 없으면 nil — **이때 차감도 없다.**
    /// 같은 종이 여러 장이면 한 장만 없앤다.
    @discardableResult
    func redeemEggVoucher(baseID: Int) -> Egg? {
        guard let index = state.eggVouchers.firstIndex(where: { $0.baseID == baseID })
        else { return nil }
        let voucher = state.eggVouchers[index]
        // 종은 확정이지만 이로치는 평소 확률로 굴린다 — 확정으로 만들면 이로치 부적이 무의미해진다.
        let shiny = EggBalance.rollShiny(nextRandomUnit(), hasCharm: state.ownsShinyCharm)
        // 알을 먼저 세운다. 슬롯이 없어 실패하면 교환권을 안 쓴 채로 돌아간다.
        guard let egg = placeEgg(grade: voucher.grade, speciesID: voucher.baseID, shiny: shiny)
        else { return nil }
        mutate { $0.eggVouchers.remove(at: index) }
        return egg
    }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run: `swift test --filter EggVoucherTests`
Expected: PASS (19개 테스트)

- [ ] **Step 5: 가드가 진짜 판별하는지 확인한다 (되돌리기 검사)**

`claimEggVoucher` 의 `state.box[index].exp -= EggVoucher.threshold(grade: individual.grade)` 를
`state.box[index].exp = 0` 으로 잠시 바꾸고 실행한다.

Run: `swift test --filter EggVoucherTests`
Expected: `testExpCarriesOverSoVouchersCanBeClaimedInARow` **가 실패해야 한다.**
실패하지 않으면 그 테스트가 아무것도 지키지 않는 것이므로 테스트를 먼저 고친다.
확인했으면 원래 코드로 되돌린다.

- [ ] **Step 6: 전체 테스트와 경고를 확인한다**

Run: `swift build 2>&1 | grep -i warning; swift test`
Expected: 경고 출력 없음, 전체 PASS

- [ ] **Step 7: 커밋**

```bash
git add Sources/PokeDexBar/Player/PlayerStore+Vouchers.swift Tests/PokeDexBarTests/EggVoucherTests.swift
git commit -m "feat: claim and redeem guaranteed egg vouchers"
```

---

## Task 4: 화면 배선

동작이 다 있어도 누를 곳이 없으면 없는 기능이다. 이 저장소는 **"사탕이 상점에서 팔리는데 쓸 화면이
없던"** 결함을 겪었고, 그래서 `BoxCell` 이 `#if DEBUG` 로 생성 기록을 남긴다.

**Files:**
- Modify: `Sources/PokeDexBar/Core/Localization.swift`
- Modify: `Sources/PokeDexBar/UI/IndividualDetailView.swift:222-236` (`actions`)
- Modify: `Sources/PokeDexBar/UI/BoxTabView.swift:87-100` (`grid`), `:160-163` (`readyToEvolve` 옆), `:170-230` (`BoxCell`)
- Modify: `Sources/PokeDexBar/UI/EggSlotsView.swift:58-67` (`body` 의 슬롯 행), `:151-155` (`emptySlot`)
- Test: `Tests/PokeDexBarTests/EggVoucherTests.swift`

**Interfaces:**
- Consumes: `PlayerStore.canClaimEggVoucher(_:line:)`, `PlayerStore.claimEggVoucher(individualID:line:)`,
  `PlayerStore.redeemEggVoucher(baseID:)`, `EggVoucher.threshold(grade:)`
- Produces: UI 만 — 이후 태스크 없음

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`EggVoucherTests.swift` 에 더한다. 소스 스캔 테스트는 이 저장소가 "기능은 있는데 화면이 없다"를
기계로 막는 방식이다.

```swift
    // MARK: 화면 배선

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 상세 화면이 지급 경로에 닿아 있다 — 안 닿으면 교환권을 영원히 못 받는다.
    func testTheDetailViewReachesTheClaimPath() throws {
        let text = try source("Sources/PokeDexBar/UI/IndividualDetailView.swift")
        XCTAssertTrue(text.contains("claimEggVoucher"), "상세에 교환권 받기 버튼이 없다")
    }

    /// 알 슬롯이 사용 경로에 닿아 있다 — 안 닿으면 받은 교환권을 영원히 못 쓴다.
    func testTheEggSlotsReachTheRedeemPath() throws {
        let text = try source("Sources/PokeDexBar/UI/EggSlotsView.swift")
        XCTAssertTrue(text.contains("redeemEggVoucher"), "알 슬롯에 교환권 쓰기가 없다")
    }

    /// 박스 칸이 배지를 그린다 — 개체를 하나씩 열어보지 않아도 받을 수 있는 아이가 보인다.
    func testTheBoxCellShowsAVoucherBadge() throws {
        let text = try source("Sources/PokeDexBar/UI/BoxTabView.swift")
        XCTAssertTrue(text.contains("canClaimVoucher"), "박스 칸에 교환권 배지가 없다")
    }

    /// **`.help()` 를 쓰지 않는다.** 이 팝오버 안에서 툴팁은 뜨지 않는다(실사용 확인).
    /// 설명은 인라인 한 줄로 적는다 — 부화 감면 안내에서 이미 한 번 밟았다.
    func testNoTooltipsInTheTouchedViews() throws {
        for path in ["Sources/PokeDexBar/UI/EggSlotsView.swift",
                     "Sources/PokeDexBar/UI/IndividualDetailView.swift"] {
            XCTAssertFalse(try source(path).contains(".help("),
                           "\(path) 에 안 뜨는 툴팁이 들어왔다")
        }
    }

    /// 문구가 세 언어를 다 채운다. `AppLanguage` 는 `ko`·`en`·`ja` 세 케이스다
    /// (`systemDefault` 는 케이스가 아니라 static var 이므로 `allCases` 에 안 들어온다).
    func testStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.voucherSectionTitle.isEmpty, "\(lang)")
            XCTAssertFalse(l.voucherClaim.isEmpty, "\(lang)")
            XCTAssertFalse(l.voucherExplain.isEmpty, "\(lang)")
            XCTAssertFalse(l.voucherSlotBadge.isEmpty, "\(lang)")
        }
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter EggVoucherTests`
Expected: 컴파일 실패 — `value of type 'L' has no member 'voucherSectionTitle'`

- [ ] **Step 3: 문구를 더한다**

`Sources/PokeDexBar/Core/Localization.swift` 의 `var detailMaxStage` (205행) **바로 아래**:

```swift
    var voucherSectionTitle: String {
        t("확정 알 교환권", "Guaranteed Egg Voucher", "かくていタマゴこうかんけん")
    }
    var voucherClaim: String {
        t("교환권 받기", "Claim voucher", "こうかんけんをうけとる")
    }
    var voucherExplain: String {
        t("더 진화하지 않는 아이는 경험치를 모아 자기 알을 불러와요",
          "A fully evolved Pokémon turns its experience into an egg of its own line",
          "しんかしきったポケモンは けいけんちで じぶんのタマゴをよびます")
    }
    var voucherSlotBadge: String { t("교환권", "Voucher", "こうかんけん") }
```

- [ ] **Step 4: 상세 화면에 지급 자리를 만든다**

`Sources/PokeDexBar/UI/IndividualDetailView.swift` 의 `actions` 안에서 아래 두 줄을

```swift
            } else if line != nil, choices.isEmpty {
                Text(l.detailMaxStage).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
```

아래로 바꾼다:

```swift
            } else if let line, choices.isEmpty {
                voucherSection(line)
            }
```

그리고 `evolutionSection(_:)` 정의 **바로 위**에 더한다:

```swift
    /// 더 진화하지 않는 아이의 경험치가 가는 곳.
    ///
    /// 전에는 여기에 "더 진화하지 않아요" 한 줄만 있었다 — 그 아이의 경험치가 어디로 가는지
    /// 알 길이 없었고, 실제로 아무 데도 안 갔다. 이제 그 자리가 진행 막대가 된다.
    @ViewBuilder
    private func voucherSection(_ line: EvoLine) -> some View {
        let need = EggVoucher.threshold(grade: individual.grade)
        VStack(alignment: .leading, spacing: 4) {
            Text(l.detailMaxStage).font(.system(size: 9)).foregroundStyle(.tertiary)
            HStack {
                Text(l.voucherSectionTitle).font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text("\(TokenFormatter.compact(min(individual.exp, need))) / \(TokenFormatter.compact(need))")
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, Double(individual.exp) / Double(need)))
                .progressViewStyle(.linear).frame(height: 5)
            if store.canClaimEggVoucher(individual, line: line) {
                DetailActionButton(title: l.voucherClaim, prominent: true) {
                    store.claimEggVoucher(individualID: individual.id, line: line)
                }
            } else {
                Text(l.voucherExplain).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }
```

- [ ] **Step 5: 박스 칸에 배지를 단다**

`Sources/PokeDexBar/UI/BoxTabView.swift` 에서 세 곳을 고친다.

`readyToEvolve` 아래에 더한다:

```swift
    private func readyToClaimVoucher(_ individual: Individual) -> Bool {
        guard let line = lines[individual.baseID] else { return false }
        return store.canClaimEggVoucher(individual, line: line)
    }
```

`grid` 의 `BoxCell(...)` 호출에서 `canEvolve:` 줄 **아래**에 더한다:

```swift
                                canClaimVoucher: readyToClaimVoucher(individual),
```

`BoxCell` 에 저장 프로퍼티·`init` 인자·본문을 더한다. `let canEvolve: Bool` 아래:

```swift
    /// 교환권을 받을 수 있나 — 진화 배지와 같은 이유로 칸에서 보여야 한다.
    let canClaimVoucher: Bool
```

`init` 시그니처의 `canEvolve: Bool,` 뒤에 `canClaimVoucher: Bool,` 를 더하고 본문에
`self.canClaimVoucher = canClaimVoucher` 를 더한다. 그리고 `if canEvolve { ... }` 블록 뒤에:

```swift
                    // 진화와 교환권은 동시에 성립하지 않는다(하나는 갈 곳이 있을 때,
                    // 다른 하나는 없을 때) — 같은 귀퉁이를 써도 겹치지 않는다.
                    if canClaimVoucher {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                            .offset(x: 3, y: -2)
                    }
```

> `BoxCell(` 호출부는 `BoxTabView.swift:93` 한 곳뿐이다(2026-08-11 확인). 인자를 더한 뒤
> `grep -rn "BoxCell(" Sources Tests` 로 그대로인지 확인한다.

- [ ] **Step 6: 알 슬롯에서 쓸 수 있게 한다**

`Sources/PokeDexBar/UI/EggSlotsView.swift` 의 `emptySlot`(151~155행)을 아래로 바꾼다:

```swift
    /// 빈 슬롯. 쓸 수 있는 교환권이 있으면 누를 수 있는 칸이 된다.
    @ViewBuilder
    private var emptySlot: some View {
        if let voucher = store.state.eggVouchers.first {
            Button {
                store.redeemEggVoucher(baseID: voucher.baseID)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 13)).foregroundStyle(Color.accentColor)
                    Text(l.voucherSlotBadge).font(.system(size: 8)).foregroundStyle(.secondary)
                }
                .frame(width: Self.tileSize, height: Self.tileSize)
                .background(Color.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3]))
                .frame(width: Self.tileSize, height: Self.tileSize)
        }
    }
```

- [ ] **Step 7: 테스트가 통과하는지 확인한다**

Run: `swift test --filter EggVoucherTests`
Expected: PASS (24개 테스트)

- [ ] **Step 8: 전체 테스트와 경고를 확인한다**

Run: `swift build 2>&1 | grep -i warning; swift test`
Expected: 경고 출력 없음, 전체 PASS

- [ ] **Step 9: 실제 앱으로 눈으로 확인한다**

```bash
PTB_DEV=1 ./scripts/build-app.sh && open "./build/PokeDexBar Dev.app"
```

확인할 것 — 최종진화체를 박스에서 열어 진행 막대와 안내 문구가 보이는가, 임계에 닿은 개체에
받기 버튼과 칸 배지가 뜨는가, 교환권이 있을 때 빈 알 슬롯이 누를 수 있는 칸으로 바뀌는가.

> **`PTB_DEV=1` 이 필수다.** 이게 없으면 릴리스 구성으로 지어 `/Applications` 의 실제 앱과
> **같은 세이브**를 쓴다. 개발 빌드는 번들 id 가 달라 세이브가 따로 간다
> (`PokeDexBarDev/` vs `PokeDexBar/`). 실제 세이브는 어떤 경우에도 손으로 고치지 않는다 —
> 봉인이 깨져 모든 스프라이트가 뒤집힌다.
>
> `open` 은 환경변수를 자식에게 넘기지 않는다. 시드가 필요하면 `open --env KEY=VALUE` 를 쓴다.

- [ ] **Step 10: 커밋**

```bash
git add Sources/PokeDexBar/Core/Localization.swift Sources/PokeDexBar/UI/IndividualDetailView.swift Sources/PokeDexBar/UI/BoxTabView.swift Sources/PokeDexBar/UI/EggSlotsView.swift Tests/PokeDexBarTests/EggVoucherTests.swift
git commit -m "feat: show and spend guaranteed egg vouchers"
```

---

## 배포 전에 (이 계획의 범위 밖, 잊지 말 것)

`Sources/PokeDexBar/UI/` 를 건드린 `feat:` 커밋이 있으므로 **`assets/` 에 새 파일이 없으면
`release.sh` 가 중단한다**(프롬프트로 못 넘기는 하드 게이트). 교환권 화면을 새로 찍는다:

```bash
PTB_SCREENSHOTS=1 PTB_APP_VERSION=<버전> swift test --filter ScreenshotGeneratorTests
```

담기는 내용은 `Tests/PokeDexBarTests/ScreenshotGenerator.swift` 의 `ScreenshotFixture` 에서
고친다 — 최종진화체 하나와 교환권 한 장이 들어가야 화면이 의미를 갖는다.
