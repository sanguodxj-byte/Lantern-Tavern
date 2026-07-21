from __future__ import annotations

"""
卓尔剑士（drow_blade）48px 体素模型 S 级重做 — 旗舰级作者化体素美术。

比例尺：1m = 32px（docs/17）。高度 48px（标准中型人形，1.5m）。
参照项目 S 级 rock_golem 质量标准：
- 簇状体素块（clustered voxel masses）、不规则阶梯轮廓（stepped/broken contours）。
- 绝无光滑平铺大盒子；80% 体量由精雕形体承担。
- 丰满身份锚点：三阶修长精灵耳、深眶血红发光瞳、前额与三段背飘银发束、
  菱形黑钢胸甲加紫晶符文核、双重刀锋肩甲、三段刺客燕尾半下摆、刺客脚尖靴。
- 遵从面接触约束，完全通过 assert_parts_voxel_assembly_valid。

运行：
  "D:/123/blender/blender.exe" --background --python tools/generate_voxel_drow_blade.py
"""

import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from voxel_humanoid_rig import PX, REFERENCE_HEIGHT_PX, create_voxel_humanoid_armature, parent_parts_by_bone
from voxel_overlap_guard import assert_parts_voxel_assembly_valid
from voxel_single_model_cli import reject_target_override

MODEL_ID = "drow_blade"
DROW_HEIGHT_PX = 48.0
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_drow_blade_48px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_drow_blade_48px_rig.glb"
OUT_GLB = STATIC_OUTPUT
PREVIEW_DIR = ROOT / "reports" / "characters_preview"
GROUND_OFFSET_PX = 1.0


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def px(value: float) -> float:
    return value * PX


