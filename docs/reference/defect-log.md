---
summary: "결함 대응 프로토콜로 축적된 구체 규칙 — 한 번 겪은 부류의 실수를 다시 겪지 않기 위한 원장."
read_when:
  - 결함·회귀·공백을 고치는 중 (프로토콜 4단계의 '부류 스윕'·'영구 캡처' 근거)
  - 동시성/await·옵셔널 판정·캐시 무효화·외부 로그 포맷을 건드릴 때
  - 크기 상한이 없는 사용자 파일을 읽는 코드(사용량 로그 파서)의 메모리를 손볼 때
  - 메뉴바·플로팅 펫 등 상시 표시 애니메이션의 성능을 손볼 때
  - 스프라이트·이미지를 고정 크기 프레임에 그릴 때(비율 왜곡 부류)
  - 세이브 이전/병합·외부 파일 입력 경로를 만들 때
  - `project.yml`(xcodegen)에 리소스·자산 카탈로그를 추가할 때, 앱 아이콘을 교체할 때
  - iCloud/CloudKit 동기화(iPhone 컴패니언 페이로드)를 건드릴 때, 앱을 Xcode Debug 빌드로 상시 운용할 때
---

# 결함 대응 축적 규칙

`CLAUDE.md` §결함 대응 프로토콜의 4단계(근본원인 → 부류 스윕 → 회귀 테스트 → 영구 캡처)를 거쳐
남은 규칙들이다. 각 항목은 실제로 겪은 회귀에 묶여 있다.

## 판정·데이터

