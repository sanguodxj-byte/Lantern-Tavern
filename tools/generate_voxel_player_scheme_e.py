from __future__ import annotations

"""Player scheme E — Roofrunner Scout

Lanky night scout: dark tunic, red scarf, greaves, hip satchel, messy black hair, sharp nose, tall narrow envelope.

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

MODEL_ID = "player_scheme_e"
TARGET_ENVELOPE_PX = (21.0, 60.0, 19.5)
ENVELOPE_TOLERANCE_PX = 1.0
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_player_scheme_e.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"
RENDER_STEM = "voxel_player_scheme_e"


def build_player_scheme_e() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    root = make_root("voxel_player_scheme_e")

    tunic_deep = make_material("E_Tunic_Deep", (0.08, 0.10, 0.12, 1.0))
    tunic_dark = make_material("E_Tunic_Dark", (0.14, 0.18, 0.20, 1.0))
    tunic_mid = make_material("E_Tunic_Mid", (0.22, 0.28, 0.30, 1.0))
    tunic_high = make_material("E_Tunic_High", (0.34, 0.42, 0.40, 1.0))
    scarf = make_material("E_Scarf", (0.45, 0.18, 0.16, 1.0))
    scarf_h = make_material("E_Scarf_H", (0.62, 0.28, 0.24, 1.0))
    leather = make_material("E_Leather", (0.28, 0.18, 0.12, 1.0))
    leather_h = make_material("E_Leather_H", (0.42, 0.28, 0.18, 1.0))
    greave = make_material("E_Greave", (0.20, 0.22, 0.24, 1.0))
    boot = make_material("E_Boot", (0.12, 0.10, 0.09, 1.0))
    skin_shadow = make_material("E_Skin_Shadow", (0.38, 0.24, 0.20, 1.0))
    skin_mid = make_material("E_Skin_Mid", (0.58, 0.40, 0.32, 1.0))
    skin_high = make_material("E_Skin_High", (0.76, 0.54, 0.42, 1.0))
    hair_deep = make_material("E_Hair_Deep", (0.05, 0.05, 0.06, 1.0))
    hair_mid = make_material("E_Hair_Mid", (0.12, 0.12, 0.14, 1.0))
    hair_high = make_material("E_Hair_High", (0.22, 0.22, 0.26, 1.0))
    eye_lgt = make_material("E_Eye", (0.65, 0.80, 0.70, 1.0))
    eye_dk = make_material("E_Pupil", (0.04, 0.05, 0.04, 1.0))

    parts: list[bpy.types.Object] = []

    def add(name, center_px, size_px, material):
        part = cube_px(name, center_px, size_px, material)
        part.parent = root
        parts.append(part)
        return part

    # Lanky tall frame
    add("boot_l", (-2.5, -0.5, 1.5), (4.0, 8.0, 3.0), boot)
    add("boot_toe_l", (-2.5, -5.0, 1.0), (4.0, 1.0, 1.0), leather_h)
    add("greave_l", (-2.5, 0.5, 6.5), (4.0, 5.0, 7.0), greave)
    add("thigh_l", (-2.5, 1.0, 15.0), (4.0, 5.0, 10.0), tunic_dark)
    add("boot_r", (2.5, -0.5, 1.5), (4.0, 8.0, 3.0), boot)
    add("boot_toe_r", (2.5, -5.0, 1.0), (4.0, 1.0, 1.0), leather_h)
    add("greave_r", (2.5, 0.5, 6.5), (4.0, 5.0, 7.0), greave)
    add("thigh_r", (2.5, 1.0, 15.0), (4.0, 5.0, 10.0), tunic_dark)
    add("pelvis", (0.0, 0.5, 22.5), (10.0, 6.0, 5.0), tunic_deep)
    add("belt", (0.0, 0.5, 25.5), (10.0, 6.0, 1.0), leather)
    add("satchel", (4.5, 4.5, 22.0), (3.0, 2.0, 4.0), leather_h)
    add("satchel_strap", (4.5, 4.5, 32.0), (1.0, 1.0, 12.0), leather)
    add("torso", (0.0, 0.5, 33.0), (9.0, 7.0, 14.0), tunic_mid)
    add("tunic_hem_f", (0.0, -3.5, 27.0), (9.0, 1.0, 4.0), tunic_high)
    add("scarf_wrap", (0.0, 0.5, 40.5), (8.0, 7.0, 1.0), scarf)
    add("scarf_tail", (-4.5, -4.0, 37.0), (2.0, 2.0, 6.0), scarf_h)
    add("shoulder_l", (-6.5, 0.5, 40.0), (4.0, 6.0, 3.0), tunic_dark)
    add("shoulder_r", (6.5, 0.5, 40.0), (4.0, 6.0, 3.0), tunic_dark)
    add("arm_l", (-8.5, 0.0, 35.5), (3.0, 5.0, 6.0), tunic_mid)
    add("cuff_l", (-8.5, 0.0, 31.0), (4.0, 6.0, 3.0), tunic_high)
    add("fore_l", (-8.5, 0.5, 26.5), (3.0, 4.0, 6.0), skin_mid)
    add("hand_l", (-8.5, 0.0, 21.0), (3.0, 5.0, 5.0), skin_mid)
    add("thumb_l", (-7.0, -3.0, 21.0), (1.0, 1.0, 2.0), skin_high)
    add("arm_r", (8.5, 0.0, 35.5), (3.0, 5.0, 6.0), tunic_mid)
    add("cuff_r", (8.5, 0.0, 31.0), (4.0, 6.0, 3.0), tunic_high)
    add("fore_r", (8.5, 0.5, 26.5), (3.0, 4.0, 6.0), skin_mid)
    add("hand_r", (8.5, 0.0, 21.0), (3.0, 5.0, 5.0), skin_mid)
    add("thumb_r", (7.0, -3.0, 21.0), (1.0, 1.0, 2.0), skin_high)
    # Head: Barony/MC oversized cube on lanky scout frame (head wider than torso)
    # Scarf/shoulder top z~41; short neck peg.
    add("neck", (0.0, 1.0, 42.5), (5.0, 5.0, 3.0), skin_shadow)
    add("jaw", (0.0, 0.5, 45.5), (14.0, 12.0, 3.0), skin_shadow)
    add("face_core", (0.0, 0.0, 50.5), (14.0, 13.0, 7.0), skin_mid)
    add("cranium", (0.0, 0.5, 55.5), (14.0, 13.0, 3.0), skin_mid)
    add("cheek_l", (-8.0, -3.0, 50.0), (2.0, 5.0, 4.0), skin_high)
    add("cheek_r", (8.0, -3.0, 50.0), (2.0, 5.0, 4.0), skin_high)
    add("chin", (0.0, -7.0, 45.5), (6.0, 3.0, 2.0), skin_high)
    add("ear_l", (-8.5, 1.5, 51.0), (3.0, 3.0, 4.0), skin_mid)
    add("ear_r", (8.5, 1.5, 51.0), (3.0, 3.0, 4.0), skin_mid)
    add("nose_bridge", (0.0, -7.5, 51.5), (3.0, 2.0, 4.0), skin_high)
    add("nose_tip", (0.0, -9.5, 49.5), (4.0, 2.0, 3.0), skin_mid)
    add("eye_l", (-3.5, -7.0, 52.5), (3.0, 1.0, 2.0), eye_lgt)
    add("eye_r", (3.5, -7.0, 52.5), (3.0, 1.0, 2.0), eye_lgt)
    add("pupil_l", (-3.5, -8.0, 52.5), (2.0, 1.0, 2.0), eye_dk)
    add("pupil_r", (3.5, -8.0, 52.5), (2.0, 1.0, 2.0), eye_dk)
    add("brow_l", (-3.5, -7.0, 54.0), (4.0, 1.0, 1.0), hair_mid)
    add("brow_r", (3.5, -7.0, 54.0), (4.0, 1.0, 1.0), hair_mid)
    add("mouth", (0.0, -7.0, 48.5), (5.0, 1.0, 2.0), hair_deep)
    # Messy scout hair: crown + asymmetric exterior spikes only.
    add("hair_crown", (0.0, 0.5, 58.0), (15.0, 14.0, 2.0), hair_mid)
    add("hair_nape", (0.0, 8.0, 54.5), (12.0, 2.0, 5.0), hair_deep)
    add("hair_side_l", (-8.5, 2.0, 55.5), (3.0, 6.0, 3.0), hair_mid)
    add("hair_side_r", (8.5, 2.0, 55.5), (3.0, 5.0, 3.0), hair_high)
    # Asymmetric messy tufts on +Z of crown.
    add("hair_messy_l", (-4.0, -2.0, 59.5), (6.0, 5.0, 1.0), hair_mid)
    add("hair_messy_r", (4.5, 1.5, 59.5), (5.0, 6.0, 1.0), hair_high)
    add("hair_spike", (1.5, -7.5, 58.0), (3.0, 2.0, 2.0), hair_high)

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
    root, parts = build_player_scheme_e()
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
