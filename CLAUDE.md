# PokeTokenBar — Claude 프로젝트 지침

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
   - **스크린샷(`assets/`)**: UI(`Sources/PokeTokenBar/UI/`) 변경 시 재생성. 기존 방식 = **HTML 렌더**
     (팝오버 라이브 캡처 아님) — Chrome `--headless --screenshot --force-device-scale-factor=2` 로 다크
     팝오버를 720px PNG 로 그린다. 애니 GIF(home)는 프레임 합성 후 `gifsicle -O3 --lossy` 로 최적화
     (PIL 재인코딩 단독은 용량 팽창 주의). 언어별 이미지(`settings.png`/`-ko`/`-ja` 등) 각 README 참조.
   - homebrew-tap cask caveat.
   - **함정:** `release.sh` 문서검토는 *커밋된* 상태를 비교 → 스크린샷을 스테이징만 하면 경고 프롬프트가
     여전히 뜬다. 미리 커밋하거나 프롬프트에 `y`(스테이징분이 release.sh line 93-94 에서 릴리스 커밋에 함께 담김). (`RELEASE.md` 체크리스트)
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
4. **검증**: 완료 후 `brew upgrade --cask poke-token-bar` 로 실제 업그레이드 동작 확인.

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
