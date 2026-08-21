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
- **프로바이더 고유 동작만 `providerID` 로 명시 분기**: 공식 한도(Claude=HTTP·Codex=프로세스·
  OpenCode Go=HTTP `/zen/go/v1/usage`, `OpenCodeGoLimitsProvider`), 5h forecast·"현재 블록" 행처럼
  *특정 프로바이더에만 존재하는* 기능만 id 로 조건 분기한다.
  범용 경로에 `== "claude_code"` 류 리터럴 분기를 추가하는 건 금지.
  한도 프로바이더가 `UsageStore` 에 새로 붙으면 기존 테스트의 스토어 구성 전부가 실 구현을 기본
  파라미터로 물고 돌게 된다 — 네트워크를 치는 프로바이더는 `AppEnv.isBundledApp` 게이트로
  테스트 실행을 원천 차단해야 한다(OpenCodeGoLimitsProvider 사례; 스텁은 값 주입용).
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
- **append-only SQLite 사용량 스토어** (Cursor `cursorDiskKV`, Copilot `assistant_usage_events`,
  앞으로 같은 형태의 세 번째 소스) = `LocalAdditionalUsageReader.scanIncrementalStores`. URL 매핑·
  `MAX` SQL·row query·parse 만 넘긴다. watermark 루프를 프로바이더마다 복사하지 마라 (#157).
