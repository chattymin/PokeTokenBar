# PokeDexBar 2a 구현 계획 — 기반 (스타터 · 박스 · 도감)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 알로 시작해 자동으로 자라던 게임을, 스타터를 골라 키우고 손으로 진화시키며 개체를 모으는 게임으로 바꾼다. 알·뽑기·상점은 2b.

**Architecture:** 업스트림 `CompanionState`/`CompanionStore`(한 마리·졸업·자동 진화)를 새 `PlayerState`/`PlayerStore`(개체 목록·지갑·도감)로 교체한다. 새 모델을 먼저 세우고(1~4), 앱의 표시 경로를 그 위로 옮긴 뒤(5), 박스·도감 화면을 붙이고(6~7), 마지막에 구 시스템을 지운다(8).

**Tech Stack:** Swift 6, SwiftUI + AppKit, XCTest. 외부 의존성 없음.

## Global Constraints

- `swift-tools-version: 6.0`, 플랫폼 하한 `macOS 14`, 외부 Swift 의존성 없음
- 커밋 메시지는 **영어**(저장소 규약), 코드 주석은 **한국어**
- 각 태스크는 `swift build`(경고 0)와 `swift test`(전부 통과)로 끝난다
- 하위호환을 만들지 않는다 — 기존 상태 파일이 있으면 새 형식으로 초기화하고 로그를 남긴다
- 스타터는 이로치가 아니다. 이로치는 2b(부화·반짝이는 사탕)에서만 나온다
- 도감 등록 기준은 "한 번이라도 보유한 종" — 진화로 지나온 형태도 포함한다
- 진화는 임계 도달 시 **사용자가 눌러야** 일어난다. 자동 진화는 금지
- 1025칸 도감은 보이는 칸만 스프라이트를 받는다(지연 그리드)

---

### Task 1: 상태 모델 (Grade · Individual · PlayerState)

**Files:**
- Create: `Sources/PokeDexBar/Player/Grade.swift`
- Create: `Sources/PokeDexBar/Player/Individual.swift`
- Create: `Sources/PokeDexBar/Player/PlayerState.swift`
- Test: `Tests/PokeDexBarTests/PlayerStateTests.swift`

**Interfaces:**
- Consumes: 기존 `Rarity`(`Core/CompanionModel.swift`), `PokemonNature`(같은 파일)
- Produces:
  - `enum Grade: String, Codable, Sendable, CaseIterable { case common, rare, epic, legendary }` + `static func from(captureRate:isLegendary:isMythical:) -> Grade` + `init(rarity: Rarity)` + `var label: String`
  - `struct Individual: Identifiable, Codable, Sendable, Equatable` — 필드 `id: UUID, baseID: Int, speciesID: Int, pathIDs: [Int], shiny: Bool, nature: PokemonNature, exp: Int, obtainedAt: Date, grade: Grade`, 계산 속성 `stageIndex: Int`
  - `struct PlayerState: Codable, Sendable` — 필드 `starterChosen, earnedTokens, spentTokens, claimedTodayTokens, lastDate, installBaselineSet, partnerID, box, dex, slots, inventory, ownsShinyCharm`, 계산 속성 `wallet: Int`, `partner: Individual?`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/PlayerStateTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

final class GradeTests: XCTestCase {
    /// 등급 경계는 스펙 표 그대로 — 커먼 ≥121, 레어 46~120, 에픽 ≤45, 레전더리는 전설·환상.
    func testGradeFromCaptureRate() {
        XCTAssertEqual(Grade.from(captureRate: 255, isLegendary: false, isMythical: false), .common)
        XCTAssertEqual(Grade.from(captureRate: 121, isLegendary: false, isMythical: false), .common)
        XCTAssertEqual(Grade.from(captureRate: 120, isLegendary: false, isMythical: false), .rare)
        XCTAssertEqual(Grade.from(captureRate: 46, isLegendary: false, isMythical: false), .rare)
        XCTAssertEqual(Grade.from(captureRate: 45, isLegendary: false, isMythical: false), .epic)
        XCTAssertEqual(Grade.from(captureRate: 3, isLegendary: false, isMythical: false), .epic)
        XCTAssertEqual(Grade.from(captureRate: 3, isLegendary: true, isMythical: false), .legendary)
        XCTAssertEqual(Grade.from(captureRate: 255, isLegendary: false, isMythical: true), .legendary)
    }

    /// 업스트림 Rarity 와의 대응 — uncommon 이 레어, rare 가 에픽이다(이름만 다르고 경계는 같다).
    func testGradeFromRarity() {
        XCTAssertEqual(Grade(rarity: .common), .common)
        XCTAssertEqual(Grade(rarity: .uncommon), .rare)
        XCTAssertEqual(Grade(rarity: .rare), .epic)
        XCTAssertEqual(Grade(rarity: .legendary), .legendary)
    }
}

final class IndividualTests: XCTestCase {
    private func make(path: [Int]) -> Individual {
        Individual(baseID: path.first ?? 1, speciesID: path.last ?? 1, pathIDs: path,
                   nature: .serious, obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
    }

    func testStageIndexFollowsPath() {
        XCTAssertEqual(make(path: [1]).stageIndex, 0)
        XCTAssertEqual(make(path: [1, 2]).stageIndex, 1)
        XCTAssertEqual(make(path: [1, 2, 3]).stageIndex, 2)
    }

    /// 경로가 비어 있어도(손상 상태) 음수 단계로 새지 않는다.
    func testEmptyPathIsStageZero() {
        XCTAssertEqual(make(path: []).stageIndex, 0)
    }
}

final class PlayerStateTests: XCTestCase {
    private func individual(_ id: UUID) -> Individual {
        Individual(id: id, baseID: 1, speciesID: 1, pathIDs: [1],
                   nature: .serious, obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
    }

    func testWalletIsEarnedMinusSpent() {
        var s = PlayerState()
        s.earnedTokens = 1_000
        s.spentTokens = 400
        XCTAssertEqual(s.wallet, 600)
    }

    /// 지출이 적립을 넘는 손상 상태에서도 음수로 새지 않는다.
    func testWalletNeverNegative() {
        var s = PlayerState()
        s.earnedTokens = 100
        s.spentTokens = 500
        XCTAssertEqual(s.wallet, 0)
    }

    func testPartnerResolvesFromBox() {
        let id = UUID()
        var s = PlayerState()
        s.box = [individual(UUID()), individual(id)]
        s.partnerID = id
        XCTAssertEqual(s.partner?.id, id)
    }

    /// 파트너가 박스에서 사라졌으면 nil — 매달린 포인터로 크래시하지 않는다.
    func testMissingPartnerIsNil() {
        var s = PlayerState()
        s.partnerID = UUID()
        XCTAssertNil(s.partner)
    }

    func testCodableRoundTrip() throws {
        var s = PlayerState()
        s.starterChosen = true
        s.earnedTokens = 12_345
        s.box = [individual(UUID())]
        s.dex = [1, 4, 7]
        s.slots = 4
        s.inventory = ["expCandy": 2]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PlayerState.self, from: data)
        XCTAssertTrue(back.starterChosen)
        XCTAssertEqual(back.earnedTokens, 12_345)
        XCTAssertEqual(back.box.count, 1)
        XCTAssertEqual(back.dex, [1, 4, 7])
        XCTAssertEqual(back.slots, 4)
        XCTAssertEqual(back.inventory["expCandy"], 2)
    }

