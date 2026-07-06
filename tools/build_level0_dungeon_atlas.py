from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "textures" / "terrain" / "level0_dungeon"
SOURCE_DIR = OUT_DIR / "source_tiles"
PREVIEW_DIR = ROOT / "reports" / "materials_preview" / "level0_dungeon"

TILE = 32
GRID = (8, 4)
ATLAS_SIZE = (GRID[0] * TILE, GRID[1] * TILE)

PALETTE = {
    "mortar_dark": (28, 31, 33, 255),
    "mortar": (43, 47, 49, 255),
    "stone_dark": (52, 58, 61, 255),
    "stone_mid": (82, 91, 94, 255),
    "stone_light": (111, 121, 122, 255),
    "stone_high": (148, 153, 150, 255),
    "wood_dark": (66, 43, 31, 255),
    "wood_mid": (104, 69, 43, 255),
    "wood_light": (148, 100, 58, 255),
    "iron_dark": (27, 29, 31, 255),
    "iron_mid": (78, 82, 82, 255),
    "iron_light": (130, 132, 126, 255),
    "void_purple": (45, 24, 76, 255),
    "bone_dark": (96, 92, 82, 255),
    "bone_mid": (154, 145, 123, 255),
    "bone_light": (194, 184, 154, 255),
    "moss": (47, 82, 54, 180),
    "grime": (22, 20, 18, 120),
    "blood": (82, 18, 20, 150),
}


def clamp(value: int) -> int:
    return max(0, min(255, int(value)))


def shade(color: tuple[int, int, int, int], delta: int) -> tuple[int, int, int, int]:
    r, g, b, a = color
    return (clamp(r + delta), clamp(g + delta), clamp(b + delta), a)


def noise(x: int, y: int, salt: int = 0) -> int:
    n = (x * 37 + y * 57 + salt * 101) & 255
    n ^= (n << 3) & 255
    return (n % 9) - 4


def save_tile(name: str, image: Image.Image) -> None:
    image.save(SOURCE_DIR / f"{name}.png")


def make_wall_stone_brick() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), PALETTE["stone_mid"])
    px = image.load()
    for y in range(TILE):
        row = y // 8
        inrow = y % 8
        offset = 0 if row % 2 == 0 else 8
        for x in range(TILE):
            local_x = (x - offset) % 16
            horizontal = inrow == 0
            vertical = local_x == 0 and inrow != 0
            if horizontal or vertical:
                px[x, y] = PALETTE["mortar_dark"] if horizontal and vertical else PALETTE["mortar"]
                continue
            brick = ((x if x >= offset else x + TILE) - offset - 1) // 16
            edge = 0
            if inrow == 1:
                edge += 17
            if local_x == 1:
                edge += 12
            if inrow == 7:
                edge -= 20
            if local_x == 15:
                edge -= 15
            brick_shift = [-5, 1, -2, 4][(row + brick) % 4]
            px[x, y] = shade(PALETTE["stone_mid"], brick_shift + edge + noise(local_x, inrow, row))
    return image


