# 2.5.6 UI image provenance

These PNGs are local native renders of the production SwiftUI/AppKit views with sample Pokémon, items and usage. They are not captures of a real user's usage. English uses the unsuffixed filename; Korean and Japanese use `-ko` and `-ja`. The common Home image is English in all three READMEs.

The renderer used source commit `9ae91bd5a8060d3b5c5dd17ad00237b699323648`. Its Git tree, `b8385908ebe56e85cce9728e2c821b69ed4ae7b0`, exactly matches the final integrated source commit `2c0212b573db5c0ff1dc8479bc4eb61c4670def1` before these image/document updates.

| Files | Native content and scope | Pixels |
|---|---|---|
| `screenshot-home.png` | Actual `PopoverView`, full 604pt host; two sample service providers through the production refresh pipeline | 720 × 1208 |
| `settings{,-ko,-ja}.png` | Actual mounted Settings scroll-content, upper 535pt; General and Difficulty controls. Backup history retains its production default collapsed state below this region | 720 × 1070 |
| `screenshot-pokemon-forms{,-ko,-ja}.png` | Actual detail view, 548pt host; two Heat Rotom individuals and one Wash Rotom. The visible form counts, individual picker and default-form metadata note are production UI; lower stats continue in the scroll view | 720 × 1096 |
| `screenshot-shop{,-ko,-ja}.png` | Actual Shop component, 548pt host, with 500M sample spendable tokens; further items continue in the scroll view | 720 × 1096 |
| `screenshot-bag{,-ko,-ja}.png` | Actual Bag component, upper 285pt; three Rare Candies and two Mints. The valid Bulbasaur stage has 60M of 125M XP: one candy previews evolution with 35M carried over | 720 × 570 |
| `screenshot-difficulty{,-ko,-ja}.png` | Actual Difficulty section; default 100% values and slider-end labels | 720 × 340 |
| `screenshot-daily-trend{,-ko,-ja}.png` | Actual monthly trend component in a sample summary panel; provider-stacked bars on the fixed October axis | 720 × 460 |
| `screenshot-usage-recap{,-ko,-ja}.png` | Actual recap screen; sample current/previous weeks and graduation records | 720 × 730 |

The native hosts use dark appearance and 2× opaque PNG export. Public Rotom sprites came from PokeAPI sprite fixtures. State, Foundation home/cache paths and all service providers were isolated from user data. HTTP(S) was rejected during rendering: 18 initial and 4 supplemental public item, egg or animation requests used the production offline/static fallbacks. No usage, credentials or user cache was read.

All 22 original PNGs were inspected individually. Dimensions, nonblank content, full opacity and SHA-256 copy equality were checked; the set totals 1,824,536 bytes. The landing uses byte-identical copies of the 19 Home/gallery images; Settings images are used by the READMEs only.
