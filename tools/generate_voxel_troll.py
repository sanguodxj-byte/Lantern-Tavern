from __future__ import annotations

"""Author and export the single Lantern Tavern troll model.

The troll faces Blender -Y. Its authored boxes occupy exactly 44 x 64 x 24
pixels at the project scale of 32 px per metre. Every proportion, contour,
palette choice, and identity anchor in this file belongs only to this troll.
"""

import math
import sys
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


MODEL_ID = "troll"
TARGET_ENVELOPE_PX = (44.0, 64.0, 24.0)
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_troll_64x.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_troll_64x_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


def build_troll() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
    """Build one authored moss-rock troll as a face-connected box assembly."""
    root = make_root("voxel_troll_64x")

    # A deliberate three-step skin ramp separates planes at gameplay distance.
    skin_high = make_material("Troll_Skin_High", (0.43, 0.53, 0.25, 1.0))
    skin_mid = make_material("Troll_Skin_Mid", (0.27, 0.36, 0.17, 1.0))
    skin_dark = make_material("Troll_Skin_Dark", (0.13, 0.20, 0.11, 1.0))
    skin_moss = make_material("Troll_Skin_Moss", (0.34, 0.43, 0.16, 1.0))
    eye_dark = make_material("Troll_Eye_Socket", (0.035, 0.045, 0.025, 1.0))
    eye_amber = make_material("Troll_Eye_Amber", (0.82, 0.43, 0.075, 1.0), emission=0.45)
    tusk_high = make_material("Troll_Tusk_High", (0.78, 0.72, 0.52, 1.0))
    tusk_dark = make_material("Troll_Tusk_Dark", (0.43, 0.38, 0.25, 1.0))
    scute_high = make_material("Troll_Scute_High", (0.31, 0.29, 0.17, 1.0))
    scute_dark = make_material("Troll_Scute_Dark", (0.15, 0.15, 0.095, 1.0))
    cloth_high = make_material("Troll_Loincloth_High", (0.39, 0.22, 0.12, 1.0))
    cloth_mid = make_material("Troll_Loincloth_Mid", (0.24, 0.12, 0.075, 1.0))
    cloth_dark = make_material("Troll_Loincloth_Dark", (0.12, 0.065, 0.045, 1.0))

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

    # Short, load-bearing legs and broad splayed feet establish the low centre
    # of gravity. Toe clusters break the footprint instead of using shoe boxes.
    add("foot_left_core", (-5.5, -3.5, 2.0), (9.0, 11.0, 4.0), skin_dark, "Foot.L")
    add("foot_left_outer_toe", (-11.0, -5.0, 1.5), (2.0, 6.0, 3.0), skin_mid, "Foot.L")
    add("foot_left_front_toe", (-7.5, -10.0, 1.0), (3.0, 2.0, 2.0), skin_high, "Foot.L")
    add("foot_right_core", (5.5, -3.0, 2.0), (9.0, 10.0, 4.0), skin_mid, "Foot.R")
    add("foot_right_outer_toe", (11.0, -4.5, 1.5), (2.0, 5.0, 3.0), skin_dark, "Foot.R")
    add("foot_right_front_toe", (7.5, -9.0, 1.0), (3.0, 2.0, 2.0), skin_high, "Foot.R")

    add("lower_leg_left", (-5.5, 1.5, 8.0), (7.0, 7.0, 8.0), skin_mid, "LowerLeg.L")
    add("shin_plate_left", (-5.5, -3.0, 8.5), (5.0, 2.0, 5.0), skin_high, "LowerLeg.L")
    add("lower_leg_right", (5.5, 1.5, 8.0), (7.0, 7.0, 8.0), skin_dark, "LowerLeg.R")
    add("shin_plate_right", (5.5, -3.0, 8.0), (5.0, 2.0, 4.0), skin_mid, "LowerLeg.R")
    add("knee_left", (-5.5, 1.0, 14.0), (9.0, 8.0, 4.0), skin_high, "LowerLeg.L")
    add("knee_right", (5.5, 1.0, 14.0), (9.0, 8.0, 4.0), skin_mid, "LowerLeg.R")
    add("thigh_left", (-5.0, 2.5, 20.0), (8.0, 7.0, 8.0), skin_mid, "UpperLeg.L")
    add("thigh_right", (5.0, 2.5, 20.0), (8.0, 7.0, 8.0), skin_dark, "UpperLeg.R")

    # The pelvis bridges both legs. Its rear mass and offset hips keep the top
    # view thick while leaving the front free for a genuinely separate wrap.
    add("pelvis_core", (0.0, 3.0, 27.0), (18.0, 8.0, 6.0), skin_dark, "Pelvis")
    add("hip_left", (-11.0, 3.0, 26.5), (4.0, 8.0, 5.0), skin_mid, "Pelvis")
    add("hip_right", (11.0, 3.0, 26.5), (4.0, 8.0, 5.0), skin_high, "Pelvis")
    add("pelvis_back", (0.0, 8.0, 27.0), (16.0, 2.0, 4.0), skin_mid, "Pelvis")

    # Torso masses step forward from pelvis to belly to chest. Side flanks and
    # split pectorals make a broken Barony-like contour rather than one cuboid.
    add("abdomen_core", (0.0, 3.0, 34.5), (22.0, 10.0, 9.0), skin_mid, "Torso")
    add("belly_front_lower", (0.0, -3.5, 33.5), (18.0, 3.0, 5.0), skin_high, "Torso")
    add("belly_front_upper", (0.0, -4.0, 37.5), (20.0, 4.0, 3.0), skin_moss, "Torso")
    add("flank_left", (-12.5, 3.0, 35.0), (3.0, 8.0, 6.0), skin_dark, "Torso")
    add("flank_right", (12.0, 3.0, 36.0), (2.0, 8.0, 6.0), skin_high, "Torso")
    add("chest_core", (0.0, 2.5, 43.5), (28.0, 11.0, 9.0), skin_mid, "Torso")
    add("pectoral_left", (-6.5, -4.5, 44.5), (13.0, 3.0, 5.0), skin_high, "Torso")
    add("pectoral_right", (6.5, -4.5, 44.0), (13.0, 3.0, 6.0), skin_dark, "Torso")
    add("chest_moss_left", (-9.0, -6.5, 45.5), (5.0, 1.0, 2.0), skin_moss, "Torso")

    # Shoulder width is built from five stepped clusters. The torso leans into
    # the head while the outer masses provide clear arm attachment shelves.
    add("upper_back_core", (0.0, 3.0, 51.5), (20.0, 10.0, 7.0), skin_dark, "Torso")
    add("shoulder_left_inner", (-12.5, 3.0, 52.0), (5.0, 10.0, 6.0), skin_mid, "Torso")
    add("shoulder_left_outer", (-17.0, 3.0, 51.5), (4.0, 8.0, 5.0), skin_high, "Torso")
    add("shoulder_right_inner", (13.0, 3.0, 51.0), (6.0, 10.0, 6.0), skin_high, "Torso")
    add("shoulder_right_outer", (18.0, 3.0, 50.5), (4.0, 8.0, 5.0), skin_mid, "Torso")
    add("shoulder_moss_left", (-12.5, -2.5, 52.5), (5.0, 1.0, 3.0), skin_moss, "Torso")

    # Horny dorsal plates own the full 24px side envelope. Each ridge is a
    # second depth layer attached to a base, readable from side and top views.
    add("dorsal_scute_low_base", (0.0, 8.5, 35.5), (8.0, 1.0, 5.0), scute_dark, "Torso")
    add("dorsal_scute_low_ridge", (0.0, 9.5, 35.5), (4.0, 1.0, 3.0), scute_high, "Torso")
    add("dorsal_scute_mid_base", (0.0, 8.5, 44.0), (10.0, 1.0, 6.0), scute_dark, "Torso")
    add("dorsal_scute_mid_ridge", (0.0, 9.5, 44.0), (6.0, 1.0, 4.0), scute_high, "Torso")
    add("dorsal_scute_high_base", (0.0, 8.5, 51.5), (12.0, 1.0, 5.0), scute_dark, "Torso")
    add("dorsal_scute_high_ridge", (0.0, 9.5, 51.5), (6.0, 1.0, 3.0), scute_high, "Torso")

    # Long arms descend below the short thighs. Unequal heights and front depth
    # offsets keep the silhouette intentionally asymmetric.
    add("upper_arm_left", (-17.0, 3.0, 44.0), (6.0, 8.0, 10.0), skin_mid, "UpperArm.L")
    add("elbow_left", (-17.5, 2.5, 37.0), (7.0, 9.0, 4.0), skin_high, "LowerArm.L")
    add("forearm_left", (-18.5, 1.5, 29.5), (7.0, 9.0, 11.0), skin_dark, "LowerArm.L")
    add("wrist_left", (-18.0, 1.0, 22.5), (6.0, 10.0, 3.0), skin_mid, "Hand.L")
    add("palm_left", (-18.0, -0.5, 17.5), (8.0, 11.0, 7.0), skin_mid, "Hand.L")
    add("knuckles_left", (-18.0, -7.0, 18.0), (8.0, 2.0, 4.0), skin_high, "Hand.L")
    add("fingers_left_outer", (-20.0, -1.0, 12.0), (4.0, 10.0, 4.0), skin_dark, "Hand.L")
    add("fingers_left_inner", (-16.0, -0.5, 12.5), (4.0, 9.0, 3.0), skin_mid, "Hand.L")

    add("upper_arm_right", (17.0, 2.5, 43.0), (6.0, 9.0, 10.0), skin_dark, "UpperArm.R")
    add("elbow_right", (17.5, 2.0, 36.0), (7.0, 10.0, 4.0), skin_mid, "LowerArm.R")
    add("forearm_right", (18.5, 2.0, 28.5), (7.0, 8.0, 11.0), skin_high, "LowerArm.R")
    add("wrist_right", (18.0, 1.0, 21.5), (6.0, 10.0, 3.0), skin_dark, "Hand.R")
    add("palm_right", (18.0, -1.0, 16.5), (8.0, 12.0, 7.0), skin_high, "Hand.R")
    add("knuckles_right", (18.0, -8.0, 17.0), (8.0, 2.0, 4.0), skin_mid, "Hand.R")
    add("fingers_right_outer", (20.0, -1.0, 11.0), (4.0, 10.0, 4.0), skin_dark, "Hand.R")
    add("fingers_right_inner", (16.0, -1.0, 11.5), (4.0, 10.0, 3.0), skin_mid, "Hand.R")

    # The head is tucked into the shoulders. Brow, sockets, nose, lip, and
    # tusks occupy separate depth layers so the face reads in real side views.
    add("neck_hump", (0.0, 3.5, 56.5), (12.0, 7.0, 3.0), skin_dark, "Neck")
    add("head_cranium", (0.0, 0.5, 61.0), (18.0, 9.0, 4.0), skin_mid, "Head")
    add("scalp_ridge", (0.0, 1.0, 63.5), (14.0, 6.0, 1.0), skin_moss, "Head")
    add("jaw_core", (0.0, -4.5, 56.5), (20.0, 5.0, 5.0), skin_dark, "Head")
    add("cheek_left", (-11.0, -3.0, 57.0), (2.0, 4.0, 4.0), skin_mid, "Head")
    add("cheek_right", (11.0, -3.0, 56.5), (2.0, 4.0, 3.0), skin_high, "Head")
    add("ear_left", (-13.0, -0.5, 58.0), (2.0, 3.0, 2.0), skin_dark, "Head")
    add("ear_right", (13.0, -1.0, 57.5), (2.0, 2.0, 1.0), skin_mid, "Head")

    add("eye_socket_left", (-5.5, -7.5, 57.0), (5.0, 1.0, 2.0), eye_dark, "Head")
    add("eye_socket_right", (5.5, -7.5, 57.0), (5.0, 1.0, 2.0), eye_dark, "Head")
    add("eye_left", (-5.5, -8.5, 56.5), (2.0, 1.0, 1.0), eye_amber, "Head")
    add("eye_right", (5.5, -8.5, 56.5), (2.0, 1.0, 1.0), eye_amber, "Head")
    add("brow_left", (-6.5, -8.0, 59.5), (7.0, 2.0, 3.0), skin_dark, "Head")
    add("brow_right", (6.5, -8.0, 59.0), (7.0, 2.0, 2.0), skin_mid, "Head")
    add("nose_bridge", (0.0, -8.0, 58.5), (6.0, 2.0, 3.0), skin_high, "Head")
    add("nose_bulb", (0.0, -10.5, 56.5), (8.0, 3.0, 3.0), skin_mid, "Head")
    add("nostril_left", (-2.5, -12.5, 56.0), (3.0, 1.0, 2.0), skin_dark, "Head")
    add("nostril_right", (2.5, -12.5, 56.0), (3.0, 1.0, 2.0), skin_dark, "Head")
    add("lower_lip", (0.0, -8.0, 54.0), (10.0, 2.0, 2.0), skin_moss, "Head")

    add("tusk_left_root", (-7.0, -8.5, 54.5), (4.0, 3.0, 3.0), tusk_dark, "Head")
    add("tusk_left_outflare", (-10.0, -10.0, 55.0), (2.0, 4.0, 2.0), tusk_high, "Head")
    add("tusk_left_forward_tip", (-10.0, -13.0, 55.5), (2.0, 2.0, 1.0), tusk_high, "Head")
    add("tusk_right_root", (7.0, -8.5, 54.5), (4.0, 3.0, 3.0), tusk_dark, "Head")
    add("tusk_right_outflare", (10.0, -10.0, 56.0), (2.0, 4.0, 2.0), tusk_high, "Head")
    add("tusk_right_chipped_tip", (10.0, -12.5, 56.5), (2.0, 1.0, 1.0), tusk_dark, "Head")

    # A separate tied wrap and uneven hanging panels make the loincloth read as
    # worn equipment rather than painted body colour.
    add("loincloth_belt", (0.0, -2.0, 27.5), (22.0, 2.0, 3.0), cloth_dark, "Pelvis")
    add("loincloth_knot", (0.0, -4.0, 27.5), (4.0, 2.0, 3.0), cloth_high, "Pelvis")
    add("loincloth_upper", (0.0, -4.0, 24.0), (14.0, 2.0, 4.0), cloth_mid, "Pelvis")
    add("loincloth_left_torn", (-4.0, -4.0, 19.0), (6.0, 2.0, 6.0), cloth_dark, "Pelvis")
    add("loincloth_right_torn", (4.0, -4.0, 20.0), (6.0, 2.0, 4.0), cloth_mid, "Pelvis")
    add("loincloth_left_fray", (-5.5, -4.0, 14.5), (3.0, 2.0, 3.0), cloth_dark, "Pelvis")
    add("loincloth_right_fray", (5.5, -4.0, 17.0), (3.0, 2.0, 2.0), cloth_high, "Pelvis")
    add("loincloth_patch_left", (-4.0, -5.5, 19.5), (4.0, 1.0, 3.0), cloth_high, "Pelvis")
    add("loincloth_patch_right", (4.0, -5.5, 20.5), (4.0, 1.0, 3.0), cloth_dark, "Pelvis")

    return root, parts, parts_by_bone


