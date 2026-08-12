# 블라인드로 오는 제안 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 박사의 제안 세 마리가 가려진 채로 오고, 한 칸씩 열 때마다 등급별 연출이 터진다.

**Architecture:** 상태는 `ProfessorOffer.opened` 플래그 하나만 는다 — 제안은 이미 완성된
`Individual` 을 품고 있어서, 블라인드는 새 데이터가 아니라 "아직 안 보여준다"는 표시다. 연출은
`EggRevealView` 를 그대로 부른다(상점의 알 뽑기 결과가 이미 쓰는 오버레이다).

**Tech Stack:** Swift 6 / SwiftPM / SwiftUI / XCTest. 외부 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-08-11-professor-and-vouchers-design.md` 의 **D 절**.
A·B·C 절은 v1.6.0 으로 이미 배포됐다 — 건드리지 않는다.

## Global Constraints

- **커밋 메시지는 영어. 코드 주석은 한국어** — 주변 주석과 같은 밀도·어투로. *왜* 를 적는다.
- **사용자에게 보이는 문자열은 전부 `L.t(ko, en, ja)`.**
- **빌드 경고 0.** `swift build` 만으로는 테스트 타깃을 안 짓는다 — **`swift build --build-tests`** 로 확인한다.
- **`PlayerState`·`ProfessorOffer` 에 필드를 더하면 관대 디코더가 그걸 읽는지 확인한다.** 이
  저장소가 세 번 밟은 부류다(저장은 되는데 못 읽는다). `ProfessorOffer` 는 합성 디코더를 쓰므로
  기본값이 있는 새 필드는 자동으로 읽히지만, `LossyProfessorOffer` 를 지나는 경로를 테스트로 확인한다.
- **`.help()` 툴팁 금지.**
- **실제 세이브 파일(`~/Library/Application Support/PokeDexBar/`) 접근 금지 in tests.**
- **안 연 카드는 못 데려간다 — 스토어가 마지막 방어선이다.** 화면이 조건을 다시 적으면 갈린다.
- 테스트: `swift test --filter BlindOfferTests` / 전체는 `swift test`.

---

## File Structure

| 파일 | 책임 |
|---|---|
| `Sources/PokeDexBar/Player/ProfessorOffer.swift` **(수정)** | `opened` 플래그. |
| `Sources/PokeDexBar/Player/PlayerStore+Professor.swift` **(수정)** | `openProfessorOffer` + `acceptProfessorOffer` 가드. |
| `Sources/PokeDexBar/UI/ProfessorOfferSection.swift` **(수정)** | 닫힌 카드, 열기 탭, 연출 콜백. |
| `Sources/PokeDexBar/UI/ShopTabView.swift` **(수정)** | 섹션의 연출 요청을 기존 `reveal` 오버레이로 넘긴다. |
| `Sources/PokeDexBar/Core/Localization.swift` **(수정)** | ko/en/ja 문구. |
| `Tests/PokeDexBarTests/BlindOfferTests.swift` **(신규)** | 두 태스크의 테스트. |

---

## Task 1: 열기 동작

**Files:**
- Modify: `Sources/PokeDexBar/Player/ProfessorOffer.swift`
- Modify: `Sources/PokeDexBar/Player/PlayerStore+Professor.swift` (`acceptProfessorOffer` 위)
- Test: `Tests/PokeDexBarTests/BlindOfferTests.swift` (신규)

**Interfaces:**
- Consumes: `PlayerStore.refreshProfessorOffers(index:)`, `PlayerStore.acceptProfessorOffer(offerID:)`,
  `ProfessorBalance.price(grade:)`
- Produces:
  - `ProfessorOffer.opened: Bool` (기본 false)
  - `@discardableResult func PlayerStore.openProfessorOffer(offerID: UUID) -> Individual?`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`Tests/PokeDexBarTests/BlindOfferTests.swift` 를 새로 만든다.

```swift
import XCTest
@testable import PokeDexBar

