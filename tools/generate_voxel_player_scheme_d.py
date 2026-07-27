from __future__ import annotations

"""Player scheme D — Cellar Bruiser

Stocky cellar bruiser: broad shoulders, thick bare arms, heavy belt, short wine apron, bald crown with side hair, square jaw.

Scale: 1m = 32px. Unarmed body only. This file owns the full silhouette and palette.
"""

import math
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from voxel_model_primitives import (
    bounds_center_scale,
    configure_real_render,
    cube_px,
    export_glb as export_static_glb,
    make_material,
    make_root,
    render_real_views,
    reset_scene,
    setup_lights_and_camera,
)
from voxel_overlap_guard import (
    assert_parts_no_positive_volume_overlap,
    assert_parts_single_face_connected_component,
)
from voxel_single_model_cli import reject_target_override

MODEL_ID = "player_scheme_d"
TARGET_ENVELOPE_PX = (30.0, 54.0, 19.5)
ENVELOPE_TOLERANCE_PX = 1.0
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_player_scheme_d.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"
RENDER_STEM = "voxel_player_scheme_d"


def build_player_scheme_d() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    root = make_root("voxel_player_scheme_d")

    leather_dark = make_material("D_Leather_Dark", (0.16, 0.10, 0.08, 1.0))
    leather_mid = make_material("D_Leather_Mid", (0.32, 0.20, 0.14, 1.0))
    leather_high = make_material("D_Leather_High", (0.48, 0.32, 0.20, 1.0))
    shirt_shadow = make_material("D_Shirt_Shadow", (0.35, 0.30, 0.24, 1.0))
    shirt_mid = make_material("D_Shirt_Mid", (0.55, 0.48, 0.38, 1.0))
    shirt_high = make_material("D_Shirt_High", (0.72, 0.64, 0.50, 1.0))
    apron_dark = make_material("D_Apron_Dark", (0.28, 0.12, 0.10, 1.0))
    apron_mid = make_material("D_Apron_Mid", (0.45, 0.20, 0.16, 1.0))
    trouser = make_material("D_Trouser", (0.16, 0.18, 0.20, 1.0))
    trouser_h = make_material("D_Trouser_H", (0.26, 0.28, 0.30, 1.0))
    skin_shadow = make_material("D_Skin_Shadow", (0.42, 0.26, 0.20, 1.0))
    skin_mid = make_material("D_Skin_Mid", (0.64, 0.42, 0.32, 1.0))
    skin_high = make_material("D_Skin_High", (0.82, 0.58, 0.44, 1.0))
    hair = make_material("D_Hair", (0.12, 0.10, 0.09, 1.0))
    metal = make_material("D_Metal", (0.60, 0.50, 0.28, 1.0), metallic=0.5)
    eye_lgt = make_material("D_Eye", (0.70, 0.75, 0.68, 1.0))
    eye_dk = make_material("D_Pupil", (0.05, 0.05, 0.05, 1.0))

    parts: list[bpy.types.Object] = []

    def add(name, center_px, size_px, material):
        part = cube_px(name, center_px, size_px, material)
        part.parent = root
        parts.append(part)
        return part

    # Stocky shorter legs
    add("boot_l", (-4.5, -0.5, 2.0), (7.0, 10.0, 4.0), leather_dark)
    add("boot_toe_l", (-4.5, -6.0, 1.5), (7.0, 1.0, 1.0), leather_mid)
    add("calf_l", (-4.5, 0.5, 8.0), (7.0, 7.0, 8.0), trouser)
    add("thigh_l", (-4.5, 1.0, 15.5), (8.0, 8.0, 7.0), trouser_h)
    add("boot_r", (4.5, -0.5, 2.0), (7.0, 10.0, 4.0), leather_dark)
    add("boot_toe_r", (4.5, -6.0, 1.5), (7.0, 1.0, 1.0), leather_mid)
    add("calf_r", (4.5, 0.5, 8.0), (7.0, 7.0, 8.0), trouser)
    add("thigh_r", (4.5, 1.0, 15.5), (8.0, 8.0, 7.0), trouser_h)
    add("pelvis", (0.0, 0.5, 21.5), (16.0, 10.0, 5.0), trouser)
    add("belt", (0.0, 0.5, 24.5), (16.0, 10.0, 1.0), leather_dark)
    add("buckle", (0.0, -5.0, 24.5), (4.0, 1.0, 1.0), metal)
    add("apron", (0.0, -5.5, 18.0), (12.0, 1.0, 12.0), apron_mid)
    add("apron_fold", (4.0, -6.5, 14.0), (3.0, 1.0, 2.0), apron_dark)
    # Broad torso
    add("belly", (0.0, 0.5, 28.0), (14.0, 10.0, 6.0), shirt_shadow)
    add("chest", (0.0, 0.5, 34.5), (14.0, 10.0, 7.0), shirt_mid)
    add("pec_l", (-4.0, -5.0, 35.0), (5.0, 1.0, 4.0), shirt_high)
    add("pec_r", (4.0, -5.0, 35.0), (5.0, 1.0, 4.0), shirt_high)
    add("shoulder_l", (-10.0, 0.5, 37.5), (6.0, 9.0, 4.0), shirt_shadow)
    add("shoulder_r", (10.0, 0.5, 37.5), (6.0, 9.0, 4.0), shirt_shadow)
    # Thick arms
    add("arm_l", (-12.5, 0.0, 32.5), (5.0, 7.0, 6.0), skin_mid)
    add("fore_l", (-12.5, 0.5, 25.5), (5.0, 6.0, 8.0), skin_shadow)
    add("hand_l", (-12.5, 0.0, 19.0), (5.0, 7.0, 5.0), skin_mid)
    add("thumb_l", (-10.5, -4.0, 19.0), (1.0, 1.0, 2.0), skin_high)
    add("arm_r", (12.5, 0.0, 32.5), (5.0, 7.0, 6.0), skin_mid)
    add("fore_r", (12.5, 0.5, 25.5), (5.0, 6.0, 8.0), skin_shadow)
    add("hand_r", (12.5, 0.0, 19.0), (5.0, 7.0, 5.0), skin_mid)
    add("thumb_r", (10.5, -4.0, 19.0), (1.0, 1.0, 2.0), skin_high)
    # Head: Barony/MC oversized bald cube, bruiser brow + ring side hair
    # Chest/shoulder top ~38-39.5; thick short neck.
    add("neck", (0.0, 1.0, 39.5), (7.0, 7.0, 3.0), skin_shadow)
    add("jaw", (0.0, 0.5, 42.5), (15.0, 12.0, 3.0), skin_shadow)
    add("face_core", (0.0, 0.0, 47.5), (15.0, 13.0, 7.0), skin_mid)
    # Bald cranium top kept skin_high as primary scalp read.
    add("cranium", (0.0, 0.5, 52.5), (15.0, 13.0, 3.0), skin_high)
    add("cheek_l", (-8.5, -3.0, 47.0), (2.0, 5.0, 4.0), skin_high)
    add("cheek_r", (8.5, -3.0, 47.0), (2.0, 5.0, 4.0), skin_high)
    add("chin", (0.0, -7.0, 42.5), (7.0, 3.0, 2.0), skin_high)
    add("ear_l", (-9.0, 1.5, 48.0), (3.0, 3.0, 4.0), skin_mid)
    add("ear_r", (9.0, 1.5, 48.0), (3.0, 3.0, 4.0), skin_mid)
    add("nose_bridge", (0.0, -7.5, 48.5), (3.0, 2.0, 4.0), skin_high)
    add("nose_tip", (0.0, -9.5, 46.5), (4.0, 2.0, 3.0), skin_mid)
    add("eye_l", (-3.5, -7.0, 49.5), (3.0, 1.0, 2.0), eye_lgt)
    add("eye_r", (3.5, -7.0, 49.5), (3.0, 1.0, 2.0), eye_lgt)
    add("pupil_l", (-3.5, -8.0, 49.5), (2.0, 1.0, 2.0), eye_dk)
    add("pupil_r", (3.5, -8.0, 49.5), (2.0, 1.0, 2.0), eye_dk)
    # Heavy bruiser brows.
    add("brow_l", (-4.0, -7.0, 51.0), (4.0, 1.0, 1.0), hair)
    add("brow_r", (4.0, -7.0, 51.0), (4.0, 1.0, 1.0), hair)
    add("mouth", (0.0, -7.0, 45.5), (6.0, 1.0, 2.0), hair)
    # Side/nape hair only — bald crown remains exposed skin.
    add("hair_side_l", (-9.0, 2.0, 52.5), (3.0, 6.0, 3.0), hair)
    add("hair_side_r", (9.0, 2.0, 52.5), (3.0, 5.0, 3.0), hair)
    add("hair_nape", (0.0, 8.0, 51.5), (12.0, 2.0, 4.0), hair)

    return root, parts


