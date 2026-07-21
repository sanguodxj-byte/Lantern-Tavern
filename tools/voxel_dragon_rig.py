"""Rig authoring and export for the fixed Lantern Sailwyrm dragon only.

This module deliberately owns no CLI, model registry, or multi-model dispatch.
The matching ``generate_voxel_dragon.py`` entry point supplies the two fixed
paths after it has generated and validated the dragon's static voxel assembly.
"""
from __future__ import annotations

from dataclasses import dataclass
import math
from pathlib import Path

import bpy
from mathutils import Vector


PX = 1.0 / 32.0
GROUND_OFFSET_M = PX
EXPECTED_STATIC_NAME = "voxel_dragon_256px.glb"
EXPECTED_RIG_NAME = "voxel_dragon_256px_rig.glb"
FACING_ROT_Z = -math.pi / 2.0


@dataclass(frozen=True)
class DragonBoneDef:
    name: str
    head_px: tuple[float, float, float]
    tail_px: tuple[float, float, float]
    parent: str = ""


DRAGON_BONES: tuple[DragonBoneDef, ...] = (
    DragonBoneDef("Root", (0.0, 0.0, 0.0), (0.0, 0.0, 28.0)),
    DragonBoneDef("Torso", (0.0, 0.0, 28.0), (0.0, 0.0, 48.0), "Root"),
    DragonBoneDef("Neck1", (-56.0, 0.0, 52.0), (-72.0, 0.0, 60.0), "Torso"),
    DragonBoneDef("Neck2", (-72.0, 0.0, 60.0), (-88.0, 0.0, 74.0), "Neck1"),
    DragonBoneDef("Head", (-88.0, 0.0, 74.0), (-116.0, 0.0, 86.0), "Neck2"),
    DragonBoneDef("Tail1", (52.0, 0.0, 40.0), (80.0, 0.0, 38.0), "Torso"),
    DragonBoneDef("Tail2", (80.0, 0.0, 38.0), (104.0, 0.0, 36.0), "Tail1"),
    DragonBoneDef("Tail3", (104.0, 0.0, 36.0), (126.0, 0.0, 36.0), "Tail2"),
    DragonBoneDef("Wing.L", (-4.0, -16.0, 58.0), (20.0, -94.0, 67.0), "Torso"),
    DragonBoneDef("Wing.R", (-4.0, 16.0, 58.0), (20.0, 94.0, 67.0), "Torso"),
    DragonBoneDef("FrontLeg.L", (-24.0, -14.0, 24.0), (-24.0, -14.0, 8.0), "Torso"),
    DragonBoneDef("FrontLeg.R", (-24.0, 14.0, 24.0), (-24.0, 14.0, 8.0), "Torso"),
    DragonBoneDef("BackLeg.L", (24.0, -14.0, 24.0), (24.0, -14.0, 8.0), "Torso"),
    DragonBoneDef("BackLeg.R", (24.0, 14.0, 24.0), (24.0, 14.0, 8.0), "Torso"),
)


def _clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.actions,
        bpy.data.armatures,
    ):
        for block in list(collection):
            collection.remove(block)


def _point_to_m(point: tuple[float, float, float]) -> Vector:
    return Vector((point[0] * PX, point[1] * PX, point[2] * PX))


def _create_dragon_armature() -> bpy.types.Object:
    bpy.ops.object.armature_add(enter_editmode=True, location=(0.0, 0.0, 0.0))
    armature = bpy.context.object
    armature.name = "Armature"
    armature.data.name = "ArmatureData"

    edit_bones = armature.data.edit_bones
    for bone in list(edit_bones):
        edit_bones.remove(bone)

    created: dict[str, bpy.types.EditBone] = {}
    for bone_def in DRAGON_BONES:
        bone = edit_bones.new(bone_def.name)
        bone.head = _point_to_m(bone_def.head_px)
        bone.tail = _point_to_m(bone_def.tail_px)
        if (bone.tail - bone.head).length < PX * 0.25:
            bone.tail = bone.head + Vector((0.0, 0.0, PX * 0.25))
        created[bone_def.name] = bone

    for bone_def in DRAGON_BONES:
        if bone_def.parent:
            created[bone_def.name].parent = created[bone_def.parent]
            created[bone_def.name].use_connect = False

    bpy.ops.object.mode_set(mode="OBJECT")
    return armature


