from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(Path(__file__).resolve().parent))
from voxel_humanoid_rig import PX, create_voxel_humanoid_armature, parent_parts_by_bone

GOBLIN_HEIGHT_PX = 42.0
OUT_GLB = ROOT / "assets" / "meshes" / "characters" / "voxel_goblin_32px.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def m(px_value: float) -> float:
    return px_value * PX


def make_mat(name: str, color: tuple[float, float, float, float], roughness: float = 0.88) -> bpy.types.Material:
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
    return mat


def cube_px(
    name: str,
    loc_px: tuple[float, float, float],
    size_px: tuple[float, float, float],
    mat: bpy.types.Material,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(m(loc_px[0]), m(loc_px[1]), m(loc_px[2])))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (m(size_px[0]), m(size_px[1]), m(size_px[2]))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def build_goblin() -> bpy.types.Object:
    skin_mid = make_mat("goblin_skin_mid", (0.34, 0.58, 0.22, 1.0))
    skin_light = make_mat("goblin_skin_highlight", (0.55, 0.78, 0.34, 1.0))
    skin_shadow = make_mat("goblin_skin_shadow", (0.17, 0.34, 0.13, 1.0))
    ear_inner = make_mat("goblin_ear_inner", (0.48, 0.28, 0.20, 1.0))
    leather = make_mat("goblin_leather_armor", (0.30, 0.16, 0.08, 1.0))
    leather_light = make_mat("goblin_leather_highlight", (0.48, 0.28, 0.13, 1.0))
    cloth = make_mat("goblin_red_cloth", (0.48, 0.06, 0.05, 1.0))
    cloth_shadow = make_mat("goblin_red_cloth_shadow", (0.24, 0.03, 0.03, 1.0))
    eye = make_mat("goblin_eye_yellow", (1.0, 0.86, 0.18, 1.0))
    pupil = make_mat("goblin_pupil", (0.03, 0.02, 0.01, 1.0))
    tooth = make_mat("goblin_tooth", (0.92, 0.86, 0.66, 1.0))
    nail = make_mat("goblin_claw_bone", (0.82, 0.74, 0.55, 1.0))

    root = bpy.data.objects.new("voxel_goblin_32px_scale_height_42px", None)
    bpy.context.collection.objects.link(root)
    parts: list[bpy.types.Object] = []

    # Feet and legs, all values are pixel units where 32px = 1m.
    parts.append(cube_px("left_foot_shadow", (-3.5, -1.0, 1.5), (5.0, 7.0, 3.0), skin_shadow))
    parts.append(cube_px("right_foot_shadow", (3.5, -1.0, 1.5), (5.0, 7.0, 3.0), skin_shadow))
    parts.append(cube_px("left_leg_mid", (-2.8, 0.0, 8.0), (3.2, 4.0, 11.0), skin_mid))
    parts.append(cube_px("right_leg_mid", (2.8, 0.0, 8.0), (3.2, 4.0, 11.0), skin_mid))
    parts.append(cube_px("left_leg_highlight", (-3.8, -2.1, 8.8), (1.0, 0.8, 8.5), skin_light))
    parts.append(cube_px("right_leg_shadow", (3.8, 2.1, 8.8), (1.0, 0.8, 8.5), skin_shadow))
    parts.append(cube_px("left_toe_claw", (-4.8, -4.8, 2.2), (1.0, 1.5, 1.0), nail))
    parts.append(cube_px("right_toe_claw", (4.8, -4.8, 2.2), (1.0, 1.5, 1.0), nail))

    parts.append(cube_px("hip_cloth", (0.0, -0.2, 14.0), (10.0, 5.5, 4.0), cloth))
    parts.append(cube_px("hip_cloth_shadow", (2.8, 2.7, 13.8), (3.8, 1.0, 3.5), cloth_shadow))
    parts.append(cube_px("belt", (0.0, -2.9, 16.6), (11.0, 1.2, 2.0), leather))
    parts.append(cube_px("belt_buckle", (0.0, -3.6, 16.7), (2.0, 0.8, 1.4), nail))

    parts.append(cube_px("torso_leather", (0.0, 0.0, 23.0), (11.0, 6.5, 13.0), leather))
    parts.append(cube_px("torso_skin_neck", (0.0, -0.8, 30.2), (5.2, 4.2, 3.0), skin_mid))
    parts.append(cube_px("torso_left_highlight", (-3.8, -3.4, 24.5), (2.0, 0.9, 9.0), leather_light))
    parts.append(cube_px("torso_right_shadow", (4.2, 3.2, 24.0), (1.8, 1.0, 9.5), leather))
    parts.append(cube_px("chest_patch", (-1.4, -3.6, 25.5), (3.0, 0.8, 4.0), cloth_shadow))

    parts.append(cube_px("left_upper_arm", (-8.2, 0.0, 24.5), (4.0, 4.0, 10.0), skin_mid))
    parts.append(cube_px("right_upper_arm", (8.2, 0.0, 24.5), (4.0, 4.0, 10.0), skin_mid))
    parts.append(cube_px("left_forearm", (-9.6, -0.6, 17.0), (3.6, 3.6, 8.5), skin_mid))
    parts.append(cube_px("right_forearm", (9.6, -0.6, 17.0), (3.6, 3.6, 8.5), skin_shadow))
    parts.append(cube_px("left_hand_claws", (-9.8, -2.8, 12.4), (4.2, 1.2, 2.0), nail))
    parts.append(cube_px("right_hand_claws", (9.8, -2.8, 12.4), (4.2, 1.2, 2.0), nail))
    parts.append(cube_px("left_arm_highlight", (-10.1, -2.2, 22.5), (0.9, 0.8, 9.0), skin_light))
    parts.append(cube_px("right_arm_shadow", (10.1, 2.2, 22.5), (0.9, 0.8, 9.0), skin_shadow))

    parts.append(cube_px("head_main", (0.0, 0.0, 36.0), (11.0, 8.0, 10.0), skin_mid))
    parts.append(cube_px("head_left_highlight", (-3.9, -4.2, 36.8), (2.0, 1.0, 7.0), skin_light))
    parts.append(cube_px("head_right_shadow", (4.2, 3.8, 36.5), (2.0, 1.0, 7.5), skin_shadow))
    parts.append(cube_px("brow", (0.0, -4.35, 38.0), (9.0, 0.45, 2.0), skin_shadow))
    parts.append(cube_px("nose", (0.0, -4.65, 35.4), (2.6, 1.2, 2.4), skin_shadow))
    parts.append(cube_px("left_eye", (-2.5, -4.35, 37.2), (1.8, 0.35, 1.5), eye))
    parts.append(cube_px("right_eye", (2.5, -4.35, 37.2), (1.8, 0.35, 1.5), eye))
    parts.append(cube_px("left_pupil", (-2.5, -4.58, 37.2), (0.6, 0.18, 1.0), pupil))
    parts.append(cube_px("right_pupil", (2.5, -4.58, 37.2), (0.6, 0.18, 1.0), pupil))
    parts.append(cube_px("mouth_shadow", (0.0, -4.52, 33.2), (5.8, 0.25, 1.2), pupil))
    parts.append(cube_px("left_tusk", (-1.8, -4.66, 32.4), (0.9, 0.25, 1.4), tooth))
    parts.append(cube_px("right_tusk", (1.8, -4.66, 32.4), (0.9, 0.25, 1.4), tooth))

    parts.append(cube_px("left_ear_base", (-7.6, 0.0, 36.4), (5.0, 2.6, 4.0), skin_mid))
    parts.append(cube_px("left_ear_tip", (-10.6, 0.0, 36.8), (2.6, 2.0, 2.6), skin_shadow))
    parts.append(cube_px("left_ear_inner", (-7.7, -1.55, 36.4), (3.0, 0.7, 1.8), ear_inner))
    parts.append(cube_px("right_ear_base", (7.6, 0.0, 36.4), (5.0, 2.6, 4.0), skin_mid))
    parts.append(cube_px("right_ear_tip", (10.6, 0.0, 36.8), (2.6, 2.0, 2.6), skin_shadow))
    parts.append(cube_px("right_ear_inner", (7.7, -1.55, 36.4), (3.0, 0.7, 1.8), ear_inner))

    parts.append(cube_px("top_hair_shadow", (0.0, 0.2, 42.0), (8.0, 6.0, 2.0), pupil))
    parts.append(cube_px("hair_spike_left", (-2.8, -0.5, 44.0), (2.4, 3.4, 2.4), pupil))
    parts.append(cube_px("hair_spike_right", (2.4, 0.1, 43.6), (2.0, 3.0, 2.0), pupil))

    armature = create_voxel_humanoid_armature(GOBLIN_HEIGHT_PX, "VoxelHumanoidRig")
    armature.parent = root
    _parent_goblin_parts_to_rig(parts, armature)
    return root


