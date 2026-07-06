import math
import sys
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[1]
CHARACTER_GLB = ROOT / "assets" / "meshes" / "characters" / "character.glb"


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def import_character() -> bpy.types.Object:
    bpy.ops.import_scene.gltf(filepath=str(CHARACTER_GLB))
    for obj in bpy.context.scene.objects:
        if obj.type == "ARMATURE":
            obj.name = "Armature"
            return obj
    raise RuntimeError("No armature found in character.glb")


def ensure_pose_mode(armature: bpy.types.Object) -> None:
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"


def reset_pose(armature: bpy.types.Object) -> None:
    for bone in armature.pose.bones:
        bone.location = (0.0, 0.0, 0.0)
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def key_bone(armature: bpy.types.Object, bone_name: str, frame: int, rot=(0.0, 0.0, 0.0), loc=None) -> None:
    bone = armature.pose.bones.get(bone_name)
    if bone is None:
        return
    bone.rotation_euler = tuple(math.radians(v) for v in rot)
    bone.keyframe_insert("rotation_euler", frame=frame)
    if loc is not None:
        bone.location = loc
        bone.keyframe_insert("location", frame=frame)


def key_pose(armature: bpy.types.Object, frame: int, keys: dict) -> None:
    reset_pose(armature)
    for bone_name, values in keys.items():
        rot = values.get("rot", (0.0, 0.0, 0.0))
        loc = values.get("loc")
        key_bone(armature, bone_name, frame, rot, loc)


def make_action(armature: bpy.types.Object, name: str, length_frames: int, frames: list[tuple[int, dict]]) -> None:
    action = bpy.data.actions.new(name)
    armature.animation_data_create()
    armature.animation_data.action = action
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = length_frames
    for frame, keys in frames:
        bpy.context.scene.frame_set(frame)
        key_pose(armature, frame, keys)
    action.frame_range = (1, length_frames)
    if armature.animation_data.nla_tracks.get(name) is None:
        track = armature.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.frame_end = length_frames
    print(f"created action {name} frames=1-{length_frames}")