    /// 필드가 빠진 저장분(형식이 자라는 중)도 기본값으로 읽힌다 — 한 필드 때문에 박스를 날리지 않는다.
    func testLenientDecodeOfMissingFields() throws {
        let json = #"{"starterChosen":true,"earnedTokens":50}"#
        let s = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertTrue(s.starterChosen)
        XCTAssertEqual(s.earnedTokens, 50)
        XCTAssertEqual(s.slots, 3)
        XCTAssertTrue(s.box.isEmpty)
        XCTAssertTrue(s.dex.isEmpty)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter "GradeTests|IndividualTests|PlayerStateTests"`
Expected: FAIL — `cannot find 'Grade' in scope`

- [ ] **Step 3: Grade 구현**

`Sources/PokeDexBar/Player/Grade.swift`:

```swift
import Foundation

/// 알·개체의 등급. 경계는 업스트림 `Rarity` 와 같고 이 게임의 어휘로 이름만 바꿨다
/// (uncommon → 레어, rare → 에픽). 뽑기 확률·진화 임계·표시가 이 값을 쓴다.
enum Grade: String, Codable, Sendable, CaseIterable {
    case common, rare, epic, legendary

    static func from(captureRate: Int, isLegendary: Bool, isMythical: Bool) -> Grade {
        if isLegendary || isMythical { return .legendary }
        if captureRate <= 45 { return .epic }
        if captureRate <= 120 { return .rare }
        return .common
    }

    init(rarity: Rarity) {
        switch rarity {
        case .common: self = .common
        case .uncommon: self = .rare
        case .rare: self = .epic
        case .legendary: self = .legendary
        }
    }

    var label: String {
        switch self {
        case .common: "커먼"
        case .rare: "레어"
        case .epic: "에픽"
        case .legendary: "레전더리"
        }
    }
}
```

- [ ] **Step 4: Individual 구현**

`Sources/PokeDexBar/Player/Individual.swift`:

```swift
import Foundation

/// 보유 개체 하나. 종(speciesID)이 아니라 개체가 단위다 — 같은 종을 여러 마리 가질 수 있고
/// 각자 이로치·성격·경험치·진화 단계가 따로 간다.
struct Individual: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    /// 처음 만난 형태(스타터로 고르거나 부화한 종). 진화해도 바뀌지 않는다.
    var baseID: Int
    /// 지금 형태.
    var speciesID: Int
    /// 실제로 지나온 경로(baseID 로 시작). 분기 진화에서 어느 쪽으로 갔는지 남는다.
    var pathIDs: [Int]
    var shiny = false
    var nature: PokemonNature
    /// 현재 단계에서 쌓은 경험치. 진화하면 0으로 돌아가고 초과분만 이월한다.
    var exp = 0
    var obtainedAt: Date
    var grade: Grade

    /// 몇 번째 형태인가(0 = 아직 안 진화). 경로가 비어도 음수로 새지 않는다.
    var stageIndex: Int { max(0, pathIDs.count - 1) }
}
```

- [ ] **Step 5: PlayerState 구현**

`Sources/PokeDexBar/Player/PlayerState.swift`:

```swift
import Foundation

/// 영속 상태. 업스트림 `CompanionState`(한 마리·졸업)를 대체한다.
struct PlayerState: Codable, Sendable {
    /// 첫 실행 스타터 선택을 마쳤나. false 면 팝오버가 선택 화면만 띄운다.
    var starterChosen = false
    /// 설치 이후 누적 사용 토큰 — 재화의 원천이자 파트너 경험치의 원천.
    var earnedTokens = 0
    /// 상점 지출 누적.
    var spentTokens = 0
    /// 오늘 어디까지 적립했나(이 기기 장부). 날짜가 바뀌면 0으로.
    var claimedTodayTokens = 0
    var lastDate = ""
    /// 설치 기준선을 잡았나 — 설치 이전 사용량은 세지 않는다.
    var installBaselineSet = false
    var partnerID: UUID?
    /// 보유 개체. 중복 허용.
    var box: [Individual] = []
    /// 한 번이라도 보유한 종 번호.
    var dex: Set<Int> = []
    /// 동시 부화 슬롯 수(2b 에서 쓴다). 기본 3, 상한 6.
    var slots = 3
    /// 아이템 종류 → 개수.
    var inventory: [String: Int] = [:]
    var ownsShinyCharm = false

    /// 상점에서 쓸 수 있는 재화.
    var wallet: Int { max(0, earnedTokens - spentTokens) }
    /// 데리고 다니는 개체. 박스에서 사라졌으면 nil.
    var partner: Individual? { box.first { $0.id == partnerID } }

    init() {}

    // 관대 디코딩 — 형식이 자라는 중에 한 필드가 빠져도 박스·도감을 통째로 날리지 않는다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        starterChosen = value(.starterChosen, false)
        earnedTokens = value(.earnedTokens, 0)
        spentTokens = value(.spentTokens, 0)
        claimedTodayTokens = value(.claimedTodayTokens, 0)
        lastDate = value(.lastDate, "")
        installBaselineSet = value(.installBaselineSet, false)
        partnerID = try? c.decode(UUID.self, forKey: .partnerID)
        box = value(.box, [])
        dex = value(.dex, [])
        slots = value(.slots, 3)
        inventory = value(.inventory, [:])
        ownsShinyCharm = value(.ownsShinyCharm, false)
    }
}
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `swift test --filter "GradeTests|IndividualTests|PlayerStateTests"`
Expected: 전부 통과(11개)

- [ ] **Step 7: 전체 테스트 + 커밋**

Run: `swift build && swift test`
Expected: 경고 0, 전부 통과

```bash
git add -A
git commit -m "feat: add the player state model built around individuals

The inherited state tracked one companion at a time and dropped it on
graduation. Model the collection as a box of individuals instead, each with
its own shiny, nature, and experience, plus a dex of species ever owned and
a wallet of burned tokens, so duplicates become normal."
```

---

### Task 2: 밸런스 (경험치 임계 · 스타터 목록)

**Files:**
- Create: `Sources/PokeDexBar/Player/ExpBalance.swift`
- Create: `Sources/PokeDexBar/Player/StarterCatalog.swift`
- Test: `Tests/PokeDexBarTests/ExpBalanceTests.swift`

**Interfaces:**
- Consumes: `Grade` (Task 1), `SpeciesSlug.slug(_:)`(`Core/SpeciesSlug.swift`)
- Produces:
  - `enum ExpBalance { static func threshold(grade: Grade, stageIndex: Int) -> Int }`
  - `enum StarterCatalog { static let byGeneration: [(generation: Int, speciesIDs: [Int])]; static let all: [Int]; static func contains(_ speciesID: Int) -> Bool }`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/ExpBalanceTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

final class ExpBalanceTests: XCTestCase {
    /// 스펙 표 그대로 — 1→2단계는 등급별 기본값, 2→3단계는 그 3배.
    func testThresholdTable() {
        XCTAssertEqual(ExpBalance.threshold(grade: .common, stageIndex: 0), 50_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .common, stageIndex: 1), 150_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .rare, stageIndex: 0), 100_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .rare, stageIndex: 1), 300_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .epic, stageIndex: 0), 200_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .epic, stageIndex: 1), 600_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .legendary, stageIndex: 0), 400_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .legendary, stageIndex: 1), 1_200_000_000)
    }

    /// 등급이 높을수록 오래 걸린다 — 순서가 뒤집히면 밸런스가 무너진다.
    func testHigherGradeCostsMore() {
        for stage in 0...1 {
            let common = ExpBalance.threshold(grade: .common, stageIndex: stage)
            let rare = ExpBalance.threshold(grade: .rare, stageIndex: stage)
            let epic = ExpBalance.threshold(grade: .epic, stageIndex: stage)
            let legendary = ExpBalance.threshold(grade: .legendary, stageIndex: stage)
            XCTAssertLessThan(common, rare)
            XCTAssertLessThan(rare, epic)
            XCTAssertLessThan(epic, legendary)
        }
    }

    /// 3형태를 넘는 경로(비정상)에서도 2→3 임계로 수렴하고 0이나 음수가 되지 않는다.
    func testDeepStagesStayPositive() {
        XCTAssertGreaterThan(ExpBalance.threshold(grade: .common, stageIndex: 5), 0)
    }
}

