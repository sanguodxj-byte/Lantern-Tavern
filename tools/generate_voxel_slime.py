from __future__ import annotations

"""Author and export exactly one broad, low Barony-style slime.

The body faces Blender -Y and occupies 34 x 24 x 28 pixels at 32 px per
metre. Its stepped six-layer gel mass, uneven puddle skirt, amber core,
asymmetric eyes, left crown droop, palette, bones, and actions are all owned
here. This file is not a creature-family template and bakes no equipment.
"""

import math
import sys
from dataclasses import dataclass
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from voxel_character_rig import export_glb as export_rig_glb, make_action
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


MODEL_ID = "slime"
TARGET_ENVELOPE_PX = (34.0, 24.0, 28.0)
AUTHORED_PART_COUNT = 51
MIN_SOLID_ENVELOPE_RATIO = 0.32
FACING_ROT_Z = math.pi
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_slime_24px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_slime_24px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"
PX = 1.0 / 32.0


@dataclass(frozen=True)
class PartSpec:
    name: str
    center_px: tuple[float, float, float]
    size_px: tuple[float, float, float]
    material_key: str
    bone: str


# Each record is an independently placed, face-attached mass for this slime.
# The one-line format lets gdUnit validate authored dimensions without Blender.
PART_SPECS: tuple[PartSpec, ...] = (
    # Wide uneven puddle skirt, already larger than the contaminated 18px body.
    PartSpec("puddle_center", (0.0, 0.0, 2.0), (18.0, 16.0, 4.0), "gel_deep", "Torso"),
    PartSpec("puddle_left_lobe", (-13.0, -1.0, 2.0), (8.0, 14.0, 4.0), "gel_mid", "Pseudopod.L"),
    PartSpec("puddle_right_lobe", (13.0, 1.0, 2.0), (8.0, 14.0, 4.0), "gel_deep", "Pseudopod.R"),
    PartSpec("puddle_front_lip", (0.0, -11.0, 2.0), (18.0, 6.0, 4.0), "gel_high", "Torso"),
    PartSpec("puddle_back_shelf", (1.0, 11.0, 2.0), (16.0, 6.0, 4.0), "gel_deep", "Torso"),

    # Lower compression ring keeps the silhouette thick in front and side.
    PartSpec("lower_belly_center", (0.0, 0.0, 6.0), (20.0, 18.0, 4.0), "gel_mid", "Torso"),
    PartSpec("lower_belly_left", (-13.0, -1.0, 6.0), (6.0, 14.0, 4.0), "gel_high", "Pseudopod.L"),
    PartSpec("lower_belly_right", (13.0, 1.0, 6.0), (6.0, 14.0, 4.0), "gel_deep", "Pseudopod.R"),
    PartSpec("lower_front_fold", (0.0, -10.5, 6.0), (20.0, 3.0, 4.0), "gel_deep", "Torso"),
    PartSpec("lower_back_fold", (1.0, 10.5, 6.0), (18.0, 3.0, 4.0), "gel_high", "Torso"),

    # Mid-body opens a recessed front socket for the condensed core.
    PartSpec("mid_belly_center", (0.0, 1.0, 10.0), (22.0, 18.0, 4.0), "gel_mid", "Torso"),
    PartSpec("mid_belly_left", (-13.0, 1.0, 10.0), (4.0, 14.0, 4.0), "gel_high", "Pseudopod.L"),
    PartSpec("mid_belly_right", (13.0, 2.0, 10.0), (4.0, 12.0, 4.0), "gel_deep", "Pseudopod.R"),
    PartSpec("mid_front_cheek_left", (-8.0, -9.5, 10.0), (6.0, 3.0, 4.0), "gel_high", "Face"),
    PartSpec("mid_front_cheek_right", (8.0, -9.5, 10.0), (6.0, 3.0, 4.0), "gel_mid", "Face"),
    PartSpec("core_shadow_lower", (0.0, -9.0, 10.0), (10.0, 2.0, 4.0), "shadow_deep", "Core"),
    PartSpec("amber_core_lower", (0.0, -11.0, 10.0), (6.0, 2.0, 4.0), "core_deep", "Core"),
    PartSpec("mid_back_ridge", (0.0, 11.0, 10.0), (16.0, 2.0, 4.0), "gel_high", "Torso"),

    # Upper ring recedes from the puddle while retaining deep side volume.
    PartSpec("upper_belly_center", (0.0, 2.0, 14.0), (20.0, 16.0, 4.0), "gel_mid", "Torso"),
    PartSpec("upper_belly_left", (-12.5, 2.0, 14.0), (5.0, 12.0, 4.0), "gel_high", "Pseudopod.L"),
    PartSpec("upper_belly_right", (12.0, 3.0, 14.0), (4.0, 10.0, 4.0), "gel_deep", "Pseudopod.R"),
    PartSpec("upper_front_cheek_left", (-7.5, -8.0, 14.0), (5.0, 4.0, 4.0), "gel_mid", "Face"),
    PartSpec("upper_front_cheek_right", (7.5, -8.0, 14.0), (5.0, 4.0, 4.0), "gel_high", "Face"),
    PartSpec("core_shadow_upper", (0.0, -8.0, 14.0), (10.0, 4.0, 4.0), "shadow_mid", "Core"),
    PartSpec("amber_core_upper", (0.0, -11.0, 14.0), (6.0, 2.0, 4.0), "core_mid", "Core"),
    PartSpec("amber_core_glint", (0.0, -12.5, 15.0), (2.0, 1.0, 2.0), "core_high", "Core"),
    PartSpec("upper_back_left", (-5.0, 11.0, 14.0), (10.0, 2.0, 4.0), "gel_deep", "Torso"),
    PartSpec("upper_back_right", (6.0, 10.5, 14.0), (12.0, 1.0, 4.0), "gel_high", "Torso"),

    # Broken crown contour and front brow give the blob a readable face.
    PartSpec("crown_center", (0.0, 2.0, 18.0), (16.0, 14.0, 4.0), "gel_mid", "Head"),
    PartSpec("crown_left_mass", (-10.5, 2.0, 18.0), (5.0, 10.0, 4.0), "gel_high", "Head"),
    PartSpec("crown_right_mass", (10.0, 3.0, 18.0), (4.0, 8.0, 4.0), "gel_deep", "Head"),
    PartSpec("crown_front_brow", (0.0, -7.0, 18.0), (12.0, 4.0, 4.0), "gel_high", "Face"),
    PartSpec("crown_back_step", (-1.0, 10.0, 18.0), (10.0, 2.0, 4.0), "gel_deep", "Head"),
    PartSpec("brow_left", (-4.0, -10.0, 18.0), (4.0, 2.0, 4.0), "shadow_mid", "Face"),
    PartSpec("brow_right", (4.0, -10.0, 18.0), (4.0, 2.0, 4.0), "shadow_deep", "Face"),
    PartSpec("face_bridge", (0.0, -10.0, 18.0), (4.0, 2.0, 4.0), "gel_mid", "Face"),

    # Unequal eyes are complete depth clusters, not flat decals.
    PartSpec("eye_socket_left", (-4.0, -12.0, 18.5), (4.0, 2.0, 3.0), "eye_deep", "Face"),
    PartSpec("eye_iris_left", (-4.0, -13.5, 18.5), (2.0, 1.0, 3.0), "eye_mid", "Face"),
    PartSpec("eye_glint_left", (-4.0, -13.5, 20.5), (1.0, 1.0, 1.0), "eye_high", "Face"),
    PartSpec("eye_socket_right", (4.5, -12.0, 18.0), (3.0, 2.0, 2.0), "eye_deep", "Face"),
    PartSpec("eye_iris_right", (4.5, -13.5, 18.0), (1.0, 1.0, 2.0), "eye_mid", "Face"),
    PartSpec("eye_glint_right", (4.5, -13.5, 19.5), (1.0, 1.0, 1.0), "eye_high", "Face"),

    # Offset cap and left-only droop prevent a generic symmetric hemisphere.
    PartSpec("cap_center_offset", (-1.0, 2.0, 22.0), (12.0, 10.0, 4.0), "gel_high", "Head"),
    PartSpec("cap_left_step", (-8.0, 2.0, 21.0), (2.0, 6.0, 2.0), "gel_mid", "Head"),
    PartSpec("cap_right_step", (7.0, 3.0, 21.0), (4.0, 6.0, 2.0), "gel_deep", "Head"),
    PartSpec("crown_droop_left", (-16.0, 2.0, 17.0), (2.0, 6.0, 4.0), "gel_mid", "Pseudopod.L"),
    PartSpec("droop_tip_left", (-16.0, 2.0, 13.5), (2.0, 4.0, 3.0), "gel_high", "Pseudopod.L"),

    # Sparse wet planes and rear bubble add material/depth cues without hiding mass.
    PartSpec("wet_plate_front_left", (-7.5, -12.0, 10.0), (3.0, 2.0, 2.0), "wet_high", "Face"),
    PartSpec("wet_plate_front_right", (7.5, -12.0, 10.0), (3.0, 2.0, 2.0), "wet_high", "Face"),
    PartSpec("rear_bubble", (-5.0, 13.0, 7.0), (4.0, 2.0, 4.0), "gel_mid", "Torso"),
    PartSpec("rear_bubble_cap", (-5.0, 13.0, 10.0), (2.0, 2.0, 2.0), "wet_high", "Torso"),
)