def _assign_dragon_parts(parts: list[bpy.types.Object]) -> dict[str, list[bpy.types.Object]]:
    mapping: dict[str, list[bpy.types.Object]] = {}
    for obj in parts:
        name = obj.name.lower()
        bone = "Torso"
        if any(token in name for token in (
            "cranium", "muzzle", "mandible", "eye", "horn", "tusk", "tooth", "brow"
        )):
            bone = "Head"
        elif any(token in name for token in ("cervix_base", "cervix_crest_0", "cervix_glow_0")):
            bone = "Neck1"
        elif any(token in name for token in ("cervix_top", "cervix_crest_1", "cervix_glow_1")):
            bone = "Neck2"
        elif any(token in name for token in ("whip_0", "whip_1")):
            bone = "Tail1"
        elif "whip_2" in name or "whip_sail" in name:
            bone = "Tail2"
        elif "whip_3" in name or "tail_spike" in name:
            bone = "Tail3"
        elif "wing" in name:
            bone = "Wing.R" if "right" in name else "Wing.L"
        elif any(token in name for token in ("leg", "shin", "claw")):
            side = "R" if "right" in name else "L"
            limb = "FrontLeg" if "front" in name else "BackLeg"
            bone = f"{limb}.{side}"
        mapping.setdefault(bone, []).append(obj)
    return mapping


def _parent_object_to_bone(
    obj: bpy.types.Object,
    armature: bpy.types.Object,
    bone_name: str,
) -> None:
    world_transform = obj.matrix_world.copy()
    obj.parent = armature
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_world = world_transform


def _parent_dragon_parts(
    parts_by_bone: dict[str, list[bpy.types.Object]],
    armature: bpy.types.Object,
) -> None:
    for bone_name, objects in parts_by_bone.items():
        if bone_name not in armature.data.bones:
            raise RuntimeError(f"dragon part assignment references missing bone: {bone_name}")
        for obj in objects:
            _parent_object_to_bone(obj, armature, bone_name)


def _rad(degrees: float) -> float:
    return math.radians(degrees)


def _clear_pose_transforms(armature: bpy.types.Object) -> None:
    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.location = (0.0, 0.0, 0.0)
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def _reset_pose(armature: bpy.types.Object) -> None:
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
    count = len(action.fcurves) if hasattr(action, "fcurves") and action.fcurves else 0
    for layer in getattr(action, "layers", None) or []:
        for strip in getattr(layer, "strips", None) or []:
            bags = getattr(strip, "channelbags", None)
            if bags is None and hasattr(strip, "channelbag"):
                bags = [strip.channelbag] if strip.channelbag else []
            for bag in bags or []:
                count += len(getattr(bag, "fcurves", None) or [])
    return count


def _ensure_action_slot(armature: bpy.types.Object, action: bpy.types.Action):
    if not hasattr(action, "slots") or armature.animation_data is None:
        return None
    try:
        slot = action.slots.new(id_type="OBJECT", name=armature.name) \
            if len(action.slots) == 0 else action.slots[0]
        if hasattr(armature.animation_data, "action_slot"):
            armature.animation_data.action_slot = slot
        return slot
    except Exception:
        return None


def _key_bone(
    armature: bpy.types.Object,
    bone_name: str,
    frame: int,
    rotation=(0.0, 0.0, 0.0),
    location=None,
) -> None:
    bone = armature.pose.bones.get(bone_name)
    if bone is None:
        raise RuntimeError(f"dragon action references missing bone: {bone_name}")
    bone.rotation_mode = "XYZ"
    bone.rotation_euler = tuple(_rad(value) for value in rotation)
    bone.keyframe_insert("rotation_euler", frame=frame)
    if location is not None:
        bone.location = location
        bone.keyframe_insert("location", frame=frame)


def _key_pose(armature: bpy.types.Object, frame: int, keys: dict) -> None:
    _clear_pose_transforms(armature)
    for bone_name, values in keys.items():
        _key_bone(
            armature,
            bone_name,
            frame,
            values.get("rot", (0.0, 0.0, 0.0)),
            values.get("loc"),
        )