def build_actions(armature: bpy.types.Object) -> None:
    make_action(
        armature,
        "slash_one_hand",
        15,
        [
            (1, {"Torso": {"rot": (0, -8, -10)}, "UpperArm.R": {"rot": (-40, -20, 40)}, "LowerArm.R": {"rot": (-40, 8, 10)}, "Hand.R": {"rot": (0, -35, 35)}}),
            (5, {"Torso": {"rot": (0, 4, 8)}, "UpperArm.R": {"rot": (-10, 20, -34)}, "LowerArm.R": {"rot": (-30, -8, -16)}, "Hand.R": {"rot": (0, 40, -42)}}),
            (9, {"Torso": {"rot": (0, 10, 14)}, "UpperArm.R": {"rot": (-4, 36, -54)}, "LowerArm.R": {"rot": (-18, -16, -24)}, "Hand.R": {"rot": (0, 52, -50)}}),
            (15, {"Torso": {"rot": (0, 0, 0)}, "UpperArm.R": {"rot": (-18, 0, 4)}, "LowerArm.R": {"rot": (-12, 0, 0)}, "Hand.R": {"rot": (0, 0, 0)}}),
        ],
    )
    make_action(
        armature,
        "slash_dagger",
        11,
        [
            (1, {"Torso": {"rot": (0, -5, -7)}, "UpperArm.R": {"rot": (-22, -12, 24)}, "LowerArm.R": {"rot": (-68, 4, 10)}, "Hand.R": {"rot": (0, -18, 28)}}),
            (4, {"Torso": {"rot": (0, 7, 10)}, "UpperArm.R": {"rot": (-4, 18, -20)}, "LowerArm.R": {"rot": (-50, -12, -16)}, "Hand.R": {"rot": (0, 28, -34)}}),
            (7, {"Torso": {"rot": (0, 10, 14)}, "UpperArm.R": {"rot": (2, 26, -32)}, "LowerArm.R": {"rot": (-38, -18, -20)}, "Hand.R": {"rot": (0, 34, -38)}}),
            (11, {"Torso": {"rot": (0, 0, 0)}, "UpperArm.R": {"rot": (-14, 0, 0)}, "LowerArm.R": {"rot": (-22, 0, 0)}, "Hand.R": {"rot": (0, 0, 0)}}),
        ],
    )
    make_action(
        armature,
        "slash_heavy",
        24,
        [
            (1, {"Torso": {"rot": (0, -14, -18)}, "UpperArm.R": {"rot": (-62, -26, 58)}, "LowerArm.R": {"rot": (-24, 10, 12)}, "Hand.R": {"rot": (0, -44, 42)}}),
            (8, {"Torso": {"rot": (0, -20, -24)}, "UpperArm.R": {"rot": (-76, -34, 68)}, "LowerArm.R": {"rot": (-18, 10, 16)}, "Hand.R": {"rot": (0, -52, 50)}}),
            (14, {"Torso": {"rot": (0, 14, 22)}, "UpperArm.R": {"rot": (8, 36, -56)}, "LowerArm.R": {"rot": (-20, -18, -22)}, "Hand.R": {"rot": (0, 58, -58)}}),
            (18, {"Torso": {"rot": (0, 18, 26)}, "UpperArm.R": {"rot": (18, 42, -68)}, "LowerArm.R": {"rot": (-10, -20, -24)}, "Hand.R": {"rot": (0, 64, -64)}}),
            (24, {"Torso": {"rot": (0, 0, 0)}, "UpperArm.R": {"rot": (-20, 0, 8)}, "LowerArm.R": {"rot": (-12, 0, 0)}, "Hand.R": {"rot": (0, 0, 0)}}),
        ],
    )
    make_action(
        armature,
        "thrust_spear",
        17,
        [
            (1, {"Torso": {"rot": (-4, -4, -4)}, "UpperArm.R": {"rot": (-24, -10, 10)}, "LowerArm.R": {"rot": (-50, 0, 0)}, "Hand.R": {"rot": (0, -8, 0)}}),
            (6, {"Torso": {"rot": (-8, -8, -8)}, "UpperArm.R": {"rot": (-34, -18, 18)}, "LowerArm.R": {"rot": (-64, 0, 0)}, "Hand.R": {"rot": (0, -12, 0)}}),
            (10, {"Torso": {"rot": (10, 4, 2), "loc": (0.0, -0.03, 0.0)}, "UpperArm.R": {"rot": (8, 4, -4)}, "LowerArm.R": {"rot": (-8, 0, 0)}, "Hand.R": {"rot": (0, 0, 0)}}),
            (17, {"Torso": {"rot": (0, 0, 0)}, "UpperArm.R": {"rot": (-16, 0, 0)}, "LowerArm.R": {"rot": (-16, 0, 0)}, "Hand.R": {"rot": (0, 0, 0)}}),
        ],
    )
    make_action(
        armature,
        "bash_shield",
        13,
        [
            (1, {"Torso": {"rot": (-6, 0, 6)}, "UpperArm.L": {"rot": (-20, 0, -30)}, "LowerArm.L": {"rot": (-44, 0, 0)}, "Hand.L": {"rot": (0, 0, -10)}}),
            (5, {"Torso": {"rot": (-12, 0, 10)}, "UpperArm.L": {"rot": (-34, 0, -38)}, "LowerArm.L": {"rot": (-58, 0, 0)}, "Hand.L": {"rot": (0, 0, -16)}}),
            (8, {"Torso": {"rot": (10, 0, -6), "loc": (0.0, -0.04, 0.0)}, "UpperArm.L": {"rot": (8, 0, -12)}, "LowerArm.L": {"rot": (-18, 0, 0)}, "Hand.L": {"rot": (0, 0, 0)}}),
            (13, {"Torso": {"rot": (0, 0, 0)}, "UpperArm.L": {"rot": (-12, 0, 0)}, "LowerArm.L": {"rot": (-18, 0, 0)}, "Hand.L": {"rot": (0, 0, 0)}}),
        ],
    )
    make_action(
        armature,
        "claw_swipe",
        13,
        [
            (1, {"Torso": {"rot": (0, -10, -10)}, "UpperArm.R": {"rot": (-36, -18, 36)}, "LowerArm.R": {"rot": (-52, 10, 10)}, "Hand.R": {"rot": (0, -20, 24)}}),
            (5, {"Torso": {"rot": (0, 8, 10)}, "UpperArm.R": {"rot": (-2, 28, -34)}, "LowerArm.R": {"rot": (-36, -12, -16)}, "Hand.R": {"rot": (0, 32, -30)}}),
            (9, {"Torso": {"rot": (0, 14, 16)}, "UpperArm.R": {"rot": (8, 40, -48)}, "LowerArm.R": {"rot": (-24, -18, -22)}, "Hand.R": {"rot": (0, 40, -40)}}),
            (13, {"Torso": {"rot": (0, 0, 0)}, "UpperArm.R": {"rot": (-14, 0, 0)}, "LowerArm.R": {"rot": (-18, 0, 0)}, "Hand.R": {"rot": (0, 0, 0)}}),
        ],
    )


def export_character() -> None:
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.export_scene.gltf(
        filepath=str(CHARACTER_GLB),
        export_format="GLB",
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=False,
        export_force_sampling=True,
        export_yup=True,
    )


def main() -> None:
    clear_scene()
    armature = import_character()
    ensure_pose_mode(armature)
    build_actions(armature)
    export_character()
    print(f"exported {CHARACTER_GLB}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