def _build_materials() -> dict[str, bpy.types.Material]:
    return {
        "gel_deep": make_material("Slime_Gel_Deep", (0.030, 0.150, 0.125, 1.0), roughness=0.82),
        "gel_mid": make_material("Slime_Gel_Mid", (0.065, 0.330, 0.245, 1.0), roughness=0.72),
        "gel_high": make_material("Slime_Gel_High", (0.150, 0.560, 0.365, 1.0), roughness=0.58),
        "wet_high": make_material("Slime_Wet_High", (0.360, 0.760, 0.520, 1.0), roughness=0.28),
        "shadow_deep": make_material("Slime_CoreShadow_Deep", (0.018, 0.045, 0.042, 1.0), roughness=0.94),
        "shadow_mid": make_material("Slime_CoreShadow_Mid", (0.035, 0.095, 0.080, 1.0), roughness=0.90),
        "core_deep": make_material("Slime_Core_Deep", (0.290, 0.075, 0.020, 1.0), emission=0.2),
        "core_mid": make_material("Slime_Core_Mid", (0.800, 0.275, 0.035, 1.0), emission=0.8),
        "core_high": make_material("Slime_Core_High", (1.000, 0.660, 0.110, 1.0), emission=2.0),
        "eye_deep": make_material("Slime_Eye_Deep", (0.008, 0.015, 0.012, 1.0), roughness=0.96),
        "eye_mid": make_material("Slime_Eye_Mid", (0.520, 0.720, 0.140, 1.0), emission=0.5),
        "eye_high": make_material("Slime_Eye_High", (0.940, 1.000, 0.500, 1.0), emission=1.8),
    }


