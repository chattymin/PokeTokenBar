#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# 목업 세이브 파일 생성
python3 scripts/setup-qa-sound-save.py "$@"

export PTB_STATE_DIR="$HOME/.poketokenbar-qa-sound"

echo "=========================================================="
echo "🎮 PokeTokenBar 사운드 통합 로컬 QA 실행 환경"
echo "격리 상태 저장 디렉터리: $PTB_STATE_DIR (실제 세이브에 영향 없음)"
echo "=========================================================="
echo ""
echo "🎧 실제 앱 동작 연계 사운드 테스트 가이드:"
echo " 1. [홈 탭] 포켓몬 스프라이트 클릭 -> 짧은 탭 큐 (.tap)"
echo " 2. [가방 탭] 이상한 사탕 1개 사용 -> 상승 큐 (.levelUp) & +100M XP"
echo " 3. [가방 탭] 이상한 사탕 1개 더 사용 -> 홈 화면으로 전환되며 진화 큐 (.evolve)"
echo " 4. [가방 탭] 민트 1개 사용 -> 성격 변경 & 반짝임 큐 (.shiny)"
echo " 5. [상점 탭] 알/사탕 구매 -> 구매 완료 큐 (.buy)"
echo " 6. [설정 탭] 효과음 볼륨 조절 & 스피커 아이콘 테스트 버튼 -> 상승 큐 (.levelUp)"
echo ""
echo "💡 참고: 알 부화 사운드(.hatch)를 바로 테스트하려면 다음 옵션으로 실행하세요:"
echo "    ./scripts/launch-qa-sound.sh --egg"
echo "=========================================================="

# 기존에 실행 중인 디버그 인스턴스가 있다면 정리
pkill -f "\./\.build/debug/PokeTokenBar" 2>/dev/null || true

# 빌드 최신화
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build

echo "🚀 메뉴바에 PokeTokenBar 디버그 인스턴스가 실행됩니다."
exec ./.build/debug/PokeTokenBar