/// 가려진 채로 오는 제안 — 한 칸씩 연다.
@MainActor
final class BlindOfferTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blind-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    private func index() -> [BaseSpecies] {
        [BaseSpecies(id: 1, captureRate: 255, isLegendary: false, isMythical: false),
         BaseSpecies(id: 4, captureRate: 45, isLegendary: false, isMythical: false),
         BaseSpecies(id: 25, captureRate: 190, isLegendary: false, isMythical: false),
         BaseSpecies(id: 133, captureRate: 35, isLegendary: false, isMythical: false),
         BaseSpecies(id: 150, captureRate: 3, isLegendary: true, isMythical: false)]
    }

    private func prepared() -> PlayerStore {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-12", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        return store
    }

    /// 새로 뽑힌 제안은 셋 다 닫혀 있다.
    func testFreshOffersArriveClosed() {
        let store = prepared()
        XCTAssertEqual(store.state.professorOffers.count, 3)
        XCTAssertTrue(store.state.professorOffers.allSatisfy { !$0.opened })
    }

    /// 열면 그 칸만 열리고, **포인트는 안 줄어든다** — 값은 데려갈 때 치른다.
    func testOpeningCostsNothingAndOpensOnlyThatSlot() {
        let store = prepared()
        store.mutate { $0.researchPoints = 500 }
        let first = store.state.professorOffers[0]

        XCTAssertEqual(store.openProfessorOffer(offerID: first.id)?.id, first.individual.id)
        XCTAssertEqual(store.state.researchPoints, 500, "여는 데 값이 나갔다")
        XCTAssertTrue(store.state.professorOffers[0].opened)
        XCTAssertFalse(store.state.professorOffers[1].opened, "옆 칸까지 열렸다")
        XCTAssertFalse(store.state.professorOffers[2].opened)
    }

    /// 같은 칸을 두 번 열어도 아무 일 없다 — 두 번째는 nil 이라 연출도 다시 안 뜬다.
    func testOpeningTwiceIsHarmless() {
        let store = prepared()
        let first = store.state.professorOffers[0]
        XCTAssertNotNil(store.openProfessorOffer(offerID: first.id))
        XCTAssertNil(store.openProfessorOffer(offerID: first.id))
        XCTAssertTrue(store.state.professorOffers[0].opened)
    }

    /// 없는 자리는 아무 일 없다.
    func testOpeningAnUnknownSlotDoesNothing() {
        let store = prepared()
        XCTAssertNil(store.openProfessorOffer(offerID: UUID()))
        XCTAssertTrue(store.state.professorOffers.allSatisfy { !$0.opened })
    }

    /// **안 연 카드는 못 데려간다 + 포인트 미차감.** 화면이 버튼을 안 그리지만 스토어가
    /// 마지막 방어선이다 — 이 기능에서 화면이 스토어 조건을 다시 적었다가 갈린 적이 있다.
    func testAnUnopenedOfferCannotBeTaken() {
        let store = prepared()
        store.mutate { $0.researchPoints = 1000 }
        let first = store.state.professorOffers[0]

        XCTAssertNil(store.acceptProfessorOffer(offerID: first.id))
        XCTAssertEqual(store.state.researchPoints, 1000, "안 열었는데 포인트가 나갔다")
        XCTAssertTrue(store.state.box.isEmpty)
        XCTAssertFalse(store.state.professorOffers[0].claimed)
    }

    /// 열고 나면 평소대로 데려갈 수 있다 — 가드가 늘 꺼져 있으면 안 된다(대조군).
    func testAnOpenedOfferCanBeTaken() {
        let store = prepared()
        store.mutate { $0.researchPoints = 1000 }
        let first = store.state.professorOffers[0]
        store.openProfessorOffer(offerID: first.id)

        XCTAssertNotNil(store.acceptProfessorOffer(offerID: first.id))
        XCTAssertEqual(store.state.box.count, 1)
    }

    /// **재기동해도 연 것은 열린 채, 안 연 것은 닫힌 채.** 합성 디코더가 기본값 있는 새 필드를
    /// 읽긴 하지만, 이 저장소는 저장은 되고 읽기만 빠지는 부류를 세 번 밟았다 — 실제 파일로 왕복한다.
    func testOpenStateSurvivesARestart() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blind-save-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        store.update(todayTokens: 0, todayDate: "2026-08-12", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        store.openProfessorOffer(offerID: store.state.professorOffers[1].id)

        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertEqual(reloaded.state.professorOffers.map(\.opened), [false, true, false])
    }

    /// 날짜가 바뀌면 셋 다 다시 닫힌다.
    func testANewDayClosesThemAgain() {
        let store = prepared()
        for offer in store.state.professorOffers { store.openProfessorOffer(offerID: offer.id) }
        XCTAssertTrue(store.state.professorOffers.allSatisfy(\.opened))

        store.update(todayTokens: 1, todayDate: "2026-08-13", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        XCTAssertTrue(store.state.professorOffers.allSatisfy { !$0.opened },
                      "새 날인데 열린 채로 왔다")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter BlindOfferTests`
Expected: 컴파일 실패 — `value of type 'PlayerStore' has no member 'openProfessorOffer'`

- [ ] **Step 3: `ProfessorOffer` 에 플래그를 더한다**

`Sources/PokeDexBar/Player/ProfessorOffer.swift` 의 `var claimed = false` **위**에:

```swift
    /// 오늘 이미 열어 봤나. **제안은 가려진 채로 온다** — 미리 등급을 보이면 전설은 열기 전에
    /// 이미 알아버려서 터지는 연출이 확인 절차로 전락한다.
    ///
    /// 개체 자체는 뽑을 때 이미 다 정해져 여기 들어 있다(그래야 보이는 것과 받는 것이 안 갈린다).
    /// 이 플래그는 데이터가 아니라 **아직 안 보여준다**는 표시다.
    var opened = false
```

- [ ] **Step 4: 여는 동작과 가드를 더한다**

`Sources/PokeDexBar/Player/PlayerStore+Professor.swift` 의 `acceptProfessorOffer` **위**에:

```swift
    /// 제안 한 칸을 연다. 이미 열었거나 없는 자리면 nil — 그때는 연출도 다시 안 뜬다.
    ///
    /// **값은 안 든다.** 여는 것은 무엇인지 보는 일이고, 값은 데려갈 때 치른다.
    @discardableResult
    func openProfessorOffer(offerID: UUID) -> Individual? {
        guard let slot = state.professorOffers.firstIndex(where: { $0.id == offerID }),
              !state.professorOffers[slot].opened else { return nil }
        let individual = state.professorOffers[slot].individual
        mutate { $0.professorOffers[slot].opened = true }
        return individual
    }
```

그리고 `acceptProfessorOffer` 의 첫 `guard` 에 조건을 더한다:

```swift
        guard let slot = state.professorOffers.firstIndex(where: { $0.id == offerID }),
              state.professorOffers[slot].opened,          // 안 연 것은 못 데려간다
              !state.professorOffers[slot].claimed else { return nil }
```

- [ ] **Step 5: 테스트가 통과하는지 확인한다**

Run: `swift test --filter BlindOfferTests`
Expected: PASS (8개)

- [ ] **Step 6: 가드가 진짜 판별하는지 확인한다 (되돌리기 검사)**

`acceptProfessorOffer` 에 더한 `state.professorOffers[slot].opened,` 줄을 잠시 지운다.

Run: `swift test --filter BlindOfferTests`
Expected: `testAnUnopenedOfferCannotBeTaken` **이 실패해야 한다.** 확인했으면 되돌리고
`git diff` 로 되돌림이 완전한지 본다.

- [ ] **Step 7: 전체 테스트와 경고를 확인한다**

Run: `swift build --build-tests 2>&1 | grep -i warning; swift test`
Expected: 경고 출력 없음, 전체 PASS. 특히 기존 `ProfessorTests` 가 통과해야 한다 —
`acceptProfessorOffer` 에 가드가 늘었으므로 그 테스트들이 먼저 열어야 할 수 있다.

- [ ] **Step 8: 커밋**

```bash
git add Sources/PokeDexBar/Player/ Tests/PokeDexBarTests/BlindOfferTests.swift
git commit -m "feat: hold the Professor's offers face down until opened"
```

---

## Task 2: 닫힌 카드와 개봉 연출

**Files:**
- Modify: `Sources/PokeDexBar/Core/Localization.swift`
- Modify: `Sources/PokeDexBar/UI/ProfessorOfferSection.swift`
- Modify: `Sources/PokeDexBar/UI/ShopTabView.swift`
- Test: `Tests/PokeDexBarTests/BlindOfferTests.swift`

**Interfaces:**
- Consumes: `PlayerStore.openProfessorOffer(offerID:)`, `ProfessorIcon`,
  `EggRevealView(grade:shiny:l:language:onDone:)`
- Produces: UI 만 — 이후 태스크 없음

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`BlindOfferTests.swift` 에 더한다.

```swift
    // MARK: 닫힌 카드가 무엇을 말하나

    /// **닫힌 카드는 종·등급·가격을 한 글자도 안 말한다.** 블라인드가 새는 것은 "안 보이게
    /// 했다고 생각했는데 라벨에 남아 있는" 식으로 일어나므로, 소스 스캔이 아니라 **닫힌 상태에서
    /// 실제로 그리는 문자열**을 검사한다.
    func testAClosedCardSaysNothingAboutWhatIsInside() {
        let store = prepared()
        let offer = store.state.professorOffers[0]
        let l = store.l
        let shown = ProfessorOfferSection.closedCardText(l: l)

        let grade = offer.individual.grade
        XCTAssertFalse(shown.contains(grade.label(store.language)), "등급이 샜다: \(shown)")
        XCTAssertFalse(shown.contains("\(ProfessorBalance.price(grade: grade))"),
                       "가격이 샜다: \(shown)")
        XCTAssertFalse(shown.contains("\(offer.individual.displaySpeciesID)"),
                       "종 번호가 샜다: \(shown)")
    }

    /// 세 칸이 **같은 문구**를 쓴다 — 칸마다 다르면 그 차이가 곧 힌트다.
    func testEveryClosedCardLooksTheSame() {
        let store = prepared()
        let texts = store.state.professorOffers.map { _ in
            ProfessorOfferSection.closedCardText(l: store.l)
        }
        XCTAssertEqual(Set(texts).count, 1, "닫힌 카드가 서로 다르다: \(texts)")
    }

    /// 문구가 세 언어를 다 채운다.
    func testBlindStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            XCTAssertFalse(L(lang).offerOpen.isEmpty, "\(lang)")
        }
    }

    /// 화면이 여는 경로와 연출에 닿아 있다 — 안 닿으면 영원히 못 연다.
    func testTheSectionReachesTheOpenPathAndTheReveal() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let section = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/ProfessorOfferSection.swift"), encoding: .utf8)
        XCTAssertTrue(section.contains("openProfessorOffer"), "여는 경로에 안 닿는다")
        XCTAssertTrue(section.contains("onReveal"), "연출을 요청하지 않는다")
        XCTAssertFalse(section.contains(".help("), "안 뜨는 툴팁이 들어왔다")

        let shop = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/ShopTabView.swift"), encoding: .utf8)
        XCTAssertTrue(shop.contains("onReveal:"), "상점이 연출 요청을 안 받는다")
    }
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run: `swift test --filter BlindOfferTests`
Expected: 컴파일 실패 — `type 'ProfessorOfferSection' has no member 'closedCardText'`

