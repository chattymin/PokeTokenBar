---
summary: "Collectible alternate forms (Unown letters, Rotom, Arceus, Gigantamax…): catalog, draw, Pokédex, save keys and sprite names."
read_when:
  - adding or removing a species' forms, or touching form sprites and their cache keys
  - changing how an individual's form is drawn, saved, imported or displayed
---

# Pokémon forms

Species from generations 1 to 5 with alternate forms are collectible when the
PokeAPI sprites repository has an animated GIF for every form: Black/White for
regular forms, Showdown for Gigantamax. The catalog lives in
`PokemonForm.catalog`, default form first:

| Species | Forms |
| --- | --- |
| Unown #201 | A–Z, ! and ? |
| Castform #351 | normal, sunny, rainy, snowy |
| Deoxys #386 | normal, attack, defense, speed |
| Burmy #412, Wormadam #413 | plant, sandy, trash |
| Cherrim #421 | overcast, sunshine |
| Shellos #422, Gastrodon #423 | west, east |
| Rotom #479 | normal, heat, wash, frost, fan, mow |
| Giratina #487 | altered, origin |
| Shaymin #492 | land, sky |
| Arceus #493 | the 18 types |
| Basculin #550 | red-striped, blue-striped |
| Darmanitan #555 | standard, zen |
| Deerling #585, Sawsbuck #586 | spring, summer, autumn, winter |
| Tornadus #641, Thundurus #642, Landorus #645 | incarnate, therian |
| Kyurem #646 | normal, black, white |
| Keldeo #647 | ordinary, resolute |
| Meloetta #648 | aria, pirouette |
| Genesect #649 | normal, douse, shock, burn, chill |
| Venusaur #3, Charizard #6, Blastoise #9, Butterfree #12, Pikachu #25, Meowth #52, Machamp #68, Gengar #94, Kingler #99, Lapras #131, Eevee #133, Snorlax #143, Garbodor #569 | normal, gmax (a rare factor, see [Gigantamax](#gigantamax)) |

Left out on purpose: spiky-eared Pichu and Arceus `unknown` (no animated GIF),
gender differences such as female Frillish (not forms), Mothim's cloaks (same
sprite), Mega Evolution (a separate mechanic, outside the form catalog), and
forms that only have static sprites (regional forms, cap Pikachu, white-striped
Basculin, Origin Dialga and Palkia).

## Drawing a form

The form belongs to the individual and is drawn once for the whole line, when
the egg's species is prepared (so the exact normal and shiny sprites can be
cached before hatching) or at hatch time without preparation. Cherubi, Darumaka
and Burmy eggs therefore already know which Cherrim, Darmanitan or Wormadam
they will become. Each species of the line shows the form when it has it and
its default otherwise: a sandy Burmy that evolves into Mothim keeps `sandy` on
record but looks like Mothim. Evolution paths are unchanged.

The draw reuses the species selector's collected-weight adjustment: each
uncollected form has weight 2 and each collected form has weight 1. Ownership
includes active and recorded Pokémon, regardless of shiny color. In lines where
several species show the form, it counts as collected only once every one of
them is owned in it. There is no duplicate streak counter or guaranteed new
form, and the draw does not change species weights or shiny odds. Factor forms
(Gigantamax) are the exception: they have their own odds, described below.

## Gigantamax

The 13 Gen 1–5 species with a Gigantamax form carry it as a rare trait of the
individual, like the Gigantamax Factor (`isFactor` on the catalog entry). The
line's form draw uses one random value: `roll % n == 0` gives the factor, and
otherwise `roll / n` makes the usual weighted draw among the other forms. `n`
favors what the player does not have yet, like the collection weighting: 8
(`uncollectedFactorDenominator`) while the line's Gigantamax form is not
collected, 16 (`collectedFactorDenominator`) once it is. "Collected" is the same
line notion as the regular draw (`collectedLineForms`: active or recorded, any
shiny color). Both odds are rarer than a regular form and more common than a
shiny (1/64).

