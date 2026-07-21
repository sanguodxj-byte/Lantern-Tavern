"""Mechanical helpers for one-model voxel weapon generators.

This module owns no weapon ids or silhouettes. Dedicated
``generate_voxel_<weapon_id>.py`` scripts define every authored part and call
the overlap guard before using these export and preview helpers.
"""
from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector


PX = 1.0 / 32.0


def px(value: float) -> float:
    return value * PX


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.images,
        bpy.data.lights,
        bpy.data.cameras,
        bpy.data.worlds,
    ):
        for block in list(collection):
            collection.remove(block)


def make_root(name: str) -> bpy.types.Object:
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    return root


def make_material(
    name: str,
    rgba: tuple[float, float, float, float],
    *,
    metallic: float = 0.0,
    roughness: float = 0.8,
    emission: float = 0.0,
) -> bpy.types.Material:
    """Create the authored base material; each box also exports COLOR_0."""
    material = bpy.data.materials.new(name)
    material.diffuse_color = rgba
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = metallic
    if emission > 0.0:
        emission_input = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
        if emission_input in bsdf.inputs:
            bsdf.inputs[emission_input].default_value = rgba
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission
    color_attribute = nodes.new(type="ShaderNodeAttribute")
    color_attribute.attribute_name = "Color"
    color_attribute.location = (-280, -80)
    # Keep authored hue in Base Color. The opaque COLOR_0 alpha connection is
    # enough for Blender's glTF exporter to retain the voxel color attribute.
    links.new(color_attribute.outputs["Alpha"], bsdf.inputs["Alpha"])
    return material


def make_pixel_material(
    name: str,
    pattern: tuple[str, ...],
    palette: dict[str, tuple[float, float, float, float]],
    *,
    metallic: float = 0.0,
    roughness: float = 0.8,
    emission: float = 0.0,
    tile_size_px: float = 8.0,
) -> bpy.types.Material:
    """Create a nearest-neighbor pixel material embedded in the exported GLB."""
    if not pattern or not pattern[0]:
        raise ValueError(f"{name}: pixel pattern cannot be empty")
    width = len(pattern[0])
    if any(len(row) != width for row in pattern):
        raise ValueError(f"{name}: pixel pattern rows must have equal width")
    missing = {symbol for row in pattern for symbol in row if symbol not in palette}
    if missing:
        raise ValueError(f"{name}: missing palette symbols {sorted(missing)}")
    if tile_size_px <= 0.0:
        raise ValueError(f"{name}: tile_size_px must be positive")

    average = tuple(
        sum(color[channel] for color in palette.values()) / len(palette)
        for channel in range(4)
    )
    material = make_material(
        name,
        average,
        metallic=metallic,
        roughness=roughness,
        emission=emission,
    )
    image = bpy.data.images.new(
        f"{name}_albedo",
        width=width,
        height=len(pattern),
        alpha=True,
    )
    pixels: list[float] = []
    for row in reversed(pattern):
        for symbol in row:
            pixels.extend(palette[symbol])
    image.file_format = "PNG"
    image.colorspace_settings.name = "sRGB"
    image.pixels.foreach_set(pixels)
    image.update()
    image.pack()

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    texture = nodes.new(type="ShaderNodeTexImage")
    texture.name = f"{name}_nearest_texture"
    texture.image = image
    texture.interpolation = "Closest"
    texture.extension = "REPEAT"
    links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    if emission > 0.0:
        emission_input = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
        if emission_input in bsdf.inputs:
            links.new(texture.outputs["Color"], bsdf.inputs[emission_input])

    # glTF multiplies COLOR_0 by the albedo texture. White retains the authored
    # texture while still exporting the vertex-color channel required by tests.
    material["voxel_texture_uses_white_vertex_color"] = True
    material["voxel_texture_tile_px"] = tile_size_px
    return material


def _apply_voxel_scaled_uv(obj: bpy.types.Object, tile_size_px: float) -> None:
    """Project UVs per box face so one texture tile has a fixed pixel scale."""
    mesh = obj.data
    uv_layer = mesh.uv_layers.active
    if uv_layer is None:
        uv_layer = mesh.uv_layers.new(name="UVMap")
    world_offset_px = obj.location / PX
    for polygon in mesh.polygons:
        normal = polygon.normal
        axis = max(range(3), key=lambda index: abs(normal[index]))
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co / PX
            world_px = vertex + world_offset_px
            if axis == 0:
                uv = (world_px.y / tile_size_px, world_px.z / tile_size_px)
            elif axis == 1:
                uv = (world_px.x / tile_size_px, world_px.z / tile_size_px)
            else:
                uv = (world_px.x / tile_size_px, world_px.y / tile_size_px)
            uv_layer.data[loop_index].uv = uv


