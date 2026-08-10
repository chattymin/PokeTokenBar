import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import PokeDexBar

// README 스크린샷·애니메이션 생성기.
//
// 실행:
//   PTB_SCREENSHOTS=1 swift test --filter ScreenshotGeneratorTests
//   (릴리스 버전을 설정 화면 푸터에 찍으려면: PTB_APP_VERSION=2.6.0 을 함께 준다)
//
// 환경변수 없이는 전부 skip 된다 — 평소 `swift test` 는 `assets/` 를 건드리지 않는다.
//
// 왜 이렇게 만드나: 예전 스크린샷은 손으로 쓴 HTML 을 헤드리스 크롬으로 찍은 목업이라, 앱에서
// 사라진 화면(가방 탭·직접 구매 상점)이 README 에 몇 달째 남아 있었다. 여기서는 **앱이 실제로
// 그리는 SwiftUI 뷰**를 그대로 오프스크린 렌더한다(`BoxViewTests`/`FormTests` 의 NSHostingView
// 패턴). 뷰가 바뀌면 다음 실행에서 그림도 같이 바뀌므로 목업처럼 드리프트하지 않는다.
//
// 세이브는 절대 건드리지 않는다 — 임시 파일 URL 로 스토어를 만들고 `#if DEBUG` 시드 헬퍼만 쓴다.
// 스프라이트는 읽기 전용으로 디스크 캐시(`~/Library/Application Support/PokeDexBar/sprites`)에서
// `SpriteView.init` 이 동기 시드하므로 네트워크 없이도 그림이 나온다.
//
// **UI 를 고칠 때 알아 둘 것 — CALayer 필터는 이 캡처에 안 담긴다.** `cacheDisplay` 는 뷰의
// *그리기* 경로를 찍으므로, SwiftUI 가 레이어 필터로 내리는 수식어(`.brightness`·`.saturation`·
// `.blur` 등)는 화면에서는 보여도 스크린샷에서는 통째로 빠진다(`.opacity` 는 레이어 alpha 라 그대로
// 나온다). 도감 실루엣이 이 함정을 한 번 밟았고 — `.brightness(-1)` 은 스크린샷에서 사라져
// 미포획 종이 컬러로 찍혔다 — `SpriteView(silhouette:)` 의 템플릿 렌더링으로 옮겨 해결했다.
// 새로 넣은 효과가 스크린샷에만 안 보이면 캡처를 의심하지 말고 그 수식어를 그리기 단계 표현으로
// 바꾸는 쪽이 맞다. (윈도우 서버 캡처는 필터까지 나오지만 화면 기록 권한에 묶여
// "다시 돌릴 수 있는 생성기"가 못 된다.)
//
// **애니메이션 GIF 도 여기서 만든다.** 정적 PNG 와 다른 점은 런루프를 실제로 돌린다는 것뿐이다 —
// 스프라이트 GIF 루프(`SpriteView` 의 `.task`)와 알 카운트다운(`TimelineView` 1초 틱)은 런루프가
// 돌아야 진행하므로, `liveFrames` 가 `RunLoop.main` 을 돌려 뷰가 스스로 움직이게 두고 일정 간격으로
// 결과를 샘플링한다. **담기는 움직임은 전부 앱이 실제로 만드는 움직임이다** — 페이드·슬라이드 같은
// 합성 전환은 넣지 않는다. 인코딩은 SDK 내장 ImageIO(`CGImageDestination`)로 하며 외부 도구
// (gifsicle 등)에 의존하지 않는다.

/// 라인 조회를 즉답으로 대신한다 — 오프스크린 렌더는 `.task` 를 돌릴 기회가 없어 네트워크 조회가
/// 착지하지 않는다. 진화 후보는 뷰에 `lines:` 로 직접 주입한다.
private struct StubProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        ScreenshotFixture.line(baseID: baseSpeciesID)
            ?? EvoLine(baseID: baseSpeciesID,
                       tree: EvoNode(speciesID: baseSpeciesID, children: []),
                       rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// 사용량 스텁 — 홈 탭의 숫자·한도는 `UsageStore` 의 `private(set)` 프로퍼티라 밖에서 못 꽂는다.
/// 스텁 프로바이더를 넣고 실제 `refresh()` 를 한 번 태워 앱과 같은 경로로 채운다(네트워크 없음).
private struct StubUsageProvider: UsageProvider {
    let id: String
    let displayName: String
    let daily: DailyUsage
    let enrichment: ProviderEnrichment
    func fetchDaily() async throws -> DailyUsage? { daily }
    func fetchEnrichment() async -> ProviderEnrichment { enrichment }
}

private struct StubClaudeLimits: ClaudeLimitsProviding {
    let status: LimitStatus
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus { status }
}

/// Codex 는 공식 한도를 안 넣는다 — 홈 탭 한도 섹션은 선택된 첫 탭(Claude)만 그린다.
private struct StubCodexLimits: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}

/// 상태 페이지 조회를 막는다 — 기본 구현은 statuspage.io 를 친다.
private struct StubStatusProvider: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] { [:] }
}

/// 뽑기 연출 화면 — 앱과 같은 겹침(상점 위 `.overlay`)을 그대로 만든다.
///
/// `armed` 로 연출의 등장 시점을 쥔다. 연출은 한 번 재생되고 끝나므로 창이 준비되기 전에 얹으면
/// 앞 단계가 준비 시간만큼(실측 0.16~0.56초, 실행마다 다름) 잘린 채 찍힌다. `liveFrames` 가 첫
/// 프레임 직전에 `armed` 를 켠 뷰로 갈아끼워, 연출의 시작과 촬영의 시작을 맞춘다.
/// (`@Observable` 스위치로도 해봤지만 오프스크린 호스팅 뷰에서는 body 가 다시 평가되지 않아
/// 오버레이가 끝까지 안 붙었다 — 루트 뷰 교체는 확실히 반영된다.)
private struct RevealComposite: View {
    let store: PlayerStore
    let provider: any PokeProviding
    let armed: Bool

    var body: some View {
        ShopTabView(store: store, provider: provider)
            .padding(PopoverMetrics.padding)
            .frame(width: PopoverMetrics.width)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay {
                if armed {
                    EggRevealView(grade: ScreenshotFixture.revealGrade,
                                  shiny: ScreenshotFixture.revealShiny,
                                  l: store.l, language: store.language,
                                  onDone: { })   // 끝나도 그대로 둔다 — 마지막 프레임이 결과 화면이어야 한다
                }
            }
    }
}

/// 부화 연출을 홈 위에 얹은 화면. 앱에서도 슬롯의 '확인'을 누른 직후 그 자리에 덮이므로,
/// 알 슬롯이 배경으로 보이는 이 구도가 실제 화면과 같다.
private struct HatchComposite: View {
    let store: PlayerStore
    let individual: Individual
    let armed: Bool

    var body: some View {
        EggSlotsView(store: store, now: ScreenshotFixture.now)
            .padding(PopoverMetrics.padding)
            // 연출은 알 그림·이름·등급까지 세로로 길다. 슬롯 줄 높이에 맞추면 이름이 잘려
            // 정작 무엇이 나왔는지가 안 담긴다 — 연출이 다 들어갈 만큼 자리를 준다.
            .frame(width: PopoverMetrics.width, height: 250, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay {
                if armed {
                    HatchedRevealView(individual: individual, store: store,
                                      line: ScreenshotFixture.lines[individual.baseID],
                                      onDone: { })   // 끝나도 그대로 — 마지막 프레임이 결과여야 한다
                }
            }
    }
}

/// 이로치 개체의 상세 화면. 반짝임은 화면에 **들어오는 순간** 한 번 나므로
/// (`IndividualDetailView` 의 `.task(id:)`), 창이 다 준비된 뒤에 열어야 연출의 시작과
/// 촬영의 시작이 맞는다. `selection` 을 넣는 것이 곧 박스에서 한 마리를 누른 것이다.
private struct SparkleComposite: View {
    let store: PlayerStore
    let selection: UUID?

