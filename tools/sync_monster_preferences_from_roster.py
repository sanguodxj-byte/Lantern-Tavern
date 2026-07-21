#!/usr/bin/env python3
"""Sync data/monster_preferences.json from data/enemy_roster.json."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROSTER = ROOT / "data" / "enemy_roster.json"
OUT = ROOT / "data" / "monster_preferences.json"


def main() -> None:
    roster = json.loads(ROSTER.read_text(encoding="utf-8"))
    prefs = []
    for e in roster["enemies"]:
        rig = e["rig"]
        static = rig.replace("_rig.glb", ".glb")
        # Prefer static glb if present, else rig
        static_path = ROOT / "assets" / "meshes" / "characters" / static
        model = static if static_path.exists() else rig
        prefs.append(
            {
                "id": e["id"],
                "name": e["name_zh"],
                "voxel_model": f"res://assets/meshes/characters/{model}",
                "liked_flavors": ["earthy", "umami"],
                "disliked_flavors": ["sweet"],
                "drops": [e.get("drop", "goblin_ear")],
            }
        )
    OUT.write_text(json.dumps(prefs, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")
    print(f"Wrote {len(prefs)} entries -> {OUT}")


if __name__ == "__main__":
    main()
