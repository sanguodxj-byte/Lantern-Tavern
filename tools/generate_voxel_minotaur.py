from __future__ import annotations

"""Author and export exactly one independently designed minotaur.

The model faces Blender -Y and occupies 48 x 72 x 28 pixels at 32 px per
metre.  Its long bovine legs, high shoulder chest, 22 x 17 x 18 pixel bull
head, broken right horn, left hip moss knot, work skirt, and clean hands are
owned here.  This file is not a humanoid or creature-family body template.
"""

import math
import sys
from dataclasses import dataclass
from pathlib import Path

import bpy


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
from voxel_overlap_guard import (
    assert_parts_no_positive_volume_overlap,
    assert_parts_single_face_connected_component,
)
from voxel_single_model_cli import reject_target_override


MODEL_ID = "minotaur"
TARGET_ENVELOPE_PX = (48.0, 72.0, 32.0)
HEAD_ENVELOPE_PX = (22.0, 17.0, 18.0)
AUTHORED_PART_COUNT = 97
MIN_SOLID_ENVELOPE_RATIO = 0.14
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_minotaur_72px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_minotaur_72px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


@dataclass(frozen=True)
class PartSpec:
    name: str
    center_px: tuple[float, float, float]
    size_px: tuple[float, float, float]
    material_key: str
    bone: str


