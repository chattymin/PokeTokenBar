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
swift build      # 앱 타깃 컴파일
swift test       # 전체 테스트 스위트 실행
```

CI는 모든 풀 리퀘스트에서 `swift build`와 `swift test`를 실행합니다; 먼저 로컬에서
둘 다 통과하는지 확인해 주세요.

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
- 풀 리퀘스트 템플릿을 채워 주세요.
- **UI 변경** (`Sources/PokeTokenBar/UI/` 아래 무엇이든)은 PR에 before/after를
  설명해야 합니다. 스크린샷이나 GIF는 환영하지만 선택입니다 — 명확한 텍스트 설명이면
  충분합니다. 정식 `assets/` 스크린샷은 PR마다가 아니라 릴리스 때 재생성됩니다.

## 코드 컨벤션

이 앱은 설계상 프로바이더 무관(provider-agnostic)합니다. 확장할 때 다음 규칙을
따르세요 (테스트로도 강제됩니다):

- **사용량 소스 추가** (새 AI CLI) = `UsageProvider` 프로토콜
  (`Sources/PokeTokenBar/Core/UsageProvider.swift`)을 새 타입 하나로 구현하고
  `UsageStore.init`의 기본 `providers:` 배열
  (`Sources/PokeTokenBar/Core/UsageStore.swift`)에 등록합니다. 이 두 곳만 손대면
  됩니다.
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