- [ ] **Step 3: 문구를 더한다**

`Sources/PokeDexBar/Core/Localization.swift` 의 `professorOffersEmpty` **아래**:

```swift
    /// 가려진 카드에 적히는 말. **세 칸이 같은 문구**를 쓴다 — 칸마다 다르면 그 차이가 곧 힌트다.
    var offerOpen: String { t("열어보기", "Open", "あけてみる") }
```

- [ ] **Step 4: 닫힌 카드를 그린다**

`Sources/PokeDexBar/UI/ProfessorOfferSection.swift` 에 순수 함수와 콜백을 더한다.

`let provider: any PokeProviding` **아래**:

```swift
    /// 카드를 열었을 때 연출을 띄워 달라고 상점에 알린다 — 오버레이는 상점이 소유한다
    /// (알 뽑기 결과가 쓰는 그 자리이고, 섹션 안에 덮으면 카드 세 장 위에만 깔린다).
    var onReveal: (Grade, Bool) -> Void = { _, _ in }
```

`canAfford` 가 있던 자리(없으면 `name(_:)` 위)에:

```swift
    /// 닫힌 카드에 적히는 문자열 전부. **순수 함수로 뽑아 두는 이유는 새는지 검사하기 위해서다** —
    /// 종·등급·가격이 한 글자도 안 들어가야 하고, 그건 눈이 아니라 테스트가 봐야 한다.
    nonisolated static func closedCardText(l: L) -> String { l.offerOpen }
```

