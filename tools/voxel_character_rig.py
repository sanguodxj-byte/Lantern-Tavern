"""Humanoid action authoring and animated GLB export mechanics.

The caller owns armature construction, mesh binding, model identity, and exact
paths. This module only writes actions onto an existing humanoid armature and
exports the already assembled Blender scene.
"""
from __future__ import annotations

import math
from pathlib import Path

import bpy

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


def build_all_actions(armature):
    """创建与 character.glb 完全一致的 12 个动画动作。"""
    make_action(armature, "idle", 29,
        [(1, {}), (15, {"Torso": {"rot": (0, 0, 2)}, "Head": {"rot": (0, 3, 0)}, "UpperArm.R": {"rot": (-5, 0, 3)}, "UpperArm.L": {"rot": (-5, 0, -3)}}), (29, {})]
    )
    make_action(armature, "run", 12,
        [(1, {"UpperLeg.R": {"rot": (30, 0, 0)}, "UpperLeg.L": {"rot": (-30, 0, 0)}, "UpperArm.R": {"rot": (-20, 0, -25)}, "UpperArm.L": {"rot": (-20, 0, 25)}, "Torso": {"rot": (8, 0, 0)}}),
         (6, {"UpperLeg.R": {"rot": (-30, 0, 0)}, "UpperLeg.L": {"rot": (30, 0, 0)}, "UpperArm.R": {"rot": (-20, 0, 25)}, "UpperArm.L": {"rot": (-20, 0, -25)}, "Torso": {"rot": (8, 0, 0)}}),
         (12, {"UpperLeg.R": {"rot": (30, 0, 0)}, "UpperLeg.L": {"rot": (-30, 0, 0)}, "UpperArm.R": {"rot": (-20, 0, -25)}, "UpperArm.L": {"rot": (-20, 0, 25)}, "Torso": {"rot": (8, 0, 0)}})]
    )
    make_action(armature, "slash", 10,
        [(1, {"Torso": {"rot": (0, -8, -10)}, "UpperArm.R": {"rot": (-40, -20, 40)}, "LowerArm.R": {"rot": (-40, 8, 10)}, "Hand.R": {"rot": (0, -35, 35)}}),
         (5, {"Torso": {"rot": (0, 4, 8)}, "UpperArm.R": {"rot": (-10, 20, -34)}, "LowerArm.R": {"rot": (-30, -8, -16)}, "Hand.R": {"rot": (0, 40, -42)}}),
         (10, {"Torso": {"rot": (0, 0, 0)}, "UpperArm.R": {"rot": (-18, 0, 4)}, "LowerArm.R": {"rot": (-12, 0, 0)}, "Hand.R": {"rot": (0, 0, 0)}})]
    )
    make_action(armature, "block", 8,
        [(1, {"UpperArm.L": {"rot": (-30, 0, -45)}, "LowerArm.L": {"rot": (-60, 0, 0)}, "Torso": {"rot": (0, 0, -5)}}),
         (4, {"UpperArm.L": {"rot": (-50, 0, -60)}, "LowerArm.L": {"rot": (-80, 0, 0)}, "Torso": {"rot": (0, 0, -8)}}),
         (8, {"UpperArm.L": {"rot": (-30, 0, -45)}, "LowerArm.L": {"rot": (-60, 0, 0)}, "Torso": {"rot": (0, 0, -5)}})]
    )
    make_action(armature, "hurt", 8,
        [(1, {"Torso": {"rot": (-15, 0, 0), "loc": (0, 0, -0.05)}, "Head": {"rot": (-20, 0, 0)}, "UpperArm.R": {"rot": (-30, 0, 20)}, "UpperArm.L": {"rot": (-30, 0, -20)}}),
         (4, {"Torso": {"rot": (-8, 0, 0), "loc": (0, 0, -0.02)}, "Head": {"rot": (-10, 0, 0)}}),
         (8, {})]
    )
    make_action(armature, "stunned", 10,
        [(1, {"Torso": {"rot": (-5, 0, 5)}, "Head": {"rot": (-10, 5, 0)}, "UpperArm.R": {"rot": (-15, 0, 15)}, "UpperArm.L": {"rot": (-15, 0, -15)}}),
         (5, {"Torso": {"rot": (-5, 0, -5)}, "Head": {"rot": (-10, -5, 0)}, "UpperArm.R": {"rot": (-15, 0, -15)}, "UpperArm.L": {"rot": (-15, 0, 15)}}),
         (10, {"Torso": {"rot": (-5, 0, 5)}, "Head": {"rot": (-10, 5, 0)}, "UpperArm.R": {"rot": (-15, 0, 15)}, "UpperArm.L": {"rot": (-15, 0, -15)}})]
    )
    make_action(armature, "death", 20,
        [(1, {"Torso": {"rot": (-10, 0, 0)}, "Head": {"rot": (-15, 0, 0)}}),
         (8, {"Torso": {"rot": (-60, 0, 10), "loc": (0, 0, -0.3)}, "Head": {"rot": (-30, 0, 0)}, "UpperArm.R": {"rot": (-20, 0, 30)}, "UpperArm.L": {"rot": (-20, 0, -30)}, "UpperLeg.R": {"rot": (20, 0, 0)}, "UpperLeg.L": {"rot": (20, 0, 0)}}),
         (20, {"Torso": {"rot": (-85, 0, 10), "loc": (0, 0, -0.6)}, "Head": {"rot": (-40, 0, 0)}, "UpperArm.R": {"rot": (-30, 0, 40)}, "UpperArm.L": {"rot": (-30, 0, -40)}, "UpperLeg.R": {"rot": (30, 0, 0)}, "UpperLeg.L": {"rot": (30, 0, 0)}})]
    )
    make_action(armature, "kick", 6,
        [(1, {"UpperLeg.R": {"rot": (-60, 0, 0)}, "LowerLeg.R": {"rot": (40, 0, 0)}, "Torso": {"rot": (-5, 0, 0)}}),
         (3, {"UpperLeg.R": {"rot": (-80, 0, 0)}, "LowerLeg.R": {"rot": (10, 0, 0)}, "Torso": {"rot": (-10, 0, 0)}}),
         (6, {})]
    )
    make_action(armature, "lift", 8,
        [(1, {"UpperArm.R": {"rot": (-20, 0, 10)}, "UpperArm.L": {"rot": (-20, 0, -10)}, "LowerArm.R": {"rot": (-30, 0, 0)}, "LowerArm.L": {"rot": (-30, 0, 0)}}),
         (4, {"UpperArm.R": {"rot": (-70, 0, 5)}, "UpperArm.L": {"rot": (-70, 0, -5)}, "LowerArm.R": {"rot": (-50, 0, 0)}, "LowerArm.L": {"rot": (-50, 0, 0)}, "Torso": {"rot": (-5, 0, 0)}}),
         (8, {"UpperArm.R": {"rot": (-20, 0, 10)}, "UpperArm.L": {"rot": (-20, 0, -10)}, "LowerArm.R": {"rot": (-30, 0, 0)}, "LowerArm.L": {"rot": (-30, 0, 0)}})]
    )
    make_action(armature, "pickup", 5,
        [(1, {"UpperArm.R": {"rot": (-40, 0, 10)}, "UpperArm.L": {"rot": (-40, 0, -10)}, "LowerArm.R": {"rot": (-50, 0, 0)}, "LowerArm.L": {"rot": (-50, 0, 0)}, "Torso": {"rot": (-10, 0, 0)}}),
         (5, {})]
    )
    make_action(armature, "throw_weapon", 6,
        [(1, {"UpperArm.R": {"rot": (-60, 0, 20)}, "LowerArm.R": {"rot": (-40, 0, 0)}, "Torso": {"rot": (-5, 0, 5)}}),
         (3, {"UpperArm.R": {"rot": (-80, 0, 30)}, "LowerArm.R": {"rot": (-10, 0, 0)}, "Torso": {"rot": (0, 0, 10)}}),
         (6, {"UpperArm.R": {"rot": (-10, 20, 0)}, "LowerArm.R": {"rot": (-10, 0, 0)}, "Torso": {"rot": (5, 0, -5)}})]
    )
    make_action(armature, "throw_furniture", 5,
        [(1, {"UpperArm.R": {"rot": (-50, 0, 15)}, "UpperArm.L": {"rot": (-50, 0, -15)}, "LowerArm.R": {"rot": (-30, 0, 0)}, "LowerArm.L": {"rot": (-30, 0, 0)}, "Torso": {"rot": (-8, 0, 0)}}),
         (5, {"UpperArm.R": {"rot": (10, 20, 0)}, "UpperArm.L": {"rot": (10, -20, 0)}, "LowerArm.R": {"rot": (0, 0, 0)}, "LowerArm.L": {"rot": (0, 0, 0)}, "Torso": {"rot": (5, 0, 0)}})]
    )


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

