# 폼 단위 도감 (Form-level Dex) — 설계

2026-08-20 · 사용자와 브레인스토밍으로 확정.

## 문제

도감이 `PlayerState.dex: Set<Int>`(종 번호)라서 알로라 식스테일을 부화해도 종 37이 통째로
등록된다 — 도감에서 관동 식스테일이 "잡음"으로 보이고, 정작 보유한 알로라 폼은 도감 어디에도
없다. 폼이 여러 개인 종은 **실제로 보유한 폼만** 도감에 등록·조회되어야 한다.

## 범위: 태생 폼만

도감 항목으로 갈라지는 폼은 **태어날 때 정해져 평생 가는 것**만이다.

| 포함 | 근거 |
|---|---|
| 지방 모습 전부 (`RegionalFormCatalog`) | 태생. 팔데아 켄타로스 3종(variant)도 각각 별개 항목 |
| 태생 무늬 전부 (`BirthFormCatalog`: 안농 26 · 비비용 18 · 플라베베 라인 5색 · 쉘로스 라인 2) | 태생 |
| 스트린더 amped/lowkey (성격 파생, `BirthFormBalance.toxtricitySlug`) | 성격 = 태생 |

**제외**: 메가·거다이맥스·전설 폼·모자 피카츄(도구로 켜고 끄는 변신), 위장(메타몽), 깨진 탈,
팔라핀 히어로, 테라파고스 테라스탈(상태 파생). 이들은 지금처럼 종 등록에 포함된다.

무늬를 갖고 있어도 그 단계에 카탈로그 항목이 없는 종(분이벌레·분떠도리, 스트린더 진화 전
전룡 라인 아님 — 즉 `BirthFormCatalog.forms(speciesID:)`가 빈 단계)은 원종으로 등록된다 —
스프라이트 규칙(`Individual.spriteForm`)과 동일한 기준.

## 데이터 모델 — 단일 소스

`PlayerState.dex: Set<Int>` 저장 필드를 **`dexForms: Set<String>`** 로 교체한다.

- 키 형식: 원종 `"37"`, 태생 폼 `"37/vulpix-alola"` (종 번호 + Showdown 슬러그).
  슬러그는 이미 전 카탈로그에서 유일한 스프라이트 식별자다.
- **기본 슬러그 = 원종 키.** 안농 A(`unown`)·비비용 화원(`vivillon`)·플라베베 빨강(`flabebe`)·
  쉘로스 서쪽(`shellos`)·스트린더 amped(`toxtricity`)처럼 변종의 슬러그가 종의 기본 슬러그와
  같으면 bare 키(`"201"`)로 적는다. 같은 그림에 키가 두 개 생기는 것을 막고, 옛 세이브의
  종 번호 이전(아래)과 자연스럽게 합쳐진다.
- `dex: Set<Int>`(종 단위)는 **저장하지 않고 파생**한다 — 키의 `/` 앞 종 번호를 파싱.
  기존 소비자(도감 카운터 `N/1025`, `ProfessorRoll`의 dex 가중, `ProblemReport.dexCount`)는
  시그니처 그대로.
- 파생 비용: `NationalDexView`는 body 진입 시 한 번 계산해 지역 변수로 셀에 넘긴다
  (셀마다 파싱하지 않는다).

## 등록 경로 — 헬퍼 하나로 수렴

현재 `state.dex.insert(...)`가 흩어져 있는 곳 전부를 **개체 기반 헬퍼 하나**로 바꾼다:

```swift
// PlayerState 또는 PlayerStore 내부
static func dexKey(for individual: Individual) -> String   // 개체 → 도감 키
```

개체의 `region`/`regionVariant`/`birthForm`/성격(스트린더 849)에서 키를 계산한다. 계산 규칙은
`Individual.spriteForm`의 태생 분기와 일치해야 한다(도구·상태 분기는 무시).

바꿀 지점 (전수):

| 위치 | 현재 |
|---|---|
| `PlayerStore.chooseStarter` (PlayerStore.swift:67) | `insert(speciesID)` — 스타터는 태생 폼이 없어 bare 키 |
| `PlayerStore.registerInDex` (PlayerStore.swift:279) | 테스트·스크린샷 시더 전용 — 종 번호 API 유지(bare 키 삽입) |
| `PlayerStore.addForTesting` (PlayerStore.swift:292) | `dexKey(for:)` 사용 |
| `PlayerStore+Hatching.claimHatch` (:53) | `dexKey(for:)` — 위장 중 등록 유예는 그대로 |
| `PlayerStore+Evolution` (:98, :121 껍질몬) | `dexKey(for:)` — 진화 후 개체로 계산해 알로라 식스테일 → 나인테일즈-알로라가 자동으로 맞는다 |
| `PlayerStore+Ditto.revealDisguises` (:24) | 정체 공개 시 `dexKey(for:)` |
| `PlayerStore+Professor` 데려오기 (:155) | 박사 제안 수령 시 `dexKey(for:)` |