def make_floor_rough_stone() -> Image.Image:
	image = Image.new("RGBA", (TILE, TILE), PALETTE["stone_mid"])
	px = image.load()
	centers = [(5, 5), (16, 4), (27, 8), (8, 17), (21, 16), (6, 28), (18, 27), (29, 25)]
	cell_ids: list[list[int]] = []
	for y in range(TILE):
		row: list[int] = []
		for x in range(TILE):
			row.append(_nearest_periodic_center_index(x, y, centers))
		cell_ids.append(row)

	for y in range(TILE):
		for x in range(TILE):
			cell = cell_ids[y][x]
			boundary = (
				cell_ids[y][(x + 1) % TILE] != cell
				or cell_ids[(y + 1) % TILE][x] != cell
				or cell_ids[y][(x - 1) % TILE] != cell
				or cell_ids[(y - 1) % TILE][x] != cell
			)
			if boundary:
				px[x, y] = PALETTE["mortar_dark"]
				continue

			cx, cy = centers[cell]
			dx = _periodic_delta(x, cx)
			dy = _periodic_delta(y, cy)
			distance = abs(dx) + abs(dy)
			base_shift = [-8, 4, -2, 7, -5, 2, 5, -3][cell % 8]
			bevel = 0
			if dx < -1 or dy < -1:
				bevel += 10
			if dx > 2 or dy > 2:
				bevel -= 10
			if distance < 5:
				bevel += 4
			px[x, y] = shade(PALETTE["stone_mid"], base_shift + bevel + noise(x, y, cell))

	for y in range(2, TILE - 2):
		for x in range(2, TILE - 2):
			if px[x, y] == PALETTE["mortar_dark"]:
				continue
			if (x * 13 + y * 17) % 71 == 0:
				px[x, y] = shade(px[x, y], -16)
				px[x - 1, y - 1] = shade(px[x - 1, y - 1], 8)
			elif (x * 7 + y * 11) % 89 == 0:
				px[x, y] = shade(px[x, y], 10)

	for y in range(TILE):
		edge = _average_color(px[0, y], px[TILE - 1, y])
		px[0, y] = edge
		px[TILE - 1, y] = edge
	for x in range(TILE):
		edge = _average_color(px[x, 0], px[x, TILE - 1])
		px[x, 0] = edge
		px[x, TILE - 1] = edge
	return image


def _nearest_periodic_center_index(x: int, y: int, centers: list[tuple[int, int]]) -> int:
	best_idx = 0
	best_dist = 10_000
	for i, center in enumerate(centers):
		dx = _periodic_delta(x, center[0])
		dy = _periodic_delta(y, center[1])
		dist = dx * dx + dy * dy + noise(x + i, y - i, i)
		if dist < best_dist:
			best_dist = dist
			best_idx = i
	return best_idx


def _periodic_delta(value: int, center: int) -> int:
	delta = value - center
	if delta > TILE / 2:
		delta -= TILE
	elif delta < -TILE / 2:
		delta += TILE
	return delta


def _draw_polyline(px, points: list[tuple[int, int]], color: tuple[int, int, int, int]) -> None:
	for start, end in zip(points, points[1:]):
		_draw_line(px, start[0], start[1], end[0], end[1], color)


def _draw_line(px, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int, int]) -> None:
	dx = abs(x1 - x0)
	dy = -abs(y1 - y0)
	sx = 1 if x0 < x1 else -1
	sy = 1 if y0 < y1 else -1
	err = dx + dy
	x = x0
	y = y0
	while True:
		if 0 <= x < TILE and 0 <= y < TILE:
			px[x, y] = color
		if x == x1 and y == y1:
			break
		e2 = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


def _average_color(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
	return (
		int((a[0] + b[0]) / 2),
		int((a[1] + b[1]) / 2),
		int((a[2] + b[2]) / 2),
		int((a[3] + b[3]) / 2),
	)


def make_ceiling_stone_slab() -> Image.Image:
    image = make_wall_stone_brick()
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            r, g, b, a = px[x, y]
            px[x, y] = (clamp(r - 16), clamp(g - 17), clamp(b - 14), a)
    return image


def make_lintel_cut_stone() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), PALETTE["stone_mid"])
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            if y in (0, 31):
                px[x, y] = PALETTE["mortar_dark"]
            elif y in (1, 2):
                px[x, y] = shade(PALETTE["stone_light"], noise(x, y, 3))
            elif y in (29, 30):
                px[x, y] = shade(PALETTE["stone_dark"], noise(x, y, 4))
            else:
                groove = -12 if x % 8 == 0 else 0
                px[x, y] = shade(PALETTE["stone_mid"], groove + noise(x, y, 5))
    return image


