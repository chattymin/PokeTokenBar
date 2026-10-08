# PokeTokenBar 기여 가이드

[English](CONTRIBUTING.md) · **한국어** · [日本語](CONTRIBUTING.ja.md)

기여에 관심 가져 주셔서 감사합니다! PokeTokenBar는 작은 비상업 팬 프로젝트이며,
크기에 상관없이 모든 기여를 환영합니다 — 버그 리포트, 수정, 새 사용량 프로바이더,
번역, 문서.

풀 리퀘스트를 열기 전에 아래 짧은 섹션들을 읽어 주세요.

## 사전 요구사항

- **macOS 14 (Sonoma) 이상**
- **Swift 6 툴체인** (Xcode 16 이상) — `Package.swift`가 요구
  (`swift-tools-version: 6.0`)

## 빌드 & 테스트

이 프로젝트는 Swift Package입니다. 저장소 루트에서:

```bash
swift build             # 앱 타깃 컴파일
./scripts/test-gate.sh   # 전체 테스트 실행 및 로직 코어 커버리지 검사
```

CI도 모든 풀 리퀘스트에서 같은 명령을 실행합니다. 테스트 게이트는
`swift test --enable-code-coverage`를 실행하고, 기본적으로 로직 코어 라인 커버리지
75% 이상을 요구합니다. PR을 제출하기 전에 로컬에서 두 명령을 실행하세요.
개발 중 특정 테스트만 확인하려면 `swift test --filter <TestCase>`를 실행하세요.

## 기여 워크플로우

1. `main`에서 feature 브랜치를 만듭니다 (쓰기 권한이 없으면 저장소를 fork).
2. 테스트와 함께 변경합니다. 변경은 focused하게 유지하세요.
3. `main`을 대상으로 풀 리퀘스트를 엽니다.
4. CI가 통과하고 리뷰가 끝나면 **squash merge**로 머지됩니다.

### 언어: 영어 우선

이 저장소는 협업 산출물에 **영어를 first language**로 사용합니다:

- **풀 리퀘스트 제목과 본문은 영어여야 합니다.**
- **커밋 메시지는 영어로 작성합니다.**

저장소가 squash-merge하므로 PR 제목이 `main`의 커밋 제목이 됩니다 — 영어 PR이
공개 히스토리를 일관되게 유지합니다.

### 커밋 & PR 컨벤션

