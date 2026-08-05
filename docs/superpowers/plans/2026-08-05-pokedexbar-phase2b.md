# PokeDexBar 2b 구현 계획 — 경제 (뽑기 · 시간 부화 · 상점)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 2a 가 만든 "스타터를 골라 키우는" 앱에 획득 루프를 붙인다 — 재화로 알을 뽑고, 실시간으로 부화시키고, 상점에서 슬롯과 아이템을 산다.

**Architecture:** 순수 밸런스(확률·시간·가격)와 상태 변경(지갑·슬롯·박스)을 나눈다. 종 추첨은 네트워크(베이스 인덱스)가 필요하므로 **호출부가 굴리고 스토어는 결과만 받는다** — 그래야 스토어가 시계·난수 주입만으로 테스트된다. 부화는 실시간이라 앱이 꺼진 동안의 경과를 실행 시 정산한다.

**Tech Stack:** Swift 6, SwiftUI + AppKit, UserNotifications, XCTest. 외부 의존성 없음.

## Global Constraints

- `swift-tools-version: 6.0`, 플랫폼 하한 `macOS 14`, 외부 Swift 의존성 없음
- 커밋 메시지는 **영어**, 코드 주석은 **한국어**
- 각 태스크는 `swift build`(경고 0)와 `swift test`(전부 통과)로 끝난다
- 알에서는 **미진화체만** 나온다 — 후보는 `evolves_from_species_id IS NULL` 로 걸러진 베이스 종
- 등급별 뽑기 확률: 커먼 55% / 레어 15% / 에픽 25% / 레전더리 5%
- 부화 시간: 커먼 30분 / 레어 2시간 / 에픽 6시간 / 레전더리 24시간
- 뽑기는 **빈 슬롯이 있어야** 돌릴 수 있다. 미부화 알 보관함은 없다
- 이로치 확률 1/64, 이로치 부적 보유 시 1/48
- 시간이 걸리는 것은 전부 **주입한 시계**로 테스트한다. 실제 대기 금지

---

### Task 1: 알 모델과 밸런스

**Files:**
- Create: `Sources/PokeDexBar/Player/Egg.swift`
- Create: `Sources/PokeDexBar/Player/EggBalance.swift`
- Modify: `Sources/PokeDexBar/Player/PlayerState.swift`
- Test: `Tests/PokeDexBarTests/EggBalanceTests.swift`

**Interfaces:**
- Consumes: `Grade`, `PlayerState` (2a)
- Produces:
  - `struct Egg: Identifiable, Codable, Sendable, Equatable` — `id, grade, speciesID, shiny, startedAt, hatchesAt`; `func isReady(at: Date) -> Bool`; `func remaining(at: Date) -> TimeInterval`
  - `enum EggBalance` — `static let drawPrice: Int`, `static let maxSlots: Int`, `static func duration(_ grade: Grade) -> TimeInterval`, `static func rollGrade(_ roll: Double) -> Grade`, `static func slotPrice(forSlotNumber: Int) -> Int?`, `static func rollShiny(_ roll: Double, hasCharm: Bool) -> Bool`
  - `PlayerState.eggs: [Egg]`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/EggBalanceTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

final class EggBalanceTests: XCTestCase {
    /// 확률표는 등급별 실제 종 수에 맞춘 값이다 — 누적 경계로 검증한다.
    func testGradeRollBoundaries() {
        XCTAssertEqual(EggBalance.rollGrade(0.0), .common)
        XCTAssertEqual(EggBalance.rollGrade(0.549), .common)
        XCTAssertEqual(EggBalance.rollGrade(0.55), .rare)
        XCTAssertEqual(EggBalance.rollGrade(0.699), .rare)
        XCTAssertEqual(EggBalance.rollGrade(0.70), .epic)
        XCTAssertEqual(EggBalance.rollGrade(0.949), .epic)
        XCTAssertEqual(EggBalance.rollGrade(0.95), .legendary)
        XCTAssertEqual(EggBalance.rollGrade(0.999), .legendary)
    }

    /// 범위 밖 입력(부동소수 오차)에도 등급이 나온다 — nil 이나 크래시로 새지 않는다.
    func testGradeRollClamps() {
        XCTAssertEqual(EggBalance.rollGrade(-0.5), .common)
        XCTAssertEqual(EggBalance.rollGrade(1.5), .legendary)
    }

    func testDurations() {
        XCTAssertEqual(EggBalance.duration(.common), 30 * 60)
        XCTAssertEqual(EggBalance.duration(.rare), 2 * 3600)
        XCTAssertEqual(EggBalance.duration(.epic), 6 * 3600)
        XCTAssertEqual(EggBalance.duration(.legendary), 24 * 3600)
    }

    /// 등급이 높을수록 오래 걸린다.
    func testDurationsIncreaseWithGrade() {
        XCTAssertLessThan(EggBalance.duration(.common), EggBalance.duration(.rare))
        XCTAssertLessThan(EggBalance.duration(.rare), EggBalance.duration(.epic))
        XCTAssertLessThan(EggBalance.duration(.epic), EggBalance.duration(.legendary))
    }

    /// 슬롯 가격은 4·5·6번째만 있고 그 위는 없다(상한 6).
    func testSlotPriceLadder() {
        XCTAssertEqual(EggBalance.slotPrice(forSlotNumber: 4), 500_000_000)
        XCTAssertEqual(EggBalance.slotPrice(forSlotNumber: 5), 1_500_000_000)
        XCTAssertEqual(EggBalance.slotPrice(forSlotNumber: 6), 4_000_000_000)
        XCTAssertNil(EggBalance.slotPrice(forSlotNumber: 7))
        XCTAssertNil(EggBalance.slotPrice(forSlotNumber: 3), "기본 3슬롯은 사는 게 아니다")
    }

    /// 이로치는 1/64, 부적이 있으면 1/48 — 경계 바로 안팎을 잠근다.
    func testShinyOdds() {
        XCTAssertTrue(EggBalance.rollShiny(1.0 / 64 - 0.0001, hasCharm: false))
        XCTAssertFalse(EggBalance.rollShiny(1.0 / 64 + 0.0001, hasCharm: false))
        XCTAssertTrue(EggBalance.rollShiny(1.0 / 48 - 0.0001, hasCharm: true))
        XCTAssertFalse(EggBalance.rollShiny(1.0 / 48 + 0.0001, hasCharm: true))
    }

    /// 부적은 확률을 낮추지 않는다 — 같은 굴림이면 부적 쪽이 더 자주 이로치다.
    func testCharmNeverHurts() {
        for step in 0...100 {
            let roll = Double(step) / 100
            if EggBalance.rollShiny(roll, hasCharm: false) {
                XCTAssertTrue(EggBalance.rollShiny(roll, hasCharm: true))
            }
        }
    }
}

