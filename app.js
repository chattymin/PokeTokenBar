"use strict";
const I18N = {
  "en": {
    "f13.t": "This month, day by day",
    "f13.d": "See this month’s daily token totals across all tools in the popover. Hover a bar for that day’s usage.",
    "f14.t": "Growth at your pace",
    "f14.d": "Set difficulty from 10% to 200% and apply it with Save. Your earned progress is preserved. Hatches from a previously graduated base species grow twice as fast.",
    "f15.t": "Individual Pokémon profiles",
    "f15.d": "Get to know each Pokémon’s individual values, ability and moves in its profile.",
    "nav.features": "The app",
    "nav.install": "Install",
    "hero.h1a": "Your tokens.",
    "hero.h1b": "A little companion.",
    "hero.lead": "A Pokémon that grows as you code. Track your AI token usage and limits, right from your Mac’s menu bar.",
    "copy": "Copy command",
    "f1.t": "Live token usage",
    "f1.d": "See the total from your supported tools in the menu bar. Open the popover for a breakdown by provider.",
    "f2.t": "Official limits",
    "f2.d": "Claude, Codex and Antigravity limits with reset countdowns and clock times. Choose used or remaining; percentages stay aligned with matching progress bars.",
    "f3.t": "Burn-rate forecast",
    "f3.d": "Estimate when your current 5-hour window will reach 100%, based on your current usage rate.",
    "f5.t": "Localized",
    "f5.d": "Seven UI languages. Pokémon, type, ability and move names follow your selected language, with English when a translation is unavailable.",
    "f6.t": "Notifications",
    "f6.d": "Choose alerts for approaching usage limits, hatching, evolution and graduation.",
    "f7.t": "Token Shop",
    "f7.d": "Use tokens you’ve already spent to get Rare Candy, nature-changing Mints, a Shiny Charm or a new egg.",
    "f9.t": "Representative Pokémon",
    "f9.d": "Pin an owned species to the menu bar and desktop pet. Your current partner keeps growing in Home.",
    "f10.t": "Additional scan folders",
    "f10.d": "Add per-provider scan folders when your logs live outside the default locations. Wildcards and a live match count help you find them.",
    "f11.t": "Official limits without the Keychain",
    "f11.d": "Use a claude.ai session key in Settings → Advanced to read official Claude limits without Keychain prompts.",
    "f12.t": "Per-model breakdown",
    "f12.d": "Pi usage follows the model recorded for each turn. The popover breaks today's Pi tokens down by model, biggest first.",
    "nav.guide": "Field guide",
    "g.t1": "Growth calculator",
    "g.t2": "A day together",
    "g.t3": "Collection",
    "g.costH": "Tokens per evolution",
    "g.costSub": "A three-form example at 100% difficulty, without the repeat-species bonus or items. The table excludes the 5M-token hatch; the calculator includes it. One- and two-form lines split the same total differently.",
    "g.thRarity": "Rarity",
    "g.thS1": "Stage 1",
    "g.thS2": "Stage 2",
    "g.thS3": "Stage 3 (graduate)",
    "g.thTotal": "Total",
    "g.calcH": "How long on my pace?",
    "g.calcQ": "How many AI-coding tokens do you burn per day? (total, including cache reads)",
    "g.p1": "Light · 10M/day",
    "g.p2": "Steady · 40M/day",
    "g.p3": "Heavy · 120M/day",
    "g.p4": "Agent fleet · 300M/day",
    "g.honest": "Estimates assume a constant daily pace. Difficulty, items and the 2× post-hatch bonus for previously graduated species change the result.",
    "g.dailyIntro": "Your companion responds to your coding rhythm, changing its pose and caption as you work.",
    "g.st1w": "no tokens today",
    "g.st1t": "Fast asleep",
    "g.st1d": "When you rest, it rests. Weekend menu bars are quiet.",
    "g.st2w": "light use",
    "g.st2t": "Loafing around",
    "g.st2d": "On lighter days, your partner idles beside you.",
    "g.st3w": "coding steadily",
    "g.st3t": "Working along",
    "g.st3d": "Your normal pace. It keeps busy too.",
    "g.st4w": "100k+ tokens/min",
    "g.st4t": "In the zone",
    "g.st4d": "When your agents are busy, your partner keeps up.",
    "g.st5w": "limit almost reached",
    "g.st5t": "Worn out",
    "g.st5d": "When a usage limit is close, it tires before you do. Take the hint.",
    "g.st6w": "evolution · graduation",
    "g.st6t": "Celebrating",
    "g.st6d": "A short animation marks each evolution and graduation.",
    "g.dailyNote": "Hatching has its own animation. A Shiny hatch gets a different entrance.",
    "g.loop": "Every graduation adds to your collection and brings a new egg.",
    "g.cWhat": "To collect",
    "g.cHow": "How it works",
    "g.c1k": "Species",
    "g.c1v": "Pokémon from Generations I–V, drawn from the app’s live species pool. Each hatch is a surprise.",
    "g.c2k": "Rarities",
    "g.c2v": "Four tiers, Common to Legendary. Rarer partners hatch less often and need more tokens to graduate.",
    "g.c3k": "✨ Shiny",
    "g.c3v": "A rare surprise at hatch: different colors that stay through evolution.",
    "g.c4k": "Natures",
    "g.c4v": "One of 25 natures per hatch gives each partner its character.",
    "g.c5k": "Branches",
    "g.c5v": "Branching evolution lines prefer paths you have not collected yet.",
    "g.c6k": "Pokédex",
    "g.c6v": "The catch log records individual partners and their evolution lines. The Pokédex groups the species you have owned.",
    "foot.disclaimer": "Pokémon data & sprites by PokéAPI. This is an unofficial, non-commercial fan project. It is not affiliated with, endorsed, sponsored, or approved by Nintendo, Game Freak, or The Pokémon Company. Pokémon and Pokémon character names are trademarks of Nintendo; names, data, and sprites are © Nintendo / Game Freak / The Pokémon Company, used at runtime for identification only. The MIT license covers this project's source code only.",
    "skip": "Skip to content",
    "nav.menu": "Menu",
    "theme": "Switch color theme",
    "hero.install": "Get PokeTokenBar",
    "hero.preview": "Meet the app",
    "hero.compat": "Free · macOS 14+ · Apple Silicon & Intel",
    "hero.note": "The tokens you already use become progress. Your usual workflow, with a little company.",
    "demo.caption": "Your menu bar, with company.",
    "demo.provenance": "Example screen · English",
    "providers.label": "Works with your coding tools",
    "providers.more": "13 tools. One companion.",
    "install.title": "Make room for\na little company.",
    "install.intro": "You’ll need macOS 14 or later and at least one supported AI coding tool. No PokeTokenBar account needed.",
    "install.homebrew": "Install with Homebrew",
    "install.step1": "Open Terminal on your Mac.",
    "install.step2": "Copy and run the command below.",
    "install.step3": "Open PokeTokenBar from Applications.",
    "install.brewhelp": "Need Homebrew?",
    "install.direct": "Prefer a direct download?",
    "install.zip": "Download ZIP for macOS",
    "install.unzip": "Unzip PokeTokenBar.zip and move PokeTokenBar.app into Applications.",
    "install.gate": "The app is self-signed. If macOS blocks the first launch, follow the Gatekeeper steps in the installation guide. Homebrew handles the quarantine attribute for you.",
    "install.help": "Open installation guide",
    "copy.pending": "Copying…",
    "copy.ok": "Copied. Paste it into Terminal to install.",
    "copy.error": "Couldn’t copy. Select the command above and copy it manually.",
    "usage.title": "Less checking.\nMore coding.",
    "usage.desc": "Today’s tokens, usage trends and provider limits live together. Open the menu bar when you need the details; keep working when you don’t.",
    "usage.limits": "See the reset coming",
    "usage.limitsDesc": "Official limits for Claude, Codex and Antigravity, with reset timing and optional notifications.",
    "usage.caption": "Daily trends and official usage limits. Example screens.",
    "growth.title": "Your coding grows a Pokémon.",
    "growth.play": "Play animation",
    "growth.pause": "Pause animation",
    "growth.desc": "The tokens you use with AI coding tools hatch an egg and grow your partner. Keep coding, watch it evolve, and keep each graduated Pokémon in your collection.",
    "growth.egg": "Start with an egg",
    "growth.eggDesc": "Your first tokens bring you closer to hatching.",
    "growth.first": "Meet your partner",
    "growth.firstDesc": "An egg hatches into a surprise Pokémon.",
    "growth.evolve": "Code. Grow. Evolve.",
    "growth.evolveDesc": "Used tokens advance its evolution line.",
    "growth.collect": "Keep it in your Pokédex",
    "growth.collectDesc": "Graduate your partner and welcome a new egg.",
    "growth.note": "Illustration: Bulbasaur’s evolution line. Your partner and growth pace vary. No extra AI requests are made to grow a Pokémon.",
    "features.more": "Explore the details",
    "comp.title": "A workday,\nwith a side quest.",
    "comp.desc": "Your existing token usage raises a partner through its real evolution line. Then a new egg arrives, and the collection grows.",
    "journey.hatch": "Hatch your first partner",
    "journey.hatchDesc": "An egg hatches after 5M tokens at the default difficulty. Which Pokémon will it be?",
    "journey.grow": "Watch it grow",
    "journey.growDesc": "Keep coding to evolve. Adjust difficulty to suit your own pace.",
    "journey.collect": "Keep the memories",
    "journey.collectDesc": "Graduated partners stay in your collection. A fresh egg starts the next chapter.",
    "comp.caption": "Every partner has a place in your Pokédex. Example screen.",
    "pet.title": "Or, right beside you.",
    "pet.desc": "Let your partner out of the menu bar. Drag it anywhere, hover to check usage, and click to open the app.",
    "guide.title": "Curious how it grows?",
    "guide.desc": "Try your pace, check the costs, and see what you can collect. Too many tokens? Lower the difficulty in the app to grow with fewer tokens.",
    "guide.open": "Open the field guide",
    "calc.pace": "Daily tokens",
    "calc.rarity": "Rarity",
    "calc.nojs": "Enable JavaScript to use the calculator. The token costs are listed above.",
    "faq.title": "A few good questions.",
    "faq.free.q": "Is it free?",
    "faq.free.a": "Yes. PokeTokenBar is a free, open-source fan project. Shop items use the tokens you’ve already spent on coding, not real-money purchases.",
    "faq.privacy.q": "Does it upload my usage logs?",
    "faq.privacy.a": "No. Usage logs stay on your Mac. The app still uses the network for provider usage and limits, Pokémon data and sprites, service status and updates. It is not a fully offline app.",
    "faq.cost.q": "Does raising a Pokémon spend extra tokens?",
    "faq.cost.a": "No. The app reads usage from your supported coding tools. It doesn’t run model turns to grow your companion.",
    "faq.source.q": "Can I build it myself?",
    "faq.source.a": "Yes. The Swift source, build instructions and issue tracker are on GitHub.",
    "footer.source": "Source code",
    "footer.releases": "Release notes",
    "footer.help": "Get help",
    "footer.sponsor": "Sponsor",
    "demo.play": "Play demo",
    "demo.stop": "Stop demo",
    "s5.t": "Earn Rare Candy",
    "s5.d": "Fill a 5-hour or weekly limit to earn Rare Candy. Use it from the Bag to grow your partner.",
    "aria.nav": "Main navigation",
    "aria.project": "Project links",
    "aria.guide": "Field guide",
    "aria.table": "Growth and collection details",
    "alt.home": "Example PokeTokenBar screen with Lapras, daily tokens and official limits",
    "alt.trend": "Example daily token usage chart",
    "alt.quota": "Example provider limits and reset timing",
    "alt.collection": "Example Pokédex showing collected species",
    "alt.pet": "Example floating desktop pet with usage callout",
    "f16.t": "A clearer collection",
    "f16.d": "Browse 16 Pokémon per page in a 4 × 4 Pokédex with larger sprites and names. Search, sort, and filter by rarity or Shiny status.",
    "f17.t": "Your usage recap",
    "f17.d": "Review token usage and companion milestones by week, month, or year.",
    "f18.t": "Back up your progress",
    "f18.d": "Export a backup of your companion data and restore it when needed.",
    "f19.t": "Multiple Claude accounts",
    "f19.d": "Track official Claude limits across multiple accounts from the same app.",
    "f20.t": "See your usage pace",
    "f20.d": "Quota bar colors reflect your usage pace relative to the remaining time in the window.",
    "f21.t": "More ways to collect and grow",
    "f21.d": "Collect Unown forms and use multiple Rare Candies at once to grow your partner.",
    "alt.recap": "Example weekly recap with token usage and an Unown graduation",
    "alt.pace": "Example quota bar with the usage pace marker"
  },
  "ko": {
    "f13.t": "이번 달의 일별 사용량",
    "f13.d": "팝오버에서 모든 도구를 합산한 이번 달의 일별 토큰 사용량을 확인하세요. 막대에 마우스를 올리면 해당 날짜의 수치가 표시됩니다.",
    "f14.t": "내 속도에 맞는 성장",
    "f14.d": "난이도를 10%~200%로 조절하고 저장을 눌러 적용하세요. 이미 쌓은 성장 진행률은 유지됩니다. 졸업한 기본 종이 다시 부화하면 2배로 성장합니다.",
    "f15.t": "포켓몬 개체별 상세",
    "f15.d": "포켓몬마다 다른 개체값과 특성, 기술을 상세 화면에서 살펴보세요.",
    "nav.features": "앱 둘러보기",
    "nav.install": "설치",
    "hero.h1a": "당신의 토큰이,",
    "hero.h1b": "작은 동료로.",
    "hero.lead": "코딩하는 동안 포켓몬이 자라요. Mac 메뉴바에서 AI 토큰 사용량과 한도를 확인하고, 함께할 파트너를 키우세요.",
    "copy": "명령어 복사",
    "f1.t": "실시간 토큰 사용량",
    "f1.d": "오늘 쓴 Claude Code·Codex·Gemini·Antigravity·OpenCode·Hermes·Cursor·Grok·Copilot·Kiro·Pi·omp·Aside 토큰 합계를 메뉴바에 간결하게(예: 253.4M). 팝오버에선 서비스별 탭으로 상세를 넘나들어요.",
    "f2.t": "공식 사용 한도",
    "f2.d": "Claude·Codex·Antigravity 한도와 리셋까지 남은 시간·시각을 확인하세요. 사용량과 남은량을 선택하면 그래프도 맞춰 바뀌고 퍼센트는 오른쪽에 정렬됩니다.",
    "f3.t": "한도 소진 예측",
    "f3.d": "지금 속도라면 5시간 한도에 언제 닿을지 미리 알려줘요. 갑자기 막혀서 당황할 일이 없죠.",
    "f5.t": "다국어 지원",
    "f5.d": "7개 언어 UI를 지원합니다. 포켓몬·타입·특성·기술 이름은 선택한 언어로 표시하고 번역이 없으면 영어를 사용합니다.",
    "f6.t": "알림",
    "f6.d": "한도가 경고·임박 기준을 넘거나, 파트너가 부화·진화·졸업할 때 알려줘요.",
    "f7.t": "토큰 상점",
    "f7.d": "이미 사용한 토큰으로 이상한 사탕, 성격을 바꾸는 민트, 이로치 부적이나 새 알을 얻으세요.",
    "f9.t": "대표 포켓몬",
    "f9.d": "도감에서 이미 가진 종을 골라 메뉴바와 플로팅 펫에 고정할 수 있어요 — 키우는 포켓몬과 별개예요. 고정 중엔 메뉴바가 알·부화·진화를 따라가지 않고, 육성 진행은 홈에서 그대로 봅니다.",
    "f10.t": "추가 스캔 폴더",
    "f10.d": "로그가 기본 경로 밖에 있나요? 프로바이더별로 스캔 루트를 더 넣을 수 있어요 — 콤마·줄바꿈 구분, * 와일드카드, 지금 몇 개가 걸리는지 실시간 표시. 목록은 프로바이더마다 따로고, 추가한 경로는 기본 경로를 대체하지 않고 더해집니다.",
    "f11.t": "Keychain 없는 공식 한도",
    "f11.d": "한도 토큰이 만료됐나요? 설정 → 고급에 claude.ai 세션 키를 붙여넣으면 공식 Claude 한도를 claude.ai에서 바로 읽어요 — Keychain 접근도, 암호 팝업도 없이 자동 폴링으로 최신을 유지합니다.",
    "f12.t": "모델별 내역",
    "f12.d": "Pi 사용량을 각 턴에 기록된 실제 모델로 집계합니다. 팝오버에서 오늘의 Pi 토큰을 모델별로 사용량이 큰 순서대로 확인하세요.",
    "nav.guide": "성장 가이드",
    "g.t1": "성장 계산기",
    "g.t2": "파트너의 하루",
    "g.t3": "수집 요소",
    "g.costH": "진화에 필요한 토큰",
    "g.costSub": "난이도 100%, 반복 부화 보너스와 아이템이 없는 3단계 진화 예시입니다. 표는 부화 비용 5M을 제외하고, 계산기는 포함합니다. 1·2단계 진화는 총량은 같지만 단계별 비용이 달라요.",
    "g.thRarity": "희귀도",
    "g.thS1": "1단계",
    "g.thS2": "2단계",
    "g.thS3": "3단계 (졸업)",
    "g.thTotal": "총량",
    "g.calcH": "내 페이스로는 얼마나 걸릴까?",
    "g.calcQ": "하루에 AI 코딩 토큰을 얼마나 쓰시나요? (캐시 읽기 포함 총량)",
    "g.p1": "가볍게 · 10M/일",
    "g.p2": "보통 · 40M/일",
    "g.p3": "헤비 · 120M/일",
    "g.p4": "에이전트 군단 · 300M/일",
    "g.honest": "매일 같은 양을 사용한다고 가정한 예상치입니다. 난이도, 아이템, 이전에 졸업한 종의 부화 이후 성장 2배 보너스에 따라 달라집니다.",
    "g.dailyIntro": "메뉴바의 파트너는 장식이 아니에요. 당신의 코딩 리듬을 그대로 살아요 — 스프라이트와 문구가 실시간으로 바뀝니다.",
    "g.st1w": "오늘 사용량 0",
    "g.st1t": "쿨쿨",
    "g.st1d": "당신이 쉬면 파트너도 자요. 주말의 메뉴바는 조용하답니다.",
    "g.st2w": "가끔 한 번씩",
    "g.st2t": "느긋",
    "g.st2d": "가볍게 몇 번 물어본 날엔 옆에서 어슬렁거려요.",
    "g.st3w": "꾸준히 코딩 중",
    "g.st3t": "같이 일하는 중",
    "g.st3d": "평소 페이스. 파트너도 부지런히 움직여요.",
    "g.st4w": "분당 10만 토큰 이상",
    "g.st4t": "몰입",
    "g.st4d": "에이전트가 달리고 있을 때 — 파트너도 달아올라요.",
    "g.st5w": "한도 임박",
    "g.st5t": "지침",
    "g.st5d": "사용 한도가 코앞이면 파트너가 먼저 지쳐요. 눈치채 주세요.",
    "g.st6w": "진화 · 졸업 직후",
    "g.st6t": "축하",
    "g.st6d": "진화 순간과 졸업 연출 — 놓치기 아까운 몇 초예요.",
    "g.dailyNote": "부화 순간엔 전용 연출이 있고, 이로치가 태어나면 연출부터 달라요.",
    "g.loop": "끝이 아니라 루프예요. 졸업할 때마다 도감이 한 칸 채워지고, 새 알이 도착합니다.",
    "g.cWhat": "모을 것",
    "g.cHow": "어떻게",
    "g.c1k": "종",
    "g.c1v": "1~5세대 포켓몬을 앱의 실시간 종 목록에서 뽑아요. 알이 부화할 때마다 새로운 만남이 기다립니다.",
    "g.c2k": "희귀도",
    "g.c2v": "Common부터 Legendary까지 4등급 — 희귀할수록 드물게 나오고, 오래 함께해요.",
    "g.c3k": "✨ 이로치",
    "g.c3v": "부화 순간의 아주 드문 행운 — 전용 색상, 진화해도 유지돼요.",
    "g.c4k": "성격",
    "g.c4v": "부화마다 25종 중 하나 — 같은 종이라도 느낌이 달라요.",
    "g.c5k": "분기 진화",
    "g.c5v": "진화가 갈라지는 종은 아직 도감에 없는 쪽을 우선해요 — 키울수록 도감이 알아서 채워집니다.",
    "g.c6k": "도감",
    "g.c6v": "(시작 종 → 최종형) 쌍으로 기록되고 진화 라인 전체가 남아요. 같은 시작 종도 분기가 다르면 별개 항목.",
    "foot.disclaimer": "포켓몬 데이터·스프라이트는 PokéAPI를 사용합니다. 본 프로젝트는 비공식·비상업 팬 프로젝트로, Nintendo·Game Freak·The Pokémon Company와 제휴하거나 보증·후원·승인을 받지 않았습니다. ‘Pokémon’과 포켓몬 캐릭터 이름은 Nintendo의 상표이며, 이름·데이터·스프라이트의 저작권은 © Nintendo / Game Freak / The Pokémon Company에 있고 식별 목적으로만 런타임에 사용됩니다. MIT 라이선스는 본 프로젝트의 소스 코드에만 적용됩니다.",
    "skip": "본문으로 건너뛰기",
    "nav.menu": "메뉴",
    "theme": "화면 테마 전환",
    "hero.install": "PokeTokenBar 설치",
    "hero.preview": "앱 먼저 둘러보기",
    "hero.compat": "무료 · macOS 14+ · Apple Silicon & Intel",
    "hero.note": "이미 쓰고 있는 토큰이 성장으로 이어져요. 평소처럼 코딩하면 됩니다.",
    "demo.caption": "메뉴바에 찾아온 작은 동료.",
    "demo.provenance": "예시 화면 · 영어",
    "providers.label": "지금 쓰는 코딩 도구와 함께",
    "providers.more": "13개 도구, 하나의 파트너",
    "install.title": "작은 동료를\n맞이할 시간.",
    "install.intro": "macOS 14 이상과 지원하는 AI 코딩 도구가 하나 이상 있으면 됩니다. PokeTokenBar 계정은 필요 없어요.",
    "install.homebrew": "Homebrew로 설치",
    "install.step1": "Mac에서 터미널을 여세요.",
    "install.step2": "아래 명령어를 복사해서 실행하세요.",
    "install.step3": "응용 프로그램에서 PokeTokenBar를 여세요.",
    "install.brewhelp": "Homebrew가 없나요?",
    "install.direct": "직접 다운로드하고 싶나요?",
    "install.zip": "macOS용 ZIP 다운로드",
    "install.unzip": "PokeTokenBar.zip의 압축을 풀고 PokeTokenBar.app을 응용 프로그램 폴더로 옮기세요.",
    "install.gate": "앱은 자체 서명되어 있어요. macOS가 첫 실행을 차단하면 설치 가이드의 Gatekeeper 안내를 따라주세요. Homebrew는 격리 속성을 자동으로 처리합니다.",
    "install.help": "설치 가이드 열기",
    "copy.pending": "복사 중…",
    "copy.ok": "복사했어요. 터미널에 붙여넣어 설치하세요.",
    "copy.error": "복사하지 못했어요. 위 명령어를 직접 선택해서 복사해주세요.",
    "usage.title": "사용량은 한눈에.\n코딩은 하던 대로.",
    "usage.desc": "오늘의 토큰, 사용량 추이, 프로바이더 한도를 한곳에서 확인하세요. 자세히 볼 때만 메뉴바를 열면 됩니다.",
    "usage.limits": "리셋까지 얼마나 남았는지",
    "usage.limitsDesc": "Claude·Codex·Antigravity의 공식 한도와 리셋 시점을 보여주고, 원하면 알림도 보내드려요.",
    "usage.caption": "일별 추이와 공식 사용량 한도. 예시 화면.",
    "features.more": "세부 기능 더 보기",
    "comp.title": "코딩하는 하루에,\n작은 모험 하나.",
    "comp.desc": "이미 쓰고 있는 토큰으로 파트너가 실제 진화 계보를 따라 자라요. 졸업하면 새 알이 찾아오고, 도감에는 함께한 기록이 남습니다.",
    "journey.hatch": "첫 파트너와 만나기",
    "journey.hatchDesc": "기본 난이도에서는 5M 토큰으로 알이 부화해요. 어떤 포켓몬이 나올까요?",
    "journey.grow": "함께 자라기",
    "journey.growDesc": "코딩을 이어가면 진화해요. 난이도는 자신의 속도에 맞게 조절할 수 있어요.",
    "journey.collect": "도감에 추억 남기기",
    "journey.collectDesc": "졸업한 파트너는 도감에 남아요. 새 알과 함께 다음 이야기를 시작하세요.",
    "comp.caption": "함께한 파트너가 쌓이는 도감. 예시 화면.",
    "pet.title": "바탕화면에서도 함께.",
    "pet.desc": "파트너를 메뉴바 밖으로 꺼내보세요. 원하는 곳으로 옮기고, 마우스를 올려 사용량을 확인하고, 클릭해서 앱을 여세요.",
    "growth.title": "코딩한 만큼, 포켓몬도 자라요.",
    "growth.play": "애니메이션 재생",
    "growth.pause": "애니메이션 일시정지",
    "growth.desc": "AI 도구로 코딩하며 쓴 토큰이 알을 깨우고, 포켓몬을 키워요. 토큰이 쌓이면 진화하고, 끝까지 키운 파트너는 도감에 남아요.",
    "growth.egg": "알에서 시작해요",
    "growth.eggDesc": "첫 토큰부터 부화에 가까워져요.",
    "growth.first": "첫 포켓몬을 만나요",
    "growth.firstDesc": "알이 부화하면 새로운 파트너를 만나요.",
    "growth.evolve": "함께 코딩하고, 진화해요",
    "growth.evolveDesc": "사용한 토큰이 쌓여 다음 모습으로 진화해요.",
    "growth.collect": "도감에 남기고, 다시 시작해요",
    "growth.collectDesc": "끝까지 키우면 도감에 남고 새 알이 찾아와요.",
    "growth.note": "이상해씨 진화 라인 예시예요. 만나는 포켓몬과 성장 속도는 달라질 수 있어요. 포켓몬을 키우기 위해 AI를 추가로 호출하지 않아요.",
    "guide.title": "얼마나 쓰면 자랄까요?",
    "guide.desc": "내 사용 속도로 계산하고, 진화 비용과 수집 요소를 확인하세요. 필요한 토큰이 부담스럽다면 앱에서 난이도를 낮춰 더 적은 토큰으로 키울 수 있어요.",
    "guide.open": "성장 가이드 펼치기",
    "calc.pace": "하루 토큰 사용량",
    "calc.rarity": "희귀도",
    "calc.nojs": "계산기를 사용하려면 JavaScript를 켜주세요. 토큰 비용은 위 표에서 확인할 수 있어요.",
    "faq.title": "궁금할 만한 것들.",
    "faq.free.q": "무료인가요?",
    "faq.free.a": "네. 무료 오픈소스 팬 프로젝트입니다. 상점에서는 실제 결제 대신 코딩에 이미 사용한 토큰을 재화로 써요.",
    "faq.privacy.q": "사용량 로그를 업로드하나요?",
    "faq.privacy.a": "아니요. 사용량 로그는 Mac 안에 남아요. 다만 프로바이더 사용량·한도, 포켓몬 데이터·스프라이트, 서비스 상태, 업데이트를 위해 네트워크를 사용합니다. 완전한 오프라인 앱은 아니에요.",
    "faq.cost.q": "포켓몬을 키우면 토큰을 추가로 쓰나요?",
    "faq.cost.a": "아니요. 지원하는 코딩 도구의 사용량을 읽습니다. 파트너를 키우기 위해 모델을 실행하지 않아요.",
    "faq.source.q": "직접 빌드할 수 있나요?",
    "faq.source.a": "네. Swift 소스 코드, 빌드 방법, 이슈 트래커가 GitHub에 공개되어 있습니다.",
    "footer.source": "소스 코드",
    "footer.releases": "릴리스 노트",
    "footer.help": "도움 받기",
    "footer.sponsor": "후원",
    "demo.play": "데모 재생",
    "demo.stop": "데모 정지",
    "s5.t": "이상한 사탕 받기",
    "s5.d": "5시간 또는 주간 한도를 채우면 이상한 사탕을 받아요. 가방에서 사용해 파트너를 키우세요.",
    "aria.nav": "주요 탐색",
    "aria.project": "프로젝트 링크",
    "aria.guide": "성장 가이드",
    "aria.table": "성장 및 수집 상세 정보",
    "alt.home": "라프라스, 오늘의 토큰, 공식 한도가 표시된 PokeTokenBar 예시 화면",
    "alt.trend": "일별 토큰 사용량 차트 예시",
    "alt.quota": "프로바이더 한도와 리셋 시점 예시",
    "alt.collection": "수집한 포켓몬이 표시된 도감 예시",
    "alt.pet": "사용량 말풍선이 표시된 바탕화면 펫 예시",
    "f16.t": "더 잘 보이는 컬렉션",
    "f16.d": "커진 이미지와 이름으로 한 페이지에 16마리를 4 × 4 도감에서 확인하세요. 검색·정렬과 희귀도·이로치 필터를 지원합니다.",
    "f17.t": "사용량 리캡",
    "f17.d": "주·월·연도별 토큰 사용량과 파트너의 성장 기록을 돌아보세요.",
    "f18.t": "성장 기록 백업",
    "f18.d": "파트너 데이터를 백업 파일로 내보내고 필요할 때 복원하세요.",
    "f19.t": "여러 Claude 계정",
    "f19.d": "하나의 앱에서 여러 Claude 계정의 공식 사용 한도를 확인하세요.",
    "f20.t": "사용 속도를 색으로 확인",
    "f20.d": "한도 막대 색상이 해당 구간의 남은 시간 대비 사용 속도를 보여줍니다.",
    "f21.t": "더 다양한 수집과 성장",
    "f21.d": "안농의 여러 모습을 수집하고 이상한 사탕을 한 번에 여러 개 사용해 파트너를 키우세요.",
    "alt.recap": "토큰 사용량과 안농 졸업 기록을 보여주는 주간 리캡 예시",
    "alt.pace": "사용 속도 마커가 표시된 한도 막대 예시"
  },
  "ja": {
    "f13.t": "今月の日別使用量",
    "f13.d": "ポップオーバーで全ツールを合算した今月の日別トークン使用量を確認。バーにポインタを重ねると、その日の数値を表示します。",
    "f14.t": "自分のペースで育成",
    "f14.d": "難易度を10%〜200%で調整し、保存して適用。獲得済みの育成進捗は維持されます。卒業済みの基本種が再び孵化すると2倍で成長します。",
    "f15.t": "ポケモンごとの詳細",
    "f15.d": "ポケモンごとの個体値、特性、技を詳細画面で見てみましょう。",
    "nav.features": "アプリを見る",
    "nav.install": "インストール",
    "hero.h1a": "あなたのトークンが、",
    "hero.h1b": "小さなパートナーに。",
    "hero.lead": "コードを書くたび、ポケモンが育つ。MacのメニューバーでAIトークンの使用量と上限を確認しながら、パートナーを育てましょう。",
    "copy": "コマンドをコピー",
    "f1.t": "リアルタイムの使用量",
    "f1.d": "今日の Claude Code・Codex・Gemini・Antigravity・OpenCode・Hermes・Cursor・Grok・Copilot・Kiro・Pi・omp・Aside トークン合計をメニューバーにコンパクト表示（例：253.4M）。ポップオーバーではサービス別タブで詳細を切替。",
    "f2.t": "公式の使用上限",
    "f2.d": "Claude・Codex・Antigravity の上限とリセットまでの時間・時刻を表示。使用量と残量の選択にグラフも連動し、割合は右端に揃います。",
    "f3.t": "上限到達の予測",
    "f3.d": "今のペースなら5時間の上限にいつ達するかを事前に予測。急に止まって困ることがありません。",
    "f5.t": "多言語対応",
    "f5.d": "7言語の UI に対応。ポケモン・タイプ・特性・技の名前は選択した言語を優先し、翻訳がなければ英語を使います。",
    "f6.t": "通知",
    "f6.d": "上限が警告・危険のラインを超えたとき、そしてパートナーが孵化・進化・卒業したときにお知らせします。",
    "f7.t": "トークンショップ",
    "f7.d": "使ったトークンで、ふしぎなアメ、せいかくを変えるミント、色違いのお守り、新しいタマゴを手に入れましょう。",
    "f9.t": "代表ポケモン",
    "f9.d": "図鑑で所有している種を選び、育成中のポケモンとは別にメニューバーとフローティングペットへ固定できます — 固定中はメニューバーがタマゴ・孵化・進化を追わなくなり、育成の進行は Home で確認できます。",
    "f10.t": "追加スキャンフォルダ",
    "f10.d": "ログが既定のパスの外にありますか？プロバイダーごとにスキャンルートを追加できます — カンマ・改行区切り、* ワイルドカード、いま何個一致しているかをその場で表示。リストはプロバイダーごとに分かれ、追加したパスは既定を置き換えずに加算されます。",
    "f11.t": "Keychain なしの公式上限",
    "f11.d": "上限トークンが切れたら、設定 → 詳細に claude.ai セッションキーを貼り付けるだけ。公式の Claude 上限を claude.ai から直接読むので、Keychain アクセスもパスワードポップアップもなく、自動ポーリングで最新を保ちます。",
    "f12.t": "モデル別の内訳",
    "f12.d": "Pi の使用量を各ターンに記録されたモデルで集計。ポップオーバーで今日の Pi トークンをモデル別に使用量順で確認できます。",
    "nav.guide": "育成ガイド",
    "g.t1": "成長計算機",
    "g.t2": "パートナーの一日",
    "g.t3": "コレクション",
    "g.costH": "進化に必要なトークン",
    "g.costSub": "難易度100%、リピートボーナスやアイテムなしの3段階進化の例です。表には孵化の5Mを含まず、計算機には含みます。1・2段階進化では同じ合計を異なる比率で分けます。",
    "g.thRarity": "レア度",
    "g.thS1": "段階 1",
    "g.thS2": "段階 2",
    "g.thS3": "段階 3（卒業）",
    "g.thTotal": "合計",
    "g.calcH": "自分のペースだとどれくらい？",
    "g.calcQ": "1日にAIコーディングトークンをどれくらい使いますか？（キャッシュ読み込み込みの総量）",
    "g.p1": "ライト · 10M/日",
    "g.p2": "ふつう · 40M/日",
    "g.p3": "ヘビー · 120M/日",
    "g.p4": "エージェント艦隊 · 300M/日",
    "g.honest": "毎日同じ量を使う場合の目安です。難易度、アイテム、卒業済み種族の孵化後2倍ボーナスによって変わります。",
    "g.dailyIntro": "メニューバーのパートナーは飾りではありません。あなたのコーディングのリズムをそのまま生きています — スプライトとキャプションがリアルタイムに変わります。",
    "g.st1w": "今日の使用量 0",
    "g.st1t": "ぐっすり",
    "g.st1d": "あなたが休めばパートナーも眠ります。週末のメニューバーは静かです。",
    "g.st2w": "ときどき使う",
    "g.st2t": "のんびり",
    "g.st2d": "軽く数回聞いた日は、そばでうろうろ。",
    "g.st3w": "コツコツ作業中",
    "g.st3t": "いっしょに仕事中",
    "g.st3d": "いつものペース。パートナーもせっせと動きます。",
    "g.st4w": "毎分10万トークン以上",
    "g.st4t": "ゾーンに突入",
    "g.st4d": "エージェントが全力疾走中 — パートナーも燃えています。",
    "g.st5w": "上限が目前",
    "g.st5t": "へとへと",
    "g.st5d": "使用上限が近づくと、あなたより先に疲れます。察してあげてください。",
    "g.st6w": "進化 · 卒業の直後",
    "g.st6t": "お祝い",
    "g.st6d": "進化の瞬間と卒業の演出 — 見逃すには惜しい数秒です。",
    "g.dailyNote": "孵化には専用の演出があり、色違いが生まれると演出からして違います。",
    "g.loop": "終わりではなくループ。卒業のたびに図鑑が1マス埋まり、新しいタマゴが届きます。",
    "g.cWhat": "集めるもの",
    "g.cHow": "しくみ",
    "g.c1k": "種族",
    "g.c1v": "第1〜5世代のポケモンをアプリの最新の種族リストから抽選。孵化するたびに新しい出会いが待っています。",
    "g.c2k": "レア度",
    "g.c2v": "Common から Legendary の4段階 — レアなほど出にくく、長く一緒にいられます。",
    "g.c3k": "✨ 色違い",
    "g.c3v": "孵化のごくまれな幸運 — 専用カラーで、進化しても維持されます。",
    "g.c4k": "せいかく",
    "g.c4v": "孵化ごとに25種類からひとつ — 同じ種族でも印象が変わります。",
    "g.c5k": "分岐進化",
    "g.c5v": "進化が分かれる種族は、まだ図鑑にない方を優先 — 育てるほど図鑑がひとりでに埋まります。",
    "g.c6k": "図鑑",
    "g.c6v": "（最初の種族 → 最終形）のペアで記録され、進化ライン全体が残ります。同じ種族でも分岐が違えば別エントリー。",
    "foot.disclaimer": "ポケモンのデータ・スプライトは PokéAPI を使用しています。本プロジェクトは非公式・非商用のファンプロジェクトであり、任天堂・ゲームフリーク・株式会社ポケモンとの提携、推奨、後援、承認はありません。「ポケモン」およびポケモンのキャラクター名は任天堂の商標であり、名前・データ・スプライトの著作権は © Nintendo / Game Freak / The Pokémon Company に帰属し、識別目的でランタイムに利用しています。MIT ライセンスは本プロジェクトのソースコードのみを対象とします。",
    "skip": "本文へ移動",
    "nav.menu": "メニュー",
    "theme": "テーマを切り替え",
    "hero.install": "PokeTokenBar を入手",
    "hero.preview": "アプリを見てみる",
    "hero.compat": "無料 · macOS 14+ · Apple Silicon & Intel",
    "hero.note": "いつも使っているトークンが成長につながります。コーディングはいつもどおりで。",
    "demo.caption": "メニューバーに、小さな仲間。",
    "demo.provenance": "画面例 · 英語",
    "providers.label": "いつものコーディングツールで",
    "providers.more": "13のツール、ひとりのパートナー",
    "install.title": "小さな仲間を、\n迎えよう。",
    "install.intro": "macOS 14以降と、対応するAIコーディングツールがひとつあれば始められます。PokeTokenBarのアカウントは不要です。",
    "install.homebrew": "Homebrewでインストール",
    "install.step1": "Macでターミナルを開きます。",
    "install.step2": "下のコマンドをコピーして実行します。",
    "install.step3": "アプリケーションからPokeTokenBarを開きます。",
    "install.brewhelp": "Homebrewが必要ですか？",
    "install.direct": "直接ダウンロードするには？",
    "install.zip": "macOS用ZIPをダウンロード",
    "install.unzip": "PokeTokenBar.zipを展開し、PokeTokenBar.appをアプリケーションフォルダへ移動します。",
    "install.gate": "アプリは自己署名です。macOSが初回起動をブロックした場合は、インストールガイドのGatekeeper手順をご覧ください。Homebrewなら隔離属性を自動で処理します。",
    "install.help": "インストールガイドを開く",
    "copy.pending": "コピー中…",
    "copy.ok": "コピーしました。ターミナルに貼り付けてインストールしてください。",
    "copy.error": "コピーできませんでした。上のコマンドを選択して手動でコピーしてください。",
    "usage.title": "使用量はひと目で。\nコードに集中。",
    "usage.desc": "今日のトークン、使用量の推移、プロバイダーの上限をひとつの場所に。詳しく知りたいときだけメニューバーを開けばOK。",
    "usage.limits": "リセットまで、あとどれくらい？",
    "usage.limitsDesc": "Claude・Codex・Antigravityの公式上限とリセット時刻を表示。必要に応じて通知も設定できます。",
    "usage.caption": "日別の推移と公式の使用上限。画面例。",
    "features.more": "詳しい機能を見る",
    "comp.title": "いつもの作業に、\n小さな冒険を。",
    "comp.desc": "いつものトークン使用量で、パートナーが本来の進化ルートをたどります。卒業したら新しいタマゴが届き、図鑑が少しずつ埋まっていきます。",
    "journey.hatch": "最初のパートナーに出会う",
    "journey.hatchDesc": "標準の難易度では5Mトークンで孵化。どのポケモンに出会えるでしょう？",
    "journey.grow": "成長を見守る",
    "journey.growDesc": "コードを書き続けると進化します。難易度は自分のペースに合わせて調整できます。",
    "journey.collect": "思い出を図鑑に",
    "journey.collectDesc": "卒業したパートナーは図鑑に残ります。新しいタマゴと次の物語へ。",
    "comp.caption": "パートナーとの記録が増えていく図鑑。画面例。",
    "pet.title": "デスクトップでも、一緒。",
    "pet.desc": "メニューバーからパートナーを連れ出しましょう。好きな場所へドラッグし、ホバーで使用量を確認、クリックでアプリを開けます。",
    "growth.title": "コードを書くほど、ポケモンが育つ。",
    "growth.play": "アニメーションを再生",
    "growth.pause": "アニメーションを一時停止",
    "growth.desc": "AIツールでコードを書くと、そのトークンでタマゴが孵り、ポケモンが育ちます。使うほど進化し、育て上げたパートナーは図鑑に残ります。",
    "growth.egg": "タマゴから始まる",
    "growth.eggDesc": "最初のトークンから孵化へ近づきます。",
    "growth.first": "パートナーと出会う",
    "growth.firstDesc": "孵ったタマゴから新しい仲間が。",
    "growth.evolve": "コードを書いて、進化する",
    "growth.evolveDesc": "使ったトークンが次の姿へ育てます。",
    "growth.collect": "図鑑に残して、次の出会いへ",
    "growth.collectDesc": "育て上げた仲間は図鑑へ。次は新しいタマゴ。",
    "growth.note": "フシギダネの進化例です。出会うポケモンや成長の速さは異なります。育成のために追加のAIリクエストは行いません。",
    "guide.title": "どれくらいで育つ？",
    "guide.desc": "自分のペースで計算して、進化コストや集められるものを確認しましょう。必要なトークンが多すぎると感じたら、アプリで難易度を下げて、少ないトークンで育てられます。",
    "guide.open": "育成ガイドを開く",
    "calc.pace": "1日のトークン",
    "calc.rarity": "レア度",
    "calc.nojs": "計算機にはJavaScriptが必要です。トークンコストは上の表をご覧ください。",
    "faq.title": "よくある質問。",
    "faq.free.q": "無料ですか？",
    "faq.free.a": "はい。無料のオープンソース・ファンプロジェクトです。ショップでは現金ではなく、コーディングで使ったトークンを通貨として使います。",
    "faq.privacy.q": "使用量ログを送信しますか？",
    "faq.privacy.a": "いいえ。使用量ログはMac内に保持されます。ただし、プロバイダーの使用量・上限、ポケモンのデータ・スプライト、サービス状態、更新には通信を使います。完全なオフラインアプリではありません。",
    "faq.cost.q": "育成のために追加トークンを使いますか？",
    "faq.cost.a": "いいえ。対応するコーディングツールの使用量を読み取ります。育成のためにモデルを実行することはありません。",
    "faq.source.q": "自分でビルドできますか？",
    "faq.source.a": "はい。Swiftのソースコード、ビルド手順、IssueトラッカーをGitHubで公開しています。",
    "footer.source": "ソースコード",
    "footer.releases": "リリースノート",
    "footer.help": "サポート",
    "footer.sponsor": "支援する",
    "demo.play": "デモを再生",
    "demo.stop": "デモを停止",
    "s5.t": "ふしぎなアメをもらう",
    "s5.d": "5時間または週間の上限を使い切ると、ふしぎなアメがもらえます。バッグから使ってパートナーを育てましょう。",
    "aria.nav": "メインナビゲーション",
    "aria.project": "プロジェクトリンク",
    "aria.guide": "育成ガイド",
    "aria.table": "成長と収集の詳細",
    "alt.home": "ラプラス、今日のトークン、公式上限を表示したPokeTokenBarの画面例",
    "alt.trend": "日別トークン使用量グラフの例",
    "alt.quota": "プロバイダーの上限とリセット時刻の例",
    "alt.collection": "集めたポケモンを表示した図鑑の例",
    "alt.pet": "使用量の吹き出しを表示したデスクトップペットの例",
    "f16.t": "見やすくなったコレクション",
    "f16.d": "大きくなった画像と名前で、1ページ16匹の4 × 4図鑑を表示。検索・並べ替えと、レア度・色違いの絞り込みに対応します。",
    "f17.t": "使用量の振り返り",
    "f17.d": "週・月・年ごとのトークン使用量とパートナーの成長記録を振り返りましょう。",
    "f18.t": "成長記録をバックアップ",
    "f18.d": "パートナーのデータをバックアップファイルに書き出し、必要なときに復元できます。",
    "f19.t": "複数のClaudeアカウント",
    "f19.d": "一つのアプリで複数のClaudeアカウントの公式使用上限を確認できます。",
    "f20.t": "使用ペースを色で確認",
    "f20.d": "上限バーの色で、ウィンドウの残り時間に対する使用ペースを確認できます。",
    "f21.t": "さらに集めて育てる",
    "f21.d": "アンノーンの姿を集めたり、ふしぎなアメをまとめて使ってパートナーを育てたりできます。",
    "alt.recap": "トークン使用量とアンノーンの卒業記録を表示した週間リキャップの例",
    "alt.pace": "使用ペースのマーカーを表示した上限バーの例"
  }
};
const root = document.documentElement;
const language = document.getElementById('language');
const themeButton = document.getElementById('themeBtn');
const menuButton = document.getElementById('menuBtn');
const navigation = document.getElementById('site-nav');
const copyStatus = document.getElementById('copy-status');
let copyState = '';
let currentLang = 'en';