    var body: some View {
        BoxTabView(store: store, lines: ScreenshotFixture.lines,
                   onNeedLine: { _ in }, selection: .constant(selection))
            .padding(PopoverMetrics.padding)
            // 반짝임은 초상 둘레 96pt 판에서 난다. 아래로 긴 상세 화면을 통째로 담으면
            // 정작 보여줄 것이 그림 한 귀퉁이가 된다. 다만 경험치 바에서 끊는다 —
            // 글이 반쯤 잘린 채 끝나면 그림이 덜 만들어진 것처럼 보인다.
            .frame(width: PopoverMetrics.width, height: 212, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// `waitFor` 가 비동기 결과를 받아 두는 자리. 지역 `var` 캡처 대신 참조 하나를 쓴다.
@MainActor
private final class AsyncResult<T> {
    var value: Result<T, any Error>?
}

/// 스크린샷에 담을 세이브 픽스처 — "그럴듯한 플레이 중반"의 상태. 값은 전부 여기서만 정한다.
enum ScreenshotFixture {
    /// 기준 시각(2026-01-01 00:00 UTC). 알 카운트다운이 실행할 때마다 달라지지 않게 고정한다.
    static let now = Date(timeIntervalSince1970: 1_767_225_600)

    /// 박스에 넣을 개체들 — 목록 순서가 곧 화면 순서다(획득 시각을 내림차순으로 배정한다).
    /// 파트너는 진화까지 절반쯤 온 리자드, 그 옆에 임계를 넘긴 피카츄(진화 배지·상세 화면용),
    /// 이로치 하나, 같은 라인의 서로 다른 단계(파이리·리자드·리자몽 / 피카츄·라이츄), 지방 모습 넷.
    static let roster: [(species: Int, path: [Int], grade: Grade, nature: PokemonNature,
                         exp: Int, shiny: Bool, region: Region?, birthForm: String?)] = [
        (5, [4, 5], .epic, .brave, 380_000_000, false, nil, nil),          // 파트너 — 리자몽까지 63%
        (25, [25], .common, .jolly, 55_000_000, false, nil, nil),          // 임계 초과 → 진화 배지
        (700, [700], .epic, .modest, 90_000_000, true, nil, nil),          // 이로치
        (37, [37], .rare, .timid, 40_000_000, false, .alola, nil),         // 알로라 식스테일
        (52, [52], .common, .naughty, 12_000_000, false, .galar, nil),     // 가라르 나옹
        (26, [25, 26], .common, .hasty, 30_000_000, false, nil, nil),      // 피카츄 라인의 진화형
        (6, [4, 5, 6], .epic, .adamant, 120_000_000, false, nil, nil),     // 파이리 라인의 최종형
        (133, [133], .rare, .calm, 130_000_000, false, nil, nil),          // 임계 초과 → 진화 배지
        (94, [92, 93, 94], .epic, .quiet, 300_000_000, false, nil, nil),
        (143, [143], .rare, .relaxed, 60_000_000, false, nil, nil),
        (215, [215], .rare, .sassy, 25_000_000, false, .hisui, nil),       // 히스이 포푸니
        (448, [447, 448], .epic, .serious, 150_000_000, false, nil, nil),
        (9, [7, 8, 9], .epic, .bold, 200_000_000, false, nil, nil),
        (194, [194], .common, .docile, 8_000_000, false, .paldea, nil),    // 팔데아 우파
        (131, [131], .rare, .gentle, 45_000_000, false, nil, nil),
        (212, [123, 212], .epic, .impish, 90_000_000, false, nil, nil),
        (282, [280, 281, 282], .epic, .mild, 250_000_000, false, nil, nil),
        (384, [384], .legendary, .lonely, 500_000_000, false, nil, nil),
        (150, [150], .legendary, .bashful, 380_000_000, false, nil, nil),
        // 태어날 때 정해지는 겉모습 — 배지가 붙는 개체들. 무늬는 비비용이 되어야 보이므로
        // 이미 진화한 개체를 넣는다(분이벌레로 두면 그림이 평소와 같아 설명이 안 된다).
        (666, [664, 665, 666], .rare, .gentle, 70_000_000, false, nil, "polar"),   // 설국의 모양
        (201, [201], .common, .quirky, 6_000_000, false, nil, "q"),                // 안농 Q
        (671, [669, 670, 671], .rare, .calm, 110_000_000, false, nil, "blue"),     // 파란 꽃
        (849, [848, 849], .rare, .calm, 95_000_000, false, nil, nil),              // 로우한 모습(성격)
    ]

    /// 부화 슬롯이 몇 칸인가. 알보다 하나 많게 둬서 빈 슬롯(점선 칸)도 함께 보이게 한다.
    static let slots = 5

    /// 지금 파트너와 며칠째인가. `setPartner` 는 부른 시각을 그대로 동행 시작점으로 잡으므로,
    /// 이만큼 시계를 되감고 지정하지 않으면 홈 카드가 "함께한 시간 0분"으로 찍힌다.
    static let partnerSinceDaysAgo = 46.0

    /// 파트너와 **누적으로** 함께한 날. 리본은 이 시간으로만 정해지고 저장되지 않으므로
    /// (`Ribbon.earned(partnerSeconds:)`), 최고 단계(반려 = 90일)를 보여주려면 시간을 그만큼 준다.
    /// 최고 단계여야 네 날개 배지와 가장 빠른 사탕 생산(20M당 1개)이 한 화면에 같이 나온다.
    ///
    /// 나눠 담는 방식은 앱이 세는 방식 그대로다 — 지금 구간은 `partnerSince`(위 상수)가 세고,
    /// 그 이전에 파트너로 지냈던 몫은 `partnerSeconds` 에 누적돼 있다(`closePartnerStint`).
    /// 그래서 차액만 `partnerSeconds` 로 심는다.
    static let partnerTotalDays = 97.5
    static var partnerPriorSeconds: Int {
        Int((partnerTotalDays - partnerSinceDaysAgo) * 86_400)
    }

    /// 부화 중인 알 — 카운트다운이 슬롯마다 **다른 단위로** 읽히도록 남은 시간을 흩어 놓는다.
    /// (`EggSlotsView.countdownText` 는 큰 단위 두 개만 쓴다: "부화!" / "1분 30초" / "47분 25초" /
    /// "22시간 47분".) 첫 줄은 이미 부화 시각을 지나 "부화!" 로 뜬다 — 다 된 알이 어떻게 보이는지가
    /// 이 화면의 핵심이라 반드시 한 칸은 익은 상태로 둔다. 등급도 넷 다 달라 아래 라벨이 겹치지 않는다.
    static let eggs: [(grade: Grade, speciesID: Int, startedMinutesAgo: Double)] = [
        (.common, 172, 35),                  // 30분짜리를 35분 전에 → 부화 완료
        (.rare, 133, 118.5),                 // 2시간짜리 → 1분 30초 남음
        (.epic, 448, 360 - 47 - 25.0 / 60),  // 6시간짜리 → 47분 25초 남음
        (.legendary, 384, 73),               // 24시간짜리 → 22시간 47분 남음
    ]

    /// GIF(홈)용 알 — **하나도 익지 않은 상태**로 둔다. 익은 알("부화!")은 `EggSlotsView` 의 1초 틱이
    /// 그 자리에서 부화시켜(`settleRipeEggs`) 루프 도중 슬롯이 사라진다 — 앱의 실제 동작이라 GIF 에
    /// 담을 수가 없다. 대신 앞의 둘을 분·초 단위에 두어 **초가 실제로 줄어드는 것**이 보이게 한다.
    /// (정적 `screenshot-eggs*.png` 는 시각이 고정이라 익은 알을 그대로 보여준다 — `eggs` 참고.)
    static let liveEggs: [(grade: Grade, speciesID: Int, startedMinutesAgo: Double)] = [
        (.common, 172, 27),        // 30분짜리 → 3분 남음(초가 매 프레임 줄어든다)
        (.rare, 133, 105),         // 2시간짜리 → 15분 남음(초까지 표시)
        (.epic, 448, 300),         // 6시간짜리 → 1시간 0분 남음
        (.legendary, 384, 73),     // 24시간짜리 → 22시간 47분 남음
    ]

    // MARK: 사용량 — 팝오버 홈이 보여주는 숫자

    /// 오늘/주/월 사용량. 서비스를 둘 넣어 프로바이더 탭 줄까지 함께 보이게 한다.
    /// (합계 = 16.6M · $27.27 → 메뉴바 숫자도 이 값에서 나온다.)
    static let usage: [(id: String, name: String, input: Int, output: Int, cacheWrite: Int,
                        cacheRead: Int, cost: Double, week: Int, weekCost: Double,
                        month: Int, monthCost: Double)] = [
        ("claude_code", "Claude Code", 184_000, 96_000, 1_240_000, 12_900_000, 23.41,
         68_300_000, 108.72, 246_100_000, 391.55),
        ("codex", "Codex", 42_000, 31_000, 0, 2_100_000, 3.86,
         9_800_000, 17.40, 34_500_000, 60.24),
    ]

    /// Claude 공식 한도(5시간·주간·주간 Opus). 리셋 카운트다운은 상대 표시라 **현재 시각 기준**으로
    /// 만든다 — 고정 시각을 쓰면 README 에 "3개월 전 리셋"이 찍힌다.
    /// 5h 62.4% + 아래 `activeBlock` 의 분당 소모량이 만나 소진 예측 줄까지 그려진다.
    static let fiveHourUtilization = 62.4
    static let fiveHourResetsIn: TimeInterval = 125 * 60
    static let sevenDayUtilization = 41.8
    static let sevenDayOpusUtilization = 18.3
    static let sevenDayResetsIn: TimeInterval = 3.2 * 86_400
    /// 현재 5시간 블록 — "현재 블록" 줄과 소진 예측(분당 소모량)의 입력.
    static let blockTokens = 3_120_000
    static let blockTokensPerMinute = 21_500.0

    /// 진화 라인 — 앱에서는 PokéAPI 가 주지만 스크린샷은 네트워크를 타지 않으므로 필요한 것만 적어 둔다.
    private static let names: [Int: [Int: [String: String]]] = [
        25: [25: ["ko": "피카츄", "en": "Pikachu", "ja": "ピカチュウ"],
             26: ["ko": "라이츄", "en": "Raichu", "ja": "ライチュウ"]],
        133: [133: ["ko": "이브이", "en": "Eevee", "ja": "イーブイ"],
              134: ["ko": "샤미드", "en": "Vaporeon", "ja": "シャワーズ"],
              135: ["ko": "쥬피썬더", "en": "Jolteon", "ja": "サンダース"],
              136: ["ko": "부스터", "en": "Flareon", "ja": "ブースター"]],
        4: [4: ["ko": "파이리", "en": "Charmander", "ja": "ヒトカゲ"],
            5: ["ko": "리자드", "en": "Charmeleon", "ja": "リザード"],
            6: ["ko": "리자몽", "en": "Charizard", "ja": "リザードン"]],
        700: [700: ["ko": "님피아", "en": "Sylveon", "ja": "ニンフィア"]],
        201: [201: ["ko": "안농", "en": "Unown", "ja": "アンノーン"]],
        664: [664: ["ko": "분이벌레", "en": "Scatterbug", "ja": "コフキムシ"],
              665: ["ko": "분떠도리", "en": "Spewpa", "ja": "コフーライ"],
              666: ["ko": "비비용", "en": "Vivillon", "ja": "ビビヨン"]],
        669: [669: ["ko": "플라베베", "en": "Flabébé", "ja": "フラベベ"],
              670: ["ko": "플라엣테", "en": "Floette", "ja": "フラエッテ"],
              671: ["ko": "플라제스", "en": "Florges", "ja": "フラージェス"]],
        848: [848: ["ko": "일레즌", "en": "Toxel", "ja": "エレズン"],
              849: [ "ko": "스트린더", "en": "Toxtricity", "ja": "ストリンダー"]],
    ]

    private static let trees: [Int: EvoNode] = [
        25: EvoNode(speciesID: 25, children: [EvoNode(speciesID: 26, children: [])]),
        133: EvoNode(speciesID: 133, children: [EvoNode(speciesID: 134, children: []),
                                                EvoNode(speciesID: 135, children: []),
                                                EvoNode(speciesID: 136, children: [])]),
        4: EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5,
                                                    children: [EvoNode(speciesID: 6, children: [])])]),
        // 이로치 개체. 진화 갈래는 없지만 라인이 있어야 이름이 번호 대신 종명으로 찍힌다.
        700: EvoNode(speciesID: 700, children: []),
        // 태어날 때 겉모습이 갈리는 라인들 — 이름이 번호로 안 떨어지게 라인을 넣는다.
        201: EvoNode(speciesID: 201, children: []),
        664: EvoNode(speciesID: 664, children: [EvoNode(speciesID: 665,
                                                        children: [EvoNode(speciesID: 666, children: [])])]),
        669: EvoNode(speciesID: 669, children: [EvoNode(speciesID: 670,
                                                        children: [EvoNode(speciesID: 671, children: [])])]),
        848: EvoNode(speciesID: 848, children: [EvoNode(speciesID: 849, children: [])]),
    ]

