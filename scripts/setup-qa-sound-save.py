#!/usr/bin/env python3
import json
import os
import sys

QA_DIR = os.path.expanduser("~/.poketokenbar-qa-sound")
os.makedirs(QA_DIR, exist_ok=True)

mode = "active"
if "--egg" in sys.argv:
    mode = "egg"
elif "--shiny-egg" in sys.argv:
    mode = "shiny-egg"

dex_entries = [
    {"baseID": 1, "finalID": 3, "chainOrder": [1, 2, 3], "rarity": "common", "isShiny": False},
    {"baseID": 4, "finalID": 6, "chainOrder": [4, 5, 6], "rarity": "common", "isShiny": False},
    {"baseID": 7, "finalID": 9, "chainOrder": [7, 8, 9], "rarity": "common", "isShiny": False},
    {"baseID": 25, "finalID": 26, "chainOrder": [25, 26], "rarity": "rare", "isShiny": False},
    {"baseID": 92, "finalID": 94, "chainOrder": [92, 93, 94], "rarity": "common", "isShiny": False},
    {"baseID": 129, "finalID": 130, "chainOrder": [129, 130], "rarity": "common", "isShiny": True},
    {"baseID": 131, "finalID": 131, "chainOrder": [131], "rarity": "rare", "isShiny": False},
    {"baseID": 132, "finalID": 132, "chainOrder": [132], "rarity": "rare", "isShiny": False},
    {"baseID": 133, "finalID": 134, "chainOrder": [133, 134], "rarity": "rare", "isShiny": False},
    {"baseID": 143, "finalID": 143, "chainOrder": [143], "rarity": "rare", "isShiny": False},
    {"baseID": 147, "finalID": 149, "chainOrder": [147, 148, 149], "rarity": "rare", "isShiny": False},
    {"baseID": 150, "finalID": 150, "chainOrder": [150], "rarity": "legendary", "isShiny": False},
    {"baseID": 151, "finalID": 151, "chainOrder": [151], "rarity": "legendary", "isShiny": True},
    {"baseID": 249, "finalID": 249, "chainOrder": [249], "rarity": "legendary", "isShiny": False},
    {"baseID": 384, "finalID": 384, "chainOrder": [384], "rarity": "legendary", "isShiny": False},
    {"baseID": 493, "finalID": 493, "chainOrder": [493], "rarity": "legendary", "isShiny": True},
    {"baseID": 644, "finalID": 644, "chainOrder": [644], "rarity": "legendary", "isShiny": False},
    {"baseID": 649, "finalID": 649, "chainOrder": [649], "rarity": "legendary", "isShiny": False},
]

mock_dex = []
for entry in dex_entries:
    mock_dex.append({
        "id": f"qa-{entry['baseID']}",
        "baseID": entry["baseID"],
        "finalID": entry["finalID"],
        "chainOrder": entry["chainOrder"],
        "rarity": entry["rarity"],
        "isShiny": entry["isShiny"],
        "caughtAt": "2026-09-22T00:00:00Z"
    })

if mode == "egg":
    mock_state = {
        "installBaselineSet": True,
        "usedSinceInstall": 50000000000,
        "spentTokens": 0,
        "eggUsage": 5000000,
        "eggTier": None,
        "pendingHatchID": 4,  # Charmander
        "lastDate": "2026-09-22",
        "active": None,
        "representativeSpeciesID": 4,
        "dex": mock_dex,
        "collectedFinals": ["1:3", "4:6", "7:9", "25:26", "92:94", "129:130", "131:131", "132:132", "143:143", "147:149", "150:150", "151:151", "249:249", "384:384", "493:493", "644:644", "649:649"],
        "language": "ko",
        "inventory": {
            "rareCandy": 10,
            "mint": 5
        }
    }
elif mode == "shiny-egg":
    mock_state = {
        "installBaselineSet": True,
        "usedSinceInstall": 50000000000,
        "spentTokens": 0,
        "eggUsage": 5000000,
        "eggTier": "legendary",
        "pendingHatchID": 151,  # Mew (shiny)
        "lastDate": "2026-09-22",
        "active": None,
        "representativeSpeciesID": 151,
        "dex": mock_dex,
        "collectedFinals": ["1:3", "4:6", "7:9", "25:26", "92:94", "129:130", "131:131", "132:132", "143:143", "147:149", "150:150", "151:151", "249:249", "384:384", "493:493", "644:644", "649:649"],
        "language": "ko",
        "inventory": {
            "rareCandy": 10,
            "mint": 5
        }
    }
else:
    # Bulbasaur with 50M XP (common stage 0 threshold is ~208M).
    # Candy 1 -> +100M (150M < 208M): Level Up jingle (.levelUp)
    # Candy 2 -> +100M (250M >= 208M): Evolution fanfare (.evolve) into Ivysaur!
    mock_state = {
        "installBaselineSet": True,
        "usedSinceInstall": 50000000000,
        "spentTokens": 0,
        "eggUsage": 0,
        "eggTier": None,
        "pendingHatchID": None,
        "lastDate": "2026-09-22",
        "active": {
            "baseID": 1,
            "pathIDs": [1],
            "plannedPathIDs": [1, 2, 3],
            "stageIndex": 0,
            "usedAtStage": 50000000,
            "rarity": "common",
            "totalForms": 3,
            "isShiny": False,
            "hasGrowthBoost": False
        },
        "representativeSpeciesID": 1,
        "dex": mock_dex,
        "collectedFinals": ["1:3", "4:6", "7:9", "25:26", "92:94", "129:130", "131:131", "132:132", "143:143", "147:149", "150:150", "151:151", "249:249", "384:384", "493:493", "644:644", "649:649"],
        "language": "ko",
        "inventory": {
            "rareCandy": 10,
            "mint": 5
        }
    }

target_file = os.path.join(QA_DIR, "companion-state.json")
with open(target_file, "w", encoding="utf-8") as f:
    json.dump(mock_state, f, indent=2, ensure_ascii=False)

print(f"Mock QA save state written to: {target_file}")
print(f"Mode: {mode}")
if mode == "active":
    print("Active: Bulbasaur (Stage 0, 50M XP). Next candy: +100M XP (Level Up). 2nd candy: Evolve into Ivysaur!")
elif mode == "egg":
    print("Active: Egg (5M/5M XP). Will hatch Charmander on launch!")
elif mode == "shiny-egg":
    print("Active: Legendary Egg (5M/5M XP). Will hatch Shiny Mew on launch!")