def make_pillar_stone_side() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), PALETTE["stone_mid"])
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            band = -16 if x in (0, 15, 16, 31) else 0
            highlight = 14 if x in (3, 18) else 0
            shadow = -10 if x in (12, 27) else 0
            px[x, y] = shade(PALETTE["stone_mid"], band + highlight + shadow + noise(x, y, 7))
    return image


def make_door_oak_iron() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE * 2), PALETTE["wood_dark"])
    px = image.load()
    for y in range(TILE * 2):
        for x in range(TILE):
            plank = x // 8
            groove = -28 if x % 8 == 0 else (-10 if x % 8 == 1 else 0)
            top_light = 9 if y in (1, 2) else 0
            bottom_shadow = -18 if y in (61, 62, 63) else 0
            side_shadow = -12 if x in (0, 1, 30, 31) else 0
            grain = -8 if (x * 5 + y * 3 + plank) % 13 == 0 else 0
            vertical_wear = -5 if y > 42 and x % 8 in (3, 4) else 0
            px[x, y] = shade(
                PALETTE["wood_dark"],
                [-8, 2, -3, 5][plank % 4]
                + groove
                + top_light
                + bottom_shadow
                + side_shadow
                + grain
                + vertical_wear
                + noise(x, y, plank),
            )

    # Thin iron perimeter: enough structure without turning the texture into a frame icon.
    for x in range(TILE):
        px[x, 0] = PALETTE["iron_dark"]
        px[x, 63] = PALETTE["iron_dark"]
    for y in range(TILE * 2):
        px[0, y] = PALETTE["iron_dark"]
        px[31, y] = PALETTE["iron_dark"]

    # Two heavy horizontal straps with rivets, common on medieval dungeon doors.
    for band_y in (15, 45):
        for yy in range(band_y, band_y + 3):
            for x in range(2, TILE - 2):
                px[x, yy] = PALETTE["iron_mid"] if yy == band_y + 1 else PALETTE["iron_dark"]
        for x in (7, 15, 23):
            _draw_rivet(px, x, band_y + 1)

    # Left hinge plates, small and functional.
    for plate_y in (10, 40):
        for yy in range(plate_y, plate_y + 7):
            for xx in range(2, 12):
                border = xx in (2, 11) or yy in (plate_y, plate_y + 6)
                px[xx, yy] = PALETTE["iron_dark"] if border else shade(PALETTE["iron_mid"], -16)
        px[5, plate_y + 3] = PALETTE["iron_light"]
        px[8, plate_y + 3] = PALETTE["iron_dark"]

    # Compact lock plate on the right side. Keep it understated at 32x64.
    for yy in range(28, 37):
        for xx in range(22, 28):
            border = xx in (22, 27) or yy in (28, 36)
            px[xx, yy] = PALETTE["iron_dark"] if border else shade(PALETTE["iron_mid"], -18 + noise(xx, yy, 13))
    px[23, 29] = PALETTE["iron_light"]
    px[24, 29] = PALETTE["iron_light"]
    for x, y in [(24, 32), (24, 33), (23, 33)]:
        px[x, y] = PALETTE["iron_dark"]
    return image