`card(_:)` 안, `let individual = offer.individual` 아래에서 닫힌 경우를 먼저 처리한다:

```swift
        if !offer.opened {
            // 박사가 아직 들고 있다 — 얼굴을 흐리게 깔아 "누가 쥐고 있는지"만 말하고
            // 무엇인지는 아무것도 안 말한다.
            Button {
                if let taken = store.openProfessorOffer(offerID: offer.id) {
                    onReveal(taken.grade, taken.showsShiny)
                }
            } label: {
                VStack(spacing: 3) {
                    ProfessorIcon(size: 30).opacity(0.35)
                    Text(Self.closedCardText(l: l))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        } else {
            // …기존 카드 본문(스프라이트·이름·등급·가격)…
        }
```

> 기존 카드 본문은 그대로 `else` 안으로 옮긴다. `@ViewBuilder` 가 붙어 있는지 확인하고,
> 없으면 `card(_:)` 에 붙인다.

- [ ] **Step 5: 상점이 연출을 띄우게 한다**

`Sources/PokeDexBar/UI/ShopTabView.swift` 의 `ProfessorOfferSection(store:provider:...)` 호출에
콜백을 더한다:

```swift
                ProfessorOfferSection(store: store, provider: provider, lines: lines,
                                      onNeedLine: onNeedLine,
                                      onReveal: { grade, shiny in reveal = (grade, shiny) })
```

