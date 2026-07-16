#!/usr/bin/env bash
#
# release.sh — 버전 배포 자동화 + 문서(README/웹페이지/cask) 일관성 검토.
#
# 사용:
#   PTB_NOTES_FILE=/tmp/notes.md ./scripts/release.sh 2.1.1
#   ./scripts/release.sh 2.1.1            # 노트 파일 없으면 최소 노트
#   ./scripts/release.sh --check-only     # 문서 일관성 검토만(배포 안 함)
#
# 단계: 1)test-gate 2)문서 검토 3)VERSION 범프 4)build+zip 5)커밋·push
#       6)GitHub Release 7)Homebrew cask 8)Pages 재빌드. 각 단계 실패 시 즉시 중단(set -e).
#
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="chattymin/PokeTokenBar"
TAP_REPO="chattymin/homebrew-tap"
CASK_PATH="Casks/poke-token-bar.rb"

# ── 문서 일관성 검토 (배포 전 항상 실행) ───────────────────────────────────
# 기계적으로 잡을 수 있는 것만 자동 경고. 내용(기능 설명) 변경 여부는 사람이 체크리스트로 판단.
doc_check() {
  local warn=0
  echo "▶ 문서 일관성 검토"
  # 정적 버전 하드코딩(릴리스마다 수동 갱신 필요 → 동적 배지 권장)
  if grep -rnE "img.shields.io/badge/release-v[0-9]" README*.md 2>/dev/null; then
    echo "  ⚠ README 에 정적 버전 배지가 있습니다(동적 github/v/release 배지 권장)."; warn=1
  fi
  # 제거된 의존성/도구 흔적 (필요 시 PATTERN 에 추가)
  for pat in ccusage; do
    if grep -rniq "$pat" README*.md 2>/dev/null; then
      echo "  ⚠ README 에 '$pat' 잔존 — 제거된 항목인지 확인."; warn=1
    fi
  done
  # UI 변경 → 스크린샷 staleness (실제 diff 상태 검증 — 수동 체크리스트가 통과의례로 묻히지 않게).
  # 직전 릴리스 태그 이후 UI 소스가 바뀌었는데 assets 스크린샷이 안 바뀌었으면 README 이미지 stale 가능.
  local last_tag ui_changed shot_changed
  last_tag=$(git describe --tags --match "v*" --abbrev=0 2>/dev/null || echo "")
  if [[ -n "$last_tag" ]]; then
    ui_changed=$(git diff --name-only "$last_tag"..HEAD -- 'Sources/PokeTokenBar/UI/' 2>/dev/null)
    shot_changed=$(git diff --name-only "$last_tag"..HEAD -- 'assets/settings*' 'assets/screenshot*' 'assets/menubar*' 'assets/shiny*' 2>/dev/null)
    if [[ -n "$ui_changed" && -z "$shot_changed" ]]; then
      echo "  ⚠ UI 소스가 $last_tag 이후 변경됐으나 스크린샷(assets/) 갱신 없음 — README 이미지 stale 가능:"
      echo "$ui_changed" | sed 's/^/       /'
      echo "     → 변경된 화면이면 assets 스크린샷 재생성 (README.md/ko/ja 각 언어)."
      warn=1
    fi
  fi
  cat <<'CHECK'
  ─ 수동 체크리스트 (내용 변경 시 갱신) ─────────────────────────────
   [ ] README.md / .ko / .ja : 기능 목록·요구사항·데이터소스·스크린샷
   [ ] 랜딩(gh-pages/index.html): hero·features·install·works-with·요구사항·푸터
       · 버전 배지는 동적(github/v/release) → 자동. 기능/문구만 수동.
       · 3개 언어 i18n 사전(en/ko/ja) 동시 갱신 + 키 정합 유지.
   [ ] homebrew-tap cask: caveats(설치 요구사항) 최신 상태인지
  ─────────────────────────────────────────────────────────────────
CHECK
  return $warn
}

if [[ "${1:-}" == "--check-only" ]]; then
  doc_check || true
  exit 0
fi

VERSION="${1:?사용: release.sh <version>  (예: 2.1.1)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ 버전 형식 오류: $VERSION"; exit 1; }
PREV=$(grep -oE 'VERSION="[0-9.]+"' scripts/build-app.sh | grep -oE '[0-9.]+')
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$BRANCH" == "main" ]] || { echo "✗ main 브랜치에서 실행하세요 (현재: $BRANCH) — 커밋/push 대상 일치 보장"; exit 1; }
echo "=== PokeTokenBar 릴리스 $PREV → $VERSION ==="

echo "▶ 1/8 릴리스 전 테스트 게이트"
./scripts/test-gate.sh >/dev/null || { echo "✗ test-gate 실패 — 중단"; exit 1; }
echo "  ✓ 통과"

if ! doc_check; then
  read -r -p "  문서 경고가 있습니다. 그래도 계속? [y/N] " a
  [[ "$a" == "y" || "$a" == "Y" ]] || { echo "중단 — 문서 먼저 갱신하세요."; exit 1; }
fi