function translated(key) { return I18N[currentLang][key] || I18N.en[key] || key; }
function applyLanguage(value) {
  currentLang = I18N[value] ? value : 'en';
  root.lang = currentLang;
  language.value = currentLang;
  document.querySelectorAll('[data-i18n]').forEach(element => {
    const value = translated(element.dataset.i18n);
    element.replaceChildren();
    value.split('\n').forEach((line, i) => {
      if (i) element.append(document.createElement('br'));
      element.append(document.createTextNode(line));
    });
  });
  themeButton.setAttribute('aria-label', translated('theme'));
  menuButton.setAttribute('aria-label', translated('nav.menu'));
  document.querySelectorAll('[data-i18n-aria]').forEach(el => el.setAttribute('aria-label', translated(el.dataset.i18nAria)));
  document.querySelectorAll('[data-i18n-alt]').forEach(el => el.setAttribute('alt', translated(el.dataset.i18nAlt)));
  syncDemoLabel();
  syncGrowthLabel();
  document.title = 'PokeTokenBar — ' + translated('hero.h1a') + ' ' + translated('hero.h1b');
  document.querySelector('meta[name="description"]').content = translated('hero.lead');
  copyStatus.textContent = copyState ? translated('copy.' + copyState) : '';
  try { localStorage.setItem('ptb-lang', currentLang); } catch (_) {}
  renderJourney();
}

