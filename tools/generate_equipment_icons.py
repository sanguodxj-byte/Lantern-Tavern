#!/usr/bin/env python3
"""Generate equipment/material UI icons from existing voxel previews and solid fallbacks.

Weapons: resize reports/weapons_preview/voxel_<id>_front.png
         -> assets/textures/icons/equipment/weapons_<id>.png
Armor:   solid palette fallback (or preview if present)
Materials: solid palette from brewing highlight colors + optional preview crop
"""
from __future__ import annotations

import json
import os
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError as exc:
    raise SystemExit("Pillow required: pip install pillow") from exc

ROOT = Path(__file__).resolve().parents[1]
WEAPONS_JSON = ROOT / "data" / "weapons" / "weapons.json"
ICON_DIR = ROOT / "assets" / "textures" / "icons" / "equipment"
MAT_ICON_DIR = ROOT / "assets" / "textures" / "icons" / "materials"
WEAPONS_PREVIEW = ROOT / "reports" / "weapons_preview"
ARMOR_PREVIEW = ROOT / "reports" / "armor_preview"
MAT_PREVIEW = ROOT / "reports" / "materials_preview"

ICON_SIZE = 128

# Material highlight palette (matches pickable_item-ish colors)
MATERIAL_COLORS = {
    "rat_tail": (0.55, 0.35, 0.30),
    "moldy_bread": (0.55, 0.48, 0.28),
    "rusty_nail": (0.55, 0.35, 0.22),
    "dungeon_moss": (0.28, 0.48, 0.22),
    "bone_shard": (0.85, 0.80, 0.70),
    "stale_water": (0.35, 0.45, 0.55),
    "prison_lichen": (0.42, 0.48, 0.38),
    "cellar_mushroom": (0.55, 0.40, 0.32),
    "blackberry": (0.18, 0.08, 0.22),
    "glowshroom": (0.15, 0.65, 0.75),
    "moongrass": (0.45, 0.70, 0.85),
    "pixie_dust": (0.85, 0.70, 0.95),
    "poison_berry": (0.55, 0.12, 0.35),
    "deeprock_moss": (0.18, 0.32, 0.22),
    "black_rye_root": (0.28, 0.18, 0.12),
    "stalactite_sap": (0.75, 0.55, 0.25),
    "goblin_nail": (0.35, 0.45, 0.25),
    "mistflower": (0.70, 0.75, 0.90),
    "wolfear_herb": (0.40, 0.50, 0.30),
    "cyclops_beard": (0.55, 0.50, 0.40),
    "geothermal_ear": (0.70, 0.35, 0.20),
    "luminous_fern": (0.25, 0.75, 0.45),
    "quartz_dust": (0.80, 0.85, 0.90),
    "blindfish_jerky": (0.55, 0.42, 0.32),
    "goblin_ear": (0.40, 0.55, 0.28),
    "giant_rat_tail": (0.55, 0.35, 0.30),
    "skeleton_dust": (0.88, 0.88, 0.82),
    "slime_jelly": (0.20, 0.75, 0.55),
    "troll_blood": (0.70, 0.10, 0.12),
    "soul_gem": (0.45, 0.25, 0.75),
    "dragon_scale": (0.55, 0.15, 0.12),
}

ARMOR_COLORS = {
    "cloth_armor": (0.55, 0.48, 0.62),
    "leather_armor": (0.42, 0.28, 0.16),
    "chain_armor": (0.55, 0.58, 0.62),
    "plate_armor": (0.65, 0.66, 0.70),
}


def _rgba(rgb: tuple[float, float, float], a: int = 255) -> tuple[int, int, int, int]:
    return (int(rgb[0] * 255), int(rgb[1] * 255), int(rgb[2] * 255), a)