The trait is drawn for the whole line at its hatch base, the species PokéAPI
lists without `evolves_from`: a Gigantamax Charmander and Charmeleon look as
usual and the Charizard they become shows the Gigantamax form. Pichu eggs carry
it for Pikachu (Raichu has a single look), Munchlax eggs for Snorlax, and
Meowth, Lapras and Eevee hatch as themselves; Eevee's evolutions look as usual.

Gen V has no Gigantamax animation, so its GIFs come from Showdown
(`AnimatedSource.showdown`): `other/showdown/<variety id>.gif`, with `shiny/`,
`back/` and `back/shiny/` beside it. Venusaur (10195) and Blastoise (10197)
have no back GIF; the 404 back-to-front fallback shows their front. Showdown
GIFs are rendered models of up to about 216×211 px and 100–144 frames (around
0.6–0.85 MB each, against about 80 KB for a Black/White GIF). Every sprite view
aspect-fits the image to its box, so they draw at the same size as other
Pokémon; nothing assumes a 96 px canvas.

PokéAPI only names Gigantamax forms in English, Japanese, French and German, so
the app labels them itself ("거다이맥스의 모습", "Gigantamax Form") and does not
fetch them. These species' usual looks have no PokéAPI name at all and use the
localized "Normal Form".

## Pokédex

The main Pokédex shows one cell per species with a form count (`3/4`). The
detail page lists every form, with uncollected ones dimmed and disabled.
Selecting a collected form lists only its individuals and allows that form to
be chosen as the representative, which then keeps its form in the menu bar and
floating pet. Shiny ownership is tracked per form; normal and shiny variants do
not increase completion.

Labels come from PokéAPI `pokemon-form` `form_names` (30-day cache), with the
identifier shown until they load. Unown shows its letter. Castform, Rotom,
Kyurem, Genesect and the Gigantamax species have no official name for their
usual look, so it is shown as the app's localized "Normal Form". Gigantamax uses
an app-localized label (`AppLabel`). The companion's title, the form picker
and the hatch, evolution and graduation messages add a `[form]` suffix to
non-default forms. Labels one thumbnail wide (capture log, recap chips) only
keep Unown's letter; their sprite already shows the form. Names are loaded with
the egg's sprites, when the raised Pokémon's line loads, and by the views that
show them.

Forms change appearance, names and collection slots. Types, stats, abilities,
height, weight and moves continue to use the species' default-form data. When
these details are loaded for a non-default form, Home and the Pokédex show a
localized "Data uses the default form" note beside the type badges. The note
also applies to the remaining detail sections; selecting a form does not reroll
the individual's profile or fetch separate battle metadata.

## Saves

Saves use `form` on active Pokémon and Pokédex entries, `pendingForm` on
prepared eggs, and `representativeForm` for the selected representative. Values
are PokeAPI form identifiers (`sky`, `blue-striped`, `exclamation`…). The former
Unown keys `unownForm`, `pendingUnownForm` and `representativeUnownForm` are
still read. A form that does not belong to the line falls back to its default,
so older Unown records without a letter keep their A appearance.

Downgrading loses forms: older versions only read the former Unown keys, so
their Unown individuals fall back to A and other forms are dropped when they
save.

## Sprites

Animated GIFs and cache keys use `<id>-<form>` (`492-sky.gif`,
`201-question.gif`), and the default form keeps the plain `<id>` names. Static
PNGs use the PokeAPI Pokémon ID for forms that are separate Pokémon
(`10006.png` for Sky Shaymin) and `<id>-<form>` for cosmetic forms
(`412-sandy.png`). Gigantamax GIFs are the exception: Showdown names them by the
Pokémon ID (`other/showdown/10196.gif`), while their cache keys keep the
`<id>-<form>` form (`6-gmax-sha`).