def build_weapon_actions(armature):
    """创建武器专用攻击动画 + 持武器姿态（人形专用）。"""

    # ---- default：零姿态 ----
    # 注意：空关键帧 {} 不会产生任何轨道，glTF 导出器会忽略无轨道的 action。
    # 因此显式为 Root 插入一个 (0,0,0) 旋转关键帧，确保 action 有至少一条轨道。
    make_action(armature, "default", 1, [(1, {"Root": {"rot": (0, 0, 0)}})])

    # ---- hold_weapon：持武器待机姿态（单帧）----
    # 右臂前抬握持武器，左臂前抬备盾，躯干微转成战斗预备。
    make_action(armature, "hold_weapon", 1,
        [(1, {
            "UpperArm.R": {"rot": (-30, 0, 25)},
            "LowerArm.R": {"rot": (-40, 0, 0)},
            "Hand.R": {"rot": (0, -20, 20)},
            "UpperArm.L": {"rot": (-20, 0, -30)},
            "LowerArm.L": {"rot": (-50, 0, 0)},
        })]
    )

    # ---- slash_one_hand：右肩后上方蓄力，跨身向前下方完成对角挥砍（10帧）----
    make_action(armature, "slash_one_hand", 10,
        [(1,  {"UpperArm.R": {"rot": (-30, 0, 25)}, "LowerArm.R": {"rot": (-40, 0, 0)},
               "Hand.R": {"rot": (0, -20, 20)}, "Torso": {"rot": (0, 0, 0)}}),
         (4,  {"UpperArm.R": {"rot": (-60, -105, 45)}, "LowerArm.R": {"rot": (120, 150, -105)},
               "Hand.R": {"rot": (150, 0, -30)}, "Torso": {"rot": (0, 8, 8)}}),
         (7,  {"UpperArm.R": {"rot": (-105, 15, -45)}, "LowerArm.R": {"rot": (150, 90, 120)},
               "Hand.R": {"rot": (-150, 0, 30)}, "Torso": {"rot": (0, -10, -12)}}),
         (10, {})]
    )

    # ---- slash_heavy：双手过头劈砍（14帧）----
    make_action(armature, "slash_heavy", 14,
        [(1,  {"UpperArm.R": {"rot": (-60, 0, 30)}, "UpperArm.L": {"rot": (-60, 0, -30)},
               "LowerArm.R": {"rot": (-30, 0, 0)}, "LowerArm.L": {"rot": (-30, 0, 0)}, "Torso": {"rot": (-8, 0, -5)}}),
         (5,  {"UpperArm.R": {"rot": (-90, -5, 40)}, "UpperArm.L": {"rot": (-90, 5, -40)},
               "LowerArm.R": {"rot": (-50, 0, 0)}, "LowerArm.L": {"rot": (-50, 0, 0)}, "Torso": {"rot": (-15, 0, -8)}}),
         (9,  {"UpperArm.R": {"rot": (30, 0, -20)}, "UpperArm.L": {"rot": (30, 0, 20)},
               "LowerArm.R": {"rot": (20, 0, 0)}, "LowerArm.L": {"rot": (20, 0, 0)}, "Torso": {"rot": (15, 0, 8)}}),
         (14, {})]
    )

    # ---- slash_dagger：匕首快速双手交替连斩（8帧）----
    make_action(armature, "slash_dagger", 8,
        [(1, {"UpperArm.R": {"rot": (-40, 0, 30)}, "UpperArm.L": {"rot": (-20, 0, -20)},
              "LowerArm.R": {"rot": (-30, 0, 0)}, "LowerArm.L": {"rot": (-20, 0, 0)}}),
         (3, {"UpperArm.R": {"rot": (20, 10, -15)}, "UpperArm.L": {"rot": (-50, 0, -35)},
              "LowerArm.R": {"rot": (10, 0, 0)}, "LowerArm.L": {"rot": (-40, 0, 0)}}),
         (5, {"UpperArm.R": {"rot": (-50, 0, 35)}, "UpperArm.L": {"rot": (20, -10, 15)},
              "LowerArm.R": {"rot": (-40, 0, 0)}, "LowerArm.L": {"rot": (10, 0, 0)}}),
         (8, {})]
    )

    # ---- thrust_spear：长矛向前突刺（10帧）----
    make_action(armature, "thrust_spear", 10,
        [(1,  {"UpperArm.R": {"rot": (-30, -10, 15)}, "LowerArm.R": {"rot": (-60, 0, 0)}, "Torso": {"rot": (0, 5, 0)}}),
         (4,  {"UpperArm.R": {"rot": (-40, -15, 10)}, "LowerArm.R": {"rot": (-80, 0, 0)}, "Torso": {"rot": (-5, 8, 0)}}),
         (7,  {"UpperArm.R": {"rot": (-10, 0, 5)}, "LowerArm.R": {"rot": (-10, 0, 0)}, "Torso": {"rot": (5, -5, 0)}}),
         (10, {})]
    )

    # ---- bash_shield：左手盾击前推（8帧）----
    make_action(armature, "bash_shield", 8,
        [(1, {"UpperArm.L": {"rot": (-30, 0, -40)}, "LowerArm.L": {"rot": (-50, 0, 0)}, "Torso": {"rot": (0, 5, 5)}}),
         (4, {"UpperArm.L": {"rot": (-40, 10, -50)}, "LowerArm.L": {"rot": (-60, 0, 0)}, "Torso": {"rot": (-3, 8, 8)}}),
         (6, {"UpperArm.L": {"rot": (-10, -20, -10)}, "LowerArm.L": {"rot": (-20, 0, 0)}, "Torso": {"rot": (3, -10, -3)}}),
         (8, {})]
    )

    # ---- claw_swipe：徒手双手爪击（8帧）----
    make_action(armature, "claw_swipe", 8,
        [(1, {"UpperArm.R": {"rot": (-40, 0, 35)}, "UpperArm.L": {"rot": (-40, 0, -35)},
              "LowerArm.R": {"rot": (-30, 0, 0)}, "LowerArm.L": {"rot": (-30, 0, 0)}, "Torso": {"rot": (0, -5, 0)}}),
         (4, {"UpperArm.R": {"rot": (25, 10, -25)}, "UpperArm.L": {"rot": (25, -10, 25)},
              "LowerArm.R": {"rot": (15, 0, 0)}, "LowerArm.L": {"rot": (15, 0, 0)}, "Torso": {"rot": (0, 10, 0)}}),
         (8, {})]
    )

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