- **옵셔널 tautology.** 옵셔널 필드라도 *생산자가 항상 채우면* `x != nil` 은 항상 참이다. "값이 있나"는
  의미값으로 검사한다(예: `totalTokens > 0`, 또는 진짜 nil 가능한 필드 `activeBlock`). — weekTotal 회귀(#56).
- **JSON `null` 은 "값 있음"이 아니다.** `obj["x"] != nil` 은 `NSNull` 에도 참이라 `intValue` 가 0 을 돌려주고,
  그 0 으로 캐시분을 빼면 토큰이 통째로 사라진다. 숫자 필드는 `NSNull`·문자열·부재를 모두 nil 로 만드는
  추출기(`intOrNil`/`doubleOrNil`)로 읽고, 대체 스펠링 폴백은 그 nil 로 판단한다.
  **숫자만의 문제가 아니다** — 존재 판정에도 같은 함정이 있다. `json["claudeAiOauth"] == nil` 로 계정 OAuth
  유무를 보면 `"claudeAiOauth": null`(로그아웃 상태)이 "있음"으로 판정돼 재로그인 안내 대신 엉뚱한 메시지가
  나간다. 기대 타입으로 캐스팅되는지로 판단한다(`(json["x"] as? [String: Any]) == nil`). 회귀 가드는
  부재·`null`·정상 셋을 모두 넣어야 한다 — 부재와 정상만 넣으면 통과하면서 `null` 을 못 잡는다.
- **관대 디코딩(`lenient`/`Lossy`)을 유지하려면 신뢰경계의 값 범위 검증이 짝으로 와야 한다.** 관대 디코딩은
  "한 필드가 깨져도 도감을 안 날린다"를 얻는 대신 "말이 안 되는 값도 통과시킨다"를 떠안는다. 자기 앱이 쓴
  파일만 읽을 땐 무해하지만, **외부 파일을 읽는 경로가 생기는 순간 그 트레이드오프가 라이브가 된다** —
  `Int.max` 같은 값이 그대로 저장되면 이후 산술이 Swift 오버플로 트랩으로 프로세스를 죽이고, 재기동해도
  같은 파일을 읽어 다시 죽는다(`load()` 의 `.corrupt` 복구는 디코드가 *성공*하므로 발동 안 함 → 파일을
  손으로 지우기 전까지 앱 사용 불가). 방어는 다운스트림 산술 지점마다가 아니라 **값이 들어오는 경계 한
  곳**에서(`SaveTransfer.sanitized`). 자르는 대상은 산술에 쓰이는 수치뿐 — 도감·인벤토리 *항목*은 잘라내면
  데이터 손실이다. (딥리뷰 2026-08-03: SIGTRAP 재현.)
- **같은 규칙이 세이브 파일이 아니라 *외부에서 오는 모든 수치*에 적용된다 — 파싱 경계도 포함.** 위 규칙을
  "세이브 파일"로 좁게 읽은 탓에 사용량 로그 파서(`LocalUsageReader`)의 `intValue` 가 무방비로 남았고,
  같은 SIGTRAP 이 Codex·Claude·Gemini 세 경로에서 재현됐다(딥리뷰 2026-08-04). 사용량 로그도 앱이 쓴 게
  아니라 **CLI 가 쓴 외부 파일**이다 — 손편집·전송 손상·업스트림 버그가 그대로 들어온다.
  방어 지점은 추출기 하나(`LocalUsageReader.intValue`/`intOrNil`)이고, **상한을 `Int.max` 로 잡으면 안 된다**:
  클램프 자체는 통과해도 `output + thoughts` 처럼 파싱 직후 더하는 곳에서 다시 트랩난다. 합산 여유가 있는
  상한(`maxParsedTokenValue`)을 쓴다. 회귀 가드는 프로바이더별로 **테스트를 쪼개라** — 트랩은 프로세스를
  끝내므로 한 테스트에 몰면 뒤 케이스가 아예 실행되지 않는다.

## 외부 로그·사용량 소스

- **append-only SQLite watermark 루프를 프로바이더마다 복사하지 마라.** Cursor 와 Copilot 이
  같은 `didReset` / `highWater == 0` 규칙을 두 벌로 들고 있으면 한쪽만 고친 수정이 다른 쪽에 남는다
  (#157). 루프는 `scanIncrementalStores` 한 곳, 포맷만 콜백. 회귀는 공유 헬퍼 테스트 **그리고**
  Copilot-only / Cursor-only 각 경로(A\|\|B 의 B 단독)를 모두 밟아야 한다.
- **파싱 뒤에 걸린 필터는 출력을 줄이지 일을 줄이지 않는다.** `modifiedSince` 가 호출부에선
  스캔 창처럼 보이지만, 행 watermark 가 있는 리더에서만 창이다. 통문서 저장(Kiro 가 대화 JSON 을
  제자리 재기록)은 창을 파싱 *뒤에* 적용해서 읽기·`jsonObject` 비용이 그대로다(실측 30×80턴:
  리턴 0건도 37ms). watermark 를 못 쓰면 싼 게이트는 파일 자신의 signature 다 — 이미 있는
  `LocalAntigravityUsageReader.signature` 를 재사용한다(`.db`/`.sqlite3` + `-wal`, `-shm` 제외).
  첫 스캔은 기록된 signature 가 없어 건너뛰지 않고, 실패한 open 은 슬롯을 차지하지 않는다.
  `.kiro` 캐시는 `existing + loaded` 를 병합하므로 빈 스캔은 캐시를 지우지 않는다.
  signature 는 process-lifetime 맵이 아니라 `Cached` 의 `kiroSignatures` 로 entries 옆에 둔다 —
  month-key 가 바뀌면 `previous` 가 nil 이라 skip 도 같이 죽는다. skip 이 `existing` 없이
  남으면 `[] + []` 로 주/블록 합계가 0 이 된다(#179). (#178)
- **외부 로그 포맷은 *상위 소스의 writer* 로 검증한다 — 내 픽스처는 증거가 아니다.** 새 프로바이더 파서를
  쓸 때 "이렇게 생겼을 것"으로 픽스처를 만들면 파서와 픽스처가 같은 오해를 공유해 테스트가 전부 통과하면서
  실사용은 0 을 표시한다(#133: 봉투 래퍼 키를 `update` 로 봤으나 실제는 `params`, `timestamp` 는 ISO 문자열이
  아니라 Unix `u64` 초 — 실제 라인은 한 건도 안 잡혔다). 순서: ① 업스트림에서 *쓰는* 코드(직렬화 구조체·serde
  계약 테스트)를 열어 키·타입·의미를 확정 ② 그 계약으로 픽스처 작성 ③ 가능하면 실파일 1건 캡처. 특히
  **같은 스펠링이 표면마다 의미가 다를 수 있다**(Grok `inputTokens`=캐시 포함 durable wire vs `input_tokens`=캐시
  제외 헤드리스 투영) — 별칭으로 합치면 캐시분을 두 번 빼거나 두 번 더한다.
- **스토리지 컷오버는 옛 파일명만 보면 커스텀 루트도 0이다.** 업스트림이 `data.sqlite3` 에 쓰기를
  멈추고 `~/.kiro/sessions` JSONL 로 옮겼는데, 리더가 루트마다 sqlite 만 열면 Settings 의
  `~/.kiro` 추가 폴더가 no-op 가 되고 최근 사용량이 0 으로 보인다(#236). 규칙: ① 기본 루트 목록에
  *새* 레이아웃 경로를 넣는다 ② 커스텀 루트는 레이아웃으로 분류해 스캔한다(`data.sqlite3` 존재 여부로
  폴더를 버리지 마라) ③ 옛 스토어는 폴백으로 남긴다 ④ 픽스처는 writer 계약(실파일에서 뽑은
  envelope — tokscale/codeburn 의 Kiro 파서 테스트). 같은 파일에 크레딧 필드가 있어도 달러가 아니면
  `reportsCost` 를 켜지 마라. 가드: `testExtraRootFindsJsonlSessionsWithoutSqlite`·
  `testCliJsonlSessionIsReadFromWriterShapedEvents`·`testV3MessagesJsonlSessionIsRead` —
  JSONL 스캔을 끄면 이 셋이 빨개져야 한다(헬퍼 복사본이 아니라 프로덕션 `kiroEntries`).
- **Antigravity의 생성 시각은 `gen_metadata` 한 곳에 고정돼 있지 않다.** 구 포맷은
  `chat_start_metadata.created_at`에 시각을 넣지만, 현재 포맷은 그 필드를 비우고 `steps.metadata`에
  타임스탬프를 둔다(`8 finished_at`, 없으면 `1 created_at`). 토큰 필드는 유지되므로 `gen_metadata`만
  읽으면 오늘 사용량이 통째로 `nil`이 된다. 연결은 네 단계다: 구 포맷의 직접 시각 → `response_id`
  1:1(`steps.metadata` 의 `9.11`) → 같은 `execution_id`(`12`) 안에서의 등장 순서 → 스토어 mtime.
  **행 순서(`idx`)로 잇지 마라** — `gen_metadata.idx` 는 자기만의 조밀한 수열이라 같은 대화 안에서도
  `steps.idx` 와 분 단위로 어긋난다. mtime 이 최후수단인 이유는 스토어 하나에 값이 하나뿐이라
  대화의 앞선 날들을 마지막 기록일로 끌어오기 때문이다(실측: 신포맷 스토어 10개에서 11,523,909 토큰이
  하루 뒤로 이동하고 원래 날짜는 0이 됐다).
  **`steps` 는 종류를 가리지 않고 전부 읽는다** — 쿼리에 `step_type` 조건이 없다. `execution_id` 를 가진
  행은 generation 이 아니어도 순서 대응 후보 목록에 들어가므로, 3단계는 그 실행의 다른 step 시각을
  집어갈 수 있다(합성 스토어로 확인). 실제 스토어에서 이 혼입이 얼마나 되는지는 **아직 측정되지 않았다** —
  근거는 `created_at` 이 남아 있는 스토어와 대조해 ~2분 이내라는 것뿐이다. 좁히려면 `step_type` 값을
  실데이터로 먼저 확정하라: 테스트 픽스처의 `steps` 에는 그 컬럼 자체가 없어, 실측 없이 조건만 넣으면
  스토어를 통째로 못 읽는 쪽으로 무너진다. 회귀 가드는
  `testCurrentGenerationFormatUsesStepMetadataTimestamp`·`testTheJoinIsTheExecutionIdAndNotTheRowIndex`·
  `testStepTimesAreHandedOutInOrderWithinAnExecution`·`testStoreMtimeRemainsTheLastResort`.
- **usage 필드 이름만 보고 버킷을 합치지 마라 — 상위 writer/type 계약의 포함 관계를 확인한다.** Pi의
  `reasoning` 은 별도 output이 아니라 `output`의 부분집합인데 Gemini 원본의 별도 `thoughts` 처리와 같은
  방식으로 더하면 실사용량이 두 번 집계된다. 반대로 provider가 `thoughts`를 아직 output에 접지 않았다면
  빼면 안 된다. 회귀 픽스처는 `input + output + cacheRead + cacheWrite == totalTokens` 같은 **writer의
  불변식**을 함께 고정하고, 매핑을 고치면 해당 provider cache parser version을 올려 기존 blob도 재파싱한다.
- **새 provider를 추가할 때 reader/cache만 연결하면 Settings의 custom-root contract가 조용히 빠진다.** `CustomScanRoots`는
  provider별 `curatedRoots(for:)`와 실제 reader의 `CustomScanRoots.storedValue(for:)` 조회를 모두 registry로
  취급한다. Pi 추가 때 reader/cache/provider는 등록했지만 이 두 지점을 빠뜨려 CI의
  `testEveryRegisteredProviderConsultsItsOwnCustomScanRootsKey`가 `pi`만 잡았다. 회귀는 provider id 전체를
  소스 스캔하는 테스트를 유지하고, 새 provider마다 curated default와 runtime union을 함께 추가한다.
- **사용량 소스의 "복사·재기록" 경로를 먼저 찾아라 (이중집계·재날짜화).** 세션 fork·재생·서브에이전트는 같은
  지출을 여러 파일에 남기거나 시각을 다시 찍는다. 규칙: ① dedup 키는 *턴 자체* 의 전역 유일 id(파일·세션 경로를
  섞지 마라 — 복사본이 별건이 된다) ② 시각은 *기록* 시각이 아니라 *턴* 시각(fork 는 봉투 timestamp 를 새로
  찍는다 → 주/월 합계가 포크 시점으로 몰린다) ③ 부모에 접혀 들어오는 자식(서브에이전트) 세션은 제외.
- **로그 루트는 한 곳이 아니다.** Claude 사용 로그는 CLI 기본 위치 말고도 `CLAUDE_CONFIG_DIR`(콤마 다중),
  XDG 스타일 `~/.config/claude/projects`, 그리고 Claude Desktop 임베디드 세션(`local-agent-mode-sessions`/
  `claude-code-sessions` 아래 세션마다 자체 `.claude/projects`)에 남는다. 루트 추가는
  `LocalUsageReader.claudeProjectRoots` 한 곳에서만 한다. 임베디드 루트 탐색은 `.claude` 가 **hidden** 이라
  `skipsHiddenFiles` 를 켜면 조용히 0건이 된다 — 회귀 가드
  `testEmbeddedRootsFindHiddenClaudeProjectsDirs` 가 그 브랜치를 밟는다.
- **커스텀 스캔 루트는 기본 루트에 더하기만 한다.** 사용자가 지정한 조상 경로(`~`, 홈 폴더)를
  `normalizedRoots` 에 넣으면 짧은 쪽이 이기고 기본 `~/.claude/projects` 가 접혀 사라진다.
  `jsonlFiles` 는 `skipsHiddenFiles` 를 쓰므로 살아남은 `~` 은 `.claude` 아래로 내려가지 않고
  합계가 조용히 0 이 된다(#162-B). 가드: `testAncestorCustomRootDoesNotEvictCuratedDefault`.
  `skipsHiddenFiles` 자체는 건드리지 않는다. 저장 키는 `customScanRoots.<providerID>` —
  공용 키에 Claude 전용 값을 넣으면 일반화할 때 마이그레이션이 생긴다(#162-C, #177).
  조상 판정은 `extra + "/"` 접두사만으로 부족하다 — 커스텀이 `/` 이면 접두사가 `"//"` 가 되어
  기본 루트를 안 접는 대신 **디스크 전체를 스캔**한다. `/` 는 모든 경로의 조상으로 취급하고 버린다.
  Codex 세션-id 인덱스는 **모든 루트를 모은 뒤에** 한 번만 prune 하고, parent-closure 도
  루트 합집합 위에서 한 번만 확장한다. 루트마다 확장하면 커스텀 폴더의 fork 가
  `~/.codex/sessions` 의 부모를 못 보고 replay 를 이중 집계한다.
  OpenCode/Hermes/Cursor/Copilot/Kiro 의 30초 엔트리 캐시는 저장 시 `invalidateScanCache` 로
  비운다 — Claude 의 300초 루트 캐시만 비우면 추가 폴더가 TTL 동안 안 보인다.
- **GUI 앱은 셸 환경을 상속하지 않는다 — 환경변수로 설정되는 경로는 셸에 물어봐야 한다.** Finder/launchd 로
  뜬 `.app` 의 `ProcessInfo.processInfo.environment` 에는 `~/.zshrc` 의 export 가 없다. 그래서
  `CLAUDE_CONFIG_DIR` 같은 값을 프로세스 환경에서만 읽으면 **CLI·`swift test` 에서는 통과하고 배포된 앱에서만
  0 을 표시**해 재현이 안 된다. 레포에 이미 같은 부류의 해법이 있다(`BinaryLocator.shellResolve` 가 PATH 때문에
  `zsh -ilc` 를 띄운다) — 새 환경변수도 `BinaryLocator.shellEnvironmentValue` 로 조회한다. 단 셸 spawn 은
  실측 ~0.44s 라 **프로세스 생애 1회만**(`static let` lazy) 캐시하고, 주기적으로 갱신되는 캐시(TTL)에 묶지 마라 —
  그 값을 안 쓰는 대다수 사용자까지 갱신마다 비용을 문다.
- **위 규칙이 문서에만 있으면 다음 프로바이더가 그대로 어긴다 — 조회 지점을 하나로 모으고 테스트로 막아라.**
  실제로 그렇게 됐다: 규칙을 적어 둔 뒤 추가된 `OPENCODE_DATA_DIR`·`HERMES_HOME`·`COPILOT_HOME`·`GROK_HOME`
  네 개가 전부 `ProcessInfo.processInfo.environment` 직독으로 들어왔고, 해당 사용자는 배포된 앱에서만 조용히
  적은 숫자를 봤다. 원인은 구현이 아니라 **강제 수단의 부재**다 — 산문 규칙은 새 파일을 리뷰할 때만 작동한다.
  이제 조회는 `UsageEnvironment` 한 곳이고(이름은 `UsageEnvironment.names` 에 추가),
  `testNoProviderReadsUsageLocationEnvDirectly` 가 `Sources/` 를 스캔해 직독 지점을 실패시킨다(허용 목록은
  사용자 override 가 아닌 것만 — `SHELL`·`PTB_STATE_DIR` 등). 조회는 **이름 수와 무관하게 spawn 1회**로 묶는다
  (`shellEnvironmentValues`) — 이름마다 띄우면 프로바이더가 늘수록 기동이 그만큼 느려진다.
  프로세스 환경에 전부 있으면 셸을 아예 안 띄우는 분기도 함께 가드한다(`…SkipsShellLookup`).
  `export FOO=` 처럼 **빈 값은 미설정으로** 취급한다 — 값으로 받으면 없는 경로를 스캔하고 조용히 0 이 된다.
  **`UsageEnvironment.value("X")` 만 있고 `names` 에 `X` 가 없으면 영원히 nil 이다.** Kiro 는
  `environmentPaths("KIRO_CLI_HOME")` 로 읽고 있었는데 이름이 레지스트리에 없어, 셸에 export 해 둔
  값이 GUI 앱은 물론 프로세스 환경에서도 안 보였다. 같은 스윕에서 `CURSOR_DATA_DIR` 도 같은 구멍.
  가드: `testSourceLiteralEnvKeysAreAllRegistered` 가 Sources 의 `environmentPaths("X")` /
  `UsageEnvironment.value("X")` 리터럴을 `names` 와 대조한다(#236).
- **디렉터리 탐색은 깊이만 막으면 폭이 안 막히지만, 이름 기반 가지치기는 더 위험하다.** 깊이 가지치기는
  `> maxDepth` 가 아니라 `>= maxDepth` 에서 걸어야 한 단계 더 내려가지 않는다(전자는 상한+1 까지 방문).
  깊이 상한은 **실제 레이아웃 깊이를 테스트로 고정**하고 여유를 둔다 — 경계에 붙여 두면 상위 소스가 한 단계
  중첩하는 순간 조용히 0건이 된다(`testEmbeddedRootsDepthBoundaryMatchesRealLayoutWithHeadroom`).
  **이름으로 가지치는 목록에는 사용자 작업 트리가 될 수 있는 이름을 절대 넣지 마라** — 이름 하나가 *조상*
  으로 걸리면 그 아래 전부가 사라진다. 실측 회귀: 폭을 줄이려고 `uploads`·`outputs`·`build`·`target` 을
  넣었는데, `uploads`·`outputs` 는 실제 세션 레이아웃에 존재하는 디렉터리고 그 안에서 돌린 Claude 세션은
  정당한 루트다 → 원래 고치려던 "조용한 0건"을 그대로 재생산했다. 목록은 패키지·VCS 내부처럼 사용자 코드가
  아닌 것만(`node_modules`·`.git`·`venv`·`.venv`) 두고, 폭 제어의 주 수단은 깊이 상한으로 둔다.
- **가지치기·필터 테스트는 양방향으로 단언하라.** "제외돼야 할 것이 제외됐나"만 보면 "포함돼야 할 것이 함께
  잘렸나"를 못 잡는다. 위 회귀가 정확히 그렇게 통과했다 — `testEmbeddedRootsDoNotDescendIntoBulkDirectories`
  는 `node_modules` 가 잘리는 것만 확인했고, 같은 목록이 정당한 루트를 자르는 건 아무도 안 봤다. 짝이 되는
  가드가 `testEmbeddedRootsFindRootsUnderWorkDirectoryNames` 다.
- **락을 쥔 채 외부 프로세스를 기다리지 마라.** 캐시 갱신 락 안에서 로그인 셸 spawn(최대 8초 대기)이나
  파일시스템 전체 탐색을 하면, `UsageStore` 가 taskGroup 으로 병렬 fetch 하는 다른 프로바이더까지 그 뒤에
  줄 선다. 결과가 idempotent 하면 **계산은 락 밖에서** 하고 락은 필드 대입에만 쥔다(경합 시 중복 계산이
  블로킹보다 낫다).
- **자식 프로세스 출력은 드레인하되, 드레인에 별도의 짧은 상한을 두지 마라.** 파이프 버퍼(64KB) 데드락을
  막으려 백그라운드 드레인으로 바꾸면서 세마포어에 2초 상한을 걸었더니, **종료를 무한정 기다리던 이전 동작에서
  값을 얻던 경우가 nil 이 됐다**(실측 회귀). 셸이 exit 해도 rc 가 띄운 백그라운드 잡(zsh-async·zinit turbo 등)이
  stdout write end 를 쥐고 있으면 EOF 가 늦게 온다 — 드레인은 **전체 타임아웃의 남은 예산**을 줘야 한다
  (실측: 고정 2초 → nil / 남은 예산 → 4.03초에 값). 그리고 포기할 땐 `handle.close()` 로 리더를 깨워라 —
  안 닫으면 `readDataToEndOfFile` 에 박힌 워커 스레드가 호출마다 하나씩 영구히 쌓인다(재시도가 타이머로
  반복되는 상주 앱에서는 하루 수백 개).
- **두 개의 완화책을 동시에 바꾸면 각각은 옳아도 조합이 회귀가 된다.** 이름 가지치기 목록을 줄이면서(정확성)
  깊이 상한을 함께 올렸더니(여유) 열거량이 수백 배로 뛰었다 — 각 변경은 단독으로는 무해했고, 폭을 잡던 것이
  이름 목록이었는데 그걸 줄이는 순간 깊이가 유일한 제어가 됐기 때문이다. 완화책을 조정할 땐 **어느 쪽이 실제로
  비용을 잡고 있었는지 측정**하고 한 번에 하나씩 바꾼다. 최종값은 측정으로 정한다(실측: 깊이 6=놓침,
  7=전부 찾음·방문 100, 8·9=방문 그대로 → 7 이 "놓치지 않는 최소값이면서 비용이 안 느는 지점").
- **`precondition` 은 릴리스 빌드에서도 앱을 죽인다 — 테스트 전용 시임을 지키는 데 쓰지 마라.** 잘못 써도
  결과가 "테스트가 엉뚱한 대상을 본다"에 그치는 실수를 SIGTRAP 으로 키운다(`-Ounchecked` 아니면 안 사라짐).
  도달 불가한 곳이면 더더욱 값이 없다. 우선순위를 주석으로 적거나, 애초에 잘못 쓸 수 없는 시그니처로 바꿔라.
- **하위 레이어 호출이 비싼 초기화를 트리거하지 않는지 보라.** 안내 문구 하나를 고르려고 부른 함수가
  `static let` 첫 접근 → 로그인 셸 spawn 을 유발해, 자동 폴링 경로의 actor 를 수백 ms~수 초 막을 수 있다.
  값이 필요한 쪽(그 값을 실제로 쓰는 경로)에서 초기화를 트리거하고, 부수적 분기에서는 싼 소스
  (`ProcessInfo.environment`)만 본다.
- **유닛 테스트가 로그인 셸을 띄우면 hermetic 하지 않다.** 프로덕션 진입점(`claudeProjectRoots`)을 테스트에서
  직접 부르면 개발자의 `.zshrc` 가 실행되고, 그 기기에 `CLAUDE_CONFIG_DIR` 이 export 돼 있으면 결과가 달라진다.
  주입 시임(`computeClaudeProjectRoots(configDirValue:home:)`)으로 판정하고, 실환경 확인은 일회성 프로브로
  분리한다.
- **경로 dedup 은 심볼릭 링크를 풀고 대소문자를 무시해야 한다.** `standardizedFileURL` 은 `..`·`.` 만 정리하고
  링크는 그대로 둔다. `~/.config/claude` → `~/.claude` 링크 같은 구성에서 같은 트리를 두 번 열거·파싱하게 된다
  (합계는 전역 dedup 이 지키지만 스캔 비용과 캐시 blob 은 두 배). `resolvingSymlinksInPath()` 로 풀고
  비교 키는 소문자로 — macOS 기본 APFS 는 대소문자를 구분하지 않는다.
- **테스트 시임이 프로덕션 브랜치를 단락시키지 않는지 확인하라.** 다중 루트 순회를 넣고 시임은 단일 루트만
  받게 두면(`claudeRoot.map { [$0] }`) 기존 테스트 전부가 루프를 1회로 단락시켜, 실제로 도는 코드는 무테스트로
  남는다. 새 브랜치를 만들면 **그 브랜치를 밟는 시임**을 같이 만든다(`LocalUsageCache(claudeRoots:)` +
  `testMultipleRootsAreScannedAndDedupedAcrossRoots`, 단일 루트 대조군 포함).
- **파일 밖 상태에 의존하는 판정을 파싱 캐시 안에서 하지 마라.** `LocalUsageCache` blob 은 그 파일의
  `(path, mtime, size)` 로만 무효화된다. 옆 파일(예: Grok `summary.json` 의 `session_kind`)로 결정되는
  포함·제외를 파서 안에서 하면, 근거가 나중에 바뀌어도 파일이 안 바뀌어 판정이 영구히 굳는다. 그런 판정은
  파일 선택 단계(`collect(include:)`)에 둬 매 새로고침 재평가되게 한다.
- **캐시를 붙이는 순간 "다음 새로고침이 다시 읽는다"가 공짜가 아니다.** 부분 읽기(SQLITE_BUSY·손상 페이지)를
  버리는 가드는 **재시도가 실제로 오는 경우에만** 가드다. TTL 시절엔 만료가 재시도를 보장했지만
  `(path, mtime, size)` 키로 바꾸는 순간 그 보장이 사라진다 — 실패 결과를 *현재* signature 아래 blob 으로
  넣으면 파일이 가만히 있는 한 그 소스는 영구히 "사용량 없음"으로 읽힌다. 규칙: ① 읽기 결과를 `[]`·`nil` 로
  접지 말고 **실패와 빈 값을 구분하는 값**으로 돌려라(`LocalAntigravityUsageReader.ConversationRead`)
  ② 일시적 실패는 캐시에 **쓰지 말고** 이전 blob 을 *옛 signature 그대로* 이어받아 다음 스캔이 다시 읽게
  하라 ③ 영구적 사실(기대 테이블이 아예 없는 파일)만 빈 값으로 캐시한다 — 안 그러면 대화가 아닌 DB 를 매
  새로고침 재오픈한다. 같은 이유로 **창(window) 필터를 캐시 단위 안에 굽지 마라**: blob 은 그 창보다 오래
  살아서 다음 날 조용히 행이 빈다. 캐시는 무필터로 담고 조립 시점에 좁힌다(`assemble(_:since:)`).
  회귀 가드: `testIncompleteScanKeepsThePreviousRowsUnderTheirOldSignature`·
  `testUnreadableStoreIsNotCachedAsAnEmptyConversation`·`testDatabaseWithoutTheExpectedTableIsCachedAsEmpty`.
- **캐시 무효화 키에 *내 읽기가 건드리는 파일*을 넣지 마라.** WAL 의 `-shm` 은 읽기 전용 커넥션도 read mark 를
  쓴다. 키에 넣으면 스캔이 방금 쓴 blob 을 그 스캔 자신이 무효화해 **히트율이 영구히 0** 이 된다 — 교체하려던
  TTL 보다 나쁘다. 커밋은 `.db`(체크포인트)나 `-wal`(append) 에 반드시 남으므로 키는 그 둘의 최신 mtime +
  크기 합이면 충분하고, 같은 이유로 창 판정에도 `-shm` 은 무의미하다(그것만 새롭다 = 누가 *읽었다*).
  그리고 **stat 은 읽기 앞에서** 한다 — 뒤에서 하면 읽는 중에 들어온 커밋이 이미 최신처럼 보이는 signature 에
  굳어 영영 안 읽힌다. 회귀 가드: `testShmChurnDoesNotInvalidateTheBlob`·`testWalCommitInvalidatesTheBlob`.
- **실패가 흔적을 안 남기면 "안 썼음"과 구분되지 않는다.** 외부 소스 리더가 실패를 `[]`/`nil` 로 접으면 사용량
  0 과 같은 값이 된다. 프로바이더별 탭이 붙은 뒤엔 숫자가 조금 낮은 정도가 아니라 **탭이 통째로 사라진다**
  (`UsageStore` 는 `today != nil` 이거나 활성 블록이 있을 때만 스냅샷을 만든다). 로그를 남기되 세 가지를 지켜라:
  ① **판정은 순수 함수로 분리** — `AppLog.write` 는 `AppEnv.isBundledApp` 가드로 xctest 에서 조기 return 하므로
  로그 파일을 보는 테스트는 아무것도 커버하지 못한다(§알림의 같은 규칙). ② **양을 묶어라** — 읽을 수 없는
  소스는 매 새로고침 다시 읽히므로(기본 2분 = 720회/일) 대상마다 한 줄이면 2MB 로그가 하루에도 여러 번
  회전해 크래시 이력을 밀어낸다. 스캔당 상위 N개만 이름을 남기고 나머지는 개수로 접는다. ③ **영구적 사실은
  로그하지 마라** — "이 파일엔 그 테이블이 없다"는 바뀌지 않으므로 영원히 반복된다.
  회귀 가드: `testIncompleteScanDropsTheConversationAndNamesTheReason`·`testLossLogNamesAFewStoresAndCountsTheRest`·
  `testDatabaseWithoutTheExpectedTableIsNotReportedAsALoss`.
- **크기 상한이 없는 사용자 파일을 통째로 읽지 마라.** `String(contentsOf:)` 가 파일 크기만큼, 뒤따르는
  `split` 이 다시 그만큼 저장소를 만든다. 라인 단위 `autoreleasepool`(#94)은 `JSONSerialization` 객체는
  배출해도 **원본 문자열과 split 저장소는 못 놓는다** — 실사용에서 21 GiB Codex rollout 하나가 앱 풋프린트를
  20 GiB 까지 밀어올렸다. 전환은 `FileHandle` 청크 스트림(`forEachCodexLine`)이고 두 가지가 핵심이다:
  ① **개행 분할은 바이트 `0x0A` 로** — UTF-8 연속 바이트는 모두 ≥`0x80` 이라 개행이 멀티바이트 시퀀스
  안에 들어갈 수 없어 청크 경계에서 문자가 깨지지 않는다. ② **청크마다 `autoreleasepool` 경계를 둔다** —
  `FileHandle` 이 bridge 한 `Data` backing 이 바깥 풀까지 살아남아, 청크가 작아도 파일 전체를 읽을 때까지
  RSS 가 누적된다. #94 에서 "스트리밍이 오히려 메모리를 악화시켰다"고 판정한 원인이 이 경계 부재였다 —
  **그 판정을 근거로 스트리밍 자체를 배제하지 마라.** 실측(실기기 rollout 59개·201MB·최대 103MB, release):
  peak RSS 416→66 MiB, 파싱 14.25→2.16s, 엔트리 출력은 바이트 동일. **prefilter 는 표현에 달렸다** —
  `String.contains` 는 grapheme 스캔이라 넣으면 느려지고, 같은 판정을 `Data.range` 바이트 탐색으로 하면
  이득이다("파싱 줄 수를 줄이면 빨라진다"가 표현에 따라 참·거짓이 갈리는 자리). 아직 통째로 읽는 곳:
  `parseClaudeFile`·`parseGrokFile`(`String(contentsOf:)`), `parseGeminiFile`(`Data(contentsOf:)`).
  **의도적 보류다** — 근거 없는 일괄 전환은 #94 를 반복하므로 프로바이더별 실측 뒤에 바꾼다. 도달 가능한
  부류이긴 하다(실기기 Claude jsonl 863개, 최대 90MB). 회귀 가드: `CodexLargeRolloutPerformanceTests` —
  **opt-in(`POKETOKENBAR_RUN_LARGE_PERF=1` / `scripts/perf-codex-large-rollout.sh`)이라 CI 는 돌리지 않는다.**
  자동으로 막히지 않으므로 이 부류를 건드리면 직접 돌린다. (#184)

## 외부 동기화 (iCloud·CloudKit)

- **CloudKit 쓰기를 'fetch → 수정 → save'로 만들지 마라 — last-write-wins면 `.allKeys` 덮어쓰기 한 방이다.**
  fetch가 일시적 오류로 실패하면 `try?`가 삼키고 "레코드 없음"으로 재해석해 같은 recordName의 *새*
  CKRecord를 insert한다. 레코드가 이미 서버에 있으면 `serverRecordChanged`("record to insert already
  exists")가 매 폴링마다 **결정적으로** 실패한다(2026-08-20 실측: 21연속, 별도 etag 경합 "client oplock
  error"까지 발생). etag 협상을 요구하는 `CKDatabase.save` 편의 API 대신
  `CKModifyRecordsOperation` + `savePolicy = .allKeys` — fetch도 etag도 없이 서버 레코드를 통째로
  덮는다(`CloudKitSync.makeRecord`/`makeSaveOperation`). 회귀 가드:
  `saveOperationIsForceOverwriteWithoutPrefetch`(결함 주입 — `.allKeys` 제거 시 실패 확인) +
  `recordPayloadRoundTripsThroughJSONField`(iPhone이 복호화하는 json 필드의 인코딩 계약).
  CKContainer는 호출마다 새로 만들지 않고 프로세스 수명 static으로 둔다.
- **실행 중인 프로세스의 .app 번들이 지워지거나 교체되면 CloudKit는 그 프로세스를 영구히 파기한다.**
  "Client went away before operation could be validated"(CKError 1/2005)는 cloudd가 *작업 단위로* 클라이언트
  코드서명을 검증한다는 뜻이다 — Xcode rebuild/clean이 실행 중 앱의 번들을 대체·삭제하면 그 검증이
  이후 모든 작업에서 실패한다(실측: 같은 PID로 19:46–20:16 저장 성공 → 번들 교체 후 20:18부터 48연속
  실패, 재시작 전까지 자가회복 없음). **메뉴바 앱을 Xcode Debug 빌드(DerivedData)로 상시 운용하지
  마라** — DerivedData는 Xcode가 지운다. 동기화가 필요한 상시 실행은 안정 경로(/Applications)의
  자동 서명 빌드로 한다. 실패는 AppLog에만 남고 앱 UI는 멀쩡하므로(**조용한 부실**) iPhone의
  "Updated N ago"가 유일한 신호다 — 의심되면 `grep "CloudKit sync failed" ~/Library/Logs/PokeTokenBar.log`.
- **`build-app.sh` 산출물에는 iCloud 자격증명이 없다 — 크래시 루프다.** 스크립트의 codesign은
  `--entitlements`를 주지 않는데, 자격증명 없는 프로세스에서는 `CloudKitSync.save()`의
  `CKContainer(identifier:)` 초기화 자체가 SIGTRAP으로 프로세스를 죽인다(2026-08-20 오후 실측 —
  같은 날 오전의 "iCloud 동기화만 조용히 죽는다" 진단은 과소평가였다). launchd KeepAlive 에이전트가
  재실행을 반복해 **~8초 주기 크래시 루프**가 되고, 루프 사이 잠깐 폰 서버(HTTP)가 살아 있어
  "서버는 되는데 동기화만 죽는다"로 오진하기 쉽다. iCloud 동기화가 필요한 설치본은 xcodebuild
  (자동 서명, entitlements 포함) 산출물로 대체한다 — 실행 절차는 `dev-deploy.md`. **릴리스 빚**:
  `release.sh`가 이 스크립트로 배포하므로 CloudKit 시대 릴리스가 나가면 전 사용자 크래시 루프가
  된다. 다음 릴리스 전에 entitlements 서명 추가 필수.
- **에너지 절약 게이트는 화면 뒤의 사람만 고려한다 — 소비자가 기기 밖에 생기면 그 전제가 죽는다.**
  `UsageStore` 는 `screensDidSleepNotification` 에 폴링 타이머를 invalidate 했다(ccusage 서브프로세스
  spawn 절약). 화면이 유일한 소비자일 땐 옳았지만, iCloud 페이로드가 **refresh 완료 훅에서만** 나가면서
  (`onStoreRefreshed` → `buildAndPublishPayload` → `CloudKitSync.save`) 폴링 정지가 곧 **동기화 정지**가
  됐다 — Mac 이 깨어서 토큰을 쓰는 중에도 화면만 꺼져 있으면 iPhone 이 옛 숫자에 굳는다. 실측
  2026-08-29: `pmset -g log` 의 display off/on 구간과 `~/Library/Logs/PokeTokenBar.log` 의 `refresh done`
  공백이 초 단위로 일치(4h24m·32m, 그 사이 refresh 0건), 폰은 30분 기준으로 stale 표시.
  **테스트가 못 걸른 이유**: 폴링 정책에 테스트가 아예 없었고, 있었더라도 "화면 꺼짐 → 타이머 없음"을
  *스펙으로* 굳혔을 것이다 — 게이트를 넣은 PR 과 CloudKit 을 넣은 PR 이 달라 둘을 같이 보는 테스트가
  생길 자리가 없었다. 규칙: **절전 게이트를 넣거나 새 소비자(폰·위젯·외부 동기화)를 붙일 때,
  그 게이트가 멈추는 것이 화면 픽셀뿐인지 데이터 생산까지인지 확인한다.** 멈추면 안 되는 생산이면
  정지가 아니라 **감속**(`UsageStore.displayAsleepMinimumInterval` = 300s, 폰 stale 기준 30분보다
  넉넉히 짧게)이고, 감속 하한은 `max` 여야 한다(사용자가 더 느리게 잡았으면 빨라지면 안 된다).
  회귀 가드: `testDisplaySleepSlowsPollingInsteadOfStoppingIt`(타이머 **생존**이 핵심 단언 — 결함 주입
  확인 완료) · `testSlowPollWhileAsleepStaysAheadOfThePhoneStaleThreshold`(상수를 폰 기준에 기계로 건다) ·
  `testScreensDidSleepNotificationReachesTheStore`(정책이 옳아도 배선이 끊기면 무의미) ·
  `testManualModeStaysManualWhileTheDisplaySleeps`. **부류 스윕**: 같은 `screensDidSleep` 게이트가
  `AppDelegate.setDisplayAwake`(메뉴바 애니메이션)와 `FloatingPetPanel`(펫 호스팅 트리)에도 있으나
  둘 다 순수 표시라 그대로 둔다 — 기기 밖 소비자를 굶기는 건 `UsageStore` 하나뿐이었다.

- **서브 패키지 테스트가 깨진 채 PR이 머지됐다.** `PokeTokenBarSharedTests`의 `PhoneLimitStatus`
  초기화가 위젯 PR(#3)에서 추가된 파라미터를 못 따라갔는데 아무도 서브 패키지의 `swift test`를
  돌리지 않아 컴파일 조차 안 되는 상태로 지나갔다. 루트 패키지 게이트만 돌리면 잡히지 않는다 —
  `PokeTokenBarShared` 테스트도 게이트에 묶는다.

## 빌드·도구체인

- **SwiftUI `View`/`App` 경계는 `@MainActor` 를 명시한다.** Swift 6.3 은 `body` 밖의 `@ViewBuilder` helper·
  동기 클로저를 nonisolated 로 검사해, `@MainActor` `@Observable` store 접근이 수십 개의 오류로 연쇄된다.
  개별 프로퍼티에 `MainActor.assumeIsolated` 를 흩뿌리지 말고 UI 타입 선언 한 곳에 격리를 둔다.
  `SwiftUIIsolationTests.testEverySwiftUIViewAndAppIsMainActorIsolated` 가 새 View/App 선언 누락을 소스 스캔으로 막는다.
- **coverage profile producer와 consumer는 같은 LLVM toolchain이어야 한다.** Homebrew Swift 6.3 이 만든
  `default.profdata` 를 구형 Xcode의 `xcrun llvm-cov` 로 읽으면 `unsupported instrumentation profile format
  version` 으로 테스트 성공 뒤 게이트만 실패한다. `test-gate.sh` 는 현재 `swift` 실경로 옆의 `llvm-cov` 를
  우선하고, sibling이 없는 Apple toolchain에서만 `xcrun --find llvm-cov` 로 폴백한다.

## 자격증명·Keychain

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
  (설정 갱신·팝오버 `claudeLimitsRefreshRow`, `refreshLimitTokenFromKeychain`)에서만. 파일이 유효
  토큰을 들고 있으면 매 자동 폴이 그걸 다시 읽고, 파일이 없을 때만 캐시가 버티다가 만료 후 stale.
  회귀 가드: `testAutoRefreshUsesNoPromptPathManualUsesPromptPath`. (완전 근절은 Developer ID
  notarization 으로 '항상 허용' 승인을 안정화하는 것뿐 — 신뢰된 서명 신원이라야 ACL 승인이 지속된다.
  미도입.)
- **OAuth 갱신은 "성공했다"가 아니라 "우리 요청이 규격에 맞다"로 검증해야 한다 — 스텁은 그걸 못 본다.**
  #44 가 넣은 antigravity 자동 갱신은 **단 한 번도 성공한 적이 없다.** Antigravity 의 Google 클라이언트는
  confidential client 라 refresh_token 그랜트에 `client_secret` 이 필수인데 그게 빠져 있었고, Google 은
  매번 `400 {"error":"invalid_request","error_description":"client_secret is missing."}` 로 답했다.
  `refreshGoogleToken` 은 non-200 을 전부 `nil` 로 접었고 호출부는 `try?` 로 삼켜서, 증상은 **매시간
  (= 액세스 토큰 수명 3600s) Keychain 프롬프트** 로만 드러났다. 실측 로그의 실패 간격이 정확히
  00:19 → 01:25 → 02:26 → 03:31 이었다.
  *테스트가 왜 못 걸렀나*: `testAntigravityAutoPollRenewsExpiredTokenUsingRefreshTokenWithoutKeychain`
  이 `tokenRefresher` 스텁을 주입해 **성공을 흉내냈다.** 프로덕션이 실제로 조립하는 요청 바디는
  단언 대상이 아니었다 — 스텁 테스트는 "갱신 결과를 우리가 잘 다루는가"만 답하지 "우리가 보내는 요청이
  통하는가"에는 답하지 않는다. 외부 API 호출은 **바디 조립을 순수 함수로 떼어 단언하고**
  (`makeRefreshRequest` + `testRefreshRequestCarriesClientSecret`), 실계정 parity 테스트로 한 번은
  진짜로 통과시켜 본다(`AntigravityRefreshParityTests`, `PTB_PARITY=1` 에서만).
- **갱신 실패를 한 종류로 뭉치면 네트워크 블립이 Keychain 프롬프트로 승격된다.** `Credential?` 하나로는
  "refresh token 이 죽었다(`invalid_grant`)" 와 "지금 5xx/타임아웃이다" 가 구분되지 않아, 후자에서도
  캐시를 버리고 사용자를 프롬프트 경로로 몰았다. → `AntigravityRefreshOutcome` 으로
  `credentialRejected`(재취득 필요) / `clientRejected`(secret 이 틀림 — 다음 후보) / `transient`
  (캐시 유지, 다음 폴 재시도) 를 나눈다. 회귀 가드:
  `testTransientFailureKeepsCredentialForNextPoll` (결함 주입 확인 완료).
- **프롬프트를 없애려고 만든 갱신 버튼이 매 탭마다 프롬프트를 내면 안 된다.** antigravity 사용자 동작
  경로는 유효한 refresh token 이 디스크에 있어도 곧장 Keychain 을 읽었다. 순서를 **무프롬프트 Keychain
  읽기 → 보관된 refresh token 으로 갱신 → (마지막) 프롬프트 동반 읽기** 로 둔다. 무프롬프트 읽기를
  맨 앞에 남기는 이유는 계정 전환 반영이다(#227 부류 — CLI 가 항목을 새 계정으로 덮어쓴다).
  회귀 가드: `testUserTapRefreshesBeforeReachingTheKeychain`.
- **vendor client_secret 은 저장소에 넣지 않는다 — 평문 자격증명 파일의 가치를 낮게 유지한다.**
  `antigravity-credential.json`(0600)의 refresh token 은 **회전하지 않고** 스코프에
  `https://www.googleapis.com/auth/cloud-platform` 이 들어 있다(실측). secret 이 없는 동안 그 파일은
  단독으로는 아무것도 못 하지만, 공개 레포에 secret 을 올리면 **파일 유출 = 갱신 가능한 GCP 액세스**
  가 된다. → secret 은 이미 설치된 Antigravity 바이너리에서 런타임에 읽는다
  (`AntigravityClientSecret`). 로컬 공격자에게는 보안 경계가 아니며(같은 바이너리를 읽으면 된다)
  **유출된 파일 하나의 가치**만 낮추는 조치다 — 그 이상을 주장하지 않는다.
  바이너리 안에서 secret 두 개가 **구분자 없이 맞닿아** 있어 탐욕적 매칭은 둘을 한 덩어리로 삼킨다 →
  접두사마다 고정 28바이트로 끊는다(`testExtractsBothAdjacentSecrets`, 결함 주입 확인 완료).
  어느 쪽이 우리 client_id 의 짝인지는 **Google 의 `invalid_client` 응답으로 고른다** — 바이너리 내
  인접 문자열로 추정하면 다음 릴리스에서 조용히 깨진다.
- **form 바디 값에 `.urlQueryAllowed` 를 쓰면 안 된다 — 구분자를 통과시킨다.** 그 집합은
  `+`·`=`·`&`·`/` 를 이스케이프하지 않는다. 쿼리 문자열에서는 합법이지만
  `application/x-www-form-urlencoded` 바디에서는 `+` 가 공백으로 디코드되고 `=`·`&` 는 필드
  구분자다 — 그런 문자가 든 값은 **조용히 다른 값으로** 전달된다. Google 의 refresh token·
  client_secret 이 base64url 계열이라 지금은 실제로 안 깨지지만, 값의 문자 집합에 기대는 인코딩은
  계약이 아니라 우연이다. → `FormURLEncoding.value` 하나로 모으고 unreserved(RFC 3986)만 남긴다.
  발견 경로가 시사적이다: 폐기 요청의 *요청 조립* 을 순수 함수로 떼어 단언을 쓰다가 드러났다.
  게이트 뒤 네트워크 코드는 스위트가 한 줄도 실행하지 않으므로, 조립을 꺼내지 않았으면 갱신 경로에
  1년을 더 있었을 결함이다. 회귀 가드: `testRefreshBodyEscapesFormDelimiters`·
  `testRevokeRequestMatchesGoogleRevokeSpec`(둘 다 결함 주입 확인 완료).
- **폐기는 서버가 확인한 뒤에만 로컬을 지운다.** 순서를 뒤집으면(먼저 지우고 호출) 실패 시 사용자는
  재시도 수단을 잃고, 서버의 토큰은 살아 있는 채로 "정리됐다" 고 오해한다 — 보안 기능이 정확히
  반대 결과를 만든다. 회귀 가드: `testServerRejectedRevokeKeepsLocalCredential`.
- **모르는 나이를 지어내지 않는다.** `obtainedAt` 이 없던 기존 자격증명에 갱신 시점의 날짜를 찍으면
  몇 달 된 토큰이 "0일째" 로 보인다 — 그 숫자를 보고 폐기 주기를 정하려던 사용자에게 **폐기를
  미루는 방향** 으로 틀린 정보다. nil 은 nil 로 두고 "시작일 미기록" 으로 표시하며, 첫 재로그인
  때 정확해진다. 회귀 가드: `testLegacyCredentialAgeStaysUnknownRatherThanFabricated`.
- **평문 자격증명은 백업·디렉터리 권한까지가 노출면이다.** 앱 소유 Keychain 항목 금지(위 항목) 때문에
  자격증명은 Application Support 평문 0600 으로 산다. 그 결정은 유지하되 `~/Library/Application
  Support` 가 **TCC 게이트가 없고 Time Machine 기본 대상**이라는 점은 따로 막는다 —
  자격증명 파일만 `isExcludedFromBackup`, 상태 디렉터리는 0700(`CredentialFileProtection`).
  디렉터리를 통째로 백업 제외하면 안 된다 — companion 상태·한도 히스토리는 복원돼야 할 사용자 데이터다.
- **Claude 의 `refreshToken` 은 보이지만 우리가 쓰면 안 된다 — 갱신 시 회전되어 Claude Code 를 깨뜨린다.**
  키체인 항목(`claudeAiOauth`)에는 `accessToken`(수명 ~5h) 옆에 `refreshToken`·`refreshTokenExpiresAt`
  (~15일)이 함께 들어 있다. "그걸로 갱신하면 키체인 접근이 5시간마다 → 15일마다로 줄겠다"는 발상이
  자연스럽게 나오는데, **하면 안 된다.** Claude Code 바이너리 확인: 갱신은
  `POST {baseURL}/v1/oauth/token`(`grant_type=refresh_token`, `client_id`)이고 응답 처리 함수가
  `ltu(e,t) → { refreshToken: t.refreshToken, … }` 로 **저장된 refreshToken 을 응답의 새 값으로 교체**한다.
  즉 회전한다. 외부 앱이 대신 갱신하면 Claude Code 의 키체인 사본이 죽은 토큰이 되어 **재로그인**을 요구한다.
  피하려면 남의 자격증명 저장소에 write 해야 하는데 그건 위 '앱 소유 keychain 항목 금지' 가 막는 영역이다.
  **Antigravity 와 다른 이유가 여기 있다** — Google 은 회전하지 않아서 `AntigravityTokenCache` 가
  `refreshToken: refreshToken` 으로 기존 값을 그대로 재사용한다(`refreshGoogleToken`). 두 프로바이더의
  토큰 규약이 다른 것이지 Claude 쪽 구현 누락이 아니다.
  **확실도:** 회전은 "Claude Code 가 응답의 토큰으로 교체 저장한다"에서 추론한 것이고 실제로 갱신을
  걸어 확인하지는 않았다 — 틀렸을 때의 대가가 사용자의 주 도구 로그인 파손이라 시험 자체를 하지 않았다.
  판단 근거는 확률이 아니라 비대칭이다: **잘 돼야 #241 세션 키가 이미 더 완전하게 주는 것(간격 축소 vs
  프롬프트 제거)의 열화판이고, 잘못되면 Claude Code 가 깨진다.**
  같은 맥락에서 기각된 것: **사용자 경로에 무프롬프트 선시도를 덧대는 것**(Antigravity 방식). ACL 이
  승인돼 있으면 프롬프트 쿼리도 조용히 통과하고, 미승인이면 무프롬프트는 실패해 결국 프롬프트를 띄운다 —
  두 경로의 결과가 같아 얻는 게 없다. 패턴이 다른 프로바이더에 있다는 것만으로 이식하지 마라.
- **Antigravity 자격증명이 지속되지 않던 결함 — 영속 저장과 `refreshToken` 자동 갱신으로 해결.**
  Antigravity 공식 한도는 최초 갱신 후 1시간이 지나면 stale 로 떨어지고, 앱을 재시작하면 한도가 사라져
  매번 수동 갱신을 눌러야 했다("creds do not stick").
  **원인 (4가지 누적):**
  1. `AntigravityTokenCache` 가 인메모리에만 토큰을 보관해 앱 재시작마다 자격증명이 증발.
  2. Google OAuth 액세스 토큰은 약 1시간 후 만료되는데, 자동 폴(`allowKeychainPrompt: false`)이
     `refreshToken` 이 메모리에 있어도 사용하지 않고 `keychainInteractionNotAllowed` 를 던짐.
     Google `refresh_token` 은 키체인을 전혀 건드리지 않고 `https://oauth2.googleapis.com/token` HTTPS
     호출만 수행하므로 자동 폴에서도 안전하며, 회전하지 않는 장기 토큰이다.
  3. `fetch()` 에러 처리에서 403까지 `invalidate()` 로 보내 캐시와 `refreshToken` 을 통째로 지움
     (403 은 자격증명 만료가 아니라 계정 티어 문제임에도 파기).
  4. `readTokenFile` 이 토큰 객체 포맷을 파싱하지 못함.
  → **해결:**
  1. `SessionKeyStore` 와 동일하게 `AppStatePaths.directory().appendingPathComponent("antigravity-credential.json")`
     에 0600(소유자 전용) 평문 JSON 으로 자격증명(`accessToken`, `refreshToken`, `expiresAt`)을 영속.
  2. 자동 폴(`allowKeychainPrompt: false`)에서 토큰 만료 시 `refreshToken` 이 있으면 네트워크로
     자동 갱신하여 키체인 접근 없이(`KeychainReader.queryCount == 0`) 최신 상태를 유지.
  3. 사용자 동작 경로(`allowKeychainPrompt: true`)에서는 키체인을 읽어 새 자격증명을 캐시 및 파일에 갱신.
  4. 401 에서만 토큰 갱신을 시도하고 403 은 자격증명을 파기하지 않음.
  가드: `testAntigravityAutoPollRenewsExpiredTokenUsingRefreshTokenWithoutKeychain`,
  `testAntigravityRestoresPersistedCredentialOnLaunch`,
  `testAntigravityExpiredTokenWithoutRefreshTokenFailsSilentlyOnAutoPoll`,
  `testAntigravityInvalidateClearsPersistentStore`,
  `testAutomaticPathNeverQueriesTheKeychain`, `testManualPathDoesQueryTheKeychain`.
- **인메모리 토큰 캐시는 만료만 보면 안 된다 — 원본 파일이 다른 유효 토큰으로 바뀌었는지도 본다.**
  `/login` 으로 계정을 갈아타면 `~/.claude/.credentials.json` 이 새 토큰으로 덮이지만, 캐시가 옛
  토큰의 `expiresAt` 까지 그걸 무시하면 공식 5h/주 바가 이전 계정에 붙고 컴패니언 EXP 만 로컬
  jsonl 로 계속 오른다(#227). 자동 폴은 키체인을 안 읽으므로 **파일 peek 를 캐시 히트보다 앞에**
  둔다. 파일이 없거나 `"claudeAiOauth": null` 이면 캐시를 유지(로그아웃·`CLAUDE_CONFIG_DIR` 잔여
  파일 — 기존 `credentialsFileIsAccountOAuthMissing` 과 같은 이유). 같은 부류: Antigravity
  `jetski-standalone-oauth-token` 은 파일 로드 시 `expiresAt=nil` 이라 캐시가 만료로 풀리지 않는다.
  회귀: `testClaudeAutoPollPicksUpInPlaceAccountSwitch`·`testAntigravityAutoPollPicksUpTokenFileSwitch`.
  캐시-우선 early return 을 되돌리면 이 두 테스트가 실패해야 한다.
- **`kSecMatchLimitAll` 과 `kSecReturnData` 는 같이 못 쓴다 — macOS 가 errSecParam(-50) 으로 거절한다.**
  "서비스에 항목이 여럿일 수 있으니 전부 받아서 유효한 걸 고르자"는 발상 자체는 옳지만(#229), 한 번의
  `SecItemCopyMatching` 으로 *모든 항목의 데이터*를 받는 쿼리는 **파라미터 단계에서** 거절된다. 항목이
  없어서가 아니라 조합이 무효라서라, ACL 승인·항목 존재·재로그인 어느 것으로도 우회되지 않는다.
  결과는 조용한 전면 실패였다 — Keychain 에만 자격증명이 있는 사용자(파일 `~/.claude/.credentials.json`
  없음)는 수동 갱신을 눌러도 `keychainUnavailable(-50)` 만 나고 공식 한도가 **영구히** 안 떴다.
  → 두 단계로 나눈다: ① `kSecMatchLimitAll` + `kSecReturnAttributes` 로 `acct` 목록만 열거
  ② 계정마다 `kSecMatchLimitOne` + `kSecReturnData` 로 단건 조회. 계정 속성을 못 얻으면 스코프 없는
  단건 읽기로 폴백한다(항목이 하나뿐인 흔한 경우).
  **5-whys(왜 못 걸렀나):** 테스트가 `extractDataItems(from:)` 라는 순수 파서만 합성 배열로 검증했다.
  결함은 그 함수가 아니라 **그 함수에 값을 넘겨주는 쿼리**에 있었고, `SecItemCopyMatching` 은 테스트
  경로에 아예 없었다 — 결함 트리거와 다른 경로로 통과하는 전형이다. 딕셔너리 모양만 단정하는 테스트도
  같은 이유로 부족하다: 어떤 키 조합이 무효인지는 **Security 프레임워크만 안다.**
  가드: `testKeychainQueriesAreAcceptedBySecurityFramework` — 존재하지 않는 서비스명(매칭 0건이라
  ACL·프롬프트에 안 닿음)으로 프로덕션 쿼리를 실제 API 에 던져 `errSecParam` 이 아님을 단정한다.
  기대값이 "성공"이 아니라 **"파라미터가 유효하다"(`errSecItemNotFound`)** 인 게 요점이다.
  `kSecMatchLimitAll` 을 데이터 쿼리에 되돌리면 이 테스트가 빨개진다(주입 확인 완료).
- **앱 소유 keychain 항목 — 대안 4가지가 모두 막혀 있다(2026-08-30 스파이크). 다시 제안하기 전에 여기부터 읽을 것.**
  위 #58 항목의 근거는 "cdhash 가 바뀌어서"인데, **그 전제 자체는 틀렸다**: 인증서로 서명된 빌드의
  지정요구(DR)는 `identifier … and certificate leaf[subject.CN] = …` 라 cdhash 를 포함하지 않는다
  (Apple Development·자체서명 `PokeTokenBar Local` 둘 다 실측 확인). 그런데도 **결론은 그대로 유지된다** —
  이유가 다를 뿐이다. 넷 다 확인했다:
  1. **데이터보호 키체인(프롬프트 자체가 없는 경로)은 릴리스 빌드가 못 쓴다.** `build-app.sh` 의
     codesign 에 `--entitlements` 가 없어(의도된 것 — `dev-deploy.md` 의 CloudKit 크래시 항목) 릴리스
     번들에는 자격증명이 전혀 없다. application-identifier 없이 `kSecUseDataProtectionKeychain` 는
     `errSecMissingEntitlement`.
  2. **외부 도구가 만든 레거시 항목을 앱이 조용히 읽을 수 없다.** 실측: 앱과 같은 신원으로 서명한
     바이너리를 `-T` 로 지정해
     `security add-generic-password -s … -T <서명된 바이너리>` 로 항목을 만든 뒤 그 바이너리가
     no-UI 로 조회하자 **120초+ 블록하며 SecurityAgent 다이얼로그**가 떴다
     (`kSecUseAuthenticationUI=fail` + `LAContext.interactionNotAllowed` 를 다 걸고도). 즉 `-T` 로 추가한
     항목은 사용자가 직접 누른 '항상 허용' 과 **동등하지 않다**. 자동 폴 경로에서 이 블록은 허용 불가다.
  3. **앱이 자기 항목에 토큰을 복사해 둬도 문제가 안 풀린다.** 복사본도 16시간 뒤 만료되고, 새 토큰은
     Claude 항목에서만 오는데 그 읽기는 사용자 동작 전용이다 — 만료 트레드밀이 옮겨갈 뿐이다.
  4. 그래서 **파일 미러가 현재로선 최선의 절충**이다(0600 · Time Machine 제외 · refreshToken 미포함).
     파일 미러가 동작하는 이유는 `/usr/bin/security` 가 **사용자가 '항상 허용' 을 누른** 신뢰 항목으로
     Claude 자격증명을 조용히 읽기 때문이다 — (2)의 `-T` 항목과 결정적으로 다른 지점.
- **세션 키로 갈아타지 않고 파일 미러를 유지한다 (2026-08-31 결정 — 다시 제안하기 전에 읽을 것).**
  업스트림 #241 의 claude.ai 세션 키 경로는 Keychain 을 아예 안 건드리고 자동 폴링으로 갱신된다 —
  외부 미러가 하던 일을 퍼스트파티로 해준다. 그래서 "미러를 지우자"가 자연스러워 보이는데,
  **보관 형태가 같다**: `SessionKeyStore` 도 Application Support 평문 JSON(0600)이고, 앱 소유 Keychain
  항목 금지(#58)를 같은 이유로 따른다. 평문 자격증명 파일이 *사라지는* 게 아니라 *바뀌는* 것이다.
  - 미러가 든 것: Claude Code **액세스 토큰** — 약 16시간 만료, refreshToken 미포함. 유출돼도 자연 소멸.
  - 세션 키가 든 것: **claude.ai 세션 쿠키** — 수개월 유효, 웹앱 전체 권한. 유출 시 훨씬 넓고 오래간다.
  → 맞바꾸는 축은 *단순함*(launchd 에이전트·스크립트·`security` ACL 승인 제거) 대 *비밀의 수명·범위*다.
  이 기기에서는 **수명이 짧고 범위가 좁은 쪽**(미러 유지)을 골랐다. 세션 키 경로 자체는 정상이니,
  미러 운영이 부담이 되면 그때 다시 저울질하면 된다 — 다만 "더 안전해진다"는 전제로는 하지 말 것.

- **자격증명 "없음"과 "계정 로그인 없음"은 다른 안내다.** Claude Code 2.1.x 의 `Claude Code-credentials`
  항목이 MCP 서버 OAuth(`mcpOAuth`) 상태만 담고 계정 토큰(`claudeAiOauth`)은 안 담는 경우가 있다. 이때
  파싱 실패를 형식 오류로 뭉뚱그리면 "재로그인하면 된다"를 안내 못 해 한도 섹션이 원인 불명으로 사라진다.
  → `LimitsError.credentialMissingAccountOAuth` 로 구분해 재로그인 안내를 띄운다
  (`OAuthCredentialData.isAccountOAuthMissing`).
- **한도 프로바이더의 라이브 조회는 실행환경 게이트로 막는다 — 테스트의 스텁 주입에 기대지 마라.**
  `UsageStore.init` 의 프로바이더 기본값이 *실물*이라, 스텁을 주입하지 않은 테스트 구성은 진짜
  프로바이더를 쓴다(`AntigravityRateLimitsProviderTests` 는 antigravity 만 주입하고 claude 는 기본값).
  무프롬프트 경로가 키체인을 안 읽어 무해해 보이지만 그건 자격증명이 *파일*로 없을 때 얘기다 —
  `~/.claude/.credentials.json` 이 있는 기기(리눅스 Claude Code, 키체인을 파일로 미러링한 맥)에선
  그 경로가 성공해 **스위트가 사용자 실계정 토큰으로 usage·profile endpoint 를 친다**. 파일 없는
  기기에선 조용히 실패해 오래 안 보였다(스위트는 계속 초록 — 전형적 false confidence).
  → 게이트는 **네트워크 경계**에 둔다(`fetchStatus`, 그리고 Antigravity 의 `refreshGoogleToken` —
  토큰 재발급도 별개의 외부 호출이다): `guard AppEnv.isBundledApp || AppEnv.isParityRun`.
  `OpenCodeGoLimitsProvider` 에만 있던 게이트를 claude·antigravity 로 확장한 것이고, 새 한도
  프로바이더도 같은 규약을 따른다.
  **`fetch` 진입부(토큰 취득 앞)에 두면 안 된다** — 처음에 그렇게 넣었다가
  `KeychainAutoPathTests.testManualPathDoesQueryTheKeychain` 이 깨졌다. 사용자 경로의 키체인 조회가
  0 이 되면 짝인 자동경로 단언이 "아무도 키체인을 안 읽는다"로도 만족돼 #210 가드가 공허해진다.
  즉 **막을 것은 자격증명 읽기가 아니라 나가는 호출**이다. 두 계약이 충돌하는 것처럼 보이면
  경계를 옮겨서 둘 다 만족시킨다.
  회귀 가드: `LiveCredentialCallGateTests` — 프로바이더별 2건 + 소스 스캔
  (`testEveryNetworkingLimitsProviderIsGated`)으로 *다음* 프로바이더의 누락까지 막는다.
  스캔은 **주석 줄을 제외**한다 — 주석 처리된 guard 를 통과시키면 그 스캔은 아무것도 지키지 않는다
  (결함 주입 검증에서 실제로 통과시켰다).

- **⌘, 가 빈 창을 띄웠다 — 설정 화면이 팝오버 안에만 있는데 `Settings` 씬이 단축키를 가져간다.**
  SwiftUI `App` 은 Scene 을 최소 하나 요구해서 `Settings { EmptyView() }` 를 뒀는데, macOS 가 거기에
  ⌘, 를 고정 연결한다. 눌러도 아무것도 없는 창이 떴다(사용자 보고 2026-09-02). 씬을 없앨 수는 없다 —
  다른 최소 씬은 *실제* 창을 띄워 더 나쁘다. → 앱 메뉴의 그 항목을 우리 액션으로 돌려 팝오버의 설정
  화면을 연다(`SettingsMenuItem.retarget`).
  함정 둘, 둘 다 실측으로 드러났다:
  ① **셀렉터로만 찾으면 못 찾는다.** SwiftUI 가 만든 항목은 `showSettingsWindow:` 도
  `showPreferencesWindow:` 도 아니었다. 항목이 눈앞에 있는데 조용히 폴백으로 떨어졌다.
  → 셀렉터 우선, 실패 시 **⌘, 키 조합** 으로 찾는다. 우리가 가로채려는 계약이 곧 그 키다.
  (제목 매칭은 애초에 답이 아니다 — "설정…"으로 번역돼 한국어 시스템에서만 실패한다.)
  ② **리타깃 시점은 첫 활성화다.** `.accessory` 앱의 메인 메뉴는 앱이 처음 활성화될 때 만들어져
  `applicationDidFinishLaunching` 과 그 다음 런루프에는 아직 없다 →
  `applicationDidBecomeActive` 에서 돌린다.
  폴백(`SettingsSceneBridge`)은 남겨 둔다 — 위 둘 다 문서화된 API 가 아니라, 실패하면 빈 창으로
  되돌아가는 대신 창을 닫고 팝오버를 연다. 회귀 가드: `SettingsMenuItemTests`(결함 주입 확인 완료).

## 로그 잡음

- **폴마다 반복되는 상태 줄은 회전으로 진단 이력을 밀어낸다.** 실측 2026-08-30: 로그 9,093줄 중
  미설치 프로바이더의 `phase1 recv id=<id> today=nil err=none`·`codex limits skipped`·
  `antigravity limits unavailable` 류가 507회씩 반복돼 약 60%를 차지했다. `AppLog` 는 2MB 에서
  1세대 회전이라(`maxBytes`), 이 잡음이 정작 필요한 "장애 직전 컨텍스트"를 밀어낸다 — 회전이 잦아
  이력이 사라지던 것은 이미 알려진 문제였는데 원인의 다수가 이 반복 줄이었다.
  → `AppLog.writeIfChanged(key:_:repeatAfter:)`. 판정은 `LogRepeatSuppressor`(순수)에 두고
  `AppLog` 는 잠금만 책임진다 — `AppLog.write` 는 `swift test` 에서 no-op 이라 파일로 검증할 수 없다.
- **억제는 상태 *전이* 를 절대 삼키면 안 된다.** 메시지가 달라지면 즉시 기록한다. 같은 상태가
  길게 이어져도 `repeatAfter`(기본 1시간)마다 한 번은 남긴다 — 그게 없으면 로그가 조용한 건지
  앱이 멈춘 건지 구분할 수 없다. 회귀 가드: `LogRepeatSuppressorTests`.
- **키는 프로바이더별로 나눈다.** 한 키로 묶으면 한 프로바이더의 변화가 다른 프로바이더의 억제를
  풀어 잡음이 그대로 돌아온다(`testKeysAreIndependent`).
- **값이 매 틱 변하는 줄에는 쓰지 마라**(토큰 수·합계). 억제가 걸리지 않아 이득 없이 잠금만 든다.

## 외부 API 가정

- **Antigravity 공식 한도 403 은 "계정 요금제" 문제다 — 무료 tier 면 안 나오고, AI Pro 로 올리면 나온다
  (2026-08-31 실측). 이 항목은 세 번 틀린 끝에 확정된 것이라, 다시 파기 전에 끝까지 읽을 것.**
  - `v1internal:retrieveUserQuotaSummary` 가 403 + "You do not have a valid license of this product"
    를 돌려주면 **말 그대로 그 계정에 라이선스(유료 tier)가 없다는 뜻**이다. 사용자가 free tier 에서
    **AI Pro 로 업그레이드하자 즉시 정상 동작**했다:
    `antigravity limits refreshed [Gemini Models: gemini-weekly=0.0%, gemini-5h=0.0% | Claude and GPT models: …]`.
  - **틀렸던 해석들**(같은 길로 다시 가지 말 것): ① "CLI 자격증명이라 안 된다" — CLI 가
    `retrieveUserQuotaSummary` 를 호출하지 않는 건 사실이지만 **권한과는 무관**했다. ② "IDE 를 깔면
    된다" — IDE 설치만으로는 안 됐다. ③ "소비자 계정용 quota API 가 없다" — 있다. 요금제 문제였다.
  - **가장 뼈아픈 지점: 답은 이미 수집한 진단 출력 안에 있었다.** 프로브가
    `currentTier(id=free-tier …)` 와 `allowedTiers …(id=standard-tier, description=Unlimited …)` 를
    그대로 찍어 줬는데, "quota 수치가 없다"만 보고 티어 필드를 '마케팅 문구'로 치부했다.
    → **프로브가 "찾던 값이 없다"고 나오면, 같은 응답의 *식별자* 필드가 질문 자체를 다시 정의하는지
    본다.** 없는 것만 보고 있는 것을 지나치기 쉽다.

- **모르는 응답의 스키마는 값이 아니라 키만 로그로 확인한다.** 이 조사의 두 단계 모두 진단 로그로
  풀렸다(403 본문 → 라이선스 문구, 키 구조 → quota 필드 부재). 값을 통째로 남기면 계정·프로젝트
  식별자가 함께 남으므로, 포함 필드는 **화이트리스트**로 고정한다(제외 목록은 새 필드가 생기면 샌다).
  진단 코드는 답이 나오면 **제거한다** — 이 두 프로브(#34·#35)는 그렇게 들어왔다 나갔다.

## HTTP 상태 해석

- **401 과 403 을 같이 묶지 마라 — 안내가 달라진다.** 401 은 "인증 안 됨"(재로그인이 답), 403 은
  "인증은 됐고 이 메서드를 쓸 권한이 없음"(재로그인으로 안 풀림)이다. 둘을 `authExpired` 하나로
  묶으면 고쳐지지 않는 조치를 사용자가 반복한다. 실측 2026-08-31: Antigravity **CLI** 자격증명으로
  `v1internal:retrieveUserQuotaSummary` 를 부르면 403 이고(CLI 는 이 메서드를 아예 호출하지 않는다 —
  IDE 전용), 그 결과 "세션 만료, 재로그인" 안내가 영구 표시됐다.
  → `updateAuthExpired`·antigravity catch 모두 **401 에서만** 만료로 판정.
  회귀 가드: `testLimitsAuthExpiredNotSetOn403`, `testAntigravityAuthExpiredSetOn401ButNotOn403`.
- **만료 안내가 재시도 수단을 가리면 막다른 길이 된다.** `PopoverView` 는 `authExpired` 일 때
  갱신 행 **대신** 안내를 그린다. 플래그는 성공해야만 풀리는데 CLI 사용자는 성공할 수 없어,
  사용자가 스스로 빠져나올 방법이 없었다. 상태 플래그를 세울 땐 "이 상태에서 사용자가 할 수 있는
  행동이 남아 있나"를 함께 본다.
- **실패 원인은 상태코드가 아니라 본문에 있다.** 401/403 본문을 잘라서라도 남긴다
  (`antigravity limits http 403: …`). 안 남기면 원인 추적이 남의 로그 고고학이 된다 — 이 건도
  `~/.gemini/antigravity-cli/log` 를 뒤져 "CLI 는 그 메서드를 호출하지 않는다"를 알아냈다.
  자격증명은 요청 헤더에 있지 응답 본문에 없으므로 본문 기록은 안전하다.

## 폴링 주기

- **사용자 설정 주기로 외부 endpoint 를 두드리지 마라.** `refreshInterval`(1~15분)은 *로컬 파일 스캔*
  주기인데 한도 조회가 같은 틱에 묶여 있어, 2분으로 두면 비공식 endpoint 를 2분마다 호출해 429 가
  반복됐다(실측 2026-08-30: `rate-limited: backing off 300s` 연속). 사용자는 "사용량을 자주 갱신"을
  고른 것이지 "endpoint 를 자주 호출"을 고른 게 아니다 — **설정의 의미와 부작용을 분리**한다.
  → `LimitsPollCadence`(5분) 게이트를 원격 한도 프로바이더에 공통 적용.
- **429 백오프는 이 게이트를 대체하지 못한다.** 백오프는 이미 맞고 나서 물러나는 *사후* 대응이라,
  매번 한 번은 맞고 시작한다. 사전 간격 게이트와 겹쳐서 쓴다.
- **간격은 시도(성공·실패 무관) 기준으로 센다.** rate limit 은 요청 수를 세지 성공 수를 세지 않는다.
  성공 기준으로 재면 실패가 이어질 때 무제한으로 재시도한다.
- **같은 판정을 프로바이더마다 새로 만들지 마라.** OpenCode Go 에만 있던 `opencodeGoPollInterval`
  (동일한 5분·시도 기준)을 claude·antigravity 가 공유하지 않아 두 프로바이더가 그대로 노출돼 있었다.
  공용 `LimitsPollCadence` 로 합쳤다 — 한쪽만 고쳐지고 다른 쪽이 남는 게 이 부류의 재발 경로다.
- **사용자 동작 경로는 간격을 우회하되 시도 시각은 기록한다.** 우회만 하고 기록을 빼면 누른 직후의
  자동 폴이 같은 endpoint 를 즉시 다시 호출한다.

## 네트워크 서비스 노출

- **LAN 에 여는 서비스는 "로컬 바인딩"이 아니라 인증으로 막는다.** `PhonePayloadServer` 는
  `NWListener(using: .tcp)` 라 **모든 인터페이스**(`*:7845`)에 바인딩되고 Bonjour(`_poketokenbar._tcp.`)로
  광고까지 해, 같은 네트워크(카페·호텔·컨퍼런스)의 누구나 발견해서 사용량·한도·플랜·도감을 읽을 수 있었다.
  루프백 바인딩은 해법이 아니다 — 폰이 LAN 에서 붙는 것이 이 기능의 존재 이유다. → 페어링 코드
  (`PhonePairingCode`, 32^8) + `Authorization: Bearer`. 판정은 `PhoneRequestRouter` 로 **순수 함수 분리**:
  `NWConnection` 에 묶인 `handleRequest` 안에 두면 인증 분기를 테스트할 방법이 없다.
- **빈 비밀은 모든 요청을 통과시킨다.** 코드가 아직 생성되지 않았거나 저장소에서 빈 문자열로 읽히면
  `"" == ""` 로 인증이 열린다. `isAuthorized` 는 `pairingCode.isEmpty` 를 **먼저** 거절한다.
  회귀 가드: `testEmptyPairingCodeRejectsEverything`.
- **비밀은 init 에서 생성했으면 그 자리에서 영속화한다.** Swift 의 `didSet` 은 init 대입에 안 돈다 —
  `UsageStore.init` 에서 생성만 하고 `defaults.set` 을 빼면 매 기동마다 코드가 바뀌어 폰이 영구히 401 이 된다.
- **`Access-Control-Allow-Origin: *` 를 습관적으로 붙이지 마라.** 붙이는 순간 위협이 "같은 LAN 의 기기"에서
  "사용자가 방문하는 아무 웹사이트의 스크립트"로 넓어진다. 폰 클라이언트는 브라우저가 아니라 CORS 가 필요 없다.

## 동시성

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

## 프로세스·인스턴스

- **로그인 실행을 LaunchAgent 로 등록하면 "등록하는 순간" 앱이 한 번 더 뜬다.** plist 의 `RunAtLoad` 는
  로그인 때만이 아니라 **에이전트가 로드되는 시점**의 실행을 뜻하고, `SMAppService.agent.register()` 가
  곧 그 로드다. 앱이 떠 있는 채로 등록되는 경로가 둘이라 둘 다 아이콘이 두 개가 된다 — 설정 토글
  (`LoginItem.setEnabled(true)`)과 구 로그인아이템 사용자의 업데이트 첫 기동
  (`migrateFromLegacyLoginItemIfNeeded()`). 후자는 **사용자가 아무것도 누르지 않아도** 일어난다.
  **LaunchServices 의 중복 실행 방지를 믿지 마라** — GUI 로 여는 경로(Finder·`open`)에만 걸리고
  launchd 는 `Contents/MacOS/…` 를 직접 exec 한다. **피해는 아이콘이 아니라 상태다**: 두 인스턴스가
  `CompanionStore`·`UsageStore` 를 같은 파일에 각자 써서 저장이 last-writer-wins 가 되고, 진화·사용량이
  조용히 덮인다. 방어는 기동 지점 한 곳에서 판정하고
  (`SingleInstance` — 나중에 뜬 쪽이 물러난다) **메뉴바 항목을 만들기 전**에 둔다. 위치는
  `CrashReporter.install` **앞**이어야 한다: 뒤면 물러나는 인스턴스가 running 마커를 덮어쓰고 종료 시
  `markClean()` 이 발화해, 살아남은 쪽이 나중에 크래시해도 다음 실행이 정상 종료로 읽는다.
  물러나기 직전 로그는 `AppLog.writeAndFlush` 로 밀어낸다 — `write` 가 async 라 `terminate` 이 `exit(0)` 에
  닿으면 사라지고(실측 100회 중 42회), 그 줄이 없으면 가드 오작동("앱이 안 뜬다")과 크래시를 구별할
  단서가 없다. **대가를 함께 적어둔다: 물러나는 쪽이 launchd 소유라 살아남는 인스턴스는 워치독 밖이고,
  크래시 자동 재실행은 다음 로그인까지 꺼진다** — 메뉴바 앱은 로그아웃 없이 몇 주를 돌아 공백이 길다.
  반대 방향(먼저 뜬 쪽이 물러남)은 워치독을 즉시 지키지만 토글 직후 창이 사라져 크래시처럼 읽힌다.
- **프로세스 나이를 `NSRunningApplication.launchDate` 로 재지 마라 — launchd 가 exec 한 프로세스에선 nil 이다.**
  그 값은 LaunchServices 가 띄운 프로세스에만 기록된다. 하필 물러나야 할 쪽이 launchd 가 띄운
  인스턴스라, launchDate 로 판정하면 **가드가 통째로 무효인데 테스트는 전부 통과한다**(실측: 로그인
  에이전트가 띄운 인스턴스는 `launchDate == nil`, 같은 pid 의 `p_starttime` 은 정상). 커널
  `p_starttime`(`sysctl` `KERN_PROC_PID`)은 두 경로 모두에 남고 프로세스 간 비교도 성립한다.
  일반화: **판정을 순수 함수로 뺐어도 그 함수에 들어가는 입력이 무테스트면 결함은 입력 쪽에 산다** —
  입력을 읽어내는 층에도 가드를 따로 둔다. 회귀 가드: `SingleInstanceTests` 의 판정 8건 + 입력 3건
  (`testProcessStartTimeIsReadableForTheCurrentProcess`·`…IsPlausible`·`…IsNilForAnUnknownProcess`).
  시작 시각을 못 읽거나 같으면 아무도 물러나지 않는다 — 아이콘 하나 더 뜨는 것보다 둘 다 사라지는 쪽이 나쁘다.
- **async logger 는 exit 경로의 로거가 아니다.** `AppLog.write` 는 백그라운드 큐에 넣고 바로 돌아온다.
  같은 턴에 호출자가 `exit()` 에 닿으면 그 줄은 자주 사라진다(실측 100회 중 42회). 마커 파일처럼
  동기인 반쪽만 남으면 로그는 세션이 항상 비정상 종료된 것처럼 읽히고, **줄이 없다고 분기가 안 돈
  증거로 쓰면 안 된다**. `willTerminate` 의 `CrashReporter.markClean`(`clean shutdown`)과 중복 인스턴스
  yield 가 그 자리 — 둘 다 `writeAndFlush`(`queue.sync {}`). 판정은 주입된 sink 로 고정한다
  (`AppLogTests`) — `write` 는 `AppEnv.isBundledApp` 가드라 프로덕션 로그를 여는 테스트는 수정
  여부와 무관하게 통과한다. 부류 스윕: `write` 직후 `terminate`/`exit` 하는 자리를 전수하고
  `writeAndFlush` 로 묶는다. `AppLog.writeAndFlush` 는 테스트된 `backend.writeAndFlush` 를
  타야 한다 — `write()`+`flush()` 두 번째 쌍은 가드가 안 되고, `flush()` 만 빼면 스위트가
  초록인데 #174 가 다시 산다. (#174)

## 표시·UI
- **앱 언어와 시스템 로케일은 다른 축이다 — SwiftUI 가 스스로 만드는 문장은 로케일을 따른다.**
  `L` 문구는 `AppLanguage` 를 따르는데 `Text(_, style: .relative)` 는 `Locale.current` 를 따라, 한국어
  Mac 에서 앱을 영어로 쓰면 "Catch log" 옆에 "3시간 46분" 이 붙는 한 화면 두 언어가 된다. 팝오버 루트
  (`PopoverView.body`)에서 `.environment(\.locale, companion.language.displayLocale)` 로 내려 8곳
  (한도 7 · 포획 로그 1)을 한 번에 맞춘다. **`body` 안에서 줘야 한다** — `rootView` 조립 시점에 주면
  설정에서 언어를 바꿔도 팝오버를 다시 열기까지 안 바뀐다. 경계: 이 환경값은 SwiftUI 가 생성하는
  문장에만 걸리고 `TokenFormatter` 처럼 포매터를 직접 만드는 코드는 여전히 시스템 로케일을 쓴다
  (ko/en/ja 는 천 단위 구분자가 같아 차이가 안 보인다). 회귀 가드 `DisplayLocaleTests` 는 코드 비교로
  끝내지 않고 **그 로케일이 실제로 해당 언어의 상대 시각을 만드는지**까지 본다 — 코드만 비교하면
  `.current` 로 잘못 매핑해도 통과한다.
- **`.task(id:)` 키와 그 안의 재로드 가드는 같은 축 집합을 써야 한다.** 두 곳이 어긋나면 태스크는
  재실행되는데 안의 작업만 조용히 건너뛴다 — 실패가 화면에만 남고 로그엔 안 남는다. `SpriteView` 는
  `.task(id:)` 에 `종+shiny` 를 담고 내부 가드는 `loadedID`(종)만 비교해, 도감의 이로치 토글
  (종 고정·shiny 만 뒤집힘)에서 색이 바뀌지 않았다 — 재렌더 플래시를 막던 가드가 토글을 삼킨 것.
  판정은 순수 함수로 빼고(`SpriteView.needsReload` — `frameDelay` 와 같은 이유) 축마다 회귀 테스트를
  둔다(`SpriteShinyReloadTests`, 양방향 토글). 부류 스윕 확인분: `menuSpriteKey`("id-shiny" 포함)·
  `SpriteStore.cacheKey`(3축)·`DexEntryRow`(항목+언어) 안전 — `SpriteView` 만 결함이었다.
  같은 상태를 두 곳에 나눠 들면 재발하므로, 축을 늘릴 땐 `SpriteSubject` 처럼 주체 하나로 모으는 쪽이
  낫다(현재는 `loadedShiny` 가 subject 밖에 있어 반영 시점을 손으로 맞춘다).
- **지연 백필로 채워지는 데이터는 화면마다 트리거가 필요하다 — 새 화면은 그 트리거를 물려받지 않는다.**
  `DexEntry.names` 는 나중에 생긴 필드라 그 전 졸업분은 `nil` 이고, 포획 로그가 행이 뜰 때
  `dexResolveChainNames` 로 채워 왔다. 종 격자는 저장분만 읽어서 구버전 저장분이 `#41` 로 남았고,
  하필 격자가 기본 화면이라 로그를 눌러야 고쳐지는 상태가 됐다 — 자가치유가 *다른 화면*에 달려 있으면
  그 화면을 안 여는 사용자에게는 치유가 없다. 파생 화면을 새로 만들 땐 원본 화면이 하던 **조회·백필까지**
  같이 옮겼는지 본다(`DexGridView.task` → `backfillMissingDexNames`). 폴백(`#id`)은 저장하지 말 것 —
  저장하면 이름이 영구히 번호로 굳는다(`testBackfillRetriesAfterAnOfflineAttempt`).
  부류 스윕 확인분: 저장분을 읽는 소비자는 `DexEntryRow`(자체 백필 보유)와 격자뿐이고,
  `activeDexEntry`·`graduate()` 의 `line.names` 는 소비가 아니라 생성 지점이라 무관.
- **상태 뱃지의 문구와 판정은 같은 의미여야 한다.** 현재 개체에서 파생된 도감 칸은 알을 새로 사거나
  (`buyEgg` 는 `active` 만 버리고 `dex` 는 안 건드린다) 메타몽이 리빌하면(`pathIDs` 가 통째로 교체)
  사라질 수 있다. 이를 설명하려고 졸업 기록이 없는 모든 도달 단계에 `키우는 중`을 달면, 진화 뒤 이전
  형태까지 동시에 키우는 포켓몬처럼 읽힌다. `키우는 중`은 저장 안정성이 아니라 현재 상태를 뜻하므로
  `id == active.currentID` 인 현재 형태 한 칸에만 표시하고, 지나온 형태에는 아무 뱃지도 표시하지 않는다.
  이전 형태의 휘발성을 안내해야 한다면 `키우는 중`을 재사용하지 말고 별도 개념으로 설계한다. 회귀는
  2단계 도달 상태의 `[false, true]`, 졸업한 라인을 다시 키우는 상태의 `[false, true, false]`, 현재 개체가
  없는 졸업 기록의 전부 `false`를 함께 고정한다.
- **뱃지로 설명하려던 휘발성은 애초에 없애는 게 답이었다.** 위 항목이 남긴 숙제 — "이전 형태의 휘발성을
  안내해야 한다면 별도 개념으로" — 의 결론은 새 뱃지가 아니라 **휘발 자체를 제거**하는 것이다. `buyEgg` 가
  `active` 만 버리고 `dex` 를 안 건드린 탓에, 현재 개체에서만 오던 종이 통째로 도감에서 빠져 종 수가 줄었다.
  수집 화면이 "쌓이기만 한다"는 약속을 주는데 이게 그 약속을 깨는 유일한 경로였다. 이제 놓아준 개체를
  `releasedAt` 을 단 `DexEntry` 로 `state.dex` 에 남긴다 — 도감(`dexSpecies`)이 `state.dex` 를 접으므로 종
  보존은 자동으로 따라오고, 포획 로그만 `놓아줌` 뱃지로 졸업분과 구분한다. 규칙 셋: ① **도달분만 기록**
  (`pathIDs.prefix(stageIndex + 1)` — `plannedPathIDs` 를 쓰면 알을 사서 포기하는 게 도감을 채우는 지름길이
  된다) ② 이로치는 `currentIsShiny`(위장 메타몽은 리빌 전까지 숨김 — 놓아주기가 리빌 수단이 되면 안 된다)
  ③ `collectedFinals` 는 그대로 — 끝까지 키운 게 아니므로 최종체 완성·분기 가중에 넣지 않는다.
  `releasedAt == nil` 이 곧 "졸업분"이라 구버전 저장분에 마이그레이션이 필요 없다. 부수 효과로, 놓아준 종을
  가리키던 **대표 선택이 이제 유지된다**(예전엔 종이 사라져 `reconcileRepresentativeSelection` 이 해제했다).
  가드: `testReleasedSpeciesStaysInTheDex`·`testReleasingMidChainCreditsOnlyReachedForms`·
  `testReleasingDisguisedDittoKeepsShinyHidden` — 기록을 빼거나 `plannedPathIDs` 로 바꾸면 실패한다(주입 확인).

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
- **수동 관찰(withObservationTracking) 표면은 companion 직접 변이 경로까지 추적해야 한다.** SwiftUI
  표면(팝오버·플로팅 펫)은 읽는 속성을 자동 추적하지만, AppKit 수동 관찰(`AppDelegate`)은 *등록한 속성만*
  본다. 메뉴바 스프라이트 갱신이 `observeStore`(=`store.menuTitle`)에만 걸려 있으면 store 틱 없이
  companion 만 바뀌는 경로 — 사탕 진화·졸업(`useRareCandy`), 세이브 가져오기(`applySave`),
  `hatchIfNeeded`·`revealDitto` 의 async 완료 — 는 다음 사용량 폴링(기본 120s)까지 이전 포켓몬이
  메뉴바에 남는다(사탕 졸업 직후 잔상 리포트). 같은 부류의 선례가 `UsageStore.onRefresh` 주석(한도
  변경이 menuTitle 미변경으로 companion 에 안 전달)이다. 표시가 파생되는 원천(`currentSpeciesID`·
  `currentIsShiny`)을 직접 추적하는 관찰 루프를 별도로 건다(`AppDelegate.observeCompanionSprite`).
  회귀 가드: `testCandyGraduationFiresSpriteIdentityObservation` — AppDelegate 쪽 배선은 AppKit
  (NSStatusBar)이라 헤드리스 테스트 불가, 관찰 계약(변이가 발화하는지)을 CompanionStore 쪽에서 고정.
- **메뉴바(상태아이템) stale dim 금지.** 시간 기반 stale(=`isStale`)로 `appearsDisabled` 를 켜면
  슬립/런치 직후 refresh 완료 전 몇 초간 메뉴바가 회색이 돼 '고장/비활성'으로 오인된다(사용자 반복 지적,
  `&& lastUpdated != nil` 로 런치만 막는 건 슬립-후 stale 을 못 막음). '오래됨' 신호는 팝오버에서만.
- **UI 변경 → 스크린샷 stale** 은 `release.sh` 가 자동 경고(`CLAUDE.md` §릴리스) — 통과의례화 방지.
- **첫 화면 선택을 비동기 판정 *전*의 동기 상태로 갈라 놓지 마라 — 완료가 그 화면을 교체한다.** iOS 루트
  화면이 `host.isEmpty && payload == nil` 같은 동기 상태만으로 갈리면 기동 직후엔 언제나 Setup(IP 입력)
  화면이 떴다가 ~1초 뒤 CloudKit fetch 완료가 대시보드로 교체했다 — 설정 화면이 1초짜리 플래시로 보인다는
  사용자 리포트. "아직 결정 안 됨"을 스토어 상태(`hasCompletedInitialFetch`)로 두고 첫 fetch 가 끝나기
  (성공·실패 무관, `defer`) 전엔 엔트리 화면만 보이게 한다. 부팅 게이트는 조건 분기 맨 앞이어야 하고,
  화면 자체의 `.task` fetch 로 완료를 기다리는 패턴이 바로 플래시의 원인이었다 — *완료가 자기를 렌더한
  조건을 무효화해 화면을 통째로 교체*한다. 부류 스윕: 동기 상태로 화면을 고르고 async 완료가 교체하는
  지점은 Setup 분기 하나뿐(호스트 설정 사용자의 `else` 진행 표시는 이미 ProgressView 라 무해). 회귀 가드는
  미포함 — iOS 앱 타깃에 테스트 타깃이 없어 xctest 불가하다(도입 시 이 플래그의 첫-방문 분기를 먼저
  검증할 것).
- **번역 가드는 "이미 표에 있는 문구"만 본다 — 표에 *못 들어간* 문구는 구조상 안 보인다.**
  `LocalizationInterpolationTests` 는 `L(lang)` 을 거친 문자열의 `\(...)` 보간이 언어마다 살아남는지
  검사한다. 그래서 `Text("Antigravity 세션 갱신 필요")` 처럼 애초에 `L` 을 안 거친 리터럴은 통과한다 —
  #210 이 이 경로로 한국어 3줄(`PopoverView` 세션만료 안내)을 넣어 전 언어 사용자에게 한국어가 보일
  뻔했다. 가드가 답하는 질문("번역이 인자를 지켰나")과 결함의 질문("이 문구가 번역 대상이긴 한가")이
  다른 층이다. 그래서 표를 검사하지 말고 **소스를 스캔**한다(`LocalizedUILiteralTests`):
  `Sources/PokeTokenBar/UI/**` 의 문자열 리터럴에 한글이 있으면 실패. 한국어 *주석*은 하우스 스타일이라
  허용해야 해서 정규식이 아니라 문자 순회로 문자열/주석 상태를 추적한다 — `"https://x//경로"` 처럼
  리터럴 안의 `//` 를 주석으로 오인하면 진짜 결함을 놓친다(역검증에서 이 케이스로 반증함).
  새 프로바이더 UI 를 붙일 땐 같은 부류의 형제 문구(여기선 `claudeAuthExpiredTitle/Hint`)를 먼저 찾아
  문안 구조까지 맞춘다 — 문구만 새로 지으면 같은 화면에서 두 안내가 다른 말투로 갈린다.
- **폰 미러 페이로드의 필드는 그 이름이 약속한 것만 담는다 — 합성 게이트를 넣으면 폰이 이유를 못 고른다.**
  `PhoneShopEntry.canAfford`("지갑이 가격을 덮나")에 `canBuyEgg`(= `hasActive && 잔액`)를 그대로
  실었더니, 상점 알 카드가 알 상태에서 목록에 남게 된 업스트림 변경(#261) 뒤에 폰이 잔액이 충분한데도
  "Not enough tokens" 로 그렸다. 게이트가 합성돼 있으면 폰엔 false 만 도착해서 **"왜 못 사는지"를
  고를 정보가 없다.** 축을 나눠 보낸다: 잔액은 `canAfford`, 상태 차단은 미리 현지화한 `lockedReason`
  한 줄(nil = 차단 없음), 표시 우선순위는 Mac 과 같게 상태 > 잔액. 폰이 표시만 하는 미러라 해도
  **판정 이유는 Mac 이 쪼개서 보내야** 한다 — 폰은 게임 규칙을 재현하지 않는다.
  선례상 이 결함은 매핑을 쓸 때가 아니라 *업스트림이 화면 규약을 바꿀 때* 드러난다. 업스트림 동기화가
  Mac UI 의 표시 규약(무엇이 목록에 남나·무엇이 비활성으로 보이나)을 건드리면 `phoneShopEntries`
  같은 미러 매핑과 iOS 뷰까지 같은 커밋에서 따라가는지 본다 — 미러는 컴파일로 깨지지 않아서
  테스트가 없으면 조용히 어긋난다. 부류 스윕 확인분: 아이템 쪽 `canAfford: canBuy(kind)` 도 보유형
  중복구매 금지를 합성해 담지만, `isOwned` 가 별도 축으로 같이 가고 iOS 뷰가 그 축을 먼저 분기해
  잘못된 라벨이 나오지 않는다 — 축이 하나 더 붙으면 같은 결함이 된다.
- **폰 페이로드에 필드를 더할 땐 옵셔널 + 구 페이로드 디코드 테스트가 짝이다.** `PhonePayload` 는 구버전
  Mac 을 위해 섹션 단위로 `decodeIfPresent` 하는데, 그 안의 원소 타입이 새 **비옵셔널** 필드를 요구하면
  원소 디코드가 던지고 섹션이 통째로 `[]` 이 된다 — 새 폰 + 구 Mac 조합에서 화면 하나가 빈다.
  새 필드는 옵셔널(합성 Codable 이 `decodeIfPresent` 로 읽는다)로 넣고, 그 필드가 없는 JSON 을 직접
  디코드하는 테스트를 같이 넣는다(`testShopEntryDecodesLegacyPayloadWithoutLockedReason`).

## 에너지 (상시 표시 애니메이션)

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
  diff-gate(동일 프레임 객체 재대입 스킵 — 애니 프레임은 서로 다른 객체라 정상 통과) + GIF fps 하한
  (`AppDelegate.menuFrameFloor`, 당시 0.4s≈2.5fps) + `Timer.tolerance` 0.5(코얼레싱)로 ~5 wakeup/s(−89%),
  애니메이션 유지. **캡 값 자체는 튜닝 가능하고 0 만 금지**다 — 세 대책 중 CPU 14%의 주범은 CA 전환·팝오버
  상주였고 fps 캡의 몫은 wakeup 을 프레임 수에 비례해 줄이는 것뿐이다(22px 에서도 2.5fps 는 느리다는
  지적이 있어 값을 사용자 선택으로 열었다 — `UsageStore.AnimationQuality` 의 0.4/0.2/0.1. CA 전환이
  제거된 뒤라 14% 당시와 같은 조건이 아니다. 단 **fps 를 올리면 CPU 는 실제로 오른다**: 실측 idle
  0.2s/tol 0.5 = 1.8% → 0.1s/tol 0.1 = 5.1%(2.8배). "CA 전환이 주범이었으니 fps 는 공짜"가 아니라,
  주범이 사라진 만큼의 여유가 생긴 것뿐이다. 그래서 **기본값은 이 설정 이전과 같은 0.4s(powerSaver)**
  이고, 더 부드러운 쪽은 opt-in 이다).
  배터리-vs-AC/thermal 적응·CADisplayLink
  전환은 1인 로컬 노트북 기준 수확체감으로 판정, 미도입(필요 시 Agent Team 계획 참조). (Agent Team 조사 + 실측, 2026-07-22.)
- **프레임 교체는 `button.image` 대입이 아니라 `spriteLayer.contents` 로 한다 — 전환 억제와 다른 축이다.**
  `setDisableActions` 는 NSStatusItemScene *전환 애니메이션* 을 없앨 뿐, 대입 자체가 유발하는 **버튼
  재드로잉**(`NSViewBackingLayer display` → `_NSViewDrawRect`)은 그대로 남는다. 그 재드로잉에는 스프라이트
  22px 뿐 아니라 **2줄 attributedTitle 텍스트 렌더**가 통째로 포함돼, 5fps 루프에서 상시로 깔린다.
  프레임 픽셀을 전용 서브레이어(`AppDelegate.spriteLayer`)의 `contents` 로 넣으면 이미 업로드된 비트맵을
  바꿔 끼우는 것뿐이라 드로잉 경로를 아예 타지 않는다. `button.image` 는 폭 확보용 **투명 자리표시자**만
  두고(크기가 바뀔 때만 재대입) `imagePosition`·텍스트 배치·상태아이템 폭 계산은 AppKit 에 그대로 맡긴다.
  **실측** — ① A/B 프로브(같은 타이머·5fps·2줄 타이틀·60초×2라운드, `/tmp/ptb-probe.swift` 형태):
  `button.image`+CATransaction 2.00ms/프레임 · CATransaction 없이 3.51ms · **`layer.contents` 0.27ms**.
  ② 라이브 앱 `sample` 전후(메인스레드 샘플 비중): 타이머 경로 235/17212(1.37%) → 33/16581(0.20%),
  `CA::Transaction::commit` 163 → 14, `_NSViewDrawRect` 105 → **0**. 타이틀을 끄고 재면 2.00 → 1.43ms 라
  텍스트 렌더는 기여분의 일부일 뿐이고 나머지는 뷰 드로잉 왕복 자체다(= 텍스트만 손봐선 안 없어진다).
  `contentsScale` 은 화면이 아니라 **비트맵 자신의 픽셀/포인트 비율**을 따라야 한다 — 프레임은 `lockFocus`
  합성 시점의 백킹 스케일로 픽셀이 굳으므로, 화면에서 읽으면 1x 외부 모니터에서 스프라이트가 2배가 된다.
  **5-whys(왜 여태 안 보였나):** ① 14%→2% 를 만든 주범(CA 전환·팝오버 상주)이 워낙 커서, 남은 2% 는
  "프레임 수에 비례하는 어쩔 수 없는 비용"으로 읽혔다 — 실제로는 성격이 다른 축이 하나 더 있었다.
  ② 판정을 CPU% 로만 해서 "2% 면 충분히 낮다"에서 멈췄다. 콜스택을 뜨자 그 2% 안에서 드로잉 경로가
  단일 최대 항목으로 드러났다(추정이 아니라 `sample` 로 봐야 보이는 층). ③ fps·tolerance 처럼 *얼마나
  자주* 축만 튜닝 대상으로 보고, *한 번에 얼마나 비싼가* 축은 손댈 수 없는 상수로 취급했다.
  **회귀 방지:** 변환이 실패하면 `setStatusImage` 가 조용히 `button.image` 폴백으로 떨어져 애니메이션은
  멀쩡해 보이는 채로 절감만 사라진다(무성 실패) → `testMenuBarFramesConvertToLayerBitmaps` 가 전 스프라이트
  형태·bob 위상에서 변환을 못 박고, 빈 이미지로 **nil 이 실제 도달 가능함**까지 함께 단언한다(주입 검증).
  스케일은 `testSpriteContentsScaleFollowsTheBitmapNotTheScreen`. (실측 2026-09-01.)
- **fps 캡은 hold 가 아니라 decimate 다 — `max(floor, delay)` 는 애니메이션을 슬로모션으로 만든다.**
  프레임 delay 에 하한을 걸면(`max(floor, delay)`) 프레임 *수* 는 그대로라 각 프레임이 늘어나고, 결과적으로
  **루프 전체가 느려진다.** Gen-V 스프라이트는 55프레임×0.05s(=2.75s, 20fps)라 floor 0.4s 에서 22s 루프
  = **1/8 속도**가 됐다(메뉴바·플로팅 펫 둘 다). 올바른 적용은 누적 delay 가 floor 를 넘을 때만 프레임을
  내보내 **루프 길이를 보존**하는 것(`GIFDecoder.capFrameRate`) — 같은 wakeup 예산에서 속도가 원본이 되고,
  floor 0.4s 면 합성할 프레임이 55→6개로 줄어 오히려 가볍다.
  **5-whys(왜 안 걸렸나):** ① 원 근거가 "22px 에선 2.5fps 와 5fps 가 구분 안 된다"였는데 이는 *프레임
  레이트* 에만 맞는 말이고 *재생 속도* 8배 지연은 시야에 없었다. ② 테스트(`frameDelay(base:floor:)`)가
  **프레임 1개 단위**로만 검증해 — `max(0.1,0.4)==0.4` — 프레임이 55개 쌓였을 때 루프가 8배가 되는 걸
  구조적으로 볼 수 없었다(결함 트리거와 다른 경로로 통과하는 전형). ③ 2프레임 bob 은 늘리기와 솎아내기가
  같은 결과라 이 결함이 드러나지 않았고, bob 과 GIF 를 같은 하한으로 다룬 게 착시를 굳혔다.
  **영구 캡처:** 단일 프레임이 아니라 **루프 총 길이**를 단정한다(`testCapPreservesPlaybackSpeed` —
  옛 hold 방식 주입 시 11.0s/22.0s 를 잡고 실패 확인). 오용된 API `SpriteView.frameDelay` 는 제거했다.
  (사용자 리포트 "툴바 포켓몬이 팝오버보다 느리다", 2026-08-20.)
- **`Timer.tolerance`(및 `Task.sleep(tolerance:)`)는 곧 재생 지연의 상한이다.** tolerance 는 **늦게만**
  발화시킨다(Apple: "fire the timer later than the scheduled time, up to the tolerance"). 배수 0.5 는
  코얼레싱 강도가 아니라 "루프가 최대 1.5배까지 늘어져도 좋다"는 선언이었다 — 2.75s 루프가 최대 4.13s 가
  되어, `tolerance: .zero` 로 정확히 도는 팝오버와 나란히 보면 메뉴바만 느려 보였다(같은 리포트의 두 번째
  원인). 상시 애니메이션 표면에서 이 배수를 정할 땐 **wakeup 절약과 재생 지연을 같이 적어라** — 현재 0.1
  (지연 ≤10%). 가드: `testToleranceDoesNotVisiblyStretchPlayback`(>0 로 코얼레싱 유지 + 최악 지연 ≤15%).
- **항상 뜬 애니메이션 표면은 메뉴바와 같은 idle 규율을 공유한다.** 플로팅 펫(`FloatingPetPanel`)처럼 상시
  표시되는 두 번째 GIF 표면을 더할 땐 메뉴바 규율을 그대로 상속해야 회귀(#102 후속)를 안 만든다. **규율 =
  "캡이 존재한다(>0)"이며 값의 일치가 아니다** — 표면이 크면 같은 fps 에서도 끊김이 더 보여 값은 갈릴 수
  있다(현재는 두 표면이 사용자 설정 `UsageStore.AnimationQuality` 하나를 공유한다 — 표면별로 값을
  갈라야 할 근거가 생기면 그때 프리셋에서 표면별 값을 뽑아라): ① GIF fps 하한
  (`SpriteView(minFrameDelay:)` — 펫은 `store.animationQuality.frameFloor`, 메뉴바는
  `AppDelegate.menuFrameFloor`, 팝오버 등 *일시적* 표시는 0=네이티브) + `Task.sleep(for:tolerance:)` 코얼레싱, ② 저전력 모드 정적화(`FloatingPetController.shouldAnimate(lowPower:)`
  — `NSProcessInfoPowerStateDidChange` 관찰 후 콘텐츠 재구성), ③ 숨김/슬립 시 `contentView=nil` 로 프레임 루프 정지
  (팝오버 `popoverDidClose` 패턴). 회귀 가드: `FloatingPetEnergyTests`(fps 하한 clamp·`frameFloor>0`·팝오버 불변·
  low-power 정적화 순수 판정 — SwiftUI `.task` 타이밍 자체는 호스트 없이 xctest 불가라 순수 경로만 잠금).
  **가드 비대칭 주의:** 펫 캡만 상수로 잠겨 있었고 메뉴바 캡은 인라인 리터럴 `max(0.4, delay)` 여서
  *캡이 통째로 사라져도 테스트가 못 잡았다*. 지금은 두 표면이 같은 프리셋 값을 읽어 비대칭 자체가
  구조적으로 불가능하고, 가드는 프리셋 계약에 걸린다(`testNoAnimationQualityPresetDisablesTheCap`,
  `testTransientSurfaceIsTheOnlyUncappedOne` — 캡=0 주입으로 실패 확인). 상시 표시 표면을 더할 땐
  캡을 반드시 **이름 있는 값**으로 두고 `>0` 를 단정한다. occlusion 게이팅은
  all-spaces/`.floating` 펫이 실제로 거의 안 가려져 메뉴바와 동일 수확체감으로 미도입. (#102 리뷰 지적 반영, 2026-07-22.)

## 알림

- **휘발성 필드를 dedup/identity 키에 쓰지 마라.** 매 fetch/refresh 마다 값이 변하는 필드(예: rolling
  한도 창의 `resets_at`)를 알림 중복방지 키에 넣으면 매번 새 키가 되어 dedup 이 무력화된다 — 주간 한도
  알림이 80·81·84…갱신마다 반복되던 회귀. 임계값 알림은 **엣지 트리거**(직전 tier 보다 높아진 순간만
  발화, 경고선 아래로 내려가면 재무장)로 구현하고, 판정은 부수효과(실 알림 전송·`.app` 번들 가드)와
  분리한 **순수 함수**(`UsageStore.evaluateLimitAlerts`)로 테스트한다 — 번들 가드 때문에 실 발화 경로는
  xctest 에서 조기 return 되어 커버 불가였던 게 무테스트의 원인.

## 상태 파일 이전·병합

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

## 렌더 기하 (스프라이트·이미지)

- **`.resizable()` + `.frame(w:h:)` 는 "맞춤"이 아니라 "늘여 채움"이다.** 대조 없이 정사각 프레임에 넣으면
  비정사각 원본은 그대로 왜곡된다. 이 부류가 오래 안 잡힌 이유가 핵심이다 — **정적 자산이 전부 정사각이라
  증상이 안 났다**(종 PNG 96×96, 아이템 30×30). 왜곡은 캔버스가 종마다 크롭된 **Gen-V 움직이는 GIF**
  에서만 드러났다(잭키 #325 는 36×66 → 가로 1.83배 뚱뚱, 피카츄 #25 50×46, 팬텀 #143 74×75). 즉 정적
  경로만 검증한 테스트는 통과하면서 GIF 경로를 통째로 비워 둔다. 규율은 셋이다:
  ① 원본 비율은 한 곳(`SpriteFit.size`)에서만 계산하고 **모든 렌더 경로가 그걸 공유한다** — SwiftUI
  (`SpriteView`·`ItemIconView`)든 AppKit `draw(in:)`(메뉴바 `menuBarLayout`)든.
  ② **바깥 슬롯은 정사각으로 유지하고 안쪽 이미지만 줄인다** — 진화 라인·도감 그리드의 폭 계산
  (`EvoLineView.rowWidth`)이 칸을 정사각으로 전제하므로 바깥을 건드리면 레이아웃이 흔들린다.
  (메뉴바는 예외: 세로 22 고정 + 가로는 맞춘 폭 — 정사각 고정이면 세로로 긴 종 좌우에 죽은 여백이 생겨
  사용량 숫자와 벌어진다.)
  ③ **크기가 0 인 원본**(디코드 실패)은 0 나눗셈이 되므로 정사각 폴백으로 막는다.
  회귀 가드(`SpriteAspectRatioTests`)는 실제 PokeAPI 캔버스 치수를 넣고, **"비정사각이 정사각으로 나오지
  않는다"는 트리거 명제를 따로 둔다** — 이게 없으면 원본이 애초에 정사각인 케이스로도 전부 통과한다.

## 프로세스 제어·업데이트

- **`pgrep -x <name>` 은 실행 파일의 정체성 검사이지, 기다리는 특정 프로세스에 대한 검사가 아니다.**
  중복 인스턴스가 떠 있는 동안 실행될 수 있는 모든 wait-for-exit 루프는 PID를 받아야 한다. `UpdateChecker`가
  자동 업데이트 시 앱 종료를 기다릴 때 `pgrep -x PokeTokenBar`를 쓰면, 중복 인스턴스가 살아있는 동안 루프를
  결코 빠져나오지 못하고 20초 타임아웃을 온전히 소모한다(#175). `ProcessInfo.processInfo.processIdentifier`로
  종료 대상 프로세스 PID를 전달하고 `kill -0 "$3"`로 특정 프로세스의 종료를 대기한다.

## 빌드·패키징 (xcodegen·자산 카탈로그)

- **xcodegen 의 `resources:` 키는 리소스 빌드 페이즈를 만들지 않는다 — 그런데 빌드는 성공한다.**
  `resources: - PokeTokenBariOS/Resources` 로 자산 카탈로그를 선언해도 xcodegen 2.46.0 은
  `PBXResourcesBuildPhase` 를 아예 생성하지 않는다(생성된 pbxproj 에 `.xcassets` 참조가 0건).
  결과는 `Assets.car` 가 번들에 없는 앱이고, **`xcodebuild` 는 경고 하나 없이 BUILD SUCCEEDED 를 낸다.**
  자산 카탈로그는 `sources:` 에 타입을 명시해야 한다:
  `- path: <...>/Assets.xcassets` + `type: folder.assetCatalog`.
  **이 부류가 오래 안 잡힌 이유가 핵심이다 — 빌드 성공은 리소스가 실렸다는 증거가 아니다.**
  컴파일·서명·설치가 전부 통과하므로 유일한 신호가 육안 확인인데, 그마저 "iOS 아이콘 캐시" 로 오귀인하기
  쉽다(재설치·재부팅·SpringBoard 를 여러 라운드 헛돌았다). 검증은 산출물을 직접 본다:
  `ls <build>/*.app/Assets.car` 와 `grep -c PBXResourcesBuildPhase *.xcodeproj/project.pbxproj`.
  **부류 스윕에서 위젯 타깃도 같은 패턴이었다** — 카탈로그가 비어 있어 증상만 없었을 뿐, 자산을 넣는
  순간 조용히 누락됐을 잠복 결함이라 함께 고쳤다.

- **iOS 18 앱 아이콘은 외형 변형 3개(light/dark/tinted)를 각각 이미지로 줘야 한다.**
  `AppIcon.appiconset/Contents.json` 에 이미지 하나만 두면, 사용자가 홈 화면을 **틴트 모드**로 쓸 때
  iOS 가 라이트 아이콘을 평탄화해 tinted 렌디션을 자동 생성하고 **투명 영역을 흰색으로 채운다** → 타일이
  흰 사각형이 된다. 소스 이미지를 어떻게 바꿔도(투명 배경, 검정 배경, 심지어 단색 빨강 테스트) 결과가
  똑같아서 **"iOS 가 아이콘을 아예 안 읽는다"는 오진을 유발한다** — 실제로는 읽고 나서 평탄화하는 것이다.
  각 변형은 `appearances: [{appearance: luminosity, value: dark|tinted}]` 로 선언한다.
  **tinted 변형은 투명도를 보존한다** — 흑백(투명 배경 + 흰 글리프)으로 만들면 iOS 가 사용자의 틴트
  색으로 매핑한다. 검증은 컴파일된 카탈로그에서 렌디션 수를 센다(1개가 아니라 3개여야 한다):
  `xcrun assetutil --info <...>/Assets.car` → `AssetType == "Icon Image"` 가 3건
  (RGB/opaque=true, RGB/opaque=false, Monochrome/opaque=false).

## 테스트

- **시간대 의존 단언 — UTC 시각의 local-day 를 기대하면 UTC 보다 느린 시간대에서 실패한다.**
  `testHermesAcceptsMillisecondStartedAt`(LocalAdditionalUsageTests)은 epoch `1767312000000`
  (2026-01-02T00:00:00Z)의 `localDay`가 `"2026-01-02"`라고 단언한다. UTC-7 로컬에서는 이 시각이
  1월 1일 저녁이라 `"2026-01-01"`이 나와 실패 — **`main`에서도 실패하는 기지 결함**(CI macos-15는
  UTC라 통과하고 로컬만 실패한다). 시간대가 스레드에 관여하는 순간 단언값도 시간대를 고정해야 한다:
  테스트에서 locale/TimeZone을 주입하거나, 파서가 UTC로 정규화하는지를 검증하는 형태로 바꾼다.
  이 판별법을 매번 반복하지 않도록 `dev-deploy.md` §기지의 선례에 목록으로 유지한다.

- **Application Support 기본 경로를 쓰는 싱글턴 스토어는 `swift test` 에서 실사용자 파일을 건드린다.**
  테스트가 `fileURL` 을 주입하면 안전하다고 착각하기 쉬운데, 주입은 *그 테스트*만 덮는다. 스토어를
  기본값으로 소유하는 상위 객체(`UsageStore` 의 `limitHistory: .shared`)를 만드는 다른 테스트가
  하나라도 있으면 그 경로로 실파일이 열리고 **쓰인다**. 실측(2026-08-30): `LimitHistoryStore` 를
  게이트 없이 넣었더니 전체 스위트 1회 실행이 `~/Library/Application Support/PokeTokenBar/
  limit-history.json` 에 사용자의 실제 한도(97·100%)를 기록했다 — 테스트가 실 endpoint 를 때린
  것이다. 같은 부류가 `LocalUsageCache`(`usage-cache.json`)에도 있었고 아래에서 함께 닫혔다.
  방어는 "테스트가 주입하기"가 아니라 **스토어 자신이 실앱에서만 디스크를 만지는 것**이다 —
  판정은 `AppEnv.persistsToUserLocation(injectedFileURL:isBundledApp:)` 한 곳에만 두고
  (`LimitHistoryStore`·`LocalUsageCache` 가 공유) 주입 경로면 항상 live, 아니면 `isBundledApp` 에만 live.
  **읽기도 함께 막는다** — 쓰기만 막으면 테스트가 사용자의 실제 캐시를 읽어 픽스처와 섞인 상태로
  단언하게 된다(격리는 양방향이라야 성립).

  - **`LocalUsageCache` 도 같은 결함이었고 2026-08-30 에 닫혔다.** 발화 경로가 두 갈래였는데 **둘 다
    개별 테스트의 잘못이 아니다**: (a) `testScreensDidSleepNotificationReachesTheStore` 가 `NSWorkspace`
    알림을 **브로드캐스트**하면 그 순간 살아 있는 *모든* `UsageStore` 가 받는다 — `UsageStore(autoRefresh:
    defaults:)` 는 `providers` 기본값이 **실물 프로바이더**라, 레지스트리만 확인하려고 만든 스토어까지
    `restoreFullPolling()` → `Task { refresh() }` 로 진짜 스캔을 돈다. (b) `setCustomScanRoots` 가 띄우는
    detached `Task` 는 테스트보다 오래 살아서, **클래스 단독 실행에선 프로세스가 먼저 끝나 안 보이고
    전체 실행에서만** 발화한다. → 클래스 단위 bisect 로 "재현 안 됨" 이 나와도 무결을 뜻하지 않는다.
  - **왜 기존 테스트가 못 걸렀나.** `LocalUsageCache` 를 쓰는 테스트는 **전부** `fileURL` 을 주입한다.
    주입은 *그 테스트*를 덮을 뿐 **프로세스**를 덮지 못하고, 기본 경로 분기는 그래서 구조적으로
    안 보인다. 커버리지도 무력하다 — 기본 경로 초기화가 1회만 실행돼도 라인은 covered 다.
  - **확인 방법(측정이 곧 증거).** `HOME` 을 바꿔 격리하려는 시도는 **무효다** — macOS 의
    `FileManager.urls(for: .applicationSupportDirectory)` 는 `$HOME` 이 아니라 사용자 DB 로 홈을 정한다
    (실측: `HOME=/tmp/x` 로 실행해도 `/Users/<me>/Library/...` 를 그대로 쓴다 → 거짓 음성).
    앱이 떠 있으면 mtime 비교도 오염된다(앱 자신이 같은 파일을 쓴다). 확실한 방법은 **쓰기·읽기 지점에
    임시 probe 를 심고 스위트를 돌리는 것**이다.
  - **회귀 가드의 함정 두 가지**(둘 다 결함 주입으로 실제로 드러났다):
    ① mtime 은 **첫 스캔 전에** 찍어야 한다 — 두 번째 호출은 `dirty == false` 라 throttle 이전에 조기
    반환하므로, 첫 호출 뒤에 찍으면 게이트를 없애도 창 안에 쓰기가 없어 통과한다.
    ② 읽기 게이트는 엔트리 수로 검증되지 않는다 — 사용자 blob 은 픽스처 루트 밖 절대경로 키라 결과에
    안 섞인다. 로드된 blob 수(`cachedBlobCount`) 같은 **직접 관측점**이 필요하다.
