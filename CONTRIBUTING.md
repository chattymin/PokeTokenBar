# Contributing to PokeTokenBar

Thanks for your interest in contributing! PokeTokenBar is a small, non-commercial
fan project, and contributions of all sizes are welcome — bug reports, fixes,
new usage providers, translations, and documentation.

Please read the short sections below before opening a pull request.

## Prerequisites

- **macOS 14 (Sonoma) or newer**
- **Swift 6 toolchain** (Xcode 16 or newer) — required by `Package.swift`
  (`swift-tools-version: 6.0`)

## Build & test

The project is a Swift Package. From the repository root:

```bash
swift build      # compile the app target
swift test       # run the full test suite
```

CI runs `swift build` and `swift test` on every pull request; please make sure
both pass locally first.

## Contribution workflow

1. Create a feature branch off `main` (fork the repo if you don't have write
   access).
2. Make your change with tests. Keep the change focused.
3. Open a pull request against `main`.
4. Once CI passes and the change is reviewed, it is merged via **squash merge**.

### Language: English first

This repository uses **English as its first language** for collaboration
artifacts:

- **Pull request titles and bodies must be in English.**
- **Commit messages should be in English.**

Because the repository squash-merges, the PR title becomes the commit subject on
`main`, so English PRs keep the public history consistent.

### Commit & PR conventions

- Use [Conventional Commits](https://www.conventionalcommits.org/) style:
  `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`, etc.
- Fill out the pull request template.
- **UI changes** (anything under `Sources/PokeTokenBar/UI/`) should describe the
  before/after in the PR. Screenshots or GIFs are welcome but optional — a clear
  text description is fine. The canonical `assets/` screenshots are regenerated
  at release, not per PR.

## Code conventions

The app is provider-agnostic by design. When extending it, follow these rules
(they are also enforced by tests):

- **Adding a usage source** (a new AI CLI) = implement the `UsageProvider`
  protocol (`Sources/PokeTokenBar/Core/UsageProvider.swift`) in one new type and
  register it in the default `providers:` array of `UsageStore.init`
  (`Sources/PokeTokenBar/Core/UsageStore.swift`). Those are the only two places
  you should need to touch.
- **Generic behavior must aggregate across all providers** (today/week/month
  totals, burn tier, companion rhythm). Do not attach a generic calculation to a
  single provider, and do not add `providerID == "..."` literal branches on
  generic paths. Provider-specific behavior (e.g. official limits) is the only
  thing that may branch on `providerID`.
- **Adding a version manager / install path** = add it to
  `BinaryLocator.commonToolDirectories()` — the single source that discovery and
  child-process `PATH` both share.

## Legal / intellectual property

PokeTokenBar is an **unofficial, non-commercial fan project** and is not
affiliated with Nintendo, Game Freak, Creatures Inc., or The Pokémon Company
(see the disclaimer in the [README](README.md#license--disclaimer)). To keep the
project safe to maintain and distribute, contributions **must** follow these
rules:

- **Do not commit or bundle any Pokémon (or other third-party) copyrighted
  assets** — sprites, artwork, audio, fonts, or bulk name/data files. Pokémon
  species data and sprites are fetched **at runtime** from the public
  [PokéAPI](https://pokeapi.co) and cached locally on the user's device; keep it
  that way.
- **Do not add features intended for commercial use**, or features that
  redistribute or export copyrighted assets.
- **Do not commit secrets, credentials, or references to private/internal
  tooling.** Keep everything in the repository generic and public-safe.
- By submitting a contribution, you confirm it is your **own original work** and
  agree that it is licensed under this project's [MIT License](LICENSE). The MIT
  license covers this project's source code only — it does not grant any rights
  to third-party trademarks, artwork, or data.

## Reporting bugs & requesting features

Please use the issue templates. For bugs, include your macOS version, the app
version, which AI CLI(s) you use, and steps to reproduce.

If you are a rights holder with a concern about this project, please open an
issue or contact the maintainer, and we will respond promptly.