    static func line(baseID: Int) -> EvoLine? {
        guard let tree = trees[baseID] else { return nil }
        return EvoLine(baseID: baseID, tree: tree, rarity: .common, names: names[baseID] ?? [:])
    }

    static var lines: [Int: EvoLine] {
        trees.keys.reduce(into: [:]) { $0[$1] = line(baseID: $1) }
    }

    // MARK: GIF 규격

    /// GIF 한 장의 규격. 재생 길이 = `frames × delay`, 용량은 (픽셀 넓이 × 프레임 수)에 비례한다 —
    /// ImageIO 는 프레임 간 델타 최적화를 하지 않으므로 프레임 수를 아끼는 게 곧 용량이다.
    struct Motion {
        var frames: Int
        var delay: TimeInterval
    }

    /// 이로치 배너에 쓰는 종 — 일반과 이로치 **둘 다** 움직이는 스프라이트가 있어야 한 쌍이 같이 돈다.
    /// (플로팅 펫·메뉴바는 파트너를 그대로 쓴다. 파트너는 `roster` 첫 줄이 정한다.)
    static let shinyBannerSpecies = 25   // 피카츄

    /// 홈(히어로). 18 × 0.1s = 1.8s — 파트너 스프라이트 한 바퀴(리자드 1.77s)에 맞춰 이음매를 줄이고,
    /// 그 사이 알 카운트다운이 1초 틱을 두 번 지나간다.
    static let homeMotion = Motion(frames: 18, delay: 0.1)
    /// 플로팅 펫. 펫은 fps 캡이 없어(`FloatingPetView.frameFloor == 0`) 원본 속도 그대로 돈다.
    static let petMotion = Motion(frames: 20, delay: 0.09)
    /// 이로치 배너. 16 × 0.0825s ≈ 1.32s = 피카츄 스프라이트 한 바퀴(이음매 없음).
    static let shinyMotion = Motion(frames: 16, delay: 0.0825)
    /// 메뉴바. 앱은 상태아이템 GIF 를 0.4s(≈2.5fps)로 캡해 배터리를 통제한다(`AppDelegate`) —
    /// 그 리듬 그대로 12프레임(4.8초)만 잘라 담는다. 실제 한 바퀴는 59프레임 ≈ 23.6초라 README 에
    /// 통째로 넣을 수 없다.
    static let menuBarMotion = Motion(frames: 12, delay: 0.4)

    // MARK: 이로치 반짝임

    /// 이 GIF 가 담을 개체 — `roster` 의 이로치. 반짝임은 이로치에게만 난다.
    static let sparkleSpecies = 700

    /// 길이는 연출 자신이 정한다(`ShinySparkles.duration`). 뒤에 여유를 붙여 **다 사그라든
    /// 뒤**까지 담는 게 중요하다 — 한 번만 반짝인다는 게 이 그림의 요점이라, 꺼지는 장면이
    /// 빠지면 계속 반짝이는 연출처럼 읽힌다.
    static var sparkleMotion: Motion {
        let delay = 0.06, tail = 0.3
        return Motion(frames: Int(((ShinySparkles.duration + tail) / delay).rounded()), delay: delay)
    }

    // MARK: 뽑기 연출

    /// 연출 GIF 가 담을 등급. **레전더리여야 한다** — 이 그림의 요점이 "등급이 오를수록 한 단계 더
    /// 올라간다"이고, 네 단계(흰색 → 하늘색 → 보라색 → 주황색)를 전부 지나는 등급은 이것뿐이다.
    static let revealGrade = Grade.legendary
    /// 이로치까지 걸린 판 — 마지막 줄이 "✨ There's a shiny inside!" 로 끝나 결과가 확실히 읽힌다.
    static let revealShiny = true

    /// 연출 GIF 의 길이는 **연출 자신이 정한다** — 단계 수도 단계별 체류 시간도 `EggReveal` 에
    /// 있으므로, 프레임 수를 손으로 적으면 밸런스를 고칠 때 GIF 가 중간에서 잘린다.
    /// 꼬리(`tail`)는 마지막 단계가 끝난 뒤 등급 라벨이 화면에 남는 시간이다.
    static var revealMotion: Motion {
        let stages = EggReveal.stages(for: revealGrade)
        let sequence = stages.indices.reduce(0.0) {
            $0 + EggReveal.duration(stageIndex: $1, of: stages.count)
        }
        let delay = 0.1, tail = 0.45
        return Motion(frames: Int(((sequence + tail) / delay).rounded()), delay: delay)
    }
}

@MainActor
final class ScreenshotGeneratorTests: XCTestCase {
    // MARK: 시드

    /// 시드된 스토어 + 파트너/상세에 쓸 개체 id. 실제 세이브는 절대 열지 않는다(임시 파일).
    private struct Fixture {
        let player: PlayerStore
        let usage: UsageStore
        let updater: UpdateChecker
        /// 상세 화면에 띄울 개체(임계를 넘긴 피카츄).
        let detailID: UUID
        /// 파트너 — 리본 상세 화면이 쓴다(최고 단계 리본을 단 개체).
        let partnerID: UUID
        /// 이로치 — 반짝임 GIF 가 쓴다.
        let shinyID: UUID
        /// 태어날 때 정해진 겉모습을 가진 개체 — 그 배지를 보여주는 스크린샷이 쓴다.
        let birthFormID: UUID
    }

    /// - Parameters:
    ///   - base: 시드 기준 시각. 정적 PNG 는 고정 시각(`ScreenshotFixture.now`)을 써 매 실행 같은
    ///     숫자를 찍고, GIF 는 **현재 시각**을 써서 알 카운트다운이 실제로 흘러가게 한다.
    ///   - live: 켜면 시드가 끝난 뒤 스토어의 시계가 실시각을 따라간다(파트너 동행 시간·알 정산).
    ///   - eggs: 부화 슬롯에 넣을 알. GIF 는 익은 알이 없는 `liveEggs` 를 쓴다(그 이유는 거기 적어 뒀다).
    private func makeFixture(base: Date = ScreenshotFixture.now, live: Bool = false,
                             eggs: [(grade: Grade, speciesID: Int,
                                     startedMinutesAgo: Double)] = ScreenshotFixture.eggs) -> Fixture {
        var clock = base
        var liveClock = false
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenshot-\(UUID().uuidString).json")
        let player = PlayerStore(fileURL: url, rng: SeededRNG(seed: 7),
                                 now: { liveClock ? Date() : clock },
                                 defaults: UserDefaults(suiteName: "ptb-shot-\(UUID().uuidString)")!)

        // 스타터는 실제 경로로 고른다 — 이걸 지나야 팝오버가 스타터 픽커 대신 본 화면을 그린다.
        clock = base.addingTimeInterval(-90 * 86_400)
        player.chooseStarter(speciesID: 4, grade: .epic)
        clock = base

        var detailID: UUID?
        var partnerID: UUID?
        var shinyID: UUID?
        var birthFormID: UUID?
        for (index, entry) in ScreenshotFixture.roster.enumerated() {
            var individual = Individual(baseID: entry.path.first ?? entry.species,
                                        speciesID: entry.species, pathIDs: entry.path,
                                        shiny: entry.shiny, nature: entry.nature, exp: entry.exp,
                                        obtainedAt: base.addingTimeInterval(-Double(index) * 3600),
                                        grade: entry.grade)
            individual.region = entry.region
            individual.birthForm = entry.birthForm
            // 함께 쓴 토큰 — 오래 데리고 다닌 개체일수록 크게. 0 만 늘어서면 이 칸이 무슨 뜻인지 안 보인다.
            individual.partnerTokens = entry.exp * 3 + index * 17_000_000
            // 파트너만 예전 동행분을 안고 시작한다 — 지금 구간(46일)만으로는 최고 리본에 못 닿는다.
            if index == 0 { individual.partnerSeconds = ScreenshotFixture.partnerPriorSeconds }
            player.addForTesting(individual)
            if index == 0 { partnerID = individual.id }
            if index == 1 { detailID = individual.id }
            if entry.shiny { shinyID = individual.id }
            // 비비용 — 무늬 배지가 가장 잘 읽히는 개체(이름이 짧고 그림이 크다).
            if entry.species == 666 { birthFormID = individual.id }
        }
        if let partnerID {
            clock = base.addingTimeInterval(-ScreenshotFixture.partnerSinceDaysAgo * 86_400)
            player.setPartner(partnerID)   // 동행 시작점을 되감아 지정한다(위 상수 참고)
            clock = base
            // 리본은 시간에서 파생될 뿐 저장되지 않는다 — 밸런스(`Ribbon.requiredPartnerSeconds`)가
            // 바뀌면 리본 스크린샷이 조용히 낮은 단계로 찍힌다. 여기서 먼저 멈춘다.
            XCTAssertEqual(player.state.box.first { $0.id == partnerID }?.ribbon(at: base), .lifelong,
                           "파트너가 최고 단계 리본을 안 달았다 — 동행 시간 픽스처가 밸런스를 못 따라간다")
        }

        // 도감은 "꾸준히 모은 중" 정도로 — 실루엣과 잡은 종이 섞여 보여야 도감 화면이 설명된다.
        for id in 1...40 where id % 3 != 0 { player.registerInDex(id) }
        for id in stride(from: 41, through: 300, by: 5) { player.registerInDex(id) }

        // 지갑·슬롯 → 아이템 구매 → 알 뽑기 순. 전부 실제 구매 경로를 지나 값이 어긋나지 않게 한다.
        // 지갑은 마지막 품목(가장 비싼 것)까지 살 수 있게 남긴다 — 전부 회색인 상점은 상점처럼 안 보인다.
        player.seedForTesting(wallet: 15_000_000_000, slots: ScreenshotFixture.slots, eggs: 0, at: base)
        // 구매 결과를 확인한다 — 가격이 오르면 조용히 실패해 재고 없는 상점이 찍힌다.
        for item in [ShopItem.expCandy, .expCandy, .expCandy, .shinyCandy, .megaStone, .dynamaxMushroom] {
            XCTAssertTrue(player.buy(item), "\(item) 를 못 샀다 — 시드 지갑이 가격을 못 따라간다")
        }

        // 파트너가 모아 온 것 — 가방 화면이 빈 상태로 찍히면 그 화면이 무엇인지 설명이 안 된다.
        // 진화 도구와 폼 도구를 섞어 둔다: 두 칸이 다 차 있어야 분류가 보인다.
        for item in [EvolutionItem.fireStone, .waterStone, .thunderStone, .linkingCord, .metalCoat] {
            player.grantForTesting(item)
        }
        for item in [FormItem.griseousCore, .costumeTrunk, .plateFire] {
            player.grantForTesting(item)
        }

        // 알은 실제 뽑기 경로로 넣는다 — 시작 시각만 시계를 되감아 각자 다르게 잡는다.
        for egg in eggs {
            clock = base.addingTimeInterval(-egg.startedMinutesAgo * 60)
            XCTAssertNotNil(player.startEgg(grade: egg.grade, speciesID: egg.speciesID, shiny: false),
                            "알을 못 넣었다 — 슬롯이나 지갑이 모자란다")
        }
        clock = base
        liveClock = live   // 시드가 끝난 뒤에만 실시각으로 전환한다(되감기가 필요한 구간을 지나서)

        let usage = UsageStore(providers: [], autoRefresh: false,
                               defaults: UserDefaults(suiteName: "ptb-shot-usage-\(UUID().uuidString)")!)
        return Fixture(player: player, usage: usage,
                       updater: UpdateChecker(currentVersion: AppEnv.appVersion ?? "0"),
                       detailID: detailID!, partnerID: partnerID!, shinyID: shinyID!,
                       birthFormID: birthFormID!)
    }