def build_slime() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
    root = make_root("voxel_slime_24px")
    materials = _build_materials()
    parts: list[bpy.types.Object] = []
    parts_by_bone: dict[str, list[bpy.types.Object]] = {}
    for spec in PART_SPECS:
        part = cube_px(spec.name, spec.center_px, spec.size_px, materials[spec.material_key])
        part.parent = root
        parts.append(part)
        parts_by_bone.setdefault(spec.bone, []).append(part)
    return root, parts, parts_by_bone


def _authored_bounds_px() -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    minimum = tuple(min(spec.center_px[axis] - spec.size_px[axis] * 0.5 for spec in PART_SPECS) for axis in range(3))
    maximum = tuple(max(spec.center_px[axis] + spec.size_px[axis] * 0.5 for spec in PART_SPECS) for axis in range(3))
    return minimum, maximum


def _assert_authored_contract() -> None:
    if len(PART_SPECS) != AUTHORED_PART_COUNT:
        raise RuntimeError(f"slime has {len(PART_SPECS)} parts, expected {AUTHORED_PART_COUNT}")
    minimum, maximum = _authored_bounds_px()
    blender_size = tuple(maximum[axis] - minimum[axis] for axis in range(3))
    envelope = (blender_size[0], blender_size[2], blender_size[1])
    if envelope != TARGET_ENVELOPE_PX:
        raise RuntimeError(f"slime envelope is {envelope}px, expected {TARGET_ENVELOPE_PX}px")
    if TARGET_ENVELOPE_PX[0] < TARGET_ENVELOPE_PX[1] * 1.35:
        raise RuntimeError("slime must remain broad rather than tall and thin")
    solid_volume = sum(spec.size_px[0] * spec.size_px[1] * spec.size_px[2] for spec in PART_SPECS)
    envelope_volume = blender_size[0] * blender_size[1] * blender_size[2]
    if solid_volume / envelope_volume < MIN_SOLID_ENVELOPE_RATIO:
        raise RuntimeError("slime primary volume collapsed below its authored density floor")


def _point_to_m(point_px: tuple[float, float, float]) -> Vector:
    return Vector(tuple(value * PX for value in point_px))


