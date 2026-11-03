#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

SCRATCH_PATH="$(mktemp -d "${TMPDIR:-/tmp}/poketokenbar-perf.XXXXXX")"
trap 'rm -rf "$SCRATCH_PATH"' EXIT

./scripts/swiftpm.sh build --scratch-path "$SCRATCH_PATH" -c release

POKETOKENBAR_RUN_LARGE_PERF=1 /usr/bin/time -l \
  ./scripts/swiftpm.sh test --scratch-path "$SCRATCH_PATH" -c release \
  --filter 'CodexLargeRolloutPerformanceTests/testCodexLargeRolloutStaysWithinMemoryBudget'

./scripts/swiftpm.sh test --scratch-path "$SCRATCH_PATH" --filter 'LocalUsageReaderTests|LocalUsageCacheTests'
./scripts/swiftpm.sh test --scratch-path "$SCRATCH_PATH"