final class StarterCatalogTests: XCTestCase {
    func testNineGenerationsOfThree() {
        XCTAssertEqual(StarterCatalog.byGeneration.count, 9)
        XCTAssertEqual(StarterCatalog.all.count, 27)
        for entry in StarterCatalog.byGeneration {
            XCTAssertEqual(entry.speciesIDs.count, 3, "\(entry.generation)세대 스타터가 3마리가 아니다")
        }
    }

    func testKnownStarters() {
        XCTAssertEqual(StarterCatalog.byGeneration.first?.speciesIDs, [1, 4, 7])
        XCTAssertEqual(StarterCatalog.byGeneration.last?.speciesIDs, [906, 909, 912])
        XCTAssertTrue(StarterCatalog.contains(495))
        XCTAssertFalse(StarterCatalog.contains(25))
    }

    /// 스타터는 전부 스프라이트를 그릴 수 있어야 한다 — 못 그리는 칸이 선택지에 있으면 안 된다.
    func testEveryStarterHasASprite() {
        for id in StarterCatalog.all {
            XCTAssertNotNil(SpeciesSlug.slug(id), "종 \(id) 슬러그 없음")
        }
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter "ExpBalanceTests|StarterCatalogTests"`
Expected: FAIL — `cannot find 'ExpBalance' in scope`

- [ ] **Step 3: ExpBalance 구현**

`Sources/PokeDexBar/Player/ExpBalance.swift`:

```swift
import Foundation

/// 진화 임계. 파트너는 토큰 사용량만큼 경험치를 얻으므로 이 값이 곧 "얼마나 써야 진화하나"다.
enum ExpBalance {
    /// 등급·단계별 임계. 2→3단계는 1→2단계의 3배 — 뒤로 갈수록 무겁게.
    static func threshold(grade: Grade, stageIndex: Int) -> Int {
        let base: Int = switch grade {
        case .common: 50_000_000
        case .rare: 100_000_000
        case .epic: 200_000_000
        case .legendary: 400_000_000
        }
        return stageIndex <= 0 ? base : base * 3
    }
}
```

- [ ] **Step 4: StarterCatalog 구현**

`Sources/PokeDexBar/Player/StarterCatalog.swift`:

```swift
import Foundation

/// 첫 실행에 고르는 스타터. 각 세대의 1단계(진화 전) 3마리씩 — 전 세대 27마리.
enum StarterCatalog {
    static let byGeneration: [(generation: Int, speciesIDs: [Int])] = [
        (1, [1, 4, 7]),          // 이상해씨 · 파이리 · 꼬부기
        (2, [152, 155, 158]),    // 치코리타 · 브케인 · 리아코
        (3, [252, 255, 258]),    // 나무지기 · 아차모 · 물짱이
        (4, [387, 390, 393]),    // 모부기 · 불꽃숭이 · 팽도리
        (5, [495, 498, 501]),    // 주리비얀 · 뚜꾸리 · 수댕이
        (6, [650, 653, 656]),    // 도치마론 · 푸호꼬 · 개구마르
        (7, [722, 725, 728]),    // 나몰빼미 · 냐오불 · 누리공
        (8, [810, 813, 816]),    // 흥나숭 · 염버니 · 울머기
        (9, [906, 909, 912]),    // 나오하 · 뜨아거 · 꾸왁스
    ]

    static let all: [Int] = byGeneration.flatMap(\.speciesIDs)

    static func contains(_ speciesID: Int) -> Bool { all.contains(speciesID) }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter "ExpBalanceTests|StarterCatalogTests"`
Expected: 전부 통과(7개)

- [ ] **Step 6: 전체 테스트 + 커밋**

Run: `swift build && swift test`
Expected: 경고 0, 전부 통과

```bash
git add -A
git commit -m "feat: add evolution thresholds and the starter roster

Experience now comes from tokens the partner burns, so the evolution
thresholds double as the price of a stage. Table them per grade, with the
second evolution costing three times the first, and list the 27 first-stage
starters the game opens on."
```

---

### Task 3: PlayerStore — 영속 · 지갑 · 도감 · 스타터

**Files:**
- Create: `Sources/PokeDexBar/Player/PlayerStore.swift`
- Test: `Tests/PokeDexBarTests/PlayerStoreTests.swift`

**Interfaces:**
- Consumes: `PlayerState`, `Individual`, `Grade` (Task 1), `StarterCatalog` (Task 2)
- Produces: `@MainActor @Observable final class PlayerStore`
  - `init(fileURL: URL? = nil, rng: any RandomNumberGenerator = SystemRandomNumberGenerator(), now: @escaping () -> Date = Date.init)`
  - `private(set) var state: PlayerState`
  - `func update(todayTokens: Int, todayDate: String, hasUsageData: Bool)` — 설치 기준선·지갑 적립·파트너 경험치
  - `@discardableResult func chooseStarter(speciesID: Int, grade: Grade) -> Individual?`
  - `func setPartner(_ id: UUID)`
  - `func registerInDex(_ speciesID: Int)`
  - `static func defaultURL() -> URL`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/PlayerStoreTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

@MainActor
final class PlayerStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(seed: UInt64 = 1) -> (PlayerStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("player-\(UUID().uuidString).json")
        return (PlayerStore(fileURL: url, rng: SeededRNG(seed: seed), now: { self.now }), url)
    }

    // MARK: 스타터

    func testChoosingAStarterFillsBoxPartnerAndDex() {
        let (store, _) = makeStore()
        let picked = store.chooseStarter(speciesID: 4, grade: .epic)
        XCTAssertNotNil(picked)
        XCTAssertTrue(store.state.starterChosen)
        XCTAssertEqual(store.state.box.count, 1)
        XCTAssertEqual(store.state.partner?.speciesID, 4)
        XCTAssertEqual(store.state.partner?.pathIDs, [4])
        XCTAssertTrue(store.state.dex.contains(4))
    }

    /// 스타터는 이로치가 아니다 — 첫 개체는 복구할 수 없으니 운에 맡기지 않는다.
    func testStarterIsNeverShiny() {
        for seed in UInt64(1)...20 {
            let (store, _) = makeStore(seed: seed)
            store.chooseStarter(speciesID: 1, grade: .epic)
            XCTAssertFalse(store.state.partner?.shiny ?? true)
        }
    }

    /// 스타터 목록 밖의 종은 고를 수 없다.
    func testRejectsNonStarter() {
        let (store, _) = makeStore()
        XCTAssertNil(store.chooseStarter(speciesID: 25, grade: .common))
        XCTAssertFalse(store.state.starterChosen)
        XCTAssertTrue(store.state.box.isEmpty)
    }

    /// 두 번 고를 수 없다 — 이미 골랐으면 무시한다.
    func testCannotChooseTwice() {
        let (store, _) = makeStore()
        store.chooseStarter(speciesID: 1, grade: .epic)
        XCTAssertNil(store.chooseStarter(speciesID: 4, grade: .epic))
        XCTAssertEqual(store.state.box.count, 1)
        XCTAssertEqual(store.state.partner?.speciesID, 1)
    }

    // MARK: 지갑·경험치 적립

    /// 설치 기준선 — 데이터가 도착한 시점의 오늘 사용량은 적립하지 않는다(설치 이전 사용분 제외).
    func testFirstUpdateSetsBaselineWithoutEarning() {
        let (store, _) = makeStore()
        store.update(todayTokens: 5_000, todayDate: "2026-08-05", hasUsageData: true)
        XCTAssertTrue(store.state.installBaselineSet)
        XCTAssertEqual(store.state.earnedTokens, 0)
        XCTAssertEqual(store.state.claimedTodayTokens, 5_000)
    }

    /// 데이터가 도착하기 전에는 기준선을 잡지 않는다 — 기동 직후 빈 새로고침에 0을 못박으면
    /// 그날 사용분이 통째로 적립된다.
    func testBaselineWaitsForRealData() {
        let (store, _) = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-05", hasUsageData: false)
        XCTAssertFalse(store.state.installBaselineSet)
    }

    func testDeltaAccruesToWalletAndPartnerExp() {
        let (store, _) = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        store.update(todayTokens: 1_000, todayDate: "2026-08-05", hasUsageData: true)
        store.update(todayTokens: 4_000, todayDate: "2026-08-05", hasUsageData: true)
        XCTAssertEqual(store.state.earnedTokens, 3_000)
        XCTAssertEqual(store.state.wallet, 3_000)
        XCTAssertEqual(store.state.partner?.exp, 3_000)
    }

    /// 파트너만 경험치를 얻는다 — 박스의 다른 개체는 그대로다.
    func testOnlyPartnerEarnsExp() {
        let (store, _) = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        let other = Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .serious,
                               obtainedAt: self.now, grade: .epic)
        store.addForTesting(other)
        store.update(todayTokens: 1_000, todayDate: "2026-08-05", hasUsageData: true)
        store.update(todayTokens: 2_000, todayDate: "2026-08-05", hasUsageData: true)
        XCTAssertEqual(store.state.partner?.exp, 1_000)
        XCTAssertEqual(store.state.box.first(where: { $0.id == other.id })?.exp, 0)
    }

    /// 날짜가 바뀌면 그날 장부만 0으로 — 누적 적립은 유지된다.
    func testDayRolloverKeepsEarnedTotal() {
        let (store, _) = makeStore()
        store.update(todayTokens: 1_000, todayDate: "2026-08-05", hasUsageData: true)
        store.update(todayTokens: 3_000, todayDate: "2026-08-05", hasUsageData: true)
        store.update(todayTokens: 500, todayDate: "2026-08-06", hasUsageData: true)
        XCTAssertEqual(store.state.earnedTokens, 2_500)
    }

    // MARK: 도감·파트너·영속

    func testRegisterInDexIsIdempotent() {
        let (store, _) = makeStore()
        store.registerInDex(25)
        store.registerInDex(25)
        XCTAssertEqual(store.state.dex, [25])
    }

    func testSetPartnerOnlyAcceptsOwnedIndividuals() {
        let (store, _) = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        let first = store.state.partner!.id
        store.setPartner(UUID())
        XCTAssertEqual(store.state.partnerID, first, "박스에 없는 개체는 파트너가 될 수 없다")
    }

    func testStatePersistsAcrossReload() {
        let (store, url) = makeStore()
        store.chooseStarter(speciesID: 7, grade: .epic)
        store.update(todayTokens: 100, todayDate: "2026-08-05", hasUsageData: true)
        store.update(todayTokens: 900, todayDate: "2026-08-05", hasUsageData: true)
        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertTrue(reloaded.state.starterChosen)
        XCTAssertEqual(reloaded.state.partner?.speciesID, 7)
        XCTAssertEqual(reloaded.state.earnedTokens, 800)
        XCTAssertTrue(reloaded.state.dex.contains(7))
    }
}
```

`SeededRNG` 는 `Tests/PokeDexBarTests/CompanionTests.swift` 에 이미 있으니 다시 만들지 말고 그대로 쓴다.

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter PlayerStoreTests`
Expected: FAIL — `cannot find 'PlayerStore' in scope`

- [ ] **Step 3: PlayerStore 구현**

`Sources/PokeDexBar/Player/PlayerStore.swift`:

```swift
import Foundation
import Observation

/// 플레이어 상태의 메인 액터 표면. 업스트림 `CompanionStore`(한 마리·졸업·자동 진화)를 대체한다.
/// 진화는 여기서 자동으로 일어나지 않는다 — 사용자가 눌러야 한다(`PlayerStore+Evolution`).
@MainActor @Observable
final class PlayerStore {
    private(set) var state = PlayerState()

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var rng: any RandomNumberGenerator
    @ObservationIgnored private let now: () -> Date

    init(fileURL: URL? = nil,
         rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
         now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL ?? Self.defaultURL()
        self.rng = rng
        self.now = now
        load()
    }

    static func defaultURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeDexBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("player-state.json")
    }

    // MARK: 스타터

    /// 첫 개체를 만든다. 스타터 목록 밖이거나 이미 골랐으면 nil.
    /// 스타터는 이로치가 아니다 — 첫 개체는 다시 뽑을 수 없으니 운에 맡기지 않는다.
    @discardableResult
    func chooseStarter(speciesID: Int, grade: Grade) -> Individual? {
        guard !state.starterChosen, StarterCatalog.contains(speciesID) else { return nil }
        let natures = PokemonNature.allCases
        let nature = natures[Int(rng.next() % UInt64(natures.count))]
        let individual = Individual(baseID: speciesID, speciesID: speciesID, pathIDs: [speciesID],
                                    shiny: false, nature: nature, exp: 0,
                                    obtainedAt: now(), grade: grade)
        state.box.append(individual)
        state.partnerID = individual.id
        state.starterChosen = true
        state.dex.insert(speciesID)
        save()
        return individual
    }

    // MARK: 적립

    /// 사용량 갱신 — 지갑과 파트너 경험치가 같은 델타를 먹는다(서로 깎지 않는다).
    func update(todayTokens: Int, todayDate: String, hasUsageData: Bool) {
        if !state.installBaselineSet {
            // 실제 데이터가 도착한 시점의 오늘 사용량을 기준선으로 — 설치 이전 사용분은 세지 않는다.
            guard hasUsageData else { return }
            state.installBaselineSet = true
            state.claimedTodayTokens = todayTokens
            state.lastDate = todayDate
            save()
            return
        }
        if todayDate != state.lastDate {
            state.lastDate = todayDate
            state.claimedTodayTokens = 0
        }
        guard todayTokens > state.claimedTodayTokens else { return }
        let delta = todayTokens - state.claimedTodayTokens
        state.claimedTodayTokens = todayTokens
        state.earnedTokens += delta
        if let index = state.box.firstIndex(where: { $0.id == state.partnerID }) {
            state.box[index].exp += delta
        }
        save()
    }

    // MARK: 박스·도감

    func setPartner(_ id: UUID) {
        guard state.box.contains(where: { $0.id == id }) else { return }
        state.partnerID = id
        save()
    }

    func registerInDex(_ speciesID: Int) {
        guard !state.dex.contains(speciesID) else { return }
        state.dex.insert(speciesID)
        save()
    }

    /// 테스트 전용 — 부화가 없는 2a 단계에서 박스에 개체를 넣는 유일한 경로.
    func addForTesting(_ individual: Individual) {
        state.box.append(individual)
        state.dex.insert(individual.speciesID)
        save()
    }

    // MARK: 영속

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode(PlayerState.self, from: data) else {
            AppLog.write("PlayerStore: 상태 파일을 읽지 못해 새로 시작한다 — \(fileURL.lastPathComponent)")
            return
        }
        state = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)   // 부분 쓰기 손상 방지
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter PlayerStoreTests`
Expected: 전부 통과(12개)

- [ ] **Step 5: 전체 테스트 + 커밋**

Run: `swift build && swift test`
Expected: 경고 0, 전부 통과

```bash
git add -A
git commit -m "feat: add the player store — starter, wallet, dex, persistence

Burned tokens now feed two separate meters: the wallet the shop will spend
and the partner's experience. Only the partner earns, the install baseline
still excludes usage from before the app existed, and the starter is never
shiny because a first companion cannot be rerolled."
```

---

### Task 4: 진화 — 임계 판정과 수동 진화

**Files:**
- Create: `Sources/PokeDexBar/Player/PlayerStore+Evolution.swift`
- Test: `Tests/PokeDexBarTests/EvolutionTests.swift`

**Interfaces:**
- Consumes: `PlayerStore`, `Individual` (Tasks 1·3), `EvoLine`/`EvoNode`(`Core/CompanionModel.swift`), `ExpBalance` (Task 2)
- Produces (모두 `PlayerStore` 확장):
  - `func canEvolve(_ individual: Individual) -> Bool`
  - `func evolutionChoices(_ individual: Individual, line: EvoLine) -> [Int]`
  - `@discardableResult func evolve(individualID: UUID, to speciesID: Int, line: EvoLine) -> Bool`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/EvolutionTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

@MainActor
final class EvolutionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("evo-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    /// 이상해씨 → 이상해풀 → 이상해꽃 (일직선)
    private func bulbaLine() -> EvoLine {
        EvoLine(baseID: 1,
                tree: EvoNode(speciesID: 1, children: [
                    EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])]),
                ]),
                rarity: .rare, names: [:])
    }

    /// 이브이 → (샤미드 | 쥬피썬더) 분기
    private func eeveeLine() -> EvoLine {
        EvoLine(baseID: 133,
                tree: EvoNode(speciesID: 133, children: [
                    EvoNode(speciesID: 134, children: []),
                    EvoNode(speciesID: 135, children: []),
                ]),
                rarity: .rare, names: [:])
    }

    private func partner(of store: PlayerStore) -> Individual { store.state.partner! }

    private func giveExp(_ store: PlayerStore, _ amount: Int) {
        store.update(todayTokens: 0, todayDate: "d", hasUsageData: true)   // 기준선
        store.update(todayTokens: amount, todayDate: "d", hasUsageData: true)
    }

    // MARK: 임계 판정

    func testCannotEvolveBelowThreshold() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 49_999_999)
        XCTAssertFalse(store.canEvolve(partner(of: store)))
    }

    func testCanEvolveAtThreshold() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 50_000_000)
        XCTAssertTrue(store.canEvolve(partner(of: store)))
    }

    // MARK: 진화

    func testEvolvingAdvancesPathAndCarriesOverflow() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 60_000_000)
        XCTAssertTrue(store.evolve(individualID: partner(of: store).id, to: 2, line: bulbaLine()))
        let p = partner(of: store)
        XCTAssertEqual(p.speciesID, 2)
        XCTAssertEqual(p.pathIDs, [1, 2])
        XCTAssertEqual(p.exp, 10_000_000, "초과분은 다음 단계로 이월된다")
        XCTAssertTrue(store.state.dex.contains(2), "진화한 형태도 도감에 등록된다")
    }

    /// 임계에 못 미치면 진화하지 않는다 — UI 가 실수로 불러도 상태가 변하면 안 된다.
    func testEvolveRejectedBelowThreshold() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 1_000)
        XCTAssertFalse(store.evolve(individualID: partner(of: store).id, to: 2, line: bulbaLine()))
        XCTAssertEqual(partner(of: store).speciesID, 1)
    }

    /// 트리에 없는 종으로는 진화할 수 없다.
    func testEvolveRejectsUnreachableSpecies() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 60_000_000)
        XCTAssertFalse(store.evolve(individualID: partner(of: store).id, to: 25, line: bulbaLine()))
        XCTAssertEqual(partner(of: store).speciesID, 1)
    }

    /// 최종형은 진화 후보가 없다 — 배지가 뜨면 안 된다.
    func testFinalFormHasNoChoices() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 200_000_000)
        store.evolve(individualID: partner(of: store).id, to: 2, line: bulbaLine())
        store.evolve(individualID: partner(of: store).id, to: 3, line: bulbaLine())
        XCTAssertEqual(store.evolutionChoices(partner(of: store), line: bulbaLine()), [])
    }

    // MARK: 분기

    func testBranchOffersEveryChild() {
        let store = makeStore()
        store.addForTesting(Individual(baseID: 133, speciesID: 133, pathIDs: [133],
                                       nature: .serious, obtainedAt: now, grade: .rare))
        let eevee = store.state.box.last!
        XCTAssertEqual(store.evolutionChoices(eevee, line: eeveeLine()).sorted(), [134, 135])
    }

    /// 분기에서 고른 쪽만 경로에 남는다.
    func testBranchTakesTheChosenPath() {
        let store = makeStore()
        var eevee = Individual(baseID: 133, speciesID: 133, pathIDs: [133],
                               nature: .serious, obtainedAt: now, grade: .rare)
        eevee.exp = ExpBalance.threshold(grade: .rare, stageIndex: 0)
        store.addForTesting(eevee)
        XCTAssertTrue(store.evolve(individualID: eevee.id, to: 135, line: eeveeLine()))
        let after = store.state.box.first { $0.id == eevee.id }!
        XCTAssertEqual(after.speciesID, 135)
        XCTAssertEqual(after.pathIDs, [133, 135])
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter EvolutionTests`
Expected: FAIL — `value of type 'PlayerStore' has no member 'canEvolve'`

- [ ] **Step 3: 구현**

`Sources/PokeDexBar/Player/PlayerStore+Evolution.swift`:

```swift
import Foundation

/// 진화 — 임계 판정과 실행. **자동으로 일어나지 않는다.** 임계에 닿으면 UI 가 배지를 띄우고,
/// 사용자가 누를 때 `evolve` 가 불린다(미루기·분기 선택이 가능해야 하기 때문).
extension PlayerStore {
    /// 다음 단계로 갈 경험치가 찼나. 최종형인지까지는 여기서 모른다 — 그건 라인이 필요하다.
    func canEvolve(_ individual: Individual) -> Bool {
        individual.exp >= ExpBalance.threshold(grade: individual.grade,
                                               stageIndex: individual.stageIndex)
    }

    /// 지금 형태에서 갈 수 있는 다음 종들. 최종형이면 빈 배열.
    func evolutionChoices(_ individual: Individual, line: EvoLine) -> [Int] {
        guard let node = line.tree.node(withID: individual.speciesID) else { return [] }
        return node.children.map(\.speciesID)
    }

    /// 진화 실행. 경험치가 모자라거나 트리에서 갈 수 없는 종이면 아무것도 하지 않고 false.
    @discardableResult
    func evolve(individualID: UUID, to speciesID: Int, line: EvoLine) -> Bool {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        let individual = state.box[index]
        guard canEvolve(individual),
              evolutionChoices(individual, line: line).contains(speciesID) else { return false }
        let threshold = ExpBalance.threshold(grade: individual.grade,
                                             stageIndex: individual.stageIndex)
        state.box[index].speciesID = speciesID
        state.box[index].pathIDs.append(speciesID)
        state.box[index].exp = individual.exp - threshold   // 초과분 이월
        state.dex.insert(speciesID)
        save()
        return true
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter EvolutionTests`
Expected: 전부 통과(8개)

- [ ] **Step 5: 전체 테스트 + 커밋**

Run: `swift build && swift test`
Expected: 경고 0, 전부 통과

```bash
git add -A
git commit -m "feat: evolve on demand instead of automatically

The inherited game evolved a companion the moment its meter filled, which
takes the choice away — branching lines have no way to ask which side you
want, and there is no way to keep a form you like. Gate evolution behind an
explicit call that verifies the threshold and that the target is reachable
in the line, carry the surplus experience into the next stage, and register
the new form in the dex."
```

---

### Task 5: 앱을 새 상태 위로 옮기기 (스타터 관문 · 파트너 표시)

**Files:**
- Modify: `Sources/PokeDexBar/PokeDexBarApp.swift`
- Create: `Sources/PokeDexBar/UI/StarterPickerView.swift`
- Modify: `Sources/PokeDexBar/UI/PopoverView.swift`
- Test: `Tests/PokeDexBarTests/StarterGateTests.swift`

**Interfaces:**
- Consumes: `PlayerStore`(Tasks 3·4), `StarterCatalog`(Task 2), `SpriteView`(`UI/CompanionView.swift`), `SpeciesSlug`
- Produces:
  - `struct StarterPickerView: View` — `init(store: PlayerStore, provider: any PokeProviding, onChosen: @escaping () -> Void)`
  - `PopoverView` 가 `player: PlayerStore` 를 받고, `player.state.starterChosen == false` 면 탭 대신 선택 화면만 그린다
  - `AppDelegate` 가 `PlayerStore` 를 만들어 `UsageStore` 갱신 때마다 `player.update(...)` 를 호출하고, 메뉴바 아이콘·플로팅 펫이 파트너 종을 그린다

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/StarterGateTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

@MainActor
final class StarterGateTests: XCTestCase {
    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gate-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                           now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    /// 관문 판정은 순수 함수여야 테스트할 수 있다 — 뷰 안에 숨기지 않는다.
    func testGateClosedUntilStarterChosen() {
        let store = makeStore()
        XCTAssertTrue(PopoverView.needsStarter(store.state))
        store.chooseStarter(speciesID: 1, grade: .epic)
        XCTAssertFalse(PopoverView.needsStarter(store.state))
    }

    /// 메뉴바·플로팅 펫이 그릴 종 — 파트너가 없으면 nil(스프라이트 대신 기본 아이콘).
    func testDisplayedSpeciesFollowsPartner() {
        let store = makeStore()
        XCTAssertNil(store.displayedSpeciesID)
        store.chooseStarter(speciesID: 7, grade: .epic)
        XCTAssertEqual(store.displayedSpeciesID, 7)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter StarterGateTests`
Expected: FAIL — `type 'PopoverView' has no member 'needsStarter'`

- [ ] **Step 3: 관문 판정과 표시 종 추가**

`Sources/PokeDexBar/Player/PlayerStore.swift` 에 다음을 더한다(클래스 안).

```swift
    /// 메뉴바 아이콘·플로팅 펫이 그릴 종. 파트너가 없으면 nil.
    var displayedSpeciesID: Int? { state.partner?.speciesID }
    var displayedIsShiny: Bool { state.partner?.shiny ?? false }
```

`Sources/PokeDexBar/UI/PopoverView.swift` 의 `PopoverView` 안에 다음을 더한다.

```swift
    /// 스타터를 아직 안 골랐나 — 골라야 다른 화면을 쓸 수 있다. 순수 판정이라 테스트로 잠근다.
    nonisolated static func needsStarter(_ state: PlayerState) -> Bool { !state.starterChosen }
```

- [ ] **Step 4: 스타터 선택 화면 작성**

`Sources/PokeDexBar/UI/StarterPickerView.swift`:

```swift
import SwiftUI

/// 첫 실행 화면 — 전 세대 스타터 27마리 중 하나를 고른다. 고르는 것이 이 앱의 시작이라
/// 선택 전에는 다른 탭으로 갈 수 없다.
struct StarterPickerView: View {
    let store: PlayerStore
    let provider: any PokeProviding
    let onChosen: () -> Void

    @State private var choosing: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("함께 시작할 포켓몬을 고르세요")
                .font(.system(size: 13, weight: .bold))
            Text("고른 포켓몬이 첫 파트너가 됩니다. 토큰을 쓸수록 경험치가 쌓여요.")
                .font(.system(size: 10)).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(StarterCatalog.byGeneration, id: \.generation) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(entry.generation)세대")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            HStack(spacing: 8) {
                                ForEach(entry.speciesIDs, id: \.self) { id in
                                    starterCell(id)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 300)
        }
        .padding(13)
        .frame(width: PopoverView.width)
    }

    private func starterCell(_ speciesID: Int) -> some View {
        Button {
            choose(speciesID)
        } label: {
            SpriteView(speciesID: speciesID, size: 64, animated: true)
                .frame(width: 76, height: 76)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(choosing != nil)
        .opacity(choosing == nil || choosing == speciesID ? 1 : 0.4)
    }

    /// 등급은 그 종의 포획률에서 온다. 조회에 실패하면 에픽으로 둔다 — 스타터는 대부분 포획률 45다.
    private func choose(_ speciesID: Int) {
        choosing = speciesID
        Task {
            let grade: Grade
            if let base = try? await provider.baseSpecies(id: speciesID) {
                grade = Grade(rarity: Rarity.from(captureRate: base.captureRate,
                                                  isLegendary: false, isMythical: false))
            } else {
                grade = .epic
            }
            store.chooseStarter(speciesID: speciesID, grade: grade)
            onChosen()
        }
    }
}
```

- [ ] **Step 5: 팝오버에 관문 붙이기**

`Sources/PokeDexBar/UI/PopoverView.swift`:
- `PopoverView` 에 저장 속성 `let player: PlayerStore` 와 `let provider: any PokeProviding` 를 더하고 `init` 에 같은 이름의 인자를 추가한다(기존 인자 뒤, `onSelect` 앞).
- `body` 의 가장 바깥에서 관문을 먼저 본다:

```swift
    var body: some View {
        Group {
            if Self.needsStarter(player.state) {
                StarterPickerView(store: player, provider: provider) { }
            } else {
                existingBody
            }
        }
    }
```

기존 `body` 의 내용을 `private var existingBody: some View` 로 옮긴다(이름만 바꾸고 내용은 그대로).

- [ ] **Step 6: 앱에 배선**

`Sources/PokeDexBar/PokeDexBarApp.swift`:
- `AppDelegate` 에 `private var player: PlayerStore!` 를 더하고 `applicationDidFinishLaunching` 에서 `player = PlayerStore()` 로 만든다.
- 기존에 `companion.update(todayTokens:...)` 를 부르는 자리에서 `player.update(todayTokens: <같은 값>, todayDate: <같은 값>, hasUsageData: <같은 값>)` 도 함께 부른다(구 스토어는 Task 8 에서 지운다).
- 메뉴바 아이콘과 플로팅 펫이 그리는 종을 `companion.currentSpeciesID` → `player.displayedSpeciesID`, shiny 는 `player.displayedIsShiny` 로 바꾼다.
- `PopoverView(...)` 를 만드는 자리에 `player: player, provider: PokeAPIClient.shared` 를 넘긴다.

- [ ] **Step 7: 빌드·테스트**

Run: `swift build && swift test`
Expected: 경고 0, 전부 통과

- [ ] **Step 8: 커밋**

```bash
git add -A
git commit -m "feat: start the game by choosing a starter

Replace the opening egg with a choice: the popover shows the 27 first-stage
starters until one is picked, and the menu bar icon and floating pet draw
whichever individual is the partner. The old companion store still runs
alongside; it comes out in a later commit."
```

---

### Task 6: 박스 탭

**Files:**
- Create: `Sources/PokeDexBar/UI/BoxTabView.swift`
- Modify: `Sources/PokeDexBar/UI/PopoverView.swift`
- Test: `Tests/PokeDexBarTests/BoxViewTests.swift`

**Interfaces:**
- Consumes: `PlayerStore`, `Individual`, `ExpBalance`, `SpriteView`
- Produces:
  - `struct BoxTabView: View` — `init(store: PlayerStore, lines: [Int: EvoLine], onNeedLine: @escaping (Int) -> Void)`
  - `BoxTabView.progress(_ individual: Individual) -> Double` (순수, 0…1)

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/BoxViewTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

@MainActor
final class BoxViewTests: XCTestCase {
    private func individual(grade: Grade, exp: Int, path: [Int]) -> Individual {
        Individual(baseID: path.first ?? 1, speciesID: path.last ?? 1, pathIDs: path,
                   nature: .serious, exp: exp,
                   obtainedAt: Date(timeIntervalSince1970: 0), grade: grade)
    }

    func testProgressIsExpOverThreshold() {
        let half = individual(grade: .common, exp: 25_000_000, path: [1])
        XCTAssertEqual(BoxTabView.progress(half), 0.5, accuracy: 0.001)
    }

    /// 임계를 넘겨도 1을 넘지 않는다 — 게이지가 칸 밖으로 나가면 안 된다.
    func testProgressClampsAtOne() {
        let over = individual(grade: .common, exp: 999_000_000, path: [1])
        XCTAssertEqual(BoxTabView.progress(over), 1.0, accuracy: 0.001)
    }

    func testProgressIsZeroForFreshIndividual() {
        XCTAssertEqual(BoxTabView.progress(individual(grade: .epic, exp: 0, path: [4])), 0)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter BoxViewTests`
Expected: FAIL — `cannot find 'BoxTabView' in scope`

- [ ] **Step 3: 구현**

`Sources/PokeDexBar/UI/BoxTabView.swift`:

```swift
import SwiftUI

/// 박스 — 보유 개체 목록. 도감이 "종을 모았나"라면 여기는 "무엇을 가졌나"다.
/// 파트너 지정과 진화가 여기서 일어난다(중복 개체를 각각 다루려면 개체 단위 화면이 필요하다).
struct BoxTabView: View {
    let store: PlayerStore
    /// 종 번호 → 진화 라인. 없으면 진화 후보를 알 수 없어 버튼을 흐리게 둔다.
    let lines: [Int: EvoLine]
    /// 라인이 없을 때 호출 — 앱이 받아와 `lines` 를 채운다.
    let onNeedLine: (Int) -> Void

    /// 현재 단계의 경험치 진행도(0…1). 순수 함수라 테스트로 잠근다.
    nonisolated static func progress(_ individual: Individual) -> Double {
        let threshold = ExpBalance.threshold(grade: individual.grade,
                                             stageIndex: individual.stageIndex)
        guard threshold > 0 else { return 0 }
        return min(1, max(0, Double(individual.exp) / Double(threshold)))
    }

    /// 최근 획득 순.
    private var sorted: [Individual] {
        store.state.box.sorted { $0.obtainedAt > $1.obtainedAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(sorted) { individual in
                    row(individual)
                }
            }
        }
        .frame(height: 320)
    }

    private func row(_ individual: Individual) -> some View {
        let isPartner = individual.id == store.state.partnerID
        let line = lines[individual.baseID]
        let choices = line.map { store.evolutionChoices(individual, line: $0) } ?? []
        let ready = store.canEvolve(individual) && !choices.isEmpty
        return HStack(alignment: .top, spacing: 8) {
            SpriteView(speciesID: individual.speciesID, size: 40, shiny: individual.shiny)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("#\(individual.speciesID)")
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    if individual.shiny { Text("✨").font(.system(size: 10)) }
                    Text(individual.grade.label)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.18), in: Capsule())
                    if isPartner {
                        Text("파트너")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Spacer()
                    Text(individual.nature.name(.systemDefault))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }

                ProgressView(value: Self.progress(individual))
                    .progressViewStyle(.linear)
                    .frame(height: 4)

                HStack(spacing: 8) {
                    if !isPartner {
                        Button("파트너로") { store.setPartner(individual.id) }
                            .buttonStyle(.borderless).font(.system(size: 10))
                    }
                    if ready {
                        ForEach(choices, id: \.self) { target in
                            Button(choices.count > 1 ? "#\(target) 로 진화" : "진화") {
                                if let line { store.evolve(individualID: individual.id,
                                                           to: target, line: line) }
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .task(id: individual.baseID) {
            if lines[individual.baseID] == nil { onNeedLine(individual.baseID) }
        }
    }
}
```

- [ ] **Step 4: 팝오버 탭에 붙이기**

`Sources/PokeDexBar/UI/PopoverView.swift`:
- `enum PopoverTab` 에 `case box` 를 더하고 세그먼트 Picker 에 `Text("박스").tag(PopoverTab.box)` 를 추가한다.
- 탭 switch 에 `case .box: BoxTabView(store: player, lines: evoLines) { baseID in loadLine(baseID) }` 를 더한다.
- `@State private var evoLines: [Int: EvoLine] = [:]` 와, 라인을 받아 채우는 `private func loadLine(_ baseID: Int)` 를 `PopoverView` 에 더한다:

```swift
    /// 박스가 진화 후보를 보여주려면 라인이 필요하다. 개체가 화면에 들어올 때 한 번만 받아둔다.
    private func loadLine(_ baseID: Int) {
        guard evoLines[baseID] == nil else { return }
        Task {
            if let line = try? await provider.line(baseSpeciesID: baseID) {
                evoLines[baseID] = line
            }
        }
    }
```

- [ ] **Step 5: 테스트 통과 + 빌드**

Run: `swift test --filter BoxViewTests && swift build && swift test`
Expected: 전부 통과, 경고 0

- [ ] **Step 6: 커밋**

```bash
git add -A
git commit -m "feat: add the box tab for owned individuals

Duplicates make a species list useless for handling what you own, so give
individuals their own screen: each row carries its shiny, nature, grade and
experience, and the partner switch and evolution buttons live here."
```

---

### Task 7: 도감 탭 (전국도감식 그리드)

**Files:**
- Create: `Sources/PokeDexBar/UI/NationalDexView.swift`
- Modify: `Sources/PokeDexBar/UI/PopoverView.swift`
- Test: `Tests/PokeDexBarTests/NationalDexTests.swift`

**Interfaces:**
- Consumes: `PlayerStore`, `SpeciesSlug`, `SpriteView`
- Produces:
  - `struct NationalDexView: View` — `init(store: PlayerStore)`
  - `NationalDexView.speciesRange: ClosedRange<Int>` (= `1...1025`)
  - `NationalDexView.progressText(caught: Int) -> String`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/PokeDexBarTests/NationalDexTests.swift`:

```swift
import XCTest
@testable import PokeDexBar

final class NationalDexTests: XCTestCase {
    /// 전국도감은 1번부터 마지막 종까지 빠짐없이 칸을 만든다 — 희귀도로 나누지 않는다.
    func testRangeCoversEverySpecies() {
        XCTAssertEqual(NationalDexView.speciesRange, 1...1025)
        XCTAssertEqual(NationalDexView.speciesRange.count, 1025)
    }

    /// 모든 칸이 스프라이트를 그릴 수 있어야 한다(실루엣도 스프라이트가 있어야 만든다).
    func testEverySlotHasASlug() {
        for id in NationalDexView.speciesRange {
            XCTAssertNotNil(SpeciesSlug.slug(id), "종 \(id) 슬러그 없음")
        }
    }

    func testProgressText() {
        XCTAssertEqual(NationalDexView.progressText(caught: 0), "0 / 1025")
        XCTAssertEqual(NationalDexView.progressText(caught: 142), "142 / 1025")
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter NationalDexTests`
Expected: FAIL — `cannot find 'NationalDexView' in scope`

- [ ] **Step 3: 구현**

`Sources/PokeDexBar/UI/NationalDexView.swift`:

```swift
import SwiftUI

/// 도감 — 1번부터 마지막 종까지 번호순 그리드. 희귀도로 나누지 않는다.
/// 읽기 전용이다(개체를 만지는 일은 박스에서 한다).
///
/// 1025칸을 한 번에 그리면 팝오버가 버벅이므로 `LazyVGrid` 로 보이는 칸만 만든다 —
/// 스프라이트 요청도 화면에 들어온 칸에서만 나간다.
struct NationalDexView: View {
    let store: PlayerStore

    nonisolated static let speciesRange = 1...1025

    nonisolated static func progressText(caught: Int) -> String {
        "\(caught) / \(speciesRange.count)"
    }

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("도감").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(Self.progressText(caught: store.state.dex.count))
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Self.speciesRange, id: \.self) { id in
                        cell(id)
                    }
                }
            }
            .frame(height: 300)
        }
    }