def _create_slime_armature() -> bpy.types.Object:
    bone_defs = (
        ("Root", (0.0, 0.0, 0.0), (0.0, 0.0, 4.0), ""),
        ("Torso", (0.0, 0.0, 4.0), (0.0, 0.0, 16.0), "Root"),
        ("Head", (0.0, 0.0, 16.0), (0.0, 0.0, 23.0), "Torso"),
        ("Face", (0.0, -6.0, 14.0), (0.0, -10.0, 19.0), "Head"),
        ("Core", (0.0, -8.0, 8.0), (0.0, -8.0, 16.0), "Torso"),
        ("Pseudopod.L", (-9.0, 0.0, 5.0), (-16.0, 0.0, 8.0), "Torso"),
        ("Pseudopod.R", (9.0, 0.0, 5.0), (16.0, 0.0, 8.0), "Torso"),
    )
    bpy.ops.object.armature_add(enter_editmode=True, location=(0.0, 0.0, 0.0))
    armature = bpy.context.object
    armature.name = "Armature"
    armature.data.name = "SlimeArmatureData"
    edit_bones = armature.data.edit_bones
    for bone in list(edit_bones):
        edit_bones.remove(bone)
    created = {}
    for name, head, tail, _parent in bone_defs:
        bone = edit_bones.new(name)
        bone.head = _point_to_m(head)
        bone.tail = _point_to_m(tail)
        created[name] = bone
    for name, _head, _tail, parent in bone_defs:
        if parent:
            created[name].parent = created[parent]
            created[name].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return armature


def _parent_parts_to_slime_bones(
    parts_by_bone: dict[str, list[bpy.types.Object]],
    armature: bpy.types.Object,
) -> None:
    for bone_name, parts in parts_by_bone.items():
        if bone_name not in armature.data.bones:
            raise RuntimeError(f"slime part references missing bone: {bone_name}")
        for part in parts:
            world_transform = part.matrix_world.copy()
            part.parent = armature
            part.parent_type = "BONE"
            part.parent_bone = bone_name
            part.matrix_world = world_transform


