---
summary: "Index of the Linear desk / Today / Pokédex notes that shipped on main in #6."
read_when:
  - Reviewing the fork's Linear workspace, Today desk, or session XP
---

# Linear desk, Today, and Pokédex notes

English-first write-ups for the work that landed on `main` in [#6](https://github.com/spawnaudio/spawn-PokeTokenBar/pull/6). Side-by-side app: `/Applications/PokeTokenBar v3.app` via `./scripts/rebuild-v3.sh`.

## Status

| Feature | Status |
|---|---|
| Linear Issues / Projects / Initiatives | **On `main`** (#6) |
| Pokédex continuous scroll | **On `main`** (#6) |
| Blank Settings launch window fix | **On `main`** (#6) |
| Session timer + Today breakout window | **On `main`** (#6) |
| Canvas feature map (source of the timer spec) | Exported here; decisions match the shipped UI |

## Documents

| File | What it contains |
|---|---|
| [linear-integration.md](./linear-integration.md) | Issues / Projects / Initiatives tabs, GraphQL complexity fallback, status dropdown, fold + hover, SF Symbols, two-way `issueUpdate`, XP on first completed transition |
| [pokedex-continuous-scroll.md](./pokedex-continuous-scroll.md) | Collection grid is a 4-column continuous `LazyVGrid`, not 24-cell pages |
| [launch-window.md](./launch-window.md) | Hidden `MenuBarExtra` + `LaunchWindowPolicy` so launch no longer opens a blank Settings window |
| [session-timer-today-desk.md](./session-timer-today-desk.md) | Overlay island, Focus pin, Today `NSWindow`, zero-time popup, check-ins, XP multipliers |
| [floating-timer-feature-map.md](./floating-timer-feature-map.md) | Readable export of the locked canvas (surfaces, zero-time, check-ins, desk, XP, scope) |

The product README for this fork is at the [repo root](../../README.md). Always-on engineering rules stay in [`docs/reference/`](../../docs/reference/).