# Every primary mass and identity anchor is explicitly authored for this one
# minotaur.  The one-line format is deliberate: the companion gdUnit test
# parses the Python AST-shaped records without importing Blender.
PART_SPECS: tuple[PartSpec, ...] = (
    # Split hooves and rear-shifted hocks establish the thick digitigrade legs.
    PartSpec("hoof_left_outer", (-11.5, -6.0, 2.0), (7.0, 10.0, 4.0), "hoof_deep", "Foot.L"),
    PartSpec("hoof_left_inner", (-3.5, -6.0, 2.0), (7.0, 10.0, 4.0), "hoof_mid", "Foot.L"),
    PartSpec("hoof_crown_left", (-8.5, -2.0, 6.0), (10.0, 9.0, 4.0), "hoof_high", "Foot.L"),
    PartSpec("fetlock_left", (-8.5, 2.0, 10.5), (8.0, 8.0, 5.0), "fur_deep", "LowerLeg.L"),
    PartSpec("rear_hock_left", (-8.5, 5.5, 15.5), (10.0, 8.0, 5.0), "fur_mid", "LowerLeg.L"),
    PartSpec("long_shank_left", (-8.5, 5.0, 22.5), (9.0, 9.0, 9.0), "fur_deep", "LowerLeg.L"),
    PartSpec("knee_left", (-8.5, 4.0, 29.0), (10.0, 9.0, 4.0), "fur_high", "UpperLeg.L"),
    PartSpec("long_thigh_left", (-7.5, 3.5, 34.0), (12.0, 10.0, 6.0), "fur_mid", "UpperLeg.L"),
    PartSpec("hoof_right_outer", (11.5, -6.0, 2.0), (7.0, 10.0, 4.0), "hoof_deep", "Foot.R"),
    PartSpec("hoof_right_inner", (3.5, -6.0, 2.0), (7.0, 10.0, 4.0), "hoof_mid", "Foot.R"),
    PartSpec("hoof_crown_right", (8.5, -2.0, 6.0), (10.0, 9.0, 4.0), "hoof_high", "Foot.R"),
    PartSpec("fetlock_right", (8.5, 2.0, 10.5), (8.0, 8.0, 5.0), "fur_deep", "LowerLeg.R"),
    PartSpec("rear_hock_right", (8.5, 5.5, 15.5), (10.0, 8.0, 5.0), "fur_mid", "LowerLeg.R"),
    PartSpec("long_shank_right", (8.5, 5.0, 22.5), (9.0, 9.0, 9.0), "fur_deep", "LowerLeg.R"),
    PartSpec("knee_right", (8.5, 4.0, 29.0), (10.0, 9.0, 4.0), "fur_high", "UpperLeg.R"),
    PartSpec("long_thigh_right", (7.5, 3.5, 34.0), (12.0, 10.0, 6.0), "fur_mid", "UpperLeg.R"),

    # Pelvis, burgundy belt and broken charcoal rye-cloth skirt.
    PartSpec("pelvis_center", (0.0, 1.0, 40.5), (8.0, 10.0, 7.0), "fur_deep", "Pelvis"),
    PartSpec("pelvis_left", (-8.0, 1.0, 40.5), (8.0, 10.0, 7.0), "fur_mid", "Pelvis"),
    PartSpec("pelvis_right", (8.0, 1.0, 40.5), (8.0, 10.0, 7.0), "fur_mid", "Pelvis"),
    PartSpec("burgundy_belt_left", (-7.0, -4.5, 42.0), (8.0, 1.0, 4.0), "burgundy_deep", "Pelvis"),
    PartSpec("burgundy_belt_center", (0.0, -4.5, 42.0), (6.0, 1.0, 4.0), "burgundy_mid", "Pelvis"),
    PartSpec("burgundy_belt_right", (7.0, -4.5, 42.0), (8.0, 1.0, 4.0), "burgundy_deep", "Pelvis"),
    PartSpec("burgundy_belt_highlight", (0.0, -5.5, 42.5), (4.0, 1.0, 1.0), "burgundy_high", "Pelvis"),
    PartSpec("forged_belt_buckle", (0.0, -6.5, 41.5), (4.0, 1.0, 3.0), "iron_mid", "Pelvis"),
    PartSpec("forged_buckle_glint", (0.0, -7.5, 41.5), (2.0, 1.0, 1.0), "iron_high", "Pelvis"),
    PartSpec("rye_skirt_left_outer", (-8.0, -4.5, 37.0), (6.0, 1.0, 6.0), "cloth_deep", "Pelvis"),
    PartSpec("rye_skirt_left_inner", (-2.5, -4.5, 36.5), (5.0, 1.0, 7.0), "cloth_mid", "Pelvis"),
    PartSpec("rye_skirt_right_inner", (2.5, -4.5, 36.5), (5.0, 1.0, 7.0), "cloth_mid", "Pelvis"),
    PartSpec("rye_skirt_right_outer", (8.0, -4.5, 37.0), (6.0, 1.0, 6.0), "cloth_deep", "Pelvis"),
    PartSpec("rye_skirt_side_left", (-14.5, 1.0, 37.5), (2.0, 10.0, 5.0), "cloth_high", "Pelvis"),
    PartSpec("rye_skirt_side_right", (14.5, 1.0, 37.5), (2.0, 10.0, 5.0), "cloth_high", "Pelvis"),
    PartSpec("moss_knot_left", (-14.5, -5.5, 38.5), (2.0, 3.0, 3.0), "moss_high", "Pelvis"),
    PartSpec("moss_twist_left", (-14.5, -5.5, 35.5), (2.0, 2.0, 3.0), "moss_mid", "Pelvis"),
    PartSpec("moss_tip_left", (-14.5, -5.5, 33.0), (2.0, 2.0, 2.0), "moss_deep", "Pelvis"),

    # A short stepped tail makes the rear silhouette readable without a pack.
    PartSpec("tail_base", (0.0, 7.5, 44.0), (4.0, 3.0, 4.0), "fur_high", "Pelvis"),
    PartSpec("tail_bend", (0.0, 10.0, 41.0), (4.0, 2.0, 4.0), "fur_mid", "Pelvis"),
    PartSpec("tail_tip", (0.0, 12.0, 38.0), (4.0, 2.0, 4.0), "fur_deep", "Pelvis"),
    PartSpec("tail_tuft", (0.0, 14.5, 37.5), (8.0, 3.0, 5.0), "fur_high", "Pelvis"),

    # High massive shoulder chest and symmetric dark-brown working straps.
    PartSpec("abdomen_keel", (0.0, 1.0, 46.5), (18.0, 10.0, 5.0), "fur_deep", "Torso"),
    PartSpec("high_chest_core", (0.0, 1.0, 52.0), (23.0, 10.0, 6.0), "fur_mid", "Torso"),
    PartSpec("chest_flank_left", (-13.5, 1.0, 52.0), (4.0, 10.0, 4.0), "fur_deep", "Torso"),
    PartSpec("chest_flank_right", (13.5, 1.0, 52.0), (4.0, 10.0, 4.0), "fur_deep", "Torso"),
    PartSpec("high_shoulder_yoke", (0.0, 1.0, 57.5), (26.0, 10.0, 5.0), "fur_high", "Torso"),
    PartSpec("neck_column", (0.0, 2.0, 62.0), (14.0, 8.0, 4.0), "fur_deep", "Neck"),
    PartSpec("neck_front_step", (0.0, -3.0, 61.5), (14.0, 2.0, 3.0), "fur_mid", "Neck"),
    PartSpec("shoulder_strap_left", (-9.5, -5.0, 56.5), (3.0, 1.0, 3.0), "strap_deep_brown", "Torso"),
    PartSpec("shoulder_strap_right", (9.5, -5.0, 56.5), (3.0, 1.0, 3.0), "strap_deep_brown", "Torso"),
    PartSpec("chest_strap_left", (-8.5, -5.0, 52.0), (3.0, 1.0, 6.0), "strap_mid_brown", "Torso"),
    PartSpec("chest_strap_right", (8.5, -5.0, 52.0), (3.0, 1.0, 6.0), "strap_mid_brown", "Torso"),
    PartSpec("strap_buckle_left", (-9.0, -6.0, 52.5), (2.0, 1.0, 3.0), "iron_deep", "Torso"),
    PartSpec("strap_buckle_right", (9.0, -6.0, 52.5), (2.0, 1.0, 3.0), "iron_deep", "Torso"),

    # Massive symmetric arms end in heavy body-only Hand.R / Hand.L clusters.
    PartSpec("shoulder_cap_left", (-17.5, 1.0, 56.5), (9.0, 10.0, 5.0), "fur_high", "UpperArm.L"),
    PartSpec("upper_arm_high_left", (-19.5, 1.5, 51.5), (8.0, 8.0, 5.0), "fur_mid", "UpperArm.L"),
    PartSpec("upper_arm_low_left", (-19.5, 1.5, 47.0), (8.0, 8.0, 4.0), "fur_deep", "UpperArm.L"),
    PartSpec("elbow_left", (-19.5, 1.5, 43.5), (8.0, 8.0, 3.0), "fur_high", "LowerArm.L"),
    PartSpec("forearm_high_left", (-19.5, 1.5, 39.5), (8.0, 8.0, 5.0), "fur_mid", "LowerArm.L"),
    PartSpec("forearm_low_left", (-19.5, 1.5, 35.0), (8.0, 8.0, 4.0), "fur_deep", "LowerArm.L"),
    PartSpec("wrist_left", (-19.5, 1.0, 31.0), (8.0, 8.0, 4.0), "fur_mid", "Hand.L"),
    PartSpec("hand_left_palm", (-19.5, 0.5, 26.5), (9.0, 9.0, 5.0), "fur_high", "Hand.L"),
    PartSpec("hand_left_fingers", (-19.5, -0.5, 22.0), (9.0, 9.0, 4.0), "fur_deep", "Hand.L"),
    PartSpec("shoulder_cap_right", (17.5, 1.0, 56.5), (9.0, 10.0, 5.0), "fur_high", "UpperArm.R"),
    PartSpec("upper_arm_high_right", (19.5, 1.5, 51.5), (8.0, 8.0, 5.0), "fur_mid", "UpperArm.R"),
    PartSpec("upper_arm_low_right", (19.5, 1.5, 47.0), (8.0, 8.0, 4.0), "fur_deep", "UpperArm.R"),
    PartSpec("elbow_right", (19.5, 1.5, 43.5), (8.0, 8.0, 3.0), "fur_high", "LowerArm.R"),
    PartSpec("forearm_high_right", (19.5, 1.5, 39.5), (8.0, 8.0, 5.0), "fur_mid", "LowerArm.R"),
    PartSpec("forearm_low_right", (19.5, 1.5, 35.0), (8.0, 8.0, 4.0), "fur_deep", "LowerArm.R"),
    PartSpec("wrist_right", (19.5, 1.0, 31.0), (8.0, 8.0, 4.0), "fur_mid", "Hand.R"),
    PartSpec("hand_right_palm", (19.5, 0.5, 26.5), (9.0, 9.0, 5.0), "fur_high", "Hand.R"),
    PartSpec("hand_right_fingers", (19.5, -0.5, 22.0), (9.0, 9.0, 4.0), "fur_deep", "Hand.R"),

    # The bull head mass itself is exactly 22W x 17H x 18D.  Horns and ears
    # attach outside it; only the complete left horn and broken right cap differ.
    PartSpec("bull_cranium_core", (0.0, 0.0, 68.0), (14.0, 8.0, 8.0), "fur_mid", "Head"),
    PartSpec("bull_cranium_side_left", (-8.0, 0.0, 68.0), (2.0, 8.0, 6.0), "fur_deep", "Head"),
    PartSpec("bull_cranium_side_right", (8.0, 0.0, 68.0), (2.0, 8.0, 6.0), "fur_deep", "Head"),
    PartSpec("forehead_plane", (0.0, -4.5, 69.5), (12.0, 1.0, 3.0), "fur_high", "Head"),
    PartSpec("brow_left", (-3.0, -5.5, 69.0), (6.0, 1.0, 2.0), "fur_deep", "Head"),
    PartSpec("brow_right", (3.0, -5.5, 69.0), (6.0, 1.0, 2.0), "fur_deep", "Head"),
    PartSpec("muzzle_bridge", (0.0, -6.0, 63.5), (10.0, 4.0, 7.0), "muzzle_high", "Head"),
    PartSpec("muzzle_cheek_left", (-8.0, -6.0, 61.0), (6.0, 3.8, 6.0), "muzzle_mid", "Head"),
    PartSpec("muzzle_cheek_right", (8.0, -6.0, 61.0), (6.0, 3.8, 6.0), "muzzle_mid", "Head"),
    PartSpec("broad_scapular_snout", (0.0, -10.0, 60.0), (16.0, 4.0, 6.0), "muzzle_mid", "Head"),
    PartSpec("nostril_left", (-5.0, -14.0, 60.0), (4.0, 4.0, 4.0), "muzzle_deep", "Head"),
    PartSpec("nose_plane_center", (0.0, -14.0, 60.0), (6.0, 4.0, 4.0), "muzzle_high", "Head"),
    PartSpec("nostril_right", (5.0, -14.0, 60.0), (4.0, 4.0, 4.0), "muzzle_deep", "Head"),
    PartSpec("heavy_lower_jaw", (0.0, -8.5, 56.0), (14.0, 5.0, 2.0), "muzzle_deep", "Head"),
    PartSpec("eye_socket_left", (-7.5, -4.5, 66.0), (3.0, 1.0, 2.0), "eye_deep", "Head"),
    PartSpec("eye_iris_left", (-7.5, -5.5, 66.0), (1.0, 1.0, 2.0), "eye_mid", "Head"),
    PartSpec("eye_glint_left", (-7.5, -6.5, 66.5), (1.0, 1.0, 1.0), "eye_high", "Head"),
    PartSpec("eye_socket_right", (7.5, -4.5, 66.0), (3.0, 1.0, 2.0), "eye_deep", "Head"),
    PartSpec("eye_iris_right", (7.5, -5.5, 66.0), (1.0, 1.0, 2.0), "eye_mid", "Head"),
    PartSpec("eye_glint_right", (7.5, -6.5, 66.5), (1.0, 1.0, 1.0), "eye_high", "Head"),
    PartSpec("ear_left", (-11.0, 0.0, 64.5), (4.0, 4.0, 3.0), "fur_high", "Head"),
    PartSpec("ear_right", (11.0, 0.0, 64.5), (4.0, 4.0, 3.0), "fur_high", "Head"),
    PartSpec("horn_left_root", (-11.0, 1.0, 69.0), (4.0, 4.0, 4.0), "horn_deep", "Head"),
    PartSpec("horn_right_root", (11.0, 1.0, 69.0), (4.0, 4.0, 4.0), "horn_deep", "Head"),
    PartSpec("horn_left_rise", (-15.0, 1.0, 70.5), (4.0, 4.0, 3.0), "horn_mid", "Head"),
    PartSpec("horn_left_sweep", (-19.0, 0.5, 71.0), (4.0, 3.0, 2.0), "horn_high", "Head"),
    PartSpec("horn_left_tip", (-22.5, 0.0, 71.5), (3.0, 2.0, 1.0), "horn_high", "Head"),
    PartSpec("horn_right_break_cap", (14.0, 1.0, 69.0), (2.0, 4.0, 2.0), "horn_deep", "Head"),
)