function applyTheme(theme) {
  root.dataset.theme = theme;
  themeButton.setAttribute('aria-pressed', String(theme === 'dark'));
  try { localStorage.setItem('ptb-theme', theme); } catch (_) {}
}
themeButton.addEventListener('click', () => applyTheme(root.dataset.theme === 'dark' ? 'light' : 'dark'));
language.addEventListener('change', () => applyLanguage(language.value));
function closeMenu() {
  navigation.classList.remove('is-open');
  menuButton.setAttribute('aria-expanded', 'false');
}
menuButton.addEventListener('click', () => {
  const open = menuButton.getAttribute('aria-expanded') !== 'true';
  navigation.classList.toggle('is-open', open);
  menuButton.setAttribute('aria-expanded', String(open));
  if (open) navigation.querySelector('a').focus();
});
navigation.querySelectorAll('a').forEach(a => a.addEventListener('click', closeMenu));
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && menuButton.getAttribute('aria-expanded') === 'true') {closeMenu();menuButton.focus();}
});
matchMedia('(min-width: 761px)').addEventListener('change', event => {if(event.matches) closeMenu();});

document.querySelectorAll('[data-copy]').forEach(button => {
  button.addEventListener('click', async () => {
    button.disabled = true;
    copyState = 'pending';
    copyStatus.textContent = translated('copy.pending');
    copyStatus.dataset.state = 'pending';
    try {
      if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
      await navigator.clipboard.writeText(button.dataset.copy);
      copyState = 'ok';
      copyStatus.dataset.state = 'success';
    } catch (_) {
      copyState = 'error';
      copyStatus.dataset.state = 'error';
      const range = document.createRange();
      range.selectNodeContents(document.getElementById('install-command'));
      const selection = window.getSelection();
      selection.removeAllRanges();selection.addRange(range);
    } finally {
      button.disabled = false;
      copyStatus.textContent = translated('copy.' + copyState);
    }
  });
});

