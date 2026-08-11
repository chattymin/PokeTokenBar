# 박사에게 보내기 · 박사의 제안 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 필요 없는 개체를 박사에게 보내 포인트를 받고, 박사가 매일 내미는 3마리와 그 포인트를 교환한다.

**Architecture:** 포인트는 `wallet`(토큰)과 완전히 별개인 `researchPoints` 다. 보내기는 이 앱에서
**개체가 박스에서 빠지는 첫 경로**이므로, 그 전제 위에 서 있던 `HatchSpeedup` 을 같이 고친다.
박사의 제안 3마리는 날짜 문자열에서 만든 결정적 굴림으로 뽑아 **완성된 `Individual` 그대로**
상태에 저장한다 — 화면에 보이는 것과 받는 것이 반드시 같아진다.

**Tech Stack:** Swift 6 / SwiftPM / SwiftUI / XCTest. 외부 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-08-11-professor-and-vouchers-design.md` 의 **B 절**.
A 절(알 발견)은 v1.5.0 으로 이미 배포됐다 — 건드리지 않는다.

## Global Constraints

- **커밋 메시지는 영어. 코드 주석은 한국어** — 주변 주석과 같은 밀도·어투로. *왜* 를 적는다.
- **사용자에게 보이는 문자열은 전부 `L.t(ko, en, ja)`** (`Sources/PokeDexBar/Core/Localization.swift`).
- **빌드 경고 0.** 하나라도 남으면 그 태스크는 완료가 아니다.
- **`PlayerState` 에 필드를 더하면 반드시 `init(from:)`(관대 디코더)에도 줄을 더한다.** 합성
  `encode(to:)` 는 새 필드를 자동으로 쓰지만 수동 `init(from:)` 은 자동으로 안 읽는다. 이 저장소가
  세 번 밟았다.
- **`.help()` 툴팁 금지** — 이 앱의 팝오버 안에서는 안 뜬다(실사용 확인). 인라인 한 줄로 적는다.
- **실제 세이브 파일(`~/Library/Application Support/PokeDexBar/`) 접근 금지 in tests.** 임시
  파일과 `#if DEBUG` 헬퍼만.
- **`SaveTransfer` 라는 타입은 없다.** `CLAUDE.md` 가 값 범위 검증을 그 이름으로 설명하지만 소스에
  존재하지 않는다(2026-08-11 확인). 검증은 `PlayerState.init(from:)` 의 `slots` clamp 자리에서 한다.
- **`SeededRNG` 는 `Tests/PokeDexBarTests/TestSupport.swift` 에만 있다** — 프로덕션 코드에서 못 쓴다.
  결정적 굴림은 Task 3 이 만드는 `ProfessorRoll` 로 한다.
- 테스트: `swift test --filter ProfessorTests` / 전체는 `swift test`.

---

## File Structure

| 파일 | 책임 |
|---|---|
| `Sources/PokeDexBar/Player/ReleaseBalance.swift` **(신규)** | 개체 하나를 보내면 몇 포인트인가. 순수 산식. |
| `Sources/PokeDexBar/Player/ProfessorRoll.swift` **(신규)** | 날짜 문자열 → 결정적 0…1 굴림. FNV-1a + 믹싱. |
| `Sources/PokeDexBar/Player/ProfessorOffer.swift` **(신규)** | 오늘의 제안 한 자리. 완성된 `Individual` 을 품는다. |
| `Sources/PokeDexBar/Player/PlayerStore+Professor.swift` **(신규)** | 보내기·제안 준비·교환 동작. |
| `Sources/PokeDexBar/Player/PlayerState.swift` **(수정)** | 세 필드 + 관대 디코딩 + 값 범위 검증. |
| `Sources/PokeDexBar/Player/HatchSpeedup.swift` **(수정)** | `box` → `dex`. 개체가 빠지는 경로가 생기므로. |
| `Sources/PokeDexBar/UI/EggSlotsView.swift` **(수정)** | `HatchSpeedup` 시그니처 변경에 맞춤. |
| `Sources/PokeDexBar/UI/IndividualDetailView.swift` **(수정)** | 보내기 버튼 + 단계별 확인. |
| `Sources/PokeDexBar/UI/ProfessorOfferSection.swift` **(신규)** | 상점 맨 위 "박사의 제안" 섹션. |
| `Sources/PokeDexBar/UI/ShopTabView.swift` **(수정)** | 그 섹션을 얹는다. |
| `Sources/PokeDexBar/Core/Localization.swift` **(수정)** | ko/en/ja 문구. |
| `Tests/PokeDexBarTests/ProfessorTests.swift` **(신규)** | 전 태스크의 테스트가 여기 모인다. |

---

## Task 1: 보내면 받는 값과 포인트 저장

**Files:**
- Create: `Sources/PokeDexBar/Player/ReleaseBalance.swift`
- Modify: `Sources/PokeDexBar/Player/PlayerState.swift` (필드 선언부, `init(from:)`)
- Test: `Tests/PokeDexBarTests/ProfessorTests.swift` (신규)

**Interfaces:**
- Consumes: `Grade`, `Individual`, `ExpBalance.threshold(grade:stageIndex:)`
- Produces:
  - `static func ReleaseBalance.base(grade: Grade) -> Int`
  - `static func ReleaseBalance.points(for individual: Individual) -> Int`
  - `PlayerState.researchPoints: Int`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`Tests/PokeDexBarTests/ProfessorTests.swift` 를 새로 만든다.

```swift
import XCTest
@testable import PokeDexBar

/// 박사에게 보내기 · 박사의 제안.
@MainActor
final class ProfessorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(seed: UInt64 = 1) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prof-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: seed), now: { self.now })
    }

    private func make(_ grade: Grade, path: [Int], exp: Int = 0) -> Individual {
        Individual(baseID: path.first ?? 1, speciesID: path.last ?? 1, pathIDs: path,
                   nature: .hardy, exp: exp, obtainedAt: now, grade: grade)
    }

    // MARK: 보내면 받는 값

    /// 등급기본 — 스펙의 표 그대로.
    func testReleaseBaseValues() {
        XCTAssertEqual(ReleaseBalance.base(grade: .common), 2)
        XCTAssertEqual(ReleaseBalance.base(grade: .rare), 5)
        XCTAssertEqual(ReleaseBalance.base(grade: .epic), 12)
        XCTAssertEqual(ReleaseBalance.base(grade: .legendary), 40)
    }

    /// 경험치 0 기준 표. 진화한 만큼 값이 붙는다.
    func testReleasePointsByStage() {
        for (grade, expected) in [(Grade.common, [2, 4, 6]), (.rare, [5, 10, 15]),
                                  (.epic, [12, 24, 36]), (.legendary, [40, 80, 120])] {
            for (stage, want) in expected.enumerated() {
                let path = Array(1...(stage + 1))
                XCTAssertEqual(ReleaseBalance.points(for: make(grade, path: path)), want,
                               "\(grade) \(stage)단계")
            }
        }
    }

    /// **지금 단계에서 채운 경험치가 더해진다** — 키운 아이일수록 값이 나가야 정리 대상이
    /// 자연히 "안 키운 중복" 이 된다.
    func testReleasePointsIncludeBankedExperience() {
        let threshold = ExpBalance.threshold(grade: .epic, stageIndex: 0)
        let half = make(.epic, path: [4], exp: threshold / 2)
        XCTAssertEqual(ReleaseBalance.points(for: half), 18)   // floor(12 × (0 + 1 + 0.5))
    }

    /// 경험치 비율은 1 에서 멈춘다 — 알 임계까지 쌓인 최종형이 배수로 튀면 안 된다.
    func testReleasePointsClampTheExperienceRatio() {
        let huge = make(.epic, path: [4, 5, 6], exp: Int.max / 4)
        XCTAssertEqual(ReleaseBalance.points(for: huge), 48)   // floor(12 × (2 + 1 + 1))
    }

    // MARK: 포인트 저장

    /// **앱을 껐다 켜도 포인트가 남는다.** 관대 디코더에 줄을 안 더하면 저장은 되고 읽기만 빠진다.
    func testResearchPointsSurviveARestart() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prof-save-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        store.mutate { $0.researchPoints = 137 }

        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertEqual(reloaded.state.researchPoints, 137, "다시 켜니 포인트가 사라졌다")
    }

    /// 말이 안 되는 값은 경계에서 자른다 — 산술에 쓰이는 수치라 `Int.max` 가 들어오면 이후
    /// 덧셈이 Swift 오버플로 트랩으로 프로세스를 죽이고, 재기동해도 같은 파일을 읽어 또 죽는다.
    func testAbsurdResearchPointsAreClamped() throws {
        let json = #"{"researchPoints": 9223372036854775807}"#
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertLessThanOrEqual(state.researchPoints, 1_000_000)
        XCTAssertGreaterThanOrEqual(state.researchPoints, 0)

        let negative = #"{"researchPoints": -5}"#
        XCTAssertEqual(try JSONDecoder().decode(PlayerState.self,
                                                from: Data(negative.utf8)).researchPoints, 0)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter ProfessorTests`
