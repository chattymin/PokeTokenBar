<div align="center">

<img src="assets/icon.png" width="128" alt="PokeTokenBar icon">

# PokeTokenBar

**Your AI coding tokens, hatched into Pokémon — right in your menu bar.**

[![Release](https://img.shields.io/github/v/release/chattymin/PokeTokenBar?color=444d56&label=release)](https://github.com/chattymin/PokeTokenBar/releases)
[![macOS](https://img.shields.io/badge/macOS-14%2B-0969da)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-f05138)](https://swift.org)
[![Homebrew](https://img.shields.io/badge/Homebrew-cask-8957e5)](#homebrew)
[![License](https://img.shields.io/badge/license-MIT-3fb950)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%99%A5-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/chattymin)

<a href="https://trendshift.io/repositories/84522?utm_source=repository-badge&amp;utm_medium=badge&amp;utm_campaign=badge-repository-84522" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/repositories/84522" alt="chattymin%2FPokeTokenBar | Trendshift" width="250" height="55"/></a>
<a href="https://trendshift.io/repositories/84522?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-84522" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/84522/daily?language=Swift" alt="chattymin%2FPokeTokenBar | Trendshift" width="250" height="55"/></a>

**English** · [한국어](README.ko.md) · [日本語](README.ja.md)

</div>

PokeTokenBar turns the AI coding tokens you're already burning — Claude Code, Codex, Gemini CLI, Antigravity, OpenCode, Hermes Agent, Cursor, Grok CLI, Copilot CLI, Kiro CLI, Pi Agent & omp — into a growing **Pokémon companion** in your macOS menu bar. Spend tokens, hatch an egg, evolve it through its real evolution line, graduate it into your Pokédex, and start again. Underneath the companion it's a precise usage tracker — today's spend, cost, and official 5-hour / weekly limits, read straight from your local logs.

> Token usage is read directly from local Claude Code, Codex, Gemini CLI, Antigravity, OpenCode, Hermes Agent, Cursor, Grok CLI, Copilot CLI, Kiro CLI, Pi Agent, and omp data (`totalTokens` = input + output + cache, local date) — no external CLI needed. Unofficial, non-commercial Pokémon fan project — see [License & disclaimer](#license--disclaimer).

## Fork of [chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar)

This repository is a fork of [PokeTokenBar](https://github.com/chattymin/PokeTokenBar) by [chattymin](https://github.com/chattymin). All credit for the original macOS menu-bar app, the Pokémon companion system, and the underlying usage-tracking design belongs to the original author.

This fork adds an **iOS companion app** and **WidgetKit extension** that connect to the Mac app over the local network. The upstream project may not adopt these additions — see the [original repo](https://github.com/chattymin/PokeTokenBar) for the macOS-only version.

## Why

- **The usage tracker you actually enjoy opening.** Your spend raises a Pokémon that hatches, evolves, graduates, and fills a Pokédex — and every shiny is a reason to check back.
- See today's token spend & cost at a glance — no dashboard, no browser tab.
- Track official **5-hour / weekly** limits with reset countdowns and a burn-rate forecast for when you'll hit them.

<div align="center">
<img src="assets/screenshot-home.gif" width="420" alt="Popover home — companion, today's tokens, official limits">
</div>

## How it works

1. 🥚 **Code as usual.** The tokens you burn in Claude Code, Codex, Gemini CLI, Antigravity, OpenCode, Hermes Agent, Cursor, Grok CLI, Copilot CLI, Kiro CLI, Pi Agent, or omp incubate an egg — nothing extra to run.
2. 🐣 **Hatch.** Eggs hatch into Pokémon with real evolution lines from [PokéAPI](https://pokeapi.co/) — any Gen 1–5 line (329 possible starts), weighted by the official capture rate: commons hatch often, a legendary is a 1-in-129 event. It appears in your **Pokédex** immediately while you raise it. Every hatch rolls one of 25 natures — and once in a rare while, the egg hatches **✨ Shiny**.
3. ⚡ **Evolve.** Keep coding and it grows through its actual evolution tree (1/2/3 stages, branching), with a little flash celebration at each step.
4. 🎓 **Graduate & collect.** Final form + threshold permanently archives it in your **Pokédex** — rarer takes longer (≈3 days common → ≈24 days legendary at heavy use) — and a fresh egg arrives.
5. 🍬 **Max out, get a candy.** Fill a 5-hour or weekly usage limit and you earn **Rare Candy** — spend it from the **Bag** to grow your current Pokémon.
6. 🛒 **Spend at the Shop.** Every token you've used is spendable currency — buy **Rare Candy**, a **Mint** that re-rolls your Pokémon's nature, a **Shiny Charm** that permanently raises your shiny odds, or an egg to send off your current companion and start over. Eggs come in three grades: a plain **Pokémon Egg**, an **Uncommon Egg** guaranteed to hatch Uncommon or better, and a **Rare Egg** guaranteed to hatch Rare or better.

## Tour

<table>
<tr>
<td width="45%" align="center"><img src="assets/floating-pet.gif" width="340" alt="Floating desktop pet with a hover callout and right-click menu"></td>
<td width="55%" valign="middle">
<h3>🐾 Let it live on your desktop</h3>
Move your companion out of the menu bar and onto the desktop, at any size from 48 to 192px. Hover it for today's usage, click to open the popover, right-click for a menu, drag it wherever you like — and limit alerts can appear as a speech bubble above it.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>In your menu bar</h3>
An animated Gen-V sprite lives next to today's total tokens (compact, e.g. <code>200.7M</code>). Add today's cost (<code>$</code>) or official limit <code>%</code> — or turn everything off for a character-only bar.
</td>
<td width="45%" align="center"><img src="assets/menubar.gif" width="240" alt="Menu bar"></td>
</tr>
<tr>
<td width="45%" align="center"><img src="assets/shiny-banner.gif" width="340" alt="Normal vs shiny"></td>
<td width="55%" valign="middle">
<h3>✨ Once in a rare while — Shiny</h3>
Shiny hatches keep their distinct colors through every evolution — menu bar, home card, evolution line. In the Pokédex a ✨ sits next to the dex number, and tapping the cell swaps in the shiny colors. A dedicated notification makes sure you don't miss the moment.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>A Pokédex worth filling</h3>
The <b>Pokédex</b> folds every species you've owned into one cell — 24 per page in dex-number order, and a ✨ on the ones you own shiny. The <b>Catch log</b> keeps the individuals: newest first, each with its full evolution line, rarity, nature, and capture date.
</td>
<td width="45%" align="center"><img src="assets/screenshot-collection-pokedex.png" width="300" alt="Pokédex — one cell per species"><br><br><img src="assets/screenshot-collection-catchlog.png" width="300" alt="Catch log — one row per Pokémon raised"></td>
</tr>
<tr>
<td width="45%" align="center"><img src="assets/settings.png" width="300" alt="Settings"></td>
<td width="55%" valign="middle">
<h3>Tune it your way</h3>
Menu-bar items, refresh interval (1–15 min or manual), launch at login, a Keychain opt-out that just hides the limits section, limit alerts with warning/critical thresholds, and companion event notifications. Full <b>KO / EN / JA / ES / FR / PT</b> UI and Pokémon names.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>🍬 Fill a limit, earn a Rare Candy</h3>
Max out a 5-hour or weekly usage limit and you're handed a <b>Rare Candy</b> — one per 5-hour cap, five per weekly. Spend it from the new <b>Bag</b> tab to grow your current Pokémon: the moment you're rate-limited becomes the moment you level up.
</td>
<td width="45%" align="center"><img src="assets/screenshot-bag.png" width="300" alt="Rare Candy and Mint in the Bag"></td>
</tr>
<tr>
<td width="45%" align="center"><img src="assets/screenshot-shop.png" width="300" alt="Token Shop — Mint, Rare Candy, Pokémon Egg, Uncommon Egg, Shiny Charm, Rare Egg"></td>
<td width="55%" valign="middle">
<h3>🛒 A shop that runs on your usage</h3>
The tokens you've already used are your currency. Spend them in the new <b>Shop</b> tab on <b>Rare Candy</b> to grow your current Pokémon, a <b>Mint</b> to re-roll its nature, a <b>Shiny Charm</b> that permanently raises your shiny hatch odds, or an egg to send off your companion and start over. Eggs come in three grades — a plain <b>Pokémon Egg</b>, an <b>Uncommon Egg</b> that always hatches Uncommon or better, and a <b>Rare Egg</b> that always hatches Rare or better. Legendaries stay in the pool for both graded eggs, so a guaranteed hatch can still surprise you.
</td>
</tr>
<tr>
<td width="55%" valign="middle">
<h3>📊 Official limits, now for Antigravity too</h3>
Antigravity 2.0 and the IDE report real quota, not an estimate. Gemini models and Claude &amp; GPT models each get their own <b>5-hour</b> and <b>weekly</b> buckets with reset countdowns, alongside Claude Code and Codex. Read quietly in the background — no Keychain prompt, and the session refreshes itself.
</td>
<td width="45%" align="center"><img src="assets/screenshot-antigravity-limits.png" width="300" alt="Antigravity official limits — 5-hour and weekly buckets per model group"></td>
</tr>
<tr>
<td width="45%" align="center"><img src="assets/screenshot-scan-folders.png" width="300" alt="Additional scan folders in Settings → Advanced"></td>
<td width="55%" valign="middle">
<h3>📁 Logs somewhere unusual? Point at them</h3>
If a tool keeps its sessions outside the built-in paths, add your own roots under <b>Settings → Advanced</b> — comma or newline separated, <code>*</code> wildcards, with a live count of how many extra folders currently match. Every provider keeps its own list, so one tool's folders are never handed to another tool's parser, and your custom roots are added to the built-in ones rather than replacing them.
</td>
</tr>
</table>

## Also in the box

- **Representative Pokémon** — pin any owned Pokédex species to the menu bar and optional floating pet, independently of the companion you're raising. While pinned, the menu bar stops following egg, hatch, and evolution changes; raising progress remains visible on Home.
- **Animation quality** — pick how smoothly the menu bar sprite and the floating pet animate (Power saver / Balanced / Smooth). Both always-visible surfaces share the setting. Power saver is the default and keeps the frame rate the app used before this setting existed; Balanced and Smooth trade battery for smoothness (measured idle CPU ~1.8% and ~5.1%).
- **Interactive floating pet** — hover for today's usage, click to open the main window, right-click for a menu, and show limit alerts as speech bubbles.
- **Per-service tabs** — when two or more of Claude Code, Codex, Gemini CLI, Antigravity, OpenCode, Hermes Agent, Cursor, Grok CLI, Copilot CLI, Kiro CLI, Pi Agent, and omp are detected, compact tabs switch between them; today's total stays combined.
- **Official limits** — Claude, Codex & Antigravity 5-hour / weekly utilization with reset countdowns, right under today's numbers.
- **Additional scan folders** — per-provider extra scan roots for logs kept outside the built-in paths (Settings → Advanced).
- **Burn-rate forecast** — projects when the current 5h window hits 100%.
- **In-app updates** — one-click update check; current version shown in Settings.
- **iOS companion app** *(this fork)* — syncs from the Mac app via iCloud (or your local network) and shows token usage and cost (today/week/month), burn-rate forecast, rate limits per provider (Claude, Codex, OpenCode Go, Antigravity) with the Mac's own warning thresholds, your companion with its status line and evolution line, plus read-only Shop, Bag, and Collection tabs. UI localized in English, Korean, Japanese, and Spanish.
- **WidgetKit extension** *(this fork)* — a medium home-screen widget with your companion sprite, today/week usage, cost, and a utilization bar per rate-limit window (with reset countdowns) — no network required once data is synced.

## Works with

| Tool | Tracked | Official limits |
|---|---|---|
| **Claude Code** | today · 5h block · week · month | ✅ 5h / weekly |
| **Codex** | today · week · month | ✅ 5h / weekly |
| **Gemini CLI** | today · week · month | — |
| **Antigravity** | today · 5h block · week · month | ✅ 5h / weekly |
| **OpenCode** | today · 5h block · week · month | — |
| **Hermes Agent** | today · 5h block · week · month | — |
| **Cursor** | today · 5h block · week · month | — |
| **Grok CLI** | today · 5h block · week · month | — |
| **Copilot CLI** | today · 5h block · week · month | — |
| **Kiro CLI** | today · 5h block · week · month | — (estimated) |
| **Pi Agent** | today · 5h block · week · month | — |
| **omp** (oh-my-pi) | today · 5h block · week · month | — |

All read locally — no external usage CLI required. Adding a tool is one provider file (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## Install

### Requirements

macOS 14+ (Apple Silicon or Intel). That's it — token usage is read directly from local Claude Code, Codex, Gemini CLI, Antigravity, OpenCode, Hermes Agent, Cursor, Grok CLI, Copilot CLI, Kiro CLI, Pi Agent, and omp data, with no external usage CLI required.

### Homebrew

```bash
brew install --cask chattymin/tap/poke-token-bar
```

ad-hoc/self-signed; the cask strips the quarantine attribute on install.

### Manual install (without Homebrew)

Prefer not to use Homebrew? Download `PokeTokenBar.zip` from the [latest release](https://github.com/chattymin/PokeTokenBar/releases/latest), unzip it, and drag `PokeTokenBar.app` into `/Applications`.

Because the app is ad-hoc/self-signed (not notarized under an Apple Developer account), Gatekeeper shows an "unidentified developer" warning on first launch. Clear it once, either way:

- **Finder:** right-click (or Control-click) `PokeTokenBar.app` → **Open** → **Open** again in the dialog.
- **Terminal:** `xattr -dr com.apple.quarantine /Applications/PokeTokenBar.app`

(The Homebrew cask strips quarantine for you, so it needs no extra step.)

### Build from source

```bash
swift build                  # debug
swift test                   # unit tests
./scripts/build-app.sh       # release → PokeTokenBar.app → /Applications
```

## Data sources

| Source | Used for | Notes |
|---|---|---|
| `~/.claude/projects/**/*.jsonl` | Claude Code daily/blocks/weekly/monthly | read directly; deduped by message id; cached incrementally |
| `~/.gemini/tmp/**/chats/*.json(l)` | Gemini CLI daily/monthly | session records (`tokens` per message); weekly = daily sum |
| `~/.gemini/antigravity/conversations/*.db`<br>`~/.gemini/antigravity-cli/conversations/*.db`<br>`~/.gemini/antigravity-ide/conversations/*.db` | Antigravity daily/blocks/weekly/monthly | SQLite read-only; per-call usage from the Cascade protobuf blob; supports Antigravity 2.0/Core, CLI & IDE; its own provider, not folded into Gemini; a subscription, so no cost is estimated |
| `~/.codex/sessions/**/*.jsonl` | Codex daily/monthly | `token_count` events; weekly = daily sum |
| `~/.local/share/opencode/opencode.db` | OpenCode daily/blocks/weekly/monthly | SQLite read-only; legacy `storage/message` JSON is also supported |
| `~/.hermes/state.db` | Hermes Agent daily/blocks/weekly/monthly | SQLite read-only; session token totals and persisted cost |
| `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` | Cursor daily/blocks/weekly/monthly | SQLite read-only fallback (`cursorDiskKV` bubble `tokenCount`); when signed in, primary source is `cursor.com` dashboard API (see Privacy) |
| `cursor.com` (dashboard API) | Cursor daily/blocks/weekly/monthly | unofficial JSON endpoint (`get-filtered-usage-events`); session from `cursorAuth/accessToken` in `state.vscdb` or `CURSOR_SESSION_TOKEN`; refetches when the provider reloads; on network error falls back to an account-scoped disk cache up to 6 h old; disable with `CURSOR_USAGE_API=0` |
| `~/.grok/sessions/**/updates.jsonl` | Grok CLI daily/blocks/weekly/monthly | `turn_completed` records (per-turn `usage`, server-reported cost); honours `$GROK_HOME`; subagent sessions are skipped because their tokens are already folded into the parent turn |
| `~/.copilot/session-store.db` | Copilot CLI daily/blocks/weekly/monthly | SQLite read-only; one `assistant_usage_events` row per API call; honours `$COPILOT_HOME`; `input_tokens` already contains the cached prompt, so cache reads/writes are subtracted; premium-request billing, so no cost is estimated |
| `~/Library/Application Support/kiro-cli/data.sqlite3`<br>`~/.kiro/sessions/cli/*.jsonl`<br>`~/.kiro/sessions/<ws>/<session>/messages.jsonl` | Kiro CLI daily/blocks/weekly/monthly | Pre-2.20 SQLite plus 2.20+ / `--v3` JSONL; neither store records real token counts, so input is a bytes÷4 **estimate** of accumulated conversation text resent on every turn; `usage_summary` credits are not converted to USD; a `/clear`d SQLite conversation's already-counted tokens stay counted until the app restarts; honours `$KIRO_CLI_HOME` and `$KIRO_HOME` |
| `~/.pi/agent/sessions/**/*.jsonl` | Pi Agent daily/blocks/weekly/monthly | Direct persisted usage from all projects; `$PI_CODING_AGENT_DIR` and `$PI_CODING_AGENT_SESSION_DIR` overrides supported; output already includes reasoning (not counted twice); forked history deduplicated by entry ID; no cost is reported |
| `~/.omp/agent/sessions/**/*.jsonl` | omp (oh-my-pi) daily/blocks/weekly/monthly | pi-format session JSONL; every assistant `usage` event is summed (rewound branches are already billed) and subagent session files count too, since their tokens are not folded into the parent; honours `$OMP_CODING_AGENT_DIR`; per-event `cost` is trusted when reported; `bridge/` conversion copies are skipped because their originals are already counted at the source |
| Keychain / `~/.claude/.credentials.json` → `api.anthropic.com` | Claude official 5h/weekly % | unofficial endpoint; the Keychain is read **only when you press refresh** — auto-polling never reads it |
| `codex app-server` | Codex official 5h/weekly % | local child process; account snapshot only, no model turn |
| [PokéAPI](https://pokeapi.co/) — `pokeapi.co`, `graphql.pokeapi.co` | Pokémon species &amp; evolution | runtime fetch; cached locally, never bundled |
| `raw.githubusercontent.com/PokeAPI/sprites` | Pokémon &amp; item sprites | runtime fetch; cached under Application Support, never bundled |
| `status.claude.com`, `status.openai.com` | provider incident banner | statuspage summary; display only — turn it off in Settings |
| `api.github.com` | update check | latest release tag; on launch and when the popover opens |

If a provider's logs live **outside** those built-in paths, add the folder in **Settings → Advanced → Additional scan folders**. Pick the provider first — each folder is parsed only by that provider, so pointing a Gemini field at Claude logs would mis-attribute tokens. Extra folders are added to the built-in locations; they never replace them.

## Privacy & permissions

- **On-device first.** Token usage is read directly from local Claude Code, Codex, Gemini CLI, Antigravity, OpenCode, Hermes Agent, Cursor, Grok CLI, Copilot CLI, Kiro CLI, Pi Agent, and omp data. The app never uploads usage or runs model turns.
- **Outbound requests.** The app is not fully offline. It talks to twelve hosts: `pokeapi.co` and `graphql.pokeapi.co` (species/evolution), `raw.githubusercontent.com` (sprites), `api.anthropic.com` (Claude official limits), `claude.ai` (Claude official limits when you save an optional claude.ai session key in Settings — the key only, no prompts or project paths), `cursor.com` (Cursor usage summary when you are signed into Cursor locally — session credential only, no prompts or project paths), `cloudcode-pa.googleapis.com` and `daily-cloudcode-pa.googleapis.com` (Antigravity official limits) plus `oauth2.googleapis.com` (their token refresh), `status.claude.com` and `status.openai.com` (incident banner — off switch in Settings), and `api.github.com` (update check). **None of them carry your usage logs, prompts, or project paths** — only the request itself (Cursor sends your session cookie to fetch your own usage rows, same as the web dashboard).
- **Keychain (optional).** The Claude OAuth credential is read **only when you press a refresh button** (Settings, or the limits row in the popover). Automatic polling never touches the Keychain, so it never raises a password prompt; when `~/.claude/.credentials.json` is present, each poll re-reads it, so an in-place `/login` to another account is picked up without pressing refresh. The token is held in memory only — the app creates no Keychain item of its own. If there is no credentials file, limits stay on the cached token until it expires or you refresh. Turn it off in Settings — the limits section simply hides.
- **iPhone companion server (optional, off by default).** Turning it on opens an HTTP listener on port 7845 that serves your usage, limits, plan tier, and companion state. It binds every interface and advertises itself over Bonjour, because the phone reaches it across the local network — so it is protected by a **pairing code** instead. The Mac shows the code in **Settings → iPhone Connection**; enter it once on the phone. Requests without the code get `401`, and the response carries no CORS header, so a web page you visit cannot read it either. Regenerate the code any time it may have been seen.
- **Pokémon assets** are fetched at runtime from PokéAPI and cached only under `~/Library/Application Support/PokeTokenBar/`. The app binary and its release artifacts contain no Pokémon assets.

## Contributors

Contributions of all sizes are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for how to build, test, and open a pull request.

[![Contributors](https://contrib.rocks/image?repo=chattymin/PokeTokenBar)](https://github.com/chattymin/PokeTokenBar/graphs/contributors)

## License & disclaimer

**MIT** — see [LICENSE](LICENSE). The MIT license covers this project's original source code only; it grants no rights to any third-party trademarks, artwork, or data accessed through the app.

PokeTokenBar is an **unofficial, non-commercial fan project**. It is **not affiliated with, endorsed, sponsored, or approved by Nintendo, Game Freak, Creatures Inc., or The Pokémon Company.** "Pokémon" and all related names, characters, and imagery are trademarks and copyrights of their respective owners. This project claims no ownership of, and asserts no rights over, any Pokémon intellectual property.

- **The app binary and its release artifacts bundle no Pokémon assets.** Pokémon species data and sprites are fetched **at runtime** from the public [PokéAPI](https://pokeapi.co) and cached locally on the user's own device; sprite images served via PokéAPI remain the property of their respective owners.
- Any Pokémon imagery in this repository's documentation (screenshots/GIFs) is shown solely to illustrate the app's functionality.
- The app is provided free of charge for **personal, non-commercial use only.**
- If you are a rights holder with any concern about this project, please open an issue or contact the maintainer, and we will respond promptly.

*Provided "as is", without warranty of any kind. This notice is not legal advice.*
