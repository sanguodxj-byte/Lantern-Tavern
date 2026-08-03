"""Mechanical Blender helpers for one independently authored voxel model.

This module owns no character proportions, silhouettes, identities, source
tables, or output registry. Callers provide every object and every exact path.
"""
from __future__ import annotations

import math
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


# ---------------------------------------------------------------------------
# Pixel-art PBR material helper
# ---------------------------------------------------------------------------
# Generates small nearest-filtered albedo / normal / roughness images from a
# caller-supplied palette + seed, producing crisp pixel-art surface detail on
# each cube face. Purely mechanical: no model identities, colour tables, or
# output registries live here. Every design choice (palette, pattern, seed,
# variation) is supplied by the calling generator.

_PIXEL_QUANT_LEVELS = 6


def _hash2(x: int, y: int, seed: int) -> float:
    """Deterministic 0..1 hash per integer pixel coordinate + seed."""
    h = (x * 374761393 + y * 668265263 + seed * 2654435761) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFFFF) / float(0xFFFFFFFF)


def _value_noise(x: float, y: float, seed: int) -> float:
    """Smooth 0..1 value noise via bilinear interpolation of integer hashes."""
    x0, y0 = math.floor(x), math.floor(y)
    x1, y1 = x0 + 1, y0 + 1
    fx = x - x0
    fy = y - y0
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    v00 = _hash2(x0, y0, seed)
    v10 = _hash2(x1, y0, seed)
    v01 = _hash2(x0, y1, seed)
    v11 = _hash2(x1, y1, seed)
    a = v00 + (v10 - v00) * fx
    b = v01 + (v11 - v01) * fx
    return a + (b - a) * fy


def _quantize(v: float, levels: int) -> float:
    levels = max(2, levels)
    return round(v * (levels - 1)) / float(levels - 1)


def _make_image(name: str, size: int, colorspace: str) -> bpy.types.Image:
    img = bpy.data.images.new(name, width=size, height=size, alpha=True)
    img.generated_type = "BLANK"
    img.colorspace_settings.name = colorspace
    return img


def _write_pixels(img: bpy.types.Image, pixels: list[float]) -> None:
    img.pixels = pixels
    img.pack()


