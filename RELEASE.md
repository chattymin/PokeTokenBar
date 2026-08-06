# 릴리스 프로세스

버전 배포 시 **코드뿐 아니라 문서(README·웹페이지·cask)까지 일관되게** 갱신하기 위한 런북.
기계적 단계는 `scripts/release.sh` 가 자동화하고, 내용 판단이 필요한 부분은 아래 체크리스트로 검토한다.

## 한 줄 배포

```bash
# (선택) 릴리스 노트를 파일로 작성
cat > /tmp/notes.md <<'EOF'
## What's new
- ...
EOF

PTB_NOTES_FILE=/tmp/notes.md ./scripts/release.sh 2.1.1
```

`scripts/release.sh <version>` 가 순서대로 수행:

1. **test-gate** (`./scripts/test-gate.sh`) — 전체 테스트 + 로직 커버리지. 실패 시 중단.
2. **문서 일관성 검토** — 정적 버전 배지·제거된 의존성(예: `ccusage`) 잔존을 자동 경고 + 아래 수동 체크리스트 출력. 경고 시 진행 여부를 묻는다.
3. **VERSION 범프** (`scripts/build-app.sh`, 아직 미커밋).
4. **빌드 + zip** (`build/PokeDexBar.zip`) + 빌드 버전 일치 확인 — **push 전 검증**(실패해도 범프 미커밋이라 origin/main 무손상).
5. **커밋 + push** (`git push origin main`, 빌드 성공 후).
6. **GitHub Release** 생성 (노트는 `PTB_NOTES_FILE` 또는 최소 노트).
7. **Homebrew cask** 버전 갱신 (`donky-ey/homebrew-tap`).
8. **GitHub Pages 재빌드** 요청 (랜딩 동적 배지 갱신 유도).

> `main` 브랜치에서만 실행(스크립트가 가드). 비-main 에서 실행 시 즉시 중단.

검토만 하려면: `./scripts/release.sh --check-only`

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
brew update && brew upgrade --cask poke-dex-bar
```

`brew list --cask --versions poke-dex-bar` 와 `/Applications/PokeDexBar.app` 버전이 새 버전인지 확인.

## 서명 (2026-07-08 부터)

릴리스 빌드는 이 머신의 `PokeDexBar Local` 자체서명 인증서로 서명된다
(`scripts/create-signing-cert.sh` 로 생성, keychain 에만 존재 — 레포 미커밋).
- designated requirement 가 버전 간 고정 → 사용자의 Keychain "항상 허용"이 업데이트 후에도 유지.
- 전환 직후 첫 업데이트 1회는 기존(ad-hoc 시절) 허용이 무효라 마지막 프롬프트가 뜰 수 있음.
- 인증서를 분실/재생성하면 DR 이 바뀌어 전 사용자 재프롬프트 — 재생성 금지(스크립트가 가드).