final class EggTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func egg(hatchesIn seconds: TimeInterval) -> Egg {
        Egg(grade: .common, speciesID: 1, shiny: false,
            startedAt: now, hatchesAt: now.addingTimeInterval(seconds))
    }

    func testReadyOnlyAfterHatchTime() {
        XCTAssertFalse(egg(hatchesIn: 10).isReady(at: now))
        XCTAssertTrue(egg(hatchesIn: 10).isReady(at: now.addingTimeInterval(10)))
        XCTAssertTrue(egg(hatchesIn: 10).isReady(at: now.addingTimeInterval(999)))
    }

    func testRemainingNeverNegative() {
        XCTAssertEqual(egg(hatchesIn: 60).remaining(at: now), 60, accuracy: 0.001)
        XCTAssertEqual(egg(hatchesIn: 60).remaining(at: now.addingTimeInterval(999)), 0)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter "EggBalanceTests|EggTests"`
Expected: FAIL — `cannot find 'EggBalance' in scope`

- [ ] **Step 3: Egg 구현**

`Sources/PokeDexBar/Player/Egg.swift`:

```swift
import Foundation

/// 부화 중인 알. 종과 이로치 여부는 **뽑는 순간** 정해 두고(스프라이트를 미리 받으려고)
/// 부화 때 공개한다.
struct Egg: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    var grade: Grade
    var speciesID: Int
    var shiny: Bool
    var startedAt: Date
    var hatchesAt: Date

    func isReady(at now: Date) -> Bool { now >= hatchesAt }

    /// 남은 시간. 이미 지났으면 0 — 음수가 화면에 새지 않게.
    func remaining(at now: Date) -> TimeInterval {
        max(0, hatchesAt.timeIntervalSince(now))
    }
}
```

- [ ] **Step 4: EggBalance 구현**

`Sources/PokeDexBar/Player/EggBalance.swift`:

```swift
import Foundation

/// 뽑기·부화·슬롯의 수치. 전부 순수 함수라 굴려 보지 않고도 잠글 수 있다.
enum EggBalance {
    static let drawPrice = 150_000_000
    static let maxSlots = 6
    /// 기본 슬롯 수(2a 의 `PlayerState.slots` 초기값과 같아야 한다).
    static let baseSlots = 3

    /// 등급별 뽑기 확률 — 그 등급이 가진 실제 베이스 종 수에 맞춘 값이다.
    /// (커먼 252종 · 레어 65종 · 에픽 136종 · 레전더리 88종)
    static let odds: [(grade: Grade, probability: Double)] = [
        (.common, 0.55), (.rare, 0.15), (.epic, 0.25), (.legendary, 0.05),
    ]

    /// 0…1 굴림 → 등급. 누적 경계로 자른다.
    static func rollGrade(_ roll: Double) -> Grade {
        var remaining = min(1, max(0, roll))
        for entry in odds {
            if remaining < entry.probability { return entry.grade }
            remaining -= entry.probability
        }
        return .legendary   // 부동소수 오차로 끝까지 온 경우
    }

    static func duration(_ grade: Grade) -> TimeInterval {
        switch grade {
        case .common: 30 * 60
        case .rare: 2 * 3600
        case .epic: 6 * 3600
        case .legendary: 24 * 3600
        }
    }

    /// N 번째 슬롯의 가격. 기본 슬롯(1~3)과 상한 초과는 nil — 살 수 없다.
    static func slotPrice(forSlotNumber slot: Int) -> Int? {
        switch slot {
        case 4: 500_000_000
        case 5: 1_500_000_000
        case 6: 4_000_000_000
        default: nil
        }
    }

    /// 이로치 판정. 부적은 분모를 낮춘다(1/64 → 1/48).
    static func rollShiny(_ roll: Double, hasCharm: Bool) -> Bool {
        roll < (hasCharm ? 1.0 / 48 : 1.0 / 64)
    }
}
```

- [ ] **Step 5: PlayerState 에 알 자리 추가**

`Sources/PokeDexBar/Player/PlayerState.swift` 에 저장 속성을 더한다(`slots` 옆).

```swift
    /// 부화 중인 알. 개수는 `slots` 를 넘지 않는다.
    var eggs: [Egg] = []
```

관대 디코딩 `init(from:)` 에도 한 줄 더한다.

```swift
        eggs = value(.eggs, [])
```

- [ ] **Step 6: 테스트 통과 + 커밋**

Run: `swift test --filter "EggBalanceTests|EggTests"` → 전부 통과, 이어서 `swift build && swift test`

```bash
git add -A
git commit -m "feat: add the egg model and draw balance

Eggs carry the species and shiny roll decided at draw time so the sprite can
be warmed before it is revealed. Grade odds follow how many base species each
grade actually holds rather than intuition, and every number here is a pure
function so the balance can be locked by tests instead of by playing."
```

---

### Task 2: 뽑기 — 지갑·슬롯·알 생성

**Files:**
- Create: `Sources/PokeDexBar/Player/PlayerStore+Eggs.swift`
- Test: `Tests/PokeDexBarTests/EggDrawTests.swift`

**Interfaces:**
- Consumes: `PlayerStore`(2a), `Egg`, `EggBalance` (Task 1)
- Produces (`PlayerStore` 확장):
  - `var canDraw: Bool` — 지갑이 충분하고 빈 슬롯이 있나
  - `var freeSlots: Int`
  - `@discardableResult func startEgg(grade: Grade, speciesID: Int, shiny: Bool) -> Egg?` — 값을 치르고 알을 슬롯에 넣는다. 종 추첨은 호출부가 한다(베이스 인덱스가 네트워크라서)
  - `func rollGradeAndShiny() -> (grade: Grade, shiny: Bool)` — 주입된 rng 로 굴린다

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/EggDrawTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

@MainActor
final class EggDrawTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(wallet: Int, slots: Int = 3, eggs: Int = 0) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("draw-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 7), now: { self.now })
        store.seedForTesting(wallet: wallet, slots: slots, eggs: eggs, at: now)
        return store
    }

    func testDrawSpendsWalletAndFillsASlot() {
        let store = makeStore(wallet: EggBalance.drawPrice)
        let egg = store.startEgg(grade: .rare, speciesID: 152, shiny: false)
        XCTAssertNotNil(egg)
        XCTAssertEqual(store.state.eggs.count, 1)
        XCTAssertEqual(store.state.wallet, 0)
        XCTAssertEqual(store.state.eggs.first?.speciesID, 152)
    }

    /// 부화 시각은 뽑은 시점 + 등급별 소요시간이다.
    func testHatchTimeComesFromGrade() {
        let store = makeStore(wallet: EggBalance.drawPrice)
        store.startEgg(grade: .epic, speciesID: 4, shiny: false)
        let egg = store.state.eggs.first!
        XCTAssertEqual(egg.startedAt, now)
        XCTAssertEqual(egg.hatchesAt.timeIntervalSince(now),
                       EggBalance.duration(.epic), accuracy: 1)
    }

    /// 재화가 모자라면 아무 일도 없다 — 지갑도 슬롯도 그대로다.
    func testCannotDrawWithoutFunds() {
        let store = makeStore(wallet: EggBalance.drawPrice - 1)
        XCTAssertFalse(store.canDraw)
        XCTAssertNil(store.startEgg(grade: .common, speciesID: 1, shiny: false))
        XCTAssertTrue(store.state.eggs.isEmpty)
        XCTAssertEqual(store.state.wallet, EggBalance.drawPrice - 1)
    }

    /// 슬롯이 꽉 차면 못 뽑는다 — 미부화 알 보관함은 없다.
    func testCannotDrawWithoutAFreeSlot() {
        let store = makeStore(wallet: 10_000_000_000, slots: 3, eggs: 3)
        XCTAssertEqual(store.freeSlots, 0)
        XCTAssertFalse(store.canDraw)
        XCTAssertNil(store.startEgg(grade: .common, speciesID: 1, shiny: false))
        XCTAssertEqual(store.state.eggs.count, 3)
        XCTAssertEqual(store.state.wallet, 10_000_000_000, "실패한 뽑기는 재화를 쓰지 않는다")
    }

    func testFreeSlotsCountsRemaining() {
        XCTAssertEqual(makeStore(wallet: 0, slots: 3, eggs: 1).freeSlots, 2)
        XCTAssertEqual(makeStore(wallet: 0, slots: 6, eggs: 6).freeSlots, 0)
    }

    /// 굴림은 주입한 난수를 쓴다 — 같은 시드면 같은 결과가 나와야 재현이 된다.
    func testRollIsDeterministicUnderSeed() {
        let a = makeStore(wallet: 0)
        let b = makeStore(wallet: 0)
        let first = a.rollGradeAndShiny()
        let second = b.rollGradeAndShiny()
        XCTAssertEqual(first.grade, second.grade)
        XCTAssertEqual(first.shiny, second.shiny)
    }

    func testDrawPersistsAcrossReload() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("draw-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 7), now: { self.now })
        store.seedForTesting(wallet: EggBalance.drawPrice, slots: 3, eggs: 0, at: now)
        store.startEgg(grade: .legendary, speciesID: 144, shiny: true)
        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 7), now: { self.now })
        XCTAssertEqual(reloaded.state.eggs.count, 1)
        XCTAssertEqual(reloaded.state.eggs.first?.speciesID, 144)
        XCTAssertTrue(reloaded.state.eggs.first?.shiny ?? false)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter EggDrawTests`
