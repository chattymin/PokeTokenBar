#!/usr/bin/env bash
#
# simulate-tokens.sh — Grok 세션 턴 완료 이벤트 및 PokeTokenBar 상태에 시뮬레이션 토큰을 추가합니다.
#
# 사용법:
#   ./scripts/simulate-tokens.sh           # 기본값 50m (50,000,000 토큰) 추가
#   ./scripts/simulate-tokens.sh 25m        # 25m (25,000,000 토큰) 추가
#   ./scripts/simulate-tokens.sh 36k        # 36k (36,000 토큰) 추가
#   ./scripts/simulate-tokens.sh 4b         # 4b (4,000,000,000 토큰) 추가
#   ./scripts/simulate-tokens.sh 250m       # 250m (250,000,000 토큰) 추가
#   ./scripts/simulate-tokens.sh --clear    # 테스트용 시뮬레이션 세션 및 상태 지우기
#

set -euo pipefail

SESSION_DIR="$HOME/.grok/sessions/simulated-token-gain"
UPDATES_FILE="$SESSION_DIR/updates.jsonl"
SUMMARY_FILE="$SESSION_DIR/summary.json"
STATE_FILE="$HOME/Library/Application Support/PokeTokenBar/companion-state.json"

if [[ "${1:-}" == "--clear" ]]; then
    if [[ -d "$SESSION_DIR" ]]; then
        rm -rf "$SESSION_DIR"
        echo "🗑️ 시뮬레이션 토큰 세션 디렉토리를 지웠습니다: $SESSION_DIR"
    else
        echo "ℹ️ 지울 시뮬레이션 세션이 없습니다."
    fi
    exit 0
fi

RAW_INPUT="${1:-50m}"

# K/M/B 단위 및 소수점 파싱
AMOUNT=$(python3 -c "
import sys, re
val = sys.argv[1].strip().lower().replace('_', '')
m = re.match(r'^([0-9]+(?:\.[0-9]+)?)([kmb])?$', val)
if not m:
    sys.exit(1)
num = float(m.group(1))
unit = m.group(2)
if unit == 'k':
    total = int(num * 1_000)
elif unit == 'm':
    total = int(num * 1_000_000)
elif unit == 'b':
    total = int(num * 1_000_000_000)
else:
    total = int(num)
print(total)
" "$RAW_INPUT" 2>/dev/null || echo "INVALID")

if [[ "$AMOUNT" == "INVALID" || "$AMOUNT" -le 0 ]]; then
    echo "❌ 오류: 올바른 토큰 수량을 입력하세요. (예: 25m, 36k, 4b, 250m, 50000000)" >&2
    echo "   입력값: '$RAW_INPUT'" >&2
    exit 1
fi

# 1. Grok 세션 디렉토리 및 summary.json 생성
mkdir -p "$SESSION_DIR"
if [[ ! -f "$SUMMARY_FILE" ]]; then
    cat <<EOF > "$SUMMARY_FILE"
{
  "session_id": "simulated-token-gain",
  "session_kind": "chat"
}
EOF
fi

TIMESTAMP=$(date +%s)
UUID=$(uuidgen 2>/dev/null || echo "turn-$(date +%s%N)")

# 3. Grok updates.jsonl 에 turn_completed 이벤트 추가
JSON_LINE="{\"timestamp\":$TIMESTAMP,\"method\":\"_x.ai/session/update\",\"params\":{\"sessionId\":\"simulated-token-gain\",\"update\":{\"sessionUpdate\":\"turn_completed\",\"prompt_id\":\"$UUID\",\"usage\":{\"inputTokens\":$AMOUNT,\"outputTokens\":0,\"totalTokens\":$AMOUNT}}}}"

echo "$JSON_LINE" >> "$UPDATES_FILE"
touch "$UPDATES_FILE"

# 포맷팅 표시 (e.g. 25M, 36K, 4B)
if (( AMOUNT >= 1000000000 )); then
    DISPLAY="$(bc -l <<< "scale=2; $AMOUNT/1000000000")B"
elif (( AMOUNT >= 1000000 )); then
    DISPLAY="$(bc -l <<< "scale=1; $AMOUNT/1000000")M"
elif (( AMOUNT >= 1000 )); then
    DISPLAY="$(bc -l <<< "scale=1; $AMOUNT/1000")K"
else
    DISPLAY="$AMOUNT"
fi

echo "✅ 시뮬레이션 토큰 +$AMOUNT ($DISPLAY) 이벤트 추가 완료! (입력: '$RAW_INPUT')"
echo "📍 세션 파일: $UPDATES_FILE"
echo "💡 PokeTokenBar 가 다음 새로고침 틱(또는 메뉴 바 '지금 새로고침')에 토큰 수증량을 반영합니다."