def _build_materials() -> dict[str, bpy.types.Material]:
    """Create deliberate three-stage ramps for every visible material family."""
    return {
        "fur_deep": make_material("Minotaur_Fur_Deep", (0.105, 0.075, 0.052, 1.0)),
        "fur_mid": make_material("Minotaur_Fur_Mid", (0.235, 0.165, 0.105, 1.0)),
        "fur_high": make_material("Minotaur_Fur_High", (0.405, 0.300, 0.185, 1.0)),
        "muzzle_deep": make_material("Minotaur_Muzzle_Deep", (0.115, 0.085, 0.070, 1.0)),
        "muzzle_mid": make_material("Minotaur_Muzzle_Mid", (0.285, 0.205, 0.165, 1.0)),
        "muzzle_high": make_material("Minotaur_Muzzle_High", (0.475, 0.355, 0.275, 1.0)),
        "horn_deep": make_material("Minotaur_Horn_Deep", (0.105, 0.100, 0.090, 1.0)),
        "horn_mid": make_material("Minotaur_Horn_Mid", (0.390, 0.355, 0.290, 1.0)),
        "horn_high": make_material("Minotaur_Horn_High", (0.720, 0.655, 0.500, 1.0)),
        "hoof_deep": make_material("Minotaur_Hoof_Deep", (0.045, 0.050, 0.047, 1.0)),
        "hoof_mid": make_material("Minotaur_Hoof_Mid", (0.125, 0.130, 0.115, 1.0)),
        "hoof_high": make_material("Minotaur_Hoof_High", (0.265, 0.260, 0.220, 1.0)),
        "cloth_deep": make_material("Minotaur_Ryecloth_Deep", (0.035, 0.038, 0.037, 1.0)),
        "cloth_mid": make_material("Minotaur_Ryecloth_Mid", (0.085, 0.090, 0.082, 1.0)),
        "cloth_high": make_material("Minotaur_Ryecloth_High", (0.175, 0.170, 0.145, 1.0)),
        "burgundy_deep": make_material("Minotaur_Burgundy_Deep", (0.105, 0.025, 0.035, 1.0)),
        "burgundy_mid": make_material("Minotaur_Burgundy_Mid", (0.255, 0.055, 0.075, 1.0)),
        "burgundy_high": make_material("Minotaur_Burgundy_High", (0.470, 0.105, 0.120, 1.0)),
        "iron_deep": make_material("Minotaur_Iron_Deep", (0.045, 0.055, 0.060, 1.0), metallic=0.35),
        "iron_mid": make_material("Minotaur_Iron_Mid", (0.170, 0.185, 0.190, 1.0), metallic=0.45),
        "iron_high": make_material("Minotaur_Iron_High", (0.400, 0.420, 0.400, 1.0), metallic=0.55),
        "moss_deep": make_material("Minotaur_Rockmoss_Deep", (0.050, 0.095, 0.060, 1.0)),
        "moss_mid": make_material("Minotaur_Rockmoss_Mid", (0.125, 0.220, 0.115, 1.0)),
        "moss_high": make_material("Minotaur_Rockmoss_High", (0.260, 0.380, 0.170, 1.0)),
        "eye_deep": make_material("Minotaur_Eye_Deep", (0.040, 0.018, 0.012, 1.0)),
        "eye_mid": make_material("Minotaur_Eye_Mid", (0.560, 0.105, 0.035, 1.0), emission=0.35),
        "eye_high": make_material("Minotaur_Eye_High", (1.000, 0.580, 0.120, 1.0), emission=1.8),
        "strap_deep_brown": make_material("Minotaur_Strapping_Deep", (0.075, 0.040, 0.028, 1.0)),
        "strap_mid_brown": make_material("Minotaur_Strapping_Mid", (0.185, 0.095, 0.055, 1.0)),
    }


