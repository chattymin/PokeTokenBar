# Mega Evolution

Mega Evolution is a selected cosmetic appearance for an owned Pokémon. It does
not change growth, graduation, stats, token accounting, or shiny odds.

## Supported forms

The catalog supports 46 Mega forms for collectible Generation I–V Pokémon
from Pokémon X/Y and Omega Ruby/Alpha Sapphire.

| Base generation | Supported Mega forms |
| --- | --- |
| I | Venusaur, Charizard X/Y, Blastoise, Beedrill, Pidgeot, Alakazam, Slowbro, Gengar, Kangaskhan, Pinsir, Gyarados, Aerodactyl, Mewtwo X/Y |
| II | Ampharos, Steelix, Scizor, Heracross, Houndoom, Tyranitar |
| III | Sceptile, Blaziken, Swampert, Gardevoir, Sableye, Mawile, Aggron, Medicham, Manectric, Sharpedo, Camerupt, Altaria, Banette, Absol, Glalie, Salamence, Metagross, Latias, Latios |
| IV | Lopunny, Garchomp, Lucario, Abomasnow, Gallade |
| V | Audino |

Rayquaza is excluded because it does not use a Mega Stone. Diancie is outside
the app's collectible generation range. Primal forms and later Mega catalogs
are outside this stone catalog.
Each form has its own permanently owned Mega Stone. Purchase each stone once;
using a stone selects its Mega form without consuming the stone or setting a time limit.

The base price is 500 million tokens per stone. The existing shop difficulty
multiplier scales the displayed price and the amount deducted from the wallet.

## Using a stone

Own the matching final-stage Pokémon, then open the Shop and select the
**Mega Stones** tab. Only eligible owned species appear in this catalog. Purchase
the desired stone to add it to the Bag.
Once its final-stage species is owned, enable Mega Evolution on that Pokémon's
Home card or collection detail page. The displayed Pokémon, menu bar, and floating
pet change immediately. Charizard and Mewtwo each have X/Y form selectors for their owned
stones. Turn the active form off to restore the Pokémon page's regular appearance and
the existing representative selection in the menu bar and floating pet.
The Bag displays owned stones and directs users to the Pokémon controls.

An owned stone can be used repeatedly at no additional cost. The selected form
remains until it is turned off, another stone is used, or another representative
is selected; there is no countdown or automatic expiry. Controls follow the normal
or shiny appearance selected on the Pokémon page. When that Pokémon is the
representative, ordinary color changes also update the menu bar and floating pet;
the explicit representative color persists across restarts.

## Behavior

- Purchase a stone using the existing token wallet and shop difficulty setting.
- Only stones for owned final-stage Pokémon are listed and can be purchased.
  Earlier evolution stages do not qualify; collection entries and the current
  final-stage companion both count as ownership.
- Activate a form only when both its stone and its base species are owned.
- A purchased stone cannot be bought again. Token cost is paid once when purchasing;
  activation never consumes a stone or charges additional tokens.
- One form may be active at a time. Activating another replaces the active form.
- The selected Mega form persists across restarts without a time limit.
- Ending Mega Evolution restores the regular representative display.
- Choosing a representative Pokémon explicitly ends the Mega appearance.
- Existing saves without Mega Evolution fields retain their current behavior.

## Assets

Mega forms use PokeAPI's Showdown animated GIFs at runtime for the menu bar,
floating pet, Home, and collection details. Normal and shiny animations use
separate paths under `pokemon/other/showdown/`. Static PNGs remain the shop and
Bag previews and provide a fallback when animation is disabled or unavailable.
The existing Generation V animation path remains unchanged for regular Pokémon.
No sprites are bundled or committed, and the underlying owned species stays unchanged.

Mega Stone item icons also come from that repository at runtime. Each catalog
entry maps to its own canonical item sprite filename.
The app uses its normal placeholder while an image is loading or unavailable.

## Contribution scope

Keep the catalog, selection rules, and shop/Bag presentation in dedicated files
where practical. This avoids expanding the evolution tree or changing the
existing alternate-form collection rules. Additional forms, gameplay bonuses,
and Mega Energy are separate future changes.
