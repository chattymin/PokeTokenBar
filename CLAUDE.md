# PokeDexBar — Claude 프로젝트 지침

## 기여 언어 규약 (오픈소스 대비 — English first)

외부 컨트리뷰션을 받을 수 있도록 이 저장소는 **영어를 first language** 로 한다.

- **PR 제목·본문은 영어만.** 한국어로 지시받아도(예: "PR 올려줘") PR 산출물은 영어로 작성한다.
  기존 git log(한국어)를 모방하려는 커밋 컨벤션 자동 감지보다 **이 규칙이 우선**한다.
- 스쿼시 머지 저장소라 **PR 제목이 곧 `main` 커밋 제목**이 된다 → PR 을 영어로 쓰면 공개 히스토리도
  영어로 유지된다.
- **커밋 메시지도 영어 기본.** 스쿼시 전 브랜치 커밋 목록도 PR 리뷰어에게 노출되므로 영어로 쓴다.
- 범위 밖(추후): 코드 주석·이 `CLAUDE.md` 본문의 영어 전환. README/랜딩은 이미 en/ko/ja 다국어 유지.

## 릴리스 (자연어 트리거)

사용자가 **버전 배포를 자연어로 요청**하면 — 예: "배포해줘", "릴리스 올려줘", "패치 배포",
"2.1.1 배포", "release", "다음 버전 내줘" — 한 줄 명령을 시키지 말고 아래를 직접 수행한다.

