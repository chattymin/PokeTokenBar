#!/usr/bin/env bash
#
# test-gate.sh — 안정성 가드레일. 커밋/머지 전 수동 실행 (1인 로컬, CI 없음).
#
#   1) swift test 전체 통과
#   2) "로직 코어" 파일 집합의 라인 커버리지 >= THRESHOLD
#
# 로직 코어 = 결정적으로 단위 테스트 가능한 파일만 포함. ProcessRunner / PokeAPIClient /
# CcusageProvider / CodexRateLimitsProvider / OAuthLimitsProvider / UpdateChecker /
# BinaryLocator 는 실제 서브프로세스·네트워크·Keychain 의존이라 단위 커버리지 대상에서 제외
# (해당 부분은 파서/순수 헬퍼만 별도로 테스트됨).
#
# 사용:  ./scripts/test-gate.sh          # 게이트 실행
#        THRESHOLD=75 ./scripts/test-gate.sh   # 임계값 임시 상향
#
set -euo pipefail
cd "$(dirname "$0")/.."

THRESHOLD="${THRESHOLD:-75}"

LOGIC_CORE=(
  "Sources/PokeTokenBar/Core/CompanionModel.swift"
  "Sources/PokeTokenBar/Core/CompanionStore.swift"
  "Sources/PokeTokenBar/Core/UsageStore.swift"
  "Sources/PokeTokenBar/Core/Models.swift"
  "Sources/PokeTokenBar/Core/TokenFormatter.swift"
  "Sources/PokeTokenBar/Core/UsageProvider.swift"
  "Sources/PokeTokenBar/Core/LocalUsageReader.swift"
  "Sources/PokeTokenBar/Core/LocalUsageCache.swift"
  "Sources/PokeTokenBar/Core/ModelPricing.swift"
)

echo "▶ swift test (--enable-code-coverage)"
swift test --enable-code-coverage

PROF=$(find .build -name 'default.profdata' | head -1)
# dSYM 안에도 같은 이름의 DWARF 바이너리가 있어 head -1 이 그걸 집으면 llvm-cov 가 실패한다 → 제외.
# Linux 의 테스트 산출물은 `.xctest` 접미사를 달고 나오므로 두 이름을 모두 받는다.
BIN=$(find .build \( -name 'PokeTokenBarPackageTests' -o -name 'PokeTokenBarPackageTests.xctest' \) \
  -type f ! -path '*.dSYM/*' | head -1)

# 커버리지 도구 — macOS 는 xcrun, Linux 는 스위프트 툴체인 안의 llvm-cov(보통 PATH 에 없다).
# 하드코딩하면 한쪽 플랫폼에서 게이트가 통째로 안 돈다.
if command -v xcrun >/dev/null 2>&1; then
  LLVM_COV=(xcrun llvm-cov)
elif [[ -x "$(dirname "$(readlink -f "$(command -v swift)")")/llvm-cov" ]]; then
  LLVM_COV=("$(dirname "$(readlink -f "$(command -v swift)")")/llvm-cov")
elif command -v llvm-cov >/dev/null 2>&1; then
  LLVM_COV=(llvm-cov)
else
  echo "✗ llvm-cov 를 찾지 못했습니다(커버리지 게이트 실행 불가)." >&2
  exit 1
fi
if [[ -z "$PROF" || -z "$BIN" ]]; then
  echo "✗ 커버리지 산출물(profdata/binary)을 찾지 못했습니다." >&2
  exit 1
fi

echo
echo "▶ 로직 코어 커버리지 (임계값 ${THRESHOLD}%)"
REPORT=$("${LLVM_COV[@]}" report "$BIN" -instr-profile="$PROF" "${LOGIC_CORE[@]}" 2>/dev/null)
echo "$REPORT"

# TOTAL 행의 라인 커버리지(%) 추출 — 컬럼: ... Lines MissedLines Cover(=$10)
COVER=$(echo "$REPORT" | awk '/^TOTAL/ { gsub("%","",$10); print $10 }')
if [[ -z "$COVER" ]]; then
  echo "✗ 커버리지 수치 파싱 실패." >&2
  exit 1
fi

echo
# 소수 비교는 awk 로 (bash 정수 비교 회피)
if awk "BEGIN { exit !($COVER >= $THRESHOLD) }"; then
  echo "✓ 게이트 통과 — 로직 코어 라인 커버리지 ${COVER}% >= ${THRESHOLD}%"
else
  echo "✗ 게이트 실패 — 로직 코어 라인 커버리지 ${COVER}% < ${THRESHOLD}%" >&2
  echo "  테스트를 보강하거나, 의도된 하락이면 THRESHOLD 를 조정하세요." >&2
  exit 1
fi