Expected: 컴파일 실패 — `cannot find 'ReleaseBalance' in scope`

- [ ] **Step 3: `ReleaseBalance.swift` 를 만든다**

```swift
import Foundation

/// 개체 하나를 박사에게 보내면 몇 포인트인가.
///
/// **등급과 경험치, 두 가지로만 정한다.** 키운 아이일수록 값이 나가므로 정리 대상이 자연히
/// "안 키운 중복" 이 된다 — 이 기능이 노리는 방향이다.
enum ReleaseBalance {
    /// 포인트 상한. 산술 안전용이지 게임 규칙이 아니다 — 정상 플레이로는 근처도 안 간다
    /// (전설 최종형 하나가 160 이다). 봉인을 깬 세이브의 `Int.max` 가 이후 덧셈에서 오버플로
    /// 트랩을 내는 것을 경계 한 곳에서 막는다.
    static let maxPoints = 1_000_000

    /// 등급기본.
    static func base(grade: Grade) -> Int {
        switch grade {
        case .common: 2
        case .rare: 5
        case .epic: 12
        case .legendary: 40
        }
    }

    /// `등급기본 × (진화 횟수 + 1 + 지금 단계에서 채운 경험치 비율)`, 내림.
    ///
    /// 경험치 비율의 분모는 **진화 임계**다(알 임계가 아니다). 알 발견은 최종형에만 열리는
    /// 별개의 길이고, 여기서 재는 것은 "이 단계에서 얼마나 키웠나" 다. 최종형은 알 임계까지
    /// 쌓이므로 이 비율이 1 에서 포화되는데, 최종형이라는 사실은 이미 `stageIndex` 로 값에
    /// 반영돼 있다.
    static func points(for individual: Individual) -> Int {
        let threshold = ExpBalance.threshold(grade: individual.grade,
                                             stageIndex: individual.stageIndex)
        let ratio = threshold > 0
            ? min(1, max(0, Double(individual.exp) / Double(threshold)))
            : 0
        let grown = Double(individual.stageIndex) + 1 + ratio
        return Int(Double(base(grade: individual.grade)) * grown)
    }
}
```

- [ ] **Step 4: `PlayerState` 에 필드와 디코딩을 더한다**

`Sources/PokeDexBar/Player/PlayerState.swift` — `var eggVouchers` 가 있던 자리는 이제 없다.
`var inventory: [String: Int] = [:]` 선언 **아래**에 더한다:

```swift
    /// 박사에게 쌓인 포인트. `wallet`(토큰) 과 완전히 별개다 — 포인트로는 알을 못 사고
    /// 토큰으로는 박사와 거래할 수 없다. 섞으면 토큰을 안 쓰고도 재화가 도는 순환이 생겨,
    /// "쓴 토큰이 곧 재화" 라는 이 앱의 전제가 흐려진다.
    var researchPoints = 0
```

`init(from decoder: Decoder)` 안, `inventory = value(.inventory, [:])` **바로 아래**:

```swift
        // 관대 디코딩의 짝 — 값 범위 검증. 산술에 쓰이는 수치이므로 자른다.
        researchPoints = min(ReleaseBalance.maxPoints, max(0, value(.researchPoints, 0)))
```

- [ ] **Step 5: 테스트가 통과하는지 확인한다**

Run: `swift test --filter ProfessorTests`
Expected: PASS (6개)

- [ ] **Step 6: 전체 테스트와 경고를 확인한다**

Run: `swift build 2>&1 | grep -i warning; swift test`
Expected: 경고 출력 없음, 전체 PASS

- [ ] **Step 7: 커밋**

```bash
git add Sources/PokeDexBar/Player/ReleaseBalance.swift Sources/PokeDexBar/Player/PlayerState.swift Tests/PokeDexBarTests/ProfessorTests.swift
git commit -m "feat: price a Pokemon sent to the Professor"
```

---

## Task 2: 보내기 동작 — 그리고 박스에서 빠지는 첫 경로

**개체가 박스에서 빠지는 경로가 이 앱에 처음 생긴다.** `HatchSpeedup` 이 그 전제 위에 서 있고
주석이 그걸 명시하므로 같이 고친다. 이 태스크의 절반은 그 정리다.

**Files:**
- Create: `Sources/PokeDexBar/Player/PlayerStore+Professor.swift`
- Modify: `Sources/PokeDexBar/Player/HatchSpeedup.swift:26-33`
- Modify: `Sources/PokeDexBar/Player/PlayerStore+Eggs.swift` (`placeEgg` 안의 `HatchSpeedup.present` 호출)
- Modify: `Sources/PokeDexBar/UI/EggSlotsView.swift` (`HatchSpeedup.warmer` 호출)
- Test: `Tests/PokeDexBarTests/ProfessorTests.swift`

**Interfaces:**
- Consumes: `ReleaseBalance.points(for:)`, `PlayerStore.mutate(_:)`
- Produces:
  - `func PlayerStore.releaseValue(_ individual: Individual) -> Int?` — 파트너면 nil
  - `@discardableResult func PlayerStore.releaseToProfessor(individualID: UUID) -> Int?`
  - `static func HatchSpeedup.present(in dex: Set<Int>) -> Bool`
  - `static func HatchSpeedup.warmer(in box: [Individual]) -> Individual?` (시그니처 유지)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`ProfessorTests.swift` 에 더한다.