def _assert_authored_envelope(parts: list[bpy.types.Object]) -> None:
    minimum = [min(obj.location[axis] - obj.dimensions[axis] * 0.5 for obj in parts) for axis in range(3)]
    maximum = [max(obj.location[axis] + obj.dimensions[axis] * 0.5 for obj in parts) for axis in range(3)]
    blender_size_px = tuple(round((maximum[axis] - minimum[axis]) * 32.0, 4) for axis in range(3))
    size_px = (blender_size_px[0], blender_size_px[2], blender_size_px[1])
    if size_px != TARGET_ENVELOPE_PX:
        raise RuntimeError(f"troll envelope is {size_px}px, expected {TARGET_ENVELOPE_PX}px")


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts, parts_by_bone = build_troll()
    _assert_authored_envelope(parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_single_face_connected_component(parts, label=MODEL_ID)

    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    export_static_glb(root, STATIC_OUTPUT)

    root.rotation_euler.z = 0.0
    bpy.context.view_layer.update()
    armature = create_voxel_humanoid_armature(height_px=64.0, name="TrollRig")
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
    render_real_views(PREVIEW_DIR, "voxel_troll", center, scale, camera)

    print(f"Wrote {STATIC_OUTPUT}")
    print(f"Wrote {RIG_OUTPUT}")
    print(f"Envelope: {TARGET_ENVELOPE_PX}px; front: Blender -Y")


if __name__ == "__main__":
    main()
