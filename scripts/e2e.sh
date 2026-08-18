#!/usr/bin/env bash
#
# e2e.sh — 실제 앱 번들 스모크 E2E (1인 로컬 GUI 세션용).
#
# 검증 단계:
#   1) 빌드 + /Applications 설치   2) 기동(프로세스 생존)
#   3) 데이터 파이프라인 — last-snapshot.json 이 이번 세션에서 갱신되고 구조/값이 유효
#   4) 메뉴바 status item — window server 에 앱 소유 status-bar 레이어 윈도우 존재
#   5) 팝오버 오픈 — Accessibility 권한 있으면 클릭→윈도우 출현 확인(없으면 SKIP)
#
# XCUITest 미채택 근거: SwiftPM 단독 레포에 Xcode 프로젝트/테스트 번들 도입 필요 — 1인 로컬 over-spec.
# 사용:  ./scripts/e2e.sh          (GUI 세션에서 실행. 5단계는 터미널에 손쉬운 사용 권한 필요)
#
set -uo pipefail
cd "$(dirname "$0")/.."

APP="/Applications/PokeTokenBar.app"
LOG="$HOME/Library/Logs/PokeTokenBar.log"
SNAP="$HOME/Library/Application Support/PokeTokenBar/last-snapshot.json"
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
skip() { echo "  – SKIP: $1"; SKIP=$((SKIP+1)); }

echo "▶ 1/5 빌드 + 설치"
if ./scripts/build-app.sh >/tmp/ptb-e2e-build.log 2>&1; then ok "build-app.sh"; else bad "빌드 실패 (/tmp/ptb-e2e-build.log)"; exit 1; fi

echo "▶ 2/5 기동"
MARK=$(date +%s)
open "$APP" || sleep 2 && open "$APP" 2>/dev/null   # LaunchServices -600 재시도
sleep 2
INSTANCES=$(pgrep -x PokeTokenBar | wc -l | tr -d ' ')
case "$INSTANCES" in
  0) bad "프로세스 없음"; exit 1 ;;
  1) ok "프로세스 생존, 단일 인스턴스 (pid $(pgrep -x PokeTokenBar))" ;;
  # 로그인 에이전트 등록(RunAtLoad)이 이미 떠 있는 앱을 한 번 더 실행하던 회귀 — SingleInstance 가드가
  # 막는다. launchd 경계는 단위 테스트로 못 밟으니 개수 검사를 여기 둔다(defect-log 프로세스·인스턴스).
  *) bad "인스턴스 $INSTANCES 개 — 중복 실행 (pid $(pgrep -x PokeTokenBar | tr '\n' ' '))" ;;
esac

echo "▶ 3/5 데이터 파이프라인 (스냅샷 갱신 대기, 최대 90s)"
found=""
for _ in $(seq 1 45); do
  if [[ -f "$SNAP" && $(stat -f %m "$SNAP") -ge "$MARK" ]]; then found=1; break; fi
  sleep 2
done
if [[ -n "$found" ]]; then ok "last-snapshot.json 이번 세션에 갱신"; else bad "스냅샷 90s 내 미갱신"; fi
if python3 - "$SNAP" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
assert isinstance(s["todayTotalTokens"], int) and s["todayTotalTokens"] >= 0
assert isinstance(s["providers"], list)
assert s.get("lastError", "") == "", f"lastError: {s['lastError']}"
print(f"    today={s['todayTotalTokens']:,} providers={[p['id'] for p in s['providers']]}")
PY
then ok "스냅샷 구조·값 유효 + lastError 없음"; else bad "스냅샷 구조/에러 검증 실패"; fi
if tail -n 100 "$LOG" 2>/dev/null | grep -q "phase1 done"; then ok "AppLog phase1 done"; else bad "AppLog 에 phase1 done 없음"; fi

echo "▶ 4/5 메뉴바 status item (window server)"
cat > /tmp/ptb-e2e-win.swift <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
var status = 0, tall = 0
for w in list where (w[kCGWindowOwnerName as String] as? String) == "PokeTokenBar" {
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    let bounds = w[kCGWindowBounds as String] as? [String: Any]
    let h = bounds?["Height"] as? Double ?? 0
    if layer == 25 { status += 1 }          // NSStatusWindowLevel
    if h > 200 { tall += 1 }                 // 팝오버 등 본문 윈도우
}
print("STATUS=\(status) TALL=\(tall)")
SWIFT
# 사전 컴파일 — swift 인터프리터 콜드 스타트(수 초)가 타이밍 검증을 깨지 않도록.
swiftc -O -o /tmp/ptb-e2e-win /tmp/ptb-e2e-win.swift 2>/dev/null
winprobe() { /tmp/ptb-e2e-win 2>/dev/null; }
# 1차: AX 로 status item 존재 확인(결정적). AX 미허용이면 window server 폴백
# (주의: status 윈도우는 앱 최초 활성화 전 CGWindowList 에 안 잡힐 수 있음 — 관측된 macOS 동작).
AXCNT=$(osascript -e 'tell application "System Events" to tell process "PokeTokenBar" to get count of menu bar items of menu bar 2' 2>/dev/null)
if [[ "${AXCNT:-}" =~ ^[0-9]+$ ]]; then
  if [[ "$AXCNT" -ge 1 ]]; then ok "status item 존재 (AX, count=$AXCNT)"; else bad "status item 없음 (AX count=0)"; fi
else
  W=$(winprobe); STATUS=$(echo "$W" | grep -oE 'STATUS=[0-9]+' | cut -d= -f2)
  if [[ "${STATUS:-0}" -ge 1 ]]; then ok "status item 윈도우 존재 ($W)"
  else skip "AX 미허용 + 활성화 전 윈도우 미등록 — 손쉬운 사용 권한 부여 시 결정적 검증"; fi
fi

echo "▶ 5/5 팝오버 오픈 (Accessibility)"
# click 이 아니라 AXPress — click 은 좌표 기반이라 비활성 앱에서 액션이 발화되지 않는 경우가 있음(관측).
press() { osascript -e 'tell application "System Events" to tell process "PokeTokenBar" to perform action "AXPress" of menu bar item 1 of menu bar 2' >/dev/null 2>&1; }
polltall() { # $1=횟수(0.5s 간격)
  TALL=0
  for _ in $(seq 1 "$1"); do
    W2=$(winprobe); TALL=$(echo "$W2" | grep -oE 'TALL=[0-9]+' | cut -d= -f2)
    [[ "${TALL:-0}" -ge 1 ]] && return 0; sleep 0.5
  done; return 1
}
if press; then
  # 기동 직후 첫 AXPress 가 무시되는 경우가 있어(AX 트리 워밍업) 미출현 시 1회 재시도.
  if ! polltall 6; then press; polltall 12 || true; fi
  if [[ "${TALL:-0}" -ge 1 ]]; then ok "팝오버 윈도우 출현 ($W2)"; else bad "AXPress 후 팝오버 미검출 ($W2)"; fi
  osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1   # ESC 로 닫기
else
  skip "Accessibility 미허용 — 시스템 설정 > 손쉬운 사용에서 터미널 허용 시 검증됨"
fi

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[[ "$FAIL" -eq 0 ]] || exit 1
