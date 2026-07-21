#!/usr/bin/env python3
"""TEMP: put all roster normal monsters into L0 only (equal weight)."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROSTER = ROOT / "data" / "enemy_roster.json"


def main() -> None:
    data = json.loads(ROSTER.read_text(encoding="utf-8"))
    bosses = list(data.get("boss_types", []))
    boss_set = set(bosses)
    normals = [e["id"] for e in data["enemies"] if e["id"] not in boss_set]
    types = {n: 10 for n in normals}
    boss = {b: 10 for b in bosses}

    data["comment"] = (
        "TEMP playtest: all normal monsters spawn only in L0 (zone 0) with equal weight. "
        "Zones 1-5 have empty normal types. Boss pool remains available."
    )
    data["zone_weights"] = {
        "0": {
            "types": types,
            "boss": boss,
            "count_per_room": 2.5,
            "hp_mult": 0.8,
            "speed_mult": 0.9,
            "dmg_mult": 0.8,
        },
        "1": {"types": {}, "boss": boss, "count_per_room": 1.0, "hp_mult": 1.0, "speed_mult": 1.0, "dmg_mult": 1.0},
        "2": {"types": {}, "boss": boss, "count_per_room": 1.0, "hp_mult": 1.2, "speed_mult": 1.1, "dmg_mult": 1.1},
        "3": {"types": {}, "boss": boss, "count_per_room": 1.0, "hp_mult": 1.4, "speed_mult": 1.15, "dmg_mult": 1.3},
        "4": {"types": {}, "boss": boss, "count_per_room": 1.0, "hp_mult": 1.8, "speed_mult": 1.25, "dmg_mult": 1.5},
        "5": {"types": {}, "boss": boss, "count_per_room": 1.0, "hp_mult": 2.2, "speed_mult": 1.3, "dmg_mult": 1.8},
    }
    ROSTER.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"L0 normals={len(types)} bosses={len(boss)}")
    print("L0 types:", ", ".join(sorted(types.keys())))
    print("L0 bosses:", ", ".join(sorted(boss.keys())))
    print(f"Wrote {ROSTER}")


if __name__ == "__main__":
    main()
