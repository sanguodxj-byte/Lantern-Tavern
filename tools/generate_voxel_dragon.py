#!/usr/bin/env python3
"""Generate only the 256px Lantern Sailwyrm dragon and its matching rig."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from voxel_dragon_rig import build_dragon_rig
from voxel_model_primitives import cube_px, finish_model, make_material, make_root, reset_scene
from voxel_single_model_cli import reject_target_override

MODEL_ID = "dragon"
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_dragon_256px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_dragon_256px_rig.glb"
REAL_RENDER_DIR = ROOT / "reports" / "characters_preview"
LENGTH_PX = 256.0


def build_dragon():
    """Build one face-connected sailwyrm with a 256px nose-to-tail envelope."""
    indigo = make_material("dragon_indigo_hull", (0.12, 0.10, 0.28, 1.0))
    copper = make_material("dragon_copper_scale", (0.55, 0.28, 0.12, 1.0))
    sail = make_material("dragon_night_sail", (0.18, 0.08, 0.32, 1.0))
    ivory = make_material("dragon_ivory_horn", (0.88, 0.82, 0.68, 1.0))
    ember = make_material("dragon_ember_eye", (1.0, 0.35, 0.05, 1.0), emission=2.0)
    aqua = make_material("dragon_aqua_vein", (0.20, 0.85, 0.75, 1.0), emission=1.3)

    root = make_root("voxel_dragon_256px_sailwyrm")
    parts = [
        cube_px("hull_core", (0, 0, 42), (80, 28, 28), indigo),
        cube_px("prow_chest", (-52, 0, 46), (24, 34, 36), copper),
        cube_px("stern_hip", (52, 0, 40), (24, 26, 24), indigo),
        cube_px("prow_keel", (-52, 0, 27.5), (18, 12, 1), aqua),
        cube_px("hull_belly_0", (-16, 0, 27.5), (8, 16, 1), aqua),
        cube_px("hull_belly_1", (0, 0, 27.5), (8, 16, 1), aqua),
        cube_px("hull_belly_2", (16, 0, 27.5), (8, 16, 1), aqua),
        cube_px("prow_plate", (-52, -17.5, 44), (14, 1, 18), aqua),
        cube_px("hull_side_mark", (8, 14.5, 34), (24, 1, 12), aqua),
        cube_px("cervix_base", (-72, 0, 60), (16, 24, 24), copper),
        cube_px("cervix_top", (-88, 0, 74), (16, 20, 20), copper),
        cube_px("cervix_crest_0", (-72, 0, 75.5), (8, 6, 7), copper),
        cube_px("cervix_crest_1", (-88, 0, 87.5), (8, 6, 7), copper),
        cube_px("cervix_glow_0", (-72, -12.5, 60), (8, 1, 8), aqua),
        cube_px("cervix_glow_1", (-88, -10.5, 74), (8, 1, 8), aqua),
        cube_px("cranium", (-108, 0, 86), (24, 26, 20), copper),
        cube_px("muzzle", (-124, 0, 86), (8, 18, 12), copper),
        cube_px("mandible", (-124, 0, 76), (8, 16, 8), copper),
        cube_px("left_eye", (-112, -13.5, 88), (6, 1, 4), ember),
        cube_px("right_eye", (-112, 13.5, 88), (6, 1, 4), ember),
        cube_px("left_horn", (-110, -8, 100.5), (6, 5, 9), ivory),
        cube_px("right_horn", (-110, 8, 100.5), (6, 5, 9), ivory),
        cube_px("left_horn_tip", (-110, -8, 107), (5, 4, 4), ivory),
        cube_px("right_horn_tip", (-110, 8, 107), (5, 4, 4), ivory),
        cube_px("brow_plate", (-112, 0, 96.5), (12, 8, 1), aqua),
        cube_px("left_tusk", (-126, -4, 70), (4, 3, 4), ivory),
        cube_px("right_tusk", (-126, 4, 70), (4, 3, 4), ivory),
        cube_px("tooth_0", (-126, 0, 70), (2, 2, 4), ivory),
        cube_px("tooth_1", (-124, 0, 70), (2, 2, 4), ivory),
        cube_px("tooth_2", (-122, 0, 70), (2, 2, 4), ivory),
        cube_px("whip_0", (72, 0, 40), (16, 22, 20), copper),
        cube_px("whip_1", (88, 0, 38), (16, 16, 14), indigo),
        cube_px("whip_2", (104, 0, 36), (16, 12, 10), copper),
        cube_px("whip_3", (118, 0, 36), (12, 8, 6), indigo),
        cube_px("tail_spike", (126, 0, 36), (4, 16, 8), ivory),
        cube_px("tail_spike_banner", (126, 0, 44), (4, 6, 8), ivory),
        cube_px("tail_spike_weight", (126, 0, 28), (4, 6, 8), ivory),
        cube_px("whip_sail_left", (88, -9.5, 38), (12, 3, 10), sail),
        cube_px("whip_sail_right", (88, 9.5, 38), (12, 3, 10), sail),
        cube_px("left_wing_shoulder", (-4, -18, 58), (20, 8, 8), copper),
        cube_px("left_wing_arm", (0, -30, 62), (24, 16, 12), copper),
        cube_px("left_wing_forearm", (8, -50, 65), (40, 24, 10), indigo),
        cube_px("left_wing_tip", (16, -74, 67), (48, 24, 10), indigo),
        cube_px("left_wing_claw", (28, -94, 67), (16, 16, 8), ivory),
        cube_px("left_wing_membrane_root", (20, -18, 48), (72, 8, 12), sail),
        cube_px("left_wing_membrane_a", (12, -30, 50), (56, 14, 12), sail),
        cube_px("left_wing_membrane_b", (12, -50, 54), (48, 22, 12), sail),
        cube_px("left_wing_membrane_tip", (16, -74, 57), (32, 20, 10), sail),
        cube_px("left_front_leg", (-24, -14, 20), (14, 12, 16), copper),
        cube_px("left_shin_front", (-26, -14, 8), (12, 12, 8), indigo),
        cube_px("left_claw_front", (-30, -14, 3), (16, 12, 2), ivory),
        cube_px("left_back_leg", (24, -14, 20), (16, 12, 16), copper),
        cube_px("left_shin_back", (26, -14, 8), (12, 12, 8), indigo),
        cube_px("left_claw_back", (30, -14, 3), (16, 12, 2), ivory),
        cube_px("right_wing_shoulder", (-4, 18, 58), (20, 8, 8), copper),
        cube_px("right_wing_arm", (0, 30, 62), (24, 16, 12), copper),
        cube_px("right_wing_forearm", (8, 50, 65), (40, 24, 10), indigo),
        cube_px("right_wing_tip", (16, 74, 67), (48, 24, 10), indigo),
        cube_px("right_wing_claw", (28, 94, 67), (16, 16, 8), ivory),
        cube_px("right_wing_membrane_root", (20, 18, 48), (72, 8, 12), sail),
        cube_px("right_wing_membrane_a", (12, 30, 50), (56, 14, 12), sail),
        cube_px("right_wing_membrane_b", (12, 50, 54), (48, 22, 12), sail),
        cube_px("right_wing_membrane_tip", (16, 74, 57), (32, 20, 10), sail),
        cube_px("right_front_leg", (-24, 14, 20), (14, 12, 16), copper),
        cube_px("right_shin_front", (-26, 14, 8), (12, 12, 8), indigo),
        cube_px("right_claw_front", (-30, 14, 3), (16, 12, 2), ivory),
        cube_px("right_back_leg", (24, 14, 20), (16, 12, 16), copper),
        cube_px("right_shin_back", (26, 14, 8), (12, 12, 8), indigo),
        cube_px("right_claw_back", (30, 14, 3), (16, 12, 2), ivory),
        cube_px("dorsal_sail_0", (-20, 0, 64), (8, 6, 16), ivory),
        cube_px("dorsal_sail_1", (0, 0, 64), (8, 6, 16), ivory),
        cube_px("dorsal_sail_2", (20, 0, 64), (8, 6, 16), ivory),
        cube_px("dorsal_glow_0", (-14, 0, 56.5), (4, 4, 1), aqua),
        cube_px("dorsal_glow_1", (6, 0, 56.5), (4, 4, 1), aqua),
        cube_px("dorsal_glow_2", (26, 0, 56.5), (4, 4, 1), aqua),
    ]
    for part in parts:
        part.parent = root
    return root


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root = build_dragon()
    static_path = finish_model(
        root,
        output_path=STATIC_OUTPUT,
        preview_dir=REAL_RENDER_DIR,
        validation_label=MODEL_ID,
        render_stem="voxel_dragon",
    )
    if static_path.resolve() != STATIC_OUTPUT.resolve():
        raise RuntimeError(f"dragon static export escaped its fixed output: {static_path}")
    build_dragon_rig(STATIC_OUTPUT, RIG_OUTPUT)


if __name__ == "__main__":
    main()
