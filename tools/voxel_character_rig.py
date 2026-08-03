"""Humanoid action authoring and animated GLB export mechanics.

The caller owns armature construction, mesh binding, model identity, and exact
paths. This module only writes actions onto an existing humanoid armature and
exports the already assembled Blender scene.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

import bpy
from mathutils import Vector


RUN_FRAME_COUNT = 24
MAX_AUTHORED_ROTATION_DEGREES = 105.0
RUN_CONTACT_PELVIS_DROP_M = 0.006
RUN_PASSING_PELVIS_DROP_M = 0.015


@dataclass(frozen=True)
class HumanoidMotionProfile:
    """Per-model motion character; model generators own the chosen values."""

    stride_scale: float = 1.0
    arm_swing_scale: float = 1.0
    weight_scale: float = 1.0
    agility_scale: float = 1.0
    torso_scale: float = 1.0
    swing_lift_scale: float = 1.0
    swing_foot_pitch_scale: float = 1.0
    contact_foot_pitch_scale: float = 1.0
    contact_lead_knee_scale: float = 1.0
    contact_height_offset_m: float = 0.0
    passing_height_offset_m: float = 0.0
    death_height_offset_m: float = 0.0


def _pose_offset_from_blender_world(
    armature: bpy.types.Object,
    bone_name: str,
    world_offset: tuple[float, float, float],
) -> tuple[float, float, float]:
    """Convert Blender-world movement to a PoseBone's local location axes.

    Blender authors these rigs Z-up and glTF export maps that axis to Godot +Y.
    Directly assigning a world-looking tuple to PoseBone.location is incorrect
    because each bone has its own rest basis.
    """
    rest_basis = armature.data.bones[bone_name].matrix_local.to_3x3()
    return tuple(rest_basis.inverted() @ Vector(world_offset))


def _validate_authored_pose_bounds(frames) -> None:
    """Reject multi-axis contortions before they reach an exported GLB."""
    for frame, keys in frames:
        for bone_name, values in keys.items():
            rotation = values.get("rot", (0.0, 0.0, 0.0))
            for component in rotation:
                if abs(float(component)) > MAX_AUTHORED_ROTATION_DEGREES:
                    raise ValueError(
                        f"frame {frame} bone {bone_name} exceeds "
                        f"{MAX_AUTHORED_ROTATION_DEGREES} degrees: {rotation}"
                    )

# ============================================================================
# 动画定义 — 与 character.glb 完全一致的动作集
# 每个动作是 (bone_name, frame, rot_degrees, loc_offset) 的序列
# ============================================================================

def _rad(deg: float) -> float:
    return math.radians(deg)


def _clear_pose_transforms(armature: bpy.types.Object) -> None:
    """Zero pose-bone transforms WITHOUT clearing animation_data.action.

    Critical: clearing action mid-keying causes Blender to auto-create a new
    action named ``ArmatureAction`` / ``Armature动作`` (locale-dependent). Those
    generic names then replace idle/run/slash in the exported GLB.
    """
    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.location = (0.0, 0.0, 0.0)
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def _reset_pose(armature: bpy.types.Object) -> None:
    """Clear active action + pose transforms for rest-pose export/render.

    Only call this AFTER all actions are authored (export path). Never call
    during make_action keyframing — use _clear_pose_transforms instead.
    """
    if armature.animation_data is not None:
        armature.animation_data.action = None
        if hasattr(armature.animation_data, "action_slot"):
            try:
                armature.animation_data.action_slot = None
            except Exception:
                pass
    _clear_pose_transforms(armature)
    bpy.context.view_layer.update()


def _action_channel_count(action: bpy.types.Action) -> int:
    """Count keyed channels across Blender 3.x fcurves and 5.x layered actions."""
    count = 0
    if hasattr(action, "fcurves") and action.fcurves:
        count += len(action.fcurves)
    # Blender 4.4+/5 layered actions store keys under layers/strips/channelbags.
    layers = getattr(action, "layers", None)
    if layers:
        for layer in layers:
            for strip in getattr(layer, "strips", []) or []:
                bags = getattr(strip, "channelbags", None)
                if bags is None and hasattr(strip, "channelbag"):
                    bags = [strip.channelbag] if strip.channelbag else []
                for bag in bags or []:
                    fcurves = getattr(bag, "fcurves", None)
                    if fcurves:
                        count += len(fcurves)
    return count


def _ensure_action_slot(armature: bpy.types.Object, action: bpy.types.Action):
    """Bind a Blender 5 action slot so pose bone keys land on this action."""
    if not hasattr(action, "slots"):
        return None
    ad = armature.animation_data
    if ad is None:
        return None
    try:
        slot = None
        if len(action.slots) == 0:
            # Pose keys are recorded against the Object ID (the armature).
            slot = action.slots.new(id_type="OBJECT", name=armature.name)
        else:
            slot = action.slots[0]
        if hasattr(ad, "action_slot") and slot is not None:
            ad.action_slot = slot
        return slot
    except Exception:
        return None


def _key_bone(armature, bone_name, frame, rot=(0, 0, 0), loc=None):
    bone = armature.pose.bones.get(bone_name)
    if bone is None:
        return
    bone.rotation_mode = "XYZ"
    bone.rotation_euler = (_rad(rot[0]), _rad(rot[1]), _rad(rot[2]))
    bone.keyframe_insert("rotation_euler", frame=frame)
    if loc is not None:
        bone.location = loc
        bone.keyframe_insert("location", frame=frame)


def _key_pose(armature, frame, keys):
    # Do NOT clear animation_data.action here — keys must stay on the named action.
    _clear_pose_transforms(armature)
    if not keys:
        # Clearing pose transforms does not create F-curve keys. Treat an empty
        # authored pose as an explicit rest frame so clips can recover cleanly.
        for bone in armature.pose.bones:
            _key_bone(armature, bone.name, frame, (0, 0, 0), (0.0, 0.0, 0.0))
        return
    for bone_name, vals in keys.items():
        _key_bone(armature, bone_name, frame, vals.get("rot", (0, 0, 0)), vals.get("loc"))


def make_action(armature, name, length, frames):
    """Author one named action and stash it on an NLA track for glTF export.

    Export name contract: NLA track name == strip name == action name == game
    animation name (idle / run / slash_one_hand / ...). Never leave Blender's
    default ``ArmatureAction`` / ``Armature动作`` names in the GLB.
    """
    _validate_authored_pose_bounds(frames)

    # Replace any prior action with the same game name.
    existing = bpy.data.actions.get(name)
    if existing is not None:
        bpy.data.actions.remove(existing)

    action = bpy.data.actions.new(name=name)
    action.name = name
    armature.animation_data_create()
    ad = armature.animation_data

    # Drop prior NLA track with the same export name (re-runs / partial builds).
    for track in list(ad.nla_tracks):
        if track.name == name:
            ad.nla_tracks.remove(track)

    ad.action = action
    slot = _ensure_action_slot(armature, action)

    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = length
    for frame, keys in frames:
        bpy.context.scene.frame_set(frame)
        # Re-assert action each frame: some Blender 5 ops may reassign defaults.
        if ad.action != action:
            ad.action = action
            slot = _ensure_action_slot(armature, action) or slot
        _key_pose(armature, frame, keys)

    # If keying auto-created a differently named action, migrate name back.
    if ad.action is not None and ad.action != action:
        orphan = ad.action
        orphan.name = name
        action = orphan
        slot = _ensure_action_slot(armature, action) or slot

    if hasattr(action, "frame_range"):
        action.frame_range = (1, length)
    action.name = name

    channel_count = _action_channel_count(action)
    if channel_count == 0:
        # Empty keys dict frames alone produce no channels; force a Root rest key
        # so the action is non-empty and export keeps the name.
        bpy.context.scene.frame_set(1)
        ad.action = action
        slot = _ensure_action_slot(armature, action) or slot
        _key_bone(armature, "Root", 1, (0, 0, 0))
        channel_count = _action_channel_count(action)

    # Push to NLA with the same name the game expects (idle/run/slash/...).
    track = ad.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, int(1), action)
    strip.name = name
    strip.frame_end = length
    if slot is not None and hasattr(strip, "action_slot"):
        try:
            strip.action_slot = slot
        except Exception:
            pass
    ad.action = None
    if hasattr(ad, "action_slot"):
        try:
            ad.action_slot = None
        except Exception:
            pass
    # Final name guard: strip/action must keep the game-facing name.
    action.name = name
    print(f"  created action: {name} (1-{length}) channels={channel_count}")


# ============================================================================
# 武器攻击动画 + 持武器姿态
# ============================================================================
# 与 character.glb 的武器专用动画名对齐，使体素人形 _rig.glb 可直接替换
# character.glb 而不触发 CombatSlashAnimator 的 "slash" 兜底。
#
# 动画名映射（与 globals/combat/combat_slash_animator.gd 对齐）：
#   slash_one_hand : 单手武器（剑/斧/钉锤）—— 右手对角挥砍
#   slash_heavy    : 双手重武器（大剑/战锤）—— 双手过头劈砍
#   slash_dagger   : 匕首 —— 快速双手交替连斩
#   thrust_spear   : 长矛 —— 向前突刺
#   bash_shield    : 盾 —— 左手盾击前推
#   claw_swipe     : 徒手 —— 双手爪击（无武器兜底）
#   hold_weapon    : 持武器待机姿态（右臂前抬握持，左臂备盾）
#   default        : 零姿态（所有骨骼归零，校验基准）
#
# 所有攻击动画从 rest 起始、经蓄力(windup)→挥击(strike)→收招(recover) 回到 rest，
# 与现有 slash 动画的帧结构一致，CombatSlashAnimator.apply_weapon_arc 的进度
# 归一化（PLAYER_HIT_START=0.28 / PLAYER_HIT_END=0.78）能正确命中 strike 段。

def _run_contact_pose(armature, profile, right_forward):
    direction = 1.0 if right_forward else -1.0
    stride = 24.0 * profile.stride_scale
    arm = 18.0 * profile.arm_swing_scale
    model_scale = float(armature.get("height_px", 42.0)) / 42.0
    return {
        "Pelvis": {"loc": _pose_offset_from_blender_world(armature, "Pelvis", (0.0, 0.0, (-RUN_CONTACT_PELVIS_DROP_M + profile.contact_height_offset_m) * model_scale))},
        "Torso": {"rot": (-4.0 * profile.torso_scale, 0.0, 1.5 * direction)},
        "Head": {"rot": (1.5, 0.0, -1.0 * direction)},
        "UpperLeg.R": {"rot": (stride * direction, 0.0, 0.0)},
        "LowerLeg.R": {"rot": ((10.0 * profile.contact_lead_knee_scale if right_forward else 24.0) * profile.stride_scale, 0.0, 0.0)},
        "Foot.R": {"rot": ((-8.0 if right_forward else -14.0) * profile.stride_scale * profile.contact_foot_pitch_scale, 0.0, 0.0)},
        "UpperLeg.L": {"rot": (-stride * direction, 0.0, 0.0)},
        "LowerLeg.L": {"rot": ((24.0 if right_forward else 10.0 * profile.contact_lead_knee_scale) * profile.stride_scale, 0.0, 0.0)},
        "Foot.L": {"rot": ((-14.0 if right_forward else -8.0) * profile.stride_scale * profile.contact_foot_pitch_scale, 0.0, 0.0)},
        "UpperArm.R": {"rot": (-arm * direction, 0.0, 2.0)},
        "LowerArm.R": {"rot": (-8.0, 0.0, 0.0)},
        "UpperArm.L": {"rot": (arm * direction, 0.0, -2.0)},
        "LowerArm.L": {"rot": (-8.0, 0.0, 0.0)},
    }


def _run_passing_pose(armature, profile, right_swinging):
    direction = 1.0 if right_swinging else -1.0
    model_scale = float(armature.get("height_px", 42.0)) / 42.0
    # The straight support leg must stay planted while the opposite foot passes.
    # A positive bob shortened both leg chains in screen space and made every
    # humanoid visibly float; heavier profiles reduce the corrective drop.
    support_drop = RUN_PASSING_PELVIS_DROP_M * model_scale / max(profile.weight_scale, 0.65)
    swing_knee = 82.0 * profile.stride_scale * profile.swing_lift_scale
    return {
        "Pelvis": {"loc": _pose_offset_from_blender_world(armature, "Pelvis", (0.0, 0.0, -support_drop + profile.passing_height_offset_m * model_scale))},
        "Torso": {"rot": (-3.0 * profile.torso_scale, 0.0, -direction)},
        "Head": {"rot": (1.0, 0.0, 0.5 * direction)},
        "UpperLeg.R": {"rot": (4.0 * direction, 0.0, 0.0)},
        "LowerLeg.R": {"rot": (swing_knee if right_swinging else 8.0 * profile.stride_scale, 0.0, 0.0)},
        "Foot.R": {"rot": ((-34.0 * profile.swing_foot_pitch_scale if right_swinging else 4.0) * profile.stride_scale, 0.0, 0.0)},
        "UpperLeg.L": {"rot": (-4.0 * direction, 0.0, 0.0)},
        "LowerLeg.L": {"rot": (8.0 * profile.stride_scale if right_swinging else swing_knee, 0.0, 0.0)},
        "Foot.L": {"rot": ((4.0 if right_swinging else -34.0 * profile.swing_foot_pitch_scale) * profile.stride_scale, 0.0, 0.0)},
        "UpperArm.R": {"rot": (-8.0 * profile.arm_swing_scale * direction, 0.0, 1.0)},
        "LowerArm.R": {"rot": (-10.0, 0.0, 0.0)},
        "UpperArm.L": {"rot": (8.0 * profile.arm_swing_scale * direction, 0.0, -1.0)},
        "LowerArm.L": {"rot": (-10.0, 0.0, 0.0)},
    }


def build_all_actions(armature, profile: HumanoidMotionProfile):
    """Author locomotion and reactions with still idle and planted leg chains."""
    static_rest = {"Root": {"rot": (0.0, 0.0, 0.0), "loc": (0.0, 0.0, 0.0)}}
    make_action(armature, "idle", 1, [(1, static_rest)])
    make_action(armature, "run", RUN_FRAME_COUNT, [
        (1, _run_contact_pose(armature, profile, True)),
        (7, _run_passing_pose(armature, profile, True)),
        (13, _run_contact_pose(armature, profile, False)),
        (19, _run_passing_pose(armature, profile, False)),
        (24, _run_contact_pose(armature, profile, True)),
    ])

    model_scale = float(armature.get("height_px", 42.0)) / 42.0
    world_loc = lambda bone, offset: _pose_offset_from_blender_world(armature, bone, offset)
    attack = profile.agility_scale
    torso = profile.torso_scale

    make_action(armature, "slash", 14, [
        (1, {}),
        (5, {"Torso": {"rot": (-3.0 * torso, 0.0, 7.0)}, "UpperArm.R": {"rot": (-52.0 * attack, 0.0, 24.0)}, "LowerArm.R": {"rot": (-48.0, 0.0, -8.0)}, "Hand.R": {"rot": (0.0, 0.0, -10.0)}}),
        (9, {"Torso": {"rot": (3.0 * torso, 0.0, -8.0)}, "UpperArm.R": {"rot": (-18.0, 0.0, -30.0 * attack)}, "LowerArm.R": {"rot": (-24.0, 0.0, 10.0)}, "Hand.R": {"rot": (0.0, 0.0, 12.0)}}),
        (14, {}),
    ])
    make_action(armature, "block", 12, [
        (1, {}),
        (5, {"UpperArm.L": {"rot": (-48.0, 0.0, -32.0)}, "LowerArm.L": {"rot": (-58.0, 0.0, 8.0)}, "Hand.L": {"rot": (0.0, 0.0, -8.0)}, "Torso": {"rot": (-3.0, 0.0, -5.0 * torso)}, "LowerLeg.R": {"rot": (10.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (10.0, 0.0, 0.0)}}),
        (9, {"UpperArm.L": {"rot": (-44.0, 0.0, -28.0)}, "LowerArm.L": {"rot": (-52.0, 0.0, 6.0)}, "Torso": {"rot": (-2.0, 0.0, -4.0 * torso)}}),
        (12, {}),
    ])
    make_action(armature, "hurt", 12, [
        (1, {}),
        (4, {"Pelvis": {"loc": world_loc("Pelvis", (0.0, 0.025 * model_scale, -0.035 * model_scale))}, "Torso": {"rot": (16.0 / profile.weight_scale, 0.0, 5.0)}, "Head": {"rot": (-18.0, 0.0, -3.0)}, "UpperArm.R": {"rot": (18.0, 0.0, 12.0)}, "UpperArm.L": {"rot": (18.0, 0.0, -12.0)}, "LowerLeg.R": {"rot": (10.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (10.0, 0.0, 0.0)}}),
        (8, {"Pelvis": {"loc": world_loc("Pelvis", (0.0, 0.0, -0.012 * model_scale))}, "Torso": {"rot": (6.0, 0.0, 2.0)}, "Head": {"rot": (-6.0, 0.0, 0.0)}}),
        (12, {}),
    ])
    make_action(armature, "stunned", 24, [
        (1, {"Torso": {"rot": (-4.0, 0.0, 4.0)}, "Head": {"rot": (-8.0, 0.0, -4.0)}, "LowerLeg.R": {"rot": (8.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (12.0, 0.0, 0.0)}}),
        (7, {"Torso": {"rot": (-5.0, 0.0, -3.0)}, "Head": {"rot": (-10.0, 0.0, 4.0)}, "LowerLeg.R": {"rot": (12.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (8.0, 0.0, 0.0)}}),
        (13, {"Torso": {"rot": (-4.0, 0.0, -4.0)}, "Head": {"rot": (-8.0, 0.0, 4.0)}, "LowerLeg.R": {"rot": (8.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (12.0, 0.0, 0.0)}}),
        (19, {"Torso": {"rot": (-5.0, 0.0, 3.0)}, "Head": {"rot": (-10.0, 0.0, -4.0)}, "LowerLeg.R": {"rot": (12.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (8.0, 0.0, 0.0)}}),
        (24, {"Torso": {"rot": (-4.0, 0.0, 4.0)}, "Head": {"rot": (-8.0, 0.0, -4.0)}, "LowerLeg.R": {"rot": (8.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (12.0, 0.0, 0.0)}}),
    ])
    make_action(armature, "death", 24, [
        (1, {}),
        (8, {"Root": {"rot": (-20.0, 0.0, 2.0), "loc": world_loc("Root", (0.0, -0.02 * model_scale, (0.025 + profile.death_height_offset_m * 0.15) * model_scale))}, "Torso": {"rot": (-4.0, 0.0, 3.0)}, "Head": {"rot": (8.0, 0.0, -2.0)}, "UpperArm.R": {"rot": (8.0, 0.0, 18.0)}, "UpperArm.L": {"rot": (8.0, 0.0, -18.0)}, "LowerLeg.R": {"rot": (12.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (12.0, 0.0, 0.0)}}),
        (16, {"Root": {"rot": (-58.0, 0.0, 4.0), "loc": world_loc("Root", (0.0, -0.05 * model_scale, (0.13 + profile.death_height_offset_m * 0.55) * model_scale))}, "Torso": {"rot": (-6.0, 0.0, 4.0)}, "Head": {"rot": (14.0, 0.0, -3.0)}, "UpperArm.R": {"rot": (12.0, 0.0, 26.0)}, "UpperArm.L": {"rot": (12.0, 0.0, -26.0)}, "UpperLeg.R": {"rot": (8.0, 0.0, 0.0)}, "UpperLeg.L": {"rot": (8.0, 0.0, 0.0)}, "LowerLeg.R": {"rot": (18.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (18.0, 0.0, 0.0)}}),
        (24, {"Root": {"rot": (-86.0, 0.0, 5.0), "loc": world_loc("Root", (0.0, -0.07 * model_scale, (0.24 + profile.death_height_offset_m) * model_scale))}, "Torso": {"rot": (-5.0, 0.0, 5.0)}, "Head": {"rot": (16.0, 0.0, -4.0)}, "UpperArm.R": {"rot": (14.0, 0.0, 30.0)}, "UpperArm.L": {"rot": (14.0, 0.0, -30.0)}, "UpperLeg.R": {"rot": (6.0, 0.0, 0.0)}, "UpperLeg.L": {"rot": (6.0, 0.0, 0.0)}, "LowerLeg.R": {"rot": (16.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (16.0, 0.0, 0.0)}}),
    ])
    make_action(armature, "kick", 12, [
        (1, {}),
        (4, {"Torso": {"rot": (5.0, 0.0, -3.0)}, "UpperLeg.R": {"rot": (-42.0 * attack, 0.0, 0.0)}, "LowerLeg.R": {"rot": (58.0, 0.0, 0.0)}, "Foot.R": {"rot": (-18.0, 0.0, 0.0)}, "UpperLeg.L": {"rot": (8.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (12.0, 0.0, 0.0)}}),
        (7, {"Torso": {"rot": (-7.0, 0.0, 3.0)}, "UpperLeg.R": {"rot": (-76.0 * attack, 0.0, 0.0)}, "LowerLeg.R": {"rot": (12.0, 0.0, 0.0)}, "Foot.R": {"rot": (8.0, 0.0, 0.0)}, "UpperLeg.L": {"rot": (10.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (16.0, 0.0, 0.0)}}),
        (12, {}),
    ])
    make_action(armature, "lift", 14, [
        (1, {}),
        (6, {"Torso": {"rot": (-8.0, 0.0, 0.0)}, "UpperArm.R": {"rot": (-76.0, 0.0, 10.0)}, "UpperArm.L": {"rot": (-76.0, 0.0, -10.0)}, "LowerArm.R": {"rot": (-54.0, 0.0, 0.0)}, "LowerArm.L": {"rot": (-54.0, 0.0, 0.0)}, "LowerLeg.R": {"rot": (16.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (16.0, 0.0, 0.0)}}),
        (10, {"Torso": {"rot": (-3.0, 0.0, 0.0)}, "UpperArm.R": {"rot": (-62.0, 0.0, 8.0)}, "UpperArm.L": {"rot": (-62.0, 0.0, -8.0)}, "LowerArm.R": {"rot": (-44.0, 0.0, 0.0)}, "LowerArm.L": {"rot": (-44.0, 0.0, 0.0)}}),
        (14, {}),
    ])
    make_action(armature, "pickup", 14, [
        (1, {}),
        (6, {"Pelvis": {"loc": world_loc("Pelvis", (0.0, 0.0, -0.10 * model_scale))}, "Torso": {"rot": (-24.0, 0.0, 0.0)}, "UpperArm.R": {"rot": (-48.0, 0.0, 8.0)}, "UpperArm.L": {"rot": (-48.0, 0.0, -8.0)}, "LowerArm.R": {"rot": (-46.0, 0.0, 0.0)}, "LowerArm.L": {"rot": (-46.0, 0.0, 0.0)}, "UpperLeg.R": {"rot": (18.0, 0.0, 0.0)}, "UpperLeg.L": {"rot": (18.0, 0.0, 0.0)}, "LowerLeg.R": {"rot": (38.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (38.0, 0.0, 0.0)}}),
        (10, {"Pelvis": {"loc": world_loc("Pelvis", (0.0, 0.0, -0.04 * model_scale))}, "Torso": {"rot": (-10.0, 0.0, 0.0)}, "LowerLeg.R": {"rot": (18.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (18.0, 0.0, 0.0)}}),
        (14, {}),
    ])
    make_action(armature, "throw_weapon", 14, [
        (1, {}),
        (5, {"Torso": {"rot": (-6.0, 0.0, 7.0)}, "UpperArm.R": {"rot": (-72.0, 0.0, 22.0)}, "LowerArm.R": {"rot": (-46.0, 0.0, -8.0)}, "Hand.R": {"rot": (0.0, 0.0, -8.0)}}),
        (9, {"Torso": {"rot": (8.0, 0.0, -8.0)}, "UpperArm.R": {"rot": (18.0, 0.0, -18.0)}, "LowerArm.R": {"rot": (8.0, 0.0, 6.0)}, "Hand.R": {"rot": (0.0, 0.0, 8.0)}}),
        (14, {}),
    ])
    make_action(armature, "throw_furniture", 16, [
        (1, {}),
        (6, {"Torso": {"rot": (-10.0, 0.0, 0.0)}, "UpperArm.R": {"rot": (-72.0, 0.0, 12.0)}, "UpperArm.L": {"rot": (-72.0, 0.0, -12.0)}, "LowerArm.R": {"rot": (-46.0, 0.0, 0.0)}, "LowerArm.L": {"rot": (-46.0, 0.0, 0.0)}, "LowerLeg.R": {"rot": (14.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (14.0, 0.0, 0.0)}}),
        (11, {"Torso": {"rot": (10.0, 0.0, 0.0)}, "UpperArm.R": {"rot": (20.0, 0.0, 8.0)}, "UpperArm.L": {"rot": (20.0, 0.0, -8.0)}, "LowerArm.R": {"rot": (8.0, 0.0, 0.0)}, "LowerArm.L": {"rot": (8.0, 0.0, 0.0)}}),
        (16, {}),
    ])


def build_weapon_actions(armature, profile: HumanoidMotionProfile):
    """Author readable weapon arcs without multi-axis shoulder/elbow inversion."""
    attack = profile.agility_scale
    torso = profile.torso_scale
    make_action(armature, "default", 1, [(1, {"Root": {"rot": (0.0, 0.0, 0.0)}})])
    make_action(armature, "hold_weapon", 1, [(1, {
        "UpperArm.R": {"rot": (-34.0, 0.0, 18.0)}, "LowerArm.R": {"rot": (-38.0, 0.0, -6.0)}, "Hand.R": {"rot": (0.0, 0.0, -8.0)},
        "UpperArm.L": {"rot": (-24.0, 0.0, -20.0)}, "LowerArm.L": {"rot": (-42.0, 0.0, 6.0)}, "Hand.L": {"rot": (0.0, 0.0, 8.0)},
    })])
    make_action(armature, "slash_one_hand", 16, [
        (1, {}),
        (5, {"Torso": {"rot": (-3.0 * torso, 0.0, 7.0)}, "UpperArm.R": {"rot": (-58.0 * attack, 0.0, 28.0)}, "LowerArm.R": {"rot": (-52.0, 0.0, -10.0)}, "Hand.R": {"rot": (0.0, 0.0, -12.0)}}),
        (10, {"Torso": {"rot": (4.0 * torso, 0.0, -9.0)}, "UpperArm.R": {"rot": (-16.0, 0.0, -34.0 * attack)}, "LowerArm.R": {"rot": (-20.0, 0.0, 12.0)}, "Hand.R": {"rot": (0.0, 0.0, 14.0)}}),
        (16, {}),
    ])
    make_action(armature, "slash_heavy", 20, [
        (1, {}),
        (7, {"Torso": {"rot": (-9.0 * torso, 0.0, 0.0)}, "UpperArm.R": {"rot": (-88.0, 0.0, 18.0)}, "UpperArm.L": {"rot": (-88.0, 0.0, -18.0)}, "LowerArm.R": {"rot": (-48.0, 0.0, -6.0)}, "LowerArm.L": {"rot": (-48.0, 0.0, 6.0)}, "LowerLeg.R": {"rot": (12.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (12.0, 0.0, 0.0)}}),
        (13, {"Torso": {"rot": (12.0 * torso, 0.0, 0.0)}, "UpperArm.R": {"rot": (24.0, 0.0, -12.0)}, "UpperArm.L": {"rot": (24.0, 0.0, 12.0)}, "LowerArm.R": {"rot": (12.0, 0.0, 4.0)}, "LowerArm.L": {"rot": (12.0, 0.0, -4.0)}, "LowerLeg.R": {"rot": (18.0, 0.0, 0.0)}, "LowerLeg.L": {"rot": (18.0, 0.0, 0.0)}}),
        (20, {}),
    ])
    make_action(armature, "slash_dagger", 16, [
        (1, {}),
        (4, {"UpperArm.R": {"rot": (-42.0 * attack, 0.0, 24.0)}, "LowerArm.R": {"rot": (-34.0, 0.0, -8.0)}, "UpperArm.L": {"rot": (-24.0, 0.0, -16.0)}}),
        (8, {"UpperArm.R": {"rot": (12.0, 0.0, -20.0)}, "LowerArm.R": {"rot": (8.0, 0.0, 6.0)}, "UpperArm.L": {"rot": (-46.0 * attack, 0.0, -26.0)}, "LowerArm.L": {"rot": (-36.0, 0.0, 8.0)}, "Torso": {"rot": (0.0, 0.0, -6.0)}}),
        (12, {"UpperArm.R": {"rot": (-38.0 * attack, 0.0, 22.0)}, "LowerArm.R": {"rot": (-30.0, 0.0, -6.0)}, "UpperArm.L": {"rot": (10.0, 0.0, 18.0)}, "LowerArm.L": {"rot": (6.0, 0.0, -5.0)}, "Torso": {"rot": (0.0, 0.0, 6.0)}}),
        (16, {}),
    ])
    make_action(armature, "thrust_spear", 16, [
        (1, {}),
        (5, {"Torso": {"rot": (-5.0, 0.0, 6.0)}, "UpperArm.R": {"rot": (-48.0, 0.0, 14.0)}, "LowerArm.R": {"rot": (-62.0, 0.0, -6.0)}, "UpperArm.L": {"rot": (-30.0, 0.0, -16.0)}, "LowerArm.L": {"rot": (-42.0, 0.0, 6.0)}, "UpperLeg.R": {"rot": (-8.0, 0.0, 0.0)}, "UpperLeg.L": {"rot": (8.0, 0.0, 0.0)}}),
        (10, {"Torso": {"rot": (7.0, 0.0, -5.0)}, "UpperArm.R": {"rot": (-82.0, 0.0, 6.0)}, "LowerArm.R": {"rot": (-12.0, 0.0, 2.0)}, "UpperArm.L": {"rot": (-58.0, 0.0, -8.0)}, "LowerArm.L": {"rot": (-18.0, 0.0, -2.0)}, "UpperLeg.R": {"rot": (12.0, 0.0, 0.0)}, "LowerLeg.R": {"rot": (14.0, 0.0, 0.0)}, "UpperLeg.L": {"rot": (-12.0, 0.0, 0.0)}}),
        (16, {}),
    ])
    make_action(armature, "bash_shield", 14, [
        (1, {}),
        (5, {"Torso": {"rot": (-4.0, 0.0, -6.0)}, "UpperArm.L": {"rot": (-48.0, 0.0, -30.0)}, "LowerArm.L": {"rot": (-56.0, 0.0, 8.0)}, "Hand.L": {"rot": (0.0, 0.0, -8.0)}}),
        (9, {"Torso": {"rot": (8.0, 0.0, 7.0)}, "UpperArm.L": {"rot": (-78.0, 0.0, -10.0)}, "LowerArm.L": {"rot": (-16.0, 0.0, 2.0)}, "Hand.L": {"rot": (0.0, 0.0, 6.0)}, "UpperLeg.L": {"rot": (-10.0, 0.0, 0.0)}, "UpperLeg.R": {"rot": (10.0, 0.0, 0.0)}}),
        (14, {}),
    ])
    make_action(armature, "claw_swipe", 14, [
        (1, {}),
        (5, {"Torso": {"rot": (-5.0, 0.0, 0.0)}, "UpperArm.R": {"rot": (-48.0, 0.0, 26.0)}, "UpperArm.L": {"rot": (-48.0, 0.0, -26.0)}, "LowerArm.R": {"rot": (-38.0, 0.0, -8.0)}, "LowerArm.L": {"rot": (-38.0, 0.0, 8.0)}}),
        (9, {"Torso": {"rot": (8.0, 0.0, 0.0)}, "UpperArm.R": {"rot": (-72.0, 0.0, -18.0)}, "UpperArm.L": {"rot": (-72.0, 0.0, 18.0)}, "LowerArm.R": {"rot": (-12.0, 0.0, 4.0)}, "LowerArm.L": {"rot": (-12.0, 0.0, -4.0)}}),
        (14, {}),
    ])


# ============================================================================
# Animated-scene export
# ============================================================================

def export_glb(path: Path) -> Path:
    path = Path(path)
    if path.suffix.lower() != ".glb":
        raise ValueError(f"animated GLB output must end in .glb: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    # Always export from rest pose (not the last animation keyframe).
    # Otherwise Hand.R / UpperArm.R freeze in hold_weapon/slash pose and look missing.
    for obj in bpy.context.scene.objects:
        if obj.type == "ARMATURE":
            ad = obj.animation_data
            if ad is not None:
                # Force strip/action names to match NLA track names (game animation names).
                for track in ad.nla_tracks:
                    for strip in track.strips:
                        if strip.action is not None and strip.action.name != track.name:
                            strip.action.name = track.name
                        strip.name = track.name
            _reset_pose(obj)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="SELECT")
    # NLA_TRACKS keeps authored track names (idle/run/slash). ACTIONS may fall back to
    # locale defaults like ``Armature动作`` / ``ArmatureAction``.
    export_kwargs = dict(
        filepath=str(path),
        export_format="GLB",
        export_animations=True,
        export_frame_range=False,
        export_force_sampling=True,
        export_yup=True,
        export_apply=True,
    )
    exported = False
    for mode in ("NLA_TRACKS", "ACTIONS"):
        try:
            kwargs = dict(export_kwargs)
            kwargs["export_animation_mode"] = mode
            bpy.ops.export_scene.gltf(**kwargs)
            exported = True
            print(f"  export_animation_mode={mode}")
            break
        except TypeError:
            continue
    if not exported:
        bpy.ops.export_scene.gltf(
            filepath=str(path),
            export_format="GLB",
            export_animations=True,
            export_yup=True,
            export_apply=True,
        )
        print("  export_animation_mode=<default>")
    print(f"  exported: {path}")
    return path
