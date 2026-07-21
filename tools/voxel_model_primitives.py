"""Mechanical Blender helpers for one independently authored voxel model.

This module owns no character proportions, silhouettes, identities, source
tables, or output registry. Callers provide every object and every exact path.
"""
from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector

from voxel_overlap_guard import assert_parts_voxel_assembly_valid


PX = 1.0 / 32.0
DEFAULT_GROUND_OFFSET_PX = 1.0
REAL_RENDER_VIEWS = ("preview", "front", "side", "top")


def reset_scene() -> None:
    """Remove Blender scene data before building one model."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.images,
        bpy.data.lights,
        bpy.data.cameras,
        bpy.data.armatures,
        bpy.data.actions,
    ):
        for block in list(collection):
            collection.remove(block)


def meters(px: float) -> float:
    return px * PX


def stack_center(bottom_px: float, height_px: float) -> float:
    """Return a Z center whose bottom face is at ``bottom_px``."""
    return bottom_px + height_px * 0.5


def face_attachment_center(
    host_center_px: float,
    host_half_px: float,
    attached_half_px: float,
    side: float,
) -> float:
    """Place one axis of a part at exact exterior face contact."""
    if side not in (-1.0, 1.0):
        raise ValueError("face attachment side must be -1.0 or 1.0")
    return host_center_px + side * (host_half_px + attached_half_px)


def make_material(
    name: str,
    color: tuple[float, float, float, float],
    *,
    roughness: float = 0.88,
    metallic: float = 0.0,
    emission: float = 0.0,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    bsdf = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = color
    if "Roughness" in bsdf.inputs:
        bsdf.inputs["Roughness"].default_value = roughness
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = metallic
    if emission > 0.0:
        emission_input = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
        if emission_input in bsdf.inputs:
            bsdf.inputs[emission_input].default_value = color
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission
    return material


def cube_px(
    name: str,
    location_px: tuple[float, float, float],
    size_px: tuple[float, float, float],
    material: bpy.types.Material,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(
        size=1.0,
        location=tuple(meters(value) for value in location_px),
    )
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = tuple(meters(value) for value in size_px)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    return obj


def make_root(name: str) -> bpy.types.Object:
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    return root


def mesh_descendants(root: bpy.types.Object) -> list[bpy.types.Object]:
    return [
        obj
        for obj in root.children_recursive
        if getattr(obj, "type", None) == "MESH"
    ]


def validate_face_attached_assembly(root: bpy.types.Object, *, label: str) -> None:
    parts = mesh_descendants(root)
    if not parts:
        raise ValueError(f"{label}: no mesh parts attached to root")
    assert_parts_voxel_assembly_valid(parts, label=label)


def _select_tree(root: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_glb(root: bpy.types.Object, output_path: Path) -> Path:
    """Export exactly ``output_path``; no filename or directory is inferred."""
    output_path = Path(output_path)
    if output_path.suffix.lower() != ".glb":
        raise ValueError(f"GLB output must end in .glb: {output_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    _select_tree(root)
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )
    return output_path


def bounds_center_scale(root: bpy.types.Object) -> tuple[Vector, float]:
    coordinates: list[Vector] = []
    for obj in mesh_descendants(root):
        coordinates.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not coordinates:
        return Vector((0.0, 0.0, 0.5)), 2.0
    minimum = Vector(tuple(min(value[index] for value in coordinates) for index in range(3)))
    maximum = Vector(tuple(max(value[index] for value in coordinates) for index in range(3)))
    center = (minimum + maximum) * 0.5
    size = maximum - minimum
    scale = max(max(size.x, size.y, size.z) * 1.55 + 0.1, 1.2)
    return center, scale


def setup_lights_and_camera(center: Vector, scale: float) -> bpy.types.Object:
    """Create neutral three-point lighting and one orthographic camera."""
    for name, location, energy in (
        ("Key", (center.x + 1.8, center.y - 3.8, center.z + 1.6), 220.0),
        ("Fill", (center.x - 2.4, center.y - 1.0, center.z + 1.0), 90.0),
        ("Top", (center.x, center.y + 0.6, center.z + 3.5), 70.0),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = 3.2
        light.rotation_euler = (center - light.location).to_track_quat("-Z", "Y").to_euler()

    bpy.ops.object.camera_add(location=(center.x + 1.6, center.y - 4.0, center.z + 0.3))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = scale
    bpy.context.scene.camera = camera
    aim_camera(camera, camera.location, center, scale)
    return camera


def aim_camera(
    camera: bpy.types.Object,
    location: tuple[float, float, float] | Vector,
    target: Vector,
    scale: float,
) -> None:
    camera.location = location
    camera.data.ortho_scale = scale
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()


def configure_real_render(*, resolution: int = 1100) -> None:
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"


def render_image(path: Path) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return path


def render_real_views(
    output_dir: Path,
    stem: str,
    center: Vector,
    scale: float,
    camera: bpy.types.Object,
) -> tuple[Path, ...]:
    """Render real 3D views with a stem distinct from structural projections."""
    views = {
        "preview": ((center.x + 1.5, center.y - 3.6, center.z + 0.3), scale),
        "front": ((center.x, center.y - 4.0, center.z), scale),
        "side": ((center.x + 4.0, center.y, center.z), scale),
        "top": ((center.x, center.y, center.z + 4.0), scale),
    }
    rendered: list[Path] = []
    for view in REAL_RENDER_VIEWS:
        location, view_scale = views[view]
        aim_camera(camera, location, center, view_scale)
        rendered.append(render_image(Path(output_dir) / f"{stem}_render_{view}.png"))
    return tuple(rendered)


def finish_model(
    root: bpy.types.Object,
    *,
    output_path: Path,
    preview_dir: Path,
    validation_label: str,
    render_stem: str,
    ground_offset_px: float = DEFAULT_GROUND_OFFSET_PX,
) -> Path:
    """Validate, export, and render one caller-authored object tree."""
    root.location.z += meters(ground_offset_px)
    validate_face_attached_assembly(root, label=validation_label)
    exported = export_glb(root, Path(output_path))
    center, scale = bounds_center_scale(root)
    camera = setup_lights_and_camera(center, scale)
    configure_real_render()
    render_real_views(Path(preview_dir), render_stem, center, scale, camera)
    return exported
