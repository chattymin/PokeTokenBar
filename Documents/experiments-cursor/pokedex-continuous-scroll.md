---
summary: "v3 Pokédex collection grid is a continuous 4-column scroll, not 24-cell pages."
read_when:
  - Changing DexGridView, collection height, or sprite cells
---

# Pokédex continuous scroll (shipped in v3)

Collection **Pokédex** segment. Status: **shipped in v3**.

## Before

`DexGridView` was a **fixed 24-cell page** (4 columns × 6 rows). No `ScrollView` — a workaround for an old popover defect where ScrollView fitting size shrank on reopen. Page chrome (prev / `n / m` / next) sat in the footer. Empty cells were transparent placeholders so the 6-row geometry stayed even.

## After

- **4-column continuous `LazyVGrid`** of owned species only (no question-mark / silhouette cells).
- Header (rarity filters) and footer (selection + representative) stay fixed.
- The grid scrolls in the remaining height inside `CollectionView`’s fixed **520** content height — the same pattern as the catch log, so reopen no longer collapses the popover.
- Filter toggle scrolls back to `dexGridTop`.
- Cells still use **static** sprites (no per-cell GIF). Continuous scroll would make simultaneous animated thumbs too expensive; the comment was updated from “24 cells” to “continuous grid.”
- Thumb size stays 44pt.

Pager strings remain in localization but are unused by the grid.

## Key file

- `Sources/PokeTokenBar/UI/CompanionView.swift` (`DexGridView`, `DexSpeciesCell`)
