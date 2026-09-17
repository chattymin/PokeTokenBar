# Pull Request: Celadon Casino, Mini-Games & Exportable Trainer Card

**Target upstream branch:** `chattymin:PokeTokenBar:main`  
**Source branch:** `KillianHzr:PokeTokenBar:feat/celadon-casino`  
**Direct creation link:** [Open Pull Request on GitHub](https://github.com/chattymin/PokeTokenBar/compare/main...KillianHzr:PokeTokenBar:feat/celadon-casino?expand=1)

---

## Suggested PR Title

```text
feat(casino): add Celadon Casino with slot machine, themes, and exportable Trainer Card
```

---

## PR Description (Copy & Paste below into GitHub)

## Summary

This PR adds the Celadon Casino (Game Corner) feature, complete with an industry-calibrated slot machine, exclusive Pokémon prizes, collectible app visual themes, the Star Prism item, and an exportable retro pixel-art Trainer Card with rich usage and Pokémon progression telemetry:

1. **Casino & Mini-Games Integration**:
   - Integrated inside the Shop view using a top segmented picker: `[ Shop | Casino ]`, keeping the popover navigation bar clean and compact.
   - Dedicated coin economy: exchange spendable tokens for casino coins across 6 tiered packages (50, 100, 500, 1,000, 5,000, 10,000 coins).

2. **Calibrated Slot Machine**:
   - 3-reel slot machine calibrated to real-world online casino math standards (95.8% RTP, 23.5% hit frequency):
     - Jackpot 777 (300x)
     - BAR (100x)
     - Jigglypuff (30x + Theme roll trigger)
     - Cherry (25x for 3, 7x for 2 on reels 1 & 2)
     - Pikachu (20x)
     - Poké Ball (10x)
     - Voltorb blanks (0x, authentic house edge)
   - Bet sizes: 1 coin (1 center line), 2 coins (3 horizontal lines), or 3 coins (3 horizontal + 2 diagonal lines). Multiplier selector (1x to 10x).
   - Lining up 3 Jigglypuffs triggers a weighted random lottery for unowned app themes based on rarity (Common, Uncommon, Rare, Epic, Legendary), or grants a 250-coin bonus when all themes are unlocked.

3. **Prize Corner**:
   - **Porygon (#137)** (9,999 coins): Strictly exclusive to the Casino Prize Corner; excluded from standard egg hatching in `chooseBase()` and `chooseBaseViaREST()`.
   - Other iconic prize Pokémon: Dratini (#147), Scyther (#123), Abra (#63), and Cleffa (#173). Purchasing a Pokémon safely archives the current companion into the Pokédex and hatches the new species with fresh egg progress.
   - **Star Prism (Prisme Étoilé)** (50,000 coins): Ultra-rare item used from the Bag to permanently transmute the active companion and its entire evolutionary line in the Pokédex into Shiny.

4. **App Visual Themes & Settings**:
   - 6 full app visual themes (Classic, Game Boy 1989, Celadon Neon, Team Rocket Dark, Indigo Plateau, Master Ball) tinting the popover window background and accent colors.
   - Theme switcher added under Settings with active preview and unlock counter.

5. **Exportable Retro Pixel-Art Trainer Card**:
   - Dedicated Trainer Card view accessible from the Companion header, Pokédex, and individual Pokémon detail view.
   - Pixel-art layout (332 x 206 pt) adapting dynamically to each of the 6 unlocked casino themes with custom watermarks, borders, and color palettes.
   - User can choose between the active companion or any registered Pokédex species (with shiny toggle support if the shiny variant is owned).
   - 2x3 telemetry grid displaying core usage and collection stats:
     - Lifetime tokens used
     - Today's tokens used
     - Pokédex progress (e.g. 42 / 151)
     - Graduated Pokémon count
     - Shiny count
     - Casino coins balance
   - Direct export via high-resolution retina rendering (scale 3.0): Copy Image to clipboard (`NSPasteboard`) and Save PNG (`NSSavePanel`).

6. **State Persistence & Save Transfer**:
   - `casinoCoins` and `unlockedThemes` classified under `progress` (preserved across machines).
   - `activeTheme` classified under `devicePreference` (kept local to each device).
   - Fully sanitized in `SaveTransfer.rebasedForThisDevice` and verified in unit tests.

## Type of change

- [ ] Bug fix
- [x] New feature
- [ ] Refactor / cleanup
- [ ] Documentation
- [ ] Other:

## UI changes

| Before | After |
| ------ | ----- |
| **Shop View**: Single vertical list of items and egg re-rolls with token balance header. | **Shop View**: Top segmented picker switching between `[ Shop | Casino ]`. |
| **Casino**: Non-existent. | **Casino View**: Integrated subview with coin balance, expandable coin exchange drawer, 3-reel slot machine with animated reels, payout table, and Prize Corner. |
| **Settings View**: General, Difficulty, Menu Bar, Floating Pet, Notifications, Updates, Transfer, Advanced sections. | **Settings View**: New "App Themes" section with active theme picker, accent color indicator, and unlocked count. |
| **Bag View**: Rare Candy, Mint, and Shiny Charm cards. | **Bag View**: Star Prism card with one-click transmutation action on active companion. |
| **Popover View**: System standard window background and accent tint. | **Popover View**: Dynamically tinted by active app visual theme. |
| **Trainer Card**: Non-existent. | **Trainer Card**: Retro pixel-art card with 6 casino theme variants, customizable Pokémon, stats telemetry grid, and copy/export actions. |

## Checklist

- [x] `swift build` and `./scripts/build-app.sh` pass locally
- [x] PR title and description are written in English
- [x] UI changes are described above (before/after — images optional)
- [x] No copyrighted assets, secrets, or private tooling references are committed (see [CONTRIBUTING](../CONTRIBUTING.md))
- [x] Tests were added or updated for this change