```swift
    // MARK: 보내기

    /// **파트너는 못 보낸다.** 값 자체가 nil 이라 화면이 버튼을 못 만든다.
    func testThePartnerCannotBeSent() {
        let store = makeStore()
        let partner = make(.common, path: [1])
        store.addForTesting(partner)
        store.setPartner(partner.id)

        XCTAssertNil(store.releaseValue(partner))
        XCTAssertNil(store.releaseToProfessor(individualID: partner.id))
        XCTAssertEqual(store.state.box.count, 1, "파트너가 사라졌다")
        XCTAssertEqual(store.state.researchPoints, 0)
    }

    /// 보내면 박스에서 빠지고 포인트가 들어온다.
    func testSendingRemovesTheIndividualAndPaysPoints() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        let send = make(.epic, path: [4, 5, 6])
        store.addForTesting(keep)
        store.addForTesting(send)
        store.setPartner(keep.id)

        XCTAssertEqual(store.releaseValue(send), 36)
        XCTAssertEqual(store.releaseToProfessor(individualID: send.id), 36)
        XCTAssertEqual(store.state.box.map(\.id), [keep.id], "박스에서 안 빠졌다")
        XCTAssertEqual(store.state.researchPoints, 36)
    }

    /// **도감은 그대로다.** 도감은 만난 기록이지 소유 기록이 아니다.
    func testSendingKeepsTheDexEntry() {
        let store = makeStore()
        let send = make(.rare, path: [25])
        store.addForTesting(send)
        store.mutate { $0.dex.insert(25) }

        store.releaseToProfessor(individualID: send.id)
        XCTAssertTrue(store.state.dex.contains(25), "도감에서 지워졌다")
    }

    /// 박스에 없는 개체는 아무 일도 안 일어난다.
    func testSendingAnUnknownIndividualDoesNothing() {
        let store = makeStore()
        XCTAssertNil(store.releaseToProfessor(individualID: UUID()))
        XCTAssertEqual(store.state.researchPoints, 0)
    }

    // MARK: 딸린 정리 — 부화 감면

    /// **유일한 불꽃몸을 보내도 부화 감면이 남는다.**
    ///
    /// `HatchSpeedup` 은 "개체가 박스에서 빠지는 경로가 없다" 는 전제 위에 있었고 주석이 그걸
    /// 명시했다. 이 기능이 그 전제를 깬다 — `dex`(한 번이라도 보유한 종)를 보게 고쳐야 주석이
    /// 원래 말하려던 것과 같아진다.
    func testTheHatchDiscountSurvivesSendingTheOnlyWarmPokemon() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        store.addForTesting(keep)
        store.setPartner(keep.id)
        // 마그마그(불꽃몸 계열).
        let slugma = make(.common, path: [218])
        store.addForTesting(slugma)
        store.mutate { $0.dex.insert(218) }
        XCTAssertTrue(HatchSpeedup.present(in: store.state.dex))

        store.releaseToProfessor(individualID: slugma.id)

        XCTAssertTrue(HatchSpeedup.present(in: store.state.dex), "보냈다고 감면이 사라졌다")
        let egg = store.placeEgg(grade: .common, speciesID: 1, shiny: false)
        XCTAssertEqual(egg?.hatchesAt.timeIntervalSince(now) ?? 0,
                       EggBalance.duration(.common) * HatchSpeedup.multiplier, accuracy: 1,
                       "새 알이 감면을 못 받았다")
    }

    /// **감면과 그 이름은 갈린다.** 감면은 `dex` 로 남고, 화면에 이름을 내밀 개체는 박스에서
    /// 사라졌으니 없다 — `EggSlotsView` 의 안내 줄만 빠지고 감면 자체는 유지된다.
    func testTheWarmPokemonsNameDisappearsButTheDiscountDoesNot() {
        let store = makeStore()
        let slugma = make(.common, path: [218])
        store.addForTesting(slugma)
        store.mutate { $0.dex.insert(218) }
        XCTAssertNotNil(HatchSpeedup.warmer(in: store.state.box))

        store.releaseToProfessor(individualID: slugma.id)

        XCTAssertNil(HatchSpeedup.warmer(in: store.state.box), "박스에 없는데 이름이 나온다")
        XCTAssertTrue(HatchSpeedup.present(in: store.state.dex), "이름이 없다고 감면까지 사라졌다")
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter ProfessorTests`
Expected: 컴파일 실패 — `value of type 'PlayerStore' has no member 'releaseValue'`

- [ ] **Step 3: `HatchSpeedup` 이 `dex` 를 보게 한다**

`Sources/PokeDexBar/Player/HatchSpeedup.swift` 의 문서 주석 중 아래 문장을

```
/// 개체는 박스에서 빠지는 경로가 없으므로 "한 번이라도 얻었으면" 과 "박스에 있으면" 은 같은 말이다.
```

아래로 바꾸고, `present`/`warmer` 를 교체한다:

```swift
/// **판정은 `dex` 로 한다.** 예전엔 박스를 봤다 — 개체가 박스에서 빠지는 경로가 없어서 "한 번이라도
/// 얻었으면" 과 "박스에 있으면" 이 같은 말이었기 때문이다. 박사에게 보내기가 그 전제를 깼다.
/// `dex` 가 정확히 "한 번이라도 보유한 종" 이라, 주석이 원래 말하려던 것과 같아진다.
```

```swift
    /// 알을 빨리 깨우는 종을 한 번이라도 얻었나.
    static func present(in dex: Set<Int>) -> Bool { !dex.isDisjoint(with: species) }

    /// 화면에 이름을 내밀 아이. 여럿이면 **가장 먼저 얻은** 아이다 — 박스는 얻은 순서라
    /// 맨 앞이 그 감면을 처음 준 개체다.
    ///
    /// **`present` 와 갈릴 수 있다.** 감면을 준 종을 박사에게 보냈으면 이름을 댈 개체가 없어
    /// nil 이지만, 감면 자체는 `dex` 에 남아 유지된다. 안내 줄만 빠진다.
    static func warmer(in box: [Individual]) -> Individual? {
        box.first { species.contains($0.speciesID) }
    }
```

- [ ] **Step 4: 호출부 두 곳을 고친다**

`Sources/PokeDexBar/Player/PlayerStore+Eggs.swift` 의 `placeEgg` 안:

```swift
        let span = HatchSpeedup.present(in: state.dex) ? full * HatchSpeedup.multiplier : full
```

`Sources/PokeDexBar/UI/EggSlotsView.swift` 의 안내 줄은 `warmer(in: store.state.box)` 를 그대로
쓴다(시그니처가 안 바뀌었다). **`present` 를 부르는 다른 자리가 없는지 확인한다:**

```bash
grep -rn "HatchSpeedup.present\|HatchSpeedup.warmer" Sources Tests
```

기존 테스트가 `present(in: box)` 를 부르고 있으면 `dex` 로 고친다.

- [ ] **Step 5: `PlayerStore+Professor.swift` 를 만든다**

```swift
import Foundation

/// 박사에게 보내기 — 필요 없는 개체를 보내고 포인트를 받는다.
///
/// **이 앱에서 개체가 박스에서 빠지는 유일한 경로다.** 되돌릴 수 없으므로 확인은 화면이 맡고,
/// 여기서는 파트너만 막는다(파트너 시계·폼 상태가 통째로 사라지는 것을 원천 차단).
extension PlayerStore {
    /// 이 개체를 보내면 받을 포인트. **파트너면 nil** — 보낼 수 없다는 뜻이고, 화면은 이 nil 로
    /// 버튼을 안 만든다(조건을 화면이 따로 적으면 스토어와 갈린다).
    func releaseValue(_ individual: Individual) -> Int? {
        guard individual.id != state.partnerID else { return nil }
        return ReleaseBalance.points(for: individual)
    }

    /// 박사에게 보낸다. 박스에서 빼고 포인트를 더한다. 보낼 수 없으면 nil.
    ///
    /// **`dex` 는 건드리지 않는다** — 도감은 만난 기록이지 소유 기록이 아니다.
    @discardableResult
    func releaseToProfessor(individualID: UUID) -> Int? {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return nil }
        guard let points = releaseValue(state.box[index]) else { return nil }
        mutate { s in
            // 인덱스를 다시 찾는다 — 위 계산과 이 변형 사이에 배열이 바뀔 일은 없지만,
            // id 로 다시 찾는 것이 이 저장소가 정한 형태다.
            guard let i = s.box.firstIndex(where: { $0.id == individualID }) else { return }
            s.box.remove(at: i)
            s.researchPoints = min(ReleaseBalance.maxPoints, s.researchPoints + points)
        }
        return points
    }
}
```

- [ ] **Step 6: 테스트가 통과하는지 확인한다**

Run: `swift test --filter ProfessorTests`
Expected: PASS (12개)