    private func cell(_ speciesID: Int) -> some View {
        let caught = store.state.dex.contains(speciesID)
        return VStack(spacing: 1) {
            SpriteView(speciesID: speciesID, size: 32)
                .frame(width: 32, height: 32)
                // 못 잡은 종은 실루엣 — 모습은 보이되 정체는 가린다.
                .brightness(caught ? 0 : -1)
                .opacity(caught ? 1 : 0.55)
            Text("\(speciesID)")
                .font(.system(size: 7)).monospacedDigit()
                .foregroundStyle(caught ? .secondary : .tertiary)
        }
        .frame(width: 44, height: 46)
        .background(Color.secondary.opacity(caught ? 0.10 : 0.04),
                    in: RoundedRectangle(cornerRadius: 6))
    }
}
```

- [ ] **Step 4: 팝오버 탭 교체**

`Sources/PokeDexBar/UI/PopoverView.swift` 의 탭 switch 에서 기존 `case .collection` 이 그리던 구 도감(`CollectionView`) 대신 `NationalDexView(store: player)` 를 그린다. 세그먼트 라벨은 "도감" 그대로 둔다.

- [ ] **Step 5: 렌더 측정으로 지연 로드 확인**

`Tests/PokeDexBarTests/NationalDexTests.swift` 에 다음을 더한다.

```swift
import SwiftUI

