# 2.5.7 UI image provenance

These PNGs are local native renders of the production SwiftUI/AppKit views with sample data. They are not captures of a real user's usage. English uses the unsuffixed filename; Korean and Japanese use `-ko` and `-ja`. The shared Home image is English. No HTML illustration, AI-generated UI, or manual control recoloring was used.

The source commit is `cb5a1c010f06c861fab6a50b134d67322a3e99d7`. All 76 production source files were independently compared byte for byte with the source behind the reused native objects in the integration preflight build. Standalone renderers link those production objects with `@testable import PokeTokenBar`; the application's entry point is renamed, so the installed app is not launched. Production source and the release build directory were not modified.

| Files | Native content and scope | Pixels (en / ko / ja) |
|---|---|---|
| `screenshot-home.png` | Actual full `PopoverView`, including the localized recap button's current layout, four-day streak, 14-day stacked bars, provider detail, and an egg at 4.6M/5M (92%; 400K remaining) | 720 × 1208 (English) |
| `screenshot-provider-settings{,-ko,-ja}.png` | Actual mounted Settings scroll-content, cropped to the complete Tracked providers section, all 16 registered providers, and its help text. Cursor and Kiro are sample opt-outs | 720 × 1381 / 1356 / 1379 |
| `screenshot-activity-views{,-ko,-ja}.png` | Comparison board made from two actual Home mounts: summary and complete 14-day provider-stacked bars/legend, then the complete 16-week heatmap. Provider tabs/detail are intentionally omitted. These are separate display states | 720 × 662 / 621 / 621 |
| `screenshot-regional-dex{,-ko,-ja}.png` | Native component board of actual `RegionTally`, `DexBadgeMedal`, and `RarityTally`, with sample progress and selected Sinnoh chip. The board displays all five regions together; the application uses a scrollable region strip | 720 × 326 (all three) |
| `screenshot-pet-interactions{,-ko,-ja}.png` | Four separate frozen sample states: prayer particles, stroking heart, sulking back sprite, and an agent waiting bubble. Actual `FloatingPetView` is used for the latter three; prayer uses actual `PrayerEmojiFrame` at fixed flight positions, following the existing render fixture | 720 × 828 (all three) |

Activity fixtures use 2026-11-05, 1,150,000 tokens/$2.76 today and 3,220,000/$7.73 this week/month. Regional counts are Kanto 151/151, Johto 100/100 (shiny complete), Hoenn 135/135, Sinnoh 62/107, and Unova 9/156: 457 owned. Rarity totals also sum to 457. The Unown medal is an explicit sample badge. Board headings and captions are documentation chrome rather than application controls. Static pet images do not demonstrate motion or imply that prayers change XP, hatch rolls, or rarity.

The native hosts use dark appearance and 2× opaque PNG export. Settings switches remain gray in the inactive render process despite an active control environment; knob position preserves the native on/off state. No color correction was applied.

Usage, limit, status, session-key and account-discovery providers are injected fakes; usage/companion defaults and state files are temporary. No real usage logs, accounts, or keys are read. HTTP is rejected by the usage renderer. Full Home's default `SpriteStore.shared` can consult the public egg-sprite cache, so complete sprite-cache isolation is not claimed. The companion renderer uses an explicit scratch sprite directory and anonymously fetched public front/back Pikachu and egg PNGs from the PokeAPI sprite repository. Neither renderer overrides `HOME`.

Production references: `UI/SettingsView.swift:305`, `UI/PopoverView.swift:221`/`:234`/`:281`, `UI/ActivityVisualization.swift:48`, `UI/ActivityHeatmap.swift:180`, `UI/CompanionView.swift:932`/`:960`/`:992`, and `UI/FloatingPetPanel.swift:1019`/`:1156`. Existing fixture references are `GenerationDexScreenshotTests.swift` and `EggPrayerRenderTests.swift`.

Renderers and logs are retained under `/tmp/artifacts/release-usage/` and `/tmp/artifacts/release-companion/`. Source hashes are in `/tmp/artifacts/release-ui-source-manifest.json`; final PNG hashes, dimensions, and copy checks are in `/tmp/artifacts/release-ui-image-validation.json`. All 13 images were inspected individually. PNG decoding, 720px width, full opacity, nonblank content, and SHA-256 equality with the landing copies passed. The image set totals 872,487 bytes. Existing 2.5.6 images other than Home retain their prior provenance in `README-release-2.5.6.md`.