- [ ] **Step 7: 가드가 진짜 판별하는지 확인한다 (되돌리기 검사)**

`HatchSpeedup.present` 를 `static func present(in dex: Set<Int>) -> Bool { false }` 로 잠시 바꾸고 실행한다.

Run: `swift test --filter ProfessorTests`
Expected: `testTheHatchDiscountSurvivesSendingTheOnlyWarmPokemon` **이 실패해야 한다.**
확인했으면 원래 코드로 되돌리고 `git diff` 로 되돌림이 완전한지 본다.

- [ ] **Step 8: 전체 테스트와 경고를 확인한다**

Run: `swift build 2>&1 | grep -i warning; swift test`
Expected: 경고 출력 없음, 전체 PASS. 부화 감면 기존 테스트(`HatchSpeedupTests`)가 전부 통과해야 한다.

- [ ] **Step 9: 커밋**

```bash
git add Sources/PokeDexBar/Player/PlayerStore+Professor.swift Sources/PokeDexBar/Player/HatchSpeedup.swift Sources/PokeDexBar/Player/PlayerStore+Eggs.swift Tests/PokeDexBarTests/
git commit -m "feat: send a Pokemon to the Professor for points"
```

---

## Task 3: 박사의 제안 — 결정적 굴림과 교환

**Files:**
- Create: `Sources/PokeDexBar/Player/ProfessorRoll.swift`
- Create: `Sources/PokeDexBar/Player/ProfessorOffer.swift`
- Modify: `Sources/PokeDexBar/Player/PlayerStore+Professor.swift`
- Modify: `Sources/PokeDexBar/Player/PlayerState.swift`
- Test: `Tests/PokeDexBarTests/ProfessorTests.swift`

**Interfaces:**
- Consumes: `EggBalance.rollGrade(_:)`, `EggBalance.pickSpecies(from:grade:roll:)`,
  `EggBalance.rollShiny(_:hasCharm:)`, `RegionBalance.rollRegion(speciesID:roll:pick:)`,
  `BirthFormBalance.rollBirthForm(baseID:roll:pick:homeRegion:)`, `VivillonRegions.current`,
  `PokemonNature.allCases`, `BaseSpecies`
- Produces:
  - `static func ProfessorRoll.hash(_ text: String) -> UInt64`
  - `static func ProfessorRoll.unit(date: String, slot: Int, salt: UInt64) -> Double`
  - `struct ProfessorOffer { var id: UUID; var individual: Individual; var claimed: Bool }`
  - `static let ProfessorBalance.offerCount = 3`
  - `static func ProfessorBalance.price(grade: Grade) -> Int`
  - `func PlayerStore.refreshProfessorOffers(index: [BaseSpecies])`
  - `@discardableResult func PlayerStore.acceptProfessorOffer(offerID: UUID) -> Individual?`
  - `PlayerState.professorOfferDate: String`, `PlayerState.professorOffers: [ProfessorOffer]`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`ProfessorTests.swift` 에 더한다.

```swift
    // MARK: 결정적 굴림

    /// **`String.hashValue` 를 쓰면 안 된다** — Swift 기본 해시는 프로세스마다 무작위로
    /// 시딩되므로 앱을 껐다 켤 때마다 다른 값이 나온다. FNV-1a 는 어디서든 같은 값이다.
    func testTheHashIsStableAndNotSwiftsOwn() {
        XCTAssertEqual(ProfessorRoll.hash("2026-08-11"), ProfessorRoll.hash("2026-08-11"))
        XCTAssertNotEqual(ProfessorRoll.hash("2026-08-11"), ProfessorRoll.hash("2026-08-12"))
        // FNV-1a 64비트 표준 벡터 — 구현이 슬쩍 바뀌면 여기서 걸린다.
        XCTAssertEqual(ProfessorRoll.hash(""), 0xcbf2_9ce4_8422_2325)
    }

    /// 굴림은 0…1 안에 있고, 같은 (날짜·자리·용도) 면 언제나 같다.
    func testRollsAreInRangeAndRepeatable() {
        for slot in 0..<3 {
            for salt in [ProfessorRoll.Salt.grade, .species, .shiny] {
                let a = ProfessorRoll.unit(date: "2026-08-11", slot: slot, salt: salt)
                XCTAssertEqual(a, ProfessorRoll.unit(date: "2026-08-11", slot: slot, salt: salt))
                XCTAssertGreaterThanOrEqual(a, 0)
                XCTAssertLessThan(a, 1)
            }
        }
    }

    /// **자리와 용도가 다르면 값도 달라야 한다.** 같으면 세 자리가 똑같은 포켓몬이 되거나
    /// 등급과 이로치가 붙어 움직인다.
    func testRollsDifferBySlotAndSalt() {
        let bySlot = (0..<3).map { ProfessorRoll.unit(date: "d", slot: $0, salt: ProfessorRoll.Salt.grade) }
        XCTAssertEqual(Set(bySlot).count, 3, "자리마다 굴림이 같다")
        let bySalt = [ProfessorRoll.Salt.grade, .species, .shiny]
            .map { ProfessorRoll.unit(date: "d", slot: 0, salt: $0) }
        XCTAssertEqual(Set(bySalt).count, 3, "용도마다 굴림이 같다")
    }

    // MARK: 오늘의 제안

    private func index() -> [BaseSpecies] {
        [BaseSpecies(id: 1, captureRate: 255, isLegendary: false, isMythical: false),
         BaseSpecies(id: 4, captureRate: 45, isLegendary: false, isMythical: false),
         BaseSpecies(id: 25, captureRate: 190, isLegendary: false, isMythical: false),
         BaseSpecies(id: 133, captureRate: 35, isLegendary: false, isMythical: false),
         BaseSpecies(id: 150, captureRate: 3, isLegendary: true, isMythical: false)]
    }

    /// 날짜가 정해진 뒤 준비하면 3마리가 뜬다.
    func testPreparingTodaysOffers() {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        XCTAssertEqual(store.state.professorOffers.count, 3)
        XCTAssertEqual(store.state.professorOfferDate, "2026-08-11")
        XCTAssertTrue(store.state.professorOffers.allSatisfy { !$0.claimed })
    }

    /// **같은 날 두 번 준비해도 같은 3마리.** 인덱스가 늦게 와서 다시 부르는 일이 실제로 있다.
    func testPreparingTwiceInADayKeepsTheSameThree() {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        let first = store.state.professorOffers.map(\.individual.speciesID)
        store.refreshProfessorOffers(index: index())
        XCTAssertEqual(store.state.professorOffers.map(\.individual.speciesID), first)
    }

    /// **앱을 껐다 켜도 같은 3마리.** 여기가 `String.hashValue` 를 썼을 때 깨지는 자리다 —
    /// 저장된 제안을 지우고 새 프로세스가 다시 굴려도 같은 종이 나와야 한다.
    func testTheSameDayRollsTheSameThreeInAFreshStore() {
        func speciesOfFreshStore() -> [Int] {
            let s = makeStore()
            s.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
            s.refreshProfessorOffers(index: index())
            return s.state.professorOffers.map(\.individual.speciesID)
        }
        XCTAssertEqual(speciesOfFreshStore(), speciesOfFreshStore())
    }

    /// 날짜가 바뀌면 새로 뽑는다.
    func testANewDayRollsNewOffers() {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        let first = store.state.professorOffers.map(\.individual.speciesID)

        store.update(todayTokens: 1, todayDate: "2026-08-12", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        XCTAssertEqual(store.state.professorOfferDate, "2026-08-12")
        XCTAssertNotEqual(store.state.professorOffers.map(\.individual.speciesID), first)
    }

    /// 인덱스가 아직 없으면 아무것도 안 한다 — 빈 후보로 굴리면 크래시다.
    func testAnEmptyIndexPreparesNothing() {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: [])
        XCTAssertTrue(store.state.professorOffers.isEmpty)
        XCTAssertEqual(store.state.professorOfferDate, "")
    }

    // MARK: 교환

    private func preparedStore() -> PlayerStore {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        return store
    }

    /// 포인트가 모자라면 교환 실패 + **포인트 미차감**.
    func testAcceptingWithoutEnoughPointsChangesNothing() {
        let store = preparedStore()
        let offer = store.state.professorOffers[0]
        XCTAssertNil(store.acceptProfessorOffer(offerID: offer.id))
        XCTAssertEqual(store.state.researchPoints, 0)
        XCTAssertTrue(store.state.box.isEmpty)
        XCTAssertFalse(store.state.professorOffers[0].claimed)
    }

    /// 교환하면 값을 치르고 박스와 도감에 들어간다. **보이던 개체 그대로**여야 한다.
    func testAcceptingTakesTheExactPokemonShown() {
        let store = preparedStore()
        store.mutate { $0.researchPoints = 1000 }
        let offer = store.state.professorOffers[0]
        let price = ProfessorBalance.price(grade: offer.individual.grade)

        let taken = store.acceptProfessorOffer(offerID: offer.id)
        XCTAssertEqual(taken?.speciesID, offer.individual.speciesID)
        XCTAssertEqual(taken?.shiny, offer.individual.shiny)
        XCTAssertEqual(taken?.nature, offer.individual.nature)
        XCTAssertEqual(taken?.grade, offer.individual.grade)
        XCTAssertEqual(store.state.researchPoints, 1000 - price)
        XCTAssertEqual(store.state.box.count, 1)
        XCTAssertTrue(store.state.dex.contains(offer.individual.speciesID))
    }

    /// **교환한 자리는 그날 다시 안 채워진다** — 자리는 남고 표시만 붙는다.
    func testAClaimedOfferStaysClaimedForTheDay() {
        let store = preparedStore()
        store.mutate { $0.researchPoints = 1000 }
        let offer = store.state.professorOffers[0]
        store.acceptProfessorOffer(offerID: offer.id)

        XCTAssertEqual(store.state.professorOffers.count, 3, "자리가 없어졌다")
        XCTAssertTrue(store.state.professorOffers[0].claimed)
        XCTAssertNil(store.acceptProfessorOffer(offerID: offer.id), "두 번 데려갔다")
        XCTAssertEqual(store.state.box.count, 1)

        store.refreshProfessorOffers(index: index())
        XCTAssertTrue(store.state.professorOffers[0].claimed, "같은 날에 되살아났다")
    }

    /// **두 재화가 안 섞인다** — 포인트로 알을 못 사고, 토큰으로 제안을 못 산다.
    func testPointsAndTokensNeverMix() {
        let store = preparedStore()
        store.mutate { $0.researchPoints = 1000 }
        let walletBefore = store.state.wallet
        store.acceptProfessorOffer(offerID: store.state.professorOffers[0].id)
        XCTAssertEqual(store.state.wallet, walletBefore, "제안을 토큰으로 샀다")

        let pointsBefore = store.state.researchPoints
        store.update(todayTokens: EggBalance.drawPrice * 2, todayDate: "2026-08-11",
                     hasUsageData: true)
        store.startEgg(grade: .common, speciesID: 1, shiny: false)
        XCTAssertEqual(store.state.researchPoints, pointsBefore, "알을 포인트로 샀다")
    }

    /// 저장 왕복 — 오늘의 제안이 재기동 후에도 남는다.
    func testOffersSurviveARestart() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prof-offers-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        let species = store.state.professorOffers.map(\.individual.speciesID)

        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertEqual(reloaded.state.professorOffers.map(\.individual.speciesID), species)
        XCTAssertEqual(reloaded.state.professorOfferDate, "2026-08-11")
    }

    /// 가격표.
    func testOfferPrices() {
        XCTAssertEqual(ProfessorBalance.price(grade: .common), 10)
        XCTAssertEqual(ProfessorBalance.price(grade: .rare), 25)
        XCTAssertEqual(ProfessorBalance.price(grade: .epic), 60)
        XCTAssertEqual(ProfessorBalance.price(grade: .legendary), 200)
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter ProfessorTests`
Expected: 컴파일 실패 — `cannot find 'ProfessorRoll' in scope`

