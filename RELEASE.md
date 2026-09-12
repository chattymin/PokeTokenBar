# 릴리스 프로세스

버전 배포 시 **코드뿐 아니라 문서(README·웹페이지·cask)까지 일관되게** 갱신하기 위한 런북.
기계적 단계는 `scripts/release.sh` 가 자동화하고, 내용 판단이 필요한 부분은 아래 체크리스트로 검토한다.

## 한 줄 배포

```bash
# 템플릿을 복사한 뒤 실제 변경사항과 Contributors를 작성한다(필수).
cp docs/reference/release-notes-template.md /tmp/notes.md
# /tmp/contributors.txt: 포함된 PR에서 확인한 GitHub handle을 한 줄에 하나씩 작성한다.
# 외부 기여자가 없는 릴리스만 빈 파일을 사용하며, 노트에도 없음을 명시한다.

PTB_NOTES_FILE=/tmp/notes.md PTB_CONTRIBUTORS_FILE=/tmp/contributors.txt ./scripts/release.sh 2.1.1
```

`scripts/release.sh <version>` 가 순서대로 수행:

0. **노트·Contributors 검사** — 필수 섹션·설치 안내와 확인한 기여자 목록 대조. 누락 시 빌드·앱 교체·push 전에 중단.
1. **test-gate** (`./scripts/test-gate.sh`) — 전체 테스트 + 로직 커버리지. 실패 시 중단.
2. **문서 일관성 검토** — 정적 버전 배지·제거된 의존성(예: `ccusage`) 잔존을 자동 경고 + 아래 수동 체크리스트 출력. 경고 시 진행 여부를 묻는다.
3. **VERSION 범프** (`scripts/build-app.sh`, 아직 미커밋).
4. **빌드 + zip** (`build/PokeTokenBar.zip`) + 빌드 버전 일치 확인 — **push 전 검증**(실패해도 범프 미커밋이라 origin/main 무손상).
5. **커밋 + push** (`git push origin main`, 빌드 성공 후).
6. **GitHub Release** 생성 (`PTB_NOTES_FILE` 원문 사용, 최소 노트 자동 대체 없음).
7. **Homebrew cask** 버전 갱신 (`chattymin/homebrew-tap`).
8. **GitHub Pages 재빌드** 요청 (랜딩 동적 배지 갱신 유도).

> `main` 브랜치에서만 실행(스크립트가 가드). 비-main 에서 실행 시 즉시 중단.

검토만 하려면: `./scripts/release.sh --check-only`

노트만 검사하려면: `python3 scripts/release-metadata.py check-notes /tmp/notes.md /tmp/contributors.txt`

## 릴리스 노트와 기여자