echo "▶ 코드서명 신원 게이트 (배포 전 — ad-hoc 릴리스 차단으로 사용자 Keychain '항상 허용' 유지)"
# 릴리스가 ad-hoc(빌드마다 cdhash 변경) 또는 다른 인증서로 나가면, 기존 사용자의 Keychain "항상 허용"이
# 앱의 지정요구(DR: identifier + certificate leaf)와 안 맞아 매 업그레이드마다 깨진다 → Claude 한도 조회 시
# macOS 키체인 접근 다이얼로그가 재프롬프트된다. 안정적 자체서명 신원(고정 leaf)으로만 배포되게 강제한다.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-PokeTokenBar Local}"
# "PokeTokenBar Local" leaf SHA-1 — 설치본 DR 의 certificate leaf pin. 인증서를 재생성/교체하면 갱신 필요.
EXPECTED_LEAF="507F814330C727B38AC9A987ECBA929721C52C62"
LEAF=$(security find-identity -v -p codesigning | awk -v id="\"$SIGN_IDENTITY\"" '$0 ~ id {print $2; exit}')
if [[ -z "$LEAF" ]]; then
  echo "✗ 유효 codesigning identity '$SIGN_IDENTITY' 없음(미설치·만료 포함)."
  echo "  이대로면 build-app.sh 가 ad-hoc 서명 → 이 릴리스로 올린 사용자 전원이 Keychain 을 재승인해야 한다."
  echo "  복구: ./scripts/create-signing-cert.sh 실행 → 새 leaf 로 이 스크립트의 EXPECTED_LEAF 갱신 → 재실행."
  exit 1
fi
if [[ "$LEAF" != "$EXPECTED_LEAF" ]]; then
  echo "⚠ 서명 인증서 leaf 불일치: 현재 $LEAF ≠ 고정 $EXPECTED_LEAF"
  echo "  인증서를 재생성/교체했다면, 이 릴리스로 업그레이드하는 기존 사용자 전원이 Keychain 을 1회 재승인해야 한다."
  read -r -p "  의도한 변경이면 EXPECTED_LEAF 를 갱신하고 계속하세요. 지금 계속? [y/N] " a
  [[ "$a" == "y" || "$a" == "Y" ]] || { echo "중단 — 서명 신원을 확인하세요."; exit 1; }
fi
echo "  ✓ '$SIGN_IDENTITY' leaf=$LEAF — 안정적 서명으로 배포(사용자 재프롬프트 없음)"
export PTB_REQUIRE_STABLE_SIGN=1   # build-app.sh 방어선: ad-hoc 폴백으로 새면 즉시 실패

echo "▶ 3/8 VERSION 범프 $PREV → $VERSION (아직 미커밋)"
perl -pi -e "s/VERSION=\"[0-9.]+\"/VERSION=\"$VERSION\"/" scripts/build-app.sh

echo "▶ 4/8 빌드 + zip (push 전 검증 — 실패해도 범프 미커밋이라 origin/main 무손상)"
./scripts/build-app.sh >/dev/null
rm -f build/PokeTokenBar.zip
ditto -c -k --keepParent build/PokeTokenBar.app build/PokeTokenBar.zip
BUILT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/PokeTokenBar.app/Contents/Info.plist)
[[ "$BUILT" == "$VERSION" ]] || { echo "✗ 빌드 버전 불일치: $BUILT (수동 복구: git checkout scripts/build-app.sh)"; exit 1; }

echo "▶ 5/8 커밋 + push (빌드 성공 후)"
git add scripts/build-app.sh
git commit -q -m "release: bump version to $VERSION

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push -q origin main

echo "▶ 6/8 GitHub Release v$VERSION"
NOTES_FILE="${PTB_NOTES_FILE:-}"
if [[ -n "$NOTES_FILE" && -f "$NOTES_FILE" ]]; then
  gh release create "v$VERSION" build/PokeTokenBar.zip --repo "$REPO" \
    --title "PokeTokenBar v$VERSION" --target main --notes-file "$NOTES_FILE"
else
  gh release create "v$VERSION" build/PokeTokenBar.zip --repo "$REPO" \
    --title "PokeTokenBar v$VERSION" --target main --notes "Release v$VERSION"
fi

echo "▶ 7/8 Homebrew cask $VERSION"
TMP_CASK=$(mktemp)
gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq '.content' | base64 -d \
  | perl -pe "s/version \"[0-9.]+\"/version \"$VERSION\"/" > "$TMP_CASK"
SHA=$(gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq '.sha')
gh api -X PUT "repos/$TAP_REPO/contents/$CASK_PATH" \
  -f message="cask: poke-token-bar $VERSION" \
  -f content="$(base64 -i "$TMP_CASK")" -f sha="$SHA" --jq '.commit.html_url'
rm -f "$TMP_CASK"

echo "▶ 8/8 GitHub Pages 재빌드(랜딩 동적 배지 갱신 유도)"
gh api -X POST "repos/$REPO/pages/builds" >/dev/null 2>&1 || true

echo "✓ v$VERSION 배포 완료. 검증: brew upgrade --cask poke-token-bar"