def _build_slime_actions(armature: bpy.types.Object) -> None:
    make_action(armature, "idle", 29, [
        (1, {}),
        (15, {"Torso": {"rot": (0, 0, 2), "loc": (0.0, 0.0, 0.025)}, "Head": {"rot": (0, 3, 0)}, "Core": {"rot": (0, 0, 8)}}),
        (29, {}),
    ])
    make_action(armature, "run", 12, [
        (1, {"Torso": {"rot": (0, -5, -4), "loc": (0.0, 0.0, 0.04)}, "Pseudopod.L": {"rot": (0, 0, 18)}, "Pseudopod.R": {"rot": (0, 0, -12)}}),
        (6, {"Torso": {"rot": (0, 5, 4)}, "Pseudopod.L": {"rot": (0, 0, -12)}, "Pseudopod.R": {"rot": (0, 0, 18)}}),
        (12, {"Torso": {"rot": (0, -5, -4), "loc": (0.0, 0.0, 0.04)}, "Pseudopod.L": {"rot": (0, 0, 18)}, "Pseudopod.R": {"rot": (0, 0, -12)}}),
    ])
    swipe = [
        (1, {"Torso": {"rot": (0, -8, 0)}, "Pseudopod.R": {"rot": (0, -10, -35)}, "Face": {"rot": (0, -4, 0)}}),
        (4, {"Torso": {"rot": (0, 8, 0)}, "Pseudopod.R": {"rot": (0, 16, 42)}, "Face": {"rot": (0, 6, 0)}}),
        (8, {}),
    ]
    make_action(armature, "slash", 8, swipe)
    make_action(armature, "block", 8, [
        (1, {"Torso": {"rot": (-10, 0, 0)}, "Pseudopod.L": {"rot": (0, 0, -25)}, "Pseudopod.R": {"rot": (0, 0, 25)}}),
        (4, {"Torso": {"rot": (-16, 0, 0), "loc": (0.0, 0.025, -0.035)}, "Head": {"rot": (10, 0, 0)}}),
        (8, {}),
    ])
    make_action(armature, "hurt", 7, [
        (1, {"Torso": {"rot": (12, 0, 8), "loc": (0.0, 0.06, 0.0)}, "Head": {"rot": (8, 0, -8)}}),
        (4, {"Torso": {"rot": (-6, 0, -4)}}),
        (7, {}),
    ])
    make_action(armature, "stunned", 12, [
        (1, {"Head": {"rot": (0, 0, 10)}, "Face": {"rot": (0, 5, 0)}, "Core": {"rot": (0, 0, -12)}}),
        (6, {"Head": {"rot": (0, 0, -10)}, "Face": {"rot": (0, -5, 0)}, "Core": {"rot": (0, 0, 12)}}),
        (12, {"Head": {"rot": (0, 0, 10)}, "Face": {"rot": (0, 5, 0)}, "Core": {"rot": (0, 0, -12)}}),
    ])
    make_action(armature, "death", 18, [
        (1, {}),
        (8, {"Torso": {"rot": (35, 0, 0), "loc": (0.0, 0.0, -0.16)}, "Head": {"rot": (25, 0, 10)}, "Pseudopod.L": {"rot": (0, 0, -28)}, "Pseudopod.R": {"rot": (0, 0, 28)}}),
        (18, {"Torso": {"rot": (72, 0, 0), "loc": (0.0, 0.0, -0.30)}, "Head": {"rot": (40, 0, 18)}, "Core": {"rot": (0, 0, 35)}}),
    ])
    make_action(armature, "kick", 6, [
        (1, {"Pseudopod.L": {"rot": (0, -15, 20)}}),
        (3, {"Pseudopod.L": {"rot": (0, 30, -35)}, "Torso": {"rot": (0, 5, 0)}}),
        (6, {}),
    ])
    make_action(armature, "lift", 8, [
        (1, {"Torso": {"rot": (-8, 0, 0)}, "Pseudopod.L": {"rot": (-20, 0, -16)}, "Pseudopod.R": {"rot": (-20, 0, 16)}}),
        (4, {"Torso": {"rot": (-15, 0, 0), "loc": (0.0, 0.0, 0.06)}, "Pseudopod.L": {"rot": (-35, 0, -25)}, "Pseudopod.R": {"rot": (-35, 0, 25)}}),
        (8, {}),
    ])
    make_action(armature, "pickup", 6, [
        (1, {"Torso": {"rot": (15, 0, 0)}, "Face": {"rot": (12, 0, 0)}}),
        (3, {"Torso": {"rot": (24, 0, 0), "loc": (0.0, -0.03, -0.03)}, "Face": {"rot": (18, 0, 0)}}),
        (6, {}),
    ])
    make_action(armature, "throw_weapon", 7, [
        (1, {"Pseudopod.R": {"rot": (0, -25, -30)}, "Torso": {"rot": (0, -10, 0)}}),
        (4, {"Pseudopod.R": {"rot": (0, 35, 45)}, "Torso": {"rot": (0, 12, 0)}}),
        (7, {}),
    ])
    make_action(armature, "throw_furniture", 8, [
        (1, {"Pseudopod.L": {"rot": (-30, 0, -20)}, "Pseudopod.R": {"rot": (-30, 0, 20)}, "Torso": {"rot": (-12, 0, 0)}}),
        (5, {"Pseudopod.L": {"rot": (25, 0, 15)}, "Pseudopod.R": {"rot": (25, 0, -15)}, "Torso": {"rot": (15, 0, 0)}}),
        (8, {}),
    ])
    make_action(armature, "claw_swipe", 8, swipe)
    make_action(armature, "default", 1, [(1, {"Root": {"rot": (0, 0, 0)}})])


def main() -> None:
    reject_target_override(MODEL_ID)
    _assert_authored_contract()
    reset_scene()
    root, parts, parts_by_bone = build_slime()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_single_face_connected_component(parts, label=MODEL_ID)

    root.rotation_euler.z = FACING_ROT_Z
    bpy.context.view_layer.update()
    export_static_glb(root, STATIC_OUTPUT)

    root.rotation_euler.z = 0.0
    bpy.context.view_layer.update()
    armature = _create_slime_armature()
    _parent_parts_to_slime_bones(parts_by_bone, armature)
    _build_slime_actions(armature)
    bpy.data.objects.remove(root, do_unlink=True)
    armature.rotation_euler.z = FACING_ROT_Z
    bpy.context.view_layer.update()
    export_rig_glb(RIG_OUTPUT)

    armature.rotation_euler.z = 0.0
    armature.data.pose_position = "REST"
    bpy.context.view_layer.update()
    center, scale = bounds_center_scale(armature)
    camera = setup_lights_and_camera(center, scale)
    configure_real_render(resolution=1100)
    render_real_views(PREVIEW_DIR, "voxel_slime", center, scale, camera)

    print(f"Wrote {STATIC_OUTPUT}")
    print(f"Wrote {RIG_OUTPUT}")
    print(f"Parts: {AUTHORED_PART_COUNT}; envelope: {TARGET_ENVELOPE_PX}px; front: Blender -Y")


if __name__ == "__main__":
    main()