- [v2.5.3](https://github.com/chattymin/PokeTokenBar/releases/tag/v2.5.3)을 기준으로 영어
  `New / Fixed / Other / Contributors`와 `Install / Upgrade` 안내를 유지한다.
- 기능은 사용자에게 달라지는 동작을 설명하고 PR 번호와 작성자 `@handle`을 연결한다.
  변경 없는 분류는 `None.`으로 남긴다. 문서·스크린샷 변경은 `Other`에 정리한다.
- **직전 공개 릴리스 태그부터 배포 대상 커밋까지** 포함된 PR을 전수 확인한다. 날짜 검색만으로
  대체하지 않는다. PR 작성자와 확인 가능한 실제 공동기여자의 GitHub handle을 수집한다.
  기본 Contributors는 v2.5.3처럼 저장소 소유자와 봇을 제외한 외부 기여자이며, 중복 제거·정렬한다.
  직접 커밋된 외부 기여도 확인한다. 로그인 이름을 확인할 수 없으면 임의로 만들지 말고 해결 후 배포한다.
- 확인한 목록을 `PTB_CONTRIBUTORS_FILE`에 한 줄 한 handle로 저장하고 노트 Contributors와 대조한다.
  검사기는 이 목록 및 변경 설명에 등장한 외부 `@handle`의 누락을 차단한다. 목록 자체의 완전성은
  위 PR·커밋 대조로 확인해야 한다. 이전 릴리스 목록을 복사하지 않는다.
- 외부 기여자가 없을 때만 빈 목록 파일과 `No external contributors in this release.`를 사용한다.
  기여자가 있으면 v2.5.3처럼 `@alice · @bob` 목록 아래 `Thank you all.`을 적는다.

## 커밋 공동작성자

릴리스 커밋에는 기본적으로 `Co-Authored-By`를 붙이지 않는다. 실제 해당 커밋에 공동작업한
참여자가 확인될 때만 `PTB_COAUTHORS_FILE`에 한 줄당 `Name <email>`로 작성해 전달한다.
특정 AI 이름은 고정하지 않으며, 현재 도구나 이전 커밋만 보고 추측하지 않는다.
전체 릴리스의 Contributors와 릴리스 준비 커밋의 공동작성자는 별도로 판정한다.

```bash
PTB_NOTES_FILE=/tmp/notes.md PTB_CONTRIBUTORS_FILE=/tmp/contributors.txt \
  PTB_COAUTHORS_FILE=/tmp/coauthors.txt ./scripts/release.sh 2.1.1
```

## E2E 스모크 (선택 — GUI 세션 필요)

```bash
./scripts/e2e.sh
```

실제 앱 번들로 빌드→기동→데이터 파이프라인(스냅샷 갱신·구조 검증·AppLog)→메뉴바
status item(AX)→팝오버 오픈(AXPress)까지 7개 체크. 5단계는 터미널에 손쉬운 사용
(Accessibility) 권한 필요 — 미허용이면 해당 단계만 SKIP. release.sh 에 포함하지 않는
이유: GUI 세션·권한 의존이라 헤드리스 실행이 깨질 수 있음. 릴리스 전 수동 1회 권장.

## 문서 검토 체크리스트 (내용 변경 시)

`release.sh` 2단계가 출력하는 것 — **기능/동작이 바뀐 릴리스면 반드시 갱신**:

- [ ] **README.md / README.ko.md / README.ja.md** — 기능 목록, 요구사항, 데이터 소스, 스크린샷. 3개 언어 동시.
- [ ] **랜딩 페이지** (`gh-pages` 브랜치 `index.html`) — hero·features·companion·install·works-with·요구사항·푸터.
  - 릴리스 배지는 **동적**(`img.shields.io/github/v/release/...`) → 버전 자동 반영. **기능/문구만 수동.**
  - i18n 사전 **en/ko/ja 동시** 갱신 + 마크업 키 ⊆ 사전, en==ko==ja 키 정합 유지.
  - 갱신은 worktree 로: `git worktree add /tmp/ptb-gh-pages gh-pages` → 편집 → commit/push → `git worktree remove`.
- [ ] **homebrew-tap cask** caveats — 설치 요구사항(의존성 등) 최신인지. 버전은 release.sh 가 갱신.

## 자동으로 갱신되는 것 (수동 불필요)

- README·랜딩의 **release 배지** = shields 동적 배지 → 최신 릴리스 자동(캐시로 수 분 지연 가능).
- 인앱 업데이트 알림 — `releases/latest` 기준 자동.

## 배포 후 검증

```bash
brew update && brew upgrade --cask poke-token-bar
```

`brew list --cask --versions poke-token-bar` 와 `/Applications/PokeTokenBar.app` 버전이 새 버전인지 확인.

## 서명 (2026-07-08 부터)

릴리스 빌드는 이 머신의 `PokeTokenBar Local` 자체서명 인증서로 서명된다
(`scripts/create-signing-cert.sh` 로 생성, keychain 에만 존재 — 레포 미커밋).
- designated requirement 가 버전 간 고정 → 사용자의 Keychain "항상 허용"이 업데이트 후에도 유지.
- 전환 직후 첫 업데이트 1회는 기존(ad-hoc 시절) 허용이 무효라 마지막 프롬프트가 뜰 수 있음.
- 인증서를 분실/재생성하면 DR 이 바뀌어 전 사용자 재프롬프트 — 재생성 금지(스크립트가 가드).
