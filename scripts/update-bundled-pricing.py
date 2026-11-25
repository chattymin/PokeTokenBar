#!/usr/bin/env python3
"""Refresh the offline subset of the public models.dev catalog bundled with the app."""

import json
from pathlib import Path
from urllib.request import Request, urlopen

CATALOG = "https://models.dev/api.json"
LICENSE = "https://raw.githubusercontent.com/anomalyco/models.dev/dev/LICENSE"
DESTINATION = (Path(__file__).resolve().parents[1] / "Sources" / "PokeTokenBar"
               / "Resources" / "model-prices.json")


def main():
    with urlopen(Request(CATALOG, headers={"User-Agent": "PokeTokenBar"}), timeout=30) as response:
        catalog = json.load(response)
    with urlopen(LICENSE, timeout=30) as response:
        license_text = response.read().decode().strip()

    # Keep one model per line so price and context-tier changes can be reviewed together.
    sections = ['  "_source": ' + json.dumps({"url": CATALOG, "license": license_text})]
    for provider in ("openai", "anthropic", "google"):
        rows = []
        for model, row in sorted(catalog[provider]["models"].items()):
            if not row.get("cost") or row["modalities"]["output"] != ["text"]:
                continue
            fields = {key: row[key] for key in ("id", "modalities", "cost")}
            rows.append("    " + json.dumps(model) + ": " + json.dumps(fields, sort_keys=True))
        if not rows:
            raise ValueError(f"No priced text models for {provider}")
        sections.append(f'  "{provider}": {{"id": "{provider}", "models": {{\n'
                        + ",\n".join(rows) + "\n  }}")
    DESTINATION.write_text("{\n" + ",\n".join(sections) + "\n}\n", encoding="utf-8")


if __name__ == "__main__":
    main()