- [ ] **Step 3: `ProfessorRoll.swift` 를 만든다**

```swift
import Foundation

/// 박사의 제안을 뽑는 **결정적** 굴림.
///
/// 왜 난수기가 아니라 이것인가: 제안 생성은 `baseSpeciesIndex()`(네트워크)를 요구해서, 그날 처음
/// 열었을 때 인덱스가 아직 안 왔으면 생성이 미뤄지고 나중에 다시 불린다. 난수기를 쓰면 재시도할
/// 때마다 다른 3마리가 나와 "인덱스가 오기 전에 껐다 켜면 리롤" 이라는 길이 생긴다. 날짜에서
/// 값을 만들면 몇 번을 다시 굴려도 같은 3마리다.
///
/// (`SeededRNG` 는 `Tests/PokeDexBarTests/TestSupport.swift` 에만 있어 프로덕션에서 못 쓴다.)
enum ProfessorRoll {
    /// 굴림의 용도. 같은 자리에서 등급·종·이로치가 같은 값을 쓰면 서로 붙어 움직인다.
    enum Salt {
        static let grade: UInt64 = 0x01
        static let species: UInt64 = 0x02
        static let shiny: UInt64 = 0x03
        static let nature: UInt64 = 0x04
        static let region: UInt64 = 0x05
        static let regionPick: UInt64 = 0x06
        static let birthForm: UInt64 = 0x07
        static let birthFormPick: UInt64 = 0x08
    }

    /// FNV-1a 64비트.
    ///
    /// **`String.hashValue` 를 쓰면 안 된다** — Swift 기본 해시는 프로세스마다 무작위로 시딩되므로
    /// 앱을 껐다 켤 때마다 다른 값이 나온다. 그러면 이 함수가 존재하는 이유 자체가 없어진다.
    static func hash(_ text: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    /// 0…1 굴림(1 미포함). 같은 (날짜·자리·용도) 면 언제나 같은 값이다.
    static func unit(date: String, slot: Int, salt: UInt64) -> Double {
        // SplitMix64 믹싱 — FNV 는 비트가 고르게 안 퍼져서 하위 비트만 쓰면 편향이 남는다.
        var z = hash(date) &+ (UInt64(bitPattern: Int64(slot)) &* 0x9E37_79B9_7F4A_7C15) &+ salt
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= (z >> 31)
        return Double(z % 1_000_000) / 1_000_000
    }
}
```

- [ ] **Step 4: `ProfessorOffer.swift` 를 만든다**

```swift
import Foundation

/// 오늘의 제안 한 자리.
///
/// **완성된 개체를 그대로 품는다.** 종·이로치·성격·태생폼을 따로 담아 뒀다가 교환할 때 다시
/// 만들면, 화면에 보인 것과 손에 들어오는 것이 갈릴 수 있다. 미리 만들어 두면 그럴 여지가 없다.
struct ProfessorOffer: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var individual: Individual
    /// 오늘 이미 데려갔나. 배열에서 빼지 않고 표시로 남긴다 — 빈 칸 두 개보다 "셋 중 하나는
    /// 이미 데려갔다" 가 사용자에게 더 정확하다.
    var claimed = false
}

/// 박사와의 거래 밸런스.
enum ProfessorBalance {
    /// 하루에 내미는 마릿수.
    static let offerCount = 3

    /// 값 — 보내기 등급기본의 5배. 확정된 한 마리를 고르는 값이므로 보내는 값보다 비싸다.
    static func price(grade: Grade) -> Int { ReleaseBalance.base(grade: grade) * 5 }
}
```

