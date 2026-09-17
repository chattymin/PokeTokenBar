# PR #317: feat(quests): add productivity quests, streaks, duplicate & group legendary achievements with passive items

## Summary

This PR introduces a complete quest and achievement progression system, productivity streaks, and 31 passive items:
1. **Productivity Streaks**: Tracks consecutive active coding days with grace periods and visual Red Chain indicators.
2. **Daily & Weekly Productivity Quests**: Scales from 10M tokens up to 3.5B tokens with automatic resets and batch claim buttons.
3. **Legendary Achievements**:
   - **Legendary Twin**: Duplicate Legendary achievement unlocking Azure Flute (quadruples legendary hatch rates).
   - **Canonical Groups**: 12 group achievements (Birds, Kanto Duo, Beasts, Tower Duo, Titans, Eon Duo, Weather Trio, Lake Guardians, Creation Trio, Swords of Justice, Forces of Nature, Tao Duo) unlocking 12 unique legendary artifacts.
4. **All 18 Type Gym Badges (Pokédex Mastery)**:
   - Catching and registering all species of any given Pokémon type across Gen 1–5 in the Pokédex unlocks that type's official Gym Badge.
   - 18 canonical Gym Badges: Boulder, Cascade, Thunder, Rainbow, Soul, Marsh, Volcano, Earth, Zephyr, Hive, Plain, Fog, Storm, Mineral, Glacier, Rising, Dark (Spikemuth), and Fairy (Valerie).
   - **Cumulative Weakness Boost Mechanic**: Earning a type badge grants a passive item in the Bag that makes Pokémon types weak to this badge appear more frequently in eggs and grow 20% faster (reducing required growth thresholds by 20% per effective badge, stacking cumulatively). For the Plain Badge (since no type is defensively weak to Normal), it boosts all Normal-type Pokémon.
5. **Fully Evolved Starter Trios & Master Achievement**:
   - Achievements for registering all 3 fully evolved starter Pokémon in your Pokédex for each generation (Gen 1–5): Kanto Starters, Johto Starters, Hoenn Starters, Sinnoh Starters, and Unova Starters.
   - Each generation trio awards that generation's evolution stone (Leaf Stone for Kanto, Fire Stone for Johto, Water Stone for Hoenn, Sun Stone for Sinnoh, Moon Stone for Unova).
   - Completing all 15 fully evolved starters unlocks the **Starter Master** milestone, awarding 5 Rare Candies and 500M tokens.
6. **Usable Elemental Evolution Stones (Type-Guaranteed Eggs)**:
   - 10 canonical evolution stones added as usable Bag items: Leaf Stone (Grass), Fire Stone (Fire), Water Stone (Water), Thunder Stone (Electric), Sun Stone (Psychic), Moon Stone (Fairy), Ice Stone (Ice), Dusk Stone (Dark), Dawn Stone (Fighting), and Shiny Stone (Dragon).
   - Awarded as hyper-rare items strictly through the First Evolution achievement (Thunder Stone) and starter trio generation achievements (Kanto Starters -> Leaf Stone, Johto Starters -> Fire Stone, Hoenn Starters -> Water Stone, Sinnoh Starters -> Sun Stone, Unova Starters -> Moon Stone).
   - Consumable active items in the Bag: using a stone consumes 1 stone, sends the current active companion to the Pokédex (as released), and gives a fresh egg guaranteed to hatch a Pokémon matching the stone's type.
   - Multi-stage safety confirmation in BagView (matching the Shop egg warning): inline confirmation modal showing the companion replacement, plus a dedicated warning prompt if the current companion is shiny to prevent accidental loss.
   - Incubating eggs display a type-colored capsule badge indicating the guaranteed type (e.g. 'Guaranteed Fire' / 'Feu garanti').
7. **Bag & Quest UI**:
   - Categorized achievement progression with rich themed banners (Starters, Legendary & Mythical, Gym Badges, Adventure & Training, Streaks & Productivity), interactive expand/collapse toggles, progress counters, unclaimed reward badges, and horizontal category filter chips.
   - Distinct sections separating active vs completed/claimed quests and achievements.
   - Batch claim buttons for quests and achievements tabs.
   - Official PokéAPI pixel-art sprites for all 31 passive items, 10 evolution stones, and badges with dynamic network fetching and local disk caching.
   - Rarity-colored border frames in captured Pokémon rows and Pokédex grid cells.
8. **Full Localization**: Complete coverage across all 7 supported languages (English, Korean, Japanese, Spanish, French, Portuguese, German).

## Type of change

- [ ] Bug fix
- [x] New feature
- [ ] Refactor / cleanup
- [x] Documentation
- [ ] Other:

## UI changes

| Before | After |
| :--- | :--- |
| Quests tab did not exist; no daily/weekly tasks, streak tracking, or lifetime Pokédex type mastery achievements. The Bag only contained consumable candies, mints, and shiny charms. | Dedicated Quests and Achievements view with daily token/streak milestones and 55 lifetime achievements (including 18 Type Gym Badges and 6 Starter Trio & Master achievements). Claimed items appear in the Bag with pixel-art sprites and atmospheric passive effects that accelerate hatching and growth. |

## Checklist

- [x] `swift build` passes locally
- [x] Release build (`./scripts/build-app.sh`) passes locally
- [x] PR title and description are written in English
- [x] UI changes are described above (before/after comparison)
- [x] No emojis in code or UI copy (standard symbols used for fallbacks)
- [x] No Hangul in UI String Literals (localized through `Localization.swift`)
- [x] Tests were added or updated for this change