Expected: FAIL — `value of type 'PlayerStore' has no member 'seedForTesting'`

- [ ] **Step 3: 테스트 시드 헬퍼 추가**

`Sources/PokeDexBar/Player/PlayerStore.swift` 의 `addForTesting` 옆에 더한다.

```swift
    /// 테스트 전용 — 지갑·슬롯·알 개수를 직접 세팅한다(적립 경로를 돌리지 않고).
    func seedForTesting(wallet: Int, slots: Int, eggs: Int, at date: Date) {
        mutate {
            $0.earnedTokens = wallet
            $0.spentTokens = 0
            $0.slots = slots
            $0.eggs = (0..<eggs).map { _ in
                Egg(grade: .common, speciesID: 1, shiny: false, startedAt: date,
                    hatchesAt: date.addingTimeInterval(EggBalance.duration(.common)))
            }
        }
    }
```

- [ ] **Step 4: 뽑기 구현**

`Sources/PokeDexBar/Player/PlayerStore+Eggs.swift`:

```swift
import Foundation

/// 알 뽑기. 종 추첨은 여기서 하지 않는다 — 후보(베이스 인덱스)를 받아오는 일이 네트워크라서
/// 호출부가 굴리고, 스토어는 그 결과로 값을 치르고 슬롯을 채운다.
extension PlayerStore {
    var freeSlots: Int { max(0, state.slots - state.eggs.count) }

    var canDraw: Bool { state.wallet >= EggBalance.drawPrice && freeSlots > 0 }

    /// 등급과 이로치 여부를 굴린다. 주입한 rng 를 쓰므로 시드가 같으면 결과도 같다.
    func rollGradeAndShiny() -> (grade: Grade, shiny: Bool) {
        let gradeRoll = Double(nextRandomUnit())
        let shinyRoll = Double(nextRandomUnit())
        return (EggBalance.rollGrade(gradeRoll),
                EggBalance.rollShiny(shinyRoll, hasCharm: state.ownsShinyCharm))
    }

    /// 값을 치르고 알을 슬롯에 넣는다. 재화가 모자라거나 빈 슬롯이 없으면 아무것도 하지 않고 nil.
    @discardableResult
    func startEgg(grade: Grade, speciesID: Int, shiny: Bool) -> Egg? {
        guard canDraw else { return nil }
        let started = currentDate()
        let egg = Egg(grade: grade, speciesID: speciesID, shiny: shiny,
                      startedAt: started,
                      hatchesAt: started.addingTimeInterval(EggBalance.duration(grade)))
        mutate {
            $0.spentTokens += EggBalance.drawPrice
            $0.eggs.append(egg)
        }
        return egg
    }
}
```

`PlayerStore` 본체(`PlayerStore.swift`)에 확장이 쓸 두 창구를 더한다 — `rng`·`now` 가 private 이라
확장에서 직접 못 쓴다. **상태 변경은 이미 있는 `mutate { }` 창구를 쓴다**(`state` 는 `private(set)` 이라
확장에서 직접 못 바꾼다. `mutate` 가 저장까지 한다).

```swift
    /// 0…1 난수. 확장(뽑기)이 주입된 rng 를 쓰는 유일한 창구.
    func nextRandomUnit() -> Double {
        Double(rng.next() % 1_000_000) / 1_000_000
    }

    /// 주입된 시계. 확장이 시각을 얻는 유일한 창구.
    func currentDate() -> Date { now() }
```

- [ ] **Step 5: 테스트 통과 + 커밋**

Run: `swift test --filter EggDrawTests` → 전부 통과, 이어서 `swift build && swift test`

```bash
git add -A
git commit -m "feat: draw eggs against the wallet and the open slots

A draw only happens when there is money and a free slot — there is no
holding pen for undrawn eggs, so slots are what limits how many rolls are in
flight. The species roll stays with the caller because the candidate list
comes over the network; the store just charges and files the egg."
```

---

### Task 3: 시간 부화 — 경과 정산

**Files:**
- Create: `Sources/PokeDexBar/Player/PlayerStore+Hatching.swift`
- Test: `Tests/PokeDexBarTests/HatchingTests.swift`

**Interfaces:**
- Consumes: `PlayerStore`, `Egg`, `Individual`, `Grade`
- Produces (`PlayerStore` 확장):
  - `@discardableResult func settleHatches(at now: Date) -> [Individual]` — 시각이 지난 알을 전부 부화시켜 박스·도감에 넣고 부화한 개체들을 돌려준다
  - `var readyEggCount: Int`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/HatchingTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

