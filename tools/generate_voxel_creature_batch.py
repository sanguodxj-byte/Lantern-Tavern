from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(Path(__file__).resolve().parent))
from voxel_humanoid_rig import PX, REFERENCE_HEIGHT_PX, create_voxel_humanoid_armature, parent_parts_by_bone

OUT_DIR = ROOT / "assets" / "meshes" / "characters"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def px(value: float) -> float:
    return value * PX


def make_mat(name: str, color: tuple[float, float, float, float], emission: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = color
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.86
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = 0.0
        if emission > 0.0:
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = color
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def cube(name: str, loc_px: tuple[float, float, float], size_px: tuple[float, float, float], mat: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px(loc_px[0]), px(loc_px[1]), px(loc_px[2])))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (px(size_px[0]), px(size_px[1]), px(size_px[2]))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def cube_ref(
    name: str,
    loc_ref_px: tuple[float, float, float],
    size_ref_px: tuple[float, float, float],
    height_px: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    scale = height_px / REFERENCE_HEIGHT_PX
    loc = tuple(v * scale for v in loc_ref_px)
    size = tuple(v * scale for v in size_ref_px)
    return cube(name, loc, size, mat)


def make_root(name: str) -> bpy.types.Object:
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    return root


def parts_with_prefix(parts: list[bpy.types.Object], prefixes: list[str]) -> list[bpy.types.Object]:
    return [part for part in parts if any(part.name.startswith(prefix) for prefix in prefixes)]


def parent_humanoid_parts(parts: list[bpy.types.Object], armature: bpy.types.Object) -> None:
    parts_by_bone = {
        "Head": parts_with_prefix(parts, ["head_", "skull_", "jaw_", "eye_", "crown_", "horn_", "hood_", "face_"]),
        "Torso": parts_with_prefix(parts, ["torso_", "rib_", "robe_torso", "chest_", "spine_", "shoulder_"]),
        "Pelvis": parts_with_prefix(parts, ["pelvis_", "hip_", "robe_hip"]),
        "UpperArm.L": parts_with_prefix(parts, ["left_upper_arm", "left_shoulder"]),
        "LowerArm.L": parts_with_prefix(parts, ["left_forearm"]),
        "Hand.L": parts_with_prefix(parts, ["left_hand"]),
        "UpperArm.R": parts_with_prefix(parts, ["right_upper_arm", "right_shoulder"]),
        "LowerArm.R": parts_with_prefix(parts, ["right_forearm"]),
        "Hand.R": parts_with_prefix(parts, ["right_hand", "staff_"]),
        "UpperLeg.L": parts_with_prefix(parts, ["left_thigh", "left_upper_leg", "robe_left"]),
        "LowerLeg.L": parts_with_prefix(parts, ["left_shin", "left_lower_leg"]),
        "Foot.L": parts_with_prefix(parts, ["left_foot"]),
        "UpperLeg.R": parts_with_prefix(parts, ["right_thigh", "right_upper_leg", "robe_right"]),
        "LowerLeg.R": parts_with_prefix(parts, ["right_shin", "right_lower_leg"]),
        "Foot.R": parts_with_prefix(parts, ["right_foot"]),
    }
    parent_parts_by_bone(parts_by_bone, armature)


def build_skeleton() -> bpy.types.Object:
    height_px = 48.0
    bone = make_mat("skeleton_bone_mid", (0.78, 0.74, 0.62, 1.0))
    bone_light = make_mat("skeleton_bone_highlight", (0.96, 0.91, 0.72, 1.0))
    bone_shadow = make_mat("skeleton_bone_shadow", (0.45, 0.40, 0.30, 1.0))
    dark = make_mat("skeleton_dark_socket", (0.035, 0.025, 0.02, 1.0))
    rag = make_mat("skeleton_rotten_rag", (0.28, 0.20, 0.13, 1.0))

    root = make_root("voxel_skeleton_48px")
    armature = create_voxel_humanoid_armature(height_px, "VoxelHumanoidRig")
    armature.parent = root
    parts: list[bpy.types.Object] = []

    parts.append(cube_ref("skull_main", (0, 0, 36.5), (9.0, 7.0, 8.0), height_px, bone))
    parts.append(cube_ref("skull_left_highlight", (-3.2, -3.6, 37.0), (1.5, 0.6, 5.5), height_px, bone_light))
    parts.append(cube_ref("skull_right_shadow", (3.6, 3.2, 36.8), (1.2, 0.8, 5.8), height_px, bone_shadow))
    parts.append(cube_ref("eye_socket_l", (-2.0, -4.0, 37.2), (1.8, 0.5, 1.6), height_px, dark))
    parts.append(cube_ref("eye_socket_r", (2.0, -4.0, 37.2), (1.8, 0.5, 1.6), height_px, dark))
    parts.append(cube_ref("jaw_block", (0, -3.8, 32.5), (6.0, 1.0, 2.4), height_px, bone_shadow))

    parts.append(cube_ref("spine_stack_low", (0, 0, 18.0), (1.8, 1.8, 6.0), height_px, bone))
    parts.append(cube_ref("spine_stack_high", (0, 0, 25.0), (1.8, 1.8, 7.0), height_px, bone))
    for i, z in enumerate([22.0, 25.0, 28.0]):
        parts.append(cube_ref(f"rib_left_{i}", (-3.0, -0.2, z), (5.0, 1.4, 1.2), height_px, bone))
        parts.append(cube_ref(f"rib_right_{i}", (3.0, -0.2, z), (5.0, 1.4, 1.2), height_px, bone_shadow))
    parts.append(cube_ref("shoulder_bar", (0, 0, 30.0), (12.0, 2.0, 2.0), height_px, bone))
    parts.append(cube_ref("pelvis_plate", (0, 0, 14.2), (8.0, 3.0, 3.2), height_px, bone_shadow))
    parts.append(cube_ref("hip_rag", (0, -2.1, 13.0), (9.0, 1.0, 3.0), height_px, rag))

    for side, sx in [("left", -1), ("right", 1)]:
        prefix = f"{side}_"
        arm_mat = bone_light if side == "left" else bone
        parts.append(cube_ref(prefix + "upper_arm", (sx * 8.0, 0, 25.0), (2.2, 2.2, 10.0), height_px, arm_mat))
        parts.append(cube_ref(prefix + "forearm", (sx * 9.0, -0.3, 17.0), (2.0, 2.0, 8.0), height_px, arm_mat))
        parts.append(cube_ref(prefix + "hand_claws", (sx * 9.2, -1.8, 12.2), (3.0, 1.0, 1.2), height_px, bone_light))
        parts.append(cube_ref(prefix + "thigh", (sx * 2.6, 0, 9.0), (2.4, 2.4, 10.0), height_px, bone))
        parts.append(cube_ref(prefix + "shin", (sx * 2.8, -0.2, 4.0), (2.0, 2.0, 8.0), height_px, bone))
        parts.append(cube_ref(prefix + "foot", (sx * 3.0, -2.5, 1.2), (4.0, 4.0, 1.8), height_px, bone_shadow))

    parent_humanoid_parts(parts, armature)
    return root


def build_necrolord() -> bpy.types.Object:
    height_px = 80.0
    robe = make_mat("necrolord_robe_mid", (0.10, 0.08, 0.18, 1.0))
    robe_light = make_mat("necrolord_robe_highlight", (0.22, 0.18, 0.38, 1.0))
    robe_shadow = make_mat("necrolord_robe_shadow", (0.035, 0.025, 0.07, 1.0))
    bone = make_mat("necrolord_bone_face", (0.82, 0.78, 0.62, 1.0))
    gold = make_mat("necrolord_cold_gold", (0.78, 0.58, 0.18, 1.0))
    cyan = make_mat("necrolord_soul_cyan", (0.22, 0.95, 1.0, 1.0), 1.5)
    dark = make_mat("necrolord_socket_black", (0.01, 0.01, 0.025, 1.0))

    root = make_root("voxel_necrolord_80px_2_5m")
    armature = create_voxel_humanoid_armature(height_px, "VoxelHumanoidRig")
    armature.parent = root
    parts: list[bpy.types.Object] = []

    parts.append(cube_ref("robe_torso_main", (0, 0, 24.0), (13.0, 7.0, 17.0), height_px, robe))
    parts.append(cube_ref("robe_torso_highlight", (-4.5, -3.8, 25.0), (2.0, 0.9, 13.0), height_px, robe_light))
    parts.append(cube_ref("robe_torso_shadow", (4.8, 3.4, 24.0), (2.0, 1.0, 14.0), height_px, robe_shadow))
    parts.append(cube_ref("robe_hip_skirt", (0, 0, 13.0), (15.0, 8.0, 10.0), height_px, robe_shadow))
    parts.append(cube_ref("chest_soul_gem", (0, -4.2, 27.0), (3.0, 0.7, 4.0), height_px, cyan))

    parts.append(cube_ref("head_skull", (0, 0, 36.5), (9.5, 7.5, 8.5), height_px, bone))
    parts.append(cube_ref("face_shadow", (0, -4.1, 35.2), (6.5, 0.8, 4.5), height_px, dark))
    parts.append(cube_ref("eye_left_soul", (-2.3, -4.7, 37.0), (1.3, 0.45, 1.2), height_px, cyan))
    parts.append(cube_ref("eye_right_soul", (2.3, -4.7, 37.0), (1.3, 0.45, 1.2), height_px, cyan))
    parts.append(cube_ref("crown_band", (0, -0.2, 41.2), (11.0, 7.0, 1.5), height_px, gold))
    parts.append(cube_ref("crown_spike_mid", (0, -0.2, 43.4), (2.0, 2.0, 4.0), height_px, gold))
    parts.append(cube_ref("crown_spike_l", (-3.8, -0.2, 42.8), (1.6, 1.6, 3.0), height_px, gold))
    parts.append(cube_ref("crown_spike_r", (3.8, -0.2, 42.8), (1.6, 1.6, 3.0), height_px, gold))
    parts.append(cube_ref("hood_back", (0, 2.8, 36.5), (11.0, 2.0, 10.0), height_px, robe_shadow))

    for side, sx in [("left", -1), ("right", 1)]:
        parts.append(cube_ref(f"{side}_shoulder_pad", (sx * 8.0, 0, 29.5), (5.0, 6.0, 4.0), height_px, robe_shadow))
        parts.append(cube_ref(f"{side}_upper_arm", (sx * 9.0, 0, 23.0), (3.0, 3.5, 11.0), height_px, robe))
        parts.append(cube_ref(f"{side}_forearm", (sx * 10.0, -0.4, 15.0), (2.8, 3.0, 9.0), height_px, robe_shadow))
        parts.append(cube_ref(f"{side}_hand_bone", (sx * 10.2, -1.8, 10.5), (3.0, 1.5, 2.0), height_px, bone))
        parts.append(cube_ref(f"{side}_thigh_hidden", (sx * 3.0, 0, 8.0), (3.0, 3.0, 8.0), height_px, robe_shadow))
        parts.append(cube_ref(f"{side}_shin_hidden", (sx * 3.0, 0, 3.5), (3.0, 3.0, 7.0), height_px, robe_shadow))
        parts.append(cube_ref(f"{side}_foot", (sx * 3.2, -2.5, 1.0), (5.0, 4.5, 2.0), height_px, robe_shadow))

    parts.append(cube_ref("staff_shaft", (13.0, -2.6, 23.0), (1.1, 1.1, 32.0), height_px, gold))
    parts.append(cube_ref("staff_skull", (13.0, -2.6, 41.5), (4.5, 3.8, 4.8), height_px, bone))
    parts.append(cube_ref("staff_soul_flame", (13.0, -3.0, 46.0), (3.2, 2.2, 5.0), height_px, cyan))

    parent_humanoid_parts(parts, armature)
    return root


def build_rat() -> bpy.types.Object:
    fur = make_mat("rat_fur_mid", (0.28, 0.25, 0.22, 1.0))
    fur_light = make_mat("rat_fur_highlight", (0.48, 0.43, 0.36, 1.0))
    fur_shadow = make_mat("rat_fur_shadow", (0.13, 0.11, 0.10, 1.0))
    pink = make_mat("rat_ear_tail_pink", (0.60, 0.32, 0.30, 1.0))
    eye = make_mat("rat_eye_black", (0.01, 0.005, 0.005, 1.0))
    tooth = make_mat("rat_tooth", (0.90, 0.86, 0.70, 1.0))

    root = make_root("voxel_rat_12px_tall")
    parts = [
        cube("body", (0, 0, 6.5), (18, 8, 8), fur),
        cube("body_highlight", (-4.0, -4.3, 8.0), (8, 0.8, 3.0), fur_light),
        cube("body_shadow", (6.0, 3.8, 5.5), (7, 0.9, 4.0), fur_shadow),
        cube("head", (-11.0, -1.0, 7.0), (7, 6, 6), fur),
        cube("snout", (-15.0, -4.0, 6.5), (4, 3, 3), fur_light),
        cube("left_eye", (-13.0, -4.1, 8.3), (1.0, 0.35, 1.0), eye),
        cube("tooth", (-16.5, -5.5, 5.2), (0.8, 0.5, 1.0), tooth),
        cube("left_ear", (-10.5, 1.5, 11.0), (2.5, 1.5, 3.0), pink),
        cube("right_ear", (-8.0, 2.3, 10.6), (2.2, 1.3, 2.4), pink),
        cube("tail_base", (10.5, 1.0, 5.5), (8, 2, 2), pink),
        cube("tail_mid", (17.0, 1.4, 6.0), (7, 1.4, 1.4), pink),
        cube("tail_tip", (22.0, 1.8, 6.4), (4, 1.0, 1.0), pink),
    ]
    for sx in [-1, 1]:
        parts.append(cube(f"front_leg_{sx}", (-5.0, sx * 3.0, 2.4), (2.0, 1.2, 3.0), fur_shadow))
        parts.append(cube(f"back_leg_{sx}", (5.0, sx * 3.0, 2.4), (2.5, 1.2, 3.0), fur_shadow))
    for part in parts:
        part.parent = root
    return root


def build_slime() -> bpy.types.Object:
    gel = make_mat("slime_gel_mid", (0.10, 0.64, 0.54, 0.92), 0.5)
    gel_light = make_mat("slime_gel_highlight", (0.45, 1.0, 0.82, 1.0), 0.8)
    gel_shadow = make_mat("slime_gel_shadow", (0.03, 0.25, 0.23, 1.0), 0.2)
    core = make_mat("slime_inner_core", (0.78, 1.0, 0.38, 1.0), 1.1)
    eye = make_mat("slime_eye_dark", (0.02, 0.04, 0.04, 1.0))

    root = make_root("voxel_slime_18px")
    parts = [
        cube("base_shadow", (0, 0, 3.0), (22, 16, 6), gel_shadow),
        cube("body_mid", (0, 0, 9.0), (18, 14, 14), gel),
        cube("body_top", (-1.0, 0, 17.0), (12, 10, 6), gel),
        cube("left_highlight", (-5.5, -6.6, 12.0), (5.0, 0.8, 7.0), gel_light),
        cube("top_glint", (-3.0, -3.8, 20.2), (4.0, 1.0, 1.0), gel_light),
        cube("inner_core", (2.0, 0, 9.5), (5.0, 4.0, 4.0), core),
        cube("left_eye", (-3.2, -7.2, 12.0), (1.8, 0.5, 1.8), eye),
        cube("right_eye", (3.2, -7.2, 12.0), (1.8, 0.5, 1.8), eye),
        cube("mouth", (0, -7.4, 8.0), (4.0, 0.45, 1.2), eye),
    ]
    for part in parts:
        part.parent = root
    return root


def build_dragon() -> bpy.types.Object:
    scale_name = "5m_shoulder_height"
    scale_red = make_mat("dragon_scale_mid", (0.55, 0.08, 0.08, 1.0))
    scale_light = make_mat("dragon_scale_highlight", (0.85, 0.25, 0.12, 1.0))
    scale_shadow = make_mat("dragon_scale_shadow", (0.22, 0.04, 0.04, 1.0))
    wing = make_mat("dragon_wing_membrane", (0.15, 0.05, 0.05, 1.0))
    horn = make_mat("dragon_horn_bone", (0.82, 0.74, 0.52, 1.0))
    eye = make_mat("dragon_eye_gold", (1.0, 0.85, 0.18, 1.0), 1.6)
    lava_glow = make_mat("dragon_lava_glow", (1.0, 0.45, 0.0, 1.0), 1.2)

    shoulder_height_px = 160.0
    ref_shoulder_height = 39.0
    scale = shoulder_height_px / ref_shoulder_height

    def cube_dragon(name: str, loc_px: tuple[float, float, float], size_px: tuple[float, float, float], mat: bpy.types.Material) -> bpy.types.Object:
        s_loc = (loc_px[0] * scale, loc_px[1] * scale, loc_px[2] * scale)
        s_size = (size_px[0] * scale, size_px[1] * scale, size_px[2] * scale)
        return cube(name, s_loc, s_size, mat)

    root = make_root(f"voxel_dragon_{scale_name}")
    parts: list[bpy.types.Object] = []

    # 1. 躯干主段 - 前胸厚重，向后微窄
    parts.append(cube_dragon("torso_main", (0, 0, 46), (72, 30, 34), scale_red))
    parts.append(cube_dragon("torso_front_chest", (-26, 0, 48), (20, 34, 38), scale_red))
    parts.append(cube_dragon("torso_rear_hip", (26, 0, 44), (20, 26, 30), scale_shadow))
    parts.append(cube_dragon("torso_highlight", (-18, -15.8, 54), (26, 1.2, 12), scale_light))
    parts.append(cube_dragon("torso_shadow", (20, 14.5, 42), (28, 1.2, 14), scale_shadow))
    parts.append(cube_dragon("chest_plate", (-30, -17, 42), (18, 1.2, 18), lava_glow))

    # 层叠腹甲
    for i, x in enumerate([-20, -10, 0, 10, 20]):
        parts.append(cube_dragon(f"belly_plate_{i}", (x, -15.5, 36), (6.0, 1.0, 10.0), lava_glow))

    # 2. 脖脊 S 形优美曲线与头部重组
    # 脖子从胸部向上扬起，再平伸探向头部
    parts.append(cube_dragon("neck_0", (-42, -5, 52), (16, 18, 22), scale_red))
    parts.append(cube_dragon("neck_1", (-54, -9, 64), (16, 16, 20), scale_red))
    parts.append(cube_dragon("neck_2", (-68, -13, 72), (16, 14, 18), scale_red))
    parts.append(cube_dragon("neck_3", (-82, -17, 76), (16, 12, 16), scale_light))
    
    for i, x in enumerate([-42, -54, -68, -82]):
        parts.append(cube_dragon(f"neck_spike_{i}", (x, -10.0, 62 + i * 4), (3.0, 1.0, 6.0), lava_glow))

    # 头部 - 阶梯鼻梁与大恶魔弯角
    parts.append(cube_dragon("head_main", (-98, -20, 80), (24, 22, 20), scale_red))
    parts.append(cube_dragon("snout", (-118, -30, 78), (22, 14, 11), scale_light))
    parts.append(cube_dragon("jaw_shadow", (-114, -28, 69), (20, 12, 8), scale_shadow))
    parts.append(cube_dragon("left_eye", (-101, -32, 82), (3, 1, 3), eye))
    parts.append(cube_dragon("right_eye", (-89, -32, 82), (3, 1, 3), eye))
    
    # 额头眉骨隆起
    parts.append(cube_dragon("crest_left", (-105, -30, 85), (4, 3, 3), scale_light))
    parts.append(cube_dragon("crest_right", (-93, -30, 85), (4, 3, 3), scale_light))

    # 霸气大折角
    parts.append(cube_dragon("left_horn", (-106, -18, 92), (5, 5, 8), horn))
    parts.append(cube_dragon("right_horn", (-88, -18, 92), (5, 5, 8), horn))
    parts.append(cube_dragon("left_horn_mid", (-98, -17, 96), (8, 4, 5), lava_glow))
    parts.append(cube_dragon("right_horn_mid", (-96, -17, 96), (8, 4, 5), lava_glow))
    parts.append(cube_dragon("left_horn_tip", (-88, -16, 92), (12, 3, 3), horn))
    parts.append(cube_dragon("right_horn_tip", (-106, -16, 92), (12, 3, 3), horn))

    # 牙齿与獠牙
    for i, x in enumerate([-118, -112, -106]):
        parts.append(cube_dragon(f"tooth_{i}", (x, -37, 69), (2, 2, 5), horn))
    parts.append(cube_dragon("tusk_left", (-119, -32, 70), (2, 3, 7), horn))
    parts.append(cube_dragon("tusk_right", (-87, -32, 70), (2, 3, 7), horn))

    # 3. 尾部流线型下垂翘尾与星槌
    parts.append(cube_dragon("tail_0", (42, 3, 44), (22, 18, 18), scale_red))
    parts.append(cube_dragon("tail_1", (62, 6, 38), (22, 15, 15), scale_red))
    parts.append(cube_dragon("tail_2", (82, 9, 32), (22, 12, 12), scale_shadow))
    parts.append(cube_dragon("tail_3", (102, 12, 30), (22, 9, 9), scale_shadow))
    parts.append(cube_dragon("tail_4", (120, 15, 34), (18, 7, 7), scale_light))
    
    parts.append(cube_dragon("tail_spike", (132, 17, 38), (12, 8, 8), horn))
    parts.append(cube_dragon("tail_spike_top", (132, 17, 44), (4, 4, 6), lava_glow))
    parts.append(cube_dragon("tail_spike_bottom", (132, 17, 32), (4, 4, 6), lava_glow))

    # 4. 恶魔拱折翼与关节折弯肢体
    for side, sy in [("left", -1), ("right", 1)]:
        # 拱展折翼
        parts.append(cube_dragon(f"{side}_wing_arm", (-4, sy * 20, 68), (16, 14, 18), scale_shadow))
        parts.append(cube_dragon(f"{side}_wing_forearm", (2, sy * 34, 76), (34, 12, 8), scale_light))
        parts.append(cube_dragon(f"{side}_wing_tip", (12, sy * 52, 62), (10, 16, 12), scale_shadow))
        parts.append(cube_dragon(f"{side}_wing_membrane_a", (8, sy * 36, 52), (36, 4, 30), wing))
        parts.append(cube_dragon(f"{side}_wing_membrane_b", (22, sy * 44, 38), (28, 4, 22), wing))
        parts.append(cube_dragon(f"{side}_wing_claw", (-10, sy * 32, 68), (4, 4, 8), horn))

        # 弯关节腿爪 (Legs & Shins & Claws)
        # 前腿
        parts.append(cube_dragon(f"{side}_leg_-20_26", (-20, sy * 12, 28), (12, 12, 20), scale_shadow))
        parts.append(cube_dragon(f"{side}_shin_front", (-24, sy * 14, 14), (10, 10, 14), scale_red))
        parts.append(cube_dragon(f"{side}_claw_-20_26", (-26, sy * 16, 7), (14, 12, 6), horn))
        # 后腿
        parts.append(cube_dragon(f"{side}_leg_18_24", (18, sy * 12, 26), (14, 12, 18), scale_shadow))
        parts.append(cube_dragon(f"{side}_shin_back", (20, sy * 13, 13), (10, 10, 14), scale_red))
        parts.append(cube_dragon(f"{side}_claw_18_24", (18, sy * 15, 6), (14, 12, 6), horn))

    # 5. 背脊双排熔岩利刺
    for i, x in enumerate([-20, 0, 20, 42, 68, 90]):
        parts.append(cube_dragon(f"back_spike_{i}", (x, 1, 67 - i * 2), (5, 5, 12), horn))
        parts.append(cube_dragon(f"back_spike_extra_l_{i}", (x, -3, 68 - i * 2), (3, 3, 9), lava_glow))
        parts.append(cube_dragon(f"back_spike_extra_r_{i}", (x, 5, 68 - i * 2), (3, 3, 9), lava_glow))

    for part in parts:
        part.parent = root
    return root


def build_troll() -> bpy.types.Object:
    height_px = 64.0
    skin_mid = make_mat("troll_skin_mid", (0.28, 0.45, 0.35, 1.0))
    skin_light = make_mat("troll_skin_highlight", (0.42, 0.62, 0.50, 1.0))
    skin_shadow = make_mat("troll_skin_shadow", (0.15, 0.28, 0.22, 1.0))
    leather = make_mat("troll_leather", (0.22, 0.12, 0.08, 1.0))
    leather_light = make_mat("troll_leather_light", (0.38, 0.24, 0.15, 1.0))
    nose_red = make_mat("troll_nose_red", (0.55, 0.25, 0.22, 1.0))
    tooth_white = make_mat("troll_tooth_white", (0.90, 0.88, 0.80, 1.0))
    hair_black = make_mat("troll_hair_black", (0.05, 0.04, 0.04, 1.0))
    eye_yellow = make_mat("troll_eye_yellow", (1.0, 0.82, 0.15, 1.0), 0.3)

    root = make_root("voxel_troll_64x_scale_height_64px")
    armature = create_voxel_humanoid_armature(height_px, "VoxelHumanoidRig")
    armature.parent = root
    parts: list[bpy.types.Object] = []

    # 1. 头部 (Head)
    parts.append(cube_ref("head_main", (0.0, -1.0, 52.0), (12.0, 10.0, 12.0), height_px, skin_mid))
    parts.append(cube_ref("head_left_highlight", (-4.2, -4.8, 53.0), (2.0, 1.0, 8.0), height_px, skin_light))
    parts.append(cube_ref("head_right_shadow", (4.5, 3.5, 51.5), (2.0, 1.0, 8.5), height_px, skin_shadow))
    parts.append(cube_ref("head_nose", (0.0, -5.8, 51.5), (3.0, 4.0, 4.0), height_px, nose_red))
    parts.append(cube_ref("face_left_tusk", (-2.2, -5.4, 48.2), (1.2, 1.0, 2.5), height_px, tooth_white))
    parts.append(cube_ref("face_right_tusk", (2.2, -5.4, 48.2), (1.2, 1.0, 2.5), height_px, tooth_white))
    parts.append(cube_ref("head_left_ear_base", (-6.8, -0.2, 53.0), (3.0, 2.0, 2.5), height_px, skin_mid))
    parts.append(cube_ref("head_left_ear_tip", (-9.5, 0.8, 54.5), (2.5, 1.2, 1.5), height_px, skin_shadow))
    parts.append(cube_ref("head_right_ear_base", (6.8, -0.2, 53.0), (3.0, 2.0, 2.5), height_px, skin_mid))
    parts.append(cube_ref("head_right_ear_tip", (9.5, 0.8, 54.5), (2.5, 1.2, 1.5), height_px, skin_shadow))
    parts.append(cube_ref("eye_left", (-2.6, -5.2, 53.5), (1.8, 0.4, 1.5), height_px, eye_yellow))
    parts.append(cube_ref("eye_right", (2.6, -5.2, 53.5), (1.8, 0.4, 1.5), height_px, eye_yellow))
    parts.append(cube_ref("hair_mohawk", (0.0, 3.8, 55.0), (2.0, 4.0, 10.0), height_px, hair_black))

    # 2. 躯干 (Torso)
    parts.append(cube_ref("torso_main", (0.0, 1.0, 36.0), (17.0, 12.0, 19.0), height_px, skin_mid))
    parts.append(cube_ref("torso_hump", (0.0, 5.8, 41.0), (13.0, 4.0, 10.0), height_px, skin_shadow))
    parts.append(cube_ref("torso_left_highlight", (-6.2, -4.5, 37.0), (2.5, 1.2, 13.0), height_px, skin_light))
    parts.append(cube_ref("torso_right_shadow", (6.5, 4.5, 35.0), (2.5, 1.2, 13.0), height_px, skin_shadow))
    parts.append(cube_ref("torso_leather_strap_l", (-4.2, -4.8, 38.0), (2.2, 1.0, 15.0), height_px, leather))
    parts.append(cube_ref("torso_leather_strap_r", (4.2, -4.8, 38.0), (2.2, 1.0, 15.0), height_px, leather))

    # 3. 骨盆 (Pelvis)
    parts.append(cube_ref("pelvis_main", (0.0, 0.2, 23.0), (14.0, 9.0, 7.0), height_px, leather))
    parts.append(cube_ref("hip_cloth_front", (0.0, -4.4, 21.0), (10.0, 1.0, 8.0), height_px, leather_light))
    parts.append(cube_ref("hip_cloth_back", (0.0, 4.4, 21.0), (11.0, 1.0, 8.0), height_px, leather))

    # 4. 左臂
    parts.append(cube_ref("left_upper_arm_main", (-11.5, 1.0, 38.0), (6.0, 6.0, 13.0), height_px, skin_mid))
    parts.append(cube_ref("left_forearm_main", (-13.0, -0.2, 26.0), (5.0, 5.0, 12.0), height_px, skin_mid))
    parts.append(cube_ref("left_hand_claws", (-13.5, -2.8, 17.5), (5.5, 5.0, 5.0), height_px, skin_shadow))
    parts.append(cube_ref("left_shoulder_plate", (-11.8, 0.8, 44.0), (7.0, 7.0, 3.0), height_px, leather))

    # 5. 右臂
    parts.append(cube_ref("right_upper_arm_main", (11.5, 1.0, 38.0), (6.0, 6.0, 13.0), height_px, skin_mid))
    parts.append(cube_ref("right_forearm_main", (13.0, -0.2, 26.0), (5.0, 5.0, 12.0), height_px, skin_shadow))
    parts.append(cube_ref("right_hand_claws", (13.5, -2.8, 17.5), (5.5, 5.0, 5.0), height_px, skin_shadow))
    parts.append(cube_ref("right_shoulder_plate", (11.8, 0.8, 44.0), (7.0, 7.0, 3.0), height_px, leather))

    # 6. 左腿
    parts.append(cube_ref("left_thigh_main", (-4.2, 0.0, 13.0), (4.5, 4.5, 11.0), height_px, skin_mid))
    parts.append(cube_ref("left_shin_main", (-4.6, -0.4, 6.0), (4.0, 4.0, 9.0), height_px, skin_mid))
    parts.append(cube_ref("left_foot_main", (-4.8, -3.2, 1.5), (5.5, 7.5, 2.5), height_px, skin_shadow))

    # 7. 右腿
    parts.append(cube_ref("right_thigh_main", (4.2, 0.0, 13.0), (4.5, 4.5, 11.0), height_px, skin_shadow))
    parts.append(cube_ref("right_shin_main", (4.6, -0.4, 6.0), (4.0, 4.0, 9.0), height_px, skin_mid))
    parts.append(cube_ref("right_foot_main", (4.8, -3.2, 1.5), (5.5, 7.5, 2.5), height_px, skin_shadow))

    parent_humanoid_parts(parts, armature)
    return root


CREATURES = {
    "skeleton": {
        "builder": build_skeleton,
        "path": OUT_DIR / "voxel_skeleton_48px.glb",
        "target_px": (0, 0, 25),
        "preview_scale": 2.1,
        "front_scale": 2.1,
    },
    "rat": {
        "builder": build_rat,
        "path": OUT_DIR / "voxel_rat_12px.glb",
        "target_px": (0, 0, 8),
        "preview_scale": 0.95,
        "front_scale": 0.95,
    },
    "slime": {
        "builder": build_slime,
        "path": OUT_DIR / "voxel_slime_18px.glb",
        "target_px": (0, 0, 11),
        "preview_scale": 1.05,
        "front_scale": 1.05,
    },
    "necrolord": {
        "builder": build_necrolord,
        "path": OUT_DIR / "voxel_necrolord_80px.glb",
        "target_px": (0, 0, 42),
        "preview_scale": 3.25,
        "front_scale": 3.25,
    },
    "dragon": {
        "builder": build_dragon,
        "path": OUT_DIR / "voxel_dragon_256px.glb",
        "target_px": (0, 0, 226),
        "preview_scale": 38.0,
        "front_scale": 38.0,
    },
    "troll": {
        "builder": build_troll,
        "path": OUT_DIR / "voxel_troll_64x.glb",
        "target_px": (0, 0, 32),
        "preview_scale": 2.5,
        "front_scale": 2.5,
    },
}


def select_tree(root: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_root(root: bpy.types.Object, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    select_tree(root)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )


def add_lights_and_camera(target_px: tuple[float, float, float], scale: float) -> bpy.types.Object:
    target = Vector((px(target_px[0]), px(target_px[1]), px(target_px[2])))
    for name, loc, energy in [
        ("KeyLight", (0.0, -4.0, 3.2), 210),
        ("SideFill", (4.0, 1.5, 2.4), 90),
        ("TopFill", (-2.0, 2.5, 5.0), 70),
    ]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = 3.4
        direction = target - light.location
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.camera_add(location=(1.7, -4.0, 1.6))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    bpy.context.scene.camera = camera
    aim_camera(camera, (1.7, -4.0, 1.6), target, scale)
    return camera


def aim_camera(camera: bpy.types.Object, location: tuple[float, float, float], target: Vector, scale: float) -> None:
    camera.location = location
    camera.data.ortho_scale = scale
    direction = target - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def configure_render() -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 1000
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 64
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.render.film_transparent = True


def render_to(path: Path) -> None:
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def render_views(name: str, camera: bpy.types.Object, target_px: tuple[float, float, float], scale: float) -> None:
    target = Vector((px(target_px[0]), px(target_px[1]), px(target_px[2])))
    aim_camera(camera, (1.7, -4.0, 1.6), target, scale)
    render_to(PREVIEW_DIR / f"voxel_{name}_preview.png")
    aim_camera(camera, (0.0, -4.0, target.z), target, scale)
    render_to(PREVIEW_DIR / f"voxel_{name}_front.png")
    aim_camera(camera, (4.0, 0.0, target.z), target, scale)
    render_to(PREVIEW_DIR / f"voxel_{name}_side.png")
    aim_camera(camera, (0.0, 0.0, 5.0 if scale < 5.0 else 12.0), target, scale)
    render_to(PREVIEW_DIR / f"voxel_{name}_top.png")


def generate_one(name: str, spec: dict) -> None:
    reset_scene()
    root = spec["builder"]()
    export_root(root, spec["path"])
    camera = add_lights_and_camera(spec["target_px"], spec["preview_scale"])
    configure_render()
    render_views(name, camera, spec["target_px"], spec["front_scale"])
    print(f"Wrote {spec['path']}")


def main() -> None:
    target_names = list(CREATURES.keys())
    if len(sys.argv) > 1 and sys.argv[-1] in CREATURES:
        target_names = [sys.argv[-1]]
    for name in target_names:
        generate_one(name, CREATURES[name])
    print(f"Scale: 1m = 32px, PX = {PX}")
    print("Necrolord height: 80px = 2.5m")
    print("Dragon length target: 256px = 8m nose-to-tail")


if __name__ == "__main__":
    main()