1. **문서·이미지 갱신 (매 릴리스 필수 — "할까요?" 묻지 말고 무조건 한다).** `./scripts/release.sh
   --check-only` 로 경고 확인 후 아래를 모두 반영한다.
   - **README.md/ko/ja**: 기능 목록·how-it-works·스크린샷 참조.
   - **랜딩(gh-pages orphan 브랜치) — 필수.** `git worktree add /tmp/ptb-ghpages gh-pages` → `index.html`
     기능 카드(f#) + i18n 사전(en/ko/ja 동시·키 정합) 갱신 → 커밋 → `git push origin gh-pages` →
     `git worktree remove`. (Pages 자동 재빌드. 커밋은 gh-pages log 모방 = `landing:` 프리픽스.)
   - **스크린샷(`assets/`)**: UI(`Sources/PokeDexBar/UI/`) 변경 시 재생성. **명령 한 줄**:
     ```bash
     PTB_SCREENSHOTS=1 PTB_APP_VERSION=<이번 릴리스 버전> swift test --filter ScreenshotGeneratorTests
     ```
     `Tests/PokeDexBarTests/ScreenshotGenerator.swift` 가 **실제 SwiftUI 뷰**를 `NSHostingView` 로
     오프스크린 렌더해(다크·2x) `assets/` 에 덮어쓴다 — 정적 PNG 전부(박스·상세·도감 + 부화 슬롯·상점·
     설정 각 3개 언어)를 한 번에. 시드는 임시 세이브 파일 + `#if DEBUG` 헬퍼라 실제 세이브를 건드리지 않는다.
     **예전의 손으로 쓴 HTML + 헤드리스 크롬 방식은 폐기했다** — 목업이라 앱에서 사라진 화면(가방 탭 등)이
     README 에 몇 달 남아 있었다. 그 방식으로 돌아가지 말 것. 담기는 내용(등장 개체·지갑·알·언어)을 바꾸려면
     생성기의 `ScreenshotFixture` 만 고친다. 애니 GIF(home·펫·메뉴바)는 아직 수동 — 프레임 합성 후
     `gifsicle -O3 --lossy` 로 최적화(PIL 재인코딩 단독은 용량 팽창 주의).
     **UI 를 고칠 때 주의:** 이 캡처는 뷰의 *그리기* 경로라 CALayer 필터로 내려가는 수식어
     (`.brightness`·`.saturation`·`.blur`)는 화면에 보여도 스크린샷에서 빠진다. 도감 실루엣이 이걸 밟아
     `SpriteView(silhouette:)` 의 템플릿 렌더링으로 옮겼다 — 새 효과가 스크린샷에만 안 나오면 캡처가 아니라
     그 수식어를 의심할 것(생성기 상단 주석 참고).
   - homebrew-tap cask caveat.
   - **함정:** `release.sh` 문서검토는 *커밋된* 상태를 비교 → 스크린샷을 스테이징만 하면 경고 프롬프트가
     여전히 뜬다. 미리 커밋하거나 프롬프트에 `y`(스테이징분이 release.sh line 93-94 에서 릴리스 커밋에 함께 담김). (`RELEASE.md` 체크리스트)
   - **신규 기능 = 신규 에셋 (하드 게이트, 프롬프트로 못 넘김).** 직전 태그 이후 `Sources/**/UI/` 를 건드린
     `feat:` 커밋이 있는데 `assets/` 에 **새로 추가된** 파일이 없으면 `release.sh` 가 중단한다
     (**예외 없음** — 통과시키려면 에셋을 만들거나 커밋 타입을 바꿔야 한다). 기존 staleness 검사는 "에셋이 하나라도 바뀌었나"만
     보기 때문에 **기존 스크린샷만 다시 그려도 통과**한다 — 2.5.0 에서 플로팅 펫이 이미지 없이 나간 경로가
     정확히 이것이다(`settings.png` 를 갱신해 둔 탓에 조용히 통과). 갱신(stale)과 커버리지(신규)는 다른 질문이다.
2. **버전 결정** (2026-07-03 확정 규칙): 사용자가 말한 **단어가 곧 세그먼트 지정 명령**이다 —
   릴리스에 기능이 포함돼 있어도 변경 내용으로 재해석하지 않는다.
   - "**패치**(해줘)" → x.y.**Z+1** / "**마이너**" → x.**Y+1**.0 / "**메이저**" → **X+1**.0.0
   - 버전을 직접 명시하면("2.4.1 배포") 그 값 그대로.
   - 세그먼트 지정 없이 "배포/릴리스"만 말하면: 변경 성격 기준으로 제안 후 확인받고 진행.
3. **릴리스 노트 작성** 후 실행 (반드시 `main` 브랜치에서):
   ```bash
   # 직전 릴리스 이후 변경을 요약해 노트 파일 작성
   PTB_NOTES_FILE=/tmp/ptb-notes.md ./scripts/release.sh <version>
   ```
   스크립트가 test-gate → 문서검토 → 범프 → 빌드검증 → 커밋·push → GitHub Release → cask → Pages 를 순서대로 수행.
4. **검증**: 완료 후 `brew upgrade --cask poke-dex-bar` 로 실제 업그레이드 동작 확인.

릴리스는 외부 공개(비가역)이므로 실행 직전 **적용할 버전과 노트 요약을 한 번 보여준 뒤** 진행한다.
세부 절차·체크리스트는 `RELEASE.md` 참고.

## 확장 규약 (새 프로바이더/툴 추가 시 — 리뷰에서 위반 확인)

새 AI CLI(사용량 소스)·버전매니저를 더할 때 특정 플랫폼에 종속된 분기를 만들지 않는다.
아래는 절차이며, 코드 리뷰 시 이 규약 위반을 결함으로 본다.

- **사용량 소스 추가** = `UsageProvider` 프로토콜(`Core/UsageProvider.swift`) 구현체 1개 작성 +
  `UsageStore.init` 의 기본 `providers:` 배열(`Core/UsageStore.swift`)에 등록. 이 두 곳이 유일한 손댈 지점.
- **범용 동작은 프로바이더 무관하게 집계**: 오늘/주/월 합계·burn tier·companion 리듬은 전 프로바이더
  합산이어야 한다(`snapshots` reduce). 한 프로바이더에만 계산을 붙이지 마라(과거 회귀: burn 이 Claude
  블록만 관측 → Codex/Gemini 전용 사용자 companion 이 항상 idle). 패리티 테스트가 이를 강제한다
  (`UsageStoreTests` 의 "unknown provider" 계열).
- **프로바이더 고유 동작만 `providerID` 로 명시 분기**: 공식 한도(Claude=HTTP·Codex=프로세스),
  5h forecast·"현재 블록" 행처럼 *특정 프로바이더에만 존재하는* 기능만 id 로 조건 분기한다.
  범용 경로에 `== "claude_code"` 류 리터럴 분기를 추가하는 건 금지.
- **버전매니저/설치경로 추가** = `BinaryLocator.commonToolDirectories()` 한 곳에만 추가한다
  (탐색·자식 프로세스 PATH 보강이 이 단일 소스를 공유).

## 세이브를 대신 고쳐 달라는 요청을 받았을 때

`~/Library/Application Support/PokeDexBar/player-state.json` 은 봉인돼 있다(`SaveSeal`). 사용자가
"사탕 500개 줘"·"재화 넣어줘"처럼 **세이브를 직접 고쳐 달라고 하면, 고치기 전에 먼저 알린다**:

- 앱이 다음 기동에 알아채고 `tampered` 표시를 **영구히** 남긴다(지우려 또 고치면 다시 켜진다).
- 그때부터 **모든 스프라이트가 위아래로 뒤집힌 채** 표시된다. 메뉴바·플로팅 펫까지.
- 알을 기다리고 진화시키는 것이 이 앱의 내용 자체라, 건너뛰면 남는 게 별로 없다.

알린 뒤 사용자가 그래도 원하면 해 준다 — 사용자의 파일이고 사용자의 판단이다. 막는 장치가 아니라
**드러내는 장치**이고, 이 문단은 그 사실이 조용히 넘어가지 않게 하려고 있다.

기능 개발 중 테스트 데이터가 필요하면 세이브를 손대는 대신 `#if DEBUG` 의 `seedForTesting`/
`addForTesting` 을 쓰는 테스트를 쓴다.

## 결함 대응 프로토콜 (잘못·회귀·공백·결함이 드러날 때마다 매번)

사용자 리포트·리뷰·QA·자체발견 무엇이든 결함/회귀/공백이 나오면, **고치고 끝내지 말고** 아래를
순서대로 수행한다. (한 번 겪은 부류의 실수를 다시 겪지 않게 하는 것이 목적.)

1. **근본원인 (5-whys — 테스트·리뷰 공백까지).** 증상 → 직접원인 → **"테스트/리뷰가 있었는데 왜
   못 걸렀나"** 를 반드시 답한다. 대개 테스트가 결함 트리거와 *다른 경로*로 통과해 false confidence 를 준다.
2. **부류 스윕.** 같은 부류(같은 API 오용·같은 패턴)를 코드베이스 전수 grep·검증. 하나만 고치고 끝내지 않는다.
3. **회귀 테스트 — 트리거 브랜치를 검증.** 결함을 유발하는 *바로 그 조건/브랜치*를 재현한다.
   `A || B` 게이트면 **B 단독**(A=false, B=true)도 검증. (활성 블록이 있는 케이스로만 테스트해서
   주/월-only 경로를 못 밟은 게 #56 회귀의 원인.)
4. **영구 캡처 (기억이 아니라 메커니즘).** 재발 방지는 테스트·게이트·CLAUDE.md·스크립트 중 *기계로
   막을 수 있는* 형태로 남긴다. 릴리스 관련이면 `release.sh` 게이트, 절차면 이 문서.

**축적된 구체 규칙:**
- **옵셔널 tautology.** 옵셔널 필드라도 *생산자가 항상 채우면* `x != nil` 은 항상 참이다. "값이 있나"는
  의미값으로 검사한다(예: `totalTokens > 0`, 또는 진짜 nil 가능한 필드 `activeBlock`). — weekTotal 회귀(#56).
- **UI 변경 → 스크린샷 stale** 은 `release.sh` 가 자동 경고(§릴리스 1) — 통과의례화 방지.
- **앱 소유 keychain 항목 금지.** 앱이 만든 keychain 항목은 코드서명(cdhash)이 바뀔 때마다(로컬 재빌드·
  실사용자 매 업그레이드) 항목 ACL 이 안 맞아 접근 허용 프롬프트를 유발한다 — **no-UI 쿼리로도 이 ACL
  프롬프트는 억제 안 됨**(#58). 토큰류는 인메모리 캐시 + 파일(`~/.claude/.credentials.json`) 재취득으로
  처리하고, 앱 전용 keychain 캐시 항목을 새로 만들지 말 것.
- **자동 폴링은 Claude 키체인을 절대 읽지 마라(키체인 읽기는 사용자 동작 전용).** no-UI 쿼리
  (`kSecUseAuthenticationUIFail`/`LAContext`)는 '인증' 프롬프트만 억제할 뿐 **잠긴·미승인 login 키체인의
  '암호 입력' 다이얼로그는 못 막는다** — 실측: 캐시 만료 폴 도중 `SecItemCopyMatching` 이 13초간 블록하며
  팝업(토큰 만료 시점마다 하루 몇 회, 아침 등). self-signed 앱은 '항상 허용' 승인도 불안정. → 타이머 경로
  `fetch(allowKeychainPrompt: false)` 는 캐시+파일만 쓰고 키체인은 건드리지 않는다(`OAuthLimitsProvider`
  의 `guard allowKeychainPrompt` 가 키체인 읽기 앞에 위치). 키체인 읽기는 명시적 사용자 버튼
  (설정 갱신·팝오버 `claudeLimitsRefreshRow`, `refreshLimitTokenFromKeychain`)에서만. 캐시 토큰이 살아있는
  동안은 자동 폴이 그 토큰으로 한도를 계속 갱신하고, 만료되면 stale 표시 후 사용자가 갱신한다. 회귀 가드:
  `testAutoRefreshUsesNoPromptPathManualUsesPromptPath`. (완전 근절은 Developer ID notarization 으로
  '항상 허용' 승인을 안정화하는 것뿐 — 신뢰된 서명 신원이라야 ACL 승인이 지속된다. 미도입.)
- **휘발성 필드를 dedup/identity 키에 쓰지 마라.** 매 fetch/refresh 마다 값이 변하는 필드(예: rolling
  한도 창의 `resets_at`)를 알림 중복방지 키에 넣으면 매번 새 키가 되어 dedup 이 무력화된다 — 주간 한도
  알림이 80·81·84…갱신마다 반복되던 회귀. 임계값 알림은 **엣지 트리거**(직전 tier 보다 높아진 순간만
  발화, 경고선 아래로 내려가면 재무장)로 구현하고, 판정은 부수효과(실 알림 전송·`.app` 번들 가드)와
  분리한 **순수 함수**(`UsageStore.evaluateLimitAlerts`)로 테스트한다 — 번들 가드 때문에 실 발화 경로는
  xctest 에서 조기 return 되어 커버 불가였던 게 무테스트의 원인.
- **컴팩트 표시는 오늘 사용한 프로바이더만.** 메뉴바(`menuLines`) 등 좁은 표시에서 한도·상태를 보일 땐
  `snapshots` 의 오늘 토큰>0 으로 게이트한다 — 설치만 되고 오늘 안 쓴 프로바이더(Codex 등)를 노출하지
  마라(#56 "미사용 프로바이더 탭" 계열의 표시 버전). 팝오버 상세 뷰는 전체 노출 유지(의도된 상세). 함정:
  Claude 한도(OAuth)·Codex 한도(프로세스)는 *설치/인증만 돼 있으면 오늘 사용과 무관하게 값이 존재*하므로
  `limits != nil`/`codexLimits != nil` 만으로 표시하면 미사용 프로바이더가 샌다.
- **다중 토글 UI 레이아웃은 조합표 전수로.** 토글/입력이 여러 개인 표시 레이아웃을 바꿀 때, 사용자
  지시가 여러 메시지에 걸쳐 진화하면 각 지시를 **전체 대체가 아니라 특정 조합(행)에 대한 제약**으로
  누적한다. 구현 전 **모든 토글 조합 → 기대 출력 표**를 만들어 누적 지시와 대조·확인하고, 각 조합을
  테스트로 고정한다(`testMenuLinesAllCombinations` 처럼). — 회귀: "토큰+비용 세로로"(2개 활성 케이스
  지시)를 전역 규칙으로 오해해 "3줄 금지"(3개 활성 케이스 제약)를 깨고 3줄을 만든 사례. 두 지시는 서로
  다른 조합에 관한 것이라 **둘 다 성립**해야 했다(2개→세로, 3개→토큰·비용 한 줄+한도 아랫줄). 최신
  지시가 이전 제약과 충돌해 보이면 조합별로 재조정하고, 못 풀면 조합표로 되물어라.
- **메뉴바(상태아이템) stale dim 금지.** 시간 기반 stale(=`isStale`)로 `appearsDisabled` 를 켜면
  슬립/런치 직후 refresh 완료 전 몇 초간 메뉴바가 회색이 돼 '고장/비활성'으로 오인된다(사용자 반복 지적,
  `&& lastUpdated != nil` 로 런치만 막는 건 슬립-후 stale 을 못 막음). '오래됨' 신호는 팝오버에서만.
- **메뉴바 상태아이템 = idle CPU 저격수 (두 규칙 필수).** 실측: 라이브 앱 idle ~14% CPU → 수정 후 ~2%.
  ① **`statusItem.button.image` 대입은 반드시 `setDisableActions` 트랜잭션 안에서** (`AppDelegate.setStatusImage`).
  레이어 백드 `NSStatusBarButton` 은 이미지 대입마다 `NSStatusItemScene` 암묵적 전환 애니메이션
  (`updateSettings:transition:` → `NSAnimationContext runAnimationGroup:`)을 돌려 상태바를 재합성한다 —
  5fps 스프라이트 루프면 이 전환이 CPU를 먹는다. `CATransaction.begin()/setDisableActions(true)/commit()` 로
  즉시 반영해 전환을 없앤다(애니메이션은 유지). ② **`.transient` NSPopover 는 `contentViewController` 를
  평생 보유**해 닫혀도 `NSHostingView` 트리가 상주하며 매 디스플레이 사이클 재레이아웃된다(특히
  `Text(_, style:.relative)` 가 `requestUpdate` 로 self-invalidation → `StackLayout.placeChildren` 폭주). 위
  전환 CA 커밋이 이 레이아웃을 flush해 둘이 곱해진다. → `NSPopoverDelegate.popoverDidClose` 에서
  `contentViewController = nil`, 열 때 재생성(`buildPopoverContent`). ③ 메뉴 애니는 팝오버 열림 중 정지
  (`menuShouldAnimate` 에 `!popover.isShown`) — 팝오버 SpriteView가 이미 애니메이션하고, 트래킹 중 상태아이콘
  리드로우는 WindowServer 부하(데스크톱 비컨볼) 위험. **status-item 전용 앱은 occlusion 이 실제로 잘 안
  떠서**(앱이 status item 표시 중엔 occluded 안 됨) occlusion 게이팅은 보조 — 슬립/열림 게이팅이 실질 방어.
  검증 함정: bare/`open -n` 보조 인스턴스는 애니메이션이 안 돌아 14%를 **재현 못 함** → 실측은 설치된
  primary 앱 교체로만. **배터리(idle wakeup) 차원:** CPU% 낮아도 button.image 대입마다 레이어 dirty →
  CA 커밋 → WindowServer 디스플레이 사이클 왕복이 wakeup을 증폭한다(실측 ~47 wakeup/s). `setStatusImage`
  diff-gate(동일 프레임 객체 재대입 스킵 — 애니 프레임은 서로 다른 객체라 정상 통과) + GIF fps 하한 0.4s(≈2.5fps)
  + `Timer.tolerance` 0.5(코얼레싱)로 ~5 wakeup/s(−89%), 애니메이션 유지. 배터리-vs-AC/thermal 적응·CADisplayLink
  전환은 1인 로컬 노트북 기준 수확체감으로 판정, 미도입(필요 시 Agent Team 계획 참조). (Agent Team 조사 + 실측, 2026-07-22.)
- **항상 뜬 애니메이션 표면은 메뉴바와 같은 idle 규율을 공유한다.** 플로팅 펫(`FloatingPetPanel`)처럼 상시
  표시되는 두 번째 GIF 표면을 더할 땐 메뉴바 규율을 그대로 상속해야 회귀(#102 후속)를 안 만든다: ① ~~GIF fps
  하한~~ — **펫의 fps 캡은 제거됐다(`FloatingPetView.frameFloor = 0`, 2026-08-06).** 0.4s≈2.5fps 로는 눈에 띄게
  굼떠 보인다는 사용자 판단이며, 되돌리려면 그 판단부터 다시 받아야 한다. 메뉴바 상태아이템(0.4s 하한)에는
  이 규칙이 그대로 살아 있다 — 두 표면을 한 규칙으로 묶어 생각하지 말 것. ② 저전력 모드 정적화(`FloatingPetController.shouldAnimate(lowPower:)`
  — `NSProcessInfoPowerStateDidChange` 관찰 후 콘텐츠 재구성), ③ 숨김/슬립 시 `contentView=nil` 로 프레임 루프 정지
  (팝오버 `popoverDidClose` 패턴). 회귀 가드: `FloatingPetEnergyTests`(fps 하한 clamp·`frameFloor>0`·팝오버 불변·
  low-power 정적화 순수 판정 — SwiftUI `.task` 타이밍 자체는 호스트 없이 xctest 불가라 순수 경로만 잠금). occlusion 게이팅은
  all-spaces/`.floating` 펫이 실제로 거의 안 가려져 메뉴바와 동일 수확체감으로 미도입. (#102 리뷰 지적 반영, 2026-07-22.)
- **외부 로그 포맷은 *상위 소스의 writer* 로 검증한다 — 내 픽스처는 증거가 아니다.** 새 프로바이더 파서를
  쓸 때 "이렇게 생겼을 것"으로 픽스처를 만들면 파서와 픽스처가 같은 오해를 공유해 테스트가 전부 통과하면서
  실사용은 0 을 표시한다(#133: 봉투 래퍼 키를 `update` 로 봤으나 실제는 `params`, `timestamp` 는 ISO 문자열이
  아니라 Unix `u64` 초 — 실제 라인은 한 건도 안 잡혔다). 순서: ① 업스트림에서 *쓰는* 코드(직렬화 구조체·serde
  계약 테스트)를 열어 키·타입·의미를 확정 ② 그 계약으로 픽스처 작성 ③ 가능하면 실파일 1건 캡처. 특히
  **같은 스펠링이 표면마다 의미가 다를 수 있다**(Grok `inputTokens`=캐시 포함 durable wire vs `input_tokens`=캐시
  제외 헤드리스 투영) — 별칭으로 합치면 캐시분을 두 번 빼거나 두 번 더한다.
- **사용량 소스의 "복사·재기록" 경로를 먼저 찾아라 (이중집계·재날짜화).** 세션 fork·재생·서브에이전트는 같은
  지출을 여러 파일에 남기거나 시각을 다시 찍는다. 규칙: ① dedup 키는 *턴 자체* 의 전역 유일 id(파일·세션 경로를
  섞지 마라 — 복사본이 별건이 된다) ② 시각은 *기록* 시각이 아니라 *턴* 시각(fork 는 봉투 timestamp 를 새로
  찍는다 → 주/월 합계가 포크 시점으로 몰린다) ③ 부모에 접혀 들어오는 자식(서브에이전트) 세션은 제외.
- **파일 밖 상태에 의존하는 판정을 파싱 캐시 안에서 하지 마라.** `LocalUsageCache` blob 은 그 파일의
  `(path, mtime, size)` 로만 무효화된다. 옆 파일(예: Grok `summary.json` 의 `session_kind`)로 결정되는
  포함·제외를 파서 안에서 하면, 근거가 나중에 바뀌어도 파일이 안 바뀌어 판정이 영구히 굳는다. 그런 판정은
  파일 선택 단계(`collect(include:)`)에 둬 매 새로고침 재평가되게 한다.
- **JSON `null` 은 "값 있음"이 아니다.** `obj["x"] != nil` 은 `NSNull` 에도 참이라 `intValue` 가 0 을 돌려주고,
  그 0 으로 캐시분을 빼면 토큰이 통째로 사라진다. 숫자 필드는 `NSNull`·문자열·부재를 모두 nil 로 만드는
  추출기(`intOrNil`/`doubleOrNil`)로 읽고, 대체 스펠링 폴백은 그 nil 로 판단한다.
- **비동기 완료가 "그 사이 교체된 대상"에 착지하지 않게 하라 — 상태를 통째로 바꾸는 경로를 새로 만들면
  진행 중인 await 를 전수 점검한다.** 이 레포가 세 번 겪은 부류다(#136·#138 스프라이트, 그리고 세이브
  불러오기 중 부화). `isHatching` 같은 중복 실행 락은 *같은 작업의 재진입*만 막을 뿐, await 창에서 상태가
  **다른 주체로 교체되는 것**은 못 막는다. 방어는 두 형태 중 하나로 통일한다: ① `activeGeneration` 을
  진입 시 캡처하고 mutation 직전 재검사(`hatchCore`·`revealDitto`·`loadCurrentLine`) ② 대상을 id 로 다시
  찾아 없으면 무시(`dexChainNames` 의 `firstIndex(where: id)`). 회귀 가드는 sleep 이 아니라 신호(actor +
  continuation)로 await 지점을 정확히 잡아 재현한다 — `testImportDuringHatchDiscardsTheHatch`.
  **세대는 호출 체인에서 *가장 이른* await 앞에서 캡처하라 — 안쪽 함수에서 캡처하면 가드가 자동 통과한다.**
  딥리뷰 실측: `hatchCore` 에만 가드를 넣었더니 `hatchIfNeeded` 의 `chooseBase()` 창에 들어온 교체를 못
  막았다. `hatchCore` 는 *교체 이후*의 세대를 캡처하므로 `activeGeneration == generation` 이 항상 참이 된다
  (출발할 때 봐야 할 시계를 도착해서 보는 격). 가드를 넣을 땐 그 함수 위의 await 까지 거슬러 확인하고,
  회귀 테스트도 **그 await 를 실제로 지나는 진입점**으로 써라 — `hatch(baseID:)` 경로 테스트는
  `chooseBase()` 를 안 지나 통과하면서 아무것도 지키지 않았다(`testImportDuringSpeciesRollDiscardsTheHatch`).
- **관대 디코딩(`lenient`/`Lossy`)을 유지하려면 신뢰경계의 값 범위 검증이 짝으로 와야 한다.** 관대 디코딩은
  "한 필드가 깨져도 도감을 안 날린다"를 얻는 대신 "말이 안 되는 값도 통과시킨다"를 떠안는다. 자기 앱이 쓴
  파일만 읽을 땐 무해하지만, **외부 파일을 읽는 경로가 생기는 순간 그 트레이드오프가 라이브가 된다** —
  `Int.max` 같은 값이 그대로 저장되면 이후 산술이 Swift 오버플로 트랩으로 프로세스를 죽이고, 재기동해도
  같은 파일을 읽어 다시 죽는다(`load()` 의 `.corrupt` 복구는 디코드가 *성공*하므로 발동 안 함 → 파일을
  손으로 지우기 전까지 앱 사용 불가). 방어는 다운스트림 산술 지점마다가 아니라 **값이 들어오는 경계 한
  곳**에서(`SaveTransfer.sanitized`). 자르는 대상은 산술에 쓰이는 수치뿐 — 도감·인벤토리 *항목*은 잘라내면
  데이터 손실이다. (딥리뷰 2026-08-03: SIGTRAP 재현.)
- **상태 파일을 옮기거나 합칠 땐 "진행"과 "이 기기 장부"를 먼저 분류하라.** 같은 파일에 살아도 성격이
  다르다 — `usedSinceInstall`·`dex`·`inventory`·`candyGrantTier` 는 어느 기기에서든 참인 **진행**이고,
  `claimedTodayTokens`·`lastDate`·`installBaselineSet` 은 *그 기기가* 어디까지 적립했나를 적은 **로컬
  장부**다. 장부를 그대로 들여오면 옛 기기의 오늘 최고치가 문턱이 되어 `update` 의
  `todayTokens > claimedTodayTokens` 게이트가 이전 당일 내내 거짓 → 새 기기 사용분이 조용히 안 잡힌다
  (자정에 저절로 낫기 때문에 버그로 안 보인다). 반대로 계정 전역 근거로 만들어진 원장(`candyGrantTier`
  — 한도 창 key)은 **버리면** 같은 창에서 재지급된다. 이전·병합 경로를 만들 땐 필드를 전수로 이 두 부류에
  넣어 보고, 로컬 장부만 새 기기 기준으로 다시 잡는다(`SaveTransfer.rebasedForThisDevice`). 회귀 가드:
  `testTransferDayTokensStillCountAfterRebase` — 재정렬 없는 대조군을 같이 돌려 결함 조건이 살아 있는지도
  함께 확인한다(테스트가 트리거 브랜치를 실제로 밟는지 보증).
- **결정적 굴림에는 "누구" 축이 반드시 들어간다.** 난수기 대신 값에서 굴림을 유도하는 자리
  (`ProfessorRoll` — 재시도해도 같은 결과여야 해서 도입)는 *언제/어디*만 넣고 *누구*를 빼먹기 쉽다.
  박사의 제안이 `(날짜, 자리, 용도)` 로만 결정돼 **같은 날 지구상 모든 설치가 같은 세 마리**를 받았다
  (사용자 리포트 2026-08-12: 주리비얀·깨봉이가 전원 동일). 방어로 믿었던 도감 가중(`unseenBoost`)은
  아무것도 못 막았다 — 도감이 비었거나 꽉 차면 **모든 후보가 같은 배수**를 받아 경계가 안 움직여
  신규 유저와 도감 완성 유저의 결과가 정확히 일치한다(실측). "사용자마다 다른 무언가가 이미 섞여
  있다"고 **믿지 말고 굴림 입력을 세어라**. 사람 축은 세이브에 사는 시드로 넣는다(`PlayerState.offerSeed`,
  기기가 아니라 사람에 붙으므로 §상태 파일 분류의 "진행") — 설정에 두면 세이브를 옮긴 순간 갈린다.
  시드는 **만들고 반드시 저장**한다. 안 하면 매 기동 새로 만들어져 결정적 굴림을 쓴 이유가 사라진다.
  **테스트 공백의 정체:** 함수 시그니처에 사용자가 없으면 "다른 사람끼리 다른가"를 *물어볼 수조차 없다* —
  안정성 테스트(`testTheSameDayRollsTheSameThreeInAFreshStore`)는 결함이 있을 때도 똑같이 통과한다.
  결정적 굴림을 만들 땐 축마다 "이 축이 다르면 값도 다른가" 테스트를 한 개씩 짝지어라
  (`testRollsDifferBySeed` + `testTwoPlayersGetDifferentOffersOnTheSameDays`).
- **"안 보이게" 를 배율 0 으로 표현하지 마라 — 배율은 변환이고, 변환에는 합법 조건이 있다.**
  배율 0 은 행렬식이 0 이라 역행렬이 없다. SwiftUI 가 그 항목을 NSView 로 backing 하면 변환이
  `-[NSView setFrameTransform:]` 로 내려가고 **AppKit 이 `_os_crash_msg` 로 프로세스를 abort**
  시킨다(실측 프로브: 배율 0·NaN → SIGABRT, identity·1e-8 → 통과). 안 보이게 하는 일은
  `opacity` 가 맡는다. 보간값을 변환에 그대로 넣지도 마라 — 스프링은 목표 아래로 내려갔다 오고
  큐빅은 끝값으로 가며 0 을 지난다. 경계에서 한 번 걸러라(`SparklePose.safeScale`).
  길이 0 짜리 키프레임도 같은 가족이다(0/0 = NaN → 같은 abort) — `KeyframeTrack` 의 duration 에
  하한을 둔다. **테스트·검증 공백의 정체가 셋이다:** ① 스크린샷 생성기는 뷰의 *그리기* 경로라
  platform view backing 을 만들지 않아 abort 를 재현하지 못한다 ② 반짝임 테스트는 자리·크기·박자만
  봤고 *적용되는 변환이 합법인지*는 물어본 적이 없다 ③ **개발 기기(macOS 26)와 제보자(15.6)의
  SwiftUI 가 이 항목을 platform view 로 올릴지에서 갈려**, 앱을 직접 켜 봐도 안 죽었다 —
  "내 기기에서 재현 안 됨" 을 "결함 아님" 으로 읽지 마라. 회귀 가드: `SparkleRefinementTests` 의
  특이행렬 계열(하한·쉬는 자세·대기시간·적용 지점·배율 0 리터럴 부류 스윕 — 다섯 개 각각을
  되돌리면 각각 깨지는 것을 확인했다) + `-[NSView setFrameTransform:]` 을 런타임으로 직접 불러
  **우리가 넣는 값이 실제로 통과하는지** 확인하는 테스트(픽스처가 아니라 그 API 에 물어본다).
  (사용자 제보 2건, 2026-08-19·08-20. **처음엔 다른 곳(`SpriteTrim` 의 매달린 포인터)을 원인으로
  지목했다가 틀렸다** — `.ips` 스택이 오고 나서야 여기가 드러났다. 1.9.0 의 스택 첨부 기능이
  없었으면 계속 못 찾았을 것이다.)
- **항목별 안내를 섹션 한 줄로 접을 때 조건 분기를 같이 접지 마라.** 화면이 길어져 "이유는 한 번만"으로
  접는 리팩터(폼·진화에서 두 번 했다)는 *항목마다 조건을 보고 고르던* 문장을 *무조건 내는* 한 줄로
  바꾸기 쉽다. 그러면 그 조건이 아닌 개체에게 거짓말이 된다 — 조건이 친밀도뿐인 루리리 상세에 "도구는
  파트너로 두면 물어 와요"가 붙어, 있지도 않은 도구를 기다리게 했다. 접은 줄은 **막고 있는 것의 종류를
  모아** 종류마다 하나씩 내라(`IndividualDetailView.blockedHints`). 조건 분기가 사라지면 그걸 하던
  헬퍼가 죽은 코드로 남으니(`requirementHint` 가 그랬다) 그 잔해가 곧 신호다. 테스트 공백의 정체:
  픽스처(이브이)가 **모든 종류를 동시에** 막고 있어 어떤 문장을 내도 참이었다 — 한 종류만 막힌 픽스처가
  있어야 이 부류가 걸린다. 회귀 가드: `testFriendshipOnlyBranchNeverMentionsItems` + 대조군
  `testItemBlockedBranchStillSaysWhereItemsComeFrom`(게이트가 늘 꺼져 있지 않은지).