@MainActor
final class HatchingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatch-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { self.now })
        store.seedForTesting(wallet: 100_000_000_000, slots: 6, eggs: 0, at: now)
        return store
    }

    private func addEgg(_ store: PlayerStore, grade: Grade, species: Int, shiny: Bool = false) {
        store.startEgg(grade: grade, speciesID: species, shiny: shiny)
    }

    func testEggHatchesAfterItsDuration() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        XCTAssertTrue(store.settleHatches(at: now).isEmpty, "아직 시간이 안 됐다")
        let hatched = store.settleHatches(at: now.addingTimeInterval(EggBalance.duration(.common)))
        XCTAssertEqual(hatched.count, 1)
        XCTAssertEqual(hatched.first?.speciesID, 1)
        XCTAssertTrue(store.state.eggs.isEmpty, "부화한 알은 슬롯을 비운다")
        XCTAssertEqual(store.state.box.count, 1)
        XCTAssertTrue(store.state.dex.contains(1))
    }

    /// 앱이 꺼져 있는 동안 여러 개가 동시에 익어도 한 번에 정산한다.
    func testAllRipeEggsHatchAtOnce() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        addEgg(store, grade: .rare, species: 4)
        addEgg(store, grade: .legendary, species: 144)
        let hatched = store.settleHatches(at: now.addingTimeInterval(3 * 3600))
        XCTAssertEqual(Set(hatched.map(\.speciesID)), [1, 4], "레전더리는 24시간이라 아직이다")
        XCTAssertEqual(store.state.eggs.count, 1)
        XCTAssertEqual(store.state.eggs.first?.speciesID, 144)
    }

    /// 부화한 개체는 알이 들고 있던 등급·이로치를 그대로 이어받는다.
    func testHatchedIndividualInheritsEggProperties() {
        let store = makeStore()
        addEgg(store, grade: .epic, species: 133, shiny: true)
        let hatched = store.settleHatches(at: now.addingTimeInterval(EggBalance.duration(.epic)))
        let individual = hatched.first!
        XCTAssertEqual(individual.grade, .epic)
        XCTAssertTrue(individual.shiny)
        XCTAssertEqual(individual.baseID, 133)
        XCTAssertEqual(individual.pathIDs, [133])
        XCTAssertEqual(individual.exp, 0)
    }

    /// 같은 종이 또 나와도 새 개체로 들어간다 — 중복이 정상이다.
    func testDuplicatesBecomeSeparateIndividuals() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        addEgg(store, grade: .common, species: 1)
        let hatched = store.settleHatches(at: now.addingTimeInterval(EggBalance.duration(.common)))
        XCTAssertEqual(hatched.count, 2)
        XCTAssertEqual(store.state.box.count, 2)
        XCTAssertNotEqual(store.state.box[0].id, store.state.box[1].id)
        XCTAssertEqual(store.state.dex.count, 1, "도감은 종 단위라 하나만 는다")
    }

    /// 정산은 여러 번 불러도 같은 알을 두 번 부화시키지 않는다.
    func testSettlingTwiceIsIdempotent() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 7)
        let later = now.addingTimeInterval(EggBalance.duration(.common))
        XCTAssertEqual(store.settleHatches(at: later).count, 1)
        XCTAssertEqual(store.settleHatches(at: later).count, 0)
        XCTAssertEqual(store.state.box.count, 1)
    }

    func testReadyEggCount() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        addEgg(store, grade: .legendary, species: 144)
        XCTAssertEqual(store.readyEggCount(at: now.addingTimeInterval(3600)), 1)
    }

    /// 부화 결과가 파일에 남아야 앱을 껐다 켜도 유지된다.
    func testHatchPersists() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatch-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { self.now })
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: now)
        store.startEgg(grade: .common, speciesID: 25, shiny: false)
        store.settleHatches(at: now.addingTimeInterval(EggBalance.duration(.common)))
        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { self.now })
        XCTAssertEqual(reloaded.state.box.count, 1)
        XCTAssertTrue(reloaded.state.eggs.isEmpty)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter HatchingTests`
Expected: FAIL — `value of type 'PlayerStore' has no member 'settleHatches'`

- [ ] **Step 3: 구현**

`Sources/PokeDexBar/Player/PlayerStore+Hatching.swift`:

```swift
import Foundation

/// 시간 부화. 알은 토큰이 아니라 실시간으로 깨지므로, 앱이 꺼져 있던 동안의 경과를
/// 실행 시점에 한 번에 정산한다.
extension PlayerStore {
    func readyEggCount(at now: Date) -> Int {
        state.eggs.count { $0.isReady(at: now) }
    }

    /// 시각이 지난 알을 전부 부화시킨다. 부화한 개체들을 돌려주고(알림·연출용) 슬롯을 비운다.
    /// 여러 번 불려도 같은 알을 두 번 부화시키지 않는다 — 부화한 알은 목록에서 사라진다.
    @discardableResult
    func settleHatches(at now: Date) -> [Individual] {
        let ripe = state.eggs.filter { $0.isReady(at: now) }
        guard !ripe.isEmpty else { return [] }
        let natures = PokemonNature.allCases
        var hatched: [Individual] = []
        for egg in ripe {
            let nature = natures[Int(nextRandomUnit() * Double(natures.count)) % natures.count]
            hatched.append(Individual(baseID: egg.speciesID, speciesID: egg.speciesID,
                                      pathIDs: [egg.speciesID], shiny: egg.shiny,
                                      nature: nature, exp: 0, obtainedAt: now, grade: egg.grade))
        }
        let hatchedIDs = Set(ripe.map(\.id))
        mutate {
            $0.box.append(contentsOf: hatched)
            for individual in hatched { $0.dex.insert(individual.speciesID) }
            $0.eggs.removeAll { hatchedIDs.contains($0.id) }
        }
        return hatched
    }
}
```

- [ ] **Step 4: 테스트 통과 + 커밋**

Run: `swift test --filter HatchingTests` → 전부 통과, 이어서 `swift build && swift test`

```bash
git add -A
git commit -m "feat: hatch eggs on wall-clock time