def _make_action(armature: bpy.types.Object, name: str, length: int, frames: list) -> None:
    existing = bpy.data.actions.get(name)
    if existing is not None:
        bpy.data.actions.remove(existing)

    action = bpy.data.actions.new(name=name)
    action.name = name
    armature.animation_data_create()
    animation_data = armature.animation_data
    for track in list(animation_data.nla_tracks):
        if track.name == name:
            animation_data.nla_tracks.remove(track)
    animation_data.action = action
    slot = _ensure_action_slot(armature, action)

    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = length
    for frame, keys in frames:
        bpy.context.scene.frame_set(frame)
        if animation_data.action != action:
            animation_data.action = action
            slot = _ensure_action_slot(armature, action) or slot
        _key_pose(armature, frame, keys)

    if animation_data.action is not None and animation_data.action != action:
        action = animation_data.action
        action.name = name
        slot = _ensure_action_slot(armature, action) or slot
    action.name = name
    if _action_channel_count(action) == 0:
        bpy.context.scene.frame_set(1)
        animation_data.action = action
        slot = _ensure_action_slot(armature, action) or slot
        _key_bone(armature, "Root", 1)

    track = animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 1, action)
    strip.name = name
    strip.frame_end = length
    if slot is not None and hasattr(strip, "action_slot"):
        try:
            strip.action_slot = slot
        except Exception:
            pass
    animation_data.action = None
    if hasattr(animation_data, "action_slot"):
        try:
            animation_data.action_slot = None
        except Exception:
            pass
    action.name = name
    print(f"  created dragon action: {name} (1-{length})")


