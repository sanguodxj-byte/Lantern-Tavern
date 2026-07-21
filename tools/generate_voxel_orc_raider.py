from __future__ import annotations

"""
兽人掠夺者（orc_raider）体素模型重做 — weaponless 身体。

比例尺：1m = 32px（docs/17）。高度 48px（中型人形，约 1.5m）。
细节标准对齐 minotaur / goblin：mid/light/shadow 分层、面部特征、护甲语义部件。
武器（斧）为独立 GLB：assets/meshes/weapons/weapons_voxel_axe.glb，由 EquipmentComponent 挂载。
部件命名前缀与本模型的骨骼绑定契约对齐，由当前生成器独立导出 static/rig。

运行：
  D:/123/blender/blender.exe --background --python tools/generate_voxel_orc_raider.py
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

# 兽人掠夺者：粗壮中型人形，略高于哥布林（42px 体高），标准 48px 人形槽位
MODEL_ID = "orc_raider"
ORC_HEIGHT_PX = 48.0
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_orc_raider_48px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_orc_raider_48px_rig.glb"
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
    roughness: float = 0.88,
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
            bsdf.inputs["Metallic"].default_value = 0.0
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
                "brow_",
                "nose_",
                "eye_",
                "mouth_",
                "tusk_",
                "ear_",
                "hair_",
                "scar_",
            ],
        ),
        "Torso": parts_with_prefix(
            parts,
            [
                "torso_",
                "chest_",
                "shoulder_pad",
                "pauldron_",
                "belt",
            ],
        ),
        "Pelvis": parts_with_prefix(parts, ["pelvis_", "hip_", "loin_"]),
        "UpperArm.L": parts_with_prefix(parts, ["left_upper_arm", "left_arm_highlight"]),
        "LowerArm.L": parts_with_prefix(parts, ["left_forearm", "left_bracer"]),
        "Hand.L": parts_with_prefix(parts, ["left_hand"]),
        "UpperArm.R": parts_with_prefix(parts, ["right_upper_arm", "right_arm_shadow"]),
        "LowerArm.R": parts_with_prefix(parts, ["right_forearm", "right_bracer"]),
        "Hand.R": parts_with_prefix(parts, ["right_hand"]),
        "UpperLeg.L": parts_with_prefix(parts, ["left_thigh"]),
        "LowerLeg.L": parts_with_prefix(parts, ["left_shin", "left_greave"]),
        "Foot.L": parts_with_prefix(parts, ["left_foot", "left_toe"]),
        "UpperLeg.R": parts_with_prefix(parts, ["right_thigh"]),
        "LowerLeg.R": parts_with_prefix(parts, ["right_shin", "right_greave"]),
        "Foot.R": parts_with_prefix(parts, ["right_foot", "right_toe"]),
    }
    parent_parts_by_bone(parts_by_bone, armature)


def build_orc_raider() -> bpy.types.Object:
    height_px = ORC_HEIGHT_PX

    # 橄榄绿皮肤 + 锈铁护甲 + 骨色獠牙
    skin_mid = make_mat("orc_skin_mid", (0.28, 0.48, 0.20, 1.0))
    skin_light = make_mat("orc_skin_highlight", (0.44, 0.66, 0.32, 1.0))
    skin_shadow = make_mat("orc_skin_shadow", (0.14, 0.28, 0.10, 1.0))
    leather = make_mat("orc_leather", (0.22, 0.12, 0.06, 1.0))
    leather_light = make_mat("orc_leather_light", (0.40, 0.24, 0.12, 1.0))
    iron = make_mat("orc_iron", (0.42, 0.44, 0.46, 1.0), roughness=0.72)
    iron_dark = make_mat("orc_iron_dark", (0.22, 0.24, 0.26, 1.0), roughness=0.78)
    rust = make_mat("orc_rust", (0.48, 0.22, 0.10, 1.0))
    bone = make_mat("orc_bone", (0.90, 0.86, 0.70, 1.0))
    eye = make_mat("orc_eye_amber", (1.0, 0.78, 0.12, 1.0), 0.45)
    pupil = make_mat("orc_pupil", (0.04, 0.02, 0.01, 1.0))
    cloth = make_mat("orc_cloth_dark", (0.16, 0.12, 0.10, 1.0))

    root = make_root("voxel_orc_raider_48px")
    armature = create_voxel_humanoid_armature(height_px, "VoxelHumanoidRig")
    armature.parent = root
    parts: list[bpy.types.Object] = []

    # ------------------------------------------------------------------
    # 1. 头：宽下颌、粗眉、獠牙、尖耳
    # ------------------------------------------------------------------
    parts.append(cube_ref("head_main", (0.0, 0.0, 36.5), (11.0, 9.0, 10.0), height_px, skin_mid))
    parts.append(cube_ref("head_left_highlight", (-4.0, -4.4, 37.2), (2.2, 1.0, 7.0), height_px, skin_light))
    parts.append(cube_ref("head_right_shadow", (4.2, 3.8, 36.5), (2.2, 1.0, 7.5), height_px, skin_shadow))
    parts.append(cube_ref("head_jaw", (0.0, -1.5, 32.2), (10.0, 7.0, 3.5), height_px, skin_shadow))
    parts.append(cube_ref("brow_ridge", (0.0, -4.6, 39.0), (9.5, 1.2, 2.2), height_px, skin_shadow))
    parts.append(cube_ref("nose_bridge", (0.0, -5.0, 36.0), (2.8, 1.6, 2.6), height_px, skin_shadow))
    parts.append(cube_ref("nose_tip", (0.0, -5.8, 34.8), (2.2, 1.2, 1.8), height_px, skin_mid))

    parts.append(cube_ref("eye_left", (-2.6, -4.75, 37.4), (2.0, 0.4, 1.5), height_px, eye))
    parts.append(cube_ref("eye_right", (2.6, -4.75, 37.4), (2.0, 0.4, 1.5), height_px, eye))
    parts.append(cube_ref("eye_left_pupil", (-2.6, -4.95, 37.4), (0.7, 0.2, 1.0), height_px, pupil))
    parts.append(cube_ref("eye_right_pupil", (2.6, -4.95, 37.4), (0.7, 0.2, 1.0), height_px, pupil))

    parts.append(cube_ref("mouth_line", (0.0, -4.9, 33.0), (5.5, 0.35, 1.2), height_px, pupil))
    # 上翘獠牙（面接触下颌前缘）
    parts.append(cube_ref("tusk_left", (-2.0, -5.2, 31.6), (1.2, 1.0, 2.4), height_px, bone))
    parts.append(cube_ref("tusk_right", (2.0, -5.2, 31.6), (1.2, 1.0, 2.4), height_px, bone))
    parts.append(cube_ref("tusk_left_tip", (-2.0, -5.5, 33.0), (0.8, 0.7, 1.2), height_px, bone))
    parts.append(cube_ref("tusk_right_tip", (2.0, -5.5, 33.0), (0.8, 0.7, 1.2), height_px, bone))

    # 尖耳（面接触头侧）
    parts.append(cube_ref("ear_left_base", (-7.0, 0.2, 37.0), (3.5, 2.2, 3.5), height_px, skin_mid))
    parts.append(cube_ref("ear_left_tip", (-9.2, 0.0, 38.0), (2.0, 1.6, 2.2), height_px, skin_shadow))
    parts.append(cube_ref("ear_right_base", (7.0, 0.2, 37.0), (3.5, 2.2, 3.5), height_px, skin_mid))
    parts.append(cube_ref("ear_right_tip", (9.2, 0.0, 38.0), (2.0, 1.6, 2.2), height_px, skin_shadow))

    # 顶发/鬃毛
    parts.append(cube_ref("hair_top", (0.0, 0.5, 42.0), (8.0, 7.0, 2.5), height_px, cloth))
    parts.append(cube_ref("hair_spike_mid", (0.0, -0.5, 44.0), (3.0, 3.5, 2.5), height_px, cloth))
    parts.append(cube_ref("hair_spike_left", (-2.5, 0.5, 43.5), (2.2, 2.8, 2.0), height_px, pupil))
    parts.append(cube_ref("hair_spike_right", (2.5, 0.2, 43.2), (2.0, 2.6, 1.8), height_px, pupil))

    # 面疤（左颊）
    parts.append(cube_ref("scar_cheek", (-3.5, -4.7, 35.2), (0.5, 0.3, 2.8), height_px, rust))

    # ------------------------------------------------------------------
    # 2. 躯干：厚胸甲 + 肩甲 + 皮带
    # ------------------------------------------------------------------
    parts.append(cube_ref("torso_main", (0.0, 0.3, 24.5), (14.0, 8.5, 14.0), height_px, skin_mid))
    parts.append(cube_ref("torso_left_highlight", (-5.2, -4.0, 25.5), (2.4, 1.0, 10.0), height_px, skin_light))
    parts.append(cube_ref("torso_right_shadow", (5.4, 3.6, 24.5), (2.2, 1.0, 10.5), height_px, skin_shadow))
    parts.append(cube_ref("chest_plate", (0.0, -4.6, 26.5), (11.0, 1.4, 9.0), height_px, iron))
    parts.append(cube_ref("chest_plate_ridge", (0.0, -5.2, 28.0), (8.0, 0.6, 2.0), height_px, iron_dark))
    parts.append(cube_ref("chest_strap_l", (-3.5, -4.9, 24.0), (2.0, 0.7, 10.0), height_px, leather))
    parts.append(cube_ref("chest_strap_r", (3.5, -4.9, 24.0), (2.0, 0.7, 10.0), height_px, leather))
    parts.append(cube_ref("pauldron_left", (-8.5, 0.5, 30.5), (5.5, 5.5, 4.0), height_px, iron_dark))
    parts.append(cube_ref("pauldron_right", (8.5, 0.5, 30.5), (5.5, 5.5, 4.0), height_px, iron))
    parts.append(cube_ref("pauldron_left_spike", (-9.5, -1.0, 32.5), (2.0, 2.0, 2.5), height_px, rust))
    parts.append(cube_ref("pauldron_right_spike", (9.5, -1.0, 32.5), (2.0, 2.0, 2.5), height_px, rust))
    parts.append(cube_ref("belt_main", (0.0, -0.2, 17.0), (14.5, 8.8, 2.2), height_px, leather))
    parts.append(cube_ref("belt_buckle", (0.0, -4.7, 17.0), (2.6, 0.8, 1.6), height_px, iron))

    # ------------------------------------------------------------------
    # 3. 骨盆 / 腰布
    # ------------------------------------------------------------------
    parts.append(cube_ref("pelvis_main", (0.0, 0.0, 14.0), (12.0, 7.5, 5.0), height_px, leather))
    parts.append(cube_ref("hip_cloth_front", (0.0, -3.8, 12.0), (8.0, 1.0, 6.0), height_px, cloth))
    parts.append(cube_ref("hip_cloth_back", (0.0, 3.6, 12.0), (9.0, 1.0, 6.0), height_px, leather_light))
    parts.append(cube_ref("loin_tassel_l", (-3.0, -4.0, 9.5), (2.0, 0.8, 3.0), height_px, leather_light))
    parts.append(cube_ref("loin_tassel_r", (3.0, -4.0, 9.5), (2.0, 0.8, 3.0), height_px, leather_light))

    # ------------------------------------------------------------------
    # 4. 手臂（粗壮 + 护腕）
    # ------------------------------------------------------------------
    for side, sx in [("left", -1), ("right", 1)]:
        arm_mat = skin_light if side == "left" else skin_mid
        parts.append(
            cube_ref(
                f"{side}_upper_arm_main",
                (sx * 10.5, 0.4, 24.5),
                (5.0, 5.0, 11.0),
                height_px,
                arm_mat,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_forearm_main",
                (sx * 11.5, -0.4, 16.0),
                (4.5, 4.5, 9.0),
                height_px,
                skin_mid if side == "left" else skin_shadow,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_bracer",
                (sx * 11.5, -0.2, 17.5),
                (5.0, 5.0, 3.5),
                height_px,
                iron_dark if side == "left" else iron,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_hand_fist",
                (sx * 11.8, -1.8, 10.5),
                (4.5, 4.2, 3.5),
                height_px,
                skin_shadow,
            )
        )
    parts.append(cube_ref("left_arm_highlight", (-12.0, -2.4, 24.0), (1.0, 0.8, 8.0), height_px, skin_light))
    parts.append(cube_ref("right_arm_shadow", (12.0, 2.4, 24.0), (1.0, 0.8, 8.0), height_px, skin_shadow))
    # weaponless: axe is separate GLB (weapons_voxel_axe.glb)

    # ------------------------------------------------------------------
    # 5. 腿 + 靴
    # ------------------------------------------------------------------
    for side, sx in [("left", -1), ("right", 1)]:
        leg_mat = skin_mid if side == "left" else skin_shadow
        parts.append(
            cube_ref(
                f"{side}_thigh_main",
                (sx * 3.5, 0.0, 9.5),
                (5.0, 5.0, 10.0),
                height_px,
                leg_mat,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_shin_main",
                (sx * 3.6, -0.2, 3.8),
                (4.2, 4.2, 7.5),
                height_px,
                skin_mid,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_greave",
                (sx * 3.6, -0.2, 5.0),
                (4.8, 4.8, 3.0),
                height_px,
                iron_dark if side == "left" else leather,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_foot_main",
                (sx * 3.8, -2.2, 1.0),
                (5.2, 7.0, 2.2),
                height_px,
                leather,
            )
        )
        parts.append(
            cube_ref(
                f"{side}_toe_claw",
                (sx * 3.8, -5.2, 1.0),
                (3.5, 2.0, 1.4),
                height_px,
                bone,
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
    render_to(PREVIEW_DIR / "voxel_orc_raider_preview.png")

    aim_camera(camera, (0.0, -3.8, target.z), target, scale)
    render_to(PREVIEW_DIR / "voxel_orc_raider_front.png")

    aim_camera(camera, (3.8, 0.0, target.z), target, scale)
    render_to(PREVIEW_DIR / "voxel_orc_raider_side.png")

    aim_camera(camera, (0.0, 0.0, 4.8), target, scale)
    render_to(PREVIEW_DIR / "voxel_orc_raider_top.png")


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root = build_orc_raider()
    root.location.z += px(GROUND_OFFSET_PX)

    target_px = (0.0, 0.0, 26.0)
    preview_scale = 2.6

    export_glb(root)
    camera = add_lights_and_camera(target_px, preview_scale)
    configure_render()
    render_previews(camera, target_px, preview_scale)

    print(f"Wrote {OUT_GLB}")
    print(f"Scale: 1m = 32px, PX = {PX}")
    print(f"Orc height: {ORC_HEIGHT_PX}px = {px(ORC_HEIGHT_PX):.4f}m")
    print("Semantic parts: tusks, pauldrons, greaves (weaponless body)")


if __name__ == "__main__":
    main()