def _pixel_albedo(
    size: int,
    color: tuple[float, float, float, float],
    palette: tuple[tuple[float, float, float, float], ...],
    variation: float,
    seed: int,
    pattern: str,
    emission: float,
    edge_darken: float = 0.0,
    highlight: float = 0.0,
    detail_noise: float = 0.0,
) -> tuple[list[float], list[float]]:
    """Return (albedo_pixels, height_field) for a pixel-art albedo texture."""
    albedo: list[float] = []
    heights: list[float] = []
    base = Vector((color[0], color[1], color[2]))
    cx = cy = (size - 1) * 0.5
    max_r = math.hypot(cx, cy) if size > 1 else 1.0
    # Pre-compute scale-row geometry for "scales" pattern.
    scale_h = max(2.0, size / 4.0)
    for y in range(size):
        for x in range(size):
            nx = x / float(size - 1) if size > 1 else 0.0
            ny = y / float(size - 1) if size > 1 else 0.0
            dist = math.hypot(x - cx, y - cy) / max_r
            n = _value_noise(x * 0.62, y * 0.62, seed)
            n2 = _value_noise(x * 1.30 + 11.0, y * 1.30 + 7.0, seed + 91)
            # Fine high-frequency detail noise for micro-grain.
            fine = _value_noise(x * 3.20, y * 3.20, seed + 777)
            bright = 0.0
            crack = 0.0
            if pattern == "crystal":
                band = _quantize(dist * 3.0, 6)
                bright = (band - 0.5) * variation * 1.8
                seam = 1.0 - min(1.0, abs(_value_noise(x * 0.9, y * 0.9, seed + 5) - 0.5) * 5.0)
                bright += seam * variation * 1.8
                crack = seam * 0.8
            elif pattern == "cracks":
                edge = 1.0 - min(1.0, abs(n - 0.5) * 5.0)
                bright = (n - 0.5) * variation * 1.0 + edge * variation * 1.8
                crack = edge * 0.9
            elif pattern == "speckle":
                bright = (n - 0.5) * variation * 0.6
                if n2 > 0.82:
                    bright += variation * 2.4
                    crack = 0.5
            elif pattern == "scales":
                # Overlapping scale rows: bright crescent tops, dark gaps.
                row = int(y / scale_h)
                x_off = (row % 2) * (scale_h * 0.5)
                sx = (x + x_off) % scale_h
                arc_dy = (y % scale_h) / scale_h
                arc_val = 1.0 - abs(sx / scale_h - 0.5) * 2.8
                arc_val = max(0.0, arc_val)
                bright = (arc_val - 0.4) * variation * 3.0 + (arc_dy - 0.5) * variation * 1.0
                bright += (n - 0.5) * variation * 0.3
                crack = (1.0 - arc_val) * 0.6
            elif pattern == "vein":
                # Branching vein lines: main channels + perpendicular branches.
                main_vein = 1.0 - min(1.0, abs(n - 0.48) * 3.0)
                branch = 1.0 - min(1.0, abs(n2 - 0.52) * 4.0)
                vein_val = max(main_vein, branch * 0.8)
                bright = (vein_val - 0.2) * variation * 3.5 + (n - 0.5) * variation * 0.15
                crack = vein_val * 0.7
            elif pattern == "banded":
                # Horizontal sedimentary / grain bands with gentle warp.
                warp = _value_noise(x * 0.30, y * 0.30, seed + 33) * 3.0
                band_y = _quantize((y + warp) / size * 5.0, 6)
                bright = (band_y - 0.5) * variation * 1.6
                bright += (n - 0.5) * variation * 0.5
                crack = (1.0 - min(1.0, abs(n - 0.5) * 6.0)) * 0.3
            elif pattern == "porous":
                # Sponge-like pore holes: dark pits with bright rims.
                pore = _value_noise(x * 0.80, y * 0.80, seed + 44)
                pore2 = _value_noise(x * 1.60, y * 1.60, seed + 55)
                pit = 1.0 if pore < 0.40 or pore2 < 0.30 else 0.0
                rim = max(0.0, 1.0 - min(1.0, abs(pore - 0.40) * 8.0)) if not pit else 0.0
                bright = (n - 0.5) * variation * 0.6
                if pit:
                    bright -= variation * 2.8
                    crack = 0.8
                elif rim:
                    bright += variation * 1.8
                    crack = 0.4
            elif pattern == "wood":
                # Concentric rings + longitudinal streaks for wood grain.
                ring_dist = dist + _value_noise(x * 0.40, y * 0.40, seed + 66) * 0.15
                ring = abs(ring_dist * 6.0 - round(ring_dist * 6.0))
                ring_val = 1.0 - min(1.0, ring * 4.0)
                streak = _value_noise(x * 0.20, y * 2.50, seed + 88)
                bright = (ring_val - 0.5) * variation * 1.4 + (streak - 0.5) * variation * 0.8
                crack = ring_val * 0.4
            else:  # "noise"
                bright = (n - 0.5) * variation * 2.4
                bright += (n2 - 0.5) * variation * 0.8
            # Secondary fine detail noise for micro-grain texture.
            if detail_noise > 0.0:
                bright += (fine - 0.5) * detail_noise * 1.2
            bright = _quantize(0.5 + bright, _PIXEL_QUANT_LEVELS) - 0.5
            shade = 1.0 + bright
            shade = max(0.25, min(shade, 1.8))
            r, g, b = base.x * shade, base.y * shade, base.z * shade
            # Edge darkening: simulate ambient occlusion at cube face borders.
            if edge_darken > 0.0:
                border_dist = min(x, y, size - 1 - x, size - 1 - y)
                border_threshold = max(1.0, size * 0.12)
                if border_dist < border_threshold:
                    edge_factor = 1.0 - (1.0 - border_dist / border_threshold) * edge_darken
                    r *= edge_factor
                    g *= edge_factor
                    b *= edge_factor
            # Specular highlight specks on raised surface areas.
            if highlight > 0.0 and bright > 0.12:
                h_strength = min(1.0, (bright - 0.12) / 0.25)
                if _hash2(x, y, seed + 400) > 0.70:
                    hl = highlight * h_strength * 0.6
                    r = min(1.0, r + hl)
                    g = min(1.0, g + hl)
                    b = min(1.0, b + hl)
            # sparse palette accent specks (mineral flecks / spores / grit)
            if palette and _hash2(x, y, seed + 200) > 0.82:
                pick = palette[int(_hash2(x, y, seed + 300) * len(palette)) % len(palette)]
                mix = 0.72
                r = r * (1.0 - mix) + pick[0] * mix
                g = g * (1.0 - mix) + pick[1] * mix
                b = b * (1.0 - mix) + pick[2] * mix
                crack = max(crack, 0.35)
            # emission glow specks for glowing materials
            if emission > 0.0 and _hash2(x, y, seed + 500) > 0.82:
                glow = 1.6 + emission * 0.2
                r = min(1.0, r * glow + 0.22)
                g = min(1.0, g * glow + 0.22)
                b = min(1.0, b * glow + 0.22)
                crack = max(crack, 0.55)
            albedo.extend((max(0.0, min(1.0, r)), max(0.0, min(1.0, g)), max(0.0, min(1.0, b)), 1.0))
            heights.append(max(0.0, min(1.0, 0.5 + bright * 1.0 + crack * 0.6)))
    return albedo, heights


