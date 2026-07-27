from __future__ import annotations

"""Player scheme C — Lantern Initiate

Mystic initiate: indigo hooded robes, gold sash, leg wraps, soft boots, pale skin, chest rune glow.

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

MODEL_ID = "player_scheme_c"
TARGET_ENVELOPE_PX = (24.0, 56.0, 19.5)
ENVELOPE_TOLERANCE_PX = 1.0
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_player_scheme_c.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"
RENDER_STEM = "voxel_player_scheme_c"


def build_player_scheme_c() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    root = make_root("voxel_player_scheme_c")

    robe_deep = make_material("C_Robe_Deep", (0.08, 0.08, 0.16, 1.0))
    robe_dark = make_material("C_Robe_Dark", (0.14, 0.14, 0.28, 1.0))
    robe_mid = make_material("C_Robe_Mid", (0.22, 0.24, 0.42, 1.0))
    robe_high = make_material("C_Robe_High", (0.34, 0.38, 0.58, 1.0))
    sash_mid = make_material("C_Sash_Mid", (0.55, 0.42, 0.18, 1.0))
    sash_high = make_material("C_Sash_High", (0.75, 0.60, 0.28, 1.0))
    wrap_dark = make_material("C_Wrap_Dark", (0.18, 0.16, 0.14, 1.0))
    wrap_mid = make_material("C_Wrap_Mid", (0.32, 0.28, 0.24, 1.0))
    boot_dark = make_material("C_Boot_Dark", (0.12, 0.10, 0.10, 1.0))
    boot_mid = make_material("C_Boot_Mid", (0.24, 0.18, 0.16, 1.0))
    skin_shadow = make_material("C_Skin_Shadow", (0.48, 0.36, 0.32, 1.0))
    skin_mid = make_material("C_Skin_Mid", (0.72, 0.56, 0.48, 1.0))
    skin_high = make_material("C_Skin_High", (0.88, 0.72, 0.62, 1.0))
    hood_deep = make_material("C_Hood_Deep", (0.06, 0.06, 0.12, 1.0))
    hood_mid = make_material("C_Hood_Mid", (0.12, 0.12, 0.22, 1.0))
    eye_lgt = make_material("C_Eye", (0.55, 0.72, 0.85, 1.0))
    eye_dk = make_material("C_Pupil", (0.08, 0.12, 0.18, 1.0))
    rune = make_material("C_Rune", (0.45, 0.70, 0.95, 1.0), emission=0.35)

    parts: list[bpy.types.Object] = []

    def add(name, center_px, size_px, material):
        part = cube_px(name, center_px, size_px, material)
        part.parent = root
        parts.append(part)
        return part

    add("boot_l", (-3.0, 0.0, 1.5), (5.0, 8.0, 3.0), boot_dark)
    add("boot_toe_l", (-3.0, -4.5, 1.0), (5.0, 1.0, 1.0), boot_mid)
    add("wrap_l", (-3.0, 0.5, 7.0), (5.0, 6.0, 8.0), wrap_dark)
    add("thigh_l", (-3.0, 1.0, 15.5), (5.0, 7.0, 9.0), wrap_mid)
    add("boot_r", (3.0, 0.0, 1.5), (5.0, 8.0, 3.0), boot_dark)
    add("boot_toe_r", (3.0, -4.5, 1.0), (5.0, 1.0, 1.0), boot_mid)
    add("wrap_r", (3.0, 0.5, 7.0), (5.0, 6.0, 8.0), wrap_dark)
    add("thigh_r", (3.0, 1.0, 15.5), (5.0, 7.0, 9.0), wrap_mid)
    add("pelvis", (0.0, 0.5, 22.0), (12.0, 8.0, 4.0), robe_dark)
    add("sash", (0.0, 0.5, 24.5), (12.0, 8.0, 1.0), sash_mid)
    add("sash_knot", (2.5, -4.5, 24.0), (3.0, 2.0, 2.0), sash_high)
    add("robe_skirt_f", (0.0, -4.0, 16.0), (11.0, 1.0, 12.0), robe_mid)
    add("robe_skirt_b", (0.0, 5.0, 16.0), (11.0, 1.0, 12.0), robe_deep)
    add("robe_torso", (0.0, 0.5, 31.0), (11.0, 9.0, 12.0), robe_mid)
    add("robe_chest_panel", (0.0, -4.5, 33.0), (5.0, 1.0, 6.0), robe_high)
    add("rune_mark", (0.0, -5.5, 34.0), (2.0, 1.0, 2.0), rune)
    add("shoulder_l", (-7.5, 0.5, 37.5), (4.0, 8.0, 3.0), robe_dark)
    add("shoulder_r", (7.5, 0.5, 37.5), (4.0, 8.0, 3.0), robe_dark)
    add("sleeve_l", (-9.5, 0.0, 33.0), (4.0, 6.0, 6.0), robe_mid)
    add("cuff_l", (-9.5, 0.0, 28.5), (5.0, 7.0, 3.0), robe_high)
    add("fore_l", (-9.5, 0.5, 24.0), (4.0, 5.0, 6.0), skin_mid)
    add("hand_l", (-9.5, 0.0, 18.5), (4.0, 6.0, 5.0), skin_mid)
    add("thumb_l", (-8.0, -3.5, 18.5), (1.0, 1.0, 2.0), skin_high)
    add("sleeve_r", (9.5, 0.0, 33.0), (4.0, 6.0, 6.0), robe_mid)
    add("cuff_r", (9.5, 0.0, 28.5), (5.0, 7.0, 3.0), robe_high)
    add("fore_r", (9.5, 0.5, 24.0), (4.0, 5.0, 6.0), skin_mid)
    add("hand_r", (9.5, 0.0, 18.5), (4.0, 6.0, 5.0), skin_mid)
    add("thumb_r", (8.0, -3.5, 18.5), (1.0, 1.0, 2.0), skin_high)
    # Head: Barony/MC oversized cube under indigo hood
    # Shoulder top z~39; short thick neck peg.
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
    add("brow_l", (-3.5, -7.0, 50.0), (4.0, 1.0, 1.0), hood_deep)
    add("brow_r", (3.5, -7.0, 50.0), (4.0, 1.0, 1.0), hood_deep)
    add("mouth", (0.0, -7.0, 44.5), (5.0, 1.0, 2.0), hood_deep)
    # Hood wraps exterior of big head only — no volume intrusion.
    # Cranium top z=53 → hood crown sits on +Z.
    # Crown depth matches cranium back y=7 exactly (size_y=13, center 0.5).
    add("hood_crown", (0.0, 0.5, 54.5), (16.0, 13.0, 3.0), hood_mid)
    # Back slab: front y=7 face-contacts cranium/crown; top z=53 face-contacts crown bottom.
    add("hood_back", (0.0, 8.0, 49.5), (14.0, 2.0, 7.0), hood_deep)
    # Side cowls on cranium z-band, extend to back face y=7.
    add("hood_side_l", (-8.5, 3.0, 51.5), (3.0, 8.0, 3.0), hood_mid)
    add("hood_side_r", (8.5, 3.0, 51.5), (3.0, 8.0, 3.0), hood_mid)
    # Brims on -Y of hood_crown (front y=0.5-6.5=-6).
    add("hood_brim_l", (-4.5, -7.0, 53.5), (4.0, 2.0, 2.0), hood_deep)
    add("hood_brim_r", (4.5, -7.0, 53.5), (4.0, 2.0, 2.0), hood_deep)
    # Lower cowl drop from hood_back bottom (z=46).
    add("hood_cowl", (0.0, 8.0, 44.5), (10.0, 2.0, 3.0), hood_mid)

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
    root, parts = build_player_scheme_c()
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