def _build_dragon_actions(armature: bpy.types.Object) -> None:
    _make_action(armature, "idle", 29, [
        (1, {}),
        (15, {
            "Torso": {"rot": (0, 0, 1)}, "Head": {"rot": (0, 3, 0)},
            "Tail2": {"rot": (0, -3, 0)}, "Wing.L": {"rot": (-3, 0, 0)},
            "Wing.R": {"rot": (-3, 0, 0)},
        }),
        (29, {}),
    ])
    gait_a = {
        "FrontLeg.L": {"rot": (25, 0, 0)}, "FrontLeg.R": {"rot": (-25, 0, 0)},
        "BackLeg.L": {"rot": (-25, 0, 0)}, "BackLeg.R": {"rot": (25, 0, 0)},
        "Torso": {"rot": (3, 0, 0)}, "Tail1": {"rot": (0, 0, 3)},
        "Wing.L": {"rot": (-10, 0, 0)}, "Wing.R": {"rot": (-10, 0, 0)},
    }
    gait_b = {
        "FrontLeg.L": {"rot": (-25, 0, 0)}, "FrontLeg.R": {"rot": (25, 0, 0)},
        "BackLeg.L": {"rot": (25, 0, 0)}, "BackLeg.R": {"rot": (-25, 0, 0)},
        "Torso": {"rot": (3, 0, 0)}, "Tail1": {"rot": (0, 0, -3)},
        "Wing.L": {"rot": (-10, 0, 0)}, "Wing.R": {"rot": (-10, 0, 0)},
    }
    _make_action(armature, "run", 12, [(1, gait_a), (6, gait_b), (12, gait_a)])
    _make_action(armature, "slash", 10, [
        (1, {"Neck1": {"rot": (0, -8, 0)}, "Neck2": {"rot": (0, -5, 0)},
             "Head": {"rot": (-10, -5, 0)}, "Torso": {"rot": (0, -3, 0)}}),
        (5, {"Neck1": {"rot": (0, 15, 0)}, "Neck2": {"rot": (0, 10, 0)},
             "Head": {"rot": (-15, 12, 0)}, "Torso": {"rot": (0, 5, 0)}}),
        (10, {}),
    ])
    _make_action(armature, "block", 8, [
        (1, {"Wing.L": {"rot": (0, 0, 30)}, "Wing.R": {"rot": (0, 0, -30)},
             "Head": {"rot": (-5, 0, 0)}}),
        (4, {"Wing.L": {"rot": (0, 0, 45)}, "Wing.R": {"rot": (0, 0, -45)},
             "Head": {"rot": (-10, 0, 0)}}),
        (8, {"Wing.L": {"rot": (0, 0, 30)}, "Wing.R": {"rot": (0, 0, -30)},
             "Head": {"rot": (-5, 0, 0)}}),
    ])
    _make_action(armature, "hurt", 8, [
        (1, {"Torso": {"rot": (-5, 0, 0), "loc": (0.02, 0, 0)},
             "Head": {"rot": (-10, 0, 0)}, "Neck1": {"rot": (-5, 0, 0)}}),
        (4, {"Torso": {"rot": (-3, 0, 0), "loc": (0.01, 0, 0)}}),
        (8, {}),
    ])
    _make_action(armature, "stunned", 10, [
        (1, {"Head": {"rot": (0, 5, 3)}, "Neck2": {"rot": (0, 3, 2)},
             "Torso": {"rot": (0, 0, 2)}}),
        (5, {"Head": {"rot": (0, -5, -3)}, "Neck2": {"rot": (0, -3, -2)},
             "Torso": {"rot": (0, 0, -2)}}),
        (10, {"Head": {"rot": (0, 5, 3)}, "Neck2": {"rot": (0, 3, 2)},
              "Torso": {"rot": (0, 0, 2)}}),
    ])
    _make_action(armature, "death", 20, [
        (1, {"Torso": {"rot": (-5, 0, 0)}}),
        (8, {"Torso": {"rot": (-50, 0, 8), "loc": (0, 0, -0.3)},
             "Head": {"rot": (-30, 0, 0)}, "Neck1": {"rot": (-20, 0, 0)},
             "Neck2": {"rot": (-15, 0, 0)}, "Wing.L": {"rot": (0, 0, 20)},
             "Wing.R": {"rot": (0, 0, -20)}, "FrontLeg.L": {"rot": (30, 0, 0)},
             "FrontLeg.R": {"rot": (30, 0, 0)}, "BackLeg.L": {"rot": (30, 0, 0)},
             "BackLeg.R": {"rot": (30, 0, 0)}}),
        (20, {"Torso": {"rot": (-80, 0, 10), "loc": (0, 0, -0.5)},
              "Head": {"rot": (-40, 0, 0)}, "Neck1": {"rot": (-30, 0, 0)},
              "Neck2": {"rot": (-25, 0, 0)}, "Wing.L": {"rot": (0, 0, 30)},
              "Wing.R": {"rot": (0, 0, -30)}, "FrontLeg.L": {"rot": (45, 0, 0)},
              "FrontLeg.R": {"rot": (45, 0, 0)}, "BackLeg.L": {"rot": (45, 0, 0)},
              "BackLeg.R": {"rot": (45, 0, 0)}}),
    ])
    _make_action(armature, "kick", 6, [
        (1, {"BackLeg.R": {"rot": (-40, 0, 0)}, "Torso": {"rot": (-3, 0, 0)}}),
        (3, {"BackLeg.R": {"rot": (-70, 0, 0)}, "Torso": {"rot": (-8, 0, 0)}}),
        (6, {}),
    ])
    _make_action(armature, "lift", 8, [
        (1, {"Neck1": {"rot": (-10, 0, 0)}, "Neck2": {"rot": (-10, 0, 0)},
             "Head": {"rot": (-5, 0, 0)}, "Wing.L": {"rot": (-15, 0, 0)},
             "Wing.R": {"rot": (-15, 0, 0)}}),
        (4, {"Neck1": {"rot": (-20, 0, 0)}, "Neck2": {"rot": (-20, 0, 0)},
             "Head": {"rot": (-10, 0, 0)}, "Wing.L": {"rot": (-25, 0, 0)},
             "Wing.R": {"rot": (-25, 0, 0)}}),
        (8, {"Neck1": {"rot": (-10, 0, 0)}, "Neck2": {"rot": (-10, 0, 0)},
             "Head": {"rot": (-5, 0, 0)}, "Wing.L": {"rot": (-15, 0, 0)},
             "Wing.R": {"rot": (-15, 0, 0)}}),
    ])
    _make_action(armature, "pickup", 5, [
        (1, {"Neck1": {"rot": (15, 0, 0)}, "Neck2": {"rot": (15, 0, 0)},
             "Head": {"rot": (20, 0, 0)}, "Torso": {"rot": (5, 0, 0)}}),
        (5, {}),
    ])
    _make_action(armature, "throw_weapon", 6, [
        (1, {"Neck1": {"rot": (0, -10, 5)}, "Head": {"rot": (-10, -5, 0)},
             "Torso": {"rot": (0, -3, 3)}}),
        (3, {"Neck1": {"rot": (0, 15, -5)}, "Head": {"rot": (5, 10, 0)},
             "Torso": {"rot": (0, 5, -3)}}),
        (6, {}),
    ])
    _make_action(armature, "throw_furniture", 5, [
        (1, {"Torso": {"rot": (-5, 0, 0)}, "Wing.L": {"rot": (-20, 0, 0)},
             "Wing.R": {"rot": (-20, 0, 0)}, "Neck1": {"rot": (-10, 0, 0)}}),
        (5, {"Torso": {"rot": (5, 0, 0)}, "Wing.L": {"rot": (10, 0, 0)},
             "Wing.R": {"rot": (10, 0, 0)}, "Neck1": {"rot": (5, 0, 0)}}),
    ])
    _make_action(armature, "claw_swipe", 8, [
        (1, {"Neck1": {"rot": (0, -8, 0)}, "Neck2": {"rot": (0, -5, 0)},
             "Head": {"rot": (-10, -5, 0)}, "Torso": {"rot": (0, -3, 0)}}),
        (4, {"Neck1": {"rot": (0, 15, 0)}, "Neck2": {"rot": (0, 10, 0)},
             "Head": {"rot": (-15, 12, 0)}, "Torso": {"rot": (0, 5, 0)}}),
        (8, {}),
    ])
    _make_action(armature, "default", 1, [(1, {"Root": {"rot": (0, 0, 0)}})])


