---
summary: "새 사용량 소스(AI CLI)·버전매니저를 더할 때의 확장 지점과 플랫폼 종속 분기 금지 규약."
read_when:
  - 새 프로바이더(사용량 소스)를 추가할 때
  - 버전매니저·설치경로 탐색을 손볼 때
  - 코드 리뷰에서 프로바이더 분기가 범용 경로에 새는지 볼 때
---

# 확장 규약 (새 프로바이더/툴 추가)

새 AI CLI(사용량 소스)·버전매니저를 더할 때 특정 플랫폼에 종속된 분기를 만들지 않는다.
아래는 절차이며, **코드 리뷰 시 이 규약 위반을 결함으로 본다.**

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
- **로그 스캔 루트 추가** = `LocalUsageReader.claudeProjectRoots` 같은 프로바이더별 루트 목록 한 곳에만
  추가한다. 스캔(`LocalUsageReader`)·캐시(`LocalUsageCache`)·테스트가 그 단일 소스를 공유해야 한다.
  Codex의 기본 목록은 활성 세션 파일이 있는 `~/.codex/sessions`와 보관된 세션 파일을 옮기는
  `~/.codex/archived_sessions`를 모두 포함해야 한다. 두 경로는 서로 다른 사용량이 아니라
  같은 rollout이 이동하는 위치이므로, 어느 한쪽만 읽으면 기존 사용량이 사라진 것처럼 보일 수 있다.
  기본 목록을 테스트할 때는 `computeCodexScanRoots(home:)`에 가짜 home을 주입해 실제 사용자
  디렉터리에 의존하지 않도록 한다.
  루트가 겹쳐도 합계는 전역 dedup 이 바로잡지만, 중복 루트는 스캔 비용을 배로 늘리므로
  `normalizedRoots` 로 접는다.
- **사용자 지정 스캔 폴더** = `customScanRoots.<providerID>` (Settings → Advanced). 항목은 그
  프로바이더 리더만 읽는다. 공통 헬퍼는 `CustomScanRoots.union` — 커스텀 루트는 기본 루트에
  *더하기만* 한다. 조상 경로(`~`)가 `normalizedRoots` 로 기본 루트를 접어 없애면
  `skipsHiddenFiles` 가 `.claude` 를 못 내려가 합계가 조용히 0 이 된다(#162-B, #177).
  새 프로바이더는 `storedValue(for: "<id>")` 를 자기 루트 함수에 연결하고,
  `CustomScanRoots.curatedRoots(for:)` 에도 그 기본 루트 목록을 넣는다 — Settings 매치 카운트가
  이 두 번째 레지스트리를 본다. 빼먹으면 `default: []` 로 카운트만 0 이 되고 스캔은 리더 쪽
  기본값으로 돌아간다.
- **로컬 파일을 읽는 새 사용량 소스는 `LocalAdditionalUsageCache` 위에 얹는다 — 리더를 손으로
  완결하지 마라.** OpenCode/Hermes/Kiro/Cursor/Copilot 이 전부 이 캐시(30초 공유 엔트리, `existing +
  loaded` keep-max 병합, `invalidateScanCache` 훅)를 타는데 Aside 만 `fetchDaily`/`fetchEnrichment` 가
  각자 전체 스캔을 하도록 직접 짰다. 그 결과가 독립 리뷰 3라운드였다 — 세션 삭제(`ON DELETE CASCADE`)로
  오늘 합계가 줄어드는 문제, 리프레시당 스캔 2회, 실패 처리 관례 불일치는 모두 "형제와 같은 경로를
  안 탔다"에서 나온 부류다(2026-09-10). 새 소스는 `LocalAdditionalSource` 케이스 하나 + 리더
  함수로 시작하고, 캐시를 우회할 이유가 있으면 doc comment 에 그 이유를 적는다. 테스트는 provider 에
  `cache:` 를 주입해 캐시를 실제로 통과시킨다 — `LocalAdditionalUsageCache(rootsOverride: [.x: roots],
  clock:)` 로 루트를 고정하고 clock 을 31초 넘겨 병합 경로(두 번째 스캔)를 밟는다(`AsideUsageTests`).
  ID 가 파일 안에서만 유일한 소스(SQLite rowid)는 파일 재생성 충돌을 막기 위해 id 에 inode 를 넣는다.
- **리더의 실패 의미(throw / nil / `[]`)를 바꾸면 소비자 `UsageStore.refresh` 까지 추적한다.**
  provider 파일 안에서만 보면 셋이 비슷해 보이지만 스토어는 다르게 처리한다: `fetchDaily` 가 throw
  → `failedIDs`·`lastErrorDescription`(팝오버 경고 아이콘)에 기록되고 **`lastUpdated` 가 앱 전체로
  멎는다**; nil → "성공인데 사용량 없음"으로 스냅샷이 사라진다; `fetchEnrichment` 의 OK 플래그 false
  → 이전 주/월/블록 값을 유지. Aside 리뷰에서 "나쁜 DB 스킵"을 `[]` 로 접어 실패가 0 사용량으로
  보였고, 그걸 "전부 실패면 throw"로 고치자 영구 스키마 불일치가 `lastUpdated` 를 얼렸다 — 두 번
  연달아 소비자를 안 읽고 고친 결과다. PR 에 "throw 는 X 일 때만, nil 은 Y" 매핑을 한 줄로 적는다.
- **append-only SQLite 사용량 스토어** (Cursor `cursorDiskKV`, Copilot `assistant_usage_events`,
  앞으로 같은 형태의 세 번째 소스) = `LocalAdditionalUsageReader.scanIncrementalStores`. URL 매핑·
  `MAX` SQL·row query·parse 만 넘긴다. watermark 루프를 프로바이더마다 복사하지 마라 (#157).