def make_boss_skull_double_door() -> Image.Image:
    image = Image.new("RGBA", (TILE * 2, TILE * 2), PALETTE["wood_dark"])
    px = image.load()
    width = TILE * 2
    height = TILE * 2

    for y in range(height):
        for x in range(width):
            half = 0 if x < TILE else 1
            local_x = x if half == 0 else x - TILE
            plank = local_x // 8
            groove = -28 if local_x % 8 == 0 else (-10 if local_x % 8 == 1 else 0)
            top_light = 9 if y in (1, 2) else 0
            bottom_shadow = -18 if y in (height - 3, height - 2, height - 1) else 0
            edge_shadow = -14 if x in (0, 1, width - 2, width - 1, 31, 32) else 0
            grain = -8 if (x * 5 + y * 3 + plank) % 13 == 0 else 0
            px[x, y] = shade(
                PALETTE["wood_dark"],
                [-8, 2, -3, 5][plank % 4] + groove + top_light + bottom_shadow + edge_shadow + grain + noise(x, y, plank + half * 7),
            )

    # Heavy perimeter and meeting edge for double doors opening from the center.
    for x in range(width):
        px[x, 0] = PALETTE["iron_dark"]
        px[x, height - 1] = PALETTE["iron_dark"]
    for y in range(height):
        px[0, y] = PALETTE["iron_dark"]
        px[width - 1, y] = PALETTE["iron_dark"]
        px[31, y] = PALETTE["iron_dark"]
        px[32, y] = PALETTE["iron_dark"]
        if y % 4 == 0:
            px[30, y] = PALETTE["iron_mid"]
            px[33, y] = PALETTE["iron_mid"]

    # Iron straps are split per door leaf so the center seam remains readable.
    for band_y in (12, 47):
        for yy in range(band_y, band_y + 4):
            for x in range(2, 30):
                px[x, yy] = PALETTE["iron_mid"] if yy in (band_y + 1, band_y + 2) else PALETTE["iron_dark"]
            for x in range(34, 62):
                px[x, yy] = PALETTE["iron_mid"] if yy in (band_y + 1, band_y + 2) else PALETTE["iron_dark"]
        for x in (7, 15, 23, 39, 47, 55):
            _draw_rivet(px, x, band_y + 2)

    # Outer hinge plates.
    for plate_y in (9, 44):
        for yy in range(plate_y, plate_y + 10):
            for xx in range(3, 11):
                border = xx in (3, 10) or yy in (plate_y, plate_y + 9)
                px[xx, yy] = PALETTE["iron_dark"] if border else shade(PALETTE["iron_mid"], -14)
            for xx in range(53, 61):
                border = xx in (53, 60) or yy in (plate_y, plate_y + 9)
                px[xx, yy] = PALETTE["iron_dark"] if border else shade(PALETTE["iron_mid"], -14)
        _draw_rivet(px, 6, plate_y + 5)
        _draw_rivet(px, 57, plate_y + 5)

    # Subtle center handles below the skull.
    for yy in range(36, 42):
        px[28, yy] = PALETTE["iron_mid"]
        px[35, yy] = PALETTE["iron_mid"]
    for x, y in [(27, 38), (29, 38), (34, 38), (36, 38)]:
        px[x, y] = PALETTE["iron_dark"]

    _draw_skull_mark(px, 32, 26)
    return image


