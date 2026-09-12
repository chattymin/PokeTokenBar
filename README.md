<div align="center">

<img src="assets/icon.png" width="128" alt="PokeTokenBar icon">

# PokeTokenBar — personal fork

**The original hatches Pokémon from AI tokens. This fork also grows them from Linear work and time at the desk.**

[![macOS](https://img.shields.io/badge/macOS-14%2B-0969da)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-f05138)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-3fb950)](LICENSE)

**English** · [한국어](README.ko.md) · [日本語](README.ja.md)

</div>

This is my personal fork of **[chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar)** — a macOS menu-bar companion that turns local AI-coding usage into a Pokémon you hatch, evolve, and graduate.

I did not rewrite the original product. The upstream README (English / 한국어 / 日本語) is archived under [`Documents/original-PokeTokenBar/`](Documents/original-PokeTokenBar/). This page is only what I changed, why, and how the Linear desk fits.

It is still an unofficial, non-commercial Pokémon fan project. See [License & disclaimer](#license--disclaimer).

## Design thinking

Upstream PokeTokenBar is a usage tracker you actually want to open: tokens you already spend raise a companion. That loop stays. What I wanted on top is closer to gamifying the task list than to grinding more tokens.

**Work should feed the same pet.** Completing a Linear issue, sitting with the app open, and finishing a timed focus session should move the egg and the evolution meter — not a second currency, not a separate overlay game.

**Usage stays the shop wallet.** Time-open XP, Linear completion XP, Rare Candy, and session XP all write to the growth meter (`eggUsage` / stage progress). They do **not** inflate `usedSinceInstall`. Shop prices still come from real tokens spent. Idle time cannot buy a Shiny Charm.

**The official economy is a campaign; this one is a sitting.** Hatch / evolve / shop costs sit behind a single `EconomyScale` knob (currently **1%** of upstream). The companion should move in an afternoon, not over a week of heavy CLI use. Official numbers stay in the source so merging `upstream/main` is “take their integer, keep the wrap.”

**Do not share a save with the stock app.** Side-by-side builds: **PokeTokenBar v2.0** and **v3** (`io.github.chattymin.poketokenbar.v2` / `.v3`, under `~/Library/Application Support/PokeTokenBar v2.0` and `… v3`). Homebrew/original `PokeTokenBar.app` is untouched.

**The menu bar is a remote, not a desk.** The 360px popover already had Home / Shop / Bag / Pokédex. Stretching it into a Today workspace fights that size. Locked split:

| Surface | Job | Not this surface |
|---|---|---|
| Menu-bar popover | Glance + companion + Linear browser. Pin / Focus. | Not the timer workspace |
| Floating pet + island | Always-visible identity and clock | Not Projects / Initiatives |
| Today window | Hero timer, pin list, session + check-in log | Not bag / dex / shop |

Full write-ups: [`Documents/experiments-cursor/`](Documents/experiments-cursor/).

## What's different on `main`

Merged in this repo: [#4](https://github.com/spawnaudio/spawn-PokeTokenBar/pull/4), [#3](https://github.com/spawnaudio/spawn-PokeTokenBar/pull/3), [#5](https://github.com/spawnaudio/spawn-PokeTokenBar/pull/5), [#6](https://github.com/spawnaudio/spawn-PokeTokenBar/pull/6).

### 1% companion economy, isolated v2.0 app

Hatch, evolve, and shop token costs are `EconomyScale.tokens(upstream)`. Rebuild without replacing the original install:

```bash
./scripts/rebuild-v2.sh                 # this tree → /Applications/PokeTokenBar v2.0.app
./scripts/rebuild-v2.sh --pull-upstream # merge chattymin/PokeTokenBar, then rebuild
```

Saves and the login agent do not collide with the stock app. Export/import still works if you want Pokédex progress from the original save.

### Time-open XP

While the app is open, wall-clock time between usage refreshes credits growth: **+1M XP / 10 minutes**, **144M / local day** cap. Catch-up is at most one interval, so waking from sleep does not dump hours of AFK XP. First enable / save import seeds the timestamp with **0 XP** (no backfill). Toggle lives on the **Time XP** popover tab.

### Linear completions

Optional personal Linear API key (plaintext JSON under Application Support, mode `0600` — same pattern as the claude.ai session key, not Keychain). On each usage refresh the app polls recently completed issues.

- First successful poll **seeds IDs with 0 XP** so existing Done issues do not explode the meter.
- Each **new** completed issue ID grants **+2M** growth XP (once; later Done clicks on the same ID do not pay again).
- Completions are listed in the Linear tab (in-progress first, then your completions today), priority-sorted, with a link out to Linear.

Key is validated with a viewer probe; query errors are not treated as “bad key.”

### Rare Candy as a snack

Upstream candy XP was a stage-skip. Here it is **1.5M** — in the same band as a Linear complete or a few time-open ticks. One candy can still clear a common first stage; it should not routinely force a later evolution. Shop price stays the scaled upstream 500M (5M after 1%), so purchased candy is a convenience spend and a **limit-cap grant stays the better deal**.

### Shop eggs stay on the shelf

During the egg stage, a shop egg is a reroll with nothing to reroll. Upstream hid the three egg cards, which read as “the shop doesn't sell eggs.” They stay listed with a disabled Buy button and a one-line reason. `canBuyEgg` is unchanged.

### Codex limits from ChatGPT.app

Usage still comes from `~/.codex/sessions`. Official limits spawn the `codex` CLI. If you only have the ChatGPT desktop app, the bundled CLI path is now a last-resort candidate so limits show up without a standalone install.

### Linear desk, Today, and a scrolling Pokédex (#6)

Side-by-side rebuild: `./scripts/rebuild-v3.sh` → `/Applications/PokeTokenBar v3.app` (does not replace v2.0 or the stock app). Notes: [`Documents/experiments-cursor/`](Documents/experiments-cursor/).

- **Linear workspace in the popover** — Issues (in progress / own completions today), Projects (In progress / Production), Initiatives (Active / Planned). Status dropdown is two-way `issueUpdate` (every team workflow state, not Done-only). GraphQL stays under Linear's 10k complexity cap by splitting issues from containers ([linear-integration.md](Documents/experiments-cursor/linear-integration.md)).
- **Focus + Today desk** — pin one issue; overlay island beside the pet (countdown / overtime); dedicated **Today** `NSWindow`. Closing Today does not stop the session. Zero-time holds 0:00 for 30s then auto-Continues. Check-ins (Yes / No / Skip) can `commentCreate` when you add a note ([session-timer-today-desk.md](Documents/experiments-cursor/session-timer-today-desk.md), [feature map](Documents/experiments-cursor/floating-timer-feature-map.md)).
- **Session XP** on the same time-open meter (time-open pauses during a session): on-time Done ×5, overtime with a note ×2, else ×1. Done +2M stays flat.
- **Pokédex** — continuous 4-column grid of owned species, not 24-cell pages ([pokedex-continuous-scroll.md](Documents/experiments-cursor/pokedex-continuous-scroll.md)).
- **Launch** — hidden `MenuBarExtra` so SwiftUI no longer opens a blank Settings window ([launch-window.md](Documents/experiments-cursor/launch-window.md)).

Later (deliberately out of this pass): Pomodoro cycles, desk tabs for Tasks / companion / usage. Not in scope: site blockers, calendar rails, Toggl export.

## Build

macOS 14+, Xcode / Swift 6. This fork is not the Homebrew cask — that still installs [upstream](https://github.com/chattymin/PokeTokenBar).

```bash
swift build
swift test
./scripts/rebuild-v2.sh    # isolated v2.0 app
./scripts/rebuild-v3.sh    # isolated v3 app (Linear desk + Today)
```

Linux Cloud Agent can install a Swift toolchain and edit sources; it cannot build the app (Apple frameworks). See `CLAUDE.md`.

## Privacy (fork additions)

Upstream's on-device usage reads and outbound hosts are unchanged — see the [original README](Documents/original-PokeTokenBar/README.md#privacy--permissions).

This fork adds **Linear** when you paste a personal API key: `api.linear.app` GraphQL for issues you already see in Linear (no prompts, no repo paths, no token-usage logs). The key is local, mode `0600`. Revoke it in Linear if you stop using the integration. Time-open XP is local wall-clock only.

## License & disclaimer

**MIT** — see [LICENSE](LICENSE). MIT covers this project's original source only.

This remains an **unofficial, non-commercial fan project**, not affiliated with Nintendo, Game Freak, Creatures Inc., or The Pokémon Company. Pokémon names, characters, and imagery are their trademarks. Runtime species data and sprites still come from [PokéAPI](https://pokeapi.co); they are not bundled in the app.

Upstream copyright and design belong to [chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar) and its contributors. This repository keeps their README in [`Documents/original-PokeTokenBar/`](Documents/original-PokeTokenBar/).