def build_minotaur() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
    """Build this minotaur's body-only, face-connected authored assembly."""
    root = make_root("voxel_minotaur_72px")
    materials = _build_materials()
    parts: list[bpy.types.Object] = []
    parts_by_bone: dict[str, list[bpy.types.Object]] = {
        "Head": [],
        "Neck": [],
        "Torso": [],
        "Pelvis": [],
        "UpperArm.L": [],
        "LowerArm.L": [],
        "Hand.L": [],
        "UpperArm.R": [],
        "LowerArm.R": [],
        "Hand.R": [],
        "UpperLeg.L": [],
        "LowerLeg.L": [],
        "Foot.L": [],
        "UpperLeg.R": [],
        "LowerLeg.R": [],
        "Foot.R": [],
    }
    for spec in PART_SPECS:
        part = cube_px(spec.name, spec.center_px, spec.size_px, materials[spec.material_key])
        part.parent = root
        parts.append(part)
        parts_by_bone[spec.bone].append(part)
    return root, parts, parts_by_bone


def _authored_bounds_px(specs: tuple[PartSpec, ...]) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    minimum = tuple(min(spec.center_px[axis] - spec.size_px[axis] * 0.5 for spec in specs) for axis in range(3))
    maximum = tuple(max(spec.center_px[axis] + spec.size_px[axis] * 0.5 for spec in specs) for axis in range(3))
    return minimum, maximum


