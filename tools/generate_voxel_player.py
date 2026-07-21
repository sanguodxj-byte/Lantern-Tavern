from __future__ import annotations

"""Author and export the single Lantern Tavern player model.

The player faces Blender -Y. The body occupies exactly 24 x 54 x 14 pixels at
32 pixels per metre. This file owns the player's complete silhouette, palette,
semantic parts, and fixed output identity. It deliberately contains only the
unarmed, unarmoured body and work clothes; gameplay equipment remains external.
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


MODEL_ID = "player"
TARGET_ENVELOPE_PX = (24.0, 54.0, 14.0)
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_player_54px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_player_54px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


def build_player() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
    """Build one authored tavern keeper as a face-connected box assembly."""
    root = make_root("voxel_player_54px")

    # Deep teal work vest: #173C3C / #25514D / #397066 / #609589.
    vest_deep = make_material("Player_Vest_Deep", (0.090, 0.235, 0.235, 1.0))
    vest_dark = make_material("Player_Vest_Dark", (0.145, 0.318, 0.302, 1.0))
    vest_mid = make_material("Player_Vest_Mid", (0.224, 0.439, 0.400, 1.0))
    vest_high = make_material("Player_Vest_High", (0.376, 0.584, 0.537, 1.0))

    # Warm linen rolled-sleeve shirt: #716654 / #A08F73 / #D0B995.
    linen_shadow = make_material("Player_Linen_Shadow", (0.443, 0.400, 0.329, 1.0))
    linen_mid = make_material("Player_Linen_Mid", (0.627, 0.561, 0.451, 1.0))
    linen_high = make_material("Player_Linen_High", (0.816, 0.725, 0.584, 1.0))

    # Wine-red cellar apron: #3A1920 / #5A2830 / #7C3A42 / #A75A59.
    apron_deep = make_material("Player_Apron_Deep", (0.227, 0.098, 0.125, 1.0))
    apron_dark = make_material("Player_Apron_Dark", (0.353, 0.157, 0.188, 1.0))
    apron_mid = make_material("Player_Apron_Mid", (0.486, 0.227, 0.259, 1.0))
    apron_high = make_material("Player_Apron_High", (0.655, 0.353, 0.349, 1.0))

    trouser_shadow = make_material("Player_Trouser_Shadow", (0.125, 0.153, 0.161, 1.0))
    trouser_mid = make_material("Player_Trouser_Mid", (0.204, 0.247, 0.255, 1.0))
    trouser_high = make_material("Player_Trouser_High", (0.325, 0.376, 0.365, 1.0))

    leather_dark = make_material("Player_Leather_Dark", (0.161, 0.102, 0.082, 1.0))
    leather_mid = make_material("Player_Leather_Mid", (0.286, 0.188, 0.145, 1.0))
    leather_high = make_material("Player_Leather_High", (0.455, 0.318, 0.227, 1.0))

    skin_shadow = make_material("Player_Skin_Shadow", (0.459, 0.267, 0.204, 1.0))
    skin_mid = make_material("Player_Skin_Mid", (0.647, 0.408, 0.302, 1.0))
    skin_high = make_material("Player_Skin_High", (0.820, 0.549, 0.412, 1.0))

    hair_deep = make_material("Player_Hair_Deep", (0.114, 0.090, 0.082, 1.0))
    hair_mid = make_material("Player_Hair_Mid", (0.208, 0.149, 0.125, 1.0))
    hair_high = make_material("Player_Hair_High", (0.337, 0.231, 0.176, 1.0))

    brass_dark = make_material("Player_Brass_Dark", (0.459, 0.322, 0.122, 1.0), metallic=0.45)
    brass_mid = make_material("Player_Brass_Mid", (0.706, 0.494, 0.188, 1.0), metallic=0.50)
    brass_high = make_material("Player_Brass_High", (0.867, 0.698, 0.333, 1.0), metallic=0.45)
    eye_dark = make_material("Player_Eye_Dark", (0.055, 0.064, 0.061, 1.0))
    eye_light = make_material("Player_Eye_Light", (0.690, 0.773, 0.722, 1.0))

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

    # Feet and legs form practical, compact workwear rather than heroic armour.
    # The broad toe blocks, not a decorative detail, own the -7px front bound.
    # Feet and legs form practical, compact workwear with solid volume.
    add("boot_sole_left", (-3.5, -1.5, 1.0), (5.0, 9.0, 2.0), leather_dark, "Foot.L")
    add("boot_toe_left", (-3.5, -6.5, 0.5), (5.0, 1.0, 1.0), leather_mid, "Foot.L")
    add("boot_heel_left", (-3.5, 4.0, 1.0), (5.0, 2.0, 2.0), leather_high, "Foot.L")
    add("boot_vamp_left", (-3.5, -0.5, 3.5), (5.0, 6.0, 3.0), leather_mid, "Foot.L")
    add("trouser_calf_left", (-3.5, 0.5, 9.5), (5.0, 6.0, 9.0), trouser_shadow, "LowerLeg.L")
    add("trouser_knee_left", (-3.5, 1.0, 15.5), (6.0, 7.0, 3.0), trouser_high, "LowerLeg.L")
    add("trouser_thigh_left", (-3.5, 1.0, 21.0), (6.0, 7.0, 8.0), trouser_mid, "UpperLeg.L")

    add("boot_sole_right", (3.5, -1.5, 1.0), (5.0, 9.0, 2.0), leather_dark, "Foot.R")
    add("boot_toe_right", (3.5, -6.5, 0.5), (5.0, 1.0, 1.0), leather_mid, "Foot.R")
    add("boot_heel_right", (3.5, 4.0, 1.0), (5.0, 2.0, 2.0), leather_high, "Foot.R")
    add("boot_vamp_right", (3.5, -0.5, 3.5), (5.0, 6.0, 3.0), leather_mid, "Foot.R")
    add("trouser_calf_right", (3.5, 0.5, 9.5), (5.0, 6.0, 9.0), trouser_shadow, "LowerLeg.R")
    add("trouser_knee_right", (3.5, 1.0, 15.5), (6.0, 7.0, 3.0), trouser_high, "LowerLeg.R")
    add("trouser_thigh_right", (3.5, 1.0, 21.0), (6.0, 7.0, 8.0), trouser_mid, "UpperLeg.R")

    # Waist bridge and short cellar apron.
    add("waist_trouser_bridge", (0.0, 0.5, 27.0), (12.0, 8.0, 4.0), trouser_shadow, "Pelvis")
    add("merchant_belt_front", (0.0, -4.0, 28.0), (12.0, 1.0, 2.0), leather_dark, "Pelvis")
    add("merchant_belt_buckle", (0.0, -5.0, 28.0), (2.0, 1.0, 1.0), brass_mid, "Pelvis")
    add("cellar_apron_wrap", (0.0, -4.0, 26.0), (12.0, 1.0, 2.0), apron_dark, "Pelvis")
    add("cellar_apron_side_left", (-6.5, 0.5, 26.5), (1.0, 6.0, 3.0), apron_deep, "Pelvis")
    add("cellar_apron_side_right", (6.5, 0.5, 26.5), (1.0, 6.0, 3.0), apron_deep, "Pelvis")
    add("cellar_apron_left_panel", (-3.5, -4.0, 21.5), (5.0, 1.0, 7.0), apron_mid, "Pelvis")
    add("cellar_apron_right_panel", (3.5, -4.0, 21.5), (5.0, 1.0, 7.0), apron_mid, "Pelvis")
    add("cellar_apron_right_fold", (5.0, -5.0, 18.5), (2.0, 1.0, 1.0), apron_high, "Pelvis")
    add("cellar_apron_tie_back", (0.0, 5.5, 27.5), (6.0, 2.0, 3.0), apron_dark, "Pelvis")
    add("cellar_apron_tie_tail_left", (-2.0, 5.0, 24.5), (2.0, 1.0, 3.0), apron_deep, "Pelvis")
    add("cellar_apron_tie_tail_right", (2.0, 5.0, 24.5), (2.0, 1.0, 3.0), apron_deep, "Pelvis")

    # The inherited-property key is the only fixed metal silhouette detail.
    add("property_key_hanger", (-4.0, -5.0, 28.5), (1.0, 1.0, 1.0), brass_high, "Pelvis")
    add("property_key_bow", (-4.0, -5.0, 27.0), (3.0, 1.0, 2.0), brass_mid, "Pelvis")
    add("property_key_stem", (-4.0, -5.0, 24.0), (1.0, 1.0, 4.0), brass_dark, "Pelvis")
    add("property_key_tooth", (-2.5, -5.0, 22.5), (2.0, 1.0, 1.0), brass_high, "Pelvis")

    # Torso is assembled from dedicated shirt and vest masses.
    add("workshirt_lower", (0.0, 0.5, 31.5), (12.0, 8.0, 5.0), linen_shadow, "Torso")
    add("workshirt_rib_center", (0.0, 0.5, 37.5), (6.0, 8.0, 7.0), linen_mid, "Torso")
    add("cellar_vest_front_left", (-5.0, 0.0, 37.5), (4.0, 9.0, 7.0), vest_mid, "Torso")
    add("cellar_vest_front_right", (5.0, 0.0, 37.5), (4.0, 9.0, 7.0), vest_mid, "Torso")
    add("cellar_vest_lapel_left", (-4.5, -5.0, 38.0), (3.0, 1.0, 4.0), vest_high, "Torso")
    add("cellar_vest_lapel_right", (4.5, -5.0, 38.0), (3.0, 1.0, 4.0), vest_high, "Torso")
    add("cellar_vest_back_yoke", (0.0, 5.5, 39.5), (12.0, 2.0, 3.0), vest_deep, "Torso")
    add("shoulder_yoke_left", (-8.0, 0.5, 39.0), (2.0, 8.0, 4.0), vest_dark, "Torso")
    add("shoulder_yoke_right", (8.0, 0.5, 39.0), (2.0, 8.0, 4.0), vest_dark, "Torso")

    # Rolled sleeves and robust hands leave clean equipment sockets.
    add("rolled_sleeve_left", (-10.5, 0.0, 37.0), (3.0, 7.0, 6.0), linen_mid, "UpperArm.L")
    add("sleeve_cuff_left", (-10.5, 0.0, 32.5), (3.0, 7.0, 3.0), linen_high, "LowerArm.L")
    add("forearm_left", (-10.25, 0.5, 28.0), (3.5, 6.0, 6.0), skin_mid, "LowerArm.L")
    add("wrist_left", (-10.25, 0.5, 24.0), (3.5, 6.0, 2.0), skin_shadow, "Hand.L")
    add("hand_left", (-10.0, 0.0, 21.0), (4.0, 6.0, 4.0), skin_mid, "Hand.L")
    add("thumb_left", (-9.0, -3.5, 21.0), (1.0, 1.0, 2.0), skin_high, "Hand.L")

    add("rolled_sleeve_right", (10.5, 0.0, 37.0), (3.0, 7.0, 6.0), linen_mid, "UpperArm.R")
    add("sleeve_cuff_right", (10.5, 0.0, 32.5), (3.0, 7.0, 3.0), linen_high, "LowerArm.R")
    add("forearm_right", (10.25, 0.5, 28.0), (3.5, 6.0, 6.0), skin_mid, "LowerArm.R")
    add("wrist_right", (10.25, 0.5, 24.0), (3.5, 6.0, 2.0), skin_shadow, "Hand.R")
    add("hand_right", (10.0, 0.0, 21.0), (4.0, 6.0, 4.0), skin_mid, "Hand.R")
    add("thumb_right", (9.0, -3.5, 21.0), (1.0, 1.0, 2.0), skin_high, "Hand.R")

    # Human head: a stepped brow/nose/jaw profile and a substantial rear hair
    # mass make the face readable from side and top without inflating the body.
    add("neck_working", (0.0, 1.0, 42.5), (4.0, 4.0, 3.0), skin_shadow, "Neck")
    add("jaw", (0.0, 0.0, 45.0), (7.0, 6.0, 2.0), skin_shadow, "Head")
    add("face_lower", (0.0, -0.5, 47.0), (8.0, 7.0, 2.0), skin_mid, "Head")
    add("face_cranium", (0.0, 0.0, 50.5), (10.0, 8.0, 5.0), skin_mid, "Head")
    add("cheek_left", (-4.5, -1.0, 47.0), (1.0, 4.0, 2.0), skin_high, "Head")
    add("cheek_right", (4.5, -1.0, 47.0), (1.0, 4.0, 2.0), skin_high, "Head")
    add("ear_left", (-6.0, 0.0, 49.5), (2.0, 3.0, 3.0), skin_mid, "Head")
    add("ear_right", (6.0, 0.0, 49.5), (2.0, 3.0, 3.0), skin_mid, "Head")

    add("nose_bridge", (0.0, -4.5, 47.5), (2.0, 1.0, 3.0), skin_high, "Head")
    add("nose_tip", (0.0, -6.0, 46.0), (3.0, 2.0, 2.0), skin_mid, "Head")
    add("mouth_line", (0.0, -3.5, 45.0), (3.0, 1.0, 1.0), hair_deep, "Head")
    add("eye_left", (-2.5, -4.5, 49.5), (2.0, 1.0, 1.0), eye_light, "Head")
    add("eye_right", (2.5, -4.5, 49.5), (2.0, 1.0, 1.0), eye_light, "Head")
    add("pupil_left", (-2.5, -5.5, 49.5), (1.0, 1.0, 1.0), eye_dark, "Head")
    add("pupil_right", (2.5, -5.5, 49.5), (1.0, 1.0, 1.0), eye_dark, "Head")
    add("brow_left", (-2.5, -4.5, 50.5), (3.0, 1.0, 1.0), hair_mid, "Head")
    add("brow_right", (2.5, -4.5, 50.5), (3.0, 1.0, 1.0), hair_mid, "Head")

    add("hair_nape", (0.0, 5.5, 50.5), (8.0, 3.0, 5.0), hair_deep, "Head")
    add("hair_temple_left", (-5.5, 2.0, 52.0), (1.0, 4.0, 2.0), hair_mid, "Head")
    add("hair_temple_right", (5.5, 2.0, 52.0), (1.0, 4.0, 2.0), hair_mid, "Head")
    add("hair_crown_left", (-2.5, 0.5, 53.5), (5.0, 9.0, 1.0), hair_mid, "Head")
    add("hair_crown_right", (2.5, 0.5, 53.5), (5.0, 9.0, 1.0), hair_mid, "Head")
    add("hair_side_part", (1.5, -4.5, 52.5), (1.0, 1.0, 1.0), skin_shadow, "Head")
    add("hair_forelock_right", (3.5, -4.5, 52.0), (3.0, 1.0, 2.0), hair_high, "Head")

    return root, parts, parts_by_bone


def _assert_authored_envelope(parts: list[bpy.types.Object]) -> None:
    minimum = [min(obj.location[axis] - obj.dimensions[axis] * 0.5 for obj in parts) for axis in range(3)]
    maximum = [max(obj.location[axis] + obj.dimensions[axis] * 0.5 for obj in parts) for axis in range(3)]
    blender_size_px = tuple(round((maximum[axis] - minimum[axis]) * 32.0, 4) for axis in range(3))
    size_px = (blender_size_px[0], blender_size_px[2], blender_size_px[1])
    if size_px != TARGET_ENVELOPE_PX:
        raise RuntimeError(f"player envelope is {size_px}px, expected {TARGET_ENVELOPE_PX}px")


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts, parts_by_bone = build_player()
    _assert_authored_envelope(parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_single_face_connected_component(parts, label=MODEL_ID)

    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    export_static_glb(root, STATIC_OUTPUT)

    root.rotation_euler.z = 0.0
    bpy.context.view_layer.update()
    armature = create_voxel_humanoid_armature(height_px=54.0, name="Armature")
    parent_parts_by_bone(parts_by_bone, armature)
    build_all_actions(armature)
    build_weapon_actions(armature)
    # The runtime contract mounts equipment at character/Armature/Skeleton3D.
    # Remove the static-only empty before rig export so Godot does not import
    # an extra voxel_player_54px wrapper between the route root and Armature.
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
    render_real_views(PREVIEW_DIR, "voxel_player", center, scale, camera)

    print(f"Wrote {STATIC_OUTPUT}")
    print(f"Wrote {RIG_OUTPUT}")
    print(f"Envelope: {TARGET_ENVELOPE_PX}px; front: Blender -Y")


if __name__ == "__main__":
    main()
