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

from voxel_character_rig import build_all_actions, build_weapon_actions, export_glb as export_rig_glb, make_action
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
    add("forearm_left", (-10.0, 0.5, 28.0), (4.0, 6.0, 6.0), skin_mid, "LowerArm.L")
    add("wrist_left", (-10.0, 0.5, 24.0), (4.0, 6.0, 2.0), skin_shadow, "Hand.L")
    add("hand_left", (-10.0, 0.0, 21.0), (4.0, 6.0, 4.0), skin_mid, "Hand.L")
    add("thumb_left", (-9.0, -3.5, 21.0), (1.0, 1.0, 2.0), skin_high, "Hand.L")

    add("rolled_sleeve_right", (10.5, 0.0, 37.0), (3.0, 7.0, 6.0), linen_mid, "UpperArm.R")
    add("sleeve_cuff_right", (10.5, 0.0, 32.5), (3.0, 7.0, 3.0), linen_high, "LowerArm.R")
    add("forearm_right", (10.0, 0.5, 28.0), (4.0, 6.0, 6.0), skin_mid, "LowerArm.R")
    add("wrist_right", (10.0, 0.5, 24.0), (4.0, 6.0, 2.0), skin_shadow, "Hand.R")
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


def build_player_crossbow_actions(armature) -> None:
    """Author the player's third-person crossbow flow on the character rig.

    These clips are deliberately player-only third-person actions. Crossbow handling is a held
    forward aim pose, a short shoulder recoil, and a full two-hand reload;
    it must never reuse the one-hand throw animation. The weapon stays on
    Hand.R for the world-model socket. The local first-person ViewModel is a
    separate weapon-only visual and does not consume these character bones.
    """
    # Right mouse aim: both hands close around a forward-facing crossbow.
    # This is a stable pose, not a charge animation; the crossbow is ready
    # immediately and the camera owns the FOV transition.
    aim_pose = {
        "UpperArm.R": {"rot": (-30, 0, 25)},
        "LowerArm.R": {"rot": (-40, 0, 0)},
        # Keep the rear grip aligned with the generic held-weapon socket. The
        # arm is raised for the third-person silhouette, but the hand itself
        # must not roll the crossbow into a diagonal silhouette.
        "Hand.R": {"rot": (0, -20, 20)},
        "UpperArm.L": {"rot": (-48, 8, -20)},
        "LowerArm.L": {"rot": (-58, 0, 0)},
        "Hand.L": {"rot": (0, 12, -10)},
        "Torso": {"rot": (-4, 0, 0)},
    }
    make_action(armature, "crossbow_aim", 1, [(1, aim_pose)])

    # Left click fire: keep the aim silhouette, kick both shoulders and the
    # torso for a few frames, then settle back.  There is no release/throw
    # pose and no large arm arc, preserving a compact third-person silhouette.
    fire_recoil = {
        # The right hand is the weapon socket. Keep it locked to the aim grip;
        # recoil is carried by the shoulder and torso so the crossbow does not
        # orbit out of its stable world-model silhouette.
        "UpperArm.R": {"rot": (-30, 0, 25)},
        "LowerArm.R": {"rot": (-40, 0, 0)},
        "Hand.R": {"rot": (0, -20, 20)},
        "UpperArm.L": {"rot": (-40, 8, -18)},
        "LowerArm.L": {"rot": (-50, 0, 0)},
        "Hand.L": {"rot": (0, 12, -10)},
        "Torso": {"rot": (-6, 0, 0)},
    }
    make_action(armature, "crossbow_fire", 8,
        [(1, aim_pose),
         (2, {**aim_pose, "Torso": {"rot": (-6, 0, 0)}}),
         (3, fire_recoil),
         (4, fire_recoil),
         (6, {**aim_pose, "Torso": {"rot": (-5, 0, 0)}}),
         (8, aim_pose)]
    )

    # Reload: lower the crossbow toward the chest, let the left hand work the
    # string/bolt, then return to the same aim pose.  The gameplay timer is
    # authoritative; Player only changes playback speed to fit reload_time.
    reload_low = {
        # Keep the firing hand and torso planted. The left hand performs the
        # visible reload work around the receiver instead of dragging the
        # weapon socket through the body silhouette.
        "UpperArm.R": {"rot": (-30, 0, 25)},
        "LowerArm.R": {"rot": (-40, 0, 0)},
        "Hand.R": {"rot": (0, -20, 20)},
        "UpperArm.L": {"rot": (-20, 10, -14)},
        "LowerArm.L": {"rot": (-25, 0, 0)},
        "Hand.L": {"rot": (0, 10, -6)},
        "Torso": {"rot": (-4, 0, 0)},
    }
    reload_work = {
        "UpperArm.R": {"rot": (-30, 0, 25)},
        "LowerArm.R": {"rot": (-40, 0, 0)},
        "Hand.R": {"rot": (0, -20, 20)},
        "UpperArm.L": {"rot": (8, 14, -22)},
        "LowerArm.L": {"rot": (-12, 0, 0)},
        "Hand.L": {"rot": (0, 22, -12)},
        "Torso": {"rot": (-4, 0, 0)},
    }
    make_action(armature, "crossbow_reload", 29,
        [(1, aim_pose),
         (4, reload_low),
         (10, reload_work),
         (16, reload_work),
         (22, reload_low),
         (29, aim_pose)]
    )


