from __future__ import annotations

"""Author and export exactly one broad, heavy Barony-style giant spider.

The spider faces Blender -Y and occupies 54 x 30 x 50 pixels at 32 px per
metre. Its layered thorax, tall abdomen, eight-eye cluster, paired mandibles,
venom rear plate, spinnerets, and eight three-segment legs are authored here.
This file is not a creature-family template and produces no other identity.
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


MODEL_ID = "spider"
TARGET_ENVELOPE_PX = (54.0, 30.0, 50.0)
AUTHORED_PART_COUNT = 85
MIN_SOLID_ENVELOPE_RATIO = 0.14
MIN_LEG_THICKNESS_PX = 5.0
FACING_ROT_Z = math.pi
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_spider_30px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_spider_30px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"
PX = 1.0 / 32.0


@dataclass(frozen=True)
class PartSpec:
    name: str
    center_px: tuple[float, float, float]
    size_px: tuple[float, float, float]
    material_key: str
    bone: str


# Every record is an authored, face-attached box. Paired legs remain mirrored;
# the venom rear plate is the only local color accent, not random asymmetry.
PART_SPECS: tuple[PartSpec, ...] = (
    # Three stepped thorax strata, split into real masses rather than plates.
    PartSpec("thorax_lower_center", (0.0, -3.0, 9.0), (12.0, 18.0, 6.0), "carapace_mid", "Thorax"),
    PartSpec("thorax_lower_left", (-8.0, -3.0, 9.0), (4.0, 18.0, 6.0), "carapace_deep", "Thorax"),
    PartSpec("thorax_lower_right", (8.0, -3.0, 9.0), (4.0, 18.0, 6.0), "carapace_deep", "Thorax"),
    PartSpec("thorax_mid_center", (0.0, -3.0, 15.0), (14.0, 18.0, 6.0), "carapace_high", "Thorax"),
    PartSpec("thorax_mid_left", (-8.5, -3.0, 15.0), (3.0, 18.0, 6.0), "carapace_mid", "Thorax"),
    PartSpec("thorax_mid_right", (8.5, -3.0, 15.0), (3.0, 18.0, 6.0), "carapace_mid", "Thorax"),
    PartSpec("thorax_upper_center", (0.0, -3.0, 21.0), (10.0, 14.0, 6.0), "carapace_mid", "Thorax"),
    PartSpec("thorax_upper_left", (-6.5, -3.0, 21.0), (3.0, 14.0, 6.0), "carapace_high", "Thorax"),
    PartSpec("thorax_upper_right", (6.5, -3.0, 21.0), (3.0, 14.0, 6.0), "carapace_high", "Thorax"),
    PartSpec("thorax_dorsal_ridge", (0.0, -3.0, 25.5), (10.0, 10.0, 3.0), "carapace_deep", "Thorax"),

    # The head steps forward in three thick tiers and stays readable in profile.
    PartSpec("head_lower_center", (0.0, -15.0, 10.0), (10.0, 6.0, 6.0), "carapace_mid", "Head"),
    PartSpec("head_lower_left", (-7.5, -15.0, 10.0), (5.0, 6.0, 6.0), "carapace_deep", "Head"),
    PartSpec("head_lower_right", (7.5, -15.0, 10.0), (5.0, 6.0, 6.0), "carapace_deep", "Head"),
    PartSpec("head_mid_center", (0.0, -15.0, 16.0), (12.0, 6.0, 6.0), "carapace_high", "Head"),
    PartSpec("head_mid_left", (-8.0, -15.0, 16.0), (4.0, 6.0, 6.0), "carapace_mid", "Head"),
    PartSpec("head_mid_right", (8.0, -15.0, 16.0), (4.0, 6.0, 6.0), "carapace_mid", "Head"),
    PartSpec("head_upper_center", (0.0, -15.0, 22.0), (8.0, 6.0, 6.0), "carapace_mid", "Head"),
    PartSpec("head_upper_left", (-5.5, -15.0, 22.0), (3.0, 6.0, 6.0), "carapace_high", "Head"),
    PartSpec("head_upper_right", (5.5, -15.0, 22.0), (3.0, 6.0, 6.0), "carapace_high", "Head"),
    PartSpec("face_center", (0.0, -20.0, 16.0), (10.0, 4.0, 14.0), "underside", "Head"),
    PartSpec("face_left", (-6.5, -20.0, 16.0), (3.0, 4.0, 14.0), "carapace_deep", "Head"),
    PartSpec("face_right", (6.5, -20.0, 16.0), (3.0, 4.0, 14.0), "carapace_deep", "Head"),

    # Eight eyes have socket depth and colored pupils; the major pair has glints.
    PartSpec("eye_socket_major_left", (-4.0, -23.0, 18.5), (3.0, 2.0, 3.0), "eye_deep", "Head"),
    PartSpec("eye_socket_major_right", (4.0, -23.0, 18.5), (3.0, 2.0, 3.0), "eye_deep", "Head"),
    PartSpec("eye_socket_outer_left", (-7.0, -23.0, 15.5), (2.0, 2.0, 2.0), "eye_deep", "Head"),
    PartSpec("eye_socket_outer_right", (7.0, -23.0, 15.5), (2.0, 2.0, 2.0), "eye_deep", "Head"),
    PartSpec("eye_socket_lower_left", (-2.0, -23.0, 14.0), (2.0, 2.0, 2.0), "eye_deep", "Head"),
    PartSpec("eye_socket_lower_right", (2.0, -23.0, 14.0), (2.0, 2.0, 2.0), "eye_deep", "Head"),
    PartSpec("eye_socket_upper_left", (-1.5, -23.0, 21.5), (2.0, 2.0, 2.0), "eye_deep", "Head"),
    PartSpec("eye_socket_upper_right", (1.5, -23.0, 21.5), (2.0, 2.0, 2.0), "eye_deep", "Head"),
    PartSpec("eye_pupil_major_left", (-4.0, -24.5, 18.5), (2.0, 1.0, 2.0), "eye_mid", "Head"),
    PartSpec("eye_pupil_major_right", (4.0, -24.5, 18.5), (2.0, 1.0, 2.0), "eye_mid", "Head"),
    PartSpec("eye_pupil_outer_left", (-7.0, -24.5, 15.5), (1.0, 1.0, 1.0), "eye_mid", "Head"),
    PartSpec("eye_pupil_outer_right", (7.0, -24.5, 15.5), (1.0, 1.0, 1.0), "eye_mid", "Head"),
    PartSpec("eye_pupil_lower_left", (-2.0, -24.5, 14.0), (1.0, 1.0, 1.0), "eye_mid", "Head"),
    PartSpec("eye_pupil_lower_right", (2.0, -24.5, 14.0), (1.0, 1.0, 1.0), "eye_mid", "Head"),
    PartSpec("eye_pupil_upper_left", (-1.5, -24.5, 21.5), (1.0, 1.0, 1.0), "eye_mid", "Head"),
    PartSpec("eye_pupil_upper_right", (1.5, -24.5, 21.5), (1.0, 1.0, 1.0), "eye_mid", "Head"),
    PartSpec("eye_glint_major_left", (-3.5, -25.5, 19.0), (1.0, 1.0, 1.0), "eye_high", "Head"),
    PartSpec("eye_glint_major_right", (4.5, -25.5, 19.0), (1.0, 1.0, 1.0), "eye_high", "Head"),

    # Mandibles are 6px roots and 4px tips, never needle-thin.
    PartSpec("mandible_root_left", (-6.0, -24.0, 10.0), (6.0, 4.0, 6.0), "fang", "Mandible.L"),
    PartSpec("mandible_tip_left", (-6.0, -24.0, 4.5), (4.0, 4.0, 5.0), "venom_mid", "Mandible.L"),
    PartSpec("mandible_root_right", (6.0, -24.0, 10.0), (6.0, 4.0, 6.0), "fang", "Mandible.R"),
    PartSpec("mandible_tip_right", (6.0, -24.0, 4.5), (4.0, 4.0, 5.0), "venom_mid", "Mandible.R"),

    # Waist and four abdomen strata form a tall, broken rear silhouette.
    PartSpec("waist_bridge", (0.0, 8.0, 13.0), (8.0, 4.0, 6.0), "underside", "Thorax"),
    PartSpec("abdomen_lower_center", (0.0, 16.0, 8.0), (12.0, 12.0, 6.0), "carapace_mid", "Abdomen"),
    PartSpec("abdomen_lower_left", (-8.5, 16.0, 8.0), (5.0, 12.0, 6.0), "carapace_deep", "Abdomen"),
    PartSpec("abdomen_lower_right", (8.5, 16.0, 8.0), (5.0, 12.0, 6.0), "carapace_deep", "Abdomen"),
    PartSpec("abdomen_mid_center", (0.0, 16.0, 14.0), (14.0, 12.0, 6.0), "carapace_high", "Abdomen"),
    PartSpec("abdomen_mid_left", (-9.5, 16.0, 14.0), (5.0, 12.0, 6.0), "carapace_mid", "Abdomen"),
    PartSpec("abdomen_mid_right", (9.5, 16.0, 14.0), (5.0, 12.0, 6.0), "carapace_mid", "Abdomen"),
    PartSpec("abdomen_upper_center", (0.0, 16.0, 20.0), (12.0, 10.0, 6.0), "carapace_mid", "Abdomen"),
    PartSpec("abdomen_upper_left", (-8.0, 16.0, 20.0), (4.0, 10.0, 6.0), "carapace_high", "Abdomen"),
    PartSpec("abdomen_upper_right", (8.0, 16.0, 20.0), (4.0, 10.0, 6.0), "carapace_high", "Abdomen"),
    PartSpec("abdomen_crown_center", (0.0, 16.0, 25.0), (8.0, 8.0, 4.0), "carapace_deep", "Abdomen"),
    PartSpec("abdomen_crown_left", (-5.5, 16.0, 25.0), (3.0, 8.0, 4.0), "carapace_mid", "Abdomen"),
    PartSpec("abdomen_crown_right", (5.5, 16.0, 25.0), (3.0, 8.0, 4.0), "carapace_mid", "Abdomen"),
    PartSpec("abdomen_top_venom_ridge", (0.0, 15.5, 28.5), (8.0, 5.0, 3.0), "venom_deep", "Venom"),
    PartSpec("spinneret_left", (-4.0, 23.0, 8.0), (4.0, 2.0, 4.0), "spinneret", "Abdomen"),
    PartSpec("spinneret_right", (4.0, 23.0, 8.0), (4.0, 2.0, 4.0), "spinneret", "Abdomen"),
    PartSpec("venom_sac_rear", (0.0, 23.0, 14.0), (6.0, 2.0, 4.0), "venom_high", "Venom"),

    # Four mirrored pairs of three-segment legs. No segment is 1-2px thin.
    PartSpec("leg1_root_left", (-13.0, -9.0, 10.0), (6.0, 5.0, 6.0), "carapace_high", "Leg1.L"),
    PartSpec("leg1_mid_left", (-19.0, -13.0, 8.0), (6.0, 6.0, 6.0), "joint", "Leg1.L"),
    PartSpec("leg1_foot_left", (-24.5, -18.0, 4.0), (5.0, 6.0, 8.0), "underside", "Leg1.L"),
    PartSpec("leg1_root_right", (13.0, -9.0, 10.0), (6.0, 5.0, 6.0), "carapace_high", "Leg1.R"),
    PartSpec("leg1_mid_right", (19.0, -13.0, 8.0), (6.0, 6.0, 6.0), "joint", "Leg1.R"),
    PartSpec("leg1_foot_right", (24.5, -18.0, 4.0), (5.0, 6.0, 8.0), "underside", "Leg1.R"),
    PartSpec("leg2_root_left", (-13.0, -4.0, 10.0), (6.0, 5.0, 6.0), "carapace_mid", "Leg2.L"),
    PartSpec("leg2_mid_left", (-19.0, -7.0, 8.0), (6.0, 6.0, 6.0), "joint", "Leg2.L"),
    PartSpec("leg2_foot_left", (-24.5, -11.0, 4.0), (5.0, 6.0, 8.0), "underside", "Leg2.L"),
    PartSpec("leg2_root_right", (13.0, -4.0, 10.0), (6.0, 5.0, 6.0), "carapace_mid", "Leg2.R"),
    PartSpec("leg2_mid_right", (19.0, -7.0, 8.0), (6.0, 6.0, 6.0), "joint", "Leg2.R"),
    PartSpec("leg2_foot_right", (24.5, -11.0, 4.0), (5.0, 6.0, 8.0), "underside", "Leg2.R"),
    PartSpec("leg3_root_left", (-13.0, 1.0, 10.0), (6.0, 5.0, 6.0), "carapace_mid", "Leg3.L"),
    PartSpec("leg3_mid_left", (-19.0, 4.0, 8.0), (6.0, 6.0, 6.0), "joint", "Leg3.L"),
    PartSpec("leg3_foot_left", (-24.5, 8.0, 4.0), (5.0, 6.0, 8.0), "underside", "Leg3.L"),
    PartSpec("leg3_root_right", (13.0, 1.0, 10.0), (6.0, 5.0, 6.0), "carapace_mid", "Leg3.R"),
    PartSpec("leg3_mid_right", (19.0, 4.0, 8.0), (6.0, 6.0, 6.0), "joint", "Leg3.R"),
    PartSpec("leg3_foot_right", (24.5, 8.0, 4.0), (5.0, 6.0, 8.0), "underside", "Leg3.R"),
    PartSpec("leg4_root_left", (-13.0, 6.0, 10.0), (6.0, 5.0, 6.0), "carapace_high", "Leg4.L"),
    PartSpec("leg4_mid_left", (-19.0, 10.0, 8.0), (6.0, 6.0, 6.0), "joint", "Leg4.L"),
    PartSpec("leg4_foot_left", (-24.5, 15.0, 4.0), (5.0, 6.0, 8.0), "underside", "Leg4.L"),
    PartSpec("leg4_root_right", (13.0, 6.0, 10.0), (6.0, 5.0, 6.0), "carapace_high", "Leg4.R"),
    PartSpec("leg4_mid_right", (19.0, 10.0, 8.0), (6.0, 6.0, 6.0), "joint", "Leg4.R"),
    PartSpec("leg4_foot_right", (24.5, 15.0, 4.0), (5.0, 6.0, 8.0), "underside", "Leg4.R"),
)


def _build_materials() -> dict[str, bpy.types.Material]:
    return {
        "carapace_deep": make_material("Spider_Carapace_Deep", (0.035, 0.040, 0.055, 1.0), roughness=0.78),
        "carapace_mid": make_material("Spider_Carapace_Mid", (0.095, 0.105, 0.135, 1.0), roughness=0.66),
        "carapace_high": make_material("Spider_Carapace_High", (0.210, 0.220, 0.260, 1.0), roughness=0.52),
        "underside": make_material("Spider_Underside_Burgundy", (0.180, 0.045, 0.065, 1.0), roughness=0.88),
        "joint": make_material("Spider_Joint_Burgundy", (0.310, 0.075, 0.095, 1.0), roughness=0.76),
        "fang": make_material("Spider_Fang_Ivory", (0.600, 0.530, 0.390, 1.0), roughness=0.72),
        "spinneret": make_material("Spider_Spinneret_Ash", (0.330, 0.350, 0.380, 1.0), roughness=0.92),
        "eye_deep": make_material("Spider_Eye_Deep", (0.010, 0.008, 0.012, 1.0), roughness=0.34),
        "eye_mid": make_material("Spider_Eye_Amber", (0.900, 0.190, 0.035, 1.0), roughness=0.28, emission=0.8),
        "eye_high": make_material("Spider_Eye_High", (1.000, 0.760, 0.180, 1.0), roughness=0.20, emission=2.0),
        "venom_deep": make_material("Spider_Venom_Deep", (0.020, 0.180, 0.150, 1.0), roughness=0.64),
        "venom_mid": make_material("Spider_Venom_Mid", (0.040, 0.430, 0.300, 1.0), roughness=0.48),
        "venom_high": make_material("Spider_Venom_High", (0.240, 0.860, 0.540, 1.0), roughness=0.34, emission=1.1),
    }


def build_spider() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
    root = make_root("voxel_spider_30px")
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
        raise RuntimeError(f"spider has {len(PART_SPECS)} parts, expected {AUTHORED_PART_COUNT}")
    minimum, maximum = _authored_bounds_px()
    blender_size = tuple(maximum[axis] - minimum[axis] for axis in range(3))
    envelope = (blender_size[0], blender_size[2], blender_size[1])
    if envelope != TARGET_ENVELOPE_PX:
        raise RuntimeError(f"spider envelope is {envelope}px, expected {TARGET_ENVELOPE_PX}px")
    if TARGET_ENVELOPE_PX[0] < TARGET_ENVELOPE_PX[1] * 1.7:
        raise RuntimeError("spider must remain broad and low")
    for spec in PART_SPECS:
        if spec.name.startswith("leg") and spec.size_px[0] < MIN_LEG_THICKNESS_PX:
            raise RuntimeError(f"spider leg collapsed below {MIN_LEG_THICKNESS_PX}px: {spec.name}")
    solid_volume = sum(spec.size_px[0] * spec.size_px[1] * spec.size_px[2] for spec in PART_SPECS)
    envelope_volume = blender_size[0] * blender_size[1] * blender_size[2]
    if solid_volume / envelope_volume < MIN_SOLID_ENVELOPE_RATIO:
        raise RuntimeError("spider solid mass collapsed below its authored density floor")


def _point_to_m(point_px: tuple[float, float, float]) -> Vector:
    return Vector(tuple(value * PX for value in point_px))


def _create_spider_armature() -> bpy.types.Object:
    bone_defs = (
        ("Root", (0.0, 0.0, 0.0), (0.0, 0.0, 5.0), ""),
        ("Thorax", (0.0, -3.0, 5.0), (0.0, -3.0, 19.0), "Root"),
        ("Head", (0.0, -10.0, 13.0), (0.0, -20.0, 18.0), "Thorax"),
        ("Abdomen", (0.0, 5.0, 12.0), (0.0, 18.0, 18.0), "Thorax"),
        ("Venom", (0.0, 15.0, 18.0), (0.0, 19.0, 27.0), "Abdomen"),
        ("Mandible.L", (-4.0, -20.0, 11.0), (-6.0, -24.0, 5.0), "Head"),
        ("Mandible.R", (4.0, -20.0, 11.0), (6.0, -24.0, 5.0), "Head"),
        ("Leg1.L", (-8.0, -9.0, 10.0), (-24.0, -18.0, 4.0), "Thorax"),
        ("Leg1.R", (8.0, -9.0, 10.0), (24.0, -18.0, 4.0), "Thorax"),
        ("Leg2.L", (-8.0, -4.0, 10.0), (-24.0, -11.0, 4.0), "Thorax"),
        ("Leg2.R", (8.0, -4.0, 10.0), (24.0, -11.0, 4.0), "Thorax"),
        ("Leg3.L", (-8.0, 1.0, 10.0), (-24.0, 8.0, 4.0), "Thorax"),
        ("Leg3.R", (8.0, 1.0, 10.0), (24.0, 8.0, 4.0), "Thorax"),
        ("Leg4.L", (-8.0, 6.0, 10.0), (-24.0, 15.0, 4.0), "Thorax"),
        ("Leg4.R", (8.0, 6.0, 10.0), (24.0, 15.0, 4.0), "Thorax"),
    )
    bpy.ops.object.armature_add(enter_editmode=True, location=(0.0, 0.0, 0.0))
    armature = bpy.context.object
    armature.name = "Armature"
    armature.data.name = "SpiderArmatureData"
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


def _parent_parts_to_spider_bones(
    parts_by_bone: dict[str, list[bpy.types.Object]],
    armature: bpy.types.Object,
) -> None:
    for bone_name, parts in parts_by_bone.items():
        if bone_name not in armature.data.bones:
            raise RuntimeError(f"spider part references missing bone: {bone_name}")
        for part in parts:
            world_transform = part.matrix_world.copy()
            part.parent = armature
            part.parent_type = "BONE"
            part.parent_bone = bone_name
            part.matrix_world = world_transform


def _build_spider_actions(armature: bpy.types.Object) -> None:
    make_action(armature, "idle", 28, [
        (1, {}),
        (14, {"Abdomen": {"rot": (3, 0, 0), "loc": (0.0, 0.0, 0.025)}, "Mandible.L": {"rot": (0, 0, -5)}, "Mandible.R": {"rot": (0, 0, 5)}}),
        (28, {}),
    ])
    make_action(armature, "run", 12, [
        (1, {"Thorax": {"loc": (0.0, 0.0, 0.04)}, "Leg1.L": {"rot": (0, 0, 14)}, "Leg2.R": {"rot": (0, 0, -14)}, "Leg3.L": {"rot": (0, 0, -12)}, "Leg4.R": {"rot": (0, 0, 12)}}),
        (6, {"Thorax": {"loc": (0.0, 0.0, -0.02)}, "Leg1.R": {"rot": (0, 0, -14)}, "Leg2.L": {"rot": (0, 0, 14)}, "Leg3.R": {"rot": (0, 0, 12)}, "Leg4.L": {"rot": (0, 0, -12)}}),
        (12, {"Thorax": {"loc": (0.0, 0.0, 0.04)}, "Leg1.L": {"rot": (0, 0, 14)}, "Leg2.R": {"rot": (0, 0, -14)}, "Leg3.L": {"rot": (0, 0, -12)}, "Leg4.R": {"rot": (0, 0, 12)}}),
    ])
    make_action(armature, "hurt", 7, [
        (1, {"Thorax": {"rot": (12, 0, 8), "loc": (0.0, 0.05, 0.0)}, "Abdomen": {"rot": (-10, 0, -8)}}),
        (4, {"Thorax": {"rot": (-5, 0, -4)}}),
        (7, {}),
    ])
    make_action(armature, "stunned", 12, [
        (1, {"Head": {"rot": (0, 0, 10)}, "Abdomen": {"rot": (0, 0, -7)}}),
        (6, {"Head": {"rot": (0, 0, -10)}, "Abdomen": {"rot": (0, 0, 7)}}),
        (12, {"Head": {"rot": (0, 0, 10)}, "Abdomen": {"rot": (0, 0, -7)}}),
    ])
    make_action(armature, "death", 18, [
        (1, {}),
        (8, {"Thorax": {"rot": (35, 0, 0), "loc": (0.0, 0.0, -0.12)}, "Abdomen": {"rot": (25, 0, 10)}}),
        (18, {"Thorax": {"rot": (85, 0, 0), "loc": (0.0, 0.0, -0.32)}, "Leg1.L": {"rot": (0, 0, 42)}, "Leg1.R": {"rot": (0, 0, -42)}, "Leg4.L": {"rot": (0, 0, -36)}, "Leg4.R": {"rot": (0, 0, 36)}}),
    ])
    make_action(armature, "kick", 7, [
        (1, {"Leg1.L": {"rot": (0, -18, 18)}}),
        (3, {"Leg1.L": {"rot": (0, 32, -30)}, "Thorax": {"rot": (0, 7, 0)}}),
        (7, {}),
    ])
    make_action(armature, "lift", 8, [
        (1, {"Leg1.L": {"rot": (-24, 0, -16)}, "Leg1.R": {"rot": (-24, 0, 16)}, "Head": {"rot": (-8, 0, 0)}}),
        (4, {"Leg1.L": {"rot": (-38, 0, -24)}, "Leg1.R": {"rot": (-38, 0, 24)}, "Thorax": {"loc": (0.0, 0.0, 0.06)}}),
        (8, {}),
    ])
    make_action(armature, "pickup", 6, [
        (1, {"Head": {"rot": (12, 0, 0)}, "Mandible.L": {"rot": (0, 0, -12)}, "Mandible.R": {"rot": (0, 0, 12)}}),
        (3, {"Head": {"rot": (24, 0, 0), "loc": (0.0, -0.03, -0.03)}, "Mandible.L": {"rot": (0, 0, 18)}, "Mandible.R": {"rot": (0, 0, -18)}}),
        (6, {}),
    ])
    make_action(armature, "throw_weapon", 7, [
        (1, {"Leg1.R": {"rot": (0, -25, -28)}, "Thorax": {"rot": (0, -10, 0)}}),
        (4, {"Leg1.R": {"rot": (0, 35, 38)}, "Thorax": {"rot": (0, 12, 0)}}),
        (7, {}),
    ])
    make_action(armature, "throw_furniture", 8, [
        (1, {"Leg1.L": {"rot": (-28, 0, -18)}, "Leg1.R": {"rot": (-28, 0, 18)}, "Thorax": {"rot": (-10, 0, 0)}}),
        (5, {"Leg1.L": {"rot": (24, 0, 16)}, "Leg1.R": {"rot": (24, 0, -16)}, "Thorax": {"rot": (14, 0, 0)}}),
        (8, {}),
    ])
    make_action(armature, "block", 8, [
        (1, {"Leg1.L": {"rot": (-20, 0, -22)}, "Leg1.R": {"rot": (-20, 0, 22)}, "Head": {"rot": (-8, 0, 0)}}),
        (4, {"Thorax": {"rot": (-14, 0, 0), "loc": (0.0, 0.025, -0.035)}, "Abdomen": {"rot": (8, 0, 0)}}),
        (8, {}),
    ])
    make_action(armature, "slash", 8, [
        (1, {"Mandible.L": {"rot": (0, -12, -25)}, "Mandible.R": {"rot": (0, 12, 25)}, "Head": {"rot": (0, -6, 0)}}),
        (4, {"Mandible.L": {"rot": (0, 20, 32)}, "Mandible.R": {"rot": (0, -20, -32)}, "Head": {"rot": (0, 8, 0)}}),
        (8, {}),
    ])
    make_action(armature, "claw_swipe", 8, [
        (1, {"Leg1.R": {"rot": (0, -18, -34)}, "Thorax": {"rot": (0, -8, 0)}}),
        (4, {"Leg1.R": {"rot": (0, 28, 40)}, "Thorax": {"rot": (0, 10, 0)}}),
        (8, {}),
    ])
    make_action(armature, "default", 1, [(1, {"Root": {"rot": (0, 0, 0)}})])


def main() -> None:
    reject_target_override(MODEL_ID)
    _assert_authored_contract()
    reset_scene()
    root, parts, parts_by_bone = build_spider()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_single_face_connected_component(parts, label=MODEL_ID)

    root.rotation_euler.z = FACING_ROT_Z
    bpy.context.view_layer.update()
    export_static_glb(root, STATIC_OUTPUT)

    root.rotation_euler.z = 0.0
    bpy.context.view_layer.update()
    armature = _create_spider_armature()
    _parent_parts_to_spider_bones(parts_by_bone, armature)
    _build_spider_actions(armature)
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
    render_real_views(PREVIEW_DIR, "voxel_spider", center, scale, camera)

    print(f"Wrote {STATIC_OUTPUT}")
    print(f"Wrote {RIG_OUTPUT}")
    print(f"Parts: {AUTHORED_PART_COUNT}; envelope: {TARGET_ENVELOPE_PX}px; front: Blender -Y")


if __name__ == "__main__":
    main()
