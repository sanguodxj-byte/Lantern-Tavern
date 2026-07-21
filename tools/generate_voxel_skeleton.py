#!/usr/bin/env python3
"""Generate the skeleton character voxel asset (A-tier High Detail Remake).

Barony-style authored voxel skeleton with exposed ribcage, double-bone shins (tibia & fibula),
tattered grave cloth, deep glowing blue soulfire eyes, and intricate spinal column.
No hand-held weapons built-in per equipment system rule.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from voxel_character_rig import build_all_actions, build_weapon_actions, export_glb as export_rig_glb
from voxel_humanoid_rig import create_voxel_humanoid_armature, parent_parts_by_bone
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
from voxel_overlap_guard import assert_parts_voxel_assembly_valid
from voxel_single_model_cli import reject_target_override

MODEL_ID = "skeleton"
TARGET_ENVELOPE_PX = (28.0, 48.0, 11.0)
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_skeleton_48px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_skeleton_48px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


def build_skeleton() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
    root = make_root("voxel_skeleton_48px")

    bone_high = make_material("Bone_High", (0.78, 0.72, 0.56, 1.0))
    bone_mid = make_material("Bone_Mid", (0.52, 0.47, 0.35, 1.0))
    bone_dark = make_material("Bone_Dark", (0.27, 0.25, 0.20, 1.0))
    socket_dark = make_material("Socket_Dark", (0.035, 0.045, 0.044, 1.0))
    soul_glow = make_material(
        "Soul_Glow", (0.10, 0.80, 0.95, 1.0), roughness=0.2, emission=3.5
    )
    cloth_high = make_material("Grave_Cloth_High", (0.42, 0.16, 0.12, 1.0))
    cloth_mid = make_material("Grave_Cloth_Mid", (0.25, 0.085, 0.075, 1.0))
    cloth_dark = make_material("Grave_Cloth_Dark", (0.105, 0.035, 0.038, 1.0))

    parts: list[bpy.types.Object] = []
    parts_by_bone: dict[str, list[bpy.types.Object]] = {
        "Head": [], "Neck": [], "Torso": [], "Pelvis": [],
        "UpperArm.L": [], "LowerArm.L": [], "Hand.L": [],
        "UpperArm.R": [], "LowerArm.R": [], "Hand.R": [],
        "UpperLeg.L": [], "LowerLeg.L": [], "Foot.L": [],
        "UpperLeg.R": [], "LowerLeg.R": [], "Foot.R": [],
    }

    def add(
        name: str,
        center_px: tuple[float, float, float],
        size_px: tuple[float, float, float],
        material: bpy.types.Material,
        bone: str,
    ) -> bpy.types.Object:
        part = cube_px(name, center_px, size_px, material)
        part.parent = root
        parts.append(part)
        parts_by_bone[bone].append(part)
        return part

    # Skull: stepped cranium, separate lower mass, jaw & glowing soulfire eyes.
    add("skull_lower_core", (0.0, 0.0, 39.0), (6.0, 6.0, 4.0), bone_mid, "Head")
    add("skull_cranium", (0.0, 0.0, 43.5), (8.0, 8.0, 5.0), bone_high, "Head")
    add("skull_cap", (0.0, 0.5, 47.0), (8.0, 9.0, 2.0), bone_mid, "Head")
    add("skull_temple_left", (-5.0, 0.0, 43.0), (2.0, 6.0, 3.0), bone_mid, "Head")
    add("skull_temple_right", (5.0, 0.0, 42.5), (2.0, 6.0, 3.0), bone_dark, "Head")
    add("skull_cheek_left", (-4.0, -0.5, 38.5), (2.0, 5.0, 3.0), bone_high, "Head")
    add("skull_cheek_right", (4.0, 0.0, 38.5), (2.0, 4.0, 3.0), bone_mid, "Head")
    # Large deep-set eye sockets flush on cranium front face (Y=-4.0 is cranium edge)
    add("eye_socket_left", (-2.5, -4.5, 43.0), (3.0, 1.0, 3.0), socket_dark, "Head")
    add("eye_socket_right", (2.5, -4.5, 43.0), (3.0, 1.0, 3.0), socket_dark, "Head")
    add("soul_eye_left", (-2.5, -5.5, 43.0), (2.0, 1.0, 2.0), soul_glow, "Head")
    add("soul_eye_right", (2.5, -5.5, 43.0), (2.0, 1.0, 2.0), soul_glow, "Head")
    # Nasal cavity — flush on skull_lower_core front (Y=-3.0 is its edge; center at -3.5)
    add("nasal_cavity", (0.0, -3.5, 39.5), (2.0, 1.0, 3.0), socket_dark, "Head")
    # Upper teeth — flush on nasal_cavity bottom (Z=38.0 is nasal bottom; teeth at Z=37.5)
    add("upper_teeth", (0.0, -3.5, 37.5), (4.0, 1.0, 1.0), bone_high, "Head")
    # Jaw — narrower to avoid clavicle overlap
    add("jaw", (0.0, -0.5, 35.5), (6.0, 5.0, 3.0), bone_mid, "Head")
    add("jaw_angle_left", (-4.0, -2.5, 35.0), (2.0, 3.0, 2.0), bone_dark, "Head")
    add("jaw_angle_right", (4.0, -2.5, 35.5), (2.0, 3.0, 2.0), bone_mid, "Head")
    # Jaw teeth flush on jaw front face (jaw Y range [-3.0, 2.0]; teeth at Y=-3.5)
    add("jaw_teeth_left", (-1.5, -3.5, 36.0), (2.0, 1.0, 1.0), bone_high, "Head")
    add("jaw_teeth_right", (1.5, -3.5, 36.0), (2.0, 1.0, 1.0), bone_high, "Head")

    # Narrow neck.
    add("neck_axis", (0.0, 1.5, 33.0), (2.0, 3.0, 2.0), bone_dark, "Neck")

    # Spine, Sternum, & 4-level Ribcage.
    add("spine_lumbar", (0.0, 2.5, 21.0), (2.0, 2.0, 6.0), bone_dark, "Torso")
    add("spine_thoracic", (0.0, 2.5, 28.0), (2.0, 2.0, 8.0), bone_mid, "Torso")
    add("sternum", (0.0, -2.5, 29.5), (4.0, 2.0, 9.0), bone_high, "Torso")

    rib_levels = (
        (0, 25.5, bone_dark, bone_mid, bone_high),
        (1, 28.0, bone_mid, bone_high, bone_mid),
        (2, 30.5, bone_dark, bone_mid, bone_high),
        (3, 33.0, bone_mid, bone_high, bone_mid),
    )
    for level, height, rear_material, side_material, front_material in rib_levels:
        add(f"rib_left_rear_{level}", (-3.0, 2.5, height), (4.0, 2.0, 1.0), rear_material, "Torso")
        add(f"rib_right_rear_{level}", (3.0, 2.5, height), (4.0, 2.0, 1.0), rear_material, "Torso")
        add(f"rib_left_side_{level}", (-6.0, 0.5, height), (2.0, 4.0, 1.0), side_material, "Torso")
        add(f"rib_right_side_{level}", (6.0, 0.5, height), (2.0, 4.0, 1.0), side_material, "Torso")
        add(f"rib_left_front_{level}", (-4.0, -2.5, height), (4.0, 2.0, 1.0), front_material, "Torso")
        add(f"rib_right_front_{level}", (4.0, -2.5, height), (4.0, 2.0, 1.0), front_material, "Torso")

    # Clavicles and arms.
    add("clavicle_left", (-5.0, 0.0, 34.5), (4.0, 2.0, 1.0), bone_high, "Torso")
    add("clavicle_right", (5.0, 0.0, 34.5), (4.0, 2.0, 1.0), bone_mid, "Torso")
    add("shoulder_joint_left", (-8.5, 0.0, 33.5), (3.0, 3.0, 3.0), bone_mid, "UpperArm.L")
    add("shoulder_joint_right", (8.5, 0.0, 33.5), (3.0, 3.0, 3.0), bone_dark, "UpperArm.R")
    add("upper_arm_left", (-9.5, 0.0, 29.0), (3.0, 3.0, 6.0), bone_high, "UpperArm.L")
    add("upper_arm_right", (9.0, 0.5, 29.0), (3.0, 3.0, 6.0), bone_mid, "UpperArm.R")
    add("elbow_left", (-10.5, 0.0, 25.0), (3.0, 3.0, 2.0), bone_dark, "LowerArm.L")
    add("elbow_right", (10.0, 0.5, 25.0), (3.0, 3.0, 2.0), bone_high, "LowerArm.R")
    add("forearm_left", (-11.5, 0.0, 20.5), (3.0, 3.0, 7.0), bone_mid, "LowerArm.L")
    add("forearm_right", (11.0, 0.5, 20.5), (3.0, 3.0, 7.0), bone_dark, "LowerArm.R")
    add("wrist_left", (-12.0, 0.0, 16.0), (2.0, 2.0, 2.0), bone_dark, "Hand.L")
    add("wrist_right", (12.0, 0.5, 16.0), (2.0, 2.0, 2.0), bone_mid, "Hand.R")
    add("hand_left", (-12.5, -0.5, 13.5), (3.0, 3.0, 3.0), bone_mid, "Hand.L")
    add("hand_right", (12.5, 0.0, 13.5), (3.0, 3.0, 3.0), bone_high, "Hand.R")

    # Pelvis & Tattered Grave Cloth.
    add("sacrum", (0.0, 1.5, 16.5), (4.0, 3.0, 3.0), bone_dark, "Pelvis")
    add("pelvis_wing_left", (-4.5, 0.5, 16.5), (5.0, 5.0, 3.0), bone_mid, "Pelvis")
    add("pelvis_wing_right", (4.5, 0.5, 16.5), (5.0, 5.0, 3.0), bone_high, "Pelvis")
    add("pelvis_crest_left", (-4.5, 0.5, 18.5), (5.0, 2.0, 1.0), bone_high, "Pelvis")
    add("pelvis_crest_right", (4.5, 1.0, 18.5), (5.0, 2.0, 1.0), bone_dark, "Pelvis")
    add("grave_cloth_left", (-4.5, -2.5, 14.5), (5.0, 1.0, 3.0), cloth_mid, "Pelvis")
    add("grave_cloth_right", (4.5, -2.5, 14.0), (5.0, 1.0, 4.0), cloth_dark, "Pelvis")
    add("grave_cloth_left_highlight", (-4.5, -3.5, 15.0), (3.0, 1.0, 1.0), cloth_high, "Pelvis")
    add("grave_cloth_right_highlight", (4.0, -3.5, 14.5), (2.0, 1.0, 1.0), cloth_mid, "Pelvis")
    add("grave_cloth_left_torn", (-5.0, -2.5, 11.5), (2.0, 1.0, 3.0), cloth_dark, "Pelvis")
    add("grave_cloth_right_torn", (5.0, -2.5, 10.5), (2.0, 1.0, 3.0), cloth_mid, "Pelvis")

    # Leg Bones with Tibia & Fibula gap.
    add("thigh_left", (-4.5, 0.5, 11.5), (3.0, 3.0, 7.0), bone_high, "UpperLeg.L")
    add("thigh_right", (4.5, 0.5, 11.5), (3.0, 3.0, 7.0), bone_mid, "UpperLeg.R")
    add("knee_left", (-5.0, 0.5, 7.0), (3.0, 3.0, 2.0), bone_dark, "LowerLeg.L")
    add("knee_right", (4.5, 0.0, 7.0), (3.0, 3.0, 2.0), bone_high, "LowerLeg.R")
    add("shin_left_tibia", (-5.0, 0.5, 4.0), (2.0, 3.0, 4.0), bone_mid, "LowerLeg.L")
    add("shin_left_fibula", (-3.0, 0.5, 4.0), (1.0, 2.0, 4.0), bone_dark, "LowerLeg.L")
    add("shin_right_tibia", (4.5, 0.0, 4.0), (2.0, 3.0, 4.0), bone_dark, "LowerLeg.R")
    add("shin_right_fibula", (2.5, 0.0, 4.0), (1.0, 2.0, 4.0), bone_mid, "LowerLeg.R")
    add("foot_left", (-4.5, -2.0, 1.0), (5.0, 6.0, 2.0), bone_dark, "Foot.L")
    add("foot_right", (4.5, -2.5, 1.0), (5.0, 7.0, 2.0), bone_mid, "Foot.R")

    return root, parts, parts_by_bone


def _assert_authored_envelope(parts: list[bpy.types.Object]) -> None:
    minimum = [min(obj.location[axis] - obj.dimensions[axis] * 0.5 for obj in parts) for axis in range(3)]
    maximum = [max(obj.location[axis] + obj.dimensions[axis] * 0.5 for obj in parts) for axis in range(3)]
    blender_size_px = tuple(round((maximum[axis] - minimum[axis]) * 32.0, 4) for axis in range(3))
    size_px = (blender_size_px[0], blender_size_px[2], blender_size_px[1])
    if size_px != TARGET_ENVELOPE_PX:
        raise RuntimeError(f"skeleton envelope is {size_px}px, expected {TARGET_ENVELOPE_PX}px")


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts, parts_by_bone = build_skeleton()
    _assert_authored_envelope(parts)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)

    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    export_static_glb(root, STATIC_OUTPUT)

    root.rotation_euler.z = 0.0
    bpy.context.view_layer.update()
    armature = create_voxel_humanoid_armature(height_px=48.0, name="SkeletonRig")
    armature.parent = root
    parent_parts_by_bone(parts_by_bone, armature)
    build_all_actions(armature)
    build_weapon_actions(armature)
    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    export_rig_glb(RIG_OUTPUT)

    root.rotation_euler.z = 0.0
    armature.data.pose_position = "REST"
    bpy.context.view_layer.update()
    center, scale = bounds_center_scale(root)
    camera = setup_lights_and_camera(center, scale)
    configure_real_render(resolution=1100)
    render_real_views(PREVIEW_DIR, "voxel_skeleton", center, scale, camera)

    print(f"Wrote {STATIC_OUTPUT}")
    print(f"Wrote {RIG_OUTPUT}")
    print(f"Envelope: {TARGET_ENVELOPE_PX}px; front: Blender -Y")


if __name__ == "__main__":
    main()