def _draw_skull_mark(px, cx: int, cy: int) -> None:
    axis_left = cx - 1
    top = cy - 15
    fill = shade(PALETTE["iron_mid"], -12)
    shadow = PALETTE["iron_dark"]
    highlight = shade(PALETTE["iron_mid"], -2)

    # The boss mark is an opaque iron applique, not a texture baked into the wood.
    # Every pixel in the mask overwrites the door below, while the center split stays intact.
    skull_rows = [
        [5, 6, 7],
        [3, 4, 5, 6, 7, 8],
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
        [0, 1, 2, 3, 4, 5, 6, 9, 10, 11],
        [0, 1, 2, 3, 4, 5, 6, 9, 10, 11],
        [0, 1, 2, 3, 4, 5, 6, 9, 10],
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        [1, 2, 3, 4, 5, 6, 7, 8, 9],
        [1, 2, 3, 4, 5, 6, 7, 8],
        [2, 3, 4, 5, 6, 7],
        [2, 3, 4, 5, 6, 7],
        [2, 3, 4, 5, 6],
        [2, 3, 4, 5, 6],
        [2, 3, 4, 6],
        [2, 3, 4, 6],
        [3, 4, 6],
        [3, 4],
        [3, 4],
    ]
    mask_pixels: set[tuple[int, int]] = set()
    for row, offsets in enumerate(skull_rows):
        y = top + row
        for offset in offsets:
            left_x = axis_left - offset
            right_x = axis_left + 1 + offset
            mask_pixels.add((left_x, y))
            mask_pixels.add((right_x, y))

    for x, y in mask_pixels:
        px[x, y] = fill

    outline_pixels: set[tuple[int, int]] = set()
    for x, y in mask_pixels:
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if (nx, ny) not in mask_pixels:
                outline_pixels.add((x, y))
                break
    for x, y in outline_pixels:
        px[x, y] = shadow

    for offset, y in [
        (5, top),
        (6, top + 1),
        (7, top + 2),
        (8, top + 3),
        (9, top + 4),
        (10, top + 5),
        (11, top + 5),
        (8, top + 10),
        (6, top + 12),
    ]:
        _set_mirrored_pair(px, axis_left, offset, y, highlight)

    for row in range(top + 6, top + 9):
        for offset in (4, 5, 6):
            _set_mirrored_pair(px, axis_left, offset, row, PALETTE["void_purple"])
    for offset in (5, 6):
        _set_mirrored_pair(px, axis_left, offset, top + 7, shade(PALETTE["void_purple"], -18))

    for offset, y in [
        (0, top + 10),
        (1, top + 10),
        (0, top + 11),
        (1, top + 11),
        (0, top + 12),
        (3, top + 14),
        (5, top + 14),
        (3, top + 15),
        (5, top + 15),
    ]:
        _set_mirrored_pair(px, axis_left, offset, y, shadow)
    for y in range(top, top + len(skull_rows)):
        px[31, y] = shadow
        px[32, y] = shadow


def _set_mirrored_pair(px, axis_left: int, offset: int, y: int, color: tuple[int, int, int, int]) -> None:
    left_x = axis_left - offset
    right_x = axis_left + 1 + offset
    if 0 <= y < TILE * 2:
        if 0 <= left_x < TILE * 2:
            px[left_x, y] = color
        if 0 <= right_x < TILE * 2:
            px[right_x, y] = color


def _draw_rivet(px, cx: int, cy: int) -> None:
    px[cx, cy] = PALETTE["iron_light"]
    for x, y in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]:
        if 0 <= x < TILE * 2 and 0 <= y < TILE * 2:
            px[x, y] = PALETTE["iron_dark"]


def make_portal_rune() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), (35, 28, 55, 255))
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            dx = x - 15.5
            dy = y - 15.5
            dist = (dx * dx + dy * dy) ** 0.5
            glow = max(0, 42 - int(dist * 3))
            px[x, y] = (clamp(35 + glow), clamp(28 + glow // 2), clamp(55 + glow * 2), 255)
            if 10 < dist < 12 and (x + y) % 3 != 0:
                px[x, y] = (112, 84, 180, 255)
    return image


def make_iron_grate() -> Image.Image:
    image = make_floor_rough_stone()
    px = image.load()
    for x in range(4, TILE, 7):
        for y in range(TILE):
            px[x, y] = PALETTE["iron_dark"]
            if x + 1 < TILE:
                px[x + 1, y] = PALETTE["iron_light"] if y % 6 == 0 else PALETTE["iron_mid"]
    for y in (8, 23):
        for x in range(TILE):
            px[x, y] = PALETTE["iron_dark"]
            px[x, y + 1] = PALETTE["iron_mid"]
    return image


def make_door_edge_side() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), PALETTE["wood_dark"])
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            grain = -10 if (x * 7 + y * 5) % 11 == 0 else 0
            vertical_shadow = -16 if x in (0, 31) else 0
            iron_banding = -30 if y in (7, 8, 23, 24) else 0
            px[x, y] = shade(PALETTE["wood_dark"], grain + vertical_shadow + iron_banding + noise(x, y, 17))
    return image


