#!/usr/bin/env python3
"""Generate the authentic Kobold character voxel asset (Redesigned per Reference).

Classic D&D / Barony-style Kobold:
A small, hunched canine-lizard creature featuring:
- Forward-extending multi-tiered canine muzzle with black nose and sharp white fangs
- Large flared canine ears with inner highlights
- Head-mounted glowing candle tied with leather rope strap ("You shall not take candle!")
- Hunched posture with leather backpack and leather straps
- Digitigrade/crouched legs, tail, and clawed hands
- Fully compliant with the equipment system (no built-in hand-held weapons).
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from pathlib import Path
import sys

import bpy

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from voxel_humanoid_rig import (  # noqa: E402
    create_voxel_humanoid_armature,
    parent_parts_by_bone,
)
from voxel_character_rig import build_all_actions, build_weapon_actions, export_glb as export_rig_glb  # noqa: E402
from voxel_model_primitives import (  # noqa: E402
    bounds_center_scale,
    cube_px,
    export_glb,
    make_material,
    make_root,
    render_real_views,
    reset_scene,
    setup_lights_and_camera,
)
from voxel_overlap_guard import (  # noqa: E402
    assert_parts_no_positive_volume_overlap,
    assert_parts_single_face_connected_component,
)

MODEL_ID = "kobold"
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_kobold_42px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_kobold_42px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


@dataclass(frozen=True)
class PartSpec:
    name: str
    center_px: tuple[float, float, float]
    size_px: tuple[float, float, float]
    material_key: str
    bone: str


PART_SPECS: tuple[PartSpec, ...] = (
    # ===== Crouched Legs & Feet =====
    PartSpec("foot_left", (-4.0, -1.0, 1.0), (4.0, 6.0, 2.0), "skin_dark_red", "Foot.L"),
    PartSpec("toes_left", (-4.0, -4.5, 1.0), (4.0, 1.0, 2.0), "bone_white", "Foot.L"),
    PartSpec("shank_left", (-4.0, 1.5, 5.0), (3.0, 3.0, 6.0), "skin_red", "LowerLeg.L"),
    PartSpec("thigh_left", (-3.5, 0.5, 11.5), (4.0, 5.0, 7.0), "skin_red", "UpperLeg.L"),

    PartSpec("foot_right", (4.0, -1.0, 1.0), (4.0, 6.0, 2.0), "skin_dark_red", "Foot.R"),
    PartSpec("toes_right", (4.0, -4.5, 1.0), (4.0, 1.0, 2.0), "bone_white", "Foot.R"),
    PartSpec("shank_right", (4.0, 1.5, 5.0), (3.0, 3.0, 6.0), "skin_red", "LowerLeg.R"),
    PartSpec("thigh_right", (3.5, 0.5, 11.5), (4.0, 5.0, 7.0), "skin_red", "UpperLeg.R"),

    # ===== Tail (curved back down Y=+12.0) =====
    PartSpec("tail_base", (0.0, 3.5, 13.5), (3.0, 3.0, 3.0), "skin_dark_red", "Pelvis"),
    PartSpec("tail_mid", (0.0, 6.0, 11.5), (3.0, 2.0, 3.0), "skin_red", "Pelvis"),
    PartSpec("tail_tip", (0.0, 8.0, 9.5), (2.0, 2.0, 3.0), "skin_dark_red", "Pelvis"),

    # ===== Pelvis, Loincloth & Belly =====
    PartSpec("pelvis_core", (0.0, 0.0, 15.0), (8.0, 6.0, 4.0), "skin_red", "Pelvis"),
    PartSpec("loincloth_front", (0.0, -3.5, 14.0), (6.0, 1.0, 5.0), "leather_brown", "Pelvis"),
    PartSpec("belly_chest_under", (0.0, -3.5, 18.0), (6.0, 1.0, 3.0), "skin_tan", "Pelvis"),

    # ===== Hunched Torso, Backpack & Straps =====
    PartSpec("torso_core", (0.0, -0.5, 22.0), (8.0, 6.0, 10.0), "skin_red", "Torso"),
    PartSpec("belly_upper_tan", (0.0, -4.0, 22.5), (6.0, 1.0, 7.0), "skin_tan", "Torso"),
    # Backpack on hunched back (Y=+3.5 to Y=+7.5)
    PartSpec("backpack_main", (0.0, 4.5, 23.0), (7.0, 4.0, 7.0), "leather_dark", "Torso"),
    PartSpec("backpack_flap", (0.0, 4.5, 27.0), (7.0, 4.0, 1.0), "leather_brown", "Torso"),
    PartSpec("backpack_strap_left", (-3.5, -0.5, 23.0), (1.0, 6.0, 10.0), "leather_brown", "Torso"),
    PartSpec("backpack_strap_right", (3.5, -0.5, 23.0), (1.0, 6.0, 10.0), "leather_brown", "Torso"),

    # ===== Long Lanky Arms & Claws (Hanging near knees) =====
    PartSpec("shoulder_left", (-5.5, -0.5, 24.5), (3.0, 4.0, 4.0), "skin_red", "UpperArm.L"),
    PartSpec("upper_arm_left", (-5.5, -1.5, 20.5), (3.0, 3.0, 4.0), "skin_red", "UpperArm.L"),
    PartSpec("forearm_left", (-6.0, -2.5, 15.5), (3.0, 3.0, 6.0), "skin_red", "LowerArm.L"),
    PartSpec("hand_left", (-6.0, -4.5, 11.5), (3.0, 3.0, 3.0), "skin_dark_red", "Hand.L"),
    PartSpec("claws_left", (-6.0, -6.0, 11.5), (2.0, 1.0, 2.0), "bone_white", "Hand.L"),

    PartSpec("shoulder_right", (5.5, -0.5, 24.5), (3.0, 4.0, 4.0), "skin_red", "UpperArm.R"),
    PartSpec("upper_arm_right", (5.5, -1.5, 20.5), (3.0, 3.0, 4.0), "skin_red", "UpperArm.R"),
    PartSpec("forearm_right", (6.0, -2.5, 15.5), (3.0, 3.0, 6.0), "skin_red", "LowerArm.R"),
    PartSpec("hand_right", (6.0, -4.5, 11.5), (3.0, 3.0, 3.0), "skin_dark_red", "Hand.R"),
    PartSpec("claws_right", (6.0, -6.0, 11.5), (2.0, 1.0, 2.0), "bone_white", "Hand.R"),

    # ===== Neck =====
    PartSpec("neck_joint", (0.0, -2.0, 27.5), (4.0, 4.0, 3.0), "skin_dark_red", "Neck"),

    # ===== HEAD (Canine Muzzle, Eyes, Fangs, Ears) =====
    # Cranium (Back of head)
    PartSpec("skull_cranium", (0.0, -1.0, 32.0), (7.0, 6.0, 6.0), "skin_red", "Head"),
    PartSpec("skull_brow", (0.0, -4.5, 33.5), (7.0, 1.0, 2.0), "skin_dark_red", "Head"),
    
    # Canine Muzzle (Extending forward Y=-4.0 to Y=-11.0)
    PartSpec("muzzle_base", (0.0, -5.5, 31.0), (5.0, 3.0, 3.0), "skin_red", "Head"),
    PartSpec("muzzle_mid", (0.0, -8.0, 30.5), (4.0, 2.0, 2.5), "skin_red", "Head"),
    PartSpec("muzzle_tip", (0.0, -9.5, 30.0), (3.0, 1.0, 2.0), "skin_tan", "Head"),
    PartSpec("black_nose", (0.0, -10.5, 30.5), (2.0, 1.0, 1.0), "nose_black", "Head"),

    # Jaw & Fangs
    PartSpec("jaw_lower", (0.0, -6.5, 28.5), (4.0, 5.0, 2.0), "skin_dark_red", "Head"),
    PartSpec("fang_left", (-1.5, -8.0, 29.5), (1.0, 1.0, 1.0), "bone_white", "Head"),
    PartSpec("fang_right", (1.5, -8.0, 29.5), (1.0, 1.0, 1.0), "bone_white", "Head"),

    # Glowing Red Eyes
    PartSpec("eye_socket_left", (-3.0, -4.5, 32.5), (1.0, 1.0, 2.0), "skin_dark_red", "Head"),
    PartSpec("eye_socket_right", (3.0, -4.5, 32.5), (1.0, 1.0, 2.0), "skin_dark_red", "Head"),
    PartSpec("eye_glow_left", (-3.0, -5.0, 32.5), (1.0, 1.0, 1.0), "eye_red_glow", "Head"),
    PartSpec("eye_glow_right", (3.0, -5.0, 32.5), (1.0, 1.0, 1.0), "eye_red_glow", "Head"),

    # Large Flared Canine Ears (Extending Out & Back X=±6.5, Y=+1.0, Z=34.0)
    PartSpec("ear_base_left", (-4.5, 0.0, 33.5), (2.0, 3.0, 3.0), "skin_dark_red", "Head"),
    PartSpec("ear_mid_left", (-6.5, 1.5, 34.5), (2.0, 3.0, 3.0), "skin_red", "Head"),
    PartSpec("ear_inner_left", (-6.5, 1.0, 34.5), (1.0, 2.0, 2.0), "skin_tan", "Head"),
    PartSpec("ear_tip_left", (-8.0, 3.0, 35.5), (1.0, 2.0, 2.0), "skin_dark_red", "Head"),

    PartSpec("ear_base_right", (4.5, 0.0, 33.5), (2.0, 3.0, 3.0), "skin_dark_red", "Head"),
    PartSpec("ear_mid_right", (6.5, 1.5, 34.5), (2.0, 3.0, 3.0), "skin_red", "Head"),
    PartSpec("ear_inner_right", (6.5, 1.0, 34.5), (1.0, 2.0, 2.0), "skin_tan", "Head"),
    PartSpec("ear_tip_right", (8.0, 3.0, 35.5), (1.0, 2.0, 2.0), "skin_dark_red", "Head"),

    # ===== Head-Mounted Candle ("You shall not take candle!") =====
    PartSpec("candle_rope_strap", (0.0, -1.0, 35.5), (7.0, 6.0, 1.0), "leather_dark", "Head"),
    PartSpec("candle_base", (0.0, -1.0, 36.5), (3.0, 3.0, 1.0), "leather_brown", "Head"),
    PartSpec("candle_wax", (0.0, -1.0, 38.5), (2.0, 2.0, 3.0), "candle_wax_mat", "Head"),
    PartSpec("candle_wick", (0.0, -1.0, 40.5), (1.0, 1.0, 1.0), "nose_black", "Head"),
    PartSpec("flame_core", (0.0, -1.0, 42.0), (2.0, 2.0, 2.0), "flame_orange", "Head"),
    PartSpec("flame_tip", (0.0, -1.0, 43.5), (1.0, 1.0, 1.0), "flame_yellow", "Head"),
)

AUTHORED_PART_COUNT = len(PART_SPECS)


def _compute_envelope(parts: tuple[PartSpec, ...]) -> tuple[float, float, float]:
    min_x = min(p.center_px[0] - p.size_px[0] / 2.0 for p in parts)
    max_x = max(p.center_px[0] + p.size_px[0] / 2.0 for p in parts)
    min_y = min(p.center_px[1] - p.size_px[1] / 2.0 for p in parts)
    max_y = max(p.center_px[1] + p.size_px[1] / 2.0 for p in parts)
    min_z = min(p.center_px[2] - p.size_px[2] / 2.0 for p in parts)
    max_z = max(p.center_px[2] + p.size_px[2] / 2.0 for p in parts)
    return (max_x - min_x, max_z - min_z, max_y - min_y)


TARGET_ENVELOPE_PX = _compute_envelope(PART_SPECS)


def _build_palette() -> dict[str, bpy.types.Material]:
    return {
        "skin_red": make_material("skin_red", (0.55, 0.16, 0.12, 1.0), roughness=0.6),
        "skin_dark_red": make_material("skin_dark_red", (0.35, 0.10, 0.08, 1.0), roughness=0.7),
        "skin_tan": make_material("skin_tan", (0.80, 0.62, 0.38, 1.0), roughness=0.5),
        "bone_white": make_material("bone_white", (0.85, 0.82, 0.72, 1.0), roughness=0.4),
        "nose_black": make_material("nose_black", (0.05, 0.05, 0.05, 1.0), roughness=0.8),
        "eye_red_glow": make_material("eye_red_glow", (1.00, 0.15, 0.05, 1.0), roughness=0.1),
        "leather_brown": make_material("leather_brown", (0.35, 0.20, 0.10, 1.0), roughness=0.8),
        "leather_dark": make_material("leather_dark", (0.18, 0.11, 0.06, 1.0), roughness=0.85),
        "candle_wax_mat": make_material("candle_wax_mat", (0.92, 0.88, 0.75, 1.0), roughness=0.3),
        "flame_orange": make_material("flame_orange", (1.00, 0.45, 0.05, 1.0), roughness=0.1),
        "flame_yellow": make_material("flame_yellow", (1.00, 0.85, 0.20, 1.0), roughness=0.1),
    }


def build_kobold_mesh() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
    reset_scene()
    materials = _build_palette()
    root = make_root(f"voxel_{MODEL_ID}")
    parts: list[bpy.types.Object] = []
    parts_by_bone: dict[str, list[bpy.types.Object]] = {}

    for spec in PART_SPECS:
        mat = materials[spec.material_key]
        cube = cube_px(spec.name, spec.center_px, spec.size_px, mat)
        cube.parent = root
        parts.append(cube)
        parts_by_bone.setdefault(spec.bone, []).append(cube)

    return root, parts, parts_by_bone


def main() -> None:
    parts = tuple({
        "name": p.name,
        "center_px": p.center_px,
        "size_px": p.size_px,
    } for p in PART_SPECS)

    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_single_face_connected_component(parts, label=MODEL_ID)

    # 1. Export Static GLB
    root, parts_objs, parts_by_bone = build_kobold_mesh()
    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    STATIC_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(root, STATIC_OUTPUT)

    # 2. Export Rigged GLB
    root, parts_objs, parts_by_bone = build_kobold_mesh()
    armature = create_voxel_humanoid_armature(height_px=44.0, name="Armature")
    parent_parts_by_bone(parts_by_bone, armature)
    build_all_actions(armature)
    build_weapon_actions(armature)
    RIG_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_rig_glb(RIG_OUTPUT)

    # 3. Render 3D Views
    root, parts_objs, _ = build_kobold_mesh()
    center, scale = bounds_center_scale(root)
    camera = setup_lights_and_camera(center, scale)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    render_real_views(
        PREVIEW_DIR,
        f"voxel_{MODEL_ID}",
        center,
        scale,
        camera,
    )
    print(
        f"Parts: {len(PART_SPECS)}; envelope: {_compute_envelope(PART_SPECS)}px; front: Blender -Y"
    )
    print(f"Wrote {STATIC_OUTPUT}")
    print(f"Wrote {RIG_OUTPUT}")


if __name__ == "__main__":
    main()