- [ ] **Step 5: `PlayerState` 에 두 필드와 디코딩을 더한다**

`researchPoints` 선언 **아래**:

```swift
    /// 오늘의 제안을 뽑은 날짜. `lastDate` 와 다르면 새로 뽑는다.
    var professorOfferDate = ""
    /// 오늘의 제안. 데려간 자리는 빠지지 않고 `claimed` 로 남는다.
    var professorOffers: [ProfessorOffer] = []
```

`init(from:)` 의 `researchPoints` 줄 **아래**:

```swift
        professorOfferDate = value(.professorOfferDate, "")
        // 제안도 박스·알과 같은 이유로 원소 단위 관대 디코딩한다 — 한 자리가 깨졌다고 오늘 치가
        // 통째로 날아가면 안 된다. 항목이므로 개수는 안 자르고, 말이 안 되는 원소만 버린다.
        let wrappedOffers = (try? c.decode([LossyProfessorOffer].self, forKey: .professorOffers)) ?? []
        professorOffers = wrappedOffers.compactMap(\.offer)
        if professorOffers.count != wrappedOffers.count {
            AppLog.write("PlayerState: dropped \(wrappedOffers.count - professorOffers.count) malformed professor offer(s) on decode")
        }
```

파일 맨 아래 `private struct LossyEgg` **뒤**에:

```swift
/// `[ProfessorOffer]` 원소 단위 관대 디코딩 래퍼 — `LossyEgg` 와 같은 패턴에, 개체 자체의
/// 값 범위 검증(`Individual.sanitized`)을 겸한다.
private struct LossyProfessorOffer: Decodable {
    let offer: ProfessorOffer?
    init(from decoder: Decoder) throws {
        guard var decoded = try? ProfessorOffer(from: decoder), decoded.individual.speciesID >= 1
        else { offer = nil; return }
        decoded.individual = decoded.individual.sanitized()
        offer = decoded
    }
}
```

- [ ] **Step 6: 제안 준비와 교환을 `PlayerStore+Professor.swift` 에 더한다**

```swift
    /// 오늘의 제안을 준비한다. 이미 오늘 것이 있거나 인덱스가 아직 없으면 아무것도 하지 않는다.
    ///
    /// 인덱스가 네트워크로 오므로 이 함수는 하루에 여러 번 불릴 수 있다 — 그래도 `ProfessorRoll`
    /// 이 날짜에서 값을 만들기 때문에 같은 3마리가 나온다.
    func refreshProfessorOffers(index: [BaseSpecies]) {
        guard !index.isEmpty, !state.lastDate.isEmpty else { return }
        guard state.professorOfferDate != state.lastDate else { return }
        let date = state.lastDate
        let offers = (0..<ProfessorBalance.offerCount).map { slot in
            ProfessorOffer(individual: Self.offeredIndividual(date: date, slot: slot,
                                                              index: index, at: currentDate()))
        }
        mutate {
            $0.professorOfferDate = date
            $0.professorOffers = offers
        }
    }

    /// 제안 한 자리의 개체를 만든다. 알이 깨질 때와 **같은 경로**를 지나므로 이로치·성격·지방·
    /// 태생폼이 그대로 실린다.
    ///
    /// **이로치 부적은 안 본다.** 이건 박사가 가진 아이지 사용자의 운이 아니고, 부적을 하루
    /// 중간에 사면 이미 뜬 제안과 앞뒤가 안 맞는다.
    private static func offeredIndividual(date: String, slot: Int,
                                          index: [BaseSpecies], at now: Date) -> Individual {
        func roll(_ salt: UInt64) -> Double { ProfessorRoll.unit(date: date, slot: slot, salt: salt) }
        let grade = EggBalance.rollGrade(roll(ProfessorRoll.Salt.grade))
        let species = EggBalance.pickSpecies(from: index, grade: grade,
                                             roll: roll(ProfessorRoll.Salt.species))
        let natures = PokemonNature.allCases
        let nature = natures[Int(roll(ProfessorRoll.Salt.nature) * Double(natures.count))
                             % natures.count]
        var individual = Individual(
            baseID: species, speciesID: species, pathIDs: [species],
            shiny: EggBalance.rollShiny(roll(ProfessorRoll.Salt.shiny), hasCharm: false),
            nature: nature, exp: 0, obtainedAt: now, grade: grade)
        let region = RegionBalance.rollRegion(speciesID: species,
                                              roll: roll(ProfessorRoll.Salt.region),
                                              pick: roll(ProfessorRoll.Salt.regionPick))
        individual.region = region?.0
        individual.regionVariant = region?.1
        individual.birthForm = BirthFormBalance.rollBirthForm(
            baseID: species, roll: roll(ProfessorRoll.Salt.birthForm),
            pick: roll(ProfessorRoll.Salt.birthFormPick), homeRegion: VivillonRegions.current)
        // 위장은 붙이지 않는다 — 제안은 무엇인지 보여 주고 고르는 자리라, 정체를 숨기면
        // 사용자가 무엇을 사는지 모른 채 값을 치르게 된다.
        return individual
    }

    /// 제안을 교환한다. 포인트가 모자라거나 이미 데려간 자리면 nil — **이때 차감도 없다.**
    @discardableResult
    func acceptProfessorOffer(offerID: UUID) -> Individual? {
        guard let slot = state.professorOffers.firstIndex(where: { $0.id == offerID }),
              !state.professorOffers[slot].claimed else { return nil }
        let offer = state.professorOffers[slot]
        let price = ProfessorBalance.price(grade: offer.individual.grade)
        guard state.researchPoints >= price else { return nil }

        // 보이던 그 개체를 그대로 데려간다. id 와 얻은 시각만 지금 것으로 새로 찍는다 —
        // 제안이 만들어진 시각이 아니라 손에 들어온 시각이 "얻은 날" 이다.
        var taken = offer.individual
        taken.id = UUID()
        taken.obtainedAt = currentDate()
        mutate {
            $0.researchPoints -= price
            $0.professorOffers[slot].claimed = true
            $0.box.append(taken)
            $0.dex.insert(taken.speciesID)
        }
        return taken
    }
```

- [ ] **Step 7: 테스트가 통과하는지 확인한다**

Run: `swift test --filter ProfessorTests`
Expected: PASS (25개)

- [ ] **Step 8: 전체 테스트와 경고를 확인한다**

Run: `swift build 2>&1 | grep -i warning; swift test`
Expected: 경고 출력 없음, 전체 PASS

- [ ] **Step 9: 커밋**

```bash
git add Sources/PokeDexBar/Player/ Tests/PokeDexBarTests/ProfessorTests.swift
git commit -m "feat: roll three Pokemon the Professor offers each day"
```

---

## Task 4: 보내기 화면

되돌릴 수 없는 조작이라 **한 번에 안 나가게** 한다. 이 앱에는 확인 다이얼로그 전례가 없고
팝오버 안에서 `.help()` 조차 안 뜨므로, 모달을 새로 들이지 않고 **버튼 자리를 단계로 바꾼다.**

**Files:**
- Modify: `Sources/PokeDexBar/Core/Localization.swift`
- Modify: `Sources/PokeDexBar/UI/IndividualDetailView.swift` (`actions`)
- Test: `Tests/PokeDexBarTests/ProfessorTests.swift`

**Interfaces:**
- Consumes: `PlayerStore.releaseValue(_:)`, `PlayerStore.releaseToProfessor(individualID:)`,
  `DetailActionButton(title:prominent:action:)` (`#if DEBUG` 레코더 보유)