def _pixel_normal(size: int, heights: list[float], strength: float) -> list[float]:
    pixels: list[float] = []
    for y in range(size):
        for x in range(size):
            xl = heights[y * size + max(0, x - 1)]
            xr = heights[y * size + min(size - 1, x + 1)]
            yu = heights[max(0, y - 1) * size + x]
            yd = heights[min(size - 1, y + 1) * size + x]
            dx = (xl - xr) * strength
            dy = (yu - yd) * strength
            nz = 1.0
            inv = 1.0 / math.sqrt(dx * dx + dy * dy + nz * nz)
            pixels.extend((dx * inv * 0.5 + 0.5, dy * inv * 0.5 + 0.5, nz * inv * 0.5 + 0.5, 1.0))
    return pixels


def _pixel_roughness(size: int, base: float, variation: float, seed: int) -> list[float]:
    pixels: list[float] = []
    for y in range(size):
        for x in range(size):
            n = _value_noise(x * 1.1, y * 1.1, seed + 13)
            r = base + (n - 0.5) * variation
            r = max(0.05, min(1.0, r))
            pixels.extend((r, r, r, 1.0))
    return pixels


def make_pixel_material(
    name: str,
    color: tuple[float, float, float, float],
    *,
    roughness: float = 0.85,
    metallic: float = 0.0,
    emission: float = 0.0,
    palette: tuple[tuple[float, float, float, float], ...] = (),
    pixel_size: int = 16,
    variation: float = 0.16,
    seed: int = 0,
    pattern: str = "noise",
    normal_strength: float = 0.6,
    edge_darken: float = 0.0,
    highlight: float = 0.0,
    detail_noise: float = 0.0,
) -> bpy.types.Material:
    """Create a Principled BSDF material with procedural pixel-art textures.

    Generates nearest-filtered albedo / normal / roughness maps so each cube
    face shows crisp, hand-pixelled-looking surface detail. All design inputs
    (colour, palette, pattern, seed, variation) come from the caller; this
    helper owns no model identity.
    """
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    nt = material.node_tree
    for node in list(nt.nodes):
        nt.nodes.remove(node)
    output = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
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

    size = max(4, int(pixel_size))
    albedo_px, heights = _pixel_albedo(size, color, palette, variation, seed, pattern, emission, edge_darken, highlight, detail_noise)
    albedo_img = _make_image(f"{name}_albedo", size, "sRGB")
    _write_pixels(albedo_img, albedo_px)
    albedo_tex = nt.nodes.new("ShaderNodeTexImage")
    albedo_tex.image = albedo_img
    albedo_tex.interpolation = "Closest"
    nt.links.new(albedo_tex.outputs["Color"], bsdf.inputs["Base Color"])

    normal_img = _make_image(f"{name}_normal", size, "Non-Color")
    _write_pixels(normal_img, _pixel_normal(size, heights, normal_strength))
    normal_tex = nt.nodes.new("ShaderNodeTexImage")
    normal_tex.image = normal_img
    normal_tex.interpolation = "Closest"
    normal_map = nt.nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = normal_strength
    nt.links.new(normal_tex.outputs["Color"], normal_map.inputs["Color"])
    nt.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])

    rough_img = _make_image(f"{name}_rough", size, "Non-Color")
    _write_pixels(rough_img, _pixel_roughness(size, roughness, variation * 0.6, seed))
    rough_tex = nt.nodes.new("ShaderNodeTexImage")
    rough_tex.image = rough_img
    rough_tex.interpolation = "Closest"
    nt.links.new(rough_tex.outputs["Color"], bsdf.inputs["Roughness"])

    nt.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
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
    # Map each face to the full 0..1 UV square so procedural pixel-art textures
    # are sampled across the whole face. The default cube unwrap tiles each face
    # into a 0.25x0.25 corner, which only reads a near-uniform 4x4 px region of a
    # 16px texture. Flat-colour materials are visually unaffected.
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv = mesh.uv_layers.active.data
    _face_corners = ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))
    for poly in mesh.polygons:
        for i, loop_idx in enumerate(poly.loop_indices):
            uv[loop_idx].uv = _face_corners[i & 3]
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