def build_player_style_actions(armature) -> None:
    """Author the player-only hold/guard/attack clips for every equipment style.

    The generic humanoid action set remains shared with enemies.  These clips
    belong only to the player rig because the player weapon schools have
    distinct grips, defensive silhouettes, and attack mechanics.
    """
    style_specs = {
        "unarmed": {
            "hold": ("unarmed_hold", 1, {
                "UpperArm.R": {"rot": (-18, 0, 24)}, "LowerArm.R": {"rot": (-28, 0, 0)},
                "UpperArm.L": {"rot": (-18, 0, -24)}, "LowerArm.L": {"rot": (-28, 0, 0)},
            }),
            "guard": ("unarmed_guard", 8, {
                "UpperArm.R": {"rot": (-48, -22, 38)}, "LowerArm.R": {"rot": (-58, 18, 0)},
                "Hand.R": {"rot": (0, -18, 18)},
                "UpperArm.L": {"rot": (-48, 22, -38)}, "LowerArm.L": {"rot": (-58, -18, 0)},
                "Hand.L": {"rot": (0, 18, -18)}, "Torso": {"rot": (0, 0, -6)},
            }),
        },
        "shortsword": {
            "hold": ("shortsword_hold", 1, {
                "UpperArm.R": {"rot": (-28, 0, 28)}, "LowerArm.R": {"rot": (-42, 0, 0)},
                "Hand.R": {"rot": (0, -18, 18)},
            }),
            "guard": ("shortsword_guard", 8, {
                "UpperArm.R": {"rot": (-38, -25, 35)}, "LowerArm.R": {"rot": (-64, 12, 0)},
                "Hand.R": {"rot": (0, -28, 28)}, "Torso": {"rot": (0, 0, -4)},
            }),
            "attack": ("shortsword_attack", 9, {
                "UpperArm.R": {"rot": (-76, -90, 36)}, "LowerArm.R": {"rot": (118, 142, -86)},
                "Hand.R": {"rot": (142, 0, -24)}, "Torso": {"rot": (0, 10, 8)},
            }),
        },
        "sword": {
            "hold": ("sword_hold", 1, {
                "UpperArm.R": {"rot": (-32, 0, 22)}, "LowerArm.R": {"rot": (-46, 0, 0)},
                "Hand.R": {"rot": (0, -22, 22)},
            }),
            "guard": ("sword_guard", 8, {
                "UpperArm.R": {"rot": (-42, -18, 30)}, "LowerArm.R": {"rot": (-68, 8, 0)},
                "Hand.R": {"rot": (0, -22, 32)}, "Torso": {"rot": (0, 0, -7)},
            }),
            "attack": ("sword_attack", 11, {
                "UpperArm.R": {"rot": (-92, -20, -42)}, "LowerArm.R": {"rot": (138, 78, 112)},
                "Hand.R": {"rot": (-150, 0, 34)}, "Torso": {"rot": (0, -12, -12)},
            }),
        },
        "dagger": {
            "hold": ("dagger_hold", 1, {
                "UpperArm.R": {"rot": (-18, 8, 42)}, "LowerArm.R": {"rot": (-24, 0, 0)},
                "Hand.R": {"rot": (0, -42, 8)}, "UpperArm.L": {"rot": (-12, 0, -18)},
            }),
            "guard": ("dagger_guard", 7, {
                "UpperArm.R": {"rot": (-26, 18, 52)}, "LowerArm.R": {"rot": (-32, 0, 0)},
                "Hand.R": {"rot": (0, -56, 10)}, "Torso": {"rot": (0, 0, 6)},
            }),
            "attack": ("dagger_attack", 7, {
                "UpperArm.R": {"rot": (18, 12, -22)}, "LowerArm.R": {"rot": (10, 0, 0)},
                "Hand.R": {"rot": (-10, 0, -36)}, "UpperArm.L": {"rot": (-52, -8, -32)},
                "LowerArm.L": {"rot": (-42, 0, 0)}, "Torso": {"rot": (0, 14, 0)},
            }),
        },
        "greatsword": {
            "hold": ("greatsword_hold", 1, {
                "UpperArm.R": {"rot": (-52, 0, 32)}, "LowerArm.R": {"rot": (-34, 0, 0)},
                "UpperArm.L": {"rot": (-52, 0, -32)}, "LowerArm.L": {"rot": (-34, 0, 0)},
            }),
            "guard": ("greatsword_guard", 10, {
                "UpperArm.R": {"rot": (-78, -8, 38)}, "LowerArm.R": {"rot": (-48, 0, 0)},
                "UpperArm.L": {"rot": (-78, 8, -38)}, "LowerArm.L": {"rot": (-48, 0, 0)},
                "Torso": {"rot": (-8, 0, -8)},
            }),
            "attack": ("greatsword_attack", 14, {
                "UpperArm.R": {"rot": (28, 0, -22)}, "LowerArm.R": {"rot": (22, 0, 0)},
                "UpperArm.L": {"rot": (28, 0, 22)}, "LowerArm.L": {"rot": (22, 0, 0)},
                "Torso": {"rot": (16, 0, 10)},
            }),
            "heavy": ("greatsword_heavy_swing", 18, {
                "UpperArm.R": {"rot": (-112, -22, 56)}, "LowerArm.R": {"rot": (-66, 0, 0)},
                "UpperArm.L": {"rot": (-106, 22, -56)}, "LowerArm.L": {"rot": (-64, 0, 0)},
                "Hand.R": {"rot": (148, 0, -28)}, "Hand.L": {"rot": (148, 0, 28)},
                "Torso": {"rot": (-22, 4, -14)},
            }),
        },
        "axe": {
            "hold": ("axe_hold", 1, {
                "UpperArm.R": {"rot": (-58, -12, 42)}, "LowerArm.R": {"rot": (-28, 0, 0)},
                "UpperArm.L": {"rot": (-44, 10, -34)}, "LowerArm.L": {"rot": (-36, 0, 0)},
            }),
            "guard": ("axe_guard", 10, {
                "UpperArm.R": {"rot": (-86, -18, 52)}, "LowerArm.R": {"rot": (-42, 0, 0)},
                "UpperArm.L": {"rot": (-64, 18, -48)}, "LowerArm.L": {"rot": (-50, 0, 0)},
                "Torso": {"rot": (-10, 0, 12)},
            }),
            "attack": ("axe_attack", 13, {
                "UpperArm.R": {"rot": (42, -12, -34)}, "LowerArm.R": {"rot": (34, 0, 0)},
                "UpperArm.L": {"rot": (42, 12, 34)}, "LowerArm.L": {"rot": (34, 0, 0)},
                "Torso": {"rot": (18, -8, -14)},
            }),
            "heavy": ("axe_heavy_swing", 17, {
                "UpperArm.R": {"rot": (-108, -38, 70)}, "LowerArm.R": {"rot": (-52, 0, 0)},
                "UpperArm.L": {"rot": (-94, 28, -58)}, "LowerArm.L": {"rot": (-62, 0, 0)},
                "Hand.R": {"rot": (132, -18, -34)}, "Hand.L": {"rot": (132, 18, 34)},
                "Torso": {"rot": (-24, -16, 20)},
            }),
        },
        "warhammer": {
            "hold": ("warhammer_hold", 1, {
                "UpperArm.R": {"rot": (-62, 8, 28)}, "LowerArm.R": {"rot": (-26, 0, 0)},
                "UpperArm.L": {"rot": (-48, -10, -26)}, "LowerArm.L": {"rot": (-38, 0, 0)},
            }),
            "guard": ("warhammer_guard", 11, {
                "UpperArm.R": {"rot": (-96, 4, 44)}, "LowerArm.R": {"rot": (-34, 0, 0)},
                "UpperArm.L": {"rot": (-72, -4, -42)}, "LowerArm.L": {"rot": (-52, 0, 0)},
                "Torso": {"rot": (-14, 0, -4)},
            }),
            "attack": ("warhammer_attack", 15, {
                "UpperArm.R": {"rot": (54, 8, -28)}, "LowerArm.R": {"rot": (42, 0, 0)},
                "UpperArm.L": {"rot": (54, -8, 28)}, "LowerArm.L": {"rot": (42, 0, 0)},
                "Torso": {"rot": (22, 6, 18)},
            }),
            "heavy": ("warhammer_heavy_swing", 19, {
                "UpperArm.R": {"rot": (-126, 22, 56)}, "LowerArm.R": {"rot": (-60, 0, 0)},
                "UpperArm.L": {"rot": (-118, -18, -52)}, "LowerArm.L": {"rot": (-70, 0, 0)},
                "Hand.R": {"rot": (154, 18, -26)}, "Hand.L": {"rot": (154, -18, 26)},
                "Torso": {"rot": (-26, 10, 24)},
            }),
        },
        "spear": {
            "hold": ("spear_hold", 1, {
                "UpperArm.R": {"rot": (-34, -16, 20)}, "LowerArm.R": {"rot": (-64, 0, 0)},
                "UpperArm.L": {"rot": (-22, 12, -18)}, "LowerArm.L": {"rot": (-42, 0, 0)},
            }),
            "guard": ("spear_guard", 9, {
                "UpperArm.R": {"rot": (-46, -26, 18)}, "LowerArm.R": {"rot": (-78, 0, 0)},
                "UpperArm.L": {"rot": (-34, 20, -16)}, "LowerArm.L": {"rot": (-54, 0, 0)},
                "Torso": {"rot": (0, 12, 0)},
            }),
            "attack": ("spear_attack", 10, {
                "UpperArm.R": {"rot": (-10, -4, 8)}, "LowerArm.R": {"rot": (-8, 0, 0)},
                "UpperArm.L": {"rot": (12, 6, -8)}, "LowerArm.L": {"rot": (-12, 0, 0)},
                "Torso": {"rot": (-8, 18, 0)},
            }),
            "heavy": ("spear_heavy_swing", 16, {
                "UpperArm.R": {"rot": (-64, -34, 14)}, "LowerArm.R": {"rot": (-96, 0, 0)},
                "UpperArm.L": {"rot": (-52, 24, -14)}, "LowerArm.L": {"rot": (-76, 0, 0)},
                "Hand.R": {"rot": (12, -18, 10)}, "Hand.L": {"rot": (8, 18, -10)},
                "Torso": {"rot": (-12, 24, 0)},
            }),
        },
        "bow": {
            "hold": ("bow_hold", 1, {
                "UpperArm.R": {"rot": (-38, 14, 24)}, "LowerArm.R": {"rot": (-50, 0, 0)},
                "UpperArm.L": {"rot": (-44, -8, -32)}, "LowerArm.L": {"rot": (-54, 0, 0)},
                "Torso": {"rot": (-4, 0, 4)},
            }),
            "guard": ("bow_aim", 1, {
                "UpperArm.R": {"rot": (-42, 18, 22)}, "LowerArm.R": {"rot": (-58, 0, 0)},
                "UpperArm.L": {"rot": (-54, -10, -34)}, "LowerArm.L": {"rot": (-68, 0, 0)},
                "Torso": {"rot": (-8, 0, 6)},
            }),
            "attack": ("bow_release", 8, {
                "UpperArm.R": {"rot": (-18, 28, 12)}, "LowerArm.R": {"rot": (-36, 0, 0)},
                "UpperArm.L": {"rot": (-30, -24, -18)}, "LowerArm.L": {"rot": (-42, 0, 0)},
                "Torso": {"rot": (4, 0, -8)},
            }),
        },
        "crossbow": {
            "hold": ("crossbow_hold", 1, {
                "UpperArm.R": {"rot": (-26, 0, 20)}, "LowerArm.R": {"rot": (-38, 0, 0)},
                "UpperArm.L": {"rot": (-34, 8, -16)}, "LowerArm.L": {"rot": (-44, 0, 0)},
                "Torso": {"rot": (-2, 0, 0)},
            }),
        },
        "staff": {
            "hold": ("staff_hold", 1, {
                "UpperArm.R": {"rot": (-44, 0, 34)}, "LowerArm.R": {"rot": (-54, 0, 0)},
                "UpperArm.L": {"rot": (-28, 0, -24)}, "LowerArm.L": {"rot": (-46, 0, 0)},
            }),
            "guard": ("staff_guard", 9, {
                "UpperArm.R": {"rot": (-62, 0, 42)}, "LowerArm.R": {"rot": (-72, 0, 0)},
                "UpperArm.L": {"rot": (-18, -4, -20)}, "LowerArm.L": {"rot": (-30, 0, 0)},
                "Torso": {"rot": (-6, -10, 6)},
            }),
            "attack": ("staff_attack", 12, {
                "UpperArm.R": {"rot": (-8, -34, 22)}, "LowerArm.R": {"rot": (-18, 0, 0)},
                "UpperArm.L": {"rot": (-10, 30, -18)}, "LowerArm.L": {"rot": (-20, 0, 0)},
                "Hand.R": {"rot": (0, -20, 50)}, "Torso": {"rot": (0, 20, 10)},
            }),
        },
        "grimoire": {
            "hold": ("grimoire_hold", 1, {
                "UpperArm.R": {"rot": (-18, -10, 18)}, "LowerArm.R": {"rot": (-30, 0, 0)},
                "UpperArm.L": {"rot": (-38, 16, -32)}, "LowerArm.L": {"rot": (-42, 0, 0)},
                "Hand.L": {"rot": (0, 20, -12)},
            }),
            "guard": ("grimoire_guard", 9, {
                "UpperArm.R": {"rot": (-20, -18, 22)}, "LowerArm.R": {"rot": (-34, 0, 0)},
                "UpperArm.L": {"rot": (-52, 22, -46)}, "LowerArm.L": {"rot": (-58, 0, 0)},
                "Hand.L": {"rot": (0, 30, -20)}, "Torso": {"rot": (0, -14, 8)},
            }),
            "attack": ("grimoire_attack", 12, {
                "UpperArm.R": {"rot": (-2, -28, 30)}, "LowerArm.R": {"rot": (-12, 0, 0)},
                "UpperArm.L": {"rot": (16, 34, -36)}, "LowerArm.L": {"rot": (8, 0, 0)},
                "Hand.L": {"rot": (0, 38, -30)}, "Torso": {"rot": (0, -20, -8)},
            }),
        },
        "shield": {
            "hold": ("shield_hold", 1, {
                "UpperArm.R": {"rot": (-28, 0, 24)}, "LowerArm.R": {"rot": (-42, 0, 0)},
                "UpperArm.L": {"rot": (-36, 0, -48)}, "LowerArm.L": {"rot": (-64, 0, 0)},
            }),
            "guard": ("shield_block", 8, {
                "UpperArm.L": {"rot": (-62, 0, -72)}, "LowerArm.L": {"rot": (-88, 0, 0)},
                "UpperArm.R": {"rot": (-30, 0, 22)}, "LowerArm.R": {"rot": (-44, 0, 0)},
                "Torso": {"rot": (0, 0, -12)},
            }),
        },
    }
    for spec in style_specs.values():
        hold_name, hold_length, hold_pose = spec["hold"]
        make_action(armature, hold_name, hold_length, [(1, hold_pose)])
        if "guard" in spec:
            guard_name, guard_length, guard_pose = spec["guard"]
            make_action(armature, guard_name, guard_length,
                [(1, guard_pose), (max(2, guard_length // 2), guard_pose), (guard_length, {})]
            )
        if "attack" in spec:
            attack_name, attack_length, attack_pose = spec["attack"]
            make_action(armature, attack_name, attack_length,
                [(1, hold_pose), (max(2, attack_length // 3), attack_pose),
                 (max(3, (attack_length * 2) // 3), attack_pose), (attack_length, {})]
            )
        if "heavy" in spec:
            heavy_name, heavy_length, heavy_pose = spec["heavy"]
            make_action(armature, heavy_name, heavy_length,
                [(1, hold_pose), (max(2, heavy_length // 4), heavy_pose),
                 (max(3, heavy_length // 2), heavy_pose),
                 (max(4, (heavy_length * 3) // 4), heavy_pose), (heavy_length, {})]
            )


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
    build_player_style_actions(armature)
    build_player_crossbow_actions(armature)
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