def _assert_authored_envelope(parts: list[bpy.types.Object]) -> None:
    minimum = [min(obj.location[axis] - obj.dimensions[axis] * 0.5 for obj in parts) for axis in range(3)]
    maximum = [max(obj.location[axis] + obj.dimensions[axis] * 0.5 for obj in parts) for axis in range(3)]
    blender_size_px = tuple(round((maximum[axis] - minimum[axis]) * 32.0, 4) for axis in range(3))
    size_px = (blender_size_px[0], blender_size_px[2], blender_size_px[1])
    for axis, (got, expected) in enumerate(zip(size_px, TARGET_ENVELOPE_PX)):
        if abs(got - expected) > ENVELOPE_TOLERANCE_PX:
            raise RuntimeError(
                f"{MODEL_ID} envelope axis {axis} is {got}px, expected {expected}px ±{ENVELOPE_TOLERANCE_PX}"
            )
    print(f"[{MODEL_ID}] envelope ok size_px={size_px} target={TARGET_ENVELOPE_PX}")


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_player_scheme_d()
    _assert_authored_envelope(parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_single_face_connected_component(parts, label=MODEL_ID)
    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    export_static_glb(root, STATIC_OUTPUT)
    root.rotation_euler.z = 0.0
    bpy.context.view_layer.update()
    center, scale = bounds_center_scale(root)
    camera = setup_lights_and_camera(center, scale)
    configure_real_render(resolution=1100)
    render_real_views(PREVIEW_DIR, RENDER_STEM, center, scale, camera)
    print(f"Wrote {STATIC_OUTPUT}")


if __name__ == "__main__":
    main()