@MainActor
final class NationalDexRenderTests: XCTestCase {
    /// 1025칸이 있어도 뷰 조립이 즉시 끝나야 한다 — 전부 미리 만들면 팝오버가 멈춘다.
    func testGridAssemblesQuickly() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dex-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        let started = ProcessInfo.processInfo.systemUptime
        let host = NSHostingView(rootView: NationalDexView(store: store)
            .frame(width: PopoverView.width))
        host.layoutSubtreeIfNeeded()
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertLessThan(elapsed, 2.0, "도감 그리드 조립이 \(elapsed)초 걸렸다 — 지연 로드가 안 걸렸다")
    }
}
```

`import AppKit` 이 필요하면 파일 상단에 더한다.

Run: `swift test --filter "NationalDexTests|NationalDexRenderTests"`
Expected: 전부 통과

- [ ] **Step 6: 전체 테스트 + 커밋**

Run: `swift build && swift test`
Expected: 경고 0, 전부 통과

```bash
git add -A
git commit -m "feat: show the dex as a national grid

Grouping by rarity hid what the dex is for — how far along the whole list
you are. Lay every species out in number order instead, silhouetted until
caught, with the count at the top, and build the cells lazily so 1025 of
them do not stall the popover."
```

---

### Task 8: 구 컴패니언 시스템 제거

**Files:**
- Delete: `Sources/PokeDexBar/Core/CompanionStore.swift`, `Sources/PokeDexBar/UI/ShopView.swift`, `Sources/PokeDexBar/UI/BagView.swift`
- Modify: `Sources/PokeDexBar/Core/CompanionModel.swift`(남길 타입만 남긴다), `Sources/PokeDexBar/PokeDexBarApp.swift`, `Sources/PokeDexBar/UI/PopoverView.swift`, `Sources/PokeDexBar/UI/CompanionView.swift`, `Sources/PokeDexBar/Core/SaveTransfer.swift`
- Delete: 구 시스템만 검증하던 테스트 파일들

**Interfaces:**
- Consumes: Tasks 1~7 의 전부
- Produces: `CompanionStore`·`CompanionState`·알·졸업·자동 진화가 사라진 코드베이스. `EvoLine`/`EvoNode`/`Rarity`/`PokemonNature`/`SpriteView` 는 남는다(새 코드가 쓴다).

- [ ] **Step 1: 무엇이 남아야 하는지 확인**

Run: `grep -rn "CompanionStore\|CompanionState\|eggUsage\|graduate\|collectedFinals" Sources Tests | cut -d: -f1 | sort | uniq -c | sort -rn`
남길 것: `EvoLine`, `EvoNode`, `Rarity`, `PokemonNature`, `DexEntry` 를 제외한 `CompanionModel.swift` 의 나머지는 지운다. `SpriteView`(`CompanionView.swift`)와 `CompanionHeader` 중 **SpriteView 는 남기고** 컴패니언 전용 뷰는 지운다.

- [ ] **Step 2: 앱에서 구 스토어 배선 제거**

`Sources/PokeDexBar/PokeDexBarApp.swift` 에서 `companion` 프로퍼티, 생성, `companion.update(...)` 호출, 컴패니언 알림/연출 관련 코드를 지운다. 메뉴바·플로팅 펫은 Task 5 에서 이미 `player` 를 보고 있으므로 그대로 둔다.

- [ ] **Step 3: 팝오버에서 상점·가방 탭 제거**

`Sources/PokeDexBar/UI/PopoverView.swift` 의 `PopoverTab` 을 `case home, box, collection` 으로 줄이고(상점은 2b 에서 새로 만든다), `ShopView`/`BagView` 참조와 세그먼트 항목을 지운다.

- [ ] **Step 4: 파일 삭제**

```bash
git rm Sources/PokeDexBar/Core/CompanionStore.swift \
       Sources/PokeDexBar/UI/ShopView.swift \
       Sources/PokeDexBar/UI/BagView.swift