def _parts_named(parts: list[bpy.types.Object], names: list[str]) -> list[bpy.types.Object]:
    return [part for part in parts if part.name in names]


def _parts_with_prefix(parts: list[bpy.types.Object], prefixes: list[str]) -> list[bpy.types.Object]:
    return [part for part in parts if any(part.name.startswith(prefix) for prefix in prefixes)]


def _parent_goblin_parts_to_rig(parts: list[bpy.types.Object], armature: bpy.types.Object) -> None:
    parts_by_bone = {
        "Head": _parts_with_prefix(parts, ["head_", "brow", "nose", "left_eye", "right_eye", "left_pupil", "right_pupil", "mouth_", "left_tusk", "right_tusk", "left_ear", "right_ear", "top_hair", "hair_"]),
        "Torso": _parts_with_prefix(parts, ["torso_", "chest_", "belt", "belt_buckle"]),
        "Pelvis": _parts_with_prefix(parts, ["hip_"]),
        "UpperArm.L": _parts_with_prefix(parts, ["left_upper_arm", "left_arm_highlight"]),
        "LowerArm.L": _parts_with_prefix(parts, ["left_forearm"]),
        "Hand.L": _parts_with_prefix(parts, ["left_hand"]),
        "UpperArm.R": _parts_with_prefix(parts, ["right_upper_arm", "right_arm_shadow"]),
        "LowerArm.R": _parts_with_prefix(parts, ["right_forearm"]),
        "Hand.R": _parts_with_prefix(parts, ["right_hand"]),
        "UpperLeg.L": _parts_with_prefix(parts, ["left_leg"]),
        "LowerLeg.L": [],
        "Foot.L": _parts_with_prefix(parts, ["left_foot", "left_toe"]),
        "UpperLeg.R": _parts_with_prefix(parts, ["right_leg"]),
        "LowerLeg.R": [],
        "Foot.R": _parts_with_prefix(parts, ["right_foot", "right_toe"]),
    }
    parent_parts_by_bone(parts_by_bone, armature)