    /// 홈 탭이 보여줄 사용량을 채운 스토어. `snapshots`·`limits`·`lastUpdated` 는 전부
    /// `private(set)` 이라 밖에서 못 꽂는다 — 스텁 프로바이더를 넣고 실제 `refresh()` 를 한 번
    /// 태워 앱과 같은 경로로 채운다(네트워크는 스텁이 전부 막는다).
    private func makeUsageStore() async throws -> UsageStore {
        let iso = ISO8601DateFormatter()
        let now = Date()
        let todayKey = LocalUsageReader.todayKey()
        let providers: [any UsageProvider] = ScreenshotFixture.usage.map { entry in
            var enrichment = ProviderEnrichment()
            enrichment.weekTotal = PeriodUsage(period: "week", totalTokens: entry.week,
                                               totalCost: entry.weekCost)
            enrichment.monthTotal = PeriodUsage(period: "month", totalTokens: entry.month,
                                                totalCost: entry.monthCost)
            enrichment.periodsOK = true
            if entry.id == "claude_code" {
                // "현재 블록" 줄 + 5시간 소진 예측의 입력. 둘 다 Claude 고유 기능이다(확장 규약).
                enrichment.activeBlock = BlockUsage(
                    id: "shot", startTime: iso.string(from: now.addingTimeInterval(-175 * 60)),
                    endTime: iso.string(from: now.addingTimeInterval(ScreenshotFixture.fiveHourResetsIn)),
                    isActive: true, totalTokens: ScreenshotFixture.blockTokens, costUSD: 12.40,
                    tokensPerMinute: ScreenshotFixture.blockTokensPerMinute)
                enrichment.blocksOK = true
            }
            let total = entry.input + entry.output + entry.cacheWrite + entry.cacheRead
            let daily = DailyUsage(date: todayKey, inputTokens: entry.input, outputTokens: entry.output,
                                   cacheCreationTokens: entry.cacheWrite, cacheReadTokens: entry.cacheRead,
                                   totalTokens: total, totalCost: entry.cost)
            return StubUsageProvider(id: entry.id, displayName: entry.name,
                                     daily: daily, enrichment: enrichment)
        }
        // 한도는 앱이 받는 것과 같은 JSON 을 태워 디코드한다 — 필드 이름(`five_hour` 등)이 어긋나면
        // 여기서 바로 드러난다.
        let json = """
        {"five_hour":{"utilization":\(ScreenshotFixture.fiveHourUtilization),
          "resets_at":"\(iso.string(from: now.addingTimeInterval(ScreenshotFixture.fiveHourResetsIn)))"},
         "seven_day":{"utilization":\(ScreenshotFixture.sevenDayUtilization),
          "resets_at":"\(iso.string(from: now.addingTimeInterval(ScreenshotFixture.sevenDayResetsIn)))"},
         "seven_day_opus":{"utilization":\(ScreenshotFixture.sevenDayOpusUtilization),
          "resets_at":"\(iso.string(from: now.addingTimeInterval(ScreenshotFixture.sevenDayResetsIn)))"}}
        """
        var limits = try JSONDecoder().decode(LimitStatus.self, from: Data(json.utf8))
        // 구독 정보는 응답이 아니라 자격증명에서 주입된다(`OAuthLimitsProvider`) — 여기서도 그렇게 넣는다.
        limits.subscriptionType = "max"
        limits.rateLimitTier = "default_claude_max_20x"

        let store = UsageStore(providers: providers,
                               claudeLimitsProvider: StubClaudeLimits(status: limits),
                               codexLimitsProvider: StubCodexLimits(),
                               statusProvider: StubStatusProvider(),
                               autoRefresh: false,
                               defaults: UserDefaults(suiteName: "ptb-shot-usage-\(UUID().uuidString)")!)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertGreaterThan(store.todayTotalTokens, 0, "사용량 시드가 안 들어갔다")
        XCTAssertNotNil(store.limits?.fiveHour?.utilization, "공식 한도 시드가 안 들어갔다")
        XCTAssertNotNil(store.fiveHourForecast, "소진 예측 줄이 안 나온다 — 블록/한도 시드가 어긋났다")
        return store
    }

    // MARK: 렌더