- Produces: UI 만

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
    // MARK: 보내기 화면

    /// 확인 단계 — 되돌릴 수 없는 조작이라 한 번에 안 나간다. 이로치·전설은 한 단계 더.
    func testConfirmStepsByRarity() {
        XCTAssertEqual(IndividualDetailView.releaseConfirmSteps(shiny: false, grade: .common), 1)
        XCTAssertEqual(IndividualDetailView.releaseConfirmSteps(shiny: false, grade: .rare), 1)
        XCTAssertEqual(IndividualDetailView.releaseConfirmSteps(shiny: true, grade: .common), 2,
                       "이로치를 한 번에 보낼 수 있다")
        XCTAssertEqual(IndividualDetailView.releaseConfirmSteps(shiny: false, grade: .legendary), 2,
                       "전설을 한 번에 보낼 수 있다")
        XCTAssertEqual(IndividualDetailView.releaseConfirmSteps(shiny: true, grade: .legendary), 2)
    }

    /// 상세 화면이 보내기 경로에 닿아 있다.
    func testTheDetailViewReachesTheReleasePath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/IndividualDetailView.swift"), encoding: .utf8)
        XCTAssertTrue(text.contains("releaseToProfessor"), "상세에 보내기 버튼이 없다")
        XCTAssertFalse(text.contains(".help("), "안 뜨는 툴팁이 들어왔다")
    }

    /// 문구가 세 언어를 다 채운다.
    func testReleaseStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.sendToProfessor(4).isEmpty, "\(lang)")
            XCTAssertFalse(l.sendConfirmNoReturn.isEmpty, "\(lang)")
            XCTAssertFalse(l.sendConfirmAgain.isEmpty, "\(lang)")
            XCTAssertFalse(l.sendCancel.isEmpty, "\(lang)")
            XCTAssertFalse(l.sendNow.isEmpty, "\(lang)")
        }
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter ProfessorTests`
Expected: 컴파일 실패 — `type 'IndividualDetailView' has no member 'releaseConfirmSteps'`

- [ ] **Step 3: 문구를 더한다**

`Sources/PokeDexBar/Core/Localization.swift` 의 `detailPartnerOnlyExp` **아래**:

```swift
    /// 박사에게 보내기 — 받을 포인트를 제목에 적어, 누르기 전에 값을 알 수 있게 한다.
    func sendToProfessor(_ points: Int) -> String {
        t("박사에게 보내기 · +\(points)P", "Send to the Professor · +\(points)P",
          "はかせにおくる · +\(points)P")
    }
    var sendConfirmNoReturn: String {
        t("돌아오지 않아요. 정말 보낼까요?",
          "This cannot be undone. Send it?",
          "もどってきません。おくりますか？")
    }
    var sendConfirmAgain: String {
        t("한 번 더 물을게요 — 다시 만나기 어려운 아이예요",
          "Asking once more — this one is hard to come by",
          "もういちどだけ — なかなか出会えない子です")
    }
    var sendCancel: String { t("그만두기", "Keep it", "やめる") }
    var sendNow: String { t("보내기", "Send", "おくる") }
```

- [ ] **Step 4: 확인 단계 판정과 버튼을 더한다**

`Sources/PokeDexBar/UI/IndividualDetailView.swift` 에 `@State` 와 순수 판정을 더한다.
`@State private var sparkleBeat = 0` **아래**:

```swift
    /// 보내기 확인이 몇 단계까지 진행됐나. 0 이면 아직 안 눌렀다.
    @State private var releaseStep = 0
```

`isFoundEggCandidate` 정의 **아래**:

```swift
    /// 보내기 전에 몇 번 확인하나. **이로치와 전설은 한 번 더 묻는다** — 되돌릴 수 없는데
    /// 다시 만나기 어려운 아이라, 실수 한 번의 값이 다른 개체와 다르다.
    nonisolated static func releaseConfirmSteps(shiny: Bool, grade: Grade) -> Int {
        (shiny || grade == .legendary) ? 2 : 1
    }
```

`actions` 안, `candySection` **위**에 더한다:

```swift
            releaseSection
```

그리고 `voucherSection`/`foundEggSection` 정의 근처에:

```swift
    /// 박사에게 보내기 — 단계로 나눠 한 번에 안 나가게 한다. 이 앱에는 확인 다이얼로그 전례가
    /// 없고 팝오버 안에서는 `.help()` 조차 안 뜨므로, 모달을 새로 들이지 않고 버튼 자리를 바꾼다.
    @ViewBuilder
    private var releaseSection: some View {
        // `releaseValue` 가 nil 이면 보낼 수 없는 개체다(파트너) — 조건을 여기서 따로 적으면
        // 스토어와 갈린다. 알 발견에서 실제로 그렇게 갈린 적이 있다.
        if let points = store.releaseValue(individual) {
            let steps = Self.releaseConfirmSteps(shiny: individual.shiny, grade: individual.grade)
            VStack(alignment: .leading, spacing: 4) {
                if releaseStep == 0 {
                    DetailActionButton(title: l.sendToProfessor(points), prominent: false) {
                        releaseStep = 1
                    }
                } else {
                    Text(releaseStep < steps ? l.sendConfirmNoReturn : l.sendConfirmAgain)
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        DetailActionButton(title: l.sendCancel, prominent: false) {
                            releaseStep = 0
                        }
                        DetailActionButton(title: l.sendNow, prominent: true) {
                            if releaseStep < steps {
                                releaseStep += 1
                            } else {
                                store.releaseToProfessor(individualID: individual.id)
                                releaseStep = 0
                                onBack()   // 박스에서 사라진 개체의 상세에 남아 있을 수 없다
                            }
                        }
                    }
                }
            }
            .task(id: individual.id) { releaseStep = 0 }   // 다른 개체를 열면 처음부터
        }
    }
```

- [ ] **Step 5: 테스트가 통과하는지 확인한다**

Run: `swift test --filter ProfessorTests`
Expected: PASS (28개)

- [ ] **Step 6: 전체 테스트와 경고를 확인한다**

Run: `swift build 2>&1 | grep -i warning; swift test`
Expected: 경고 출력 없음, 전체 PASS

- [ ] **Step 7: 커밋**

```bash
git add Sources/PokeDexBar/Core/Localization.swift Sources/PokeDexBar/UI/IndividualDetailView.swift Tests/PokeDexBarTests/ProfessorTests.swift
git commit -m "feat: let the Box send a Pokemon to the Professor"
```

---

## Task 5: 박사의 제안 화면

**Files:**
- Create: `Sources/PokeDexBar/UI/ProfessorOfferSection.swift`
- Modify: `Sources/PokeDexBar/UI/ShopTabView.swift:38-46` (`body`)
- Modify: `Sources/PokeDexBar/Core/Localization.swift`
- Test: `Tests/PokeDexBarTests/ProfessorTests.swift`

**Interfaces:**
- Consumes: `PlayerStore.refreshProfessorOffers(index:)`, `PlayerStore.acceptProfessorOffer(offerID:)`,
  `ProfessorBalance.price(grade:)`, `SpriteView`(`Sources/PokeDexBar/UI/CompanionView.swift:61`)
- Produces: UI 만 — 이후 태스크 없음

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
    // MARK: 제안 화면

    /// 살 수 있나 — 순수 판정이라 뷰 없이 잠근다.
    func testOfferAffordability() {
        XCTAssertTrue(ProfessorOfferSection.canAfford(price: 10, points: 10))
        XCTAssertTrue(ProfessorOfferSection.canAfford(price: 10, points: 11))
        XCTAssertFalse(ProfessorOfferSection.canAfford(price: 10, points: 9))
    }

    /// 상점이 제안 경로에 닿아 있다 — 안 닿으면 제안을 영원히 못 본다.
    func testTheShopReachesTheOfferSection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shop = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/ShopTabView.swift"), encoding: .utf8)
        XCTAssertTrue(shop.contains("ProfessorOfferSection"), "상점에 박사의 제안이 없다")
        let section = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/ProfessorOfferSection.swift"), encoding: .utf8)
        XCTAssertTrue(section.contains("acceptProfessorOffer"), "교환 경로에 안 닿는다")
        XCTAssertTrue(section.contains("refreshProfessorOffers"), "제안을 준비하지 않는다")
        XCTAssertFalse(section.contains(".help("), "안 뜨는 툴팁이 들어왔다")
    }

    /// 문구가 세 언어를 다 채운다.
    func testOfferStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.professorOffersTitle.isEmpty, "\(lang)")
            XCTAssertFalse(l.researchPoints(7).isEmpty, "\(lang)")
            XCTAssertFalse(l.offerTaken.isEmpty, "\(lang)")
            XCTAssertFalse(l.offerPrice(10).isEmpty, "\(lang)")
        }
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter ProfessorTests`
Expected: 컴파일 실패 — `cannot find 'ProfessorOfferSection' in scope`

