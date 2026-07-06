from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "models" / "materials"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
SAMPLES = {
    "voxel_glowcap": OUT_DIR / "materials_voxel_glowcap.glb",
    "voxel_bone_shard_sample": OUT_DIR / "materials_voxel_bone_shard_sample.glb",
}


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def make_mat(name: str, color: tuple[float, float, float, float], emission: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = color
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.9
        if emission > 0.0:
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = color
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def cube(name: str, loc: tuple[float, float, float], size: tuple[float, float, float], mat: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def parent_parts(root: bpy.types.Object, parts: list[bpy.types.Object]) -> None:
    for part in parts:
        part.parent = root


def make_root(name: str) -> bpy.types.Object:
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    return root


def build_glowcap() -> bpy.types.Object:
    cap_mid = make_mat("glowcap_cap_mid", (0.36, 0.11, 0.42, 1.0))
    cap_light = make_mat("glowcap_cap_highlight", (0.65, 0.22, 0.78, 1.0))
    cap_shadow = make_mat("glowcap_cap_shadow", (0.18, 0.05, 0.24, 1.0))
    stem_mid = make_mat("glowcap_stem_mid", (0.66, 0.56, 0.42, 1.0))
    stem_shadow = make_mat("glowcap_stem_shadow", (0.38, 0.30, 0.22, 1.0))
    glow = make_mat("glowcap_spore_glow", (0.32, 1.0, 0.72, 1.0), 1.4)

    root = make_root("voxel_glowcap")
    parts: list[bpy.types.Object] = []

    parts.append(cube("stem_base_shadow", (0.025, 0.0, 0.12), (0.14, 0.14, 0.24), stem_shadow))
    parts.append(cube("stem_base_light", (-0.035, 0.035, 0.16), (0.09, 0.07, 0.28), stem_mid))
    parts.append(cube("stem_neck", (0.0, 0.0, 0.36), (0.10, 0.10, 0.22), stem_mid))

    parts.append(cube("cap_lower_shadow", (0.04, 0.0, 0.51), (0.42, 0.34, 0.12), cap_shadow))
    parts.append(cube("cap_mid", (0.0, 0.0, 0.61), (0.56, 0.42, 0.18), cap_mid))
    parts.append(cube("cap_crown", (-0.03, 0.0, 0.75), (0.36, 0.30, 0.12), cap_mid))
    parts.append(cube("cap_highlight_patch", (-0.15, 0.09, 0.83), (0.12, 0.10, 0.035), cap_light))
    parts.append(cube("cap_small_highlight", (0.06, 0.12, 0.81), (0.07, 0.07, 0.035), cap_light))

    for i, (x, y) in enumerate([(-0.16, -0.13), (0.0, -0.16), (0.16, -0.11), (-0.06, 0.16), (0.19, 0.12)]):
        parts.append(cube(f"spore_dot_{i}", (x, y, 0.515), (0.055, 0.030, 0.035), glow))

    parent_parts(root, parts)
    return root


def build_bone_shard() -> bpy.types.Object:
    bone_mid = make_mat("bone_mid", (0.76, 0.69, 0.55, 1.0))
    bone_light = make_mat("bone_highlight", (0.95, 0.88, 0.68, 1.0))
    bone_shadow = make_mat("bone_shadow", (0.42, 0.34, 0.24, 1.0))
    marrow = make_mat("bone_marrow_dark", (0.23, 0.12, 0.10, 1.0))
    red = make_mat("bone_old_blood", (0.42, 0.04, 0.03, 1.0))

    root = make_root("voxel_bone_shard_sample")
    parts: list[bpy.types.Object] = []

    rows = [
        ("base", 0.18, 0.36, 0.20),
        ("lower", 0.39, 0.31, 0.18),
        ("mid", 0.59, 0.24, 0.15),
        ("upper", 0.75, 0.17, 0.11),
        ("tip", 0.88, 0.08, 0.06),
    ]
    for name, z, height, width in rows:
        parts.append(cube(f"bone_{name}_light", (-width * 0.22, 0.0, z), (width * 0.42, 0.13, height), bone_light))
        parts.append(cube(f"bone_{name}_mid", (width * 0.08, 0.0, z), (width * 0.38, 0.13, height), bone_mid))
        parts.append(cube(f"bone_{name}_shadow", (width * 0.32, 0.0, z), (width * 0.24, 0.13, height), bone_shadow))

    parts.append(cube("marrow_hollow", (0.02, 0.071, 0.20), (0.12, 0.020, 0.10), marrow))
    parts.append(cube("diagonal_crack_low", (0.05, 0.072, 0.48), (0.10, 0.018, 0.035), bone_shadow))
    parts[-1].rotation_euler.z = math.radians(18)
    parts.append(cube("diagonal_crack_high", (-0.03, 0.072, 0.70), (0.08, 0.018, 0.030), bone_shadow))
    parts[-1].rotation_euler.z = math.radians(-18)
    parts.append(cube("old_blood_stain", (-0.07, 0.073, 0.33), (0.055, 0.018, 0.060), red))

    parent_parts(root, parts)
    return root


def select_root_tree(root: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_sample(root: bpy.types.Object, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    select_root_tree(root)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )


def add_lights_and_camera() -> bpy.types.Object:
    for name, loc, energy in [
        ("KeyLight", (0.0, -3.0, 3.0), 180),
        ("SideFill", (3.0, 1.5, 2.0), 80),
        ("GlowFill", (-2.5, 1.0, 1.0), 40),
    ]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = 2.8
        direction = Vector((0.0, 0.0, 0.45)) - light.location
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    bpy.ops.object.camera_add(location=(1.8, -3.4, 1.45))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.15
    bpy.context.scene.camera = camera
    aim_camera(camera, (1.8, -3.4, 1.45), (0.0, 0.0, 0.45), 2.15)
    return camera


def aim_camera(camera: bpy.types.Object, location: tuple[float, float, float], target: tuple[float, float, float], scale: float) -> None:
    camera.location = location
    camera.data.ortho_scale = scale
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def configure_render() -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 64
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.render.film_transparent = True


def render_to(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def set_tree_render_visible(root: bpy.types.Object, visible: bool) -> None:
    root.hide_render = not visible
    for child in root.children_recursive:
        child.hide_render = not visible


def render_preview_set(glowcap: bpy.types.Object, bone: bpy.types.Object, camera: bpy.types.Object) -> None:
    configure_render()
    glowcap.location.x = -0.55
    bone.location.x = 0.55
    aim_camera(camera, (1.8, -3.4, 1.45), (0.0, 0.0, 0.45), 2.15)
    render_to(PREVIEW_DIR / "voxel_material_samples_preview.png")

    for root, name in [(glowcap, "voxel_glowcap"), (bone, "voxel_bone_shard_sample")]:
        other_roots = [glowcap, bone]
        for other in other_roots:
            set_tree_render_visible(other, other == root)
        root.location.x = 0.0
        aim_camera(camera, (0.0, -3.0, 0.48), (0.0, 0.0, 0.48), 1.35)
        render_to(PREVIEW_DIR / f"{name}_front.png")
        aim_camera(camera, (3.0, 0.0, 0.48), (0.0, 0.0, 0.48), 1.35)
        render_to(PREVIEW_DIR / f"{name}_side.png")
        aim_camera(camera, (0.0, 0.0, 3.0), (0.0, 0.0, 0.48), 1.35)
        render_to(PREVIEW_DIR / f"{name}_top.png")
        root.location.x = -0.55 if root == glowcap else 0.55
    for root in [glowcap, bone]:
        set_tree_render_visible(root, True)


def main() -> None:
    reset_scene()
    glowcap = build_glowcap()
    bone = build_bone_shard()
    camera = add_lights_and_camera()
    export_sample(glowcap, SAMPLES["voxel_glowcap"])
    export_sample(bone, SAMPLES["voxel_bone_shard_sample"])
    render_preview_set(glowcap, bone, camera)
    for path in [*SAMPLES.values(), PREVIEW_DIR / "voxel_material_samples_preview.png"]:
        print(f"Wrote {path}")


if __name__ == "__main__":
    main()