> `lines`/`onNeedLine` 은 이미 넘기고 있다 — 인자 이름과 순서는 현재 코드에 맞춘다.
> `reveal` 은 이미 있는 `@State private var reveal: (grade: Grade, shiny: Bool)?` 이고,
> 그 오버레이도 이미 `EggRevealView` 를 띄운다. **새로 만들 것이 없다.**

- [ ] **Step 6: 테스트가 통과하는지 확인한다**

Run: `swift test --filter BlindOfferTests`
Expected: PASS (12개)

- [ ] **Step 7: 전체 테스트와 경고를 확인한다**

Run: `swift build --build-tests 2>&1 | grep -i warning; swift test`
Expected: 경고 출력 없음, 전체 PASS. 특히 `ProfessorTests` 의 제안 화면 렌더 테스트가
닫힌 카드 때문에 깨질 수 있다 — 그 테스트들이 먼저 열도록 고친다.

- [ ] **Step 8: 스크린샷 픽스처를 고친다**

`Tests/PokeDexBarTests/ScreenshotGenerator.swift` 가 제안을 시드하는 자리에서 **셋 중 하나는
닫힌 채로** 둔다 — 그래야 README 그림이 이 기능을 보여 준다. 나머지 둘은 열어 두어 카드 본문도
같이 보이게 한다.

Run: `PTB_SCREENSHOTS=1 PTB_APP_VERSION=1.7.0 swift test --filter ScreenshotGeneratorTests`

**그리고 결과 PNG 를 열어 본다** — `assets/professor-banner.png` 와 `assets/screenshot-shop.png`
에 닫힌 카드가 실제로 그려졌는지. 이 환경에서 이미지를 못 보면 보고서에 그렇게 적는다.

- [ ] **Step 9: 실제 앱으로 눈으로 확인한다**

```bash
PTB_DEV=1 ./scripts/build-app.sh && open "./build/PokeDexBar Dev.app"
```

확인할 것 — 상점에 카드 셋이 가려진 채 뜨는가, 한 칸을 누르면 연출이 터지고 그 칸만 열리는가,
전설을 열면 커먼보다 연출이 긴가, 안 연 카드에는 데려가기 버튼이 없는가, 앱을 껐다 켜도 연 것은
열린 채인가.

> **`PTB_DEV=1` 이 필수다.** 없으면 릴리스 구성으로 지어 실제 앱과 같은 세이브를 쓴다.

- [ ] **Step 10: 커밋**

```bash
git add Sources/PokeDexBar/ Tests/PokeDexBarTests/ assets/
git commit -m "feat: turn the Professor's cards face up one at a time"
```

---

## 배포 전에 (이 계획의 범위 밖)

`Sources/PokeDexBar/UI/` 를 건드린 `feat:` 커밋이 있으므로 **`assets/` 에 새 파일이 없으면
`release.sh` 가 중단한다**. Task 2 Step 8 이 기존 에셋을 갱신하지만 **새 파일은 아니다** —
닫힌 카드를 보여 주는 배너를 새 이름으로 하나 만들거나, 그 판단을 `docs/undocumented.md` 에
버전과 함께 적어야 한다. README ×3 과 랜딩도 그때 함께 간다.

**태그를 먼저 가져온다:** `git fetch --tags`. v1.5.0 때 로컬에 태그가 없어 `release.sh` 의
에셋 게이트가 한 버전 더 옛날부터를 봤다.
