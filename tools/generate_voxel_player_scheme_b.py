from __future__ import annotations

"""Player scheme B — Road Freeblade

Travel-worn freeblade: leather jerkin, open collar, asymmetric half-cape, belt pouches, brow scar, tied long hair.

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

MODEL_ID = "player_scheme_b"
TARGET_ENVELOPE_PX = (24.0, 55.0, 19.5)
ENVELOPE_TOLERANCE_PX = 1.0
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_player_scheme_b.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"
RENDER_STEM = "voxel_player_scheme_b"


def build_player_scheme_b() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    root = make_root("voxel_player_scheme_b")

    leather_deep = make_material("B_Leather_Deep", (0.12, 0.07, 0.05, 1.0))
    leather_dark = make_material("B_Leather_Dark", (0.22, 0.12, 0.08, 1.0))
    leather_mid = make_material("B_Leather_Mid", (0.38, 0.22, 0.14, 1.0))
    leather_high = make_material("B_Leather_High", (0.55, 0.36, 0.22, 1.0))
    cloth_shadow = make_material("B_Cloth_Shadow", (0.28, 0.26, 0.22, 1.0))
    cloth_mid = make_material("B_Cloth_Mid", (0.48, 0.44, 0.36, 1.0))
    cloth_high = make_material("B_Cloth_High", (0.68, 0.62, 0.50, 1.0))
    cape_deep = make_material("B_Cape_Deep", (0.10, 0.12, 0.16, 1.0))
    cape_mid = make_material("B_Cape_Mid", (0.18, 0.22, 0.28, 1.0))
    cape_high = make_material("B_Cape_High", (0.30, 0.36, 0.44, 1.0))
    trouser_dark = make_material("B_Trouser_Dark", (0.12, 0.14, 0.16, 1.0))
    trouser_mid = make_material("B_Trouser_Mid", (0.22, 0.25, 0.28, 1.0))
    skin_shadow = make_material("B_Skin_Shadow", (0.40, 0.24, 0.18, 1.0))
    skin_mid = make_material("B_Skin_Mid", (0.62, 0.40, 0.30, 1.0))
    skin_high = make_material("B_Skin_High", (0.80, 0.54, 0.40, 1.0))
    hair_deep = make_material("B_Hair_Deep", (0.08, 0.06, 0.05, 1.0))
    hair_mid = make_material("B_Hair_Mid", (0.18, 0.12, 0.09, 1.0))
    hair_high = make_material("B_Hair_High", (0.32, 0.20, 0.14, 1.0))
    metal = make_material("B_Metal", (0.55, 0.55, 0.52, 1.0), metallic=0.6, roughness=0.45)
    eye_lgt = make_material("B_Eye", (0.72, 0.78, 0.70, 1.0))
    eye_dk = make_material("B_Pupil", (0.05, 0.05, 0.05, 1.0))
    scar = make_material("B_Scar", (0.55, 0.32, 0.28, 1.0))

    parts: list[bpy.types.Object] = []

    def add(name, center_px, size_px, material):
        part = cube_px(name, center_px, size_px, material)
        part.parent = root
        parts.append(part)
        return part

    # Legs
    add("boot_l", (-3.5, -0.5, 2.0), (6.0, 9.0, 4.0), leather_dark)
    add("boot_toe_l", (-3.5, -5.5, 1.5), (6.0, 1.0, 1.0), leather_mid)
    add("calf_l", (-3.5, 0.5, 8.5), (5.0, 6.0, 9.0), trouser_dark)
    add("thigh_l", (-3.5, 1.0, 17.5), (6.0, 7.0, 9.0), trouser_mid)
    add("boot_r", (3.5, -0.5, 2.0), (6.0, 9.0, 4.0), leather_dark)
    add("boot_toe_r", (3.5, -5.5, 1.5), (6.0, 1.0, 1.0), leather_mid)
    add("calf_r", (3.5, 0.5, 8.5), (5.0, 6.0, 9.0), trouser_dark)
    add("thigh_r", (3.5, 1.0, 17.5), (6.0, 7.0, 9.0), trouser_mid)
    # Pelvis + pouches
    add("pelvis", (0.0, 0.5, 24.0), (13.0, 8.0, 4.0), trouser_dark)
    add("belt", (0.0, 0.5, 26.5), (13.0, 8.0, 1.0), leather_deep)
    add("buckle", (0.0, -4.0, 26.5), (3.0, 1.0, 1.0), metal)
    add("pouch_l", (-5.5, -4.5, 24.5), (3.0, 2.0, 3.0), leather_mid)
    add("pouch_r", (5.5, -4.5, 24.0), (3.0, 2.0, 2.0), leather_high)
    # Torso leather jerkin over open shirt
    add("shirt", (0.0, 0.5, 32.0), (7.0, 8.0, 10.0), cloth_mid)
    add("shirt_collar", (0.0, -4.0, 35.0), (5.0, 1.0, 2.0), cloth_high)
    add("jerkin_l", (-5.5, -0.5, 34.5), (4.0, 9.0, 7.0), leather_mid)
    add("jerkin_r", (5.5, -0.5, 34.5), (4.0, 9.0, 7.0), leather_mid)
    add("jerkin_back", (0.0, 5.0, 34.5), (13.0, 1.0, 7.0), leather_dark)
    add("jerkin_lapel_l", (-4.5, -5.5, 35.5), (2.0, 1.0, 3.0), leather_high)
    add("jerkin_lapel_r", (4.5, -5.5, 35.5), (2.0, 1.0, 3.0), leather_high)
    # Asymmetric half-cape on left shoulder/back
    add("cape_shoulder", (-5.5, 3.0, 38.5), (5.0, 4.0, 1.0), cape_mid)
    add("cape_fall", (-5.5, 6.5, 34.0), (4.0, 2.0, 8.0), cape_deep)
    add("cape_edge", (-5.5, 8.0, 30.5), (3.0, 1.0, 3.0), cape_high)
    # Arms
    add("arm_l", (-9.5, 0.0, 34.0), (4.0, 6.0, 8.0), cloth_shadow)
    add("cuff_l", (-9.5, 0.0, 28.5), (5.0, 7.0, 3.0), cloth_high)
    add("fore_l", (-9.5, 0.5, 24.0), (4.0, 5.0, 6.0), skin_mid)
    add("hand_l", (-9.5, 0.0, 18.5), (4.0, 6.0, 5.0), skin_mid)
    add("thumb_l", (-8.0, -3.5, 18.5), (1.0, 1.0, 2.0), skin_high)
    add("arm_r", (9.5, 0.0, 34.0), (4.0, 6.0, 8.0), cloth_shadow)
    add("cuff_r", (9.5, 0.0, 28.5), (5.0, 7.0, 3.0), cloth_high)
    add("fore_r", (9.5, 0.5, 24.0), (4.0, 5.0, 6.0), skin_mid)
    add("hand_r", (9.5, 0.0, 18.5), (4.0, 6.0, 5.0), skin_mid)
    add("thumb_r", (8.0, -3.5, 18.5), (1.0, 1.0, 2.0), skin_high)
    # Head: Barony/MC oversized cube (~1/4 height), freeblade scar + long tail hair
    # Shirt top z=37; short thick neck peg.
    add("neck", (0.0, 1.0, 38.5), (6.0, 6.0, 3.0), skin_shadow)
    add("jaw", (0.0, 0.5, 41.5), (14.0, 12.0, 3.0), skin_shadow)
    add("face_core", (0.0, 0.0, 46.5), (14.0, 13.0, 7.0), skin_mid)
    add("cranium", (0.0, 0.5, 51.5), (14.0, 13.0, 3.0), skin_mid)
    add("cheek_l", (-8.0, -3.0, 46.0), (2.0, 5.0, 4.0), skin_high)
    add("cheek_r", (8.0, -3.0, 46.0), (2.0, 5.0, 4.0), skin_high)
    add("chin", (0.0, -7.0, 41.5), (6.0, 3.0, 2.0), skin_high)
    add("ear_l", (-8.5, 1.5, 47.0), (3.0, 3.0, 4.0), skin_mid)
    add("ear_r", (8.5, 1.5, 47.0), (3.0, 3.0, 4.0), skin_mid)
    add("nose_bridge", (0.0, -7.5, 47.5), (3.0, 2.0, 4.0), skin_high)
    add("nose_tip", (0.0, -9.5, 45.5), (4.0, 2.0, 3.0), skin_mid)
    add("eye_l", (-3.5, -7.0, 48.5), (3.0, 1.0, 2.0), eye_lgt)
    add("eye_r", (3.5, -7.0, 48.5), (3.0, 1.0, 2.0), eye_lgt)
    add("pupil_l", (-3.5, -8.0, 48.5), (2.0, 1.0, 2.0), eye_dk)
    add("pupil_r", (3.5, -8.0, 48.5), (2.0, 1.0, 2.0), eye_dk)
    add("brow_l", (-3.5, -7.0, 50.0), (4.0, 1.0, 1.0), hair_mid)
    add("brow_r", (3.5, -7.0, 50.0), (4.0, 1.0, 1.0), hair_mid)
    # Scar on exterior brow plate over left eye.
    add("scar_brow", (-5.5, -8.0, 50.0), (1.0, 1.0, 2.0), scar)
    add("mouth", (0.0, -7.0, 44.5), (5.0, 1.0, 2.0), hair_deep)
    add("hair_crown", (0.0, 0.5, 54.0), (15.0, 14.0, 2.0), hair_mid)
    # Nape on +Y of cranium (back y=0.5+6.5=7).
    add("hair_nape", (0.0, 8.0, 50.5), (12.0, 2.0, 5.0), hair_deep)
    # Tied long tail hanging from nape bottom (nape z 48-53).
    add("hair_tail", (0.0, 8.0, 46.0), (5.0, 2.0, 4.0), hair_high)
    add("hair_tail_end", (0.0, 8.0, 42.5), (4.0, 2.0, 3.0), hair_mid)
    # Side hair above ears on cranium z-band only.
    add("hair_side_l", (-8.5, 2.0, 51.5), (3.0, 6.0, 3.0), hair_mid)
    add("hair_side_r", (8.5, 2.0, 51.5), (3.0, 5.0, 3.0), hair_mid)
    add("hair_forelock", (2.5, -8.0, 54.0), (5.0, 3.0, 2.0), hair_high)

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
    root, parts = build_player_scheme_b()
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
