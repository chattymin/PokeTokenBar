# 박사에게 보내기 · 확정 알 교환권 — 설계

2026-08-11

## 무엇을 만드나

두 덩어리다. 서로 맞물리지만 각자 배포해도 성립한다.

- **A. 확정 알 교환권** — 더 진화할 곳이 없는 파트너가 경험치를 모으면, 자기 라인의 알을 하나
  불러오는 교환권을 받는다.
- **B. 박사에게 보내기** — 필요 없는 개체를 박사에게 보내 포인트를 받고, 박사가 매일 내미는
  3마리와 그 포인트를 교환한다.

**구현 계획은 둘로 나눈다** — A 한 벌, B 한 벌. 각자 동작하는 소프트웨어로 끝나고 따로 배포된다.

**A 를 먼저 낸다.** B 는 최종진화체를 통째로 내주므로 그 앞 단계들이 도감에 구멍으로 남는데,
A 가 있으면 받은 아이를 곁에 두고 키워 자기 라인의 알을 불러 그 구멍을 메울 수 있다. 순서를
뒤집으면 그 사이에 받은 개체마다 메울 길 없는 구멍이 생긴다.

---

## A. 확정 알 교환권

### 왜 필요한가

지금 **최종진화체의 경험치는 통째로 버려진다.** `evolutionChoices` 가 빈 배열이라 `canEvolve`
가 참이 되어도 갈 곳이 없고, 그 뒤로 파트너가 버는 경험치는 아무 데도 안 쓰인다. 리자몽을
파트너로 두는 것이 이 앱에서는 손해다 — 다 키운 아이일수록 곁에 둘 이유가 없어지는, 방향이
거꾸로 된 유인이다.

### 규칙

**진화할 곳이 없는 개체**만 교환권을 번다. 경험치를 쓸 데가 있는 아이는 진화에 쓴다.

임계는 `ExpBalance.threshold(grade: grade, stageIndex: 0)` — 등급 기본값을 그대로 쓴다.

| 등급 | 교환권 1장 | (대조) 1→2단계 진화 |
|---|---|---|
| common | 50,000,000 | 50,000,000 |
| rare | 100,000,000 | 100,000,000 |
| epic | 200,000,000 | 200,000,000 |
| legendary | 400,000,000 | 400,000,000 |

*"한 단계 진화할 값어치를 모을 때마다 자기 라인의 알을 하나 불러온다."* 최종진화체에 갇힌
경험치가 진화와 **같은 환율**로 다시 흐른다. 새 환율을 발명하지 않는 것이 요점이다.

교환권이 가리키는 종은 그 개체의 **`baseID`** 다. 리자몽은 파이리 알을, 라프라스는 라프라스
알을 부른다.

### 지급 방식 — 자동이 아니라 사용자가 누른다

진화와 **같은 방식**으로 간다: 임계에 닿으면 배지가 뜨고, 사용자가 누를 때 지급된다.

자동 지급을 안 하는 이유는 두 가지다.

1. **최종형인지 아는 데 `EvoLine` 이 필요하다.** 그 라인은 네트워크에서 오고 UI 가 비동기로
   싣는다. `PlayerStore.update()`(사용량 갱신 경로)에는 라인이 없으므로 거기서는 판정 자체가
   불가능하다. 판정을 하려면 "최종형인가"를 세이브에 캐시해야 하는데, 그건 네트워크에서 파생된
   값을 영속 상태에 굳히는 일이라 라인 데이터가 바뀌면 조용히 틀어진다.
2. 진화가 이미 "배지 → 사용자 클릭" 이고, 같은 자리에서 같은 경험치를 쓰는 일이 두 가지 방식으로
   갈리면 안 된다.