Eggs ripen while the app is closed, so settle every elapsed egg at once when
it next runs rather than counting ticks. The hatched individual inherits the
grade and shiny roll the egg was drawn with, and a repeat species becomes a
separate individual while the dex only counts it once."
```

---

### Task 4: 상점 — 슬롯 확장과 아이템

**Files:**
- Create: `Sources/PokeDexBar/Player/ShopItem.swift`
- Create: `Sources/PokeDexBar/Player/PlayerStore+Shop.swift`
- Test: `Tests/PokeDexBarTests/ShopTests.swift`

**Interfaces:**
- Consumes: `PlayerStore`, `EggBalance`, `Individual`
- Produces:
  - `enum ShopItem: String, CaseIterable, Sendable { case expCandy, shinyCandy, shinyCharm }` — `var price: Int`, `var label: String`, `var isConsumable: Bool`
  - `PlayerStore` 확장: `func buySlot() -> Bool`, `func buy(_ item: ShopItem) -> Bool`, `func count(of item: ShopItem) -> Int`, `func useExpCandy(on individualID: UUID) -> Bool`, `func useShinyCandy(on individualID: UUID) -> Bool`
  - `static let expCandyAmount = 100_000_000`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/ShopTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

@MainActor
final class ShopTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(wallet: Int, slots: Int = 3) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shop-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 5), now: { self.now })
        store.seedForTesting(wallet: wallet, slots: slots, eggs: 0, at: now)
        return store
    }

    private func addIndividual(_ store: PlayerStore, shiny: Bool = false) -> UUID {
        let individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], shiny: shiny,
                                    nature: .serious, exp: 0, obtainedAt: now, grade: .common)
        store.addForTesting(individual)
        return individual.id
    }

    // MARK: 슬롯

    func testBuyingASlotChargesTheLadderPrice() {
        let store = makeStore(wallet: 500_000_000, slots: 3)
        XCTAssertTrue(store.buySlot())
        XCTAssertEqual(store.state.slots, 4)
        XCTAssertEqual(store.state.wallet, 0)
    }

    func testSlotPriceRisesWithEachPurchase() {
        let store = makeStore(wallet: 6_000_000_000, slots: 3)
        XCTAssertTrue(store.buySlot())   // 4번째 500M
        XCTAssertTrue(store.buySlot())   // 5번째 1.5B
        XCTAssertTrue(store.buySlot())   // 6번째 4B
        XCTAssertEqual(store.state.slots, 6)
        XCTAssertEqual(store.state.wallet, 0)
    }

    /// 상한을 넘겨 살 수 없다.
    func testCannotBuyPastMaxSlots() {
        let store = makeStore(wallet: 100_000_000_000, slots: EggBalance.maxSlots)
        XCTAssertFalse(store.buySlot())
        XCTAssertEqual(store.state.slots, EggBalance.maxSlots)
        XCTAssertEqual(store.state.wallet, 100_000_000_000, "실패한 구매는 재화를 쓰지 않는다")
    }

    func testCannotBuySlotWithoutFunds() {
        let store = makeStore(wallet: 499_999_999, slots: 3)
        XCTAssertFalse(store.buySlot())
        XCTAssertEqual(store.state.slots, 3)
    }

    // MARK: 아이템

    func testBuyingAConsumableAddsToInventory() {
        let store = makeStore(wallet: ShopItem.expCandy.price * 2)
        XCTAssertTrue(store.buy(.expCandy))
        XCTAssertTrue(store.buy(.expCandy))
        XCTAssertEqual(store.count(of: .expCandy), 2)
        XCTAssertEqual(store.state.wallet, 0)
    }

    /// 이로치 부적은 보유형 — 한 번 사면 끝이고 두 번 살 수 없다.
    func testShinyCharmIsBoughtOnce() {
        let store = makeStore(wallet: ShopItem.shinyCharm.price * 2)
        XCTAssertTrue(store.buy(.shinyCharm))
        XCTAssertTrue(store.state.ownsShinyCharm)
        XCTAssertFalse(store.buy(.shinyCharm))
        XCTAssertEqual(store.state.wallet, ShopItem.shinyCharm.price)
    }

    func testCannotBuyWithoutFunds() {
        let store = makeStore(wallet: ShopItem.expCandy.price - 1)
        XCTAssertFalse(store.buy(.expCandy))
        XCTAssertEqual(store.count(of: .expCandy), 0)
    }

    // MARK: 사용

    func testExpCandyRaisesExperienceAndIsConsumed() {
        let store = makeStore(wallet: ShopItem.expCandy.price)
        let id = addIndividual(store)
        store.buy(.expCandy)
        XCTAssertTrue(store.useExpCandy(on: id))
        XCTAssertEqual(store.state.box.first { $0.id == id }?.exp, PlayerStore.expCandyAmount)
        XCTAssertEqual(store.count(of: .expCandy), 0)
    }

    func testCannotUseCandyYouDoNotHave() {
        let store = makeStore(wallet: 0)
        let id = addIndividual(store)
        XCTAssertFalse(store.useExpCandy(on: id))
        XCTAssertEqual(store.state.box.first { $0.id == id }?.exp, 0)
    }

    func testShinyCandyMakesTheIndividualShiny() {
        let store = makeStore(wallet: ShopItem.shinyCandy.price)
        let id = addIndividual(store)
        store.buy(.shinyCandy)
        XCTAssertTrue(store.useShinyCandy(on: id))
        XCTAssertTrue(store.state.box.first { $0.id == id }?.shiny ?? false)
        XCTAssertEqual(store.count(of: .shinyCandy), 0)
    }

    /// 이미 이로치면 쓸 수 없다 — 사탕을 헛되이 쓰지 않게.
    func testShinyCandyRejectsAlreadyShiny() {
        let store = makeStore(wallet: ShopItem.shinyCandy.price)
        let id = addIndividual(store, shiny: true)
        store.buy(.shinyCandy)
        XCTAssertFalse(store.useShinyCandy(on: id))
        XCTAssertEqual(store.count(of: .shinyCandy), 1, "쓰지 못했으면 사탕이 남는다")
    }

    /// 박스에 없는 개체에는 쓸 수 없다.
    func testUsingOnUnknownIndividualFails() {
        let store = makeStore(wallet: ShopItem.expCandy.price)
        store.buy(.expCandy)
        XCTAssertFalse(store.useExpCandy(on: UUID()))
        XCTAssertEqual(store.count(of: .expCandy), 1)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter ShopTests`
Expected: FAIL — `cannot find 'ShopItem' in scope`

- [ ] **Step 3: ShopItem 구현**

`Sources/PokeDexBar/Player/ShopItem.swift`:

```swift
import Foundation

/// 상점 품목(알 뽑기·슬롯 확장 제외 — 그 둘은 값이 상황에 따라 달라 따로 다룬다).
enum ShopItem: String, CaseIterable, Sendable {
    case expCandy, shinyCandy, shinyCharm

    var price: Int {
        switch self {
        case .expCandy: 500_000_000
        case .shinyCandy: 2_000_000_000
        case .shinyCharm: 3_000_000_000
        }
    }

    var label: String {
        switch self {
        case .expCandy: "경험치 사탕"
        case .shinyCandy: "반짝이는 사탕"
        case .shinyCharm: "이로치 부적"
        }
    }

    /// 부적은 보유형이라 개수를 세지 않고 한 번만 산다.
    var isConsumable: Bool { self != .shinyCharm }

    var detail: String {
        switch self {
        case .expCandy: "지정한 포켓몬에게 경험치를 줍니다"
        case .shinyCandy: "지정한 포켓몬을 이로치로 만듭니다"
        case .shinyCharm: "이후 부화의 이로치 확률이 올라갑니다"
        }
    }
}
```

- [ ] **Step 4: 상점 동작 구현**

`Sources/PokeDexBar/Player/PlayerStore+Shop.swift`:

```swift
import Foundation

/// 상점 — 슬롯 확장과 아이템. 실패한 구매·사용은 재화도 아이템도 건드리지 않는다.
extension PlayerStore {
    static let expCandyAmount = 100_000_000

    // MARK: 슬롯

    /// 다음 슬롯을 산다. 상한이거나 재화가 모자라면 false.
    func buySlot() -> Bool {
        let next = state.slots + 1
        guard let price = EggBalance.slotPrice(forSlotNumber: next),
              state.wallet >= price else { return false }
        mutate {
            $0.spentTokens += price
            $0.slots = next
        }
        return true
    }

    /// 다음 슬롯 가격(화면 표시용). 상한이면 nil.
    var nextSlotPrice: Int? { EggBalance.slotPrice(forSlotNumber: state.slots + 1) }

    // MARK: 구매

    func count(of item: ShopItem) -> Int { state.inventory[item.rawValue] ?? 0 }

    func buy(_ item: ShopItem) -> Bool {
        guard state.wallet >= item.price else { return false }
        if item == .shinyCharm {
            guard !state.ownsShinyCharm else { return false }   // 보유형 — 두 번 사지 않는다
            mutate {
                $0.spentTokens += item.price
                $0.ownsShinyCharm = true
            }
            return true
        }
        mutate {
            $0.spentTokens += item.price
            $0.inventory[item.rawValue, default: 0] += 1
        }
        return true
    }

    // MARK: 사용

    func useExpCandy(on individualID: UUID) -> Bool {
        guard count(of: .expCandy) > 0,
              let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        mutate {
            $0.box[index].exp += Self.expCandyAmount
            Self.consume(.expCandy, in: &$0)
        }
        return true
    }

    func useShinyCandy(on individualID: UUID) -> Bool {
        guard count(of: .shinyCandy) > 0,
              let index = state.box.firstIndex(where: { $0.id == individualID }),
              !state.box[index].shiny else { return false }   // 이미 이로치면 낭비하지 않는다
        mutate {
            $0.box[index].shiny = true
            Self.consume(.shinyCandy, in: &$0)
        }
        return true
    }

    /// 아이템 1개 소모. `mutate` 블록 안에서 불리므로 상태를 인자로 받는다.
    private static func consume(_ item: ShopItem, in state: inout PlayerState) {
        let left = (state.inventory[item.rawValue] ?? 0) - 1
        if left > 0 { state.inventory[item.rawValue] = left }
        else { state.inventory.removeValue(forKey: item.rawValue) }
    }
}
```

- [ ] **Step 5: 테스트 통과 + 커밋**

Run: `swift test --filter ShopTests` → 전부 통과, 이어서 `swift build && swift test`

```bash
git add -A
git commit -m "feat: add the shop — slot expansion, candies, and the charm

Slots get more expensive each time because they are what limits how many
draws are in flight. Candies apply to a chosen individual rather than the
partner, and every failed purchase or use leaves the wallet and the
inventory untouched — including spending a shiny candy on something that is
already shiny."
```

---

### Task 5: 상점 탭 UI

**Files:**
- Create: `Sources/PokeDexBar/UI/ShopTabView.swift`
- Modify: `Sources/PokeDexBar/UI/PopoverView.swift`
- Test: `Tests/PokeDexBarTests/ShopViewTests.swift`

**Interfaces:**
- Consumes: `PlayerStore`(+Eggs/+Shop), `ShopItem`, `EggBalance`, `SpeciesSlug`, `PokeProviding`
- Produces:
  - `struct ShopTabView: View` — `init(store: PlayerStore, provider: any PokeProviding)`
  - `ShopTabView.oddsText() -> String` (순수)
  - `PopoverTab` 에 `case shop` 복귀

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/ShopViewTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

final class ShopViewTests: XCTestCase {
    /// 확률은 숨기지 않는다 — 표기 문자열을 테스트로 잠근다.
    func testOddsTextListsEveryGrade() {
        let text = ShopTabView.oddsText()
        XCTAssertTrue(text.contains("커먼 55%"), text)
        XCTAssertTrue(text.contains("레어 15%"), text)
        XCTAssertTrue(text.contains("에픽 25%"), text)
        XCTAssertTrue(text.contains("레전더리 5%"), text)
    }

    /// 표기 확률의 합은 100% 여야 한다 — 밸런스를 고치면 문구도 같이 틀어지는 걸 막는다.
    func testOddsSumToOne() {
        let total = EggBalance.odds.reduce(0) { $0 + $1.probability }
        XCTAssertEqual(total, 1.0, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter ShopViewTests`
Expected: FAIL — `cannot find 'ShopTabView' in scope`

- [ ] **Step 3: 구현**

`Sources/PokeDexBar/UI/ShopTabView.swift`:

```swift
import SwiftUI

/// 상점 — 알 뽑기, 슬롯 확장, 아이템. 확률은 그대로 적어 둔다.
struct ShopTabView: View {
    let store: PlayerStore
    let provider: any PokeProviding

    @State private var drawing = false
    @State private var lastError: String?

    /// 뽑기 확률 표기. 밸런스 표에서 만들어 문구와 수치가 어긋나지 않게 한다.
    nonisolated static func oddsText() -> String {
        EggBalance.odds
            .map { "\($0.grade.label) \(Int($0.probability * 100))%" }
            .joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                walletRow
                drawSection
                slotSection
                itemSection
            }
            .padding(.vertical, 2)
        }
        .frame(height: 320)
    }

    private var walletRow: some View {
        HStack {
            Text("재화").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text(TokenFormatter.compact(store.state.wallet))
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
        }
    }

    private var drawSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("알 뽑기").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(TokenFormatter.compact(EggBalance.drawPrice))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(Self.oddsText()).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text("빈 슬롯 \(store.freeSlots) / \(store.state.slots)")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
            if let lastError {
                Text(lastError).font(.system(size: 9)).foregroundStyle(.orange)
            }
            Button(drawing ? "뽑는 중…" : "뽑기") { draw() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!store.canDraw || drawing)
        }
    }

    private var slotSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("부화 슬롯").font(.system(size: 12, weight: .semibold))
            if let price = store.nextSlotPrice {
                HStack {
                    Text("슬롯 늘리기 (\(store.state.slots) → \(store.state.slots + 1))")
                        .font(.system(size: 10))
                    Spacer()
                    Button(TokenFormatter.compact(price)) { _ = store.buySlot() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(store.state.wallet < price)
                }
            } else {
                Text("슬롯을 최대까지 늘렸어요")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    private var itemSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("아이템").font(.system(size: 12, weight: .semibold))
            ForEach(ShopItem.allCases, id: \.self) { item in
                itemRow(item)
            }
        }
    }

    private func itemRow(_ item: ShopItem) -> some View {
        let owned = item == .shinyCharm ? (store.state.ownsShinyCharm ? 1 : 0)
                                        : store.count(of: item)
        let soldOut = item == .shinyCharm && store.state.ownsShinyCharm
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.label).font(.system(size: 11, weight: .medium))
                    if owned > 0 {
                        Text(item.isConsumable ? "×\(owned)" : "보유 중")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Text(item.detail).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(soldOut ? "보유" : TokenFormatter.compact(item.price)) { _ = store.buy(item) }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(soldOut || store.state.wallet < item.price)
        }
    }

    /// 등급·이로치를 굴리고, 그 등급 안에서 베이스 종을 포획률 가중으로 고른다.
    /// 후보는 네트워크(베이스 인덱스)라 여기서 받아 스토어에 넘긴다.
    private func draw() {
        drawing = true
        lastError = nil
        Task {
            defer { drawing = false }
            let roll = store.rollGradeAndShiny()
            guard let index = try? await provider.baseSpeciesIndex(), !index.isEmpty else {
                lastError = "부화 후보를 받지 못했어요. 잠시 뒤 다시 시도해 주세요."
                return
            }
            let pool = index.filter {
                Grade.from(captureRate: $0.captureRate, isLegendary: false, isMythical: false)
                    == roll.grade
            }
            // 레전더리는 포획률만으로는 갈리지 않는다(인덱스에 전설 플래그가 없다) —
            // 그 등급의 후보가 비면 한 단계 아래에서 고른다.
            let candidates = pool.isEmpty ? index : pool
            let weights = candidates.map { max(1, $0.captureRate) }
            let total = weights.reduce(0, +)
            var pick = Int(store.nextRandomUnit() * Double(total)) % max(1, total)
            var chosen = candidates[0].id
            for (candidate, weight) in zip(candidates, weights) {
                if pick < weight { chosen = candidate.id; break }
                pick -= weight
            }
            store.startEgg(grade: roll.grade, speciesID: chosen, shiny: roll.shiny)
        }
    }
}
```

- [ ] **Step 4: 팝오버 탭에 붙이기**

`Sources/PokeDexBar/UI/PopoverView.swift`:
- `enum PopoverTab` 에 `case shop` 을 더하고(순서: `home, box, collection, shop`) 세그먼트에 `Text("상점").tag(PopoverTab.shop)` 을 넣는다.
- 탭 switch 에 `case .shop: ShopTabView(store: player, provider: provider)` 를 더한다.

- [ ] **Step 5: 테스트 통과 + 커밋**

Run: `swift test --filter ShopViewTests` → 통과, 이어서 `swift build && swift test`

```bash
git add -A
git commit -m "feat: add the shop tab