def make_door_edge_top() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), PALETTE["wood_dark"])
    px = image.load()
    for y in range(TILE):
        for x in range(TILE):
            rim_shadow = -22 if y in (0, 31) else 0
            saw_grain = -8 if (x * 9 + y * 3) % 13 == 0 else 0
            iron_cap = -35 if x in (0, 1, 30, 31) else 0
            px[x, y] = shade(PALETTE["wood_dark"], rim_shadow + saw_grain + iron_cap + noise(x, y, 19))
    return image


def make_overlay(kind: str) -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    px = image.load()
    if kind == "cracks":
        lines = [
            [(5, 8), (6, 8), (7, 9), (7, 10)],
            [(20, 5), (21, 6), (22, 7)],
            [(12, 22), (13, 22), (14, 23), (15, 23)],
        ]
        for line in lines:
            for x, y in line:
                px[x, y] = (24, 27, 29, 190)
    elif kind == "moss":
        for y in range(TILE):
            for x in range(TILE):
                edge = min(x, y, TILE - 1 - x, TILE - 1 - y)
                if edge < 3 and (x * 5 + y * 7) % 4 != 0:
                    px[x, y] = PALETTE["moss"]
    elif kind == "grime":
        for y in range(TILE):
            for x in range(TILE):
                if (x - 16) * (x - 16) + (y - 18) * (y - 18) < 86 and (x + y) % 3 != 0:
                    px[x, y] = PALETTE["grime"]
    elif kind == "blood":
        for y in range(TILE):
            for x in range(TILE):
                if (x - 12) * (x - 12) + (y - 20) * (y - 20) < 32 or (x - 20) * (x - 20) + (y - 13) * (y - 13) < 18:
                    px[x, y] = PALETTE["blood"]
    elif kind == "torch_scorch":
        for y in range(TILE):
            for x in range(TILE):
                dx = x - 16
                dy = y - 8
                if dx * dx + dy * dy < 110 and y < 22 and (x + y) % 2 == 0:
                    px[x, y] = (20, 18, 15, 120)
    return image


def make_rubble() -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    px = image.load()
    chunks = [(6, 22, 4, 3), (13, 18, 5, 4), (22, 24, 6, 3), (24, 15, 3, 3), (9, 11, 3, 2)]
    for cx, cy, w, h in chunks:
        for y in range(cy, cy + h):
            for x in range(cx, cx + w):
                if 0 <= x < TILE and 0 <= y < TILE:
                    delta = 18 if y == cy or x == cx else (-16 if y == cy + h - 1 or x == cx + w - 1 else 0)
                    px[x, y] = shade(PALETTE["stone_mid"], delta + noise(x, y, 9))
    return image


def compose_preview(base: Image.Image, overlay: Image.Image) -> Image.Image:
    result = base.copy()
    result.alpha_composite(overlay)
    return result


def save_previews(tiles: dict[str, Image.Image], atlas: Image.Image) -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    atlas.resize((ATLAS_SIZE[0] * 2, ATLAS_SIZE[1] * 2), Image.Resampling.NEAREST).save(PREVIEW_DIR / "level0_dungeon_terrain_atlas_preview.png")
    for name in ("wall_stone_brick", "floor_rough_stone", "door_oak_iron", "boss_skull_double_door"):
        scale = 8 if tiles[name].width == TILE else 4
        tiles[name].resize((tiles[name].width * scale, tiles[name].height * scale), Image.Resampling.NEAREST).save(PREVIEW_DIR / f"{name}_preview.png")
    tiled_floor = Image.new("RGBA", (TILE * 8, TILE * 8), (0, 0, 0, 0))
    for ty in range(8):
        for tx in range(8):
            tiled_floor.alpha_composite(tiles["floor_rough_stone"], (tx * TILE, ty * TILE))
    tiled_floor.resize((512, 512), Image.Resampling.NEAREST).save(PREVIEW_DIR / "floor_rough_stone_tiled_preview.png")
    overlay_preview = compose_preview(tiles["floor_rough_stone"], tiles["overlay_moss"])
    overlay_preview.alpha_composite(tiles["overlay_cracks"])
    overlay_preview.resize((256, 256), Image.Resampling.NEAREST).save(PREVIEW_DIR / "floor_with_overlays_preview.png")


