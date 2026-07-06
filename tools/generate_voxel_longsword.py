from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_longsword.glb"
OUT_PREVIEW = ROOT / "reports" / "weapons_preview" / "voxel_longsword_preview.png"
OUT_FRONT = ROOT / "reports" / "weapons_preview" / "voxel_longsword_front.png"
OUT_SIDE = ROOT / "reports" / "weapons_preview" / "voxel_longsword_side.png"
OUT_TOP = ROOT / "reports" / "weapons_preview" / "voxel_longsword_top.png"


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def make_mat(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = next((node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = color
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.82
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def cube(
    name: str,
    location: tuple[float, float, float],
    size: tuple[float, float, float],
    mat: bpy.types.Material,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def build_sword() -> bpy.types.Object:
    steel = make_mat("voxel_steel_mid", (0.62, 0.69, 0.73, 1.0))
    steel_light = make_mat("voxel_steel_highlight", (0.86, 0.95, 0.98, 1.0))
    steel_glint = make_mat("voxel_steel_glint", (1.0, 1.0, 0.92, 1.0))
    steel_shadow = make_mat("voxel_steel_shadow", (0.36, 0.42, 0.47, 1.0))
    brass = make_mat("voxel_old_brass", (0.82, 0.58, 0.22, 1.0))
    brass_light = make_mat("voxel_old_brass_highlight", (1.0, 0.78, 0.32, 1.0))
    brass_shadow = make_mat("voxel_old_brass_shadow", (0.50, 0.32, 0.10, 1.0))
    leather = make_mat("voxel_dark_leather", (0.22, 0.11, 0.06, 1.0))
    leather_light = make_mat("voxel_dark_leather_highlight", (0.42, 0.22, 0.12, 1.0))
    ruby = make_mat("voxel_ruby", (0.55, 0.04, 0.08, 1.0))

    root = bpy.data.objects.new("weapons_voxel_longsword", None)
    bpy.context.collection.objects.link(root)

    parts: list[bpy.types.Object] = []

    # Blade extends along negative Z so it matches the combat forward direction.
    # Each row uses adjacent color blocks instead of smooth gradients: highlight, mid-tone, shadow.
    blade_rows = [
        ("base", -0.35, 0.40, 0.22),
        ("mid", -0.76, 0.42, 0.19),
        ("upper", -1.12, 0.32, 0.15),
        ("tip", -1.36, 0.18, 0.09),
        ("point", -1.50, 0.08, 0.045),
    ]
    for name, z, length, width in blade_rows:
        left_w = width * 0.30
        mid_w = width * 0.46
        right_w = width * 0.28
        parts.append(cube(f"blade_{name}_highlight", (-(width - left_w) * 0.5, 0.0, z), (left_w + 0.004, 0.055, length + 0.012), steel_light))
        parts.append(cube(f"blade_{name}_mid", ((left_w - right_w) * 0.5, 0.0, z), (mid_w + 0.004, 0.055, length + 0.012), steel))
        parts.append(cube(f"blade_{name}_shadow", ((width - right_w) * 0.5, 0.0, z), (right_w + 0.004, 0.055, length + 0.012), steel_shadow))

    parts.append(cube("blade_upper_glint", (-0.035, 0.034, -0.58), (0.030, 0.018, 0.28), steel_glint))
    parts.append(cube("blade_lower_glint", (-0.025, 0.034, -1.14), (0.026, 0.018, 0.20), steel_glint))
    parts.append(cube("blade_tip_spark", (0.0, 0.034, -1.53), (0.040, 0.018, 0.045), steel_glint))

    parts.append(cube("crossguard_core", (0.0, 0.0, -0.08), (0.58, 0.09, 0.09), brass))
    parts.append(cube("crossguard_highlight", (-0.11, 0.052, -0.105), (0.36, 0.020, 0.026), brass_light))
    parts.append(cube("crossguard_shadow", (0.13, -0.046, -0.055), (0.34, 0.020, 0.026), brass_shadow))
    parts.append(cube("crossguard_left_cap", (-0.35, 0.0, -0.08), (0.12, 0.11, 0.11), brass))
    parts.append(cube("crossguard_right_cap", (0.35, 0.0, -0.08), (0.12, 0.11, 0.11), brass_shadow))
    parts.append(cube("grip", (0.0, 0.0, 0.17), (0.105, 0.105, 0.43), leather))
    parts.append(cube("grip_highlight", (-0.035, 0.056, 0.17), (0.030, 0.020, 0.38), leather_light))
    for i, z in enumerate([0.02, 0.16, 0.30]):
        parts.append(cube(f"grip_wrap_{i}", (0.0, 0.058, z), (0.13, 0.028, 0.04), brass_light))
    parts.append(cube("pommel_block", (0.0, 0.0, 0.44), (0.18, 0.14, 0.14), brass))
    parts.append(cube("pommel_shadow", (0.045, -0.050, 0.44), (0.055, 0.025, 0.12), brass_shadow))
    parts.append(cube("pommel_gem", (0.0, 0.073, 0.44), (0.065, 0.018, 0.065), ruby))

    for part in parts:
        part.parent = root

    return root


def add_camera_and_light(target: bpy.types.Object) -> bpy.types.Object:
    bpy.ops.object.light_add(type="AREA", location=(0.0, -3.2, 2.8))
    light = bpy.context.object
    light.name = "PreviewKeyLight"
    light.data.energy = 170
    light.data.size = 3.0
    direction = Vector((0.0, 0.0, -0.42)) - light.location
    light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    for name, location, energy in [
        ("PreviewSideFill", (3.0, 0.0, 2.0), 130),
        ("PreviewTopFill", (0.0, 0.0, 3.6), 90),
    ]:
        bpy.ops.object.light_add(type="AREA", location=location)
        fill = bpy.context.object
        fill.name = name
        fill.data.energy = energy
        fill.data.size = 2.5
        direction = Vector((0.0, 0.0, -0.42)) - fill.location
        fill.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    bpy.ops.object.camera_add(location=(1.6, -3.1, 1.0), rotation=(math.radians(64), 0, math.radians(34)))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 3.0
    bpy.context.scene.camera = camera

    direction = Vector((0.0, 0.0, -0.42)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return camera


def export_glb() -> None:
    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=True,
    )


def configure_render() -> None:
    OUT_PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 1000
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 64
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.render.film_transparent = True


def aim_camera(camera: bpy.types.Object, location: tuple[float, float, float], target: tuple[float, float, float], scale: float) -> None:
    camera.location = location
    camera.data.ortho_scale = scale
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_to(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def render_previews(root: bpy.types.Object, camera: bpy.types.Object) -> None:
    configure_render()

    root.rotation_euler = (0.0, 0.0, 0.0)
    aim_camera(camera, (1.6, -3.1, 1.0), (0.0, 0.0, -0.42), 3.0)
    render_to(OUT_PREVIEW)

    aim_camera(camera, (0.0, -4.0, -0.42), (0.0, 0.0, -0.42), 4.0)
    render_to(OUT_FRONT)

    aim_camera(camera, (4.0, 0.0, -0.42), (0.0, 0.0, -0.42), 4.0)
    render_to(OUT_SIDE)

    root.rotation_euler = (math.radians(90), 0.0, 0.0)
    aim_camera(camera, (0.0, 0.0, 4.0), (0.0, 0.42, 0.0), 4.0)
    render_to(OUT_TOP)
    root.rotation_euler = (0.0, 0.0, 0.0)


def main() -> None:
    reset_scene()
    root = build_sword()
    camera = add_camera_and_light(root)
    export_glb()
    render_previews(root, camera)
    print(f"Wrote {OUT_GLB}")
    print(f"Wrote {OUT_PREVIEW}")
    print(f"Wrote {OUT_FRONT}")
    print(f"Wrote {OUT_SIDE}")
    print(f"Wrote {OUT_TOP}")


if __name__ == "__main__":
    main()