const tabs = [...document.querySelectorAll('[data-gtab]')];
function selectTab(selected, focus = false) {
  tabs.forEach(tab => {
    const active = tab === selected;
    tab.setAttribute('aria-selected', String(active));
    tab.tabIndex = active ? 0 : -1;
    const panel = document.getElementById(tab.getAttribute('aria-controls'));
    panel.hidden = !active;
    panel.setAttribute('role', 'tabpanel');
    panel.setAttribute('aria-labelledby', tab.id);
    panel.tabIndex = 0;
  });
  if (focus) selected.focus();
}
tabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectTab(tab));
  tab.addEventListener('keydown', event => {
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
    if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
    if (event.key === 'Home') next = 0;
    if (event.key === 'End') next = tabs.length - 1;
    if (next !== undefined) {event.preventDefault(); selectTab(tabs[next], true);}
  });
});

// Three-form, first-time hatch at 100% difficulty; costs verified against CompanionModel.swift.
const growthTotals = {common:750e6, uncommon:1.875e9, rare:3e9, legendary:6e9};
const journeyCopy = {
  en: {hatch:'Hatch',evolve:n=>`Evolution ${n}`,graduate:'Graduate · a new egg arrives',day:n=>n===1?'Day 1':`Day ${n}`},
  ko: {hatch:'부화',evolve:n=>`${n}차 진화`,graduate:'졸업 · 새 알 도착',day:n=>`${n}일째`},
  ja: {hatch:'孵化',evolve:n=>`進化 ${n}`,graduate:'卒業 · 新しいタマゴ',day:n=>`${n}日目`}
};
function renderJourney() {
  const pace = Number(document.getElementById('gPace').value) * 1e6;
  const total = growthTotals[document.getElementById('gRarity').value];
  const s = journeyCopy[currentLang];
  let cumulative = 5e6;
  const rows = [{label:s.hatch,tokens:cumulative}];
  for(let stage=1;stage<=3;stage++) {
    cumulative += total*stage/6;
    rows.push({label:stage===3?s.graduate:s.evolve(stage),tokens:cumulative});
  }
  const timeline = document.getElementById('gTimeline');
  timeline.replaceChildren(...rows.map(row => {
    const element = document.createElement('div');element.className='tl-row';
    const label = document.createElement('span');label.textContent=row.label;
    const day = document.createElement('span');day.className='tl-when';day.textContent=s.day(Math.max(1,Math.ceil(row.tokens/pace)));
    element.append(label,day);return element;
  }));
}
document.getElementById('gPace').addEventListener('change', renderJourney);
document.getElementById('gRarity').addEventListener('change', renderJourney);