**기다린다고 손해 보지 않는다.** 경험치는 계속 쌓이고, 지급은 `exp -= 임계` 이므로 한 주 만에
열어도 쌓인 만큼 연속으로 받을 수 있다. (`Discovery` 가 세운 축 — "앱을 켜 둔 쪽이 아니라 실제로
일한 쪽에 보상" — 을 그대로 지킨다.)

### 사용

`Egg` 는 이미 종과 이로치를 **뽑는 순간 고정**한다(스프라이트 선반입을 위해). 그래서 `Egg` 에는
필드를 하나도 더하지 않는다. 다만 `PlayerStore` 쪽은 두 군데 손봐야 한다.

**① `startEgg` 은 값을 치른다.** 지금 본문이 `spentTokens += EggBalance.drawPrice` 를 포함하므로
그대로 부르면 교환권을 쓰고 토큰까지 낸다. 슬롯 배치·부화 시간 계산(부화 감면 포함)을 값 치르는
부분에서 떼어낸다.

```swift
/// 값과 무관하게 알을 슬롯에 넣는다. 빈 슬롯이 없으면 nil.
/// 부화 감면은 여기서 적용된다 — 교환권 알도 똑같이 받는다.
func placeEgg(grade: Grade, speciesID: Int, shiny: Bool) -> Egg?

/// 값을 치르고 `placeEgg` 를 부른다. 재화가 모자라면 nil.
func startEgg(grade: Grade, speciesID: Int, shiny: Bool) -> Egg?
```

교환권 경로는 `placeEgg` 를 부른다. **`canDraw` 가 아니라 빈 슬롯만 본다** — 지갑은 안 본다.

**② 등급을 교환권이 들고 있어야 한다.** `EggBalance.speciesGrade` 는 `BaseSpecies` 를 받는
`private` 함수라, 쓰는 시점에 네트워크 인덱스가 있어야 한다. 그러면 오프라인에서 교환권을 못 쓴다.
등급은 **지급 시점에 개체에서 그대로 가져온다** — `Individual.grade` 가 이미 그 라인의 등급이다.
`speciesGrade` 는 건드리지 않는다.

```swift
placeEgg(grade: voucher.grade,       // 지급할 때 개체에서 받아 둔 값
         speciesID: voucher.baseID,  // 확정
         shiny: EggBalance.rollShiny(<굴림>, hasCharm: state.ownsShinyCharm))
```

`Egg` 는 이미 종과 이로치를 **뽑는 순간 고정**한다(스프라이트 선반입을 위해). 그래서 `Egg` 에
필드를 하나도 더하지 않는다. `startEgg(grade:speciesID:shiny:)` 도 이미 종을 인자로 받는다.

- **토큰은 안 든다.** 교환권이 값이다.
- 종은 확정, **이로치는 평소 확률로 굴린다** — 확정으로 만들면 이로치 부적이 무의미해진다.
- 등급은 그 종의 등급을 따른다(`EggBalance` 의 종→등급 판정). 등급이 부화 시간을 정하므로
  파이리 알은 epic 시간을 그대로 기다린다.
- **빈 알 슬롯이 없으면 못 쓴다.** 실패해도 교환권은 차감되지 않는다.

### API

```swift
extension PlayerStore {
    /// 이 개체가 교환권을 받을 수 있나. 라인이 필요하다 — 최종형 판정이 라인에 달렸다.
    func canClaimEggVoucher(_ individual: Individual, line: EvoLine) -> Bool

    /// 교환권 지급. 경험치를 임계만큼 차감하고 `eggVouchers` 에 한 장 더한다
    /// (`EggVoucher(baseID: individual.baseID, grade: individual.grade)`).
    /// 조건을 못 채우면 아무것도 하지 않고 false.
    @discardableResult
    func claimEggVoucher(individualID: UUID, line: EvoLine) -> Bool

    /// 교환권으로 알을 건다. 빈 슬롯이 없거나 그 종의 교환권이 없으면 nil — 이때 차감도 없다.
    /// 같은 종이 여러 장이면 한 장만 없앤다(`firstIndex` 로 지운다).
    @discardableResult
    func redeemEggVoucher(baseID: Int) -> Egg?
}
```

`claimEggVoucher` 는 `evolve(individualID:to:line:)` 와 같은 모양으로 쓴다 — 같은 가드, 같은
`exp - threshold` 이월.

---

## B. 박사에게 보내기

### 재화

**별도 포인트다.** `wallet`(`earnedTokens - spentTokens`) 과 섞지 않는다.

섞으면 토큰을 안 쓰고도 재화가 도는 길이 생긴다 — 알을 뽑아 부화시켜 팔아 다시 알을 뽑는
순환이다. 이 앱의 전제는 "쓴 토큰이 곧 재화" 이므로 그 순환이 생기는 순간 메뉴바에 붙어 있을
이유가 흐려진다. 포인트로는 **알을 살 수 없고**, 토큰으로는 **박사와 거래할 수 없다.**

### 보내면 받는 값

등급과 경험치, 두 가지로만 정한다.

```
포인트 = floor(등급기본 × (stageIndex + 1 + 현재단계 경험치비율))

stageIndex   = individual.stageIndex                     // pathIDs.count - 1
경험치비율    = min(1, exp / ExpBalance.threshold(grade: grade, stageIndex: stageIndex))
```

| 등급 | 등급기본 | 갓 깬 아이 | 1회 진화 | 2회 진화 |
|---|---|---|---|---|
| common | 2 | 2 | 4 | 6 |
| rare | 5 | 5 | 10 | 15 |
| epic | 12 | 12 | 24 | 36 |
| legendary | 40 | 40 | 80 | 120 |

(표는 경험치 0 기준 — 지금 단계에서 채운 만큼이 여기에 더해진다. 경험치를 꽉 채운 2회 진화
전설은 `floor(40 × 4) = 160`.)

키운 아이일수록 값이 나가므로 **정리 대상이 자연히 안 키운 중복**이 된다. 의도한 방향이다.

### 안전장치

- **파트너는 못 보낸다.** 버튼 자체가 안 뜬다.
- 확인창에 이름·등급·이로치 여부와 **"돌아오지 않습니다"** 를 띄운다.
- **이로치와 전설은 한 번 더 묻는다.**
- 그 밖에는 막지 않는다. 도감에 하나뿐인 개체도 보낼 수 있다 — 도감은 만난 기록이지 소유
  기록이 아니므로 `dex` 에서는 아무것도 지우지 않는다.

### 박사의 제안

날짜(`state.lastDate`)가 바뀌면 3마리를 새로 뽑는다.

뽑는 경로를 새로 만들지 않는다 — 알이 깨질 때와 **똑같이** `EggBalance.rollGrade` →
`EggBalance.pickSpecies` → `EggBalance.rollShiny` 를 지난다. 그래서 제안에도 이로치·성격·태생폼이
그대로 실린다.

**시드는 날짜 문자열에서 만든다.** 굴림에 `SeededRNG(seed: fnv1a(state.lastDate))` 를 쓴다.

> **함정 — `String.hashValue` 를 쓰면 안 된다.** Swift 의 기본 해시는 프로세스마다 무작위로
> 시딩되므로 앱을 껐다 켤 때마다 다른 값이 나온다. FNV-1a 같은 결정적 해시를 직접 쓴다.

시드가 필요한 이유: 제안 생성은 `baseSpeciesIndex()`(네트워크)를 요구하므로, 그날 처음 열었을 때
인덱스가 아직 안 왔으면 생성이 미뤄진다. 시드가 없으면 재시도할 때마다 다른 3마리가 나와,
"인덱스가 오기 전에 껐다 켜면 리롤" 이라는 길이 생긴다.

뽑힌 제안은 **상태에 저장한다** — 매번 다시 굴리지 않는다.

가격은 등급기본의 5배다.

| 등급 | 가격 |
|---|---|
| common | 10 |
| rare | 25 |
| epic | 60 |
| legendary | 200 |

**이로치가 떠도 값은 같다.** 리롤이 없으니 그날 운이고, 그게 매일 열어 볼 이유가 된다.

교환한 자리는 **데려갔다는 표시로 남고 그날은 다시 안 채워진다.** 자리를 아예 없애지 않는 것은,
빈 칸 두 개보다 "셋 중 하나는 이미 데려갔다"가 사용자에게 더 정확하기 때문이다.

### API

```swift
extension PlayerStore {
    /// 이 개체를 보내면 받을 포인트. 파트너면 nil — 보낼 수 없다는 뜻이다.
    func releaseValue(_ individual: Individual) -> Int?

    /// 박사에게 보낸다. 박스에서 빼고 포인트를 더한다. `dex` 는 건드리지 않는다.
    @discardableResult
    func releaseToProfessor(individualID: UUID) -> Bool

    /// 오늘의 제안을 준비한다. 날짜가 그대로면 아무것도 하지 않는다.
    func refreshProfessorOffers(index: [BaseSpecies])

    /// 제안 교환. 포인트가 모자라면 false — 이때 차감도 없다.
    @discardableResult
    func acceptProfessorOffer(offerID: UUID) -> Bool
}
```

---

## 데이터 모델

`PlayerState` 에 네 필드가 는다. **전부 관대 디코더(`init(from:)`)에도 넣는다.**

```swift
/// 확정 알 교환권. 장수는 원소 개수다 — 같은 종 두 장이면 원소가 둘.
var eggVouchers: [EggVoucher] = []
/// 박사에게 쌓인 포인트. `wallet` 과 완전히 별개다.
var researchPoints = 0
/// 오늘의 제안을 뽑은 날짜. `lastDate` 와 다르면 새로 뽑는다.
var professorOfferDate = ""
/// 오늘의 제안 3마리.
var professorOffers: [ProfessorOffer] = []
```

```swift
/// 자기 라인의 알을 하나 불러오는 표. **등급을 같이 들고 다닌다** — 등급 판정에 네트워크
/// 인덱스가 필요한데, 그걸 쓸 때 요구하면 오프라인에서 교환권을 못 쓰게 된다. 지급하는
/// 시점에는 개체가 손에 있으므로 `Individual.grade` 를 그대로 받아 둔다.
struct EggVoucher: Codable, Sendable, Equatable, Hashable {
    var baseID: Int
    var grade: Grade
}

struct ProfessorOffer: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var speciesID: Int
    var grade: Grade
    var shiny: Bool
    var nature: PokemonNature
    /// `BirthFormCatalog` 의 **variant 키**(`"c"`·`"polar"`·`"blue"`). 슬러그가 아니다 —
    /// `Individual.birthForm` 과 같은 형식이라 그대로 옮겨 담을 수 있다. 해당 없으면 nil.
    var birthForm: String?
    /// 오늘 이미 교환했나. 배열에서 빼지 않고 표시로 남긴다 — 그래야 화면이 "오늘 이건 이미
    /// 데려갔다"를 3칸 자리에 그대로 보여줄 수 있고, 그날 안 되살아나는지도 검사할 수 있다.
    var claimed = false
}
```

> **이 저장소가 세 번 밟은 부류다.** `disguisedAs`·`birthForm`·`formBroken` 이 각각 관대
> 디코더에 안 들어가 "저장은 되는데 못 읽는" 상태로 나갔다. 필드를 더할 때 `init(from:)` 을
> 같이 고치고, 저장 왕복 테스트로 못박는다.

`SaveTransfer.sanitized` 도 손본다 — `researchPoints` 는 산술에 쓰이는 수치이므로 외부 파일에서
`Int.max` 가 들어오면 오버플로 트랩으로 프로세스가 죽는다. 경계 한 곳에서 자른다. `eggVouchers`
는 *항목* 이므로 개수를 자르지 않는다(자르면 데이터 손실이다) — 대신 말이 안 되는 `baseID` 를 가진
원소만 버린다.

`SaveTransfer.rebasedForThisDevice` 는 손대지 않는다 — 넷 다 **진행**이지 이 기기 장부가 아니다.
(`professorOfferDate` 는 날짜라 장부처럼 보이지만, 다른 기기에서 들여온 날짜가 오늘과 다르면
그냥 새로 뽑히므로 자체 교정된다.)

### 딸린 정리 — `HatchSpeedup`

**개체가 박스에서 빠지는 경로가 이 앱에 처음 생긴다.** `HatchSpeedup.present(in: box)` 는 그런
경로가 없다는 전제 위에 서 있고, 주석이 그걸 명시한다:

> 개체는 박스에서 빠지는 경로가 없으므로 "한 번이라도 얻었으면" 과 "박스에 있으면" 은 같은 말이다.

B 가 그 전제를 깬다 — 유일한 파이리를 보내면 부화 감면이 사라진다. **`box` 대신 `dex` 를 본다.**
`dex` 가 정확히 "한 번이라도 보유한 종" 이므로 주석이 원래 말하려던 것과 같아진다.

```swift
static func present(in dex: Set<Int>) -> Bool
static func warmer(in dex: Set<Int>, box: [Individual]) -> Individual?
```

`warmer` 는 화면에 이름을 내밀기 위한 것이라 개체가 필요하다. 감면을 준 종이 박스에 없으면
(보냈으면) 이름을 못 대므로 `nil` 을 돌려주고, `EggSlotsView` 의 안내 줄만 빠진다 — **감면 자체는
유지된다.** 이 둘이 갈린다는 점이 이 변경의 핵심이다.

---

## 화면

새 탭은 만들지 않는다. 세 군데를 고친다.

### 개체 상세 (`IndividualDetailView`)

- `expSection` — 진화할 곳이 없는 개체면 지금은 채워진 막대만 덩그러니 있다. 여기서 **교환권
  임계 기준**으로 막대를 그리고, 임계에 닿으면 `DetailActionButton` 으로 "확정 알 교환권 받기"
  를 띄운다. 최종진화체를 곁에 둘 이유가 그 자리에서 보인다.
- `actions` — "박사에게 보내기" 버튼. 받을 포인트를 제목에 적는다("박사에게 보내기 · +4").
  파트너면 안 뜬다.

### 박스 (`BoxTabView`)

`readyToEvolve` 옆에 `readyToClaimVoucher` 를 둔다. `BoxCell` 이 이미 `canEvolve` 배지를
그리므로 같은 자리에 다른 기호로 그린다. 라인 로딩도 이미 하고 있어 새로 실을 것이 없다.

### 상점 (`ShopTabView`)

맨 위에 **"박사의 제안"** 섹션 — 포인트 잔액과 오늘의 3마리(스프라이트·이름·등급·이로치
표시·가격). `claimed` 인 자리는 그 자리에 그대로 남되 흐리게 그리고 가격 대신 "데려갔어요"를 쓴다.

### 알 슬롯 (`EggSlotsView`)

빈 슬롯에 교환권이 있으면 "확정 알" 버튼. 교환권이 여러 종이면 목록에서 고른다.

### 문구

전부 `L.t(ko, en, ja)` 로 ko/en/ja 세 언어를 동시에 채운다.

---

## 테스트

### A

- 진화할 곳이 **있는** 개체는 교환권을 못 받는다 (경험치는 진화용)
- 진화할 곳이 없고 경험치가 찼으면 받는다
- 지급 후 경험치가 임계만큼 줄고, 초과분은 남는다 (연속 지급이 되는지)
- **교환권으로 알을 걸어도 토큰이 안 줄어든다** (`spentTokens` 불변). `startEgg` 을 그대로
  부르면 여기서 깨진다
- **`startEgg` 은 여전히 값을 치른다** — 떼어내다 상점 뽑기가 공짜가 되지 않는지 대조군으로 확인
- 교환권 알도 **부화 감면을 받는다** (`placeEgg` 로 옮기면서 빠뜨리기 쉬운 자리)
- 교환권으로 건 알의 종이 확정 — **굴림 시드를 바꿔도 같은 종**
- 이로치는 확정이 아니다 (시드를 바꾸면 갈린다)
- 슬롯이 꽉 차면 사용 실패 + **교환권 미차감**
- 없는 교환권을 쓰려 하면 실패 + 음수로 안 내려감

### B

- 파트너는 못 보낸다
- 보낸 뒤 `dex` 가 그대로다
- **보낸 뒤 부화 감면이 그대로다** (이번에 새로 생기는 위험 — 파이리 하나만 가진 상태에서
  보내고, 새 알이 여전히 절반인지 본다. `warmer` 가 nil 이 되어도 `present` 는 참이어야 한다)
- 등급·진화 단계·경험치별 포인트 산식이 표와 일치
- 같은 날 두 번 준비해도 같은 3마리, 날짜가 바뀌면 다른 3마리
- **재기동해도 같은 3마리** (`String.hashValue` 를 쓰면 여기서 깨진다)
- 교환한 자리는 그날 안 되살아난다
- 포인트가 모자라면 교환 실패 + **포인트 미차감**
- 포인트로 알을 못 사고, 토큰으로 제안을 못 산다 (두 재화가 안 섞이는지)

### 공통

- 네 필드 저장 왕복 — 재기동 후에도 남는다
- `SaveTransfer.sanitized` 가 말도 안 되는 값을 자른다

### 회귀 가드

- `HatchSpeedup` 이 `box` 를 직접 보지 않는다는 것을 소스 스캔으로 고정 (되돌아오면 실패)

---

## 하지 않는 것

- **박사에게서 되찾기.** 보낸 아이는 돌아오지 않는다. 되돌리기를 만들면 확인창의 무게가 사라진다.
- **포인트↔토큰 환전.** 두 재화를 나눈 이유 자체를 없앤다.
- **제안 리롤.** 유료든 무료든. 그날 운이라는 점이 매일 열어 볼 이유다.
- **일괄 보내기.** 한 번에 여러 마리를 보내는 화면. 되돌릴 수 없는 조작을 묶는 것은 사고를 부른다.
  실제로 번거로워진 뒤에 다시 본다.
- **교환권 거래.** 교환권을 포인트로 사거나 팔기.
- **교환권 만료.**

---

## 릴리스

A 와 B 를 각각 마이너로 낸다. 둘 다 UI 를 건드리는 `feat:` 이므로 **`assets/` 에 새 파일이 있어야
`release.sh` 를 통과한다** — A 는 교환권 화면, B 는 박사의 제안 화면을 새로 찍는다.

```bash
PTB_SCREENSHOTS=1 PTB_APP_VERSION=<버전> swift test --filter ScreenshotGeneratorTests
```