```

`Sources/PokeDexBar/Core/CompanionModel.swift` 에서 `CompanionState`, `MonState`, `DexEntry`, `PokemonBalance`, `RareCandy`, `Mint`, `ShinyCharm`, `FreshEgg`, `ItemKind`, `PokemonOdds` 를 지우고 `Rarity`, `PokemonNature`, `EvoNode`, `EvoLine`, `EvoLineItem*`, `PokemonAssets` 만 남긴다.

- [ ] **Step 5: 구 시스템 전용 테스트 삭제**

구 스토어·알·졸업·상점만 검증하던 테스트 파일을 지운다. 대상은 Step 1 의 grep 결과에서 `Tests/` 로 나온 파일 중 새 코드가 쓰지 않는 것 전부다. `SeededRNG`/`CountingRNG` 같은 공용 헬퍼가 지워질 파일에 있으면 `Tests/PokeDexBarTests/TestSupport.swift` 로 옮긴다.

- [ ] **Step 6: SaveTransfer 정리**

`Sources/PokeDexBar/Core/SaveTransfer.swift` 가 `CompanionState` 를 다룬다면, `PlayerState` 를 대상으로 바꾸거나 — 2b 에서 다시 볼 기능이므로 — 파일과 그 UI 진입점·테스트를 함께 지운다. 지우는 쪽을 택했다면 보고서에 그렇게 적는다.

- [ ] **Step 7: 빌드·테스트**

Run: `swift build && swift test`
Expected: 경고 0, 전부 통과. 남은 참조로 컴파일이 깨지면 그 참조가 구 시스템 전용인지 확인하고 지운다.

- [ ] **Step 8: 커밋**

```bash
git add -A
git commit -m "refactor: remove the inherited companion system

The egg, the graduation, the automatic evolution and the shop it fed are
all replaced now, and keeping them meant two state models writing to the
same app. Delete them and their tests, keeping the evolution-line types and
the sprite view the new code builds on."
```

---

## 2b 에서 이어짐 (이 계획의 범위 밖)

상점·알 뽑기·슬롯·시간 부화·부화 알림·아이템 4종. 설계는
`docs/superpowers/specs/2026-08-05-pokedexbar-phase2-design.md` 의 해당 절에 있다.
`PlayerState` 에 `slots`·`inventory`·`ownsShinyCharm` 자리를 미리 만들어 두었으므로
2b 는 `eggs: [Egg]` 를 더하고 상점 화면을 붙이는 일에서 시작한다.