def export_glb(root: bpy.types.Object) -> None:
    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )


def add_lights_and_camera() -> bpy.types.Object:
    for name, loc, energy in [
        ("KeyLight", (0.0, -3.6, 2.3), 190),
        ("SideFill", (3.2, 0.8, 2.0), 90),
        ("TopFill", (-1.2, 1.6, 3.5), 60),
    ]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = 2.8
        direction = Vector((0.0, 0.0, m(23.0))) - light.location
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    bpy.ops.object.camera_add(location=(1.5, -3.6, 1.55))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.9
    bpy.context.scene.camera = camera
    aim_camera(camera, (1.5, -3.6, 1.55), (0.0, 0.0, m(23.0)), 1.9)
    return camera


def aim_camera(camera: bpy.types.Object, location: tuple[float, float, float], target: tuple[float, float, float], scale: float) -> None:
    camera.location = location
    camera.data.ortho_scale = scale
    direction = Vector(target) - camera.location
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


def render_previews(root: bpy.types.Object, camera: bpy.types.Object) -> None:
    configure_render()
    root.rotation_euler = (0.0, 0.0, 0.0)
    aim_camera(camera, (1.5, -3.6, 1.55), (0.0, 0.0, m(23.0)), 1.9)
    render_to(PREVIEW_DIR / "voxel_goblin_32px_preview.png")

    aim_camera(camera, (0.0, -3.6, m(23.0)), (0.0, 0.0, m(23.0)), 1.9)
    render_to(PREVIEW_DIR / "voxel_goblin_32px_front.png")

    aim_camera(camera, (3.6, 0.0, m(23.0)), (0.0, 0.0, m(23.0)), 1.9)
    render_to(PREVIEW_DIR / "voxel_goblin_32px_side.png")

    aim_camera(camera, (0.0, 0.0, 3.6), (0.0, 0.0, m(23.0)), 1.9)
    render_to(PREVIEW_DIR / "voxel_goblin_32px_top.png")


def main() -> None:
    reset_scene()
    root = build_goblin()
    camera = add_lights_and_camera()
    export_glb(root)
    render_previews(root, camera)
    print(f"Wrote {OUT_GLB}")
    print(f"Scale: 1m = 32px, PX = {PX}")
    print(f"Nominal body height: 42px = {m(42.0):.4f}m, hair silhouette reaches 45.2px")


if __name__ == "__main__":
    main()
