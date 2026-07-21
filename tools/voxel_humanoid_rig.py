from __future__ import annotations

from dataclasses import dataclass

import bpy
from mathutils import Vector


PX = 1.0 / 32.0
REFERENCE_HEIGHT_PX = 42.0


@dataclass(frozen=True)
class BoneDef:
    name: str
    head_px: tuple[float, float, float]
    tail_px: tuple[float, float, float]
    parent: str = ""


REFERENCE_BONES: tuple[BoneDef, ...] = (
    BoneDef("Root", (0.0, 0.0, 0.0), (0.0, 0.0, 4.0)),
    BoneDef("Pelvis", (0.0, 0.0, 14.0), (0.0, 0.0, 18.0), "Root"),
    BoneDef("Torso", (0.0, 0.0, 18.0), (0.0, 0.0, 31.0), "Pelvis"),
    BoneDef("Neck", (0.0, 0.0, 31.0), (0.0, 0.0, 33.0), "Torso"),
    BoneDef("Head", (0.0, 0.0, 33.0), (0.0, 0.0, 42.0), "Neck"),
    BoneDef("UpperArm.R", (5.5, 0.0, 29.0), (9.0, 0.0, 23.0), "Torso"),
    BoneDef("LowerArm.R", (9.0, 0.0, 23.0), (9.8, 0.0, 15.0), "UpperArm.R"),
    BoneDef("Hand.R", (9.8, 0.0, 15.0), (9.8, -1.0, 12.0), "LowerArm.R"),
    BoneDef("UpperArm.L", (-5.5, 0.0, 29.0), (-9.0, 0.0, 23.0), "Torso"),
    BoneDef("LowerArm.L", (-9.0, 0.0, 23.0), (-9.8, 0.0, 15.0), "UpperArm.L"),
    BoneDef("Hand.L", (-9.8, 0.0, 15.0), (-9.8, -1.0, 12.0), "LowerArm.L"),
    BoneDef("UpperLeg.R", (2.8, 0.0, 14.0), (2.8, 0.0, 8.0), "Pelvis"),
    # LowerLeg 保持纯垂直方向（head/tail 的 X/Y 相同），避免 Blender glTF
    # 导出器对角度骨骼的局部坐标系翻转 bug（原 tail 有 +0.7X/-0.5Y 偏移）。
    BoneDef("LowerLeg.R", (2.8, 0.0, 8.0), (2.8, 0.0, 2.0), "UpperLeg.R"),
    BoneDef("Foot.R", (2.8, 0.0, 2.0), (3.5, -4.0, 1.0), "LowerLeg.R"),
    BoneDef("UpperLeg.L", (-2.8, 0.0, 14.0), (-2.8, 0.0, 8.0), "Pelvis"),
    BoneDef("LowerLeg.L", (-2.8, 0.0, 8.0), (-2.8, 0.0, 2.0), "UpperLeg.L"),
    BoneDef("Foot.L", (-2.8, 0.0, 2.0), (-3.5, -4.0, 1.0), "LowerLeg.L"),
)


def px_to_m(value_px: float, height_px: float = REFERENCE_HEIGHT_PX) -> float:
    return value_px * (height_px / REFERENCE_HEIGHT_PX) * PX


def point_px_to_m(point: tuple[float, float, float], height_px: float = REFERENCE_HEIGHT_PX) -> Vector:
    return Vector((px_to_m(point[0], height_px), px_to_m(point[1], height_px), px_to_m(point[2], height_px)))


def create_voxel_humanoid_armature(
    height_px: float = REFERENCE_HEIGHT_PX,
    name: str = "VoxelHumanoidRig",
) -> bpy.types.Object:
    bpy.ops.object.armature_add(enter_editmode=True, location=(0.0, 0.0, 0.0))
    armature = bpy.context.object
    armature.name = name
    armature.data.name = f"{name}Data"
    armature["height_px"] = height_px
    armature["meters_per_pixel"] = PX
    armature["reference_height_px"] = REFERENCE_HEIGHT_PX

    edit_bones = armature.data.edit_bones
    for bone in list(edit_bones):
        edit_bones.remove(bone)

    created: dict[str, bpy.types.EditBone] = {}
    for bone_def in REFERENCE_BONES:
        bone = edit_bones.new(bone_def.name)
        bone.head = point_px_to_m(bone_def.head_px, height_px)
        bone.tail = point_px_to_m(bone_def.tail_px, height_px)
        if (bone.tail - bone.head).length < PX * 0.25:
            bone.tail = bone.head + Vector((0.0, 0.0, PX * 0.25))
        created[bone_def.name] = bone

    for bone_def in REFERENCE_BONES:
        if bone_def.parent:
            created[bone_def.name].parent = created[bone_def.parent]
            created[bone_def.name].use_connect = False

    bpy.ops.object.mode_set(mode="OBJECT")
    return armature


def parent_object_to_bone(obj: bpy.types.Object, armature: bpy.types.Object, bone_name: str) -> None:
    matrix = obj.matrix_world.copy()
    obj.parent = armature
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_world = matrix


def parent_parts_by_bone(parts_by_bone: dict[str, list[bpy.types.Object]], armature: bpy.types.Object) -> None:
    for bone_name, objects in parts_by_bone.items():
        if bone_name not in armature.data.bones:
            continue
        for obj in objects:
            parent_object_to_bone(obj, armature, bone_name)