Draw odds are printed next to the button rather than hidden, and the draw is
disabled when there is no money or no free slot so the rule is visible before
the click. The species roll happens here because the candidate list comes
from the network; the store only takes the result."
```

---

### Task 6: 홈에 부화 슬롯 표시

**Files:**
- Create: `Sources/PokeDexBar/UI/EggSlotsView.swift`
- Modify: `Sources/PokeDexBar/UI/PopoverView.swift`(홈 탭 구성)
- Test: `Tests/PokeDexBarTests/EggSlotsViewTests.swift`

**Interfaces:**
- Consumes: `PlayerStore`, `Egg`, `SpriteView`
- Produces:
  - `struct EggSlotsView: View` — `init(store: PlayerStore, now: Date)`
  - `EggSlotsView.countdownText(_ remaining: TimeInterval) -> String`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/EggSlotsViewTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

final class EggSlotsViewTests: XCTestCase {
    func testCountdownFormats() {
        XCTAssertEqual(EggSlotsView.countdownText(0), "부화!")
        XCTAssertEqual(EggSlotsView.countdownText(45), "45초")
        XCTAssertEqual(EggSlotsView.countdownText(90), "1분 30초")
        XCTAssertEqual(EggSlotsView.countdownText(3 * 3600 + 12 * 60), "3시간 12분")
        XCTAssertEqual(EggSlotsView.countdownText(25 * 3600), "1일 1시간")
    }

    /// 남은 시간이 음수로 들어와도(시계 되감김) 부화로 표시한다.
    func testNegativeRemainingIsReady() {
        XCTAssertEqual(EggSlotsView.countdownText(-10), "부화!")
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter EggSlotsViewTests`
Expected: FAIL — `cannot find 'EggSlotsView' in scope`

- [ ] **Step 3: 구현**

`Sources/PokeDexBar/UI/EggSlotsView.swift`:

```swift
import SwiftUI

/// 홈의 부화 슬롯 줄. 알은 종을 숨긴 채 남은 시간만 보여준다 — 무엇이 나올지는 깨야 안다.
struct EggSlotsView: View {
    let store: PlayerStore
    /// 1초 틱 — 남은 시간이 살아 움직이게.
    let now: Date

    /// 남은 시간 표기. 단위는 큰 것 두 개까지만 — "1일 1시간", "3시간 12분", "1분 30초".
    nonisolated static func countdownText(_ remaining: TimeInterval) -> String {
        let s = Int(remaining)
        guard s > 0 else { return "부화!" }
        let days = s / 86_400, hours = (s % 86_400) / 3600
        let minutes = (s % 3600) / 60, seconds = s % 60
        if days > 0 { return "\(days)일 \(hours)시간" }
        if hours > 0 { return "\(hours)시간 \(minutes)분" }
        if minutes > 0 { return "\(minutes)분 \(seconds)초" }
        return "\(seconds)초"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("부화 중").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.state.eggs.count) / \(store.state.slots)")
                    .font(.system(size: 9)).monospacedDigit().foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                ForEach(store.state.eggs) { egg in
                    slot(egg)
                }
                ForEach(0..<max(0, store.state.slots - store.state.eggs.count), id: \.self) { _ in
                    emptySlot
                }
            }
        }
    }

    private func slot(_ egg: Egg) -> some View {
        let remaining = egg.remaining(at: now)
        return VStack(spacing: 2) {
            Text("🥚").font(.system(size: 20))
            Text(Self.countdownText(remaining))
                .font(.system(size: 8)).monospacedDigit()
                .foregroundStyle(remaining <= 0 ? Color.accentColor : .secondary)
            Text(egg.grade.label)
                .font(.system(size: 7, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .frame(width: 52, height: 52)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3]))
            .frame(width: 52, height: 52)
    }
}
```

- [ ] **Step 4: 홈 탭에 붙이기**

`Sources/PokeDexBar/UI/PopoverView.swift` 의 홈 탭 내용에 파트너 카드 아래로 `EggSlotsView(store: player, now: context.date)` 를 넣는다(홈이 이미 1초 틱 `TimelineView` 안에 있으면 그 `context.date` 를 쓰고, 없으면 홈 탭을 `TimelineView(.periodic(from: .now, by: 1))` 로 감싼다).

- [ ] **Step 5: 테스트 통과 + 커밋**

Run: `swift test --filter EggSlotsViewTests` → 통과, 이어서 `swift build && swift test`

```bash
git add -A
git commit -m "feat: show hatching slots on the home tab

Eggs ripen on the clock, so the home tab shows the countdown per slot and
leaves the empty ones outlined — the limit is the point, since a full board
is what stops the next draw. The species stays hidden until it hatches."
```

---

### Task 7: 부화 정산 배선과 알림

**Files:**
- Modify: `Sources/PokeDexBar/PokeDexBarApp.swift`
- Create: `Sources/PokeDexBar/Player/HatchNotifier.swift`
- Test: `Tests/PokeDexBarTests/HatchNotifierTests.swift`

**Interfaces:**
- Consumes: `PlayerStore.settleHatches(at:)`, `Individual`, `SpeciesSlug`
- Produces:
  - `struct HatchNotifier` — `func requestAuthorization()`, `func notify(hatched: [Individual])`
  - `HatchNotifier.message(for hatched: [Individual]) -> (title: String, body: String)?` (순수)
  - `AppDelegate` 가 사용량 갱신 틱마다 `settleHatches` 를 부르고 결과를 알린다

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/HatchNotifierTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

final class HatchNotifierTests: XCTestCase {
    private func individual(_ species: Int, shiny: Bool = false) -> Individual {
        Individual(baseID: species, speciesID: species, pathIDs: [species], shiny: shiny,
                   nature: .serious, exp: 0, obtainedAt: Date(timeIntervalSince1970: 0),
                   grade: .common)
    }

