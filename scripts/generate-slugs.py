#!/usr/bin/env python3
"""Showdown pokedex → 종 번호 → 슬러그 매핑(기본 폼만). 개발 시 1회 실행해 산출물을 커밋한다."""
import json
import urllib.request

URL = "https://play.pokemonshowdown.com/data/pokedex.json"
OUT = "Sources/PokeDexBar/Resources/showdown-slugs.json"
LAST_SPECIES = 1025

req = urllib.request.Request(URL, headers={"User-Agent": "PokeDexBar-slugs/1.0"})
with urllib.request.urlopen(req, timeout=30) as response:
    dex = json.load(response)

table = {}
for slug, entry in dex.items():
    num = entry.get("num", 0)
    # 폼(메가·리전폼·거다이맥스)은 baseSpecies/forme 를 들고 있다 — 기본 폼만 남긴다.
    if num <= 0 or "forme" in entry or "baseSpecies" in entry:
        continue
    table.setdefault(num, slug)

missing = [n for n in range(1, LAST_SPECIES + 1) if n not in table]
if missing:
    raise SystemExit(f"빠진 종 {len(missing)}개: {missing[:20]}")

with open(OUT, "w") as f:
    json.dump({str(n): table[n] for n in sorted(table)}, f,
              ensure_ascii=False, separators=(",", ":"))
print(f"{len(table)} species -> {OUT}")