def build() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)

    tiles = {
        "wall_stone_brick": make_wall_stone_brick(),
        "floor_rough_stone": make_floor_rough_stone(),
        "ceiling_stone_slab": make_ceiling_stone_slab(),
        "lintel_cut_stone": make_lintel_cut_stone(),
        "pillar_stone_side": make_pillar_stone_side(),
        "door_oak_iron": make_door_oak_iron(),
        "boss_skull_double_door": make_boss_skull_double_door(),
        "door_edge_side": make_door_edge_side(),
        "door_edge_top": make_door_edge_top(),
        "portal_rune": make_portal_rune(),
        "decor_iron_grate": make_iron_grate(),
        "overlay_cracks": make_overlay("cracks"),
        "overlay_moss": make_overlay("moss"),
        "overlay_grime": make_overlay("grime"),
        "overlay_blood": make_overlay("blood"),
        "overlay_torch_scorch": make_overlay("torch_scorch"),
        "decor_rubble": make_rubble(),
    }
    for name, tile in tiles.items():
        save_tile(name, tile)

    layout = {
        "wall_stone_brick": (0, 0, 1, 1),
        "floor_rough_stone": (1, 0, 1, 1),
        "ceiling_stone_slab": (2, 0, 1, 1),
        "lintel_cut_stone": (3, 0, 1, 1),
        "pillar_stone_side": (4, 0, 1, 1),
        "door_oak_iron": (7, 1, 1, 2),
        "portal_rune": (7, 0, 1, 1),
        "decor_iron_grate": (0, 1, 1, 1),
        "decor_rubble": (1, 1, 1, 1),
        "door_edge_side": (2, 2, 1, 1),
        "door_edge_top": (3, 2, 1, 1),
        "overlay_cracks": (2, 1, 1, 1),
        "overlay_moss": (3, 1, 1, 1),
        "overlay_grime": (4, 1, 1, 1),
        "overlay_blood": (5, 1, 1, 1),
        "overlay_torch_scorch": (6, 1, 1, 1),
        "boss_skull_double_door": (0, 2, 2, 2),
    }

    atlas = Image.new("RGBA", ATLAS_SIZE, (0, 0, 0, 0))
    metadata_tiles = {}
    for name, (col, row, span_x, span_y) in layout.items():
        tile = tiles[name]
        expected_size = (span_x * TILE, span_y * TILE)
        if tile.size != expected_size:
            raise ValueError(f"{name} is {tile.size}, expected {expected_size}")
        atlas.alpha_composite(tile, (col * TILE, row * TILE))
        metadata_tiles[name] = {
            "source": f"source_tiles/{name}.png",
            "col": col,
            "row": row,
            "span": [span_x, span_y],
            "pixel_rect": [col * TILE, row * TILE, span_x * TILE, span_y * TILE],
        }

    atlas_path = OUT_DIR / "level0_dungeon_terrain_atlas_32px.png"
    atlas.save(atlas_path)
    metadata = {
        "image": atlas_path.name,
        "tile_px": [TILE, TILE],
        "grid": [GRID[0], GRID[1]],
        "size_px": [ATLAS_SIZE[0], ATLAS_SIZE[1]],
        "tiles": metadata_tiles,
        "level": 0,
        "deprecated_replaces": [
            "res://assets/textures/dungeon-texture.png",
            "res://assets/textures/dungeon_floor.png",
            "res://assets/textures/dungeon_wall.png",
        ],
    }
    (OUT_DIR / "level0_dungeon_terrain_atlas_32px.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    save_previews(tiles, atlas)


if __name__ == "__main__":
    build()
