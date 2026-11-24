# PokeTokenBar

A companion game where the tokens a player spends raise Pokémon, and the Pokédex is the long-term goal.

## Language

**Completion**:
The player's progress measured in two ordered steps: first every Form Key held, then every Form Key that can be shiny held shiny.
_Avoid_: 100%, full dex

**Form Key**:
One appearance the app's form total counts: a species in one of its forms, Arceus and its Plates included, or a Battle Form.
_Avoid_: Form, entry

**Battle Form**:
A Mega Evolution, Primal Reversion or Gigantamax form won in the daily and weekly dungeons, never hatched from an egg and never shiny.
_Avoid_: Temporary form

**Egg Form Key**:
A Form Key that eggs can give: every Form Key but the Battle Forms and those only a dungeon gives at first, Arceus's among them.
_Avoid_: Hatchable form

**First Win**:
A player's first victory in a dungeon.
_Avoid_: Clear

**Dungeon Budget**:
The share of a player's tokens that Prof. Oak's advice lets dungeons take while an Egg Form Key is still missing, counted from the moment the rule applies to them. While it is spent, he advises no dungeon, whatever the Pokémon being raised. Once every Egg Form Key is held, there is no Dungeon Budget.
_Avoid_: Dungeon cap, dungeon quota

**Win Odds**:
The estimated chance that a team beats a dungeon's boss, not merely reaches it.
_Avoid_: Reach, chances

**Tokens to Completion**:
The tokens a player still has to spend to reach a step of Completion. It is the only unit used to compare strategies; a duration is only this figure divided by a player's pace, and the calendar's floor on Battle Forms is stated apart.
_Avoid_: Time to complete, years

**Useful Stat**:
A stat a Pokémon's battles read: HP, Defense, Sp. Def and Speed always, Attack if one of its attacking moves is physical, Sp. Atk if one is special. Body Press counts Defense, Foul Play counts neither, and Shedinja's HP never counts. The moves are the set the player chose, else those suggested for that dungeon.
_Avoid_: Relevant stat

**Theft**:
Items a villains' team takes from the Bag, once a day or from the loot a team brings back. The code calls it a `VillainAmbush`.
_Avoid_: Ambush

**Chase**:
The battle a player's team fights after a Theft to win the items back. Lost, the items wait in the thieves' Hideout.
_Avoid_: Defense

**Hideout**:
A villains' team's dungeon, where what it took waits behind its boss and three Pokémon. Beating its leader gives it all back, with the leader's chest.
_Avoid_: Lair

**Candy Crumb**:
What a Rare Candy's EXP thrown away at a graduation leaves behind: one per tenth of a plain candy's EXP, the remainder lost. A hundred make a Rare Candy. Not an item of the Bag.
_Avoid_: Shard, fragment