    func testNoMessageWhenNothingHatched() {
        XCTAssertNil(HatchNotifier.message(for: []))
    }

    func testSingleHatchNamesTheSpecies() {
        let message = HatchNotifier.message(for: [individual(1)])
        XCTAssertEqual(message?.title, "알이 부화했어요")
        XCTAssertTrue(message?.body.contains("#1") ?? false, message?.body ?? "")
    }

    /// 이로치는 문구에서 티가 나야 한다 — 놓치면 아까운 정보다.
    func testShinyIsCalledOut() {
        let message = HatchNotifier.message(for: [individual(25, shiny: true)])
        XCTAssertTrue(message?.body.contains("✨") ?? false, message?.body ?? "")
    }

    /// 여러 개가 한꺼번에 깨면 하나로 묶는다 — 알림 폭탄을 만들지 않는다.
    func testMultipleHatchesAreSummarised() {
        let message = HatchNotifier.message(for: [individual(1), individual(4), individual(7)])
        XCTAssertTrue(message?.body.contains("3") ?? false, message?.body ?? "")
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter HatchNotifierTests`
Expected: FAIL — `cannot find 'HatchNotifier' in scope`

- [ ] **Step 3: 구현**

`Sources/PokeDexBar/Player/HatchNotifier.swift`:

```swift
import Foundation
import UserNotifications

/// 부화 알림. 문구 조립은 순수 함수로 떼어 테스트한다(실제 발송은 번들 앱에서만 동작해
/// xctest 로는 확인할 수 없다).
struct HatchNotifier: Sendable {
    /// 부화 결과 → 알림 문구. 아무것도 안 깼으면 nil. 여러 개면 하나로 묶는다.
    static func message(for hatched: [Individual]) -> (title: String, body: String)? {
        guard !hatched.isEmpty else { return nil }
        let title = "알이 부화했어요"
        if hatched.count == 1, let one = hatched.first {
            let shiny = one.shiny ? "✨ " : ""
            return (title, "\(shiny)#\(one.speciesID) 를 만났어요")
        }
        let shinyCount = hatched.count { $0.shiny }
        let extra = shinyCount > 0 ? " (✨ \(shinyCount)마리)" : ""
        return (title, "\(hatched.count)마리가 부화했어요\(extra)")
    }

    func requestAuthorization() {
        guard AppEnv.isBundledApp else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(hatched: [Individual]) {
        guard AppEnv.isBundledApp, let message = Self.message(for: hatched) else { return }
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 4: 앱에 배선**

`Sources/PokeDexBar/PokeDexBarApp.swift`:
- `private let hatchNotifier = HatchNotifier()` 를 더하고 `applicationDidFinishLaunching` 에서 `hatchNotifier.requestAuthorization()` 을 부른다.
- `player.update(...)` 를 부르는 자리 **바로 뒤에** 정산을 넣는다:

```swift
        let hatched = player.settleHatches(at: Date())
        hatchNotifier.notify(hatched: hatched)
```

- 팝오버를 열 때도 한 번 정산하도록, 팝오버 생성 직전에 같은 두 줄을 넣는다(앱이 오래 유휴였다가 열릴 때 즉시 반영되게).

- [ ] **Step 5: 테스트 통과 + 커밋**

Run: `swift test --filter HatchNotifierTests` → 통과, 이어서 `swift build && swift test`

```bash
git add -A
git commit -m "feat: settle hatches on each tick and announce them

Eggs ripen while the app idles, so settle on every usage tick and again when
the popover opens rather than waiting for a timer that only runs in the
foreground. Several eggs finishing together collapse into one notification
instead of a burst, and a shiny is called out because it is easy to miss."
```

---

### Task 8: 실사용 검증

**Files:**
- Modify: `README.md`(기능 설명 갱신)

**Interfaces:**
- Consumes: Task 1~7 전부

- [ ] **Step 1: 빌드·전체 테스트**

Run: `swift build && swift test`
Expected: 경고 0, 전부 통과

- [ ] **Step 2: 시간 압축 점검**

주입 시계로 하루치를 시뮬레이션해 뽑기→부화→도감이 한 바퀴 도는지 확인하는 테스트를 더한다.

`Tests/PokeDexBarTests/EconomyLoopTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

@MainActor
final class EconomyLoopTests: XCTestCase {
    /// 뽑기 → 부화 → 도감 등록 → 슬롯 반환이 한 바퀴 도는지, 하루를 압축해 확인한다.
    func testFullLoopOverOneDay() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loop-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 11), now: { start })
        store.seedForTesting(wallet: EggBalance.drawPrice * 3, slots: 3, eggs: 0, at: start)

        store.startEgg(grade: .common, speciesID: 1, shiny: false)
        store.startEgg(grade: .rare, speciesID: 4, shiny: false)
        store.startEgg(grade: .legendary, speciesID: 144, shiny: true)
        XCTAssertEqual(store.freeSlots, 0)
        XCTAssertFalse(store.canDraw, "슬롯이 꽉 차면 못 뽑는다")

        let hatched = store.settleHatches(at: start.addingTimeInterval(24 * 3600))
        XCTAssertEqual(hatched.count, 3)
        XCTAssertEqual(store.freeSlots, 3, "부화하면 슬롯이 돌아온다")
        XCTAssertEqual(store.state.dex, [1, 4, 144])
        XCTAssertTrue(store.state.box.first { $0.speciesID == 144 }?.shiny ?? false)
    }
}
```

Run: `swift test --filter EconomyLoopTests`
Expected: 통과

- [ ] **Step 3: 앱 번들 생성**

Run: `./scripts/build-app.sh`
Expected: `build/PokeDexBar.app` 생성. **앱을 실행하지는 않는다** — 사람이 직접 띄워 확인한다.

- [ ] **Step 4: README 갱신**

`README.md` 의 기능 설명에서 "알을 키워 졸업시킨다" 계열 문장을 지금 게임에 맞게 고친다:
스타터를 골라 시작하고, 토큰이 재화가 되며, 재화로 알을 뽑고, 알은 시간이 지나면 깨지고,
경험치로 진화시키며, 도감과 박스가 따로 있다는 것. 한국어·일본어 README 도 같은 내용으로 맞춘다.

- [ ] **Step 5: 사람이 확인할 목록을 보고서에 적는다**

직접 클릭하지 말고 다음을 보고서에 적어 사람에게 넘긴다.

1. 첫 실행에 스타터 27마리가 뜨고, 고르면 파트너가 된다
2. 상점에서 확률이 보이고, 재화가 모자라거나 슬롯이 차면 뽑기 버튼이 비활성이다
3. 뽑으면 홈에 알이 뜨고 남은 시간이 1초마다 준다
4. 커먼 알(30분)이 실제로 깨지고 알림이 오며, 박스와 도감에 반영된다
5. 박스에서 파트너를 바꾸고, 경험치가 차면 진화 버튼이 뜬다

- [ ] **Step 6: 커밋**

```bash
git add -A
git commit -m "test: cover the draw-to-dex loop and refresh the README

Compress a day of wall clock into one test so the full cycle — draw, fill
the slots, hatch, register in the dex, free the slots — is verified without
waiting for it, and describe the game the app actually is now."
```
