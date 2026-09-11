# Unown forms

Unown (#201) has 28 collectible forms: A–Z, ! and ?. A new Unown egg chooses
its letter when the species is prepared, allowing the exact normal and shiny
sprites to be cached before hatching. If an Unown hatches without preparation,
the letter is chosen at hatch time. Other species keep their existing random
draw sequence and hatching weights.

The letter stays with the Pokémon through raising, graduation, release, restarts,
and save export/import. Released Pokémon remain in the Pokédex under the existing
collection rules. The Pokédex shows one cell per letter, combines duplicates
of the same letter, and tracks shiny ownership separately for each letter. Its
species total still counts Unown once; the form counter shows collection
progress out of 28. A chosen representative keeps its letter in the menu bar
and floating pet. The detail page lists individuals of the selected letter;
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
