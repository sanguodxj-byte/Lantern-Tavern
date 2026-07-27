from __future__ import annotations

"""Player scheme A — Lantern Keeper

Premium cellar host: teal split vest, wine apron, brass property key, warm linen sleeves, chestnut side-part hair. Practical tavern-dungeoneer silhouette with strong front/side depth.

Scale: 1m = 32px. Unarmed body only; equipment mounts at runtime sockets.
This file owns the complete silhouette, palette, semantic parts, and output identity.
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

MODEL_ID = "player_scheme_a"
TARGET_ENVELOPE_PX = (24.0, 59.0, 19.5)
ENVELOPE_TOLERANCE_PX = 1.0
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_player_scheme_a.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"
RENDER_STEM = "voxel_player_scheme_a"


def build_player_scheme_a() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    root = make_root("voxel_player_scheme_a")

    # Palette: deep teal vest, warm linen, wine apron, brass key, chestnut hair.
    vest_deep = make_material("A_Vest_Deep", (0.07, 0.18, 0.19, 1.0))
    vest_dark = make_material("A_Vest_Dark", (0.12, 0.28, 0.27, 1.0))
    vest_mid = make_material("A_Vest_Mid", (0.20, 0.42, 0.39, 1.0))
    vest_high = make_material("A_Vest_High", (0.34, 0.56, 0.50, 1.0))
    linen_shadow = make_material("A_Linen_Shadow", (0.40, 0.34, 0.26, 1.0))
    linen_mid = make_material("A_Linen_Mid", (0.62, 0.54, 0.42, 1.0))
    linen_high = make_material("A_Linen_High", (0.82, 0.72, 0.56, 1.0))
    apron_deep = make_material("A_Apron_Deep", (0.20, 0.08, 0.10, 1.0))
    apron_dark = make_material("A_Apron_Dark", (0.34, 0.14, 0.17, 1.0))
    apron_mid = make_material("A_Apron_Mid", (0.50, 0.22, 0.25, 1.0))
    apron_high = make_material("A_Apron_High", (0.68, 0.36, 0.34, 1.0))
    trouser_shadow = make_material("A_Trouser_Shadow", (0.10, 0.13, 0.15, 1.0))
    trouser_mid = make_material("A_Trouser_Mid", (0.18, 0.23, 0.25, 1.0))
    trouser_high = make_material("A_Trouser_High", (0.30, 0.36, 0.35, 1.0))
    leather_dark = make_material("A_Leather_Dark", (0.14, 0.09, 0.07, 1.0))
    leather_mid = make_material("A_Leather_Mid", (0.28, 0.18, 0.13, 1.0))
    leather_high = make_material("A_Leather_High", (0.46, 0.31, 0.21, 1.0))
    skin_shadow = make_material("A_Skin_Shadow", (0.42, 0.24, 0.18, 1.0))
    skin_mid = make_material("A_Skin_Mid", (0.64, 0.40, 0.30, 1.0))
    skin_high = make_material("A_Skin_High", (0.82, 0.55, 0.41, 1.0))
    hair_deep = make_material("A_Hair_Deep", (0.10, 0.07, 0.06, 1.0))
    hair_mid = make_material("A_Hair_Mid", (0.22, 0.14, 0.11, 1.0))
    hair_high = make_material("A_Hair_High", (0.36, 0.24, 0.17, 1.0))
    brass_dark = make_material("A_Brass_Dark", (0.42, 0.28, 0.10, 1.0), metallic=0.5)
    brass_mid = make_material("A_Brass_Mid", (0.72, 0.50, 0.18, 1.0), metallic=0.55)
    brass_high = make_material("A_Brass_High", (0.90, 0.72, 0.34, 1.0), metallic=0.5)
    eye_dark = make_material("A_Eye_Dark", (0.05, 0.06, 0.05, 1.0))
    eye_light = make_material("A_Eye_Light", (0.70, 0.78, 0.72, 1.0))

    parts: list[bpy.types.Object] = []

    def add(
        name: str,
        center_px: tuple[float, float, float],
        size_px: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> bpy.types.Object:
        part = cube_px(name, center_px, size_px, material)
        part.parent = root
        parts.append(part)
        return part

    # --- Legs / boots: solid primary masses with stepped toe ---
    add("boot_sole_l", (-3.5, -1.0, 1.0), (6.0, 10.0, 2.0), leather_dark)
    add("boot_toe_l", (-3.5, -6.5, 1.5), (6.0, 1.0, 1.0), leather_mid)
    add("boot_vamp_l", (-3.5, -0.5, 3.5), (6.0, 7.0, 3.0), leather_mid)
    add("boot_cuff_l", (-3.5, 0.5, 6.0), (6.0, 6.0, 2.0), leather_high)
    add("calf_l", (-3.5, 0.5, 11.0), (5.0, 6.0, 8.0), trouser_shadow)
    add("knee_l", (-3.5, 1.0, 16.5), (6.0, 7.0, 3.0), trouser_high)
    add("thigh_l", (-3.5, 1.0, 22.0), (6.0, 7.0, 8.0), trouser_mid)

    add("boot_sole_r", (3.5, -1.0, 1.0), (6.0, 10.0, 2.0), leather_dark)
    add("boot_toe_r", (3.5, -6.5, 1.5), (6.0, 1.0, 1.0), leather_mid)
    add("boot_vamp_r", (3.5, -0.5, 3.5), (6.0, 7.0, 3.0), leather_mid)
    add("boot_cuff_r", (3.5, 0.5, 6.0), (6.0, 6.0, 2.0), leather_high)
    add("calf_r", (3.5, 0.5, 11.0), (5.0, 6.0, 8.0), trouser_shadow)
    add("knee_r", (3.5, 1.0, 16.5), (6.0, 7.0, 3.0), trouser_high)
    add("thigh_r", (3.5, 1.0, 22.0), (6.0, 7.0, 8.0), trouser_mid)

    # --- Pelvis / apron: double-panel cellar apron + key ---
    add("pelvis_core", (0.0, 0.5, 27.5), (13.0, 8.0, 3.0), trouser_shadow)
    add("belt_wrap", (0.0, 0.5, 29.5), (13.0, 8.0, 1.0), leather_dark)
    add("belt_buckle", (0.0, -4.0, 29.5), (3.0, 1.0, 1.0), brass_mid)
    add("apron_bib", (0.0, -4.0, 32.0), (7.0, 1.0, 4.0), apron_dark)
    add("apron_panel_l", (-3.5, -4.0, 23.0), (5.0, 1.0, 10.0), apron_mid)
    add("apron_panel_r", (3.5, -4.0, 23.0), (5.0, 1.0, 10.0), apron_mid)
    add("apron_fold_r", (5.5, -5.0, 19.0), (2.0, 1.0, 2.0), apron_high)
    add("apron_side_l", (-7.0, 0.5, 28.0), (1.0, 6.0, 4.0), apron_deep)
    add("apron_side_r", (7.0, 0.5, 28.0), (1.0, 6.0, 4.0), apron_deep)
    add("apron_tie_back", (0.0, 5.5, 29.5), (7.0, 2.0, 1.0), apron_dark)
    add("key_ring", (-4.5, -5.0, 28.0), (1.0, 1.0, 1.0), brass_high)
    add("key_bow", (-4.5, -5.0, 26.5), (3.0, 1.0, 2.0), brass_mid)
    add("key_stem", (-4.5, -5.0, 23.5), (1.0, 1.0, 4.0), brass_dark)
    add("key_tooth", (-3.0, -5.0, 22.0), (2.0, 1.0, 1.0), brass_high)

    # --- Torso: shirt mass + split vest plates + shoulder yokes ---
    add("shirt_belly", (0.0, 0.5, 32.5), (7.0, 8.0, 5.0), linen_shadow)
    add("shirt_chest", (0.0, 0.5, 38.0), (7.0, 8.0, 6.0), linen_mid)
    add("vest_front_l", (-5.5, -0.5, 37.5), (4.0, 9.0, 9.0), vest_mid)
    add("vest_front_r", (5.5, -0.5, 37.5), (4.0, 9.0, 9.0), vest_mid)
    add("vest_lapel_l", (-4.0, -5.5, 38.5), (3.0, 1.0, 5.0), vest_high)
    add("vest_lapel_r", (4.0, -5.5, 38.5), (3.0, 1.0, 5.0), vest_high)
    add("vest_back", (0.0, 5.5, 38.0), (13.0, 2.0, 8.0), vest_deep)
    add("shoulder_yoke_l", (-6.5, 0.5, 43.0), (4.0, 8.0, 2.0), vest_dark)
    add("shoulder_yoke_r", (6.5, 0.5, 43.0), (4.0, 8.0, 2.0), vest_dark)
    add("collar_open", (0.0, -4.5, 40.0), (5.0, 2.0, 2.0), linen_high)

    # --- Arms: rolled sleeves, open hands ---
    add("upper_arm_l", (-9.5, 0.0, 37.0), (4.0, 6.0, 8.0), linen_mid)
    add("cuff_roll_l", (-9.5, 0.0, 31.5), (5.0, 7.0, 3.0), linen_high)
    add("forearm_l", (-9.5, 0.5, 27.0), (4.0, 5.0, 6.0), skin_mid)
    add("hand_l", (-9.5, 0.0, 21.5), (4.0, 6.0, 5.0), skin_mid)
    add("thumb_l", (-8.0, -3.5, 21.5), (1.0, 1.0, 2.0), skin_high)

    add("upper_arm_r", (9.5, 0.0, 37.0), (4.0, 6.0, 8.0), linen_mid)
    add("cuff_roll_r", (9.5, 0.0, 31.5), (5.0, 7.0, 3.0), linen_high)
    add("forearm_r", (9.5, 0.5, 27.0), (4.0, 5.0, 6.0), skin_mid)
    add("hand_r", (9.5, 0.0, 21.5), (4.0, 6.0, 5.0), skin_mid)
    add("thumb_r", (8.0, -3.5, 21.5), (1.0, 1.0, 2.0), skin_high)

    # --- Head: Barony/MC oversized primary mass (head ~1/4 height, width ≈ shoulders) ---
    # Short thick neck peg.
    add("neck", (0.0, 1.0, 42.5), (6.0, 6.0, 3.0), skin_shadow)
    # Wide jaw shelf (bottom of big head cube stack).
    add("jaw", (0.0, 0.5, 45.5), (14.0, 12.0, 3.0), skin_shadow)
    # Primary face cube — the Barony/MC read-from-distance mass.
    add("face_core", (0.0, 0.0, 50.5), (14.0, 13.0, 7.0), skin_mid)
    # Cranium top slab.
    add("cranium", (0.0, 0.5, 55.5), (14.0, 13.0, 3.0), skin_mid)
    # Exterior cheek plates on ±X of face_core (half-x=7).
    add("cheek_l", (-8.0, -3.0, 50.0), (2.0, 5.0, 4.0), skin_high)
    add("cheek_r", (8.0, -3.0, 50.0), (2.0, 5.0, 4.0), skin_high)
    # Chin on exterior -Y of jaw (jaw half-y=6, center y=0.5 → front face y=-5.5).
    add("chin", (0.0, -7.0, 45.5), (6.0, 3.0, 2.0), skin_high)
    # Ears on exterior ±X of face_core.
    add("ear_l", (-8.5, 1.5, 51.0), (3.0, 3.0, 4.0), skin_mid)
    add("ear_r", (8.5, 1.5, 51.0), (3.0, 3.0, 4.0), skin_mid)
    # Large nose stack on exterior -Y of face_core (half-y=6.5).
    add("nose_bridge", (0.0, -7.5, 51.5), (3.0, 2.0, 4.0), skin_high)
    add("nose_tip", (0.0, -9.5, 49.5), (4.0, 2.0, 3.0), skin_mid)
    # Big MC eyes on face front.
    add("eye_l", (-3.5, -7.0, 52.5), (3.0, 1.0, 2.0), eye_light)
    add("eye_r", (3.5, -7.0, 52.5), (3.0, 1.0, 2.0), eye_light)
    add("pupil_l", (-3.5, -8.0, 52.5), (2.0, 1.0, 2.0), eye_dark)
    add("pupil_r", (3.5, -8.0, 52.5), (2.0, 1.0, 2.0), eye_dark)
    add("brow_l", (-3.5, -7.0, 54.0), (4.0, 1.0, 1.0), hair_mid)
    add("brow_r", (3.5, -7.0, 54.0), (4.0, 1.0, 1.0), hair_mid)
    # Mouth on exterior -Y of jaw/face junction.
    add("mouth", (0.0, -7.0, 48.5), (5.0, 1.0, 2.0), hair_deep)
    # Hair: crown on +Z of cranium only; sides/nape/forelock pure exterior plates.
    add("hair_crown", (0.0, 0.5, 58.0), (15.0, 14.0, 2.0), hair_mid)
    # Nape on +Y of cranium (cranium back y=0.5+6.5=7).
    add("hair_nape", (0.0, 8.0, 54.5), (12.0, 2.0, 5.0), hair_deep)
    # Side hair above ears on ±X of cranium only (cranium z 54-57).
    add("hair_side_l", (-8.5, 2.0, 55.5), (3.0, 6.0, 3.0), hair_mid)
    add("hair_side_r", (8.5, 2.0, 55.5), (3.0, 5.0, 3.0), hair_mid)
    # Forelock on -Y of hair_crown (crown front y=0.5-7=-6.5).
    add("hair_forelock", (2.5, -8.0, 58.0), (5.0, 3.0, 2.0), hair_high)

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
    root, parts = build_player_scheme_a()
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
    print(f"Envelope target: {TARGET_ENVELOPE_PX}px; front: Blender -Y")


if __name__ == "__main__":
    main()
