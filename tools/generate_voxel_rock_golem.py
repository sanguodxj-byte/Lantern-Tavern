from __future__ import annotations

"""
岩石魔像体素模型生成器。

比例尺：1m = 32px（docs/17）。高度 80px（与 necrolord 同级的大型构装体）。
遵循 VoxelHumanoidRig 绑定约定，部件命名前缀与 parent_humanoid_parts 对齐。

运行：
  D:/123/blender/blender.exe --background --python tools/generate_voxel_rock_golem.py
"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from voxel_humanoid_rig import PX, REFERENCE_HEIGHT_PX, create_voxel_humanoid_armature, parent_parts_by_bone
from voxel_single_model_cli import reject_target_override

# 岩石魔像：高大块状构装体，略高于牛头人（72px），对齐死灵领主量级
MODEL_ID = "rock_golem"
GOLEM_HEIGHT_PX = 80.0
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_rock_golem_80px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_rock_golem_80px_rig.glb"
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
    roughness: float = 0.92,
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
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    return root


def parts_with_prefix(parts: list[bpy.types.Object], prefixes: list[str]) -> list[bpy.types.Object]:
    return [part for part in parts if any(part.name.startswith(prefix) for prefix in prefixes)]


def parent_humanoid_parts(parts: list[bpy.types.Object], armature: bpy.types.Object) -> None:
    parts_by_bone = {
        "Head": parts_with_prefix(
            parts,
            [
                "head_",
                "skull_",
                "jaw_",
                "eye_",
                "face_",
                "core_face",
                "moss_head",
                "stone_head",
                "brow_",
            ],
        ),
        "Torso": parts_with_prefix(
            parts,
            [
                "torso_",
                "chest_",
                "spine_",
                "shoulder_",
                "core_chest",
                "moss_torso",
                "plate_",
                "rivet_torso",
            ],
        ),
        "Pelvis": parts_with_prefix(parts, ["pelvis_", "hip_", "belt_", "moss_hip"]),
        "UpperArm.L": parts_with_prefix(parts, ["left_upper_arm", "left_shoulder"]),
        "LowerArm.L": parts_with_prefix(parts, ["left_forearm"]),
        "Hand.L": parts_with_prefix(parts, ["left_hand"]),
        "UpperArm.R": parts_with_prefix(parts, ["right_upper_arm", "right_shoulder"]),
        "LowerArm.R": parts_with_prefix(parts, ["right_forearm"]),
        "Hand.R": parts_with_prefix(parts, ["right_hand"]),
        "UpperLeg.L": parts_with_prefix(parts, ["left_thigh", "left_upper_leg"]),
        "LowerLeg.L": parts_with_prefix(parts, ["left_shin", "left_lower_leg"]),
        "Foot.L": parts_with_prefix(parts, ["left_foot", "left_stone_foot"]),
        "UpperLeg.R": parts_with_prefix(parts, ["right_thigh", "right_upper_leg"]),
        "LowerLeg.R": parts_with_prefix(parts, ["right_shin", "right_lower_leg"]),
        "Foot.R": parts_with_prefix(parts, ["right_foot", "right_stone_foot"]),
    }
    parent_parts_by_bone(parts_by_bone, armature)


def build_rock_golem() -> bpy.types.Object:
    height_px = GOLEM_HEIGHT_PX

    # 灰岩 / 苔藓 / 熔岩核心 / 铆钉
    stone_mid = make_mat("golem_stone_mid", (0.42, 0.40, 0.38, 1.0), roughness=0.95)
    stone_light = make_mat("golem_stone_light", (0.58, 0.56, 0.52, 1.0), roughness=0.90)
    stone_shadow = make_mat("golem_stone_shadow", (0.24, 0.22, 0.20, 1.0), roughness=0.96)
    stone_dark = make_mat("golem_stone_dark", (0.16, 0.15, 0.14, 1.0), roughness=0.97)
    moss = make_mat("golem_moss", (0.22, 0.40, 0.18, 1.0), roughness=0.98)
    moss_dark = make_mat("golem_moss_dark", (0.12, 0.26, 0.10, 1.0), roughness=0.98)
    core = make_mat("golem_core_glow", (0.95, 0.42, 0.10, 1.0), emission=1.6, roughness=0.35)
    core_deep = make_mat("golem_core_deep", (0.70, 0.18, 0.05, 1.0), emission=0.8, roughness=0.40)
    rivet = make_mat("golem_rivet_iron", (0.35, 0.34, 0.32, 1.0), roughness=0.55, metallic=0.65)
    crack = make_mat("golem_crack_shadow", (0.08, 0.07, 0.06, 1.0), roughness=0.99)

    root = make_root("voxel_rock_golem_80px")
    armature = create_voxel_humanoid_armature(height_px, "VoxelHumanoidRig")
    armature.parent = root
    parts: list[bpy.types.Object] = []

    # ------------------------------------------------------------------
    # 1. 石块头（立方、厚眉、发光眼缝）
    # ------------------------------------------------------------------
    # 主头骨：与颈/躯干上沿面接触（torso 上沿 ~31.5）
    parts.append(cube_ref("head_main", (0.0, 0.0, 36.5), (12.0, 11.0, 10.0), height_px, stone_mid))
    parts.append(cube_ref("head_left_highlight", (-4.8, -5.6, 37.5), (2.4, 0.8, 7.0), height_px, stone_light))
    parts.append(cube_ref("head_right_shadow", (5.0, 4.5, 36.0), (2.2, 0.8, 7.5), height_px, stone_shadow))
    parts.append(cube_ref("brow_ridge", (0.0, -5.7, 39.5), (11.0, 1.0, 2.5), height_px, stone_dark))
    parts.append(cube_ref("jaw_block", (0.0, -4.5, 32.2), (10.0, 6.0, 3.0), height_px, stone_shadow))
    # 眼缝（贴在 head 前表面）
    parts.append(cube_ref("eye_left_socket", (-3.2, -5.8, 37.2), (3.0, 0.6, 1.6), height_px, crack))
    parts.append(cube_ref("eye_right_socket", (3.2, -5.8, 37.2), (3.0, 0.6, 1.6), height_px, crack))
    parts.append(cube_ref("eye_left", (-3.2, -6.1, 37.2), (2.2, 0.4, 1.0), height_px, core))
    parts.append(cube_ref("eye_right", (3.2, -6.1, 37.2), (2.2, 0.4, 1.0), height_px, core))
    # 头顶石冠 / 苔藓（贴合 head 顶面）
    parts.append(cube_ref("head_crown_slab", (0.0, 0.5, 41.8), (10.0, 8.0, 2.0), height_px, stone_light))
    parts.append(cube_ref("moss_head_patch", (-3.0, -3.5, 41.0), (4.0, 3.0, 1.2), height_px, moss))
    parts.append(cube_ref("moss_head_patch_r", (3.5, 2.0, 40.5), (3.5, 2.5, 1.0), height_px, moss_dark))
    # 面甲裂缝
    parts.append(cube_ref("face_crack_v", (0.0, -5.75, 35.5), (0.8, 0.5, 5.0), height_px, crack))

    # ------------------------------------------------------------------
    # 2. 躯干：叠层石板 + 核心腔
    # ------------------------------------------------------------------
    parts.append(cube_ref("torso_main", (0.0, 0.5, 24.0), (18.0, 12.0, 16.0), height_px, stone_mid))
    parts.append(cube_ref("torso_left_highlight", (-7.2, -5.8, 25.0), (3.0, 1.0, 12.0), height_px, stone_light))
    parts.append(cube_ref("torso_right_shadow", (7.5, 5.0, 23.5), (3.0, 1.0, 12.0), height_px, stone_shadow))
    # 前胸石板（贴 torso 前表面）
    parts.append(cube_ref("chest_plate_upper", (0.0, -6.3, 28.0), (12.0, 1.2, 6.0), height_px, stone_light))
    parts.append(cube_ref("chest_plate_lower", (0.0, -6.3, 22.5), (11.0, 1.2, 5.0), height_px, stone_shadow))
    # 核心腔与发光核（贴在胸甲缝中，向前略突出但仍贴合）
    parts.append(cube_ref("core_chest_socket", (0.0, -6.9, 25.5), (5.0, 0.8, 5.0), height_px, stone_dark))
    parts.append(cube_ref("core_chest_glow", (0.0, -7.4, 25.5), (3.5, 0.6, 3.5), height_px, core))
    parts.append(cube_ref("core_chest_inner", (0.0, -7.7, 25.5), (1.8, 0.4, 1.8), height_px, core_deep))
    # 肩横梁
    parts.append(cube_ref("shoulder_bar", (0.0, 0.0, 31.5), (20.0, 8.0, 3.5), height_px, stone_shadow))
    parts.append(cube_ref("shoulder_left_pad", (-10.5, 0.5, 31.0), (6.0, 7.0, 5.0), height_px, stone_mid))
    parts.append(cube_ref("shoulder_right_pad", (10.5, 0.5, 31.0), (6.0, 7.0, 5.0), height_px, stone_mid))
    # 铆钉（奇数像素宽度）
    parts.append(cube_ref("rivet_torso_l", (-5.0, -6.9, 28.5), (1.0, 0.5, 1.0), height_px, rivet))
    parts.append(cube_ref("rivet_torso_r", (5.0, -6.9, 28.5), (1.0, 0.5, 1.0), height_px, rivet))
    parts.append(cube_ref("rivet_torso_c", (0.0, -6.9, 22.0), (1.0, 0.5, 1.0), height_px, rivet))
    # 苔藓
    parts.append(cube_ref("moss_torso_l", (-7.5, -5.5, 20.0), (4.0, 2.0, 3.0), height_px, moss))
    parts.append(cube_ref("moss_torso_r", (6.5, 4.5, 27.0), (3.5, 2.0, 4.0), height_px, moss_dark))
    # 躯干裂缝
    parts.append(cube_ref("torso_crack_l", (-2.5, -6.35, 24.5), (0.7, 0.5, 8.0), height_px, crack))

    # ------------------------------------------------------------------
    # 3. 骨盆 / 腰部石环
    # ------------------------------------------------------------------
    parts.append(cube_ref("pelvis_main", (0.0, 0.0, 14.0), (15.0, 10.0, 6.0), height_px, stone_shadow))
    parts.append(cube_ref("hip_plate_front", (0.0, -5.2, 13.5), (11.0, 1.0, 5.0), height_px, stone_mid))
    parts.append(cube_ref("hip_plate_back", (0.0, 5.0, 13.5), (12.0, 1.0, 5.0), height_px, stone_dark))
    parts.append(cube_ref("belt_ring", (0.0, 0.0, 16.5), (16.0, 10.5, 2.0), height_px, stone_light))
    parts.append(cube_ref("moss_hip_front", (2.0, -5.5, 12.0), (4.0, 1.0, 2.5), height_px, moss))

    # ------------------------------------------------------------------
    # 4. 手臂：粗石柱 + 巨拳
    # ------------------------------------------------------------------
    for side, sx in [("left", -1), ("right", 1)]:
        arm_mid = stone_light if side == "left" else stone_mid
        arm_dark = stone_mid if side == "left" else stone_shadow
        # 肩垫已在 Torso；上臂贴肩外侧
        parts.append(
            cube_ref(
                f"{side}_upper_arm_main",
                (sx * 12.5, 0.5, 24.0),
                (6.5, 6.5, 12.0),
                height_px,
                arm_mid,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_upper_arm_plate",
                (sx * 12.5, -3.5, 25.0),
                (5.0, 1.0, 8.0),
                height_px,
                stone_light if side == "right" else stone_shadow,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_forearm_main",
                (sx * 13.2, -0.5, 15.0),
                (6.0, 6.0, 10.0),
                height_px,
                arm_dark,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_forearm_band",
                (sx * 13.2, -0.5, 17.5),
                (6.5, 6.5, 2.0),
                height_px,
                rivet,
            )
        )
        # 巨拳
        parts.append(
            cube_ref(
                f"{side}_hand_fist",
                (sx * 13.5, -2.0, 8.5),
                (6.5, 6.0, 5.0),
                height_px,
                stone_shadow,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_hand_knuckle",
                (sx * 13.5, -5.0, 9.0),
                (5.5, 1.5, 3.5),
                height_px,
                stone_dark,
            )
        )

    # ------------------------------------------------------------------
    # 5. 腿：石柱 + 宽足
    # ------------------------------------------------------------------
    for side, sx in [("left", -1), ("right", 1)]:
        leg_mat = stone_mid if side == "left" else stone_shadow
        parts.append(
            cube_ref(
                f"{side}_thigh_main",
                (sx * 4.2, 0.0, 9.5),
                (6.0, 6.5, 10.0),
                height_px,
                leg_mat,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_shin_main",
                (sx * 4.4, -0.2, 4.0),
                (5.5, 5.5, 8.0),
                height_px,
                stone_mid,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_shin_plate",
                (sx * 4.4, -3.1, 4.5),
                (4.5, 1.0, 5.0),
                height_px,
                stone_light,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_foot_main",
                (sx * 4.5, -2.5, 1.0),
                (6.5, 8.0, 2.5),
                height_px,
                stone_shadow,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_stone_foot_toe",
                (sx * 4.5, -6.0, 0.9),
                (5.0, 2.5, 2.0),
                height_px,
                stone_dark,
            )
        )

    parent_humanoid_parts(parts, armature)
    return root


def select_tree(root: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_glb(root: bpy.types.Object) -> None:
    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    select_tree(root)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )


def add_lights_and_camera(target_px: tuple[float, float, float], scale: float) -> bpy.types.Object:
    target = Vector((px(target_px[0]), px(target_px[1]), px(target_px[2])))
    for name, loc, energy in [
        ("KeyLight", (0.0, -4.5, 3.6), 240),
        ("SideFill", (4.5, 1.8, 2.8), 100),
        ("TopFill", (-2.4, 2.8, 5.4), 80),
    ]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = 3.8
        direction = target - light.location
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    bpy.ops.object.camera_add(location=(2.0, -4.6, 1.9))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    bpy.context.scene.camera = camera
    aim_camera(camera, (2.0, -4.6, 1.9), target, scale)
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
    aim_camera(camera, (2.0, -4.6, 1.9), target, scale)
    render_to(PREVIEW_DIR / "voxel_rock_golem_preview.png")

    aim_camera(camera, (0.0, -4.6, target.z), target, scale)
    render_to(PREVIEW_DIR / "voxel_rock_golem_front.png")

    aim_camera(camera, (4.6, 0.0, target.z), target, scale)
    render_to(PREVIEW_DIR / "voxel_rock_golem_side.png")

    aim_camera(camera, (0.0, 0.0, 6.2), target, scale * 0.95)
    render_to(PREVIEW_DIR / "voxel_rock_golem_top.png")


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root = build_rock_golem()
    root.location.z += px(GROUND_OFFSET_PX)

    target_px = (0.0, 0.0, 42.0)
    preview_scale = 4.6

    export_glb(root)
    camera = add_lights_and_camera(target_px, preview_scale)
    configure_render()
    render_previews(camera, target_px, preview_scale)

    print(f"Wrote {OUT_GLB}")
    print(f"Scale: 1m = 32px, PX = {PX}")
    print(f"Rock golem height: {GOLEM_HEIGHT_PX}px = {px(GOLEM_HEIGHT_PX):.4f}m")


if __name__ == "__main__":
    main()