def make_mat(
    name: str,
    color: tuple[float, float, float, float],
    emission: float = 0.0,
    roughness: float = 0.85,
    metallic: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = color
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = roughness
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metallic
        if emission > 0.0:
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = color
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def cube(
    name: str,
    loc_px: tuple[float, float, float],
    size_px: tuple[float, float, float],
    mat: bpy.types.Material,
) -> bpy.types.Object:
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
    empty = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(empty)
    return empty


def build_drow_blade() -> bpy.types.Object:
    height_px = DROW_HEIGHT_PX
    root = make_root(f"voxel_{MODEL_ID}")
    armature = create_voxel_humanoid_armature(height_px, f"VoxelHumanoidRig_{MODEL_ID}")
    armature.parent = root

    # ------------------------------------------------------------------
    # S级旗舰材质层次 (Multi-ramp Palette)
    # ------------------------------------------------------------------
    # 皮肤明暗阶
    skin_light = make_mat("mat_skin_light", (0.34, 0.30, 0.40, 1.0), roughness=0.80)
    skin_mid = make_mat("mat_skin_mid", (0.24, 0.20, 0.30, 1.0), roughness=0.85)
    skin_shadow = make_mat("mat_skin_shadow", (0.16, 0.13, 0.22, 1.0), roughness=0.90)
    skin_dark = make_mat("mat_skin_dark", (0.10, 0.08, 0.14, 1.0), roughness=0.95)

    # 银发色阶
    hair_light = make_mat("mat_hair_light", (0.95, 0.94, 0.98, 1.0), roughness=0.70)
    hair_mid = make_mat("mat_hair_mid", (0.84, 0.83, 0.89, 1.0), roughness=0.75)
    hair_shadow = make_mat("mat_hair_shadow", (0.68, 0.66, 0.74, 1.0), roughness=0.80)
    hair_dark = make_mat("mat_hair_dark", (0.50, 0.48, 0.56, 1.0), roughness=0.85)

    # 血红瞳色阶
    eye_dark = make_mat("mat_eye_dark", (0.35, 0.05, 0.10, 1.0), roughness=0.90)
    eye_red = make_mat("mat_eye_red", (0.92, 0.15, 0.28, 1.0), roughness=0.40)
    eye_glow = make_mat("mat_eye_glow", (1.00, 0.35, 0.50, 1.0), emission=3.2, roughness=0.20)

    # 护甲与皮具色阶
    steel_dark = make_mat("mat_steel_dark", (0.15, 0.16, 0.20, 1.0), roughness=0.40, metallic=0.75)
    steel_light = make_mat("mat_steel_light", (0.28, 0.30, 0.38, 1.0), roughness=0.35, metallic=0.85)
    leather = make_mat("mat_leather", (0.16, 0.13, 0.12, 1.0), roughness=0.88)
    leather_light = make_mat("mat_leather_light", (0.26, 0.21, 0.19, 1.0), roughness=0.82)
    purple_trim = make_mat("mat_purple_trim", (0.46, 0.16, 0.62, 1.0), roughness=0.60, emission=0.3)
    purple_dark = make_mat("mat_purple_dark", (0.26, 0.08, 0.36, 1.0), roughness=0.80)
    gem_rune = make_mat("mat_gem_rune", (0.65, 0.18, 0.85, 1.0), emission=2.8, roughness=0.15)

    parts: list[bpy.types.Object] = []
    parts_by_bone: dict[str, list[bpy.types.Object]] = {}

    def reg(bone: str, part: bpy.types.Object) -> None:
        part.parent = root
        parts.append(part)
        parts_by_bone.setdefault(bone, []).append(part)

    # ------------------------------------------------------------------
    # 1. 头部集群 (Head, Face, Ears, Hair)
    # ------------------------------------------------------------------
    # 头部主轮廓簇 (Head Core & Sculpted Facial Features)
    reg("Head", cube_ref("head_main", (0.0, 0.2, 36.2), (5.8, 5.2, 7.0), height_px, skin_mid))
    reg("Head", cube_ref("head_cheek_l", (-3.2, -0.4, 35.8), (0.6, 3.2, 4.5), height_px, skin_light))
    reg("Head", cube_ref("head_cheek_r", (3.2, -0.4, 35.8), (0.6, 3.2, 4.5), height_px, skin_shadow))
    # chin: Z [32.4, 34.0], 顶面接 face_front 底面 Z=34.0
    reg("Head", cube_ref("jaw_chin", (0.0, -2.7, 33.2), (3.6, 0.6, 1.6), height_px, skin_dark))
    # face_front: Y [-3.0, -2.4], Z [34.0, 38.0]
    reg("Head", cube_ref("face_front", (0.0, -2.7, 36.0), (4.8, 0.6, 4.0), height_px, skin_light))

    # 深阶眉骨与血红双眼（贴在 face_front 前壁 Y=-3.0）
    reg("Head", cube_ref("brow_ridge", (0.0, -3.3, 37.8), (5.2, 0.6, 1.4), height_px, skin_shadow))
    reg("Head", cube_ref("eye_left_socket", (-1.5, -3.3, 36.4), (1.8, 0.6, 1.4), height_px, eye_dark))
    reg("Head", cube_ref("eye_right_socket", (1.5, -3.3, 36.4), (1.8, 0.6, 1.4), height_px, eye_dark))
    reg("Head", cube_ref("eye_left", (-1.5, -3.7, 36.4), (1.2, 0.2, 1.0), height_px, eye_red))
    reg("Head", cube_ref("eye_right", (1.5, -3.7, 36.4), (1.2, 0.2, 1.0), height_px, eye_red))
    reg("Head", cube_ref("eye_pupil_l", (-1.5, -3.9, 36.4), (0.6, 0.2, 0.6), height_px, eye_glow))
    reg("Head", cube_ref("eye_pupil_r", (1.5, -3.9, 36.4), (0.6, 0.2, 0.6), height_px, eye_glow))

    # 卓尔修长三阶尖耳 (Ear Root 贴在 head_cheek 外侧 X=±3.5)
    reg("Head", cube_ref("ear_left_base", (-3.8, 0.4, 36.5), (0.6, 1.8, 2.2), height_px, skin_mid))
    reg("Head", cube_ref("ear_left_mid", (-5.0, 1.0, 37.2), (1.8, 1.4, 1.8), height_px, skin_light))
    reg("Head", cube_ref("ear_left_tip", (-6.6, 1.6, 38.0), (1.4, 1.0, 1.2), height_px, skin_light))

    reg("Head", cube_ref("ear_right_base", (3.8, 0.4, 36.5), (0.6, 1.8, 2.2), height_px, skin_mid))
    reg("Head", cube_ref("ear_right_mid", (5.0, 1.0, 37.2), (1.8, 1.4, 1.8), height_px, skin_shadow))
    reg("Head", cube_ref("ear_right_tip", (6.6, 1.6, 38.0), (1.4, 1.0, 1.2), height_px, skin_shadow))

    # 飘逸阶梯银发簇
    reg("Head", cube_ref("hair_top", (0.0, 0.2, 40.4), (6.2, 5.6, 1.4), height_px, hair_light))
    reg("Head", cube_ref("hair_spikes_top", (0.0, -0.6, 41.6), (4.0, 3.6, 1.0), height_px, hair_light))
    reg("Head", cube_ref("hair_bangs", (0.0, -2.7, 39.2), (5.4, 0.6, 1.6), height_px, hair_light))
    reg("Head", cube_ref("hair_side_lock_l", (-3.8, -1.8, 38.0), (0.6, 1.4, 3.5), height_px, hair_mid))
    reg("Head", cube_ref("hair_side_lock_r", (3.8, -1.8, 38.0), (0.6, 1.4, 3.5), height_px, hair_mid))

    reg("Head", cube_ref("hair_back_strand_top", (0.0, 3.1, 37.0), (5.0, 0.6, 5.4), height_px, hair_mid))
    reg("Head", cube_ref("hair_back_strand_mid", (0.0, 3.1, 30.5), (4.2, 0.6, 7.6), height_px, hair_shadow))
    reg("Head", cube_ref("hair_back_strand_low", (0.0, 3.1, 22.5), (3.4, 0.6, 8.4), height_px, hair_dark))

    # ------------------------------------------------------------------
    # 2. 颈部与刺客围巾高领 (Neck & Assassin Collar)
    # ------------------------------------------------------------------
    reg("Neck", cube_ref("neck_main", (0.0, 0.0, 31.5), (3.2, 2.8, 2.4), height_px, skin_shadow))
    reg("Neck", cube_ref("collar_wrap_f", (0.0, -1.7, 31.5), (4.2, 0.6, 2.0), height_px, purple_dark))
    reg("Neck", cube_ref("collar_wrap_b", (0.0, 1.7, 31.5), (4.2, 0.6, 2.0), height_px, purple_trim))

    # ------------------------------------------------------------------
    # 3. 躯干、菱形胸甲与双刀锋肩甲 (Torso, Diamond Armor & Blade Pauldrons)
    # ------------------------------------------------------------------
    reg("Torso", cube_ref("torso_main", (0.0, 0.0, 24.4), (8.0, 4.8, 11.8), height_px, skin_mid))
    reg("Torso", cube_ref("torso_flank_l", (-4.3, 0.0, 24.4), (0.6, 3.4, 8.0), height_px, skin_light))
    reg("Torso", cube_ref("torso_flank_r", (4.3, 0.0, 24.4), (0.6, 3.4, 8.0), height_px, skin_shadow))

    # 菱形精钢胸甲 + 符文核
    reg("Torso", cube_ref("chest_plate", (0.0, -2.7, 26.5), (7.0, 0.6, 6.0), height_px, steel_dark))
    reg("Torso", cube_ref("chest_gem_socket", (0.0, -3.2, 26.5), (2.2, 0.4, 2.4), height_px, purple_trim))
    reg("Torso", cube_ref("chest_gem_glow", (0.0, -3.5, 26.5), (1.2, 0.2, 1.4), height_px, gem_rune))
    reg("Torso", cube_ref("abs_plate", (0.0, -2.7, 20.8), (5.6, 0.6, 3.4), height_px, leather))

    # 不对称刀锋级双重肩甲 (Double-blade Pauldrons)
    reg("Torso", cube_ref("pauldron_left", (-5.3, 0.0, 28.5), (1.4, 3.6, 3.4), height_px, steel_dark))
    reg("Torso", cube_ref("pauldron_blade_l", (-6.7, 0.0, 29.2), (1.4, 2.8, 2.6), height_px, steel_light))
    reg("Torso", cube_ref("pauldron_spike_l", (-7.7, 0.0, 30.0), (0.6, 1.6, 1.4), height_px, purple_trim))

    reg("Torso", cube_ref("pauldron_right", (5.3, 0.0, 28.5), (1.4, 3.6, 3.4), height_px, steel_dark))
    reg("Torso", cube_ref("pauldron_blade_r", (6.7, 0.0, 29.2), (1.4, 2.8, 2.6), height_px, steel_light))
    reg("Torso", cube_ref("pauldron_spike_r", (7.7, 0.0, 30.0), (0.6, 1.6, 1.4), height_px, purple_trim))

    # ------------------------------------------------------------------
    # 4. 骨盆、腰带与刺客燕尾半下摆 (Pelvis, Belt & Tailcoat Slits)
    # ------------------------------------------------------------------
    reg("Pelvis", cube_ref("pelvis_main", (0.0, 0.0, 15.0), (7.6, 4.8, 6.0), height_px, leather))
    reg("Pelvis", cube_ref("belt_main", (0.0, 0.0, 18.25), (8.4, 5.4, 0.5), height_px, leather_light))
    reg("Pelvis", cube_ref("belt_buckle", (0.0, -2.9, 18.25), (2.2, 0.5, 0.5), height_px, purple_trim))

    # 三段阶梯后下摆 (Stepped Tailcoat Flaps)
    reg("Pelvis", cube_ref("tailcoat_front_l", (-2.2, -2.7, 11.5), (2.6, 0.6, 5.0), height_px, purple_dark))
    reg("Pelvis", cube_ref("tailcoat_front_r", (2.2, -2.7, 11.5), (2.6, 0.6, 5.0), height_px, purple_dark))
    reg("Pelvis", cube_ref("tailcoat_back_top", (0.0, 2.7, 13.5), (6.8, 0.6, 4.0), height_px, purple_trim))
    reg("Pelvis", cube_ref("tailcoat_back_mid", (0.0, 2.7, 9.0), (5.6, 0.6, 5.0), height_px, purple_dark))
    reg("Pelvis", cube_ref("tailcoat_back_tip", (0.0, 2.7, 4.5), (4.0, 0.6, 4.0), height_px, leather))

    # ------------------------------------------------------------------
    # 5. 修长双臂与多重手甲 (Slender Arms & Segmented Bracers)
    # ------------------------------------------------------------------
    # 左臂 (sx = -1)
    reg("UpperArm.L", cube_ref("left_upper_arm", (-5.3, 0.0, 23.5), (1.4, 2.6, 6.6), height_px, skin_light))
    reg("UpperArm.L", cube_ref("left_deltoid_pad", (-6.3, 0.0, 25.0), (0.6, 2.2, 3.0), height_px, steel_dark))
    reg("LowerArm.L", cube_ref("left_forearm", (-5.3, -0.2, 18.8), (1.4, 2.4, 2.8), height_px, skin_mid))
    reg("LowerArm.L", cube_ref("left_bracer", (-5.3, -0.2, 16.0), (1.8, 2.8, 2.8), height_px, steel_dark))
    reg("LowerArm.L", cube_ref("left_bracer_gem", (-6.3, -0.2, 16.0), (0.4, 1.2, 1.4), height_px, purple_trim))
    reg("Hand.L", cube_ref("left_hand", (-5.3, -0.8, 13.5), (1.4, 2.2, 2.2), height_px, skin_shadow))
    reg("Hand.L", cube_ref("left_knuckles", (-5.3, -2.0, 13.5), (1.2, 0.2, 1.4), height_px, steel_light))

    # 右臂 (sx = 1)
    reg("UpperArm.R", cube_ref("right_upper_arm", (5.3, 0.0, 23.5), (1.4, 2.6, 6.6), height_px, skin_mid))
    reg("UpperArm.R", cube_ref("right_deltoid_pad", (6.3, 0.0, 25.0), (0.6, 2.2, 3.0), height_px, steel_dark))
    reg("LowerArm.R", cube_ref("right_forearm", (5.3, -0.2, 18.8), (1.4, 2.4, 2.8), height_px, skin_mid))
    reg("LowerArm.R", cube_ref("right_bracer", (5.3, -0.2, 16.0), (1.8, 2.8, 2.8), height_px, steel_dark))
    reg("LowerArm.R", cube_ref("right_bracer_gem", (6.3, -0.2, 16.0), (0.4, 1.2, 1.4), height_px, purple_trim))
    reg("Hand.R", cube_ref("right_hand", (5.3, -0.8, 13.5), (1.4, 2.2, 2.2), height_px, skin_shadow))
    reg("Hand.R", cube_ref("right_knuckles", (5.3, -2.0, 13.5), (1.2, 0.2, 1.4), height_px, steel_light))

    # ------------------------------------------------------------------
    # 6. 细长腿部与刀刃膝甲/尖头脚靴 (Legs, Knee Blades & Pointed Boots)
    # ------------------------------------------------------------------
    # 左腿
    reg("UpperLeg.L", cube_ref("left_thigh", (-2.2, 0.0, 9.5), (2.6, 3.0, 5.0), height_px, skin_mid))
    reg("LowerLeg.L", cube_ref("left_knee_blade", (-2.2, -1.7, 7.0), (2.2, 0.4, 2.0), height_px, steel_light))
    reg("LowerLeg.L", cube_ref("left_shin", (-2.2, -0.1, 5.5), (2.4, 2.6, 3.0), height_px, leather))
    reg("LowerLeg.L", cube_ref("left_greave", (-2.2, -0.1, 3.0), (2.8, 3.0, 2.0), height_px, steel_dark))
    reg("Foot.L", cube_ref("left_foot", (-2.2, -1.2, 1.0), (2.6, 4.4, 2.0), height_px, leather))
    reg("Foot.L", cube_ref("left_boot_tip", (-2.2, -3.7, 1.0), (2.0, 0.6, 1.2), height_px, steel_dark))

    # 右腿
    reg("UpperLeg.R", cube_ref("right_thigh", (2.2, 0.0, 9.5), (2.6, 3.0, 5.0), height_px, skin_shadow))
    reg("LowerLeg.R", cube_ref("right_knee_blade", (2.2, -1.7, 7.0), (2.2, 0.4, 2.0), height_px, steel_light))
    reg("LowerLeg.R", cube_ref("right_shin", (2.2, -0.1, 5.5), (2.4, 2.6, 3.0), height_px, leather))
    reg("LowerLeg.R", cube_ref("right_greave", (2.2, -0.1, 3.0), (2.8, 3.0, 2.0), height_px, steel_dark))
    reg("Foot.R", cube_ref("right_foot", (2.2, -1.2, 1.0), (2.6, 4.4, 2.0), height_px, leather))
    reg("Foot.R", cube_ref("right_boot_tip", (2.2, -3.7, 1.0), (2.0, 0.6, 1.2), height_px, steel_dark))

    # 严格检验：纯面接触，禁止三轴正体积重叠
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)

    # 绑定骨骼
    parent_parts_by_bone(parts_by_bone, armature)

    return root