def _fit_icon(src: Image.Image, size: int = ICON_SIZE) -> Image.Image:
    """Crop non-transparent content and fit into size x size with padding."""
    img = src.convert("RGBA")
    # If mostly transparent with dark bg, keep as-is
    alpha = img.split()[-1]
    bbox = alpha.getbbox()
    if bbox is None:
        # fully transparent — use whole image
        content = img
    else:
        content = img.crop(bbox)
    # Pad square
    w, h = content.size
    side = max(w, h)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(content, ((side - w) // 2, (side - h) // 2), content)
    # Slight padding margin
    pad = int(side * 0.08)
    canvas = Image.new("RGBA", (side + pad * 2, side + pad * 2), (0, 0, 0, 0))
    canvas.paste(square, (pad, pad), square)
    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def _solid_icon(rgb: tuple[float, float, float], label: str = "") -> Image.Image:
    img = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    margin = 10
    color = _rgba(rgb)
    # rounded rect body
    draw.rounded_rectangle(
        [margin, margin, ICON_SIZE - margin, ICON_SIZE - margin],
        radius=16,
        fill=color,
        outline=(255, 255, 255, 60),
        width=2,
    )
    # highlight blob
    hl = tuple(min(255, c + 40) for c in color[:3]) + (90,)
    draw.ellipse([margin + 12, margin + 10, ICON_SIZE // 2, ICON_SIZE // 2], fill=hl)
    if label:
        # tiny label strip at bottom
        draw.rectangle([margin, ICON_SIZE - margin - 18, ICON_SIZE - margin, ICON_SIZE - margin], fill=(0, 0, 0, 100))
    return img


def _save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")


def generate_weapon_icons() -> list[str]:
    written: list[str] = []
    data = json.loads(WEAPONS_JSON.read_text(encoding="utf-8"))
    entries = list(data.get("weapons", [])) + list(data.get("armor", [])) + list(data.get("accessories", []))
    for entry in entries:
        eid = entry["id"]
        icon_rel = entry.get("icon", f"res://assets/textures/icons/equipment/weapons_{eid}.png")
        # res://... -> local
        icon_path = ROOT / icon_rel.replace("res://", "")
        category = entry.get("category", "weapons")
        glb = entry.get("glb_path", "")

        # Prefer existing front preview
        candidates = [
            WEAPONS_PREVIEW / f"voxel_{eid}_front.png",
            WEAPONS_PREVIEW / f"voxel_{eid}_preview.png",
            ARMOR_PREVIEW / f"voxel_{eid}_front.png",
            ARMOR_PREVIEW / f"armor_{eid}_front.png",
        ]
        # longsword alias for sword if needed
        if eid == "sword":
            candidates.insert(0, WEAPONS_PREVIEW / "voxel_sword_front.png")
        src_path = next((p for p in candidates if p.exists()), None)

        if src_path is not None:
            img = Image.open(src_path)
            icon = _fit_icon(img)
            _save(icon, icon_path)
            written.append(f"{eid} <- {src_path.name}")
            continue

        # armor solid fallback
        if "armor" in category or "armor" in eid:
            color = ARMOR_COLORS.get(eid, (0.5, 0.5, 0.55))
            _save(_solid_icon(color, eid), icon_path)
            written.append(f"{eid} solid armor")
            continue

        # generic solid
        _save(_solid_icon((0.55, 0.55, 0.58), eid), icon_path)
        written.append(f"{eid} solid fallback")
    return written


def generate_material_icons() -> list[str]:
    written: list[str] = []
    MAT_ICON_DIR.mkdir(parents=True, exist_ok=True)
    # From manifest if present
    manifest_path = ROOT / "data" / "material_model_manifest.json"
    ids: list[str] = list(MATERIAL_COLORS.keys())
    if manifest_path.exists():
        man = json.loads(manifest_path.read_text(encoding="utf-8"))
        for entry in man.get("materials", []):
            mid = entry.get("id")
            if mid and mid not in ids:
                ids.append(mid)

    for mid in ids:
        out = MAT_ICON_DIR / f"{mid}.png"
        # Prefer material preview if exists
        for cand in [
            MAT_PREVIEW / f"{mid}_front.png",
            MAT_PREVIEW / f"materials_{mid}_front.png",
            MAT_PREVIEW / f"voxel_{mid}_front.png",
        ]:
            if cand.exists():
                icon = _fit_icon(Image.open(cand))
                _save(icon, out)
                written.append(f"{mid} <- {cand.name}")
                break
        else:
            color = MATERIAL_COLORS.get(mid, (0.55, 0.50, 0.40))
            _save(_solid_icon(color, mid), out)
            written.append(f"{mid} solid")
    return written


def main() -> None:
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    w = generate_weapon_icons()
    m = generate_material_icons()
    print(f"Equipment icons: {len(w)}")
    for line in w:
        print("  ", line)
    print(f"Material icons: {len(m)}")
    for line in m[:8]:
        print("  ", line)
    if len(m) > 8:
        print(f"  ... +{len(m)-8} more")


if __name__ == "__main__":
    main()
