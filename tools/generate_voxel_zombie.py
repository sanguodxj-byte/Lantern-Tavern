#!/usr/bin/env python3
"""Generate the zombie character voxel asset (Completely Remade High Quality).

Barony-style authored voxel zombie with dislocated tilted jaw, decayed yellow teeth,
broken ribcage with deep cavity, glowing toxic guts core, tattered split shroud,
and forward-extended claws.
No hand-held weapons built-in per equipment system rule.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from voxel_humanoid_rig import (  # noqa: E402
    create_voxel_humanoid_armature,
    parent_parts_by_bone,
)
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

MODEL_ID = "zombie"
TARGET_ENVELOPE_PX = (22.0, 49.5, 19.5)
HEAD_ENVELOPE_PX = (16.0, 16.0, 16.0)
AUTHORED_PART_COUNT = 50
MIN_SOLID_ENVELOPE_RATIO = 0.12
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_zombie_52px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_zombie_52px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


@dataclass(frozen=True)
class PartSpec:
    name: str
    center_px: tuple[float, float, float]
    size_px: tuple[float, float, float]
    material_key: str
    bone: str


PART_SPECS: tuple[PartSpec, ...] = (
    # Feet and torn uneven legs.
    PartSpec("foot_left_heel", (-5.0, 1.0, 2.0), (5.0, 5.0, 4.0), "skin_decay_dark", "Foot.L"),
    PartSpec("foot_left_toe", (-5.0, -3.0, 2.0), (5.0, 3.0, 3.0), "skin_decay_mid", "Foot.L"),
    PartSpec("shin_left", (-5.0, 0.5, 8.0), (5.0, 5.0, 8.0), "skin_decay_mid", "LowerLeg.L"),
    PartSpec("knee_left", (-5.0, -1.0, 13.0), (5.0, 4.0, 2.0), "skin_decay_dark", "UpperLeg.L"),
    PartSpec("thigh_left", (-4.5, 0.5, 18.0), (6.0, 6.0, 8.0), "cloth_rag_dark", "UpperLeg.L"),

    PartSpec("foot_right_heel", (5.0, 1.0, 2.0), (5.0, 5.0, 4.0), "skin_decay_mid", "Foot.R"),
    PartSpec("foot_right_toe", (5.0, -3.0, 2.0), (5.0, 3.0, 3.0), "skin_decay_dark", "Foot.R"),
    PartSpec("shin_right", (5.0, 0.5, 8.0), (5.0, 5.0, 8.0), "skin_decay_dark", "LowerLeg.R"),
    PartSpec("knee_right", (5.0, -1.0, 13.0), (5.0, 4.0, 2.0), "skin_decay_mid", "UpperLeg.R"),
    PartSpec("thigh_right", (4.5, 0.5, 18.0), (6.0, 6.0, 8.0), "cloth_rag_mid", "UpperLeg.R"),

    # Pelvis, belt remnant, and stepped tattered shroud strips.
    PartSpec("pelvis_core", (0.0, 0.5, 23.0), (12.0, 7.0, 4.0), "skin_decay_dark", "Pelvis"),
    PartSpec("shroud_front_left", (-4.0, -3.5, 21.0), (4.0, 1.0, 6.0), "cloth_rag_mid", "Pelvis"),
    PartSpec("shroud_front_right", (4.0, -3.5, 20.0), (4.0, 1.0, 8.0), "cloth_rag_dark", "Pelvis"),
    PartSpec("shroud_side_left", (-6.5, 0.5, 21.0), (1.0, 5.0, 6.0), "cloth_rag_dark", "Pelvis"),
    PartSpec("shroud_side_right", (6.5, 0.5, 22.0), (1.0, 5.0, 4.0), "cloth_rag_mid", "Pelvis"),

    # Decaying Torso with deep hollow cavity, broken ribs, & glowing toxic guts.
    PartSpec("torso_back", (0.0, 3.0, 32.0), (12.0, 2.0, 12.0), "skin_decay_dark", "Torso"),
    PartSpec("torso_left_flank", (-5.0, 0.5, 32.0), (2.0, 5.0, 12.0), "skin_decay_mid", "Torso"),
    PartSpec("torso_right_flank", (5.0, 0.5, 32.0), (2.0, 5.0, 12.0), "skin_decay_dark", "Torso"),
    PartSpec("chest_shirt_left", (-3.5, -2.5, 35.0), (4.0, 1.0, 6.0), "cloth_rag_mid", "Torso"),
    PartSpec("chest_shirt_right", (3.5, -2.5, 36.0), (4.0, 1.0, 4.0), "cloth_rag_dark", "Torso"),

    # Deep Hollow Inner Cavity & Exposed Broken Ribs.
    PartSpec("inner_cavity_dark", (0.0, 0.5, 31.0), (8.0, 3.0, 8.0), "cavity_black", "Torso"),
    PartSpec("rib_broken_upper", (-2.0, -2.5, 34.0), (4.0, 1.0, 1.0), "bone_decayed", "Torso"),
    PartSpec("rib_broken_mid", (2.0, -2.5, 32.0), (4.0, 1.0, 1.0), "bone_decayed", "Torso"),
    PartSpec("rib_broken_lower", (-2.5, -2.5, 30.0), (3.0, 1.0, 1.0), "bone_decayed", "Torso"),

    # Glowing Toxic Guts Core (High emission & multi-layered volume).
    PartSpec("guts_toxic_main", (0.5, -1.0, 29.0), (5.0, 3.0, 4.0), "toxic_guts_glow", "Torso"),
    PartSpec("guts_toxic_drip", (1.5, -2.5, 27.5), (3.0, 1.0, 3.0), "toxic_guts_glow", "Torso"),

    # Dislocated Skull, crooked jaw, decayed teeth & asymmetric eyes.
    PartSpec("neck_core", (0.0, 0.5, 39.0), (6.0, 5.0, 2.0), "skin_decay_dark", "Neck"),
    PartSpec("head_cranium_main", (0.0, 0.5, 45.0), (9.0, 8.0, 8.0), "skin_decay_mid", "Head"),
    PartSpec("head_temple_left", (-5.0, 0.5, 45.0), (1.0, 6.0, 6.0), "skin_decay_dark", "Head"),
    PartSpec("jaw_dislocated_left", (-2.0, -3.5, 41.5), (5.0, 3.0, 3.0), "skin_decay_dark", "Head"),
    PartSpec("jaw_dislocated_right", (3.0, -4.5, 41.0), (4.0, 3.0, 3.0), "skin_decay_mid", "Head"),
    PartSpec("tooth_rot_1", (-2.5, -5.0, 43.0), (1.0, 1.0, 2.0), "bone_decayed", "Head"),
    PartSpec("tooth_rot_2", (-1.0, -5.0, 43.0), (1.0, 1.0, 1.0), "bone_decayed", "Head"),
    PartSpec("tooth_rot_3", (1.5, -5.5, 42.5), (1.0, 1.0, 2.0), "bone_decayed", "Head"),
    PartSpec("eye_socket_empty", (-2.5, -4.0, 46.0), (3.0, 1.0, 2.0), "cavity_black", "Head"),
    PartSpec("eye_glowing_toxic", (2.5, -4.0, 46.0), (2.0, 1.0, 2.0), "toxic_guts_glow", "Head"),
    PartSpec("hair_tuft_back", (0.0, 4.5, 48.0), (7.0, 1.0, 3.0), "cloth_rag_dark", "Head"),
    PartSpec("hair_tuft_side", (-4.5, 1.5, 48.5), (2.0, 4.0, 2.0), "cloth_rag_mid", "Head"),

    # Rigid forward-extended Left Arm & Clawed Hand (Reaching Y = -14.0px).
    PartSpec("shoulder_left", (-8.5, 0.5, 36.0), (5.0, 6.0, 4.0), "cloth_rag_mid", "UpperArm.L"),
    PartSpec("upper_arm_left", (-8.5, -2.5, 35.0), (4.0, 6.0, 4.0), "skin_decay_mid", "UpperArm.L"),
    PartSpec("forearm_left", (-8.5, -7.5, 35.0), (4.0, 6.0, 4.0), "skin_decay_dark", "LowerArm.L"),
    PartSpec("hand_left_palm", (-8.5, -11.5, 35.0), (4.0, 4.0, 4.0), "skin_decay_mid", "Hand.L"),
    PartSpec("hand_left_claw_thumb", (-6.0, -13.5, 34.5), (1.0, 2.0, 2.0), "bone_decayed", "Hand.L"),
    PartSpec("hand_left_claw_fingers", (-9.0, -13.5, 35.0), (3.0, 2.0, 3.0), "bone_decayed", "Hand.L"),

    # Rigid forward-extended Right Arm & Clawed Hand (Reaching Y = -14.0px).
    PartSpec("shoulder_right", (8.5, 0.5, 36.0), (5.0, 6.0, 4.0), "cloth_rag_dark", "UpperArm.R"),
    PartSpec("upper_arm_right", (8.5, -2.5, 35.0), (4.0, 6.0, 4.0), "skin_decay_dark", "UpperArm.R"),
    PartSpec("forearm_right", (8.5, -7.5, 35.0), (4.0, 6.0, 4.0), "skin_decay_mid", "LowerArm.R"),
    PartSpec("hand_right_palm", (8.5, -11.5, 35.0), (4.0, 4.0, 4.0), "skin_decay_dark", "Hand.R"),
    PartSpec("hand_right_claw_thumb", (6.0, -13.5, 34.5), (1.0, 2.0, 2.0), "bone_decayed", "Hand.R"),
    PartSpec("hand_right_claw_fingers", (9.0, -13.5, 35.0), (3.0, 2.0, 3.0), "bone_decayed", "Hand.R"),
)


def _build_palette() -> dict[str, bpy.types.Material]:
    return {
        "skin_decay_mid": make_material("skin_decay_mid", (0.32, 0.42, 0.32, 1.0), roughness=0.8),
        "skin_decay_dark": make_material("skin_decay_dark", (0.18, 0.25, 0.20, 1.0), roughness=0.9),
        "cloth_rag_mid": make_material("cloth_rag_mid", (0.24, 0.22, 0.20, 1.0), roughness=0.9),
        "cloth_rag_dark": make_material("cloth_rag_dark", (0.12, 0.10, 0.10, 1.0), roughness=0.9),
        "bone_decayed": make_material("bone_decayed", (0.65, 0.60, 0.45, 1.0), roughness=0.7),
        "cavity_black": make_material("cavity_black", (0.02, 0.02, 0.02, 1.0), roughness=0.95),
        "toxic_guts_glow": make_material("toxic_guts_glow", (0.10, 0.95, 0.15, 1.0), roughness=0.1, metallic=0.1, emission=3.0),
    }


def _compute_envelope(parts: tuple[PartSpec, ...]) -> tuple[float, float, float]:
    min_x = min(p.center_px[0] - p.size_px[0] / 2.0 for p in parts)
    max_x = max(p.center_px[0] + p.size_px[0] / 2.0 for p in parts)
    min_y = min(p.center_px[1] - p.size_px[1] / 2.0 for p in parts)
    max_y = max(p.center_px[1] + p.size_px[1] / 2.0 for p in parts)
    min_z = min(p.center_px[2] - p.size_px[2] / 2.0 for p in parts)
    max_z = max(p.center_px[2] + p.size_px[2] / 2.0 for p in parts)
    return (max_x - min_x, max_z - min_z, max_y - min_y)


def _assert_authored_contract() -> None:
    if len(PART_SPECS) != AUTHORED_PART_COUNT:
        raise RuntimeError(
            f"zombie part count is {len(PART_SPECS)}, expected {AUTHORED_PART_COUNT}"
        )
    envelope = _compute_envelope(PART_SPECS)
    if envelope != TARGET_ENVELOPE_PX:
        raise RuntimeError(
            f"zombie envelope is {envelope}px, expected {TARGET_ENVELOPE_PX}px"
        )
    vol = sum(p.size_px[0] * p.size_px[1] * p.size_px[2] for p in PART_SPECS)
    target_vol = (
        TARGET_ENVELOPE_PX[0] * TARGET_ENVELOPE_PX[1] * TARGET_ENVELOPE_PX[2]
    )
    ratio = vol / target_vol
    if ratio < MIN_SOLID_ENVELOPE_RATIO:
        raise RuntimeError(
            f"zombie volume ratio {ratio:.3f} < threshold {MIN_SOLID_ENVELOPE_RATIO:.3f}"
        )


def build_zombie_mesh() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
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
    _assert_authored_contract()
    parts = tuple({
        "name": p.name,
        "center_px": p.center_px,
        "size_px": p.size_px,
    } for p in PART_SPECS)

    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_single_face_connected_component(parts, label=MODEL_ID)

    # 1. 导出静态 GLB
    root, parts_objs, parts_by_bone = build_zombie_mesh()
    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    STATIC_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(root, STATIC_OUTPUT)

    # 2. 导出 Rigged GLB
    root, parts_objs, parts_by_bone = build_zombie_mesh()
    armature = create_voxel_humanoid_armature(height_px=52.0, name="Armature")
    parent_parts_by_bone(parts_by_bone, armature)
    RIG_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(armature, RIG_OUTPUT)

    # 3. 渲染 3D 视觉图片
    root, parts_objs, _ = build_zombie_mesh()
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