const demoButton = document.getElementById('demoBtn');
const demoImage = document.getElementById('pet-demo');
function syncDemoLabel() {
  demoButton.querySelector('span').textContent = translated(demoButton.getAttribute('aria-pressed') === 'true' ? 'demo.stop' : 'demo.play');
}
function setDemoPlaying(playing) {
  demoButton.setAttribute('aria-pressed', String(playing));
  demoImage.src = playing ? 'assets/floating-pet.gif' : 'assets/floating-pet-still.png';
  syncDemoLabel();
}
demoButton.addEventListener('click', () => setDemoPlaying(demoButton.getAttribute('aria-pressed') !== 'true'));
matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change', event => { if(event.matches) setDemoPlaying(false); });

const growthMotionButton = document.getElementById('growth-motion');
const growthMotionPreference = matchMedia('(prefers-reduced-motion: reduce)');
function syncGrowthLabel() {
  growthMotionButton.querySelector('span').textContent = translated(growthMotionButton.getAttribute('aria-pressed') === 'true' ? 'growth.pause' : 'growth.play');
}
function setGrowthPlaying(playing) {
  growthMotionButton.setAttribute('aria-pressed', String(playing));
  document.querySelectorAll('[data-growth-sprite]').forEach(img => {
    img.src = `assets/growth/${img.dataset.growthSprite}.${playing ? 'gif' : 'png'}`;
  });
  syncGrowthLabel();
}
growthMotionButton.addEventListener('click', () => setGrowthPlaying(growthMotionButton.getAttribute('aria-pressed') !== 'true'));
growthMotionPreference.addEventListener('change', event => { if (event.matches) setGrowthPlaying(false); });

let initialLanguage = navigator.language.slice(0,2);
try { initialLanguage = localStorage.getItem('ptb-lang') || initialLanguage; } catch (_) {}
applyLanguage(initialLanguage);
applyTheme(root.dataset.theme === 'dark' ? 'dark' : 'light');
selectTab(tabs[0]);
// Keep baseline content available if script initialization fails or JavaScript is disabled.
root.classList.add('js');

setGrowthPlaying(!growthMotionPreference.matches);
