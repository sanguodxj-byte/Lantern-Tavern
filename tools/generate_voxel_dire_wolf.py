#!/usr/bin/env python3
"""Generate only the 100px Dire Wolf (恐狼) quadruped and its matching rig.

The dire wolf is an authored, non-humanoid body-attack creature. Its silhouette
is defined here from scratch — a stocky grey-brown wolf with a deep chest,
powerful haunches, erect ears, amber eyes, dark spine ridge, pale underbelly
and a bushy drooping tail. Scale follows docs/17: 1m = 32px, 1px = 1/32m.

Authoring axes (mirrors the S-tier dragon convention):
    +X  -> tail,  -X -> nose
    +Y  -> right, -Y -> left
    +Z  -> up, ground at Z=0 (feet bottom at Z=1)
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from voxel_dire_wolf_rig import build_dire_wolf_rig
from voxel_model_primitives import cube_px, finish_model, make_material, make_root, reset_scene
from voxel_single_model_cli import reject_target_override

MODEL_ID = "dire_wolf"
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_dire_wolf_100px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_dire_wolf_100px_rig.glb"
REAL_RENDER_DIR = ROOT / "reports" / "characters_preview"

# Final silhouette envelope (pixel units): nose -52 .. tail tip +48 on X,
# chest -9 .. +9 on Y, feet bottom 1 .. ear tip 44 on Z.
LENGTH_PX = 100.0
HEIGHT_PX = 44.0
WIDTH_PX = 18.0


def build_dire_wolf():
    """Build one face-connected dire wolf voxel assembly."""
    # Barony-style authored colour ramp: mid / dark / light fur, pale belly,
    # amber eyes, dark nose, ivory teeth.
    fur_mid = make_material("dire_wolf_fur_mid", (0.45, 0.39, 0.32, 1.0))
    fur_dark = make_material("dire_wolf_fur_dark", (0.30, 0.25, 0.21, 1.0))
    fur_light = make_material("dire_wolf_fur_light", (0.58, 0.51, 0.42, 1.0))
    belly = make_material("dire_wolf_belly", (0.72, 0.65, 0.54, 1.0))
    eye = make_material("dire_wolf_eye", (0.96, 0.62, 0.10, 1.0))
    nose = make_material("dire_wolf_nose", (0.10, 0.08, 0.08, 1.0))
    tooth = make_material("dire_wolf_tooth", (0.87, 0.83, 0.73, 1.0))

    root = make_root("voxel_dire_wolf_100px")
    parts: list = []

    # --- Body chain (front -> back along X), Z 14..26 ----------------------
    parts.append(cube_px("chest", (-14, 0, 20), (16, 18, 12), fur_mid))      # X -22..-6, deep chest
    parts.append(cube_px("body_core", (2, 0, 20), (16, 15, 12), fur_mid))    # X -6..10, mid torso
    parts.append(cube_px("haunch", (18, 0, 20), (16, 15, 12), fur_mid))      # X 10..26, hips

    # --- Spine ridge (dark, exterior plates on body top Z=26) --------------
    parts.append(cube_px("spine_chest", (-12, 0, 26.5), (12, 8, 1), fur_dark))
    parts.append(cube_px("spine_core", (2, 0, 26.5), (14, 7, 1), fur_dark))
    parts.append(cube_px("spine_haunch", (18, 0, 26.5), (14, 7, 1), fur_dark))

    # --- Pale underbelly (exterior plate under body_core, between legs) ----
    parts.append(cube_px("belly", (2, 0, 13.5), (10, 7, 1), belly))

    # --- Neck + ruff (pale mane) ------------------------------------------
    parts.append(cube_px("neck", (-26, 0, 24), (8, 11, 10), fur_mid))        # X -30..-22
    for side, sy in (("left", -1.0), ("right", 1.0)):
        parts.append(cube_px(f"{side}_ruff", (-26, sy * 6.0, 24), (6, 1, 7), fur_light))

    # --- Head + muzzle + jaw ----------------------------------------------
    parts.append(cube_px("head", (-36, 0, 29), (12, 12, 10), fur_mid))       # X -42..-30
    parts.append(cube_px("muzzle", (-46, 0, 26), (8, 8, 8), fur_light))      # X -50..-42
    parts.append(cube_px("jaw", (-46, 0, 19.5), (8, 6, 5), fur_light))       # Z 17..22
    parts.append(cube_px("nose", (-51, 0, 26), (2, 4, 4), nose))             # X -52..-50

    # --- Eyes (amber, exterior plates on head sides) -----------------------
    # head half-width = 6px, eye half-width = 0.5px -> center at +-6.5px.
    for side, sy in (("left", -1.0), ("right", 1.0)):
        parts.append(cube_px(f"{side}_eye", (-38, sy * 6.5, 29), (3, 1, 2), eye))

    # --- Ears (erect, pointed) --------------------------------------------
    for side, sy in (("left", -1.0), ("right", 1.0)):
        parts.append(cube_px(f"{side}_ear", (-33, sy * 4.0, 38), (3, 3, 8), fur_dark))
        parts.append(cube_px(f"{side}_ear_tip", (-33, sy * 4.0, 43), (2, 2, 2), fur_dark))

    # --- Fangs (ivory canines under jaw) ----------------------------------
    for side, sy in (("left", -1.0), ("right", 1.0)):
        parts.append(cube_px(f"{side}_fang", (-49, sy * 1.5, 15.5), (2, 2, 3), tooth))

    # --- Legs (thigh + foot), front under chest, back under haunch --------
    for side, sy in (("left", -1.0), ("right", 1.0)):
        parts.append(cube_px(f"{side}_front_thigh", (-16, sy * 6.0, 9), (7, 7, 10), fur_mid))
        parts.append(cube_px(f"{side}_front_foot", (-16, sy * 6.0, 2.5), (9, 7, 3), fur_dark))
        parts.append(cube_px(f"{side}_back_thigh", (16, sy * 6.0, 9), (8, 8, 10), fur_mid))
        parts.append(cube_px(f"{side}_back_foot", (16, sy * 6.0, 2.5), (9, 8, 3), fur_dark))

    # --- Bushy drooping tail ----------------------------------------------
    parts.append(cube_px("tail_1", (30, 0, 20), (8, 7, 8), fur_mid))         # X 26..34
    parts.append(cube_px("tail_2", (38, 0, 18), (8, 6, 6), fur_mid))         # X 34..42
    parts.append(cube_px("tail_3", (45, 0, 15), (6, 5, 5), fur_dark))        # X 42..48, tip

    for part in parts:
        part.parent = root
    return root


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root = build_dire_wolf()
    static_path = finish_model(
        root,
        output_path=STATIC_OUTPUT,
        preview_dir=REAL_RENDER_DIR,
        validation_label=MODEL_ID,
        render_stem="voxel_dire_wolf",
    )
    if static_path.resolve() != STATIC_OUTPUT.resolve():
        raise RuntimeError(f"dire wolf static export escaped its fixed output: {static_path}")
    build_dire_wolf_rig(STATIC_OUTPUT, RIG_OUTPUT)


if __name__ == "__main__":
    main()
