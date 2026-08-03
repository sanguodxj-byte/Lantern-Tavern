from __future__ import annotations

"""Independently authored voxel acid_trap dungeon hazard model.

Identity: cracked stone acid pool with glowing green liquid and corroded rim
Blank-slate redesign. Shared mechanical helpers only.

Run:
  D:/123/blender/blender.exe --background --python tools/generate_voxel_acid_trap.py
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

MODEL_ID = "acid_trap"
OUT_GLB = ROOT / "assets" / "meshes" / "traps" / f"traps_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "traps_preview"
SHAPE_NOTE = "cracked stone acid pool with glowing green liquid and corroded rim"

# Acid trap identity palette: dark dungeon stone, cracked granite, toxic
# green acid, yellow-green scum, corroded brown, deep shadow.
# Each material owns its own seed/pattern; no shared identity table.
_DARK_STONE = (0.32, 0.30, 0.28, 1.0)
_CRACK_GRANITE = (0.42, 0.38, 0.34, 1.0)
_PALE_STONE = (0.52, 0.48, 0.44, 1.0)
_ACID_GREEN = (0.10, 0.75, 0.12, 1.0)
_ACID_BRIGHT = (0.30, 0.95, 0.20, 1.0)
_SCUM_YELLOW = (0.65, 0.80, 0.20, 1.0)
_CORRODE_BROWN = (0.38, 0.24, 0.10, 1.0)
_DEEP_SHADOW = (0.08, 0.10, 0.06, 1.0)
_ACID_TEAL = (0.08, 0.45, 0.28, 1.0)


def build_model():
    # --- Materials ---
    stone = make_pixel_material(
        "at_stone", (0.32, 0.30, 0.28, 1.0),
        roughness=0.92,
        palette=(_DARK_STONE, _CRACK_GRANITE, _PALE_STONE, _DEEP_SHADOW),
        pixel_size=48, variation=0.42, seed=3201, pattern="cracks", normal_strength=1.2,
        edge_darken=0.45, highlight=0.20, detail_noise=0.15,
    )
    stone_dark = make_pixel_material(
        "at_stone_dark", (0.22, 0.20, 0.18, 1.0),
        roughness=0.94,
        palette=(_DEEP_SHADOW, _DARK_STONE, _CORRODE_BROWN, _CRACK_GRANITE),
        pixel_size=48, variation=0.42, seed=3213, pattern="cracks", normal_strength=1.3,
        edge_darken=0.50, highlight=0.15, detail_noise=0.15,
    )
    acid = make_pixel_material(
        "at_acid", (0.10, 0.75, 0.12, 1.0),
        roughness=0.15,
        palette=(_ACID_GREEN, _ACID_BRIGHT, _SCUM_YELLOW, _ACID_TEAL),
        pixel_size=48, variation=0.40, seed=3227, pattern="speckle", normal_strength=0.8,
        edge_darken=0.30, highlight=0.60, detail_noise=0.15,
    )
    scum = make_pixel_material(
        "at_scum", (0.65, 0.80, 0.20, 1.0),
        roughness=0.55,
        palette=(_SCUM_YELLOW, _ACID_BRIGHT, _CORRODE_BROWN, _ACID_GREEN),
        pixel_size=48, variation=0.41, seed=3241, pattern="porous", normal_strength=1.0,
        edge_darken=0.35, highlight=0.45, detail_noise=0.15,
    )
    corrode = make_pixel_material(
        "at_corrode", (0.38, 0.24, 0.10, 1.0),
        roughness=0.80, metallic=0.20,
        palette=(_CORRODE_BROWN, _DARK_STONE, _ACID_TEAL, _DEEP_SHADOW),
        pixel_size=48, variation=0.42, seed=3257, pattern="porous", normal_strength=1.1,
        edge_darken=0.45, highlight=0.20, detail_noise=0.15,
    )
    crack = make_pixel_material(
        "at_crack", (0.12, 0.10, 0.08, 1.0),
        roughness=0.96,
        palette=(_DEEP_SHADOW, _CORRODE_BROWN, _DARK_STONE, _ACID_TEAL),
        pixel_size=48, variation=0.42, seed=3271, pattern="cracks", normal_strength=1.4,
        edge_darken=0.55, highlight=0.10, detail_noise=0.15,
    )

    root = make_root(f"traps_{MODEL_ID}")

    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    # ================================================================
    # Geometry notes (pixel units, 1m = 32px):
    #   Pool floor: 24×24, Z:0..2 — central slab
    #   Rim base: 4-piece ring at Y/X=±14, Z:0..2 — LOW border, same
    #     height as pool floor, so acid surface above is visible from
    #     three-quarter and side views.
    #   Rim lip: corroded cap on rim base, Z:2..4 — taller, behind acid
    #   Acid surface: 20×20, Z:2..3 — sits on pool floor, ABOVE rim base
    #   Scum/bubbles: Z:3..4 — sit on acid surface
    #   Cracks/corrosion: Z:4..5 — sit on rim lip
    #   Corner stones: Z:4..9 — sit on rim lip corners
    # ================================================================

    rim_y = 14.0   # rim piece center (Y for N/S, X for W/E)
    rim_w = 4.0    # rim border thickness

    # --- Dark inner pool floor (24×24, Z:0..2) ---
    add("pool_floor", (0.0, 0.0, stack_center(0.0, 2.0)), (24.0, 24.0, 2.0), stone_dark)

    # --- Stone pool rim base (4-piece ring, Z:0..2, LOW) ---
    # N/S: full 32px width; W/E: 24px inner length (avoids corner overlap)
    add("rim_base_n", (0.0, rim_y, stack_center(0.0, 2.0)), (32.0, rim_w, 2.0), stone)
    add("rim_base_s", (0.0, -rim_y, stack_center(0.0, 2.0)), (32.0, rim_w, 2.0), stone)
    add("rim_base_w", (-rim_y, 0.0, stack_center(0.0, 2.0)), (rim_w, 24.0, 2.0), stone)
    add("rim_base_e", (rim_y, 0.0, stack_center(0.0, 2.0)), (rim_w, 24.0, 2.0), stone)

    # --- Corroded rim lip (on top of rim base, Z:2..4) ---
    add("rim_lip_n", (0.0, rim_y, stack_center(2.0, 2.0)), (32.0, rim_w, 2.0), corrode)
    add("rim_lip_s", (0.0, -rim_y, stack_center(2.0, 2.0)), (32.0, rim_w, 2.0), corrode)
    add("rim_lip_w", (-rim_y, 0.0, stack_center(2.0, 2.0)), (rim_w, 24.0, 2.0), corrode)
    add("rim_lip_e", (rim_y, 0.0, stack_center(2.0, 2.0)), (rim_w, 24.0, 2.0), corrode)

    # --- Acid liquid surface (20×20, Z:2..3, on pool floor, ABOVE low rim) ---
    add("acid_surface", (0.0, 0.0, stack_center(2.0, 1.0)), (20.0, 20.0, 1.0), acid)

    # --- Scum patches on acid surface (Z:3..4) ---
    add("scum_a", (-5.0, 3.0, stack_center(3.0, 1.0)), (4.0, 3.0, 1.0), scum)
    add("scum_b", (6.0, -4.0, stack_center(3.0, 1.0)), (3.0, 4.0, 1.0), scum)
    add("scum_c", (2.0, 7.0, stack_center(3.0, 1.0)), (3.0, 2.0, 1.0), scum)

    # --- Bubble highlights (Z:3..4) ---
    add("bubble_a", (-3.0, -2.0, stack_center(3.0, 1.0)), (1.0, 1.0, 1.0), acid)
    add("bubble_b", (4.0, 5.0, stack_center(3.0, 1.0)), (1.0, 1.0, 1.0), acid)
    add("bubble_c", (7.0, 1.0, stack_center(3.0, 1.0)), (1.0, 1.0, 1.0), acid)

    # --- Cracks on rim lip top (Z:4..5) ---
    add("crack_n", (0.0, rim_y, stack_center(4.0, 1.0)), (8.0, 2.0, 1.0), crack)
    add("crack_e", (rim_y, 0.0, stack_center(4.0, 1.0)), (2.0, 8.0, 1.0), crack)
    add("crack_w", (-rim_y, 0.0, stack_center(4.0, 1.0)), (2.0, 6.0, 1.0), crack)

    # --- Corrosion stains on rim lip top (Z:4..5) ---
    add("corrode_n", (8.0, rim_y, stack_center(4.0, 1.0)), (5.0, 2.0, 1.0), corrode)
    add("corrode_w", (-rim_y, 8.0, stack_center(4.0, 1.0)), (2.0, 5.0, 1.0), corrode)

    # --- Corner stones (broken, asymmetric, on rim lip corners, Z:4..) ---
    add("corner_ne", (rim_y, rim_y, stack_center(4.0, 5.0)), (4.0, 4.0, 5.0), stone_dark)
    add("corner_sw", (-rim_y, -rim_y, stack_center(4.0, 4.0)), (4.0, 4.0, 4.0), stone)
    add("corner_nw", (-rim_y, rim_y, stack_center(4.0, 3.0)), (4.0, 4.0, 3.0), stone)
    add("corner_se", (rim_y, -rim_y, stack_center(4.0, 5.0)), (4.0, 4.0, 5.0), stone_dark)

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
        ground_offset_px=1.0,
    )
    print(f"Wrote {OUT_GLB}")


if __name__ == "__main__":
    main()