def _assert_authored_contract() -> None:
    if len(PART_SPECS) != AUTHORED_PART_COUNT:
        raise RuntimeError(f"minotaur has {len(PART_SPECS)} parts, expected {AUTHORED_PART_COUNT}")
    minimum, maximum = _authored_bounds_px(PART_SPECS)
    blender_size = tuple(maximum[axis] - minimum[axis] for axis in range(3))
    envelope = (blender_size[0], blender_size[2], blender_size[1])
    if envelope != TARGET_ENVELOPE_PX:
        raise RuntimeError(f"minotaur envelope is {envelope}px, expected {TARGET_ENVELOPE_PX}px")

    by_name = {spec.name: spec for spec in PART_SPECS}
    minimum_widths = {
        "hand_left_palm": 6.0,
        "hand_left_fingers": 6.0,
        "wrist_left": 5.0,
        "forearm_high_left": 6.0,
        "forearm_low_left": 6.0,
        "upper_arm_high_left": 6.0,
        "upper_arm_low_left": 6.0,
        "hand_right_palm": 6.0,
        "hand_right_fingers": 6.0,
        "wrist_right": 5.0,
        "forearm_high_right": 6.0,
        "forearm_low_right": 6.0,
        "upper_arm_high_right": 6.0,
        "upper_arm_low_right": 6.0,
        "hoof_left_outer": 5.0,
        "hoof_left_inner": 5.0,
        "hoof_crown_left": 7.0,
        "fetlock_left": 5.0,
        "rear_hock_left": 7.0,
        "long_shank_left": 5.0,
        "knee_left": 7.0,
        "long_thigh_left": 8.0,
        "hoof_right_outer": 5.0,
        "hoof_right_inner": 5.0,
        "hoof_crown_right": 7.0,
        "fetlock_right": 5.0,
        "rear_hock_right": 7.0,
        "long_shank_right": 5.0,
        "knee_right": 7.0,
        "long_thigh_right": 8.0,
    }
    for part_name, minimum_width in minimum_widths.items():
        actual_width = by_name[part_name].size_px[0]
        if actual_width < minimum_width:
            raise RuntimeError(f"{part_name} is only {actual_width}px wide; minimum is {minimum_width}px")

    minimum_depths = {
        "high_chest_core": 10.0,
        "abdomen_keel": 8.0,
        "high_shoulder_yoke": 8.0,
    }
    for part_name, minimum_depth in minimum_depths.items():
        actual_depth = by_name[part_name].size_px[1]
        if actual_depth < minimum_depth:
            raise RuntimeError(f"{part_name} is only {actual_depth}px deep; minimum is {minimum_depth}px")

    solid_volume = sum(spec.size_px[0] * spec.size_px[1] * spec.size_px[2] for spec in PART_SPECS)
    envelope_volume = blender_size[0] * blender_size[1] * blender_size[2]
    solid_ratio = solid_volume / envelope_volume
    if solid_ratio < MIN_SOLID_ENVELOPE_RATIO:
        raise RuntimeError(
            f"minotaur solid/envelope ratio is {solid_ratio:.4f}; "
            f"minimum is {MIN_SOLID_ENVELOPE_RATIO:.4f}"
        )


