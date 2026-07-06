from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "textures" / "props" / "voxel"
ATLAS_PATH = OUT_DIR / "voxel_prop_material_atlas_32px.png"
META_PATH = OUT_DIR / "voxel_prop_material_atlas_32px.json"

TILE = 32
GRID = (4, 2)
SIZE = (GRID[0] * TILE, GRID[1] * TILE)

LAYOUT = {
    "wood_mid": (0, 0),
    "wood_dark": (1, 0),
    "black_iron": (2, 0),
    "cut_stone": (3, 0),
    "wax": (0, 1),
    "flame": (1, 1),
    "bone": (2, 1),
    "red_cloth": (3, 1),
}

PAL = {
    "wood_mid": (92, 55, 31, 255),
    "wood_dark": (50, 29, 17, 255),
    "wood_light": (134, 86, 47, 255),
    "iron_dark": (30, 32, 32, 255),
    "iron_mid": (68, 72, 70, 255),
    "iron_high": (118, 120, 112, 255),
    "stone_mid": (78, 88, 88, 255),
    "stone_dark": (46, 52, 54, 255),
    "stone_light": (128, 136, 132, 255),
    "wax_mid": (174, 150, 98, 255),
    "wax_light": (218, 194, 132, 255),
    "flame_orange": (255, 110, 18, 255),
    "flame_yellow": (255, 220, 46, 255),
    "bone_mid": (158, 148, 121, 255),
    "bone_dark": (100, 94, 78, 255),
    "cloth_red": (92, 16, 20, 255),
    "cloth_high": (136, 38, 36, 255),
}


def clamp(value: int) -> int:
    return max(0, min(255, int(value)))


def shade(color: tuple[int, int, int, int], delta: int) -> tuple[int, int, int, int]:
    r, g, b, a = color
    return clamp(r + delta), clamp(g + delta), clamp(b + delta), a


def noise(x: int, y: int, salt: int = 0) -> int:
    n = (x * 37 + y * 57 + salt * 103) & 255
    n ^= (n << 3) & 255
    return (n % 9) - 4


def wood(base: tuple[int, int, int, int], salt: int) -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), base)
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            seam = x % 8 == 0
            edge = 11 if x % 8 == 1 else (-12 if x % 8 == 7 else 0)
            grain = 3 if (y + salt) % 11 in [0, 1] else 0
            px[x, y] = shade(base, (-22 if seam else edge + grain + noise(x, y, salt)))
    return image


def iron() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), PAL["iron_mid"])
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            border = x in [0, 31] or y in [0, 31]
            rivet = (x - 8) ** 2 + (y - 8) ** 2 < 9 or (x - 23) ** 2 + (y - 23) ** 2 < 9
            if border:
                px[x, y] = PAL["iron_dark"]
            elif rivet:
                px[x, y] = PAL["iron_high"]
            else:
                px[x, y] = shade(PAL["iron_mid"], noise(x, y, 8))
    return image


def stone() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), PAL["stone_mid"])
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            seam = y in [0, 16] or x in [0, 15, 31]
            if seam:
                px[x, y] = PAL["stone_dark"]
            else:
                bevel = 10 if x % 16 in [1, 2] or y % 16 in [1, 2] else (-10 if x % 16 in [14, 15] or y % 16 in [14, 15] else 0)
                px[x, y] = shade(PAL["stone_mid"], bevel + noise(x, y, 12))
    return image


def wax() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), PAL["wax_mid"])
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            drip = x in [8, 9, 20] and y > 12
            px[x, y] = shade(PAL["wax_light"] if x < 8 or drip else PAL["wax_mid"], noise(x, y, 16))
    return image


def flame() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), PAL["flame_orange"])
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            inner = abs(x - 16) + y // 2 < 23
            px[x, y] = shade(PAL["flame_yellow"] if inner else PAL["flame_orange"], noise(x, y, 20))
    return image


def bone() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), PAL["bone_mid"])
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            px[x, y] = shade(PAL["bone_mid"], noise(x, y, 24) + (-18 if x in [0, 31] or y in [0, 31] else 0))
    return image


def cloth() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), PAL["cloth_red"])
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            weave = 9 if (x + y) % 6 == 0 else (-8 if x % 5 == 0 else 0)
            px[x, y] = shade(PAL["cloth_high"] if x < 6 else PAL["cloth_red"], weave + noise(x, y, 28))
    return image


def build() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tiles = {
        "wood_mid": wood(PAL["wood_mid"], 1),
        "wood_dark": wood(PAL["wood_dark"], 2),
        "black_iron": iron(),
        "cut_stone": stone(),
        "wax": wax(),
        "flame": flame(),
        "bone": bone(),
        "red_cloth": cloth(),
    }
    atlas = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    metadata_tiles = {}
    for name, (col, row) in LAYOUT.items():
        atlas.alpha_composite(tiles[name], (col * TILE, row * TILE))
        metadata_tiles[name] = {
            "col": col,
            "row": row,
            "span": [1, 1],
            "pixel_rect": [col * TILE, row * TILE, TILE, TILE],
        }
    atlas.save(ATLAS_PATH)
    META_PATH.write_text(json.dumps({
        "image": ATLAS_PATH.name,
        "tile_px": [TILE, TILE],
        "grid": [GRID[0], GRID[1]],
        "size_px": [SIZE[0], SIZE[1]],
        "voxel_px_per_meter": 32,
        "tiles": metadata_tiles,
    }, indent=2), encoding="utf-8")


if __name__ == "__main__":
    build()