def _export_dragon_glb(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    for obj in bpy.context.scene.objects:
        if obj.type != "ARMATURE":
            continue
        animation_data = obj.animation_data
        if animation_data is not None:
            for track in animation_data.nla_tracks:
                for strip in track.strips:
                    if strip.action is not None:
                        strip.action.name = track.name
                    strip.name = track.name
        _reset_pose(obj)

    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="SELECT")
    kwargs = dict(
        filepath=str(path),
        export_format="GLB",
        export_animations=True,
        export_frame_range=False,
        export_force_sampling=True,
        export_yup=True,
        export_apply=True,
    )
    for mode in ("NLA_TRACKS", "ACTIONS"):
        try:
            bpy.ops.export_scene.gltf(export_animation_mode=mode, **kwargs)
            print(f"  exported dragon rig with animation mode {mode}: {path}")
            return
        except TypeError:
            continue
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_animations=True,
        export_yup=True,
        export_apply=True,
    )
    print(f"  exported dragon rig with default animation mode: {path}")


def build_dragon_rig(static_path: Path, rig_path: Path) -> Path:
    """Build exactly the dragon rig from and to its fixed asset filenames."""
    static_path = Path(static_path)
    rig_path = Path(rig_path)
    if static_path.name != EXPECTED_STATIC_NAME or rig_path.name != EXPECTED_RIG_NAME:
        raise ValueError("dragon rig exporter accepts only the fixed dragon asset filenames")
    if static_path.parent.resolve() != rig_path.parent.resolve():
        raise ValueError("dragon static and rig outputs must share one character asset directory")
    if not static_path.is_file():
        raise FileNotFoundError(static_path)

    _clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(static_path))
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not mesh_objects:
        raise RuntimeError(f"dragon static GLB contains no mesh objects: {static_path}")

    min_z = min(
        (obj.matrix_world @ Vector(corner)).z
        for obj in mesh_objects
        for corner in obj.bound_box
    )
    armature = _create_dragon_armature()
    assignments = _assign_dragon_parts(mesh_objects)
    if sum(len(objects) for objects in assignments.values()) != len(mesh_objects):
        raise RuntimeError("not every dragon mesh received exactly one bone assignment")
    _parent_dragon_parts(assignments, armature)

    if min_z < GROUND_OFFSET_M:
        armature.location.z += GROUND_OFFSET_M - min_z
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.rotation_euler = (0.0, 0.0, FACING_ROT_Z)

    _build_dragon_actions(armature)
    _export_dragon_glb(rig_path)
    return rig_path
