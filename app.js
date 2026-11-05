"use strict";
const I18N = {
  "en": {
    "f13.t": "Activity, on your terms",
    "f13.d": "Choose 7, 14 or 21 days, or this month, from the bar-chart title. Multiple tools stack by provider; hover for daily totals and a breakdown. Click the chart to switch to a 16-week grid. Its range is independent of the selected bar period, and locally stored history stays available on quiet days.",
    "f14.t": "Growth at your pace",
    "f14.d": "Set growth and shop difficulty from 10% to 200%, then apply with Save. Stage progress is preserved. Show Pokémon growth % in the menu bar, including egg progress, and hover Home’s bar for tokens, target and percentage. Hatches from a previously graduated base species grow twice as fast.",
    "f15.t": "Individual Pokémon profiles",
    "f15.d": "Inspect each individual’s level, gender, nature, ability, IVs, calculated stats and learned moves. Home and Pokédex details show type-colored badges; the individual selector appears only when there is more than one individual.",
    "nav.features": "The app",
    "nav.install": "Install",
    "hero.h1a": "Your tokens.",
    "hero.h1b": "A little companion.",
    "hero.lead": "A Pokémon that grows as you code. Track your AI token usage and limits, right from your Mac’s menu bar.",
    "copy": "Copy command",
    "f1.t": "Live token usage",
    "f1.d": "See the total from your supported tools in the menu bar. Open the popover for a breakdown by provider.",
    "f2.t": "Official limits",
    "f2.d": "See provider limits with reset timing, including OpenCode Go allowances and Grok CLI subscription credits. Choose used or remaining; numbers and progress bars follow the same choice.",
    "f3.t": "Burn-rate forecast",
    "f3.d": "Estimate when your current 5-hour window will reach 100%, based on your current usage rate.",
    "f5.t": "Localized",
    "f5.d": "Eight app UI languages, including Russian. Pokémon, type, ability and move names follow your selected language, with English when a translation is unavailable.",
    "f6.t": "Notifications",
    "f6.d": "Choose alerts for approaching usage limits, hatching, evolution and graduation.",
    "f7.t": "Token Shop",
    "f7.d": "Use tokens you’ve already spent to get Rare Candy, nature-changing Mints, a Shiny Charm or a new egg. Choose consumable quantities and see the total price. An empty Bag offers a shortcut to the Shop.",
    "f9.t": "Representative Pokémon",
    "f9.d": "Pin an owned species and form to the menu bar and desktop pet. Your current partner keeps growing in Home.",
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
    "providers.more": "16 tools. One companion.",
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
    "usage.limitsDesc": "Official Claude, Codex and Antigravity limits, OpenCode Go 5-hour / weekly / monthly allowances, and Grok CLI weekly subscription credits. Availability depends on each tool’s login or subscription.",
    "usage.caption": "Activity: sample data · UI render. Limits: English example screen.",
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
    "pet.desc": "Let your partner out of the menu bar. Drag it anywhere and hover to check usage. Click an egg to pray or a hatched Pokémon to open the app; right-click → Open always opens it.",
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
    "s5.d": "Fill a 5-hour or weekly limit to earn Rare Candy. Choose how many to use in the Bag and preview evolution or graduation, including carried-over growth.",
    "aria.nav": "Main navigation",
    "aria.project": "Project links",
    "aria.guide": "Field guide",
    "aria.table": "Growth and collection details",
    "alt.home": "Native Home sample with an incubating egg, token totals, a streak badge and the selected-period activity chart",
    "alt.trend": "Production activity UI rendered with sample data, showing bar-period selection and the 16-week activity grid",
    "alt.quota": "Example provider limits and reset timing",
    "alt.collection": "Example Pokédex showing collected species",
    "alt.pet": "Example floating desktop pet with usage callout",
    "f16.t": "A clearer collection",
    "f16.d": "Browse 16 Pokémon per page in a 4 × 4 Pokédex with larger sprites and names. Search, sort, and filter by rarity or Shiny status.",
    "f17.t": "Your usage recap",
    "f17.d": "Browse weekly, monthly and yearly recaps through the labeled Home shortcut. Hover a meter for the date and full token count, then jump to the current period. A flame beside the shortcut marks usage streaks of at least two days; it stays gray until today’s first usage extends the run.",
    "f18.t": "Back up your progress",
    "f18.d": "Export and restore companion data, or restore an automatic backup. Automatic backup history starts collapsed; the manual Create Backup button stays visible.",
    "f19.t": "Multiple Claude accounts",
    "f19.d": "Track official Claude limits across multiple accounts from the same app.",
    "f20.t": "See your usage pace",
    "f20.d": "Quota bar colors reflect your usage pace relative to the remaining time in the window.",
    "f21.t": "Collect alternate forms",
    "f21.d": "Collect Rotom appliances, Shaymin’s Land and Sky Formes, Deerling seasons, Unown letters and other supported Gen 1–5 forms. See form counts and individuals in the Pokédex. Forms follow evolution and stay in saves and exports. Types, stats, abilities and moves use the default form’s data.",
    "alt.recap": "Native weekly recap sample with token usage and Pokémon graduation records",
    "alt.pace": "Example quota bar with the usage pace marker",
    "f22.t": "Shortcuts that keep your place",
    "f22.d": "Click collected Pokémon on Home or in the catch log to open their details; Back returns to their page or log row. Page the Pokédex with the scroll wheel or larger arrow targets. Right-click the menu-bar item for Refresh, Pokédex, Settings and more.",
    "alt.forms": "Native Rotom detail sample showing owned Heat and Wash forms, individual selection and the default-form metadata note",
    "alt.bag": "Native Bag upper-region sample showing Rare Candy quantity and evolution preview with 35M growth carried over",
    "alt.shop": "Native Shop sample showing consumable quantity controls and total price",
    "alt.difficulty": "Native difficulty settings sample with labeled growth and shop slider ends",
    "native.home": "Native UI · sample data · English",
    "native.forms": "Native UI · sample Pokémon · detail scroll view continues below.",
    "native.shop": "Native UI · sample tokens · shop scroll view continues below.",
    "native.bag": "Native UI · sample items · upper Bag region.",
    "native.difficulty": "Native UI · sample settings.",
    "native.recap": "Native UI · sample usage and Pokémon.",
    "f23.t": "Choose the tools you track",
    "f23.d": "Use Settings → Tracked providers to turn individual providers on or off. An off provider is not read and is excluded from tabs, totals, Pokémon growth and official-limit requests. Devin CLI and omo (senpi) join the supported tools; Devin usage is read from its local session database without a cost estimate.",
    "f24.t": "Finish a region, collect a badge",
    "f24.d": "Filter the Pokédex to Kanto, Johto, Hoenn, Sinnoh or Unova and see owned and shiny counts. Completion badges record regional sets, shiny sets, 28 Unown forms and the 649-species national collection. These milestones are cosmetic and do not change hatch odds or growth.",
    "f25.t": "Pet, pray, and share a moment",
    "f25.d": "Move your pointer over the floating pet to pet it, click an egg to pray, and watch for sulking or occasional event bubbles. Every 30 prayers can bring a quip and a usage refresh. These reactions do not change hatch odds or growth rewards. Sprite downloads retry automatically if an animation fails to load.",
    "f26.t": "Let your coding agent say hello",
    "f26.d": "Optional URL events make the floating pet react while an agent works, waits for input or finishes. Setup is manual: add the documented Claude Code hooks or send events from another agent. PokeTokenBar does not install hooks or edit agent settings.",
    "agent.guide": "Read the agent setup guide",
    "alt.providers": "Production Settings UI with per-provider tracking switches, rendered using sample data",
    "alt.regionalDex": "Native regional collection-count and completion-badge components rendered with sample data",
    "alt.petInteractions": "Separate native pet samples for egg prayer, petting, sulking and agent waiting",
    "native.current": "Native UI renders · sample states"
  },
  "ko": {
    "f13.t": "원하는 방식으로 보는 활동",
    "f13.d": "막대 차트 제목에서 7일·14일·21일·이번 달을 선택하세요. 여러 도구를 쓰면 도구별로 쌓이고, 호버로 일별 합계와 내역을 봅니다. 차트를 클릭하면 16주 격자로 전환됩니다. 격자는 막대의 선택 기간과 별개이며, 조용한 날에도 로컬에 저장된 기록을 볼 수 있어요.",
    "f14.t": "내 속도에 맞는 성장",
    "f14.d": "성장·상점 난이도를 10%~200%로 조절하고 저장하세요. 현재 단계의 진행률은 유지됩니다. 메뉴바에 알 부화를 포함한 포켓몬 성장률을 표시하고, 홈 막대 호버로 사용량·목표·진행률을 확인하세요. 졸업한 기본 종에서 다시 부화하면 두 배 빠르게 자랍니다.",
    "f15.t": "포켓몬 개체별 상세",
    "f15.d": "개체별 레벨·성별·성격·특성·IV·계산된 능력치·배운 기술을 확인하세요. 홈과 도감 상세에는 타입 색상 배지가 표시되고, 개체 선택기는 두 마리 이상일 때만 나타나요.",
    "nav.features": "앱 둘러보기",
    "nav.install": "설치",
    "hero.h1a": "당신의 토큰이,",
    "hero.h1b": "작은 동료로.",
    "hero.lead": "코딩하는 동안 포켓몬이 자라요. Mac 메뉴바에서 AI 토큰 사용량과 한도를 확인하고, 함께할 파트너를 키우세요.",
    "copy": "명령어 복사",
    "f1.t": "실시간 토큰 사용량",
    "f1.d": "오늘 쓴 Claude Code·Codex·Gemini·Antigravity·OpenCode·Hermes·Cursor·Grok·Copilot·Kiro·Pi·omp·Aside 토큰 합계를 메뉴바에 간결하게(예: 253.4M). 팝오버에선 서비스별 탭으로 상세를 넘나들어요.",
    "f2.t": "공식 사용 한도",
    "f2.d": "OpenCode Go 사용량과 Grok CLI 구독 크레딧을 포함한 도구별 한도와 리셋 시점을 확인하세요. 사용량·남은량을 선택하면 숫자와 막대가 함께 바뀝니다.",
    "f3.t": "한도 소진 예측",
    "f3.d": "지금 속도라면 5시간 한도에 언제 닿을지 미리 알려줘요. 갑자기 막혀서 당황할 일이 없죠.",
    "f5.t": "다국어 지원",
    "f5.d": "러시아어를 포함한 8개 앱 UI 언어를 지원해요. 포켓몬·타입·특성·기술 이름도 선택한 언어를 따르며, 번역이 없으면 영어를 표시해요.",
    "f6.t": "알림",
    "f6.d": "한도가 경고·임박 기준을 넘거나, 파트너가 부화·진화·졸업할 때 알려줘요.",
    "f7.t": "토큰 상점",
    "f7.d": "이미 사용한 토큰으로 이상한 사탕, 성격을 바꾸는 민트, 빛나는부적, 새 알을 구매하세요. 소모품 수량과 총가격을 확인할 수 있고, 가방이 비어 있으면 상점으로 바로 갈 수 있어요.",
    "f9.t": "대표 포켓몬",
    "f9.d": "소유한 종과 폼을 메뉴바·데스크톱 펫의 대표 포켓몬으로 고정하세요. 현재 파트너는 홈에서 계속 성장해요.",
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
    "providers.more": "16개 도구, 하나의 파트너",
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
    "usage.limitsDesc": "Claude·Codex·Antigravity의 공식 한도, OpenCode Go의 5시간·주간·월간 사용량, Grok CLI의 주간 구독 크레딧을 확인하세요. 도구의 로그인·구독 상태에 따라 표시됩니다.",
    "usage.caption": "활동: 샘플 데이터 · UI 렌더. 한도: 영어 예시 화면.",
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
    "pet.desc": "파트너를 메뉴바 밖으로 꺼내보세요. 드래그로 옮기고, 호버로 사용량을 확인하세요. 알을 클릭하면 기도하고, 부화한 포켓몬을 클릭하면 앱을 엽니다. 우클릭 → 열기로는 언제든 열 수 있어요.",
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
    "s5.d": "5시간 또는 주간 한도를 채우면 이상한 사탕을 받아요. 가방에서 사용할 수량을 고르고 진화·졸업과 이월되는 성장량을 미리 확인하세요.",
    "aria.nav": "주요 탐색",
    "aria.project": "프로젝트 링크",
    "aria.guide": "성장 가이드",
    "aria.table": "성장 및 수집 상세 정보",
    "alt.home": "부화 중인 알·토큰 합계·연속 사용 배지·선택 기간 활동 차트를 표시한 실제 홈 UI 샘플",
    "alt.trend": "기간 선택 막대 차트와 16주 활동 격자를 샘플 데이터로 렌더링한 실제 UI",
    "alt.quota": "프로바이더 한도와 리셋 시점 예시",
    "alt.collection": "수집한 포켓몬이 표시된 도감 예시",
    "alt.pet": "사용량 말풍선이 표시된 바탕화면 펫 예시",
    "f16.t": "더 잘 보이는 컬렉션",
    "f16.d": "커진 이미지와 이름으로 한 페이지에 16마리를 4 × 4 도감에서 확인하세요. 검색·정렬과 희귀도·이로치 필터를 지원합니다.",
    "f17.t": "사용량 리캡",
    "f17.d": "홈의 이름이 붙은 버튼으로 주·월·연도별 회고를 여세요. 막대 호버로 날짜와 전체 토큰 수를 확인하고 현재 기간으로 바로 돌아옵니다. 버튼 옆 불꽃은 이틀 이상 연속 사용 일수를 표시하며, 오늘 첫 사용으로 기록을 잇기 전에는 회색입니다.",
    "f18.t": "성장 기록 백업",
    "f18.d": "파트너 데이터를 내보내고 복원하거나 자동 백업으로 되돌릴 수 있어요. 자동 백업 기록은 처음에 접혀 있고, 수동 백업 생성 버튼은 계속 보여요.",
    "f19.t": "여러 Claude 계정",
    "f19.d": "하나의 앱에서 여러 Claude 계정의 공식 사용 한도를 확인하세요.",
    "f20.t": "사용 속도를 색으로 확인",
    "f20.d": "한도 막대 색상이 해당 구간의 남은 시간 대비 사용 속도를 보여줍니다.",
    "f21.t": "다양한 폼 수집",
    "f21.d": "로토무의 가전 폼, 쉐이미의 랜드·스카이폼, 사철록의 계절 모습, 안농 문자 등 지원되는 1~5세대 폼을 수집하세요. 도감에서 폼별 수와 개체를 확인하고, 진화·저장·내보내기에도 폼이 유지돼요. 타입·능력치·특성·기술 정보는 기본 폼 기준이에요.",
    "alt.recap": "토큰 사용량과 포켓몬 졸업 기록이 표시된 실제 주간 회고 UI 샘플",
    "alt.pace": "사용 속도 마커가 표시된 한도 막대 예시",
    "f22.t": "보던 위치로 돌아가기",
    "f22.d": "홈이나 포획 기록의 포켓몬을 눌러 상세를 열고, 뒤로가기로 원래 페이지·기록 행에 돌아오세요. 도감은 스크롤 휠이나 더 넓어진 화살표로 넘길 수 있어요. 메뉴바를 우클릭하면 새로고침·도감·설정 등으로 바로 갈 수 있어요.",
    "alt.forms": "히트·워시 폼 보유 수, 개체 선택기, 기본 폼 정보 안내가 표시된 실제 로토무 상세 UI 샘플",
    "alt.bag": "이상한 사탕 수량과 성장량 35M이 이월되는 진화 미리보기를 보여 주는 실제 가방 UI 상단 샘플",
    "alt.shop": "소모품 수량과 총가격을 보여 주는 실제 상점 UI 샘플",
    "alt.difficulty": "성장·상점 슬라이더 양끝에 값이 표시된 실제 난이도 설정 UI 샘플",
    "native.home": "실제 UI 렌더 · 샘플 데이터 · 영어",
    "native.forms": "실제 UI 렌더 · 샘플 포켓몬 · 아래로 상세 스크롤이 이어져요.",
    "native.shop": "실제 UI 렌더 · 샘플 토큰 · 아래로 상점 스크롤이 이어져요.",
    "native.bag": "실제 UI 렌더 · 샘플 아이템 · 가방 상단.",
    "native.difficulty": "실제 UI 렌더 · 샘플 설정.",
    "native.recap": "실제 UI 렌더 · 샘플 사용량과 포켓몬.",
    "f23.t": "추적할 도구를 고르세요",
    "f23.d": "설정 → 추적할 프로바이더에서 도구별 추적을 켜고 끄세요. 끈 도구는 읽지 않고 탭·합계·포켓몬 성장·공식 한도 요청에서 제외합니다. Devin CLI와 omo(senpi)도 지원하며, Devin은 로컬 세션 DB에서 사용량을 읽고 비용은 추정하지 않습니다.",
    "f24.t": "지방을 완성하고 배지를 모으세요",
    "f24.d": "관동·성도·호연·신오·하나로 도감을 좁혀 보유 종과 이로치 수를 확인하세요. 지방별 일반·이로치 도감, 안농 28가지 폼, 전국 649종 수집에 완성 배지가 주어집니다. 수집 기록을 위한 배지이며 부화 확률과 성장은 바뀌지 않아요.",
    "f25.t": "쓰다듬고 기도하며 함께하기",
    "f25.d": "플로팅 펫 위로 포인터를 움직여 쓰다듬고, 알을 클릭해 기도하고, 삐침과 가끔 나타나는 이벤트 말풍선을 보세요. 기도 30회마다 한마디와 사용량 새로고침이 나타날 수 있습니다. 부화 확률이나 성장 보상은 바뀌지 않아요. 애니메이션 다운로드에 실패하면 자동으로 재시도합니다.",
    "f26.t": "코딩 에이전트의 소식도 펫으로",
    "f26.d": "선택적으로 URL 이벤트를 보내 에이전트의 작업·입력 대기·완료에 맞춰 펫을 움직일 수 있습니다. 문서의 Claude Code 훅을 추가하거나 다른 에이전트에서 이벤트를 보내는 수동 설정입니다. 앱이 훅을 설치하거나 에이전트 설정을 수정하지는 않습니다.",
    "agent.guide": "에이전트 연동 설정 보기",
    "alt.providers": "도구별 추적 스위치를 샘플 데이터로 렌더링한 실제 설정 UI",
    "alt.regionalDex": "지방별 수집 수와 완성 배지 컴포넌트를 샘플 데이터로 렌더링한 보드",
    "alt.petInteractions": "알 기도·쓰다듬기·삐침·에이전트 대기를 각각 렌더링한 실제 펫 샘플",
    "native.current": "실제 UI 렌더 · 샘플 상태"
  },
  "ja": {
    "f13.t": "活動を好きな表示で",
    "f13.d": "棒グラフの見出しで7日・14日・21日・今月を選択。複数のツールは積み上げて表示し、ホバーで日別合計と内訳を確認できます。クリックで16週間のグリッドに切り替わり、棒グラフとは別の範囲を表示。静かな日も保存済みのローカル履歴を見られます。",
    "f14.t": "自分のペースで育成",
    "f14.d": "成長とショップの難易度を10%〜200%で調整し、保存で適用。現在段階の進捗は保ちます。タマゴを含むポケモンの成長率をメニューバーに表示でき、ホームのバーへのホバーで使用量・目標・割合を確認。卒業済みの基本種から再び孵化すると2倍の速さで育ちます。",
    "f15.t": "ポケモンごとの詳細",
    "f15.d": "個体ごとのレベル・性別・性格・特性・IV・計算された能力値・覚えた技を確認。ホームと図鑑の詳細にはタイプ別の色付きバッジがあり、個体の選択欄は2匹以上のときだけ表示します。",
    "nav.features": "アプリを見る",
    "nav.install": "インストール",
    "hero.h1a": "あなたのトークンが、",
    "hero.h1b": "小さなパートナーに。",
    "hero.lead": "コードを書くたび、ポケモンが育つ。MacのメニューバーでAIトークンの使用量と上限を確認しながら、パートナーを育てましょう。",
    "copy": "コマンドをコピー",
    "f1.t": "リアルタイムの使用量",
    "f1.d": "今日の Claude Code・Codex・Gemini・Antigravity・OpenCode・Hermes・Cursor・Grok・Copilot・Kiro・Pi・omp・Aside トークン合計をメニューバーにコンパクト表示（例：253.4M）。ポップオーバーではサービス別タブで詳細を切替。",
    "f2.t": "公式の使用上限",
    "f2.d": "OpenCode Go の利用枠や Grok CLI のサブスクリプションクレジットなど、各ツールの上限とリセット時刻を表示。使用量・残量の選択に数値とバーが連動します。",
    "f3.t": "上限到達の予測",
    "f3.d": "今のペースなら5時間の上限にいつ達するかを事前に予測。急に止まって困ることがありません。",
    "f5.t": "多言語対応",
    "f5.d": "ロシア語を含む8つのアプリUI言語に対応。ポケモン・タイプ・特性・技の名前も選択した言語に従い、翻訳がない場合は英語で表示します。",
    "f6.t": "通知",
    "f6.d": "上限が警告・危険のラインを超えたとき、そしてパートナーが孵化・進化・卒業したときにお知らせします。",
    "f7.t": "トークンショップ",
    "f7.d": "使用済みのトークンでふしぎなアメ、性格を変えるミント、ひかるおまもり、新しいタマゴを購入。消耗品の数量と合計価格を確認でき、空のバッグからショップへ直接移動できます。",
    "f9.t": "代表ポケモン",
    "f9.d": "所有する種と姿をメニューバーとデスクトップペットの代表に固定。現在のパートナーはホームで成長し続けます。",
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
    "providers.more": "16のツール、ひとりのパートナー",
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
    "usage.limitsDesc": "Claude・Codex・Antigravity の公式上限、OpenCode Go の5時間・週間・月間利用枠、Grok CLI の週間サブスクリプションクレジットを表示。各ツールのログイン・契約により異なります。",
    "usage.caption": "活動：サンプルデータ · UI レンダー。上限：英語の画面例。",
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
    "pet.desc": "パートナーをメニューバーから連れ出しましょう。ドラッグで移動、ホバーで使用量を確認。タマゴをクリックするとお祈りし、孵化したポケモンならアプリを開きます。右クリック → 開くならいつでも開けます。",
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
    "s5.d": "5時間または週間の上限を使い切ると、ふしぎなアメがもらえます。バッグで使用数を選び、進化・卒業と繰り越す成長量を事前に確認できます。",
    "aria.nav": "メインナビゲーション",
    "aria.project": "プロジェクトリンク",
    "aria.guide": "育成ガイド",
    "aria.table": "成長と収集の詳細",
    "alt.home": "孵化中のタマゴ・トークン合計・連続使用バッジ・選択期間の活動グラフを示す実際のホームUIサンプル",
    "alt.trend": "期間を選べる棒グラフと16週間の活動グリッドをサンプルデータで描画した実際のUI",
    "alt.quota": "プロバイダーの上限とリセット時刻の例",
    "alt.collection": "集めたポケモンを表示した図鑑の例",
    "alt.pet": "使用量の吹き出しを表示したデスクトップペットの例",
    "f16.t": "見やすくなったコレクション",
    "f16.d": "大きくなった画像と名前で、1ページ16匹の4 × 4図鑑を表示。検索・並べ替えと、レア度・色違いの絞り込みに対応します。",
    "f17.t": "使用量の振り返り",
    "f17.d": "ホームのラベル付きボタンから週・月・年の振り返りへ。バーにホバーすると日付と全トークン数を表示し、現在の期間にすぐ戻れます。横の炎は2日以上の連続使用日数を示し、今日最初の使用で記録を延ばすまでは灰色です。",
    "f18.t": "成長記録をバックアップ",
    "f18.d": "パートナーデータを書き出して復元したり、自動バックアップから戻したりできます。自動バックアップ履歴は最初は折りたたまれ、手動のバックアップ作成ボタンは常に表示されます。",
    "f19.t": "複数のClaudeアカウント",
    "f19.d": "一つのアプリで複数のClaudeアカウントの公式使用上限を確認できます。",
    "f20.t": "使用ペースを色で確認",
    "f20.d": "上限バーの色で、ウィンドウの残り時間に対する使用ペースを確認できます。",
    "f21.t": "さまざまなフォルムを集める",
    "f21.d": "ロトムの家電フォルム、シェイミのランド・スカイフォルム、シキジカの季節、アンノーン文字など、対応する第1〜5世代の姿を収集。図鑑で姿別の数と個体を確認でき、進化・保存・書き出しでも姿を維持します。タイプ・能力値・特性・技の情報は通常の姿を基準にします。",
    "alt.recap": "トークン使用量とポケモンの卒業記録を表示した実際の週間振り返りUIサンプル",
    "alt.pace": "使用ペースのマーカーを表示した上限バーの例",
    "f22.t": "見ていた場所に戻る",
    "f22.d": "ホームや捕獲記録のポケモンから詳細を開き、戻ると元のページ・記録行へ。図鑑はスクロールホイールや広くなった矢印でも切り替えられます。メニューバーを右クリックすると更新・図鑑・設定などに移動できます。",
    "alt.forms": "ヒート・ウォッシュの所有数、個体選択、通常の姿の情報に関する注記を表示した実際のロトム詳細UIサンプル",
    "alt.bag": "ふしぎなアメの数量と成長量35Mを繰り越す進化プレビューを示す実際のバッグUI上部サンプル",
    "alt.shop": "消耗品の数量と合計価格を示す実際のショップUIサンプル",
    "alt.difficulty": "育成・ショップのスライダー両端に値を表示した実際の難易度設定UIサンプル",
    "native.home": "実際のUIレンダー · サンプルデータ · 英語",
    "native.forms": "実際のUIレンダー · サンプルポケモン · 下に詳細が続きます。",
    "native.shop": "実際のUIレンダー · サンプルトークン · 下に商品が続きます。",
    "native.bag": "実際のUIレンダー · サンプルアイテム · バッグ上部。",
    "native.difficulty": "実際のUIレンダー · サンプル設定。",
    "native.recap": "実際のUIレンダー · サンプル使用量とポケモン。",
    "f23.t": "記録するツールを選ぶ",
    "f23.d": "設定 → 集計するプロバイダーでツールごとの記録をオン・オフ。オフのツールは読み取らず、タブ・合計・ポケモンの成長・公式上限の取得から除外します。Devin CLI と omo（senpi）も対応。Devin はローカルのセッションDBから使用量を読み、費用は推定しません。",
    "f24.t": "地方を完成させてバッジを集める",
    "f24.d": "カントー・ジョウト・ホウエン・シンオウ・イッシュで図鑑を絞り、所有数と色違いの数を確認。地方ごとの通常・色違い図鑑、アンノーン28フォルム、全国649種の完成バッジを集めましょう。収集の記録であり、孵化確率や成長は変わりません。",
    "f25.t": "なでて、お祈りして、一緒に過ごす",
    "f25.d": "ペットの上でポインタを動かしてなでたり、タマゴをクリックしてお祈りしたりできます。すねる姿や時折のイベントの吹き出しも。30回のお祈りごとに一言と使用量の更新が出ることがあります。孵化確率と成長報酬は変わりません。アニメーションの取得失敗時は自動で再試行します。",
    "f26.t": "コーディングエージェントからの便り",
    "f26.d": "任意のURLイベントで作業・入力待ち・完了に合わせてペットを動かせます。文書の Claude Code フックを追加するか、ほかのエージェントからイベントを送る手動設定です。アプリがフックをインストールしたり、エージェント設定を編集したりすることはありません。",
    "agent.guide": "エージェント連携の設定を読む",
    "alt.providers": "ツールごとの記録スイッチをサンプルデータで描画した実際の設定UI",
    "alt.regionalDex": "地方ごとの収集数と完成バッジのコンポーネントをサンプルデータで描画したボード",
    "alt.petInteractions": "タマゴへのお祈り・なでる動作・すねる姿・エージェントの入力待ちを個別に描画した実際のペットサンプル",
    "native.current": "実際の UI レンダー · サンプル状態"
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
  document.querySelectorAll('[data-i18n-image]').forEach(el => {
    const suffix = currentLang === 'en' ? '' : '-' + currentLang;
    el.src = 'assets/' + el.dataset.i18nImage + suffix + '.png';
  });
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
