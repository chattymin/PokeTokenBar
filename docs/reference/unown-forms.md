# Unown forms

Unown (#201) has 28 collectible forms: A–Z, ! and ?. A new Unown egg chooses
its letter when the species is prepared, allowing the exact normal and shiny
sprites to be cached before hatching. If an Unown hatches without preparation,
the letter is chosen at hatch time. Other species keep their existing random
draw sequence and hatching weights.

Form selection reuses the species selector's collected-weight adjustment: each
uncollected form has weight 2 and each collected form has weight 1. Ownership
includes active and recorded Pokémon, regardless of shiny color. There is no
duplicate streak counter or guaranteed new form. Once all forms are collected,
selection is uniform again. This runs only after Unown is selected and does not
change species-selection weights or shiny odds.

The letter stays with the Pokémon through raising, graduation, release, restarts,
and save export/import. Released Pokémon remain in the Pokédex under the existing
collection rules. The main Pokédex shows a single Unown cell with a form count
out of 28. The detail page shows all 28 forms, with uncollected forms dimmed and
disabled. Selecting a collected form lists only its individuals and allows that
form to be chosen as the representative. Shiny ownership is tracked per form;
normal and shiny variants do not increase completion beyond 28.
A chosen representative keeps its letter in the menu bar and floating pet;
species information, difficulty, and repeat-hatch growth bonuses keep their
existing species-based behavior.

Saves use `unownForm` on active Pokémon and Pokédex entries, `pendingUnownForm`
on prepared eggs, and `representativeUnownForm` for the selected representative.
Values are lowercase `a`–`z`, `exclamation`, or `question`. Older Unown records
without a letter retain their former A appearance. Form fields on other species
are ignored. Species IDs and evolution paths remain unchanged.

Sprites come from the existing PokeAPI source: A uses `201.png`/`201.gif`, and
the other letters use names such as `201-b.png` or `201-question.gif`. Cache
keys distinguish the letter, shiny color, and animation format while retaining
the original A cache keys.
