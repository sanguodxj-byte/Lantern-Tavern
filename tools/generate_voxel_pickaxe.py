"""Standalone voxel pickaxe for EquipmentComponent (not baked into character meshes).

Scale matches other weapons_voxel_*.glb: grip near origin, head along -Z combat forward.

Run:
  D:/123/blender/blender.exe --background --python tools/generate_voxel_pickaxe.py
"""
from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_pickaxe.glb"
OUT_PREVIEW = ROOT / "reports" / "weapons_preview" / "voxel_pickaxe_preview.png"


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def make_mat(name: str, color: tuple[float, float, float, float], metallic: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.72
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metallic
    return mat


def cube(name, location, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def build_pickaxe() -> bpy.types.Object:
    wood = make_mat("pick_wood", (0.42, 0.28, 0.14, 1.0))
    wood_light = make_mat("pick_wood_light", (0.58, 0.40, 0.22, 1.0))
    iron = make_mat("pick_iron", (0.55, 0.58, 0.62, 1.0), metallic=0.55)
    iron_dark = make_mat("pick_iron_dark", (0.32, 0.34, 0.38, 1.0), metallic=0.4)
    iron_light = make_mat("pick_iron_light", (0.75, 0.78, 0.82, 1.0), metallic=0.6)

    root = bpy.data.objects.new("weapons_voxel_pickaxe", None)
    bpy.context.collection.objects.link(root)
    parts = []

    # Shaft along -Z (combat forward), grip near origin
    parts.append(cube("haft_main", (0.0, 0.0, -0.35), (0.07, 0.07, 0.95), wood))
    parts.append(cube("haft_highlight", (-0.025, 0.035, -0.35), (0.02, 0.02, 0.85), wood_light))
    parts.append(cube("grip_wrap", (0.0, 0.0, 0.08), (0.09, 0.09, 0.18), wood_light))
    parts.append(cube("pommel", (0.0, 0.0, 0.22), (0.10, 0.10, 0.08), iron_dark))

    # Pick head
    parts.append(cube("head_socket", (0.0, 0.0, -0.78), (0.12, 0.12, 0.12), iron))
    parts.append(cube("head_blade_l", (-0.22, 0.0, -0.78), (0.32, 0.06, 0.10), iron_light))
    parts.append(cube("head_blade_r", (0.22, 0.0, -0.78), (0.32, 0.06, 0.10), iron))
    parts.append(cube("head_tip_l", (-0.40, 0.0, -0.78), (0.10, 0.04, 0.06), iron_dark))
    parts.append(cube("head_tip_r", (0.40, 0.0, -0.78), (0.10, 0.04, 0.06), iron_dark))
    parts.append(cube("head_spike", (0.0, 0.0, -0.90), (0.05, 0.05, 0.14), iron_light))

    for p in parts:
        p.parent = root
    return root


def export_glb(root: bpy.types.Object) -> None:
    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        use_selection=True,
        export_format="GLB",
        export_apply=True,
    )


def main() -> None:
    reset_scene()
    root = build_pickaxe()
    export_glb(root)
    print(f"Wrote {OUT_GLB}")


if __name__ == "__main__":
    main()