def main() -> None:
    reject_target_override(MODEL_ID)
    _assert_authored_contract()
    reset_scene()
    root, parts, parts_by_bone = build_minotaur()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_single_face_connected_component(parts, label=MODEL_ID)

    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    export_static_glb(root, STATIC_OUTPUT)

    root.rotation_euler.z = 0.0
    bpy.context.view_layer.update()
    armature = create_voxel_humanoid_armature(height_px=72.0, name="Armature")
    parent_parts_by_bone(parts_by_bone, armature)
    build_all_actions(armature)
    build_weapon_actions(armature)
    # The rig GLB must expose Armature as its sole top-level authored object.
    # Every mesh has already moved to a bone, so remove the static-only empty.
    bpy.data.objects.remove(root, do_unlink=True)
    armature.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    export_rig_glb(RIG_OUTPUT)

    armature.rotation_euler.z = 0.0
    armature.data.pose_position = "REST"
    bpy.context.view_layer.update()
    center, scale = bounds_center_scale(armature)
    camera = setup_lights_and_camera(center, scale)
    configure_real_render(resolution=1100)
    render_real_views(PREVIEW_DIR, "voxel_minotaur", center, scale, camera)

    print(f"Wrote {STATIC_OUTPUT}")
    print(f"Wrote {RIG_OUTPUT}")
    print(f"Parts: {AUTHORED_PART_COUNT}; envelope: {TARGET_ENVELOPE_PX}px; front: Blender -Y")


if __name__ == "__main__":
    main()