- [ ] **Step 3: 문구를 더한다**

`sendNow` **아래**:

```swift
    var professorOffersTitle: String { t("박사의 제안", "The Professor's offer", "はかせのていあん") }
    func researchPoints(_ points: Int) -> String {
        t("\(points)P", "\(points)P", "\(points)P")
    }
    var offerTaken: String { t("데려갔어요", "Taken", "つれていきました") }
    func offerPrice(_ points: Int) -> String {
        t("\(points)P 로 데려가기", "Take for \(points)P", "\(points)Pでつれていく")
    }
    var professorOffersEmpty: String {
        t("오늘의 제안을 준비하고 있어요", "Getting today's offer ready",
          "きょうのていあんをじゅんびしています")
    }
```

- [ ] **Step 4: `ProfessorOfferSection.swift` 를 만든다**

```swift
import SwiftUI

/// 상점 맨 위 "박사의 제안" — 오늘의 3마리와 포인트 잔액.
///
/// 새 탭을 만들지 않는다. 값을 치르고 무언가를 얻는 자리는 이미 상점이고, 포인트 잔액도
/// 지갑 옆에 있어야 두 재화가 서로 다른 것이라는 게 한눈에 보인다.
struct ProfessorOfferSection: View {
    let store: PlayerStore
    /// 베이스 종 인덱스를 받아 올 곳. 상점이 뽑기에 쓰는 것과 같은 프로바이더다.
    let provider: any PokeProviding

    /// 받아 온 후보. 네트워크로 오므로 처음엔 비어 있고, 그동안은 준비 중이라고 적는다.
    @State private var index: [BaseSpecies] = []

    private var l: L { store.l }

    /// 살 수 있나. 순수 함수라 뷰 없이 테스트로 잠근다.
    nonisolated static func canAfford(price: Int, points: Int) -> Bool { points >= price }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l.professorOffersTitle)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(l.researchPoints(store.state.researchPoints))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if store.state.professorOffers.isEmpty {
                Text(l.professorOffersEmpty)
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(store.state.professorOffers) { offer in
                        card(offer)
                    }
                }
            }
        }
        .task {
            // 인덱스는 네트워크로 온다. 늦게 착지해도 안전하다 — `refreshProfessorOffers` 가
            // `professorOfferDate != lastDate` 를 스스로 확인하므로, 이미 준비됐으면 아무것도
            // 안 하고 아직이면 그때 준비한다. 여러 번 불려도 같은 3마리다(`ProfessorRoll`).
            guard index.isEmpty else { return }
            guard let fetched = try? await provider.baseSpeciesIndex(), !fetched.isEmpty else { return }
            guard !Task.isCancelled else { return }   // 팝오버가 닫혔으면 착지하지 않는다
            index = fetched
            store.refreshProfessorOffers(index: fetched)
        }
    }

    @ViewBuilder
    private func card(_ offer: ProfessorOffer) -> some View {
        let individual = offer.individual
        let price = ProfessorBalance.price(grade: individual.grade)
        let affordable = Self.canAfford(price: price, points: store.state.researchPoints)
        VStack(spacing: 3) {
            SpriteView(speciesID: individual.displaySpeciesID, form: individual.spriteForm,
                       size: 40, shiny: individual.showsShiny)
                .frame(width: 40, height: 40)
            Text(individual.grade.label(store.language))
                .font(.system(size: 8)).foregroundStyle(.secondary)
            if offer.claimed {
                Text(l.offerTaken).font(.system(size: 9)).foregroundStyle(.tertiary)
            } else {
                Button { store.acceptProfessorOffer(offerID: offer.id) } label: {
                    Text(l.offerPrice(price))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(affordable ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(affordable ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(!affordable)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(offer.claimed ? 0.5 : 1)
        .padding(6)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 5: 상점에 얹는다**

`Sources/PokeDexBar/UI/ShopTabView.swift` 의 `body` 안, `walletRow` **아래·`drawSection` 위**:

```swift
                ProfessorOfferSection(store: store, provider: provider)
                Divider()
```

`provider` 는 `ShopTabView` 가 이미 들고 있는 `let provider: any PokeProviding` 다
(`ShopTabView.swift:6`). **상점은 인덱스를 저장하지 않는다** — 뽑기 `task` 안에서 지역변수로만
쓴다(`ShopTabView.swift:153`). 그래서 섹션이 자기 것을 따로 받아 온다. 상점에 새 `@State` 를
만들지 않는다.

- [ ] **Step 6: 테스트가 통과하는지 확인한다**

Run: `swift test --filter ProfessorTests`
Expected: PASS (31개)

- [ ] **Step 7: 전체 테스트와 경고를 확인한다**

Run: `swift build 2>&1 | grep -i warning; swift test`
Expected: 경고 출력 없음, 전체 PASS

- [ ] **Step 8: 실제 앱으로 눈으로 확인한다**

```bash
PTB_DEV=1 ./scripts/build-app.sh && open --env PTB_SEED_EXP=100 "./build/PokeDexBar Dev.app"
```

확인할 것 — 상점 맨 위에 제안 3마리와 포인트 잔액이 뜨는가, 박스에서 개체를 열면 보내기 버튼이
있고 파트너에는 없는가, 누르면 확인 단계가 뜨고 이로치·전설은 한 번 더 묻는가, 보낸 뒤 상세가
닫히고 포인트가 오르는가, 포인트가 모자란 제안의 버튼이 비활성인가.

> **`PTB_DEV=1` 이 필수다.** 없으면 릴리스 구성으로 지어 `/Applications` 의 실제 앱과 같은
> 세이브를 쓴다. 실제 세이브는 어떤 경우에도 손으로 고치지 않는다.

- [ ] **Step 9: 커밋**

```bash
git add Sources/PokeDexBar/UI/ Sources/PokeDexBar/Core/Localization.swift Tests/PokeDexBarTests/ProfessorTests.swift
git commit -m "feat: show the Professor's daily offer in the shop"
```

---

## 배포 전에 (이 계획의 범위 밖, 잊지 말 것)

`Sources/PokeDexBar/UI/` 를 건드린 `feat:` 커밋이 있으므로 **`assets/` 에 새 파일이 없으면
`release.sh` 가 중단한다**(프롬프트로 못 넘기는 하드 게이트).

```bash
PTB_SCREENSHOTS=1 PTB_APP_VERSION=<버전> swift test --filter ScreenshotGeneratorTests
```

`Tests/PokeDexBarTests/ScreenshotGenerator.swift` 에 박사의 제안 배너를 더한다 —
`foundEggBanner()` 가 바로 옆에 있는 본보기다. README ×3 과 랜딩(gh-pages)도 같이 간다.
