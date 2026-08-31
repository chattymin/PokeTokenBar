<div align="center">

<img src="assets/icon.png" width="128" alt="PokeTokenBar 아이콘">

# PokeTokenBar

**당신의 AI 코딩 토큰을 포켓몬으로 — 메뉴바에서.**

[![Release](https://img.shields.io/github/v/release/chattymin/PokeTokenBar?color=444d56&label=release)](https://github.com/chattymin/PokeTokenBar/releases)
[![macOS](https://img.shields.io/badge/macOS-14%2B-0969da)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-f05138)](https://swift.org)
[![Homebrew](https://img.shields.io/badge/Homebrew-cask-8957e5)](#homebrew)
[![License](https://img.shields.io/badge/license-MIT-3fb950)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%99%A5-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/chattymin)

<a href="https://trendshift.io/repositories/84522?utm_source=repository-badge&amp;utm_medium=badge&amp;utm_campaign=badge-repository-84522" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/repositories/84522" alt="chattymin%2FPokeTokenBar | Trendshift" width="250" height="55"/></a>
<a href="https://trendshift.io/repositories/84522?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-84522" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/84522/daily?language=Swift" alt="chattymin%2FPokeTokenBar | Trendshift" width="250" height="55"/></a>


[English](README.md) · **한국어** · [日本語](README.ja.md)

</div>

PokeTokenBar는 당신이 이미 태우고 있는 AI 코딩 토큰(Claude Code · Codex · Gemini CLI · Antigravity · OpenCode · Hermes Agent · Cursor · Grok CLI · Copilot CLI · Kiro CLI · Pi Agent · omp)을 macOS 메뉴바 속 자라나는 **포켓몬 companion**으로 바꿔줍니다. 토큰을 쓰면 알이 부화하고, 실제 진화 라인을 따라 진화하며, 최종 진화 후 도감에 졸업하고, 다시 새 알이 시작됩니다. companion 아래에는 정확한 사용량 트래커가 있습니다 — 오늘의 사용량·비용, 공식 5시간/주간 한도를 로컬 로그에서 직접 읽습니다.

> 토큰 사용량은 로컬 Claude Code·Codex·Gemini CLI·Antigravity·OpenCode·Hermes Agent·Cursor·Grok CLI·Copilot CLI·Kiro CLI·Pi Agent·omp 데이터에서 직접 읽습니다(`totalTokens` = input + output + cache, 로컬 날짜) — 외부 CLI 불필요. 비공식·비상업 포켓몬 팬 프로젝트 — [라이선스 & 면책](#라이선스--면책) 참고.

## 왜

- **열어보는 게 즐거운 사용량 트래커.** 사용량이 포켓몬을 키웁니다 — 부화하고, 진화하고, 졸업해 도감을 채우죠. 이로치 한 마리가 다시 열어볼 이유가 됩니다.
- 오늘의 토큰 사용량과 비용을 한눈에 — 대시보드도, 브라우저 탭도 필요 없이.
- 공식 **5시간 / 주간** 한도를 리셋 카운트다운과 함께 추적하고, 현재 burn rate로 언제 도달할지 예측합니다.

<div align="center">
<img src="assets/screenshot-home.gif" width="420" alt="팝오버 홈 — companion, 오늘 토큰, 공식 한도">
</div>

## 어떻게 자라나요

1. 🥚 **평소처럼 코딩하세요.** Claude Code·Codex·Gemini CLI·Antigravity·OpenCode·Hermes Agent·Cursor·Grok CLI·Copilot CLI·Kiro CLI·Pi Agent·omp에서 태우는 토큰이 알을 품습니다 — 따로 돌릴 건 없어요.
2. 🐣 **부화.** [PokéAPI](https://pokeapi.co/)의 **1~5세대 모든 진화 계보(시작점 329종)**에서 공식 capture rate 가중으로 태어납니다 — 흔한 포켓몬은 자주, 전설은 부화 129번에 1번. 부화한 포켓몬은 키우는 동안에도 **도감**에 바로 나타납니다. 부화마다 25종 성격 중 하나가 정해지고 — **아주 특별한 우연으론 ✨ 이로치가 태어납니다**.
3. ⚡ **진화.** 계속 코딩하면 실제 진화 트리(1/2/3단, 분기)를 따라 자라고, 단계마다 작은 연출이 반겨줍니다.
4. 🎓 **졸업 & 수집.** 최종 진화 + 임계 도달 시 **도감**에 영구 보존됩니다 — 희귀할수록 오래 걸리고(헤비 유저 기준 common ≈3일 → legendary ≈24일) — 새 알이 도착합니다.
5. 🍬 **한도 채우고 사탕 받기.** 5시간 또는 주간 사용량 한도를 다 채우면 **이상한 사탕**을 받아요 — 새 **가방** 탭에서 써서 현재 포켓몬을 키우세요.
6. 🛒 **상점에서 쓰기.** 그동안 사용한 토큰이 곧 재화입니다 — 새 **상점** 탭에서 **이상한 사탕**, 포켓몬 성격을 랜덤으로 다시 굴리는 **민트**, 이로치 확률을 영구히 올리는 **이로치 부적**, 또는 지금 포켓몬을 놓아주고 다시 시작하는 알을 살 수 있어요. 알은 세 종류입니다 — 일반 **포켓몬 알**, 고급 이상이 확정으로 나오는 **고급 알**, 희귀 이상이 확정으로 나오는 **희귀 알**.

## 둘러보기

<table>
<tr>
<td width="45%" align="center"><img src="assets/floating-pet.gif" width="340" alt="바탕화면 플로팅 펫 — 호버 콜아웃과 우클릭 메뉴"></td>
<td width="55%" valign="middle">
<h3>🐾 바탕화면에 두기</h3>
파트너를 메뉴바 밖 바탕화면으로 꺼내 48~192px 원하는 크기로 둘 수 있어요. 호버하면 오늘 사용량, 클릭하면 팝오버, 우클릭하면 메뉴, 드래그로 위치 이동 — 한도 알림은 펫 위 말풍선으로도 떠요.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>메뉴바 속 파트너</h3>
움직이는 Gen-V 스프라이트가 오늘 토큰 합계(compact, 예: <code>200.7M</code>) 옆에 삽니다. 오늘 비용(<code>$</code>)이나 공식 한도 <code>%</code> 를 더하거나 — 전부 꺼서 캐릭터만 남길 수도 있어요.
</td>
<td width="45%" align="center"><img src="assets/menubar.gif" width="240" alt="메뉴바"></td>
</tr>
<tr>
<td width="45%" align="center"><img src="assets/shiny-banner.gif" width="340" alt="일반 vs 이로치"></td>
<td width="55%" valign="middle">
<h3>✨ 아주 드문 우연, 이로치</h3>
이로치는 메뉴바·홈 카드·진화 라인에서 전용 색으로 표시되고, 진화를 거쳐도 유지됩니다. 도감에서는 번호 옆에 ✨가 붙고, 칸을 탭하면 이로치 색으로 바뀝니다. 전용 알림이 그 순간을 놓치지 않게 해줘요.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>채우고 싶어지는 도감</h3>
<b>도감</b>은 보유한 종을 한 칸으로 접어 도감 번호순으로 보여줍니다 — 한 페이지 24칸, 이로치로 잡은 종에는 ✨가 붙어요. <b>포획 로그</b>는 개체를 그대로 남깁니다: 최신순으로 전체 진화 라인·희귀도·성격·획득일까지.
</td>
<td width="45%" align="center"><img src="assets/screenshot-collection-pokedex.png" width="300" alt="도감 — 종 하나가 한 칸"><br><br><img src="assets/screenshot-collection-catchlog.png" width="300" alt="포획 로그 — 키운 개체 하나가 한 행"></td>
</tr>
<tr>
<td width="45%" align="center"><img src="assets/settings-ko.png" width="300" alt="설정"></td>
<td width="55%" valign="middle">
<h3>설정에서 취향대로</h3>
메뉴바 표시 항목, 새로고침 간격(1–15분/수동), 로그인 시 자동 시작, 한도 섹션만 숨기는 Keychain 끄기, 경고/임박 임계값 한도 알림, companion 이벤트 알림. <b>한국어/영어/일본어/스페인어/프랑스어/포르투갈어</b> UI·포켓몬 이름 완비.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>🍬 한도를 채우면 이상한 사탕</h3>
5시간 또는 주간 사용량 한도를 다 채우면 <b>이상한 사탕</b>을 받습니다 — 5시간 한도당 1개, 주간 한도당 5개. 새 <b>가방</b> 탭에서 현재 포켓몬에게 써서 키우세요: 막히는 순간이 곧 성장하는 순간이 됩니다.
</td>
<td width="45%" align="center"><img src="assets/screenshot-bag-ko.png" width="300" alt="가방 속 이상한 사탕과 민트"></td>
</tr>
<tr>
<td width="45%" align="center"><img src="assets/screenshot-shop-ko.png" width="300" alt="토큰 상점 — 민트·이상한 사탕·포켓몬 알·고급 알·이로치 부적·희귀 알"></td>
<td width="55%" valign="middle">
<h3>🛒 사용량으로 돌아가는 상점</h3>
그동안 쓴 토큰이 곧 재화입니다 — 새 <b>상점</b> 탭에서 <b>이상한 사탕</b>으로 현재 포켓몬을 키우거나, <b>민트</b>로 성격을 다시 굴리거나, <b>이로치 부적</b>으로 이로치 확률을 영구히 올리거나, 알을 사서 지금 포켓몬을 놓아주고 다시 시작하세요. 알은 세 종류입니다 — 일반 <b>포켓몬 알</b>, 고급 이상이 확정으로 나오는 <b>고급 알</b>, 희귀 이상이 확정으로 나오는 <b>희귀 알</b>. 등급 알에도 전설은 그대로 섞여 있어서, 확정 부화에도 깜짝 놀랄 여지가 남습니다.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>📊 공식 한도, 이제 Antigravity 도</h3>
Antigravity 2.0 과 IDE 가 추정치가 아닌 실제 할당량을 보고합니다. Gemini 모델군과 Claude &amp; GPT 모델군이 각각 <b>5시간</b>·<b>주간</b> 버킷과 리셋 카운트다운을 갖고, Claude Code·Codex 와 나란히 표시됩니다. 백그라운드에서 조용히 읽어와서 Keychain 팝업이 뜨지 않고, 세션도 알아서 갱신됩니다.
</td>
<td width="45%" align="center"><img src="assets/screenshot-antigravity-limits-ko.png" width="300" alt="Antigravity 공식 한도 — 모델군별 5시간·주간 버킷"></td>
</tr>
<tr>
<td width="45%" align="center"><img src="assets/screenshot-scan-folders-ko.png" width="300" alt="설정 → 고급의 추가 스캔 폴더"></td>
<td width="55%" valign="middle">
<h3>📁 로그가 엉뚱한 데 있다면 직접 지정</h3>
어떤 도구가 세션을 기본 경로 밖에 둔다면 <b>설정 → 고급</b>에서 직접 루트를 추가하세요 — 콤마·줄바꿈 구분, <code>*</code> 와일드카드, 지금 몇 개 폴더가 걸리는지 실시간 표시. 프로바이더마다 목록이 따로라 한 도구의 폴더가 다른 도구의 파서로 넘어가지 않고, 추가한 경로는 기본 경로를 대체하는 게 아니라 더해집니다.
</td>
</tr>
</table>

## 이 밖에도

- **대표 포켓몬** — 도감에서 보유한 종을 골라 현재 키우는 포켓몬과 별개로 메뉴바와 선택적 플로팅 펫에 고정. 고정 중에는 메뉴바가 알·부화·진화를 따라가지 않지만, 육성 과정은 Home에서 계속 확인할 수 있습니다.
- **애니메이션 품질** — 메뉴바 스프라이트와 플로팅 펫이 얼마나 부드럽게 움직일지 고릅니다(배터리 절약 / 기본 / 부드럽게). 상시 표시되는 두 표면이 같은 설정을 씁니다. 기본값 "배터리 절약"은 이 설정이 생기기 전과 같은 프레임 레이트이고, "기본"·"부드럽게"는 배터리를 더 씁니다(실측 유휴 CPU 약 1.8% / 약 5.1%).
- **인터랙티브 플로팅 펫** — 호버로 오늘 사용량, 클릭으로 메인 창, 우클릭 메뉴, 한도 알림은 말풍선으로 표시.
- **서비스별 탭** — Claude Code·Codex·Gemini CLI·Antigravity·OpenCode·Hermes Agent·Cursor·Grok CLI·Copilot CLI·Kiro CLI·Pi Agent·omp 중 2개 이상 감지되면 작은 탭으로 상세를 서비스별 전환(오늘 합계는 통합 유지).
- **공식 한도** — Claude·Codex·Antigravity 5시간/주간 사용률 + 리셋 카운트다운을 오늘 숫자 바로 아래에.
- **추가 스캔 폴더** — 기본 경로 밖에 있는 로그를 위해 프로바이더별로 스캔 루트를 더 지정 (설정 → 고급).
- **소진 예측** — 현재 5시간 창이 100%에 도달할 시각 예측.
- **인앱 업데이트** — 원클릭 업데이트 확인, 설정에 현재 버전 표시.

## 지원 도구

| 도구 | 집계 범위 | 공식 한도 |
|---|---|---|
| **Claude Code** | 오늘 · 5시간 블록 · 주 · 월 | ✅ 5시간 / 주간 |
| **Codex** | 오늘 · 주 · 월 | ✅ 5시간 / 주간 |
| **Gemini CLI** | 오늘 · 주 · 월 | — |
| **Antigravity** | 오늘 · 5시간 블록 · 주 · 월 | ✅ 5시간 / 주간 |
| **OpenCode** | 오늘 · 5시간 블록 · 주 · 월 | — |
| **Hermes Agent** | 오늘 · 5시간 블록 · 주 · 월 | — |
| **Cursor** | 오늘 · 5시간 블록 · 주 · 월 | — |
| **Grok CLI** | 오늘 · 5시간 블록 · 주 · 월 | — |
| **Copilot CLI** | 오늘 · 5시간 블록 · 주 · 월 | — |
| **Kiro CLI** | 오늘 · 5시간 블록 · 주 · 월 | — (추정치) |
| **Pi Agent** | 오늘 · 5시간 블록 · 주 · 월 | — |
| **omp** (oh-my-pi) | 오늘 · 5시간 블록 · 주 · 월 | — |

모두 로컬에서 읽습니다 — 외부 사용량 CLI 불필요. 도구 추가는 프로바이더 파일 하나면 됩니다([CONTRIBUTING.ko.md](CONTRIBUTING.ko.md) 참고).

## 설치

### 요구사항

macOS 14+ (Apple Silicon 또는 Intel). 끝입니다 — 토큰 사용량은 로컬 Claude Code·Codex·Gemini CLI·Antigravity·OpenCode·Hermes Agent·Cursor·Grok CLI·Copilot CLI·Kiro CLI·Pi Agent·omp 데이터에서 직접 읽으며 외부 사용량 CLI가 필요 없습니다.

### Homebrew

```bash
brew install --cask chattymin/tap/poke-token-bar
```

ad-hoc/자체 서명 앱이라 Cask 설치 시 격리 속성을 자동 제거합니다.

### 직접 설치 (Homebrew 없이)

Homebrew를 쓰지 않는다면 [최신 릴리스](https://github.com/chattymin/PokeTokenBar/releases/latest)에서 `PokeTokenBar.zip`을 내려받아 압축을 풀고 `PokeTokenBar.app`을 `/Applications`로 드래그합니다.

이 앱은 ad-hoc/자체 서명(Apple 개발자 계정 공증 없음)이라 첫 실행 시 Gatekeeper가 "확인되지 않은 개발자" 경고를 띄웁니다. 아래 둘 중 하나로 한 번만 해제하면 됩니다.

- **Finder:** `PokeTokenBar.app`을 우클릭(또는 Control+클릭) → **열기** → 대화상자에서 **열기**를 다시 클릭.
- **터미널:** `xattr -dr com.apple.quarantine /Applications/PokeTokenBar.app`

(Homebrew Cask는 격리 속성을 자동 제거하므로 이 과정이 필요 없습니다.)

### 소스 빌드

```bash
swift build                  # 디버그
swift test                   # 단위 테스트
./scripts/build-app.sh       # release → PokeTokenBar.app → /Applications
```

## 데이터 소스

| 소스 | 용도 | 비고 |
|---|---|---|
| `~/.claude/projects/**/*.jsonl` | Claude Code daily/blocks/weekly/monthly | 직접 읽음; 메시지 id 로 중복제거; 증분 캐시 |
| `~/.gemini/tmp/**/chats/*.json(l)` | Gemini CLI daily/monthly | 세션 레코드(메시지별 `tokens`); 주간 = daily 합산 |
| `~/.gemini/antigravity/conversations/*.db`<br>`~/.gemini/antigravity-cli/conversations/*.db`<br>`~/.gemini/antigravity-ide/conversations/*.db` | Antigravity daily/blocks/weekly/monthly | SQLite 읽기 전용; Cascade protobuf blob 의 호출별 사용량; Antigravity 2.0/Core, CLI, IDE 모두 지원; Gemini 에 합산하지 않는 별도 프로바이더; 구독제라 비용은 추정하지 않음 |
| `~/.codex/sessions/**/*.jsonl` | Codex daily/monthly | `token_count` 이벤트; 주간 = daily 합산 |
| `~/.local/share/opencode/opencode.db` | OpenCode daily/blocks/weekly/monthly | SQLite 읽기 전용; 레거시 `storage/message` JSON도 지원 |
| `~/.hermes/state.db` | Hermes Agent daily/blocks/weekly/monthly | SQLite 읽기 전용; 세션 토큰 합계와 저장된 비용 |
| `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` | Cursor daily/blocks/weekly/monthly | SQLite 읽기 전용 폴백(`cursorDiskKV` 버블 엔트리의 `tokenCount`); 로그인 상태면 `cursor.com` 대시보드 API 가 기본 소스(개인정보 항목 참고) |
| `cursor.com`(대시보드 API) | Cursor daily/blocks/weekly/monthly | 비공식 JSON endpoint(`get-filtered-usage-events`); 세션은 `state.vscdb` 의 `cursorAuth/accessToken` 또는 `CURSOR_SESSION_TOKEN`; 프로바이더가 새로고침될 때마다 다시 가져옴; 네트워크 실패 시 계정별로 분리된 최대 6시간 이내의 디스크 캐시로 대체; `CURSOR_USAGE_API=0` 으로 비활성화 |
| `~/.grok/sessions/**/updates.jsonl` | Grok CLI daily/blocks/weekly/monthly | `turn_completed` 레코드(턴 단위 `usage`, 서버 보고 비용); `$GROK_HOME` 설정 시 그 경로; 서브에이전트 세션은 토큰이 부모 턴에 이미 포함돼 제외 |
| `~/.copilot/session-store.db` | Copilot CLI daily/blocks/weekly/monthly | SQLite 읽기 전용; `assistant_usage_events` 1행 = API 호출 1건; `$COPILOT_HOME` 설정 시 그 경로; `input_tokens` 에 캐시 프롬프트가 이미 포함돼 캐시 read/write 를 빼고 집계; premium request 과금이라 비용은 추정하지 않음 |
| `~/Library/Application Support/kiro-cli/data.sqlite3`<br>`~/.kiro/sessions/cli/*.jsonl`<br>`~/.kiro/sessions/<ws>/<session>/messages.jsonl` | Kiro CLI daily/blocks/weekly/monthly | 2.20 이전 SQLite + 2.20+/`--v3` JSONL; 어느 쪽도 실제 토큰 수를 저장하지 않아 input 은 매 턴 재전송되는 누적 대화 텍스트를 바이트÷4 로 **추정**; `usage_summary` 크레딧은 USD 로 바꾸지 않음; `/clear`·압축으로 지워진 SQLite 대화의 이미 집계된 토큰은 앱을 재시작하기 전까지 계속 집계; `$KIRO_CLI_HOME`·`$KIRO_HOME` 지원 |
| `~/.pi/agent/sessions/**/*.jsonl` | Pi Agent daily/blocks/weekly/monthly | 모든 프로젝트의 저장된 usage를 직접 집계; `$PI_CODING_AGENT_DIR`·`$PI_CODING_AGENT_SESSION_DIR` override 지원; output에는 reasoning이 이미 포함되어 별도 합산하지 않음; fork 복사본은 entry ID로 중복 제거; 비용은 표시하지 않음 |
| `~/.omp/agent/sessions/**/*.jsonl` | omp (oh-my-pi) daily/blocks/weekly/monthly | pi 포맷 세션 JSONL; 모든 assistant `usage` 이벤트를 합산(되돌린 분기도 이미 청구된 토큰)하고 서브에이전트 세션 파일도 부모에 합산되지 않으므로 함께 집계; `$OMP_CODING_AGENT_DIR` 지원; 이벤트별 `cost` 가 기록돼 있으면 그대로 신뢰; `bridge/` 아래 변환 사본은 원본이 이미 집계되므로 제외 |
| Keychain / `~/.claude/.credentials.json` → `api.anthropic.com` | Claude 공식 5h/주간 % | 비공식 endpoint; Keychain 은 **갱신 버튼을 누를 때만** 읽음 — 자동 폴링은 읽지 않음 |
| `codex app-server` | Codex 공식 5h/주간 % | 로컬 자식 프로세스; 계정 snapshot만, 모델 turn 없음 |
| [PokéAPI](https://pokeapi.co/) — `pokeapi.co`, `graphql.pokeapi.co` | 포켓몬 종·진화 | 런타임 fetch; 로컬 캐시, 번들 안 함 |
| `raw.githubusercontent.com/PokeAPI/sprites` | 포켓몬·아이템 스프라이트 | 런타임 fetch; Application Support 에 캐시, 번들 안 함 |
| `status.claude.com`, `status.openai.com` | 프로바이더 장애 배너 | statuspage 요약; 표시 전용 — 설정에서 끌 수 있음 |
| `api.github.com` | 업데이트 확인 | 최신 릴리스 태그; 기동 시와 팝오버를 열 때 |

로그가 **위 기본 경로 밖**에 있으면 **설정 → 고급 → 추가 스캔 폴더**에 그 폴더를 넣습니다. 프로바이더를 먼저 고르세요 — 폴더는 그 프로바이더만 파싱하므로, Gemini 칸에 Claude 로그를 넣으면 토큰이 잘못 귀속됩니다. 추가 폴더는 기본 위치에 *더해질* 뿐 대체하지 않습니다.

## 프라이버시 & 권한

- **온디바이스 우선.** 토큰 사용량은 로컬 Claude Code·Codex·Gemini CLI·Antigravity·OpenCode·Hermes Agent·Cursor·Grok CLI·Copilot CLI·Kiro CLI·Pi Agent·omp 데이터에서 직접 읽습니다. 사용량을 업로드하거나 모델 turn을 실행하지 않습니다.
- **외부 요청.** 앱은 완전 오프라인이 아닙니다. 12개 호스트에 접속합니다 — `pokeapi.co`·`graphql.pokeapi.co`(종·진화), `raw.githubusercontent.com`(스프라이트), `api.anthropic.com`(Claude 공식 한도), `claude.ai`(설정에서 claude.ai 세션 키를 저장한 경우의 Claude 공식 한도 — 그 키만, 프롬프트·프로젝트 경로 없음), `cursor.com`(로컬에서 Cursor 에 로그인한 경우 Cursor 사용량 요약 — 세션 자격증명만, 프롬프트·프로젝트 경로 없음), `cloudcode-pa.googleapis.com`·`daily-cloudcode-pa.googleapis.com`(Antigravity 공식 한도)와 `oauth2.googleapis.com`(토큰 갱신), `status.claude.com`·`status.openai.com`(장애 배너 — 설정에서 끌 수 있음), `api.github.com`(업데이트 확인). **어느 요청에도 사용량 로그·프롬프트·프로젝트 경로는 담기지 않습니다** — 요청 자체만 나갑니다(Cursor 는 웹 대시보드와 동일하게 본인 사용량 행을 가져오기 위해 세션 쿠키를 보냅니다).
- **Keychain(선택).** Claude OAuth 자격증명은 **갱신 버튼을 누를 때만** 읽습니다(설정, 또는 팝오버의 한도 행). 자동 폴링은 Keychain 을 건드리지 않으므로 비밀번호 프롬프트가 뜨지 않고, `~/.claude/.credentials.json` 이 있으면 매 폴마다 다시 읽어 `/login` 으로 계정을 바꿔도 갱신 버튼 없이 따라갑니다. 토큰은 메모리에만 두며 **앱 자체 Keychain 항목은 만들지 않습니다.** 자격증명 파일이 없으면 캐시 토큰이 만료될 때까지(또는 갱신 버튼을 누를 때까지) 한도는 이전 값으로 남습니다. 설정에서 끄면 한도 섹션만 숨겨집니다.
- **포켓몬 에셋**은 런타임에 PokéAPI에서 받아오며 `~/Library/Application Support/PokeTokenBar/`에만 캐시됩니다. 앱 바이너리와 릴리스 아티팩트에는 포켓몬 에셋이 포함되지 않습니다.

## 기여자

크기에 상관없이 모든 기여를 환영합니다 — 빌드·테스트·풀 리퀘스트 방법은 [CONTRIBUTING.ko.md](CONTRIBUTING.ko.md)를 참고하세요.

[![Contributors](https://contrib.rocks/image?repo=chattymin/PokeTokenBar)](https://github.com/chattymin/PokeTokenBar/graphs/contributors)

## 라이선스 & 면책

**MIT** — [LICENSE](LICENSE) 참고. MIT는 본 프로젝트의 **원본 소스 코드에만** 적용되며, 앱을 통해 접근하는 제3자의 상표·아트워크·데이터에 대한 권리는 부여하지 않습니다.

PokeTokenBar는 **비공식·비상업 팬 프로젝트**입니다. **Nintendo, Game Freak, Creatures Inc., The Pokémon Company와 제휴·보증·후원·승인 관계가 없습니다.** "포켓몬(Pokémon)"과 관련 명칭·캐릭터·이미지는 각 권리자의 상표 및 저작물이며, 본 프로젝트는 어떤 포켓몬 지식재산에 대해서도 소유권이나 권리를 주장하지 않습니다.

- **앱 바이너리와 릴리스 아티팩트에는 포켓몬 에셋이 포함되지 않습니다.** 포켓몬 종 데이터와 스프라이트는 공개 [PokéAPI](https://pokeapi.co)에서 **런타임에** 받아 사용자 기기에 로컬 캐시되며, PokéAPI를 통해 제공되는 스프라이트 이미지의 권리는 각 권리자에게 있습니다.
- 저장소 문서(스크린샷/GIF)에 보이는 포켓몬 이미지는 앱 기능 설명 목적으로만 표시됩니다.
- 본 앱은 **개인적·비상업적 용도로만** 무료 제공됩니다.
- 권리자께서 본 프로젝트에 대해 우려가 있으시면 이슈를 열거나 메인테이너에게 연락 주시면 신속히 대응하겠습니다.

*본 프로젝트는 어떠한 보증도 없이 "있는 그대로" 제공됩니다. 본 고지는 법률 자문이 아닙니다.*