def _paint_vertex_color(
    obj: bpy.types.Object,
    rgba: tuple[float, float, float, float],
) -> None:
    mesh = obj.data
    if hasattr(mesh, "color_attributes"):
        attribute = mesh.color_attributes.get("Color")
        if attribute is None:
            attribute = mesh.color_attributes.new(
                name="Color",
                type="BYTE_COLOR",
                domain="CORNER",
            )
        for item in attribute.data:
            item.color = rgba
        mesh.color_attributes.active_color = attribute
        return
    if not mesh.vertex_colors:
        mesh.vertex_colors.new(name="Col")
    for item in mesh.vertex_colors.active.data:
        item.color = rgba


def box_px(
    name: str,
    center_px: tuple[float, float, float],
    size_px: tuple[float, float, float],
    material: bpy.types.Material,
) -> bpy.types.Object:
    """Create one axis-aligned box from authored pixel dimensions."""
    bpy.ops.mesh.primitive_cube_add(
        size=1.0,
        location=tuple(px(value) for value in center_px),
    )
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = tuple(px(value) for value in size_px)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    texture_tile_px = material.get("voxel_texture_tile_px")
    if texture_tile_px is not None:
        _apply_voxel_scaled_uv(obj, float(texture_tile_px))
    vertex_color = (
        (1.0, 1.0, 1.0, 1.0)
        if material.get("voxel_texture_uses_white_vertex_color", False)
        else tuple(material.diffuse_color)
    )
    _paint_vertex_color(obj, vertex_color)
    return obj


def parent_parts(root: bpy.types.Object, parts: list[bpy.types.Object]) -> None:
    for part in parts:
        part.parent = root


def _select_tree(root: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root


def export_glb(root: bpy.types.Object, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    _select_tree(root)
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_attributes=True,
    )


def _bounds(root: bpy.types.Object) -> tuple[Vector, Vector]:
    points: list[Vector] = []
    for obj in root.children_recursive:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        raise RuntimeError(f"{root.name} has no mesh bounds")
    minimum = Vector(
        (
            min(point.x for point in points),
            min(point.y for point in points),
            min(point.z for point in points),
        )
    )
    maximum = Vector(
        (
            max(point.x for point in points),
            max(point.y for point in points),
            max(point.z for point in points),
        )
    )
    return minimum, maximum


def bounds_size_px(root: bpy.types.Object) -> tuple[float, float, float]:
    minimum, maximum = _bounds(root)
    size = (maximum - minimum) / PX
    return (size.x, size.y, size.z)


def _aim_camera(
    camera: bpy.types.Object,
    location: Vector,
    target: Vector,
    scale: float,
) -> None:
    camera.location = location
    camera.data.ortho_scale = scale
    camera.rotation_euler = (target - location).to_track_quat("-Z", "Y").to_euler()


def _configure_render() -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0

    world = bpy.data.worlds.new("WeaponPreviewWorld")
    world.use_nodes = True
    background = next(
        node for node in world.node_tree.nodes if node.type == "BACKGROUND"
    )
    background.inputs["Color"].default_value = (0.018, 0.021, 0.024, 1.0)
    background.inputs["Strength"].default_value = 0.22
    scene.world = world


def _add_preview_lights(target: Vector, reach: float) -> None:
    light_specs = [
        ("KeyLight", Vector((1.55, -2.4, 1.8)), 310.0, 3.2),
        ("FillLight", Vector((-2.0, -0.8, 0.7)), 125.0, 2.8),
        ("RimLight", Vector((1.0, 2.2, 2.3)), 170.0, 2.6),
    ]
    for name, direction, energy, size in light_specs:
        location = target + direction * reach
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = size
        light.rotation_euler = (target - location).to_track_quat("-Z", "Y").to_euler()


def render_true_3d_views(
    root: bpy.types.Object,
    model_id: str,
    preview_dir: Path,
) -> None:
    """Render preview/front/side/top for exactly one model root."""
    preview_dir.mkdir(parents=True, exist_ok=True)
    _configure_render()
    minimum, maximum = _bounds(root)
    target = (minimum + maximum) * 0.5
    size = maximum - minimum
    longest = max(size.x, size.y, size.z)
    ortho_scale = max(longest * 1.28, 0.65)
    reach = max(longest * 2.8, 2.0)
    _add_preview_lights(target, max(longest, 0.8))

    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.name = f"{model_id}_preview_camera"
    camera.data.type = "ORTHO"
    bpy.context.scene.camera = camera

    views = {
        "preview": target + Vector((reach * 0.58, -reach, reach * 0.24)),
        "front": target + Vector((0.0, -reach, 0.0)),
        "side": target + Vector((reach, 0.0, 0.0)),
        "top": target + Vector((0.0, 0.0, reach)),
    }
    for view_name, location in views.items():
        scale = ortho_scale * (1.06 if view_name == "preview" else 1.0)
        _aim_camera(camera, location, target, scale)
        output_path = preview_dir / f"voxel_{model_id}_render_{view_name}.png"
        bpy.context.scene.render.filepath = str(output_path)
        bpy.ops.render.render(write_still=True)
