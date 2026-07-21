#!/usr/bin/env python3
"""Compose visual QA contact sheets for equipment/material icons used by UI."""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports" / "ui_preview"
OUT.mkdir(parents=True, exist_ok=True)
EQ = ROOT / "assets" / "textures" / "icons" / "equipment"
MAT = ROOT / "assets" / "textures" / "icons" / "materials"
WEAPONS_JSON = ROOT / "data" / "weapons" / "weapons.json"

ICON = 72
PAD = 10
COLS = 6
BG = (26, 28, 33, 255)
CELL = (36, 38, 44, 255)


def load_icon(path: Path) -> Image.Image | None:
    if not path.exists():
        return None
    img = Image.open(path).convert("RGBA")
    img = img.resize((ICON, ICON), Image.Resampling.LANCZOS)
    return img


def sheet(cells: list[dict], title: str, out_name: str) -> Path:
    rows = max(1, (len(cells) + COLS - 1) // COLS)
    cell_w = ICON + PAD * 2
    cell_h = ICON + 34
    w = COLS * cell_w + PAD * 2
    h = rows * cell_h + 48
    canvas = Image.new("RGBA", (w, h), BG)
    draw = ImageDraw.Draw(canvas)
    draw.rectangle([0, 0, w, 36], fill=(42, 44, 52, 255))
    draw.text((12, 10), title, fill=(230, 230, 235, 255))
    for i, cell in enumerate(cells):
        col = i % COLS
        row = i // COLS
        x = PAD + col * cell_w
        y = 44 + row * cell_h
        draw.rounded_rectangle([x, y, x + cell_w - PAD, y + cell_h - PAD], 8, fill=CELL)
        icon = cell.get("img")
        if icon is not None:
            ix = x + (cell_w - PAD - ICON) // 2
            iy = y + 6
            canvas.paste(icon, (ix, iy), icon)
        else:
            draw.rectangle([x + 14, y + 14, x + ICON, y + ICON], fill=(140, 40, 40, 255))
        label = str(cell.get("label", ""))[:14]
        draw.text((x + 6, y + ICON + 10), label, fill=(190, 192, 198, 255))
    out = OUT / out_name
    canvas.save(out)
    print(f"wrote {out} ({len(cells)} cells)")
    return out


def main() -> None:
    data = json.loads(WEAPONS_JSON.read_text(encoding="utf-8"))
    eq_cells: list[dict] = []
    for section in ("weapons", "armor", "accessories"):
        for entry in data.get(section, []):
            eid = entry["id"]
            icon_rel = entry.get("icon", "")
            path = ROOT / icon_rel.replace("res://", "") if icon_rel else EQ / f"weapons_{eid}.png"
            if not path.exists():
                # try armor naming
                alt = EQ / f"armor_{eid}.png"
                path = alt if alt.exists() else path
            eq_cells.append({
                "label": entry.get("name_zh") or entry.get("name") or eid,
                "img": load_icon(path),
            })
    sheet(eq_cells, "Equipment Icons (registry)", "equipment_icons_sheet.png")

    mat_cells: list[dict] = []
    for p in sorted(MAT.glob("*.png")):
        mat_cells.append({"label": p.stem, "img": load_icon(p)})
    sheet(mat_cells[:18], "Material Icons (sample)", "material_icons_sheet.png")

    loot_ids = [
        ("weapons_shortsword.png", "短剑"),
        ("weapons_axe.png", "战斧"),
        ("weapons_greatsword.png", "巨剑"),
        ("weapons_shield.png", "盾"),
        ("weapons_dagger.png", "匕首"),
        ("weapons_staff.png", "法杖"),
        ("armor_plate_armor.png", "板甲"),
    ]
    loot_cells = [{"label": lab, "img": load_icon(EQ / fn)} for fn, lab in loot_ids]
    for mid in ["rat_tail", "glowshroom", "goblin_nail", "bone_shard"]:
        loot_cells.append({"label": mid, "img": load_icon(MAT / f"{mid}.png")})
    sheet(loot_cells, "Loot Grid Preview", "loot_grid_icons_sheet.png")

    # also copy a few individual icons for direct visual check
    for name in ["weapons_shortsword.png", "weapons_axe.png", "armor_plate_armor.png"]:
        src = EQ / name
        if src.exists():
            Image.open(src).save(OUT / f"sample_{name}")


if __name__ == "__main__":
    main()
