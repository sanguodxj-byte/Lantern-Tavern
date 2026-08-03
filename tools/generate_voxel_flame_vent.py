from __future__ import annotations

"""Independently authored voxel flame_vent dungeon hazard model.

Identity: scorched iron floor grate with glowing lava pit beneath
Blank-slate redesign. Shared mechanical helpers only.

Run:
  D:/123/blender/blender.exe --background --python tools/generate_voxel_flame_vent.py
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from voxel_model_primitives import (  # noqa: E402
    cube_px,
    face_attachment_center,
    finish_model,
    make_pixel_material,
    make_root,
    reset_scene,
    stack_center,
)
from voxel_single_model_cli import reject_target_override  # noqa: E402

MODEL_ID = "flame_vent"
OUT_GLB = ROOT / "assets" / "meshes" / "traps" / f"traps_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "traps_preview"
SHAPE_NOTE = "scorched iron floor grate with glowing lava pit beneath"

# Flame vent identity palette: dark dungeon stone, scorched iron grate,
# glowing lava orange, ember red, soot black, dark ash grey.
# Each material owns its own seed/pattern; no shared identity table.
_DARK_STONE = (0.28, 0.26, 0.24, 1.0)
_SCORCH_STONE = (0.18, 0.14, 0.12, 1.0)
_GRATE_IRON = (0.30, 0.20, 0.14, 1.0)
_GRATE_DARK = (0.14, 0.10, 0.08, 1.0)
_LAVA_ORANGE = (0.95, 0.45, 0.06, 1.0)
_LAVA_BRIGHT = (1.0, 0.80, 0.20, 1.0)
_EMBER_RED = (0.80, 0.12, 0.02, 1.0)
_SOOT_BLACK = (0.06, 0.05, 0.04, 1.0)
_ASH_GREY = (0.35, 0.30, 0.26, 1.0)
_CHAR_CRACK = (0.08, 0.06, 0.05, 1.0)


def build_model():
    # --- Materials ---
    stone = make_pixel_material(
        "fv_stone", (0.28, 0.26, 0.24, 1.0),
        roughness=0.92,
        palette=(_DARK_STONE, _SCORCH_STONE, _ASH_GREY, _SOOT_BLACK),
        pixel_size=48, variation=0.42, seed=3301, pattern="cracks", normal_strength=1.2,
        edge_darken=0.45, highlight=0.20, detail_noise=0.15,
    )
    scorch = make_pixel_material(
        "fv_scorch", (0.18, 0.14, 0.12, 1.0),
        roughness=0.95,
        palette=(_SOOT_BLACK, _SCORCH_STONE, _CHAR_CRACK, _GRATE_DARK),
        pixel_size=48, variation=0.44, seed=3313, pattern="cracks", normal_strength=1.3,
        edge_darken=0.50, highlight=0.10, detail_noise=0.15,
    )
    grate_iron = make_pixel_material(
        "fv_grate", (0.30, 0.20, 0.14, 1.0),
        roughness=0.78, metallic=0.55,
        palette=(_GRATE_IRON, _GRATE_DARK, _SOOT_BLACK, _EMBER_RED),
        pixel_size=48, variation=0.42, seed=3327, pattern="banded", normal_strength=1.1,
        edge_darken=0.42, highlight=0.30, detail_noise=0.15,
    )
    grate_dark = make_pixel_material(
        "fv_grate_dark", (0.14, 0.10, 0.08, 1.0),
        roughness=0.88, metallic=0.40,
        palette=(_GRATE_DARK, _SOOT_BLACK, _GRATE_IRON, _CHAR_CRACK),
        pixel_size=48, variation=0.42, seed=3341, pattern="cracks", normal_strength=1.2,
        edge_darken=0.48, highlight=0.15, detail_noise=0.15,
    )
    lava = make_pixel_material(
        "fv_lava", (0.95, 0.45, 0.06, 1.0),
        roughness=0.12,
        palette=(_LAVA_ORANGE, _LAVA_BRIGHT, _EMBER_RED, _SOOT_BLACK),
        pixel_size=48, variation=0.40, seed=3357, pattern="cracks", normal_strength=0.9,
        edge_darken=0.25, highlight=0.70, detail_noise=0.15,
    )
    ember = make_pixel_material(
        "fv_ember", (0.80, 0.12, 0.02, 1.0),
        roughness=0.30,
        palette=(_EMBER_RED, _LAVA_ORANGE, _SOOT_BLACK, _CHAR_CRACK),
        pixel_size=48, variation=0.42, seed=3371, pattern="speckle", normal_strength=1.0,
        edge_darken=0.30, highlight=0.55, detail_noise=0.15,
    )
    crack_glow = make_pixel_material(
        "fv_crack_glow", (0.60, 0.20, 0.04, 1.0),
        roughness=0.50,
        palette=(_EMBER_RED, _LAVA_ORANGE, _SOOT_BLACK, _GRATE_DARK),
        pixel_size=48, variation=0.42, seed=3389, pattern="vein", normal_strength=1.1,
        edge_darken=0.35, highlight=0.40, detail_noise=0.15,
    )

    root = make_root(f"traps_{MODEL_ID}")

    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    # ================================================================
    # Geometry notes (pixel units, 1m = 32px):
    #   Frame: 32×32 outer, 24×24 inner opening, Z:0..2 (LOW)
    #   Pit walls: Z:-1..0 (very shallow, 1px pit)
    #   Pit floor: Z:-2..-1, connects to pit walls via Z flush at -1
    #   Lava: Z:-1..0, on pit floor, just 1px below frame bottom
    #   Embers: Z:0..1, ABOVE frame bottom, at frame level for max visibility
    #   Grate bars: 2 bars only (wide gaps), Z:2..4, thinner (1px wide)
    # ================================================================

    frame_half = 16.0   # outer half-extent of frame
    frame_w = 4.0       # frame border width
    inner_half = 12.0   # inner opening half-extent (frame_half - frame_w)
    pit_depth = 1.0     # pit wall depth below frame (very shallow)

    # --- Outer stone frame (4 pieces forming a square ring, Z:0..2) ---
    add("frame_n", (0.0, face_attachment_center(0.0, inner_half, frame_w * 0.5, 1.0), stack_center(0.0, 2.0)),
        (32.0, frame_w, 2.0), stone)
    add("frame_s", (0.0, face_attachment_center(0.0, inner_half, frame_w * 0.5, -1.0), stack_center(0.0, 2.0)),
        (32.0, frame_w, 2.0), stone)
    add("frame_w", (face_attachment_center(0.0, inner_half, frame_w * 0.5, -1.0), 0.0, stack_center(0.0, 2.0)),
        (frame_w, 24.0, 2.0), stone)
    add("frame_e", (face_attachment_center(0.0, inner_half, frame_w * 0.5, 1.0), 0.0, stack_center(0.0, 2.0)),
        (frame_w, 24.0, 2.0), stone)

    # --- Pit walls (4 pieces, Z:-1..0, very shallow) ---
    wall_thick = 2.0
    wall_overlap = 1.5
    wall_y = inner_half + wall_overlap  # 13.5
    add("pit_wall_n", (0.0, wall_y, stack_center(-pit_depth, pit_depth)), (24.0, wall_thick, pit_depth), grate_dark)
    add("pit_wall_s", (0.0, -wall_y, stack_center(-pit_depth, pit_depth)), (24.0, wall_thick, pit_depth), grate_dark)
    add("pit_wall_w", (-wall_y, 0.0, stack_center(-pit_depth, pit_depth)), (wall_thick, 20.0, pit_depth), grate_dark)
    add("pit_wall_e", (wall_y, 0.0, stack_center(-pit_depth, pit_depth)), (wall_thick, 20.0, pit_depth), grate_dark)

    # --- Pit floor (26×26, Z:-2..-1, connects to pit walls via Z flush at -1) ---
    add("pit_floor", (0.0, 0.0, stack_center(-pit_depth - 1.0, 1.0)), (26.0, 26.0, 1.0), grate_dark)

    # --- Lava floor (22×22, Z:-1..0, on pit floor, just below frame bottom) ---
    add("lava_floor", (0.0, 0.0, stack_center(-pit_depth, 1.0)), (22.0, 22.0, 1.0), lava)

    # --- Ember clusters on lava (Z:0..1, at frame level for max visibility) ---
    lava_top = -pit_depth + 1.0  # Z = 0
    add("ember_a", (-5.0, 4.0, stack_center(lava_top, 1.0)), (4.0, 3.0, 1.0), ember)
    add("ember_b", (6.0, -3.0, stack_center(lava_top, 1.0)), (3.0, 4.0, 1.0), ember)
    add("ember_c", (2.0, 7.0, stack_center(lava_top, 1.0)), (3.0, 2.0, 1.0), ember)
    add("ember_d", (-7.0, -5.0, stack_center(lava_top, 1.0)), (2.0, 3.0, 1.0), ember)
    add("ember_e", (8.0, 5.0, stack_center(lava_top, 1.0)), (2.0, 2.0, 1.0), ember)

    # --- Glowing cracks on pit walls (interior face plates, Z:-1..0) ---
    crack_y = wall_y - wall_thick * 0.5 - 0.5  # inner face of wall, plate center at 12.0
    add("crack_glow_n", (0.0, crack_y, stack_center(-pit_depth, pit_depth)), (6.0, 1.0, pit_depth), crack_glow)
    crack_x = -wall_y + wall_thick * 0.5 + 0.5
    add("crack_glow_w", (crack_x, -3.0, stack_center(-pit_depth, pit_depth)), (1.0, 5.0, pit_depth), crack_glow)

    # --- Scorch marks on frame exterior (face-attached plates, Z:0..2) ---
    scorch_y = face_attachment_center(0.0, frame_half, 0.5, 1.0)
    add("scorch_n", (3.0, scorch_y, stack_center(0.0, 2.0)), (8.0, 1.0, 2.0), scorch)
    scorch_x = face_attachment_center(0.0, frame_half, 0.5, -1.0)
    add("scorch_w", (scorch_x, -2.0, stack_center(0.0, 2.0)), (1.0, 6.0, 2.0), scorch)

    # --- Grate bars (2 bars only, wide gaps, Z:2..4, thinner 1px) ---
    grate_len = 28.0
    grate_positions = [-6.0, 6.0]
    for i, gx in enumerate(grate_positions):
        suffix = ["l", "r"][i]
        add(f"grate_bar_{suffix}", (gx, 0.0, stack_center(2.0, 2.0)), (1.0, grate_len, 2.0), grate_iron)
        add(f"grate_bar_{suffix}_under", (gx, 0.0, stack_center(1.0, 1.0)), (1.0, 20.0, 1.0), grate_dark)

    # --- Soot / rust accents on grate top (Z:4..5) ---
    add("soot_l", (-6.0, 5.0, stack_center(4.0, 1.0)), (1.0, 3.0, 1.0), scorch)
    add("rust_r", (6.0, -5.0, stack_center(4.0, 1.0)), (1.0, 4.0, 1.0), grate_dark)

    # --- Corner bolts on frame top (Z:2..3) ---
    bolt_z = stack_center(2.0, 1.0)
    bolt_offset = frame_half - 1.0
    add("bolt_nw", (-bolt_offset, bolt_offset, bolt_z), (2.0, 2.0, 1.0), grate_iron)
    add("bolt_ne", (bolt_offset, bolt_offset, bolt_z), (2.0, 2.0, 1.0), grate_iron)
    add("bolt_sw", (-bolt_offset, -bolt_offset, bolt_z), (2.0, 2.0, 1.0), grate_iron)
    add("bolt_se", (bolt_offset, -bolt_offset, bolt_z), (2.0, 2.0, 1.0), grate_iron)

    return root


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root = build_model()
    finish_model(
        root,
        output_path=OUT_GLB,
        preview_dir=PREVIEW_DIR,
        validation_label=MODEL_ID,
        render_stem=f"voxel_{MODEL_ID}",
        ground_offset_px=2.0,
    )
    print(f"Wrote {OUT_GLB}")


if __name__ == "__main__":
    main()