    /// 팝오버 탭 화면 한 장. 앱에서 탭 뷰가 받는 폭·여백(`PopoverMetrics`)을 그대로 씌운다.
    private func tabChrome<V: View>(_ view: V) -> some View {
        view
            .padding(PopoverMetrics.padding)
            .frame(width: PopoverMetrics.width)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 뷰를 다크 모드로 오프스크린 렌더해 2배 스케일 PNG 바이트를 만든다.
    /// (`bitmapImageRepForCachingDisplay` 는 백킹 스케일을 따라 2x 픽셀 버퍼를 준다.)
    ///
    /// - Parameter fullScroll: 세로 스크롤 영역을 끝까지 훑어 한 장으로 잇는다. 팝오버는 세로가
    ///   좁아(상점 320pt·설정 460pt) 화면이 한 번에 다 안 들어가는데 README 는 전체를 보여줘야 한다.
    ///   스크롤해서 찍은 조각도 전부 같은 실제 뷰다. 목록이 무한히 긴 화면(도감 1025칸)에는 쓰지 않는다.
    private func png<V: View>(_ view: V, fullScroll: Bool = false) throws -> Data {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()

        let rep = try fullScroll ? scrolledSnapshot(host) : snapshot(host)
        XCTAssertEqual(CGFloat(rep.pixelsWide) / host.bounds.width, Self.scale,
                       "2배 스케일이 아니다 — 레티나가 아닌 디스플레이에서 돌렸다")
        // 기존 에셋과 같이 픽셀=포인트(72dpi)로 기록한다 — 뷰어가 반쪽 크기로 그리지 않게.
        rep.size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]), "PNG 인코딩 실패")
    }

    private static let scale: CGFloat = 2

    /// 지금 보이는 그대로 한 장.
    private func snapshot(_ host: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds),
                                "비트맵 버퍼를 못 만들었다")
        // 스크롤 뒤에는 바뀐 영역만 다시 그려져 나머지가 빈 채로 남는다 — 매번 전체를 무효화한다.
        host.setNeedsDisplay(host.bounds)
        host.displayIfNeeded()
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private func firstScrollView(_ view: NSView) -> NSScrollView? {
        (view as? NSScrollView) ?? view.subviews.lazy.compactMap(firstScrollView).first
    }

    /// 스크롤 영역을 끝까지 찍어 이어 붙인 한 장. 고정된 머리말·꼬리말은 한 번씩만 들어간다.
    private func scrolledSnapshot(_ host: NSView) throws -> NSBitmapImageRep {
        guard let scroll = firstScrollView(host) else { return try snapshot(host) }
        let clip = scroll.convert(scroll.contentView.frame, to: host)
        let bandHeight = clip.height
        let hostHeight = host.bounds.height

        func capture(at offset: CGFloat) throws -> NSBitmapImageRep {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
            host.layoutSubtreeIfNeeded()
            return try snapshot(host)
        }

        // SwiftUI 스크롤은 콘텐츠 높이를 AppKit 쪽에 알려주지 않는다(documentView 가 0×0). 대신
        // 콘텐츠를 완전히 지나친 위치를 "빈 밴드" 기준으로 삼아, 그와 같아지는 지점까지 훑는다.
        let blank = try capture(at: 200_000)
        var lastFilled = 0
        var band = 1
        while band < 40 {
            let shot = try capture(at: CGFloat(band) * bandHeight)
            if bandRows(shot, differFrom: blank, clip: clip).isEmpty { break }
            lastFilled = band
            band += 1
        }
        XCTAssertLessThan(band, 40, "스크롤이 끝나지 않는다 — fullScroll 을 쓸 화면이 아니다")

        // 마지막으로 내용이 있던 밴드에서 실제 바닥을 찾아 빈 여백을 잘라낸다.
        let lastShot = try capture(at: CGFloat(lastFilled) * bandHeight)
        let filledRows = bandRows(lastShot, differFrom: blank, clip: clip)
        let bottomInBand = filledRows.last.map { CGFloat($0 + 1) / Self.scale } ?? bandHeight
        let contentHeight = CGFloat(lastFilled) * bandHeight + bottomInBand
        let maxOffset = max(0, contentHeight - bandHeight)

        var offsets = stride(from: CGFloat(0), to: maxOffset, by: bandHeight).map { $0 }
        offsets.append(maxOffset)

        let canvasHeight = clip.minY + contentHeight + (hostHeight - clip.maxY)
        let canvas = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(host.bounds.width * Self.scale),
            pixelsHigh: Int((canvasHeight * Self.scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), "캔버스 생성 실패")
        canvas.size = CGSize(width: host.bounds.width, height: canvasHeight)

        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas), "컨텍스트 생성 실패")
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        /// 원본(호스트 좌표, 위에서부터)의 한 구간을 캔버스의 지정 위치(역시 위에서부터)에 그린다.
        func draw(_ rep: NSBitmapImageRep, srcTop: CGFloat, height: CGFloat, dstTop: CGFloat) {
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(rep)
            image.draw(at: NSPoint(x: 0, y: canvasHeight - dstTop - height),
                       from: NSRect(x: 0, y: hostHeight - srcTop - height,
                                    width: host.bounds.width, height: height),
                       operation: .copy, fraction: 1)
        }

        let first = try capture(at: 0)
        draw(first, srcTop: 0, height: clip.minY, dstTop: 0)                       // 머리말
        for offset in offsets {
            let shot = try capture(at: offset)
            draw(shot, srcTop: clip.minY, height: bandHeight, dstTop: clip.minY + offset)
        }
        let last = try capture(at: maxOffset)
        draw(last, srcTop: clip.maxY, height: hostHeight - clip.maxY,
             dstTop: clip.minY + contentHeight)                                     // 꼬리말

        NSGraphicsContext.restoreGraphicsState()
        return canvas
    }

    /// 스크롤 밴드 안에서 기준(빈 화면)과 다른 픽셀 줄들의 인덱스(밴드 위에서부터, 픽셀 단위).
    private func bandRows(_ shot: NSBitmapImageRep, differFrom blank: NSBitmapImageRep,
                          clip: NSRect) -> [Int] {
        guard let a = shot.bitmapData, let b = blank.bitmapData,
              shot.bytesPerRow == blank.bytesPerRow else { return [] }
        let bytesPerRow = shot.bytesPerRow
        let top = Int(clip.minY * Self.scale), height = Int(clip.height * Self.scale)
        return (0..<height).filter { row in
            let offset = (top + row) * bytesPerRow
            return memcmp(a + offset, b + offset, bytesPerRow) != 0
        }
    }

    // MARK: 애니메이션

    /// 비동기 작업을 런루프를 돌리며 기다린다.
    ///
    /// **이 테스트가 `async` 면 안 되는 이유가 여기 있다.** `async` 테스트 본문은 그 자체가 메인 큐
    /// 작업 항목 안에서 실행되고, 그 안에서 중첩 런루프를 돌려도 메인 큐를 다시 비울 수 없다 —
    /// 뷰의 `.task`(스프라이트 프레임 루프)와 `TimelineView` 틱이 영영 진행하지 않아 GIF 가 정지
    /// 화면 18장이 된다(실제로 겪음). 그래서 본문은 동기로 두고 비동기 조각만 여기서 기다린다.
    private func waitFor<T>(_ operation: @escaping @MainActor () async throws -> T) throws -> T {
        let box = AsyncResult<T>()
        Task { @MainActor in
            do { box.value = .success(try await operation()) } catch { box.value = .failure(error) }
        }
        let deadline = Date().addingTimeInterval(60)
        while box.value == nil, Date() < deadline { pump(0.01) }
        return try XCTUnwrap(box.value, "비동기 작업이 제한 시간 안에 안 끝났다").get()
    }

    /// 런루프를 실제 시간만큼 돌린다. 스프라이트 GIF 루프(`SpriteView` 의 `.task`)와 알 카운트다운
    /// (`TimelineView` 1초 틱)은 메인 런루프가 돌아야 진행한다 — 정적 PNG 경로는 런루프를 돌리지
    /// 않아서 이 애니메이션들이 첫 프레임에 멈춘 채로 찍힌다.
    private func pump(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
        }
    }

    /// 살아 있는 뷰를 일정 간격으로 샘플링해 프레임을 모은다.
    ///
    /// 프레임 사이에 하는 일은 "기다리기"뿐이다 — 프레임 인덱스를 손으로 돌리거나 전환을 합성하지
    /// 않는다. 그래서 담기는 움직임은 앱이 스스로 만드는 것(스프라이트 프레임·bob·카운트다운)뿐이다.
    ///
    /// - Parameter warmup: 첫 프레임 전에 돌려 둘 시간. 스프라이트 로드 → GIF 디코드 → 루프 시작까지
    ///   가는 시간이라 이게 짧으면 앞쪽 프레임이 정지 화면으로 찍힌다.
    /// - Parameter onReady: 워밍업이 끝나고 **첫 프레임을 찍기 직전**에 부른다. 한 번만 재생되고 끝나는
    ///   연출(뽑기 리빌)을 여기서 시작시키면 창 준비 시간이 연출을 갉아먹지 않는다 — 창을 띄우고
    ///   레이아웃하는 데 걸리는 시간은 실행마다 달라서(실측 0.16~0.56초), 뷰를 처음부터 얹어 두면
    ///   앞 단계가 그만큼 잘린 채로, 그것도 매번 다른 길이로 찍힌다. 반복 재생되는 GIF 는 필요 없다.
    private func liveFrames<V: View>(_ view: V, _ motion: ScreenshotFixture.Motion,
                                     warmup: TimeInterval,
                                     onReady: ((NSHostingView<V>) -> Void)? = nil) throws -> [NSBitmapImageRep] {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        // **화면 밖 창에 붙여야 한다.** `TimelineView`(알 카운트다운 1초 틱)는 창 없는 호스팅 뷰에서
        // 한 번도 돌지 않는다 — 실측: 창 없이 3.6초를 훑어도 전부 같은 그림, 창을 주면 정상 틱.
        // (`.task` 는 창 없이도 돈다. 그래서 스프라이트만 움직이고 카운트다운은 얼어붙은 GIF 가 나왔다.)
        // 좌표가 모든 화면 밖이라 사용자 눈에는 아무것도 뜨지 않는다.
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        pump(warmup)
        if let onReady {
            onReady(host)
            // SwiftUI 가 켜진 뷰를 실제로 얹는 데는 런루프 한 턴 + 레이아웃이 필요하다. 이걸
            // 빼먹으면 오버레이가 끝까지 안 붙어 프레임이 전부 같은 그림으로 나온다(실측).
            host.layoutSubtreeIfNeeded()
            pump(0.05)
            host.layoutSubtreeIfNeeded()
        }
        // **프레임은 벽시계 격자에 맞춰 찍는다.** 찍는 일 자체가 공짜가 아니라서(리빌 합성 화면은
        // 한 장에 ~0.06초), 프레임마다 `delay` 만큼 *더* 기다리면 실제 간격이 선언한 간격보다 길어진다
        // — GIF 는 선언한 간격으로 재생되므로 그만큼 빨라진 영상이 된다(실측: 0.1초로 적고 0.163초마다
        // 찍어 1.6배 빨랐다). 매 프레임의 목표 시각을 시작점에서 계산해 그 시각까지만 기다린다.
        var frames: [NSBitmapImageRep] = []
        let start = Date()
        for index in 0..<motion.frames {
            pump(start.addingTimeInterval(Double(index) * motion.delay).timeIntervalSinceNow)
            frames.append(try snapshot(host))
        }
        // 격자를 못 지켰다면(한 장 찍는 값이 간격보다 크다) 재생 속도가 실제와 어긋난 GIF 가 된다.
        let achieved = Date().timeIntervalSince(start) / Double(motion.frames)
        XCTAssertLessThan(achieved, motion.delay * 1.15,
                          "프레임 간격이 선언값(\(motion.delay)s)보다 길다 — 실제보다 빠르게 재생된다")
        let first = try XCTUnwrap(frames.first, "프레임이 하나도 없다")
        XCTAssertEqual(CGFloat(first.pixelsWide) / host.bounds.width, Self.scale,
                       "2배 스케일이 아니다 — 레티나가 아닌 디스플레이에서 돌렸다")
        XCTAssertGreaterThan(Set(frames.map { $0.representation(using: .png, properties: [:]) }).count, 1,
                             "모든 프레임이 같다 — 움직이지 않는 화면을 GIF 로 찍고 있다")
        return frames
    }

    /// 프레임들을 애니메이션 GIF 로 인코딩한다. ImageIO 는 SDK 내장이라 외부 의존성이 없다 —
    /// 대신 프레임 간 델타 최적화를 하지 않으므로 용량은 (픽셀 넓이 × 프레임 수)에 거의 비례한다.
    private func gif(_ frames: [NSBitmapImageRep], delay: TimeInterval) throws -> Data {
        let buffer = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(buffer, UTType.gif.identifier as CFString,
                                             frames.count, nil), "GIF 인코더 생성 실패")
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],   // 0 = 무한 반복
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ],
        ] as CFDictionary
        for frame in frames {
            CGImageDestinationAddImage(destination,
                                       try XCTUnwrap(frame.cgImage, "CGImage 변환 실패"),
                                       frameProperties)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination), "GIF 인코딩 실패")
        return buffer as Data
    }

    /// 메뉴바 한 프레임을 합성한다.
    ///
    /// **여기만 앱의 그리기 코드를 그대로 못 쓴다.** 상태아이템은 `NSStatusItem` 이라 화면에 붙은
    /// 채로만 존재하고(오프스크린 캡처는 백킹 스케일조차 들쭉날쭉하다), 합성 헬퍼
    /// (`AppDelegate.menuBarImage`/`applyMenuText`)는 `private` 이다. 그래서 앱이 쓰는 **재료**로
    /// 같은 그림을 다시 조립한다 — 스프라이트 프레임은 캐시된 Gen-V GIF 를 앱과 같은 `GIFDecoder`
    /// 로 푼 것, 숫자는 `UsageStore.menuLines`, 아이콘 칸 높이는 `NSStatusBar.system.thickness`,
    /// 스프라이트 맞춤은 `PixelScale.fittedRect`. **띠 배경과 좌우 여백만 표현용**이다(실제 메뉴바는
    /// 뒤 배경이 비쳐 보인다 — 그건 윈도우 서버가 그리는 것이라 어떤 오프스크린 렌더로도 못 담는다).
    private func menuBarFrame(sprite: NSImage, title: String) throws -> NSBitmapImageRep {
        let thickness = NSStatusBar.system.thickness     // 메뉴바 높이(22pt)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.white,             // 다크 메뉴바의 라벨 색
        ]
        let text = title as NSString
        let textSize = text.size(withAttributes: attributes)
        let sidePad: CGFloat = 16
        let width = (sidePad * 2 + thickness + textSize.width).rounded(.up)
        let size = CGSize(width: width, height: thickness)

        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * Self.scale), pixelsHigh: Int(size.height * Self.scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), "메뉴바 캔버스 생성 실패")
        rep.size = size

        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep), "컨텍스트 생성 실패")
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        // 스프라이트는 22×22 고정 칸 안에서만 비율을 지켜 넣는다(앱과 같은 규칙 — 폭이 흔들리면 떨린다).
        context.imageInterpolation = .none
        let box = PixelScale.fittedRect(source: sprite.size,
                                        in: CGSize(width: thickness - 2, height: thickness - 2))
        sprite.draw(in: box.offsetBy(dx: sidePad + 1, dy: 1), from: .zero,
                    operation: .sourceOver, fraction: 1)
        text.draw(at: NSPoint(x: sidePad + thickness,
                              y: ((thickness - textSize.height) / 2).rounded()),
                  withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static let assetsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // PokeDexBarTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // 저장소 루트
        .appendingPathComponent("assets")

    private func write(_ data: Data, _ name: String) throws {
        let url = Self.assetsDir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        print("screenshot: \(name) (\(data.count / 1024) KB)")
    }

    // MARK: 화면들

    /// 언어별로 다시 그리는 화면(상점·설정)의 파일 접미 — `.en` 만 접미가 없다(README 기본).
    private static let languages: [(AppLanguage, String)] = [(.en, ""), (.ko, "-ko"), (.ja, "-ja")]

    private func setLanguage(_ language: AppLanguage, _ fixture: Fixture) {
        fixture.player.setLanguage(language)
        fixture.usage.localizationLanguage = language
    }

    func testGenerateScreenshots() throws {
        guard ProcessInfo.processInfo.environment["PTB_SCREENSHOTS"] == "1" else {
            throw XCTSkip("set PTB_SCREENSHOTS=1 to regenerate assets/ screenshots")
        }
        if let version = ProcessInfo.processInfo.environment["PTB_APP_VERSION"] {
            AppEnv.appVersionOverride = version
        }
        defer { AppEnv.appVersionOverride = nil }

        let fixture = makeFixture()
        setLanguage(.en, fixture)

        // 박스 — 보유 개체 그리드(진화 배지·이로치 테두리·지방 배지).
        try write(png(tabChrome(BoxTabView(store: fixture.player, lines: ScreenshotFixture.lines,
                                           onNeedLine: { _ in }, selection: .constant(nil)))),
                  "screenshot-box.png")

        // 개체 상세 — 진화·폼(거다이맥스)·사탕 버튼이 한 화면에 나오는 개체를 고른다.
        try write(png(tabChrome(BoxTabView(store: fixture.player, lines: ScreenshotFixture.lines,
                                           onNeedLine: { _ in },
                                           selection: .constant(fixture.detailID))),
                      fullScroll: true),
                  "screenshot-detail.png")

        // 리본 — 오래 함께한 파트너의 상세. 배지 그림 + 사탕 생산 속도("1 candy per 20M") +
        // 그 리본이 어디서 왔는지(함께한 시간)가 한 화면에 같이 나와야 기능이 설명된다.
        try write(png(tabChrome(BoxTabView(store: fixture.player, lines: ScreenshotFixture.lines,
                                           onNeedLine: { _ in },
                                           selection: .constant(fixture.partnerID))),
                      fullScroll: true),
                  "screenshot-ribbon.png")

        // 가방 — 파트너가 모아 온 것. 상점(사는 곳)과 갈라 둔 화면이라 따로 찍는다:
        // 도구 106종 중 살 수 있는 건 7종뿐이고 나머지는 여기서만 볼 수 있다.
        try write(png(tabChrome(BagTabView(store: fixture.player)), fullScroll: true),
                  "screenshot-bag.png")

        // 도감 — 번호순 그리드 + 못 잡은 종 실루엣.
        try write(png(tabChrome(NationalDexView(store: fixture.player))), "screenshot-collection.png")

        // 곁에 두면 바뀌는 폼 — 이 규칙은 한 화면에 안 담긴다(파트너로 뒀다 내려야 보인다).
        // 그래서 이로치 배너와 같은 방식으로, 앱이 쓰는 `SpriteView` 를 나란히 놓아 대비를 보인다.
        try write(png(partnerFormBanner(fixture)), "form-banner.png")

        // 부화 감면 — 같은 알이 얼마나 줄어드는지는 한 화면에 안 담긴다(감면 전후를 같이 봐야 한다).
        try write(png(hatchSpeedupBanner()), "hatch-speedup.png")

        // 태어날 때 정해지는 겉모습 — 이름 옆 배지가 그 개체가 어떤 무늬로 태어났는지 말한다.
        // 지방 배지와 같은 자리를 쓰므로, 이 그림 하나로 두 규칙이 같이 설명된다.
        try write(png(tabChrome(BoxTabView(store: fixture.player, lines: ScreenshotFixture.lines,
                                           onNeedLine: { _ in },
                                           selection: .constant(fixture.birthFormID))),
                      fullScroll: true),
                  "screenshot-birth-form.png")

        for (language, suffix) in Self.languages {
            setLanguage(language, fixture)

            // 부화 슬롯 — 홈 탭의 알 줄. 카운트다운·등급 라벨이 언어를 타므로 3개 언어로 찍는다.
            // `now` 는 픽스처 기준 시각으로 고정한다 — 실제 시각을 쓰면 돌릴 때마다 숫자가 달라진다.
            try write(png(tabChrome(EggSlotsView(store: fixture.player, now: ScreenshotFixture.now))),
                      "screenshot-eggs\(suffix).png")

            try write(png(tabChrome(ShopTabView(store: fixture.player, provider: StubProvider())),
                          fullScroll: true),
                      "screenshot-shop\(suffix).png")
            try write(png(SettingsView(onClose: { })
                .environment(fixture.usage).environment(fixture.player).environment(fixture.updater)
                .frame(width: PopoverMetrics.width)
                .background(Color(nsColor: .windowBackgroundColor)),
                          fullScroll: true),
                      "settings\(suffix).png")
        }

        try generateAnimations()
    }

    // MARK: 움직이는 그림들 (GIF)

    /// 애니메이션 네 장. 정적 PNG 와 픽스처는 같지만 기준 시각만 **현재 시각**으로 바꾼다 —
    /// 알 카운트다운이 실제로 흘러가야 GIF 에 담을 움직임이 생긴다.
    private func generateAnimations() throws {
        let fixture = makeFixture(base: Date(), live: true, eggs: ScreenshotFixture.liveEggs)
        fixture.player.setLanguage(.en)
        let usage = try waitFor { try await self.makeUsageStore() }
        usage.localizationLanguage = .en

        // 부화를 **가장 먼저** 찍는다. 앞선 캡처를 여러 번 돌린 뒤에는 이 연출의 `.task` 가
        // 깨어나지 못하고 얼어붙는 실행이 절반쯤 나온다 — 한 번 얼면 그 프로세스에서는 다시
        // 찍어도 계속 언다(재시도 8번이 전부 얼어붙는 것을 실측). 프로세스가 깨끗할 때 찍는다.
        try write(try hatchAnimation(fixture), "screenshot-hatch.gif")
        try write(try shinySparkleAnimation(fixture), "shiny-sparkle.gif")
        try write(try homeAnimation(fixture, usage: usage), "screenshot-home.gif")
        try write(try petAnimation(fixture, usage: usage), "floating-pet.gif")
        try write(try shinyAnimation(usage: usage), "shiny-banner.gif")
        try write(try revealAnimation(fixture), "screenshot-reveal.gif")
        try write(try menuBarAnimation(fixture, usage: usage), "menubar.gif")
    }

    /// 부화 감면 — 같은 알을 감면 전후로 나란히.
    ///
    /// 알 줄 스크린샷 하나로는 "빨라졌다"가 안 보인다. 비교가 있어야 2시간이 1시간이 된 것이
    /// 읽히고, 아래 줄의 안내 문구가 그 이유를 말한다.
    private func hatchSpeedupBanner() -> some View {
        let now = ScreenshotFixture.now
        func row(warmed: Bool) -> some View {
            let store = PlayerStore(fileURL: FileManager.default.temporaryDirectory
                                        .appendingPathComponent("warm-\(UUID().uuidString).json"),
                                    rng: SeededRNG(seed: 11), now: { now },
                                    defaults: UserDefaults(suiteName: "ptb-warm-\(UUID().uuidString)")!)
            store.setLanguage(.en)
            store.seedForTesting(wallet: 100_000_000_000, slots: 4, eggs: 0, at: now)
            for (grade, species) in [(Grade.rare, 133), (.legendary, 384)] {
                XCTAssertNotNil(store.startEgg(grade: grade, speciesID: species, shiny: false),
                                "알을 못 넣었다 — 슬롯이나 지갑이 모자란다")
            }
            var lines: [Int: EvoLine] = [:]
            if warmed {
                // 파이어로(불꽃몸). **알을 넣은 뒤에** 더해야 감면이 남은 시간에 걸리는 게 보인다.
                store.addForTesting(Individual(baseID: 661, speciesID: 663, pathIDs: [661, 662, 663],
                                               nature: .jolly, obtainedAt: now, grade: .rare))
                lines[661] = EvoLine(baseID: 661, tree: EvoNode(speciesID: 663, children: []),
                                     rarity: .rare, names: [663: ["ko": "파이어로", "en": "Talonflame",
                                                                  "ja": "ファイアロー"]])
            }
            return EggSlotsView(store: store, now: now, lines: lines)
        }
        let plain = row(warmed: false), warmed = row(warmed: true)
        return VStack(alignment: .leading, spacing: 16) {
            plain
            warmed
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .frame(width: PopoverMetrics.width, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 곁에 두면 바뀌는 폼 — 평소 모습과 바뀐 모습을 나란히.
    ///
    /// 앱에 이런 화면이 따로 있는 건 아니고, 앱이 쓰는 `SpriteView` 를 README 용으로 짝지어
    /// 놓은 배너다(이로치 배너와 같은 방식). 규칙 자체가 시간에 걸쳐 일어나는 일이라
    /// 한 화면으로는 안 담긴다.
    ///
    /// **정적 PNG 다.** 테라파고스는 Showdown 에 움직이는 스프라이트가 없어(실측) GIF 로 만들면
    /// 한쪽만 멈춘 그림이 된다.
    private func partnerFormBanner(_ fixture: Fixture) throws -> some View {
        // `png` 는 `.task` 를 안 돌린다 — 그림은 `SpriteView.init` 의 동기 디스크 캐시에서만 온다.
        // 그래서 먼저 받아 둔다(안 그러면 새 종이 빈칸으로 찍힌다).
        for (species, form) in [(964, nil), (964, "palafin-hero"),
                                (1024, nil), (1024, "terapagos-terastal")] as [(Int, String?)] {
            _ = try waitFor { await SpriteLoader.image(speciesID: species, form: form) }
        }
        func pair(_ species: Int, _ changed: String) -> some View {
            HStack(spacing: 20) {
                SpriteView(speciesID: species, size: 68)
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                SpriteView(speciesID: species, form: changed, size: 68)
            }
        }
        return VStack(spacing: 14) {
            pair(964, "palafin-hero")
            Divider().frame(width: 200)
            pair(1024, "terapagos-terastal")
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 히어로 — 팝오버 홈 탭 전체. 움직이는 것은 두 가지이고 둘 다 앱이 스스로 하는 일이다:
    /// 파트너 카드의 Gen-V 스프라이트 프레임 루프와, 부화 슬롯의 1초 카운트다운(`TimelineView`).
    private func homeAnimation(_ fixture: Fixture, usage: UsageStore) throws -> Data {
        let motion = ScreenshotFixture.homeMotion
        let view = PopoverView(player: fixture.player, provider: StubProvider())
            .environment(usage).environment(fixture.player)
            .environment(fixture.updater).environment(PopoverNavigation())
            // 리셋 카운트다운(`Text(_, style: .relative)`)만은 앱 언어가 아니라 **시스템 로캘**을
            // 따른다 — 한국어 맥에서 찍으면 영어 화면에 "2시간 4분"이 섞인다. README 기본이 영어이니
            // 영어권 사용자가 보는 화면과 같아지게 로캘을 고정한다.
            .environment(\.locale, Locale(identifier: "en_US"))
            .background(Color(nsColor: .windowBackgroundColor))
        return try gif(liveFrames(view, motion, warmup: 2.0), delay: motion.delay)
    }

    /// 플로팅 펫 — 패널(`NSPanel`)은 투명·보더리스라 화면에 실제로 보이는 건 이 콘텐츠 뷰뿐이다.
    /// 패널 자체는 오프스크린으로 못 찍으므로 데스크톱 자리에 은은한 배경만 깔고 뷰를 그대로 올린다
    /// (호버 콜아웃·우클릭 메뉴는 별도 패널/`NSMenu` 라 여기 담기지 않는다).
    private func petAnimation(_ fixture: Fixture, usage: UsageStore) throws -> Data {
        let motion = ScreenshotFixture.petMotion
        let size = CGFloat(usage.floatingPetSize)
        let view = FloatingPetView(animated: true)
            .environment(usage).environment(fixture.player)
            .frame(width: size + 16, height: size + 8)
            .padding(.horizontal, 46).padding(.top, 12).padding(.bottom, 18)
            .background(
                LinearGradient(colors: [Color(red: 0.16, green: 0.17, blue: 0.24),
                                        Color(red: 0.09, green: 0.10, blue: 0.14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
        return try gif(liveFrames(view, motion, warmup: 2.0), delay: motion.delay)
    }

    /// "이로치는 나온다" 줄 — 같은 종의 일반/이로치 스프라이트를 나란히. 앱에 이런 화면이 따로
    /// 있는 건 아니고, 앱이 쓰는 `SpriteView` 두 개를 README 용으로 나란히 놓은 배너다.
    private func shinyAnimation(usage: UsageStore) throws -> Data {
        let motion = ScreenshotFixture.shinyMotion
        let species = ScreenshotFixture.shinyBannerSpecies
        let view = HStack(spacing: 36) {
            SpriteView(speciesID: species, size: 72, animated: true,
                       antialias: usage.antialiasSprites)
            SpriteView(speciesID: species, size: 72, animated: true, shiny: true,
                       antialias: usage.antialiasSprites)
        }
        .padding(.horizontal, 25).padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        return try gif(liveFrames(view, motion, warmup: 2.0), delay: motion.delay)
    }

    /// 뽑기 연출 — 알을 뽑은 직후 상점 위에 덮이는 화면. 등급이 오를수록 단계가 하나씩 더 얹히는
    /// 게 이 기능의 전부라, 네 단계를 다 지나는 레전더리를 담는다.
    ///
    /// 앱은 `ShopTabView` 의 `.overlay` 로 이 뷰를 덮는다(같은 파일 `body` 참조). 그 `reveal` 상태는
    /// `private` 이고 네트워크 뽑기가 끝나야 채워지므로, 여기서는 **앱과 똑같은 겹침을 직접 만든다** —
    /// 뷰도 지오메트리도 앱이 쓰는 그대로라, 사용자가 보는 화면과 같은 그림이 나온다.
    ///
    /// **담기는 것과 안 담기는 것.** 단계별 색은 알의 글로우(`shadow(color:)`)와 마지막 등급 라벨로
    /// 담기지만, **날아가는 파티클은 담기지 않는다.** 파티클은 `burst` 가 참인 동안 `opacity(0)` 이고
    /// 눈에 보이는 건 그 사이를 잇는 SwiftUI 애니메이션의 중간값뿐인데, `cacheDisplay` 는 애니메이션
    /// *모델* 값(=최종값)을 그리므로 늘 투명한 상태로 찍힌다. 오프스크린 창을 화면 안으로 옮겨도,
    /// `CALayer.presentation()` 을 대신 렌더해도 결과는 같았다(둘 다 실측). 그래서 이 GIF 의 에스컬레이션은
    /// "파티클이 네 번 터진다"가 아니라 "알의 글로우가 네 색을 거친다"로 읽힌다 — 아래 검사도 그 기준이다.
    private func revealAnimation(_ fixture: Fixture) throws -> Data {
        let motion = ScreenshotFixture.revealMotion
        let provider = StubProvider()
        // 창이 다 준비된 뒤에 연출을 얹는다 — 앱에서도 뽑기가 끝난 순간 나타나는 오버레이라
        // 등장 시점이 곧 연출의 시작이다.
        let frames = try liveFrames(
            RevealComposite(store: fixture.player, provider: provider, armed: false),
            motion, warmup: 0.4,
            onReady: { host in
                host.rootView = RevealComposite(store: fixture.player, provider: provider, armed: true)
            })
        try assertEscalationIsVisible(in: frames)
        return try gif(frames, delay: motion.delay)
    }

    /// 부화 연출 — 금 간 알이 흔들리다 터지고 그 자리에서 포켓몬이 나온다. 뽑기 연출과 달리
    /// 등급 에스컬레이션이 없으므로, 대신 **알에서 포켓몬으로 바뀌었는지**를 확인한다.
    private func hatchAnimation(_ fixture: Fixture) throws -> Data {
        let individual = try XCTUnwrap(fixture.player.state.box.first { $0.grade == .legendary }
                                        ?? fixture.player.state.box.first)
        let delay = 0.1
        let motion = ScreenshotFixture.Motion(
            frames: Int(((RevealMotion.hatchShake + 1.1) / delay).rounded()), delay: delay)

        // **이 연출은 이 캡처 환경에서 가끔 얼어붙는다.** 오프스크린 창에서 `.task` 의
        // `Task.sleep` 이 깨지 못해 알이 흔들리다 멈춘 채로 남는다(실측: 6번째 프레임부터 값이
        // 완전히 고정 — 스프라이트 애니메이션까지 정지). 앱에서는 재현되지 않는다.
        //
        // 알아낸 것 둘: ① **한 번 얼면 그 프로세스에서는 계속 언다** — 여덟 번을 다시 찍어도
        // 전부 얼어붙었다. 그래서 재시도는 시간만 버린다. ② 이 연출을 애니메이션 중 **맨 처음**
        // 찍으면 빈도가 뚜렷하게 준다(실측 2/5 → 4/5 성공). 그래서 순서를 앞으로 옮겼다.
        //
        // 남은 실패는 조용히 넘기지 않고 **크게 터뜨린다** — 얼어붙은 프레임으로 GIF 를 만들면
        // 알만 있고 부화가 없는 그림이 릴리스에 실린다. 다시 돌리면 대개 통과한다.
        let frames = try liveFrames(
            HatchComposite(store: fixture.player, individual: individual, armed: false),
            motion, warmup: 0.4,
            onReady: { host in
                host.rootView = HatchComposite(store: fixture.player, individual: individual,
                                               armed: true)
            })
        guard eggBecomesAPokemon(in: frames) else {
            struct HatchCaptureFroze: Error {}
            XCTFail("부화 캡처가 얼어붙었다(이 환경의 알려진 문제) — 다시 실행하면 대개 통과한다")
            throw HatchCaptureFroze()   // 던져서 얼어붙은 프레임이 에셋에 안 쓰이게 한다
        }
        return try gif(frames, delay: motion.delay)
    }

    /// 이로치 반짝임 — 박스에서 이로치를 열면 초상 둘레에서 금색 별이 한 번 터지고 사라진다.
    /// 앱에서 이 연출이 나는 곳이 바로 이 화면이라, 합성 배너가 아니라 상세 화면 그대로 담는다.
    private func shinySparkleAnimation(_ fixture: Fixture) throws -> Data {
        let motion = ScreenshotFixture.sparkleMotion
        // **초상 스프라이트를 미리 받아 둔다.** 캐시에 GIF 가 없으면 `SpriteView` 는 다 받을
        // 때까지 자리를 비워 두므로(정적 → 움직이는 것으로 바뀌는 순간이 어색하다는 지적을
        // 받아 그렇게 고쳤다), 워밍업이 이 종을 안 지나면 반짝임만 있고 포켓몬이 없는 GIF 가 된다.
        _ = try waitFor {
            await SpriteLoader.image(speciesID: ScreenshotFixture.sparkleSpecies,
                                     animated: true, shiny: true)
        }
        let frames = try liveFrames(
            SparkleComposite(store: fixture.player, selection: nil),
            motion, warmup: 1.0,
            onReady: { host in
                host.rootView = SparkleComposite(store: fixture.player, selection: fixture.shinyID)
            })
        try assertSparkleIsOneShot(in: frames)
        return try gif(frames, delay: motion.delay)
    }

    /// 반짝임이 **한 번만** 났나. 이 GIF 가 존재하는 이유가 그것이라(원작처럼 등장하는 순간에만),
    /// 연출이 상시 반복으로 되돌아가면 잘못된 그림을 릴리스에 싣는 대신 여기서 멈춰야 한다.
    ///
    /// 세는 것은 **금색 픽셀의 넓이**다. 스프라이트 자신이 계속 움직여 프레임마다 그림이 달라지므로
    /// "프레임이 서로 다르다"로는 반짝임을 가려낼 수 없다. 대신 금색 넓이가 **솟았다가 바닥으로
    /// 돌아오는지**를 본다 — 화면의 고정된 금빛(사탕 게이지 등)은 바닥값에 함께 깔리고, 상시
    /// 반짝임이면 끝까지 안 내려온다.
    private func assertSparkleIsOneShot(in frames: [NSBitmapImageRep]) throws {
        // **찍힌 별은 호박색이 아니라 연한 크림색이다.** 처음엔 `ShinySparkles.gold` 의 바깥
        // 색(252,184,41)을 기대해 `b < 130` 으로 걸렀는데, 실제 픽셀은 (254,246,207)·(253,242,191)
        // 이었다 — 별이 작아 그라디언트의 흰 안쪽이 넓이의 거의 전부를 차지한다. 그 조건으로는
        // 900 픽셀짜리 폭발이 30 으로 세어져 멀쩡한 GIF 가 실패했다. 그래서 "밝고 **따뜻한**"
        // 픽셀로 센다 — 파랑보다 빨강이 뚜렷이 큰 것.
        let gold = frames.map { frame -> Int in
            guard let bytes = frame.bitmapData else { return 0 }
            let bpp = frame.bitsPerPixel / 8
            var count = 0
            for y in 0..<frame.pixelsHigh {
                for x in 0..<frame.pixelsWide {
                    let o = y * frame.bytesPerRow + x * bpp
                    let r = Int(bytes[o]), g = Int(bytes[o + 1]), b = Int(bytes[o + 2])
                    if r > 170, g > 140, r > b + 40 { count += 1 }
                }
            }
            return count
        }
        let floor = try XCTUnwrap(gold.min()), peak = try XCTUnwrap(gold.max())
        let burst = peak - floor
        // 실측: 바닥 135(이름 옆 ✨ 등 화면에 늘 있는 따뜻한 픽셀) · 꼭대기 1037.
        XCTAssertGreaterThan(burst, 400, "반짝임이 프레임에 안 담겼다 — 금색 넓이가 평평하다: \(gold)")
        // 등장하는 순간에 나야 한다 — 꼭대기가 뒤쪽이면 연출이 늦게 시작한 것이다.
        let peakIndex = try XCTUnwrap(gold.firstIndex(of: peak))
        XCTAssertLessThan(peakIndex, frames.count * 2 / 3,
                          "반짝임이 뒤늦게 난다(\(peakIndex)/\(frames.count)): \(gold)")
        // 그리고 꺼져야 한다. 이 검사가 상시 반짝임과 한 번 반짝임을 가르는 지점이다.
        let tail = gold.suffix(4)
        XCTAssertLessThan(tail.reduce(0, +) / tail.count, floor + burst / 4,
                          "반짝임이 끝까지 남아 있다 — 한 번만 나는 연출이 아니다: \(gold)")
    }

    /// 알에서 포켓몬으로 바뀌는 순간이 실제로 찍혔나. 연출이 조용히 짧아지거나 순서가 바뀌면
    /// 알만, 또는 포켓몬만 있는 GIF 를 릴리스에 실어 보내게 된다.
    private func eggBecomesAPokemon(in frames: [NSBitmapImageRep]) -> Bool {
        // 가운데 판의 **밝은 픽셀 넓이**를 센다. 줄 하나의 폭으로 재던 것은 링·글로우까지
        // 같이 잡혀 알과 스프라이트가 구분이 안 됐다(실측: 92~115 로 평평했다).
        let areas = frames.map { frame -> Int in
            guard let bytes = frame.bitmapData else { return 0 }
            let bpp = frame.bitsPerPixel / 8
            let xs = Int(Double(frame.pixelsWide) * 0.30)..<Int(Double(frame.pixelsWide) * 0.70)
            let ys = Int(Double(frame.pixelsHigh) * 0.15)..<Int(Double(frame.pixelsHigh) * 0.75)
            var count = 0
            for y in ys {
                for x in xs {
                    let o = y * frame.bytesPerRow + x * bpp
                    let lum = (Int(bytes[o]) + Int(bytes[o + 1]) + Int(bytes[o + 2])) / 3
                    if lum > 110 { count += 1 }
                }
            }
            return count
        }
        guard let first = areas.first, let smallest = areas.min() else { return false }
        // 실측: 알 구간 약 11,000 · 포켓몬 구간 약 2,800.
        XCTAssertGreaterThan(first, 6000, "첫 프레임에 알이 안 보인다")
        // **마지막 프레임이 아니라 가장 작은 프레임**을 본다. 확인하려는 건 "알이 포켓몬으로
        // 바뀌는 순간이 담겼나"이지 "마지막 프레임이 포켓몬인가"가 아니다.
        return smallest < first / 2
    }

    /// 네 단계가 **순서대로** 프레임에 찍혔는지 확인한다. 이 GIF 는 에스컬레이션을 보여주려고
    /// 존재하므로, 연출이 조용히 짧아지거나(단계 수 변경) 색이 뒤바뀌면 잘못된 그림을 릴리스에
    /// 실어 보내는 대신 여기서 멈춰야 한다.
    ///
    /// 판정은 밝기가 아니라 **색조**로 한다 — 글로우는 검은 막 위에 번진 것이라 원색보다 훨씬
    /// 어둡다(실측: 하늘색 단계의 가장 진한 픽셀이 rgb(51,71,84)). 채널을 최댓값으로 정규화하면
    /// 어두워도 색조는 남는다.
    private func assertEscalationIsVisible(in frames: [NSBitmapImageRep]) throws {
        let stages = EggReveal.stages(for: ScreenshotFixture.revealGrade)
        let targets = try stages.map {
            try XCTUnwrap(NSColor($0.color).usingColorSpace(.deviceRGB), "단계 색을 RGB 로 못 바꿨다")
        }
        var next = 0   // 다음으로 나타나야 할 단계
        for frame in frames {
            guard let hue = dominantHue(frame) else { continue }
            let nearest = targets.indices.min {
                distance(hue, normalized(targets[$0])) < distance(hue, normalized(targets[$1]))
            }
            if nearest == next { next += 1 }
        }
        XCTAssertEqual(next, stages.count,
                       "연출이 \(stages.count)단계를 순서대로 지나지 않았다 — \(next)단계까지만 보인다")
    }

    /// 프레임에서 가장 색이 진한 픽셀의 색조. 알 글로우만 보도록 가운데로 좁힌다 — 상점의 초록
    /// "Draw" 버튼이 왼쪽에 있어 프레임 전체를 보면 그게 이길 수 있다. (마지막 단계에만 나오는
    /// 결과 줄의 ✨ 가 아래쪽 경계로 들어와도 무해하다 — 그 프레임은 어차피 주황 단계다.)
    private func dominantHue(_ frame: NSBitmapImageRep) -> (r: Double, g: Double, b: Double)? {
        guard let bytes = frame.bitmapData else { return nil }
        let bytesPerPixel = frame.bitsPerPixel / 8
        let xs = Int(Double(frame.pixelsWide) * 0.33)..<Int(Double(frame.pixelsWide) * 0.67)
        let ys = Int(Double(frame.pixelsHigh) * 0.15)..<Int(Double(frame.pixelsHigh) * 0.70)
        var best: (chroma: Int, color: (r: Double, g: Double, b: Double))?
        for y in ys {
            for x in xs {
                let offset = y * frame.bytesPerRow + x * bytesPerPixel
                let r = Int(bytes[offset]), g = Int(bytes[offset + 1]), b = Int(bytes[offset + 2])
                let chroma = max(r, max(g, b)) - min(r, min(g, b))
                if chroma > (best?.chroma ?? 0) {
                    best = (chroma, normalized(r: Double(r), g: Double(g), b: Double(b)))
                }
            }
        }
        return best?.color
    }

    /// 가장 밝은 채널을 1 로 맞춘 색 — 밝기를 빼고 색조만 남긴다.
    private func normalized(r: Double, g: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        let peak = max(r, max(g, b))
        guard peak > 0 else { return (0, 0, 0) }
        return (r / peak, g / peak, b / peak)
    }

    private func normalized(_ color: NSColor) -> (r: Double, g: Double, b: Double) {
        normalized(r: color.redComponent, g: color.greenComponent, b: color.blueComponent)
    }

    private func distance(_ a: (r: Double, g: Double, b: Double),
                          _ b: (r: Double, g: Double, b: Double)) -> Double {
        abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
    }

    /// 메뉴바 — 상태아이템은 오프스크린 렌더가 닿지 않는 표면이라 유일하게 손으로 조립한다.
    /// 무엇이 진짜고 무엇이 표현인지는 `menuBarFrame` 주석에 적어 뒀다.
    private func menuBarAnimation(_ fixture: Fixture, usage: UsageStore) throws -> Data {
        let motion = ScreenshotFixture.menuBarMotion
        let species = try XCTUnwrap(fixture.player.displayedSpeciesID, "파트너가 없다")
        let form = fixture.player.displayedForm
        let shiny = fixture.player.displayedIsShiny
        let loaded = try waitFor {
            await SpriteStore.shared.data(speciesID: species, form: form,
                                          animated: true, shiny: shiny)
        }
        let data = try XCTUnwrap(loaded, "움직이는 스프라이트를 못 얻었다 — 캐시에도 없고 받지도 못했다")
        let sprites = GIFDecoder.frames(from: data)
        XCTAssertGreaterThan(sprites.count, motion.frames,
                             "스프라이트 프레임이 잘라 쓸 만큼도 안 된다")
        let title = try XCTUnwrap(usage.menuLines.first, "메뉴바에 표시할 줄이 없다")
        let frames = try sprites.prefix(motion.frames).map {
            try menuBarFrame(sprite: $0.image, title: title)
        }
        return try gif(frames, delay: motion.delay)
    }
}
