---
summary: "결함 대응 프로토콜로 축적된 구체 규칙 — 한 번 겪은 부류의 실수를 다시 겪지 않기 위한 원장."
read_when:
  - 결함·회귀·공백을 고치는 중 (프로토콜 4단계의 '부류 스윕'·'영구 캡처' 근거)
  - 동시성/await·옵셔널 판정·캐시 무효화·외부 로그 포맷을 건드릴 때
  - 크기 상한이 없는 사용자 파일을 읽는 코드(사용량 로그 파서)의 메모리를 손볼 때
  - 메뉴바·플로팅 펫 등 상시 표시 애니메이션의 성능을 손볼 때
  - 스프라이트·이미지를 고정 크기 프레임에 그릴 때(비율 왜곡 부류)
  - 세이브 이전/병합·외부 파일 입력 경로를 만들 때
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
  (설정 갱신·팝오버 `claudeLimitsRefreshRow`, `refreshLimitTokenFromKeychain`)에서만. 캐시 토큰이 살아있는
  동안은 자동 폴이 그 토큰으로 한도를 계속 갱신하고, 만료되면 stale 표시 후 사용자가 갱신한다. 회귀 가드:
  `testAutoRefreshUsesNoPromptPathManualUsesPromptPath`. (완전 근절은 Developer ID notarization 으로
  '항상 허용' 승인을 안정화하는 것뿐 — 신뢰된 서명 신원이라야 ACL 승인이 지속된다. 미도입.)
- **자격증명 "없음"과 "계정 로그인 없음"은 다른 안내다.** Claude Code 2.1.x 의 `Claude Code-credentials`
  항목이 MCP 서버 OAuth(`mcpOAuth`) 상태만 담고 계정 토큰(`claudeAiOauth`)은 안 담는 경우가 있다. 이때
  파싱 실패를 형식 오류로 뭉뚱그리면 "재로그인하면 된다"를 안내 못 해 한도 섹션이 원인 불명으로 사라진다.
  → `LimitsError.credentialMissingAccountOAuth` 로 구분해 재로그인 안내를 띄운다
  (`OAuthCredentialData.isAccountOAuthMissing`).

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
- **영구 기록과 임시 상태를 한 목록에 섞을 땐 임시 쪽에 표식이 필요하다.** 도감·수집 화면은 "쌓이기만
  한다"는 약속을 주는데, 현재 키우는 개체에서 파생된 항목은 알을 새로 사면(`buyEgg` 는 `active` 만 버리고
  `dex` 는 안 건드린다) 또는 메타몽이 리빌하면(`pathIDs` 가 통째로 교체) 사라진다 — 총계가 줄어 결함처럼
  보인다. 포획 로그는 행에 `키우는 중` 뱃지가 있어 괜찮았지만 종 격자는 표식 없이 같은 모양이었다.
  판정 기준은 "현재 개체에 속하는가"가 아니라 **"졸업 기록이 있는가"** 다(`DexSpecies.isRaising` =
  `!isGraduated`) — 같은 라인을 다시 키우는 중이면 이미 확정분이라 표식 대상이 아니고, 이 분기가
  두 규칙이 갈리는 유일한 지점이라 회귀 테스트도 그 상태(졸업분 + 같은 라인 육성 중)로 쓴다.

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
  diff-gate(동일 프레임 객체 재대입 스킵 — 애니 프레임은 서로 다른 객체라 정상 통과) + GIF fps 하한 0.4s(≈2.5fps)
  + `Timer.tolerance` 0.5(코얼레싱)로 ~5 wakeup/s(−89%), 애니메이션 유지. 배터리-vs-AC/thermal 적응·CADisplayLink
  전환은 1인 로컬 노트북 기준 수확체감으로 판정, 미도입(필요 시 Agent Team 계획 참조). (Agent Team 조사 + 실측, 2026-07-22.)
- **항상 뜬 애니메이션 표면은 메뉴바와 같은 idle 규율을 공유한다.** 플로팅 펫(`FloatingPetPanel`)처럼 상시
  표시되는 두 번째 GIF 표면을 더할 땐 메뉴바 규율을 그대로 상속해야 회귀(#102 후속)를 안 만든다: ① GIF fps
  하한(`SpriteView(minFrameDelay:)` — 펫은 `FloatingPetView.frameFloor` 0.4s≈2.5fps, 팝오버 등 *일시적* 표시는
  0=네이티브) + `Task.sleep(for:tolerance:)` 코얼레싱, ② 저전력 모드 정적화(`FloatingPetController.shouldAnimate(lowPower:)`
  — `NSProcessInfoPowerStateDidChange` 관찰 후 콘텐츠 재구성), ③ 숨김/슬립 시 `contentView=nil` 로 프레임 루프 정지
  (팝오버 `popoverDidClose` 패턴). 회귀 가드: `FloatingPetEnergyTests`(fps 하한 clamp·`frameFloor>0`·팝오버 불변·
  low-power 정적화 순수 판정 — SwiftUI `.task` 타이밍 자체는 호스트 없이 xctest 불가라 순수 경로만 잠금). occlusion 게이팅은
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