def select_tree(root: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_glb(root: bpy.types.Object) -> None:
    STATIC_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    select_tree(root)

    # 1. 导出 static GLB
    bpy.ops.export_scene.gltf(
        filepath=str(STATIC_OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )

    # 2. 导出 rig GLB
    bpy.ops.export_scene.gltf(
        filepath=str(RIG_OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
    )


def add_lights_and_camera(target_px: tuple[float, float, float], scale: float) -> bpy.types.Object:
    target = Vector((px(target_px[0]), px(target_px[1]), px(target_px[2])))
    for name, loc, energy in [
        ("KeyLight", (0.0, -3.8, 3.0), 200),
        ("SideFill", (3.8, 1.4, 2.4), 90),
        ("TopFill", (-2.0, 2.4, 4.6), 70),
    ]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = 3.2
        direction = target - light.location
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    bpy.ops.object.camera_add(location=(1.6, -3.8, 1.5))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    bpy.context.scene.camera = camera
    aim_camera(camera, (1.6, -3.8, 1.5), target, scale)
    return camera


def aim_camera(
    camera: bpy.types.Object,
    location: tuple[float, float, float],
    target: Vector,
    scale: float,
) -> None:
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


def render_previews(camera: bpy.types.Object, target_px: tuple[float, float, float], scale: float) -> None:
    target = Vector((px(target_px[0]), px(target_px[1]), px(target_px[2])))
    aim_camera(camera, (1.6, -3.8, 1.5), target, scale)
    render_to(PREVIEW_DIR / f"voxel_{MODEL_ID}_render_preview.png")

    aim_camera(camera, (0.0, -3.8, target.z), target, scale)
    render_to(PREVIEW_DIR / f"voxel_{MODEL_ID}_render_front.png")

    aim_camera(camera, (3.8, 0.0, target.z), target, scale)
    render_to(PREVIEW_DIR / f"voxel_{MODEL_ID}_render_side.png")

    aim_camera(camera, (0.0, 0.0, 4.8), target, scale)
    render_to(PREVIEW_DIR / f"voxel_{MODEL_ID}_render_top.png")


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root = build_drow_blade()
    root.location.z += px(GROUND_OFFSET_PX)

    target_px = (0.0, 0.0, 24.0)
    preview_scale = 2.4

    export_glb(root)
    camera = add_lights_and_camera(target_px, preview_scale)
    configure_render()
    render_previews(camera, target_px, preview_scale)

    print(f"Wrote {STATIC_OUTPUT}")
    print(f"Wrote {RIG_OUTPUT}")
    print(f"Scale: 1m = 32px, PX = {PX}")
    print(f"Drow height: {DROW_HEIGHT_PX}px = {px(DROW_HEIGHT_PX):.4f}m")


if __name__ == "__main__":
    main()
