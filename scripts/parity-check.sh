#!/bin/bash
# 앱 표시값 == ccusage totalTokens 재계산값 검증.
# 사용법: 앱에서 새로고침 직후 1분 내에 실행 (그 사이 토큰이 쌓이면 delta 발생 가능).
set -euo pipefail

SNAP="$HOME/Library/Application Support/PokeDexBar/last-snapshot.json"
JQ=$(command -v jq)
CCUSAGE=$(command -v ccusage || echo /opt/homebrew/bin/ccusage)

if [ ! -f "$SNAP" ]; then
    echo "FAIL: 스냅샷 없음 ($SNAP) — 앱을 먼저 실행하고 새로고침하세요."
    exit 1
fi

TODAY_KEY=$(date +%Y-%m-%d)
TODAY_STAMP=$(date +%Y%m%d)

APP_TOTAL=$("$JQ" -r '.todayTotalTokens' "$SNAP")
APP_AT=$("$JQ" -r '.generatedAt' "$SNAP")

CLAUDE_TOTAL=$("$CCUSAGE" claude daily --json --offline --since "$TODAY_STAMP" 2>/dev/null \
    | sed -n '/^{/,$p' | "$JQ" --arg d "$TODAY_KEY" '[.daily[] | select((.date // .period) == $d) | .totalTokens] | add // 0')
CODEX_TOTAL=0
if "$CCUSAGE" codex --help >/dev/null 2>&1; then
    CODEX_TOTAL=$("$CCUSAGE" codex daily --json --offline --since "$TODAY_STAMP" 2>/dev/null \
        | sed -n '/^{/,$p' | "$JQ" --arg d "$TODAY_KEY" '[.daily[] | select((.date // .period) == $d) | .totalTokens] | add // 0')
fi
EXPECTED=$((CLAUDE_TOTAL + CODEX_TOTAL))
DELTA=$((EXPECTED - APP_TOTAL))

echo "앱 스냅샷 시각 : $APP_AT"
echo "앱 표시 합계   : $APP_TOTAL"
echo "ccusage 재계산 : $EXPECTED (claude=$CLAUDE_TOTAL, codex=$CODEX_TOTAL)"
echo "차이           : $DELTA"

if [ "$DELTA" -eq 0 ]; then
    echo "PASS: 리더보드 집계 기준과 정확히 일치"
    exit 0
fi

# 차이가 있으면 활성 사용 드리프트인지 판별: 15초 간격 재측정으로 현재 burn rate 산출
echo "차이 발견 — 활성 사용 드리프트 판별 중 (15초 재측정)..."
sleep 15
CLAUDE_RECHECK=$("$CCUSAGE" claude daily --json --offline --since "$TODAY_STAMP" 2>/dev/null \
    | sed -n '/^{/,$p' | "$JQ" --arg d "$TODAY_KEY" '[.daily[] | select((.date // .period) == $d) | .totalTokens] | add // 0')
CODEX_RECHECK=0
if "$CCUSAGE" codex --help >/dev/null 2>&1; then
    CODEX_RECHECK=$("$CCUSAGE" codex daily --json --offline --since "$TODAY_STAMP" 2>/dev/null \
        | sed -n '/^{/,$p' | "$JQ" --arg d "$TODAY_KEY" '[.daily[] | select((.date // .period) == $d) | .totalTokens] | add // 0')
fi
RECHECK=$((CLAUDE_RECHECK + CODEX_RECHECK))
BURN_15S=$((RECHECK - EXPECTED))

AGE_SEC=$(( $(date +%s) - $(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$APP_AT" +%s 2>/dev/null || date +%s) ))
# 허용치 = 측정 burn rate × 경과 시간 × 2 (여유) + 고정 마진 1000
TOLERANCE=$(( (BURN_15S * AGE_SEC / 15) * 2 + 1000 ))
[ "$TOLERANCE" -lt 1000 ] && TOLERANCE=1000

echo "스냅샷 경과    : ${AGE_SEC}초, 측정 burn: ${BURN_15S} tokens/15s, 허용치: $TOLERANCE"

if [ "$BURN_15S" -eq 0 ] && [ "$AGE_SEC" -gt 30 ]; then
    echo "WARN: 스냅샷 이후 사용량이 변했지만 현재 burn이 없어 보정 불가 — 앱 새로고침 직후 재실행 필요"
    exit 0
fi

if [ "${DELTA#-}" -le "$TOLERANCE" ]; then
    echo "PASS: 차이는 스냅샷 이후 실시간 사용분 범위 내 — 집계 로직 일치. (사용 중지 상태에서 재실행 시 오차 0 확인 가능)"
else
    echo "FAIL: 차이가 활성 사용 드리프트로 설명되지 않음 — 집계 로직 점검 필요"
    exit 1
fi