- [Conventional Commits](https://www.conventionalcommits.org/) 스타일 사용:
  `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:` 등.
- 영어 PR 제목(예: `fix(home): retain idle usage history`)을 사용하고 풀 리퀘스트
  템플릿의 해당 섹션과 체크리스트를 채워 주세요.
- **화면이 달라지는 모든 PR**은 `UI changes`에 이미지를 삽입해야 합니다. UI 디렉터리
  밖에서 발생하는 화면 변경도 포함합니다. 실제 스크린샷, 프로덕션 UI의 로컬 렌더링,
  변경 UI를 그린 이미지 모두 허용합니다. 샘플 데이터 렌더링과 일러스트는 그 사실을
  명시해 주세요. 기존 화면은 전후 이미지, 신규 화면은 이전 화면이 없다는 설명과 신규
  이미지가 필요합니다. 텍스트만으로 대체할 수 없습니다. 이미지가 없으면 코딩 에이전트가
  승인된 PR 작업의 일부로 직접 생성하고 첨부합니다. 적절한 생성·첨부 대안을 시도한 뒤에도
  실제 장애로 완료할 수 없을 때만 게시를 보류합니다. 정식 `assets/` 스크린샷은 PR마다가
  아니라 릴리스 때 재생성됩니다.
- 코딩 에이전트는 `.agents/skills/prepare-pr/`의 공용 skill을 사용합니다.
  `.claude/skills/prepare-pr`도 같은 skill을 가리킵니다. 게시 전 로컬 검사:
  `python3 scripts/check-pr.py --base origin/main --title 'docs: clarify PR requirements' --body-file /tmp/pr-body.md`.
  UI 디렉터리 밖의 화면 변경은 `--ui-changes`를 추가해 주세요.

## 코드 컨벤션

이 앱은 설계상 프로바이더 무관(provider-agnostic)합니다. 확장할 때 다음 규칙을
따르세요 (테스트로도 강제됩니다):

- **사용량 소스 추가** (새 AI CLI) = `UsageProvider` 프로토콜
  (`Sources/PokeTokenBar/Core/UsageProvider.swift`)을 새 타입 하나로 구현하고
  `UsageStore.init`의 기본 `providers:` 배열
  (`Sources/PokeTokenBar/Core/UsageStore.swift`)에 등록합니다. 이 두 곳은 기본 진입점이며,
  수정 범위가 두 파일로 제한되지는 않습니다. 소스에 맞춰 리더, 공유 캐시 연동,
  사용자 지정 스캔 경로, 테스트도 추가하거나 수정하세요.
  [프로바이더 확장 규약](docs/reference/provider-extension.md)과
  [프로바이더 기여 체크리스트](https://github.com/chattymin/PokeTokenBar/issues/115)를 따르세요.
- **범용 동작은 모든 프로바이더에 걸쳐 집계해야 합니다** (오늘/주/월 합계, burn tier,
  companion 리듬). 범용 계산을 한 프로바이더에만 붙이지 말고, 범용 경로에
  `providerID == "..."` 리터럴 분기를 추가하지 마세요. 프로바이더 고유 동작
  (예: 공식 한도)만 `providerID`로 분기할 수 있습니다.
- **버전 매니저 / 설치 경로 추가** = `BinaryLocator.commonToolDirectories()`에
  추가합니다 — 탐색과 자식 프로세스 `PATH`가 공유하는 단일 소스입니다.
- **append-only SQLite 사용량 스토어 추가** (Cursor·Copilot처럼 rowid/`id` 워터마크) =
  `LocalAdditionalUsageReader.scanIncrementalStores`에 URL / `MAX` SQL / row query /
  parse만 넘기세요. watermark 루프를 복사하지 마세요.

## 법적 / 지식재산

PokeTokenBar는 **비공식·비상업 팬 프로젝트**이며 Nintendo, Game Freak,
Creatures Inc., The Pokémon Company와 제휴 관계가 없습니다
([README](README.ko.md#라이선스--면책)의 면책 참고). 프로젝트를 안전하게 유지·배포하기
위해 기여는 **반드시** 다음 규칙을 따라야 합니다:

- **포켓몬(또는 다른 제3자) 저작물을 커밋하거나 번들하지 마세요** — 스프라이트,
  아트워크, 오디오, 폰트, 대량 이름/데이터 파일. 포켓몬 종 데이터와 스프라이트는 공개
  [PokéAPI](https://pokeapi.co)에서 **런타임에** 받아 사용자 기기에 로컬 캐시됩니다;
  그대로 유지하세요.
- **상업적 사용을 의도한 기능**이나 저작물을 재배포·익스포트하는 기능을 추가하지 마세요.
- **secret, 자격증명, 비공개/내부 툴링 참조를 커밋하지 마세요.** 저장소의 모든 것을
  generic하고 public-safe하게 유지하세요.
- 기여를 제출함으로써, 그것이 **본인의 원본 작업물**임을 확인하고 이 프로젝트의
  [MIT License](LICENSE)로 라이선스됨에 동의합니다. MIT 라이선스는 이 프로젝트의 소스
  코드에만 적용되며 — 제3자의 상표·아트워크·데이터에 대한 권리는 부여하지 않습니다.

## 버그 신고 & 기능 요청

이슈 템플릿을 사용해 주세요. 버그의 경우 macOS 버전, 앱 버전, 사용하는 AI CLI,
재현 단계를 포함해 주세요.

권리자로서 본 프로젝트에 우려가 있으시면 이슈를 열거나 메인테이너에게 연락 주시면
신속히 대응하겠습니다.