## 도감 UI — 탭 상세

`NationalDexView` 그리드는 종당 한 칸 유지.

- **칸 상태**: 어느 폼이든 하나라도 등록 → 밝음. 스프라이트는 bare 키가 있으면 원종,
  아니면 등록된 폼 중 카탈로그 순서 첫 번째의 슬러그로 그린다. 없으면 지금처럼 실루엣.
- **탭 상세**: 태생 폼 후보가 2개 이상인 종의 칸을 탭하면 팝오버 안에서 폼 목록이 열린다.
  - 행 구성: 지방 모습이 있는 종 = 원종 행 + 지방 폼 행들. 태생 무늬 종 = 무늬 행들
    (원종 행 없음 — A·화원·빨강·서쪽·amped가 곧 그 자리다). 팔데아 켄타로스 = 원종 + 3 변종.
  - 등록 폼: 스프라이트 + 폼 이름(`FormLabel`/`Region.label`). 미등록 폼: 실루엣 + 폼 이름.
    **이름은 가리지 않는다** — 뭘 모아야 하는지가 수집 목표가 된다.
  - 헤더에 `폼 n/m` 진행 표시.
  - 후보가 1개뿐인 종(대다수)은 탭 동작 없음(현행 유지).
- 도감 전체 카운터는 지금처럼 종 단위 `N / 1025`.

폼 후보 열거는 카탈로그에서 파생하는 순수 함수로 둔다(테스트 대상):

```swift
static func dexFormCandidates(speciesID: Int) -> [DexFormCandidate]
// DexFormCandidate: key(도감 키), slug(스프라이트), label(폼 이름 | 원종)
```

## 세이브 이전 & 신뢰경계

- **디코더 이전**: `PlayerState.init(from:)`에서 `dexForms` 키가 없으면 옛 `dex`(Int 배열)를
  읽어 각 종을 bare 키로 넣는다 — "원종 인정". 옛 `dex` 키는 이후 인코딩에서 쓰지 않는다.
  **단, 태생 무늬 종은 제외**(`DexKey.bareKeyIsAPlainBase`) — 안농·스트린더 같은 종은 bare
  키가 원종이 아니라 특정 변종(A·하이한 모습)이라, 종 번호만으로는 그 변종을 잡았다고 말할
  수 없다(사용자 리포트 2026-08-20: C 안농만 잡았는데 A 가 등록됨). 그 종은 박스 재스캔만
  믿는다. 판별은 "원종 행(label == nil)이 후보에 실제로 있는가".
- **박스 재스캔**: `PlayerStore.load()` 직후 1회, 박스의 모든 개체에 `dexKey(for:)`를 돌려
  합친다. 세이브 이전 직후뿐 아니라 매 기동에 돌아도 무해하다(멱등) — 별도 마이그레이션
  플래그를 두지 않는다.
- **값 범위 검증** (관대 디코딩의 짝, CLAUDE.md 결함 대응 프로토콜): 디코드 경계에서
  종 번호가 1...1025 밖이거나, 슬러그부가 태생 폼 카탈로그(지방·태생 무늬·스트린더)에 그 종의
  것으로 존재하지 않는 키는 버리고 로그를 남긴다. 유령 키가 도감 카운터를 부풀리지 않게 한다.
- `dexForms`는 기기 장부가 아니라 **진행**이다 — 세이브를 옮기면 그대로 간다.

## 테스트

트리거 브랜치를 실제로 밟는 회귀 가드(결함 대응 프로토콜 §3):

1. 알로라 개체 부화 → 알로라 키만 등록, bare 키 없음. **대조군**: 원종 부화 → bare 키만.
2. 알로라 식스테일 진화 → `38/ninetales-alola` 등록 (진화 경로가 폼을 잇는다).
3. 옛 세이브 JSON(`dex: [37]`, `dexForms` 없음) 디코드 → `"37"` 이전 + 박스의 알로라 개체
   재스캔 반영. **대조군**: 재스캔 없이 디코드만 하면 알로라 키가 없는지 확인(트리거 보증).
4. 파생 `dex` — 같은 종의 두 폼 키 = 종 1로 센다.
5. 경계 검증 — 종 범위 밖·엉뚱한 슬러그 키 드롭, 정상 키 생존.
6. 특례: 스트린더 lowkey 부화 → `849/toxtricity-lowkey`; 안농 A 부화 → bare `"201"`;
   분이벌레(무늬 보유, 단계 항목 없음) → bare 키, 비비용 진화 시 무늬 키.
7. UI 순수 함수: `dexFormCandidates` — 켄타로스 4행, 안농 26행, 식스테일 2행, 일반 종 1행.

## 릴리스 메모

UI 변경(도감 탭 상세)이므로 다음 릴리스에서 신규 에셋 게이트(`release.sh`)에 걸린다 —
도감 상세가 담긴 스크린샷을 새 에셋으로 추가해야 한다.
