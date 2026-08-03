from __future__ import annotations

"""Generate the dedicated round voxel buckler (圆盾) as one fixed-identity model.

This generator owns exactly one model and one output identity. It rebuilds the
legacy high-poly buckler (17k triangles, built from Blender cylinders) as a
Barony-style authored voxel round shield using face-attached stepped slabs, a
centred boss, a metal rim and a rear wrist grip. Pixel scale: 1m = 32px.

The exported GLB keeps the exact node contract used at runtime: a root node
(voxel_buckler) containing a single merged MeshInstance3D named "Buckler",
so ``mesh_node = buckler/Buckler`` in pickable_buckler.tscn keeps resolving.
"""

import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import bpy  # noqa: E402

from voxel_overlap_guard import (  # noqa: E402
    assert_parts_no_positive_volume_overlap,
    assert_parts_voxel_assembly_valid,
)
from voxel_single_model_cli import reject_target_override  # noqa: E402
from voxel_weapon_model_lib import (  # noqa: E402
    PX,
    box_px,
    export_glb,
    make_material,
    make_pixel_material,
    make_root,
    parent_parts,
    reset_scene,
    render_true_3d_views,
)

MODEL_ID = "buckler"
# Round buckler: ~24px diameter face, ~5px thick, stepped silhouette.
DIAMETER_PX = 24.0
THICKNESS_PX = 5.0
ROW_HEIGHT_PX = 4.0
RADIUS_PX = DIAMETER_PX * 0.5

OUT_GLB = ROOT / "assets" / "meshes" / "shields" / "voxel_buckler.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_buckler() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    # Flat oak body with a subtle ringed wood pixel texture.
    oak = make_pixel_material(
        "buckler_material_oak",
        (
            "ddmmmmdd",
            "dmllllmd",
            "mllmmllm",
            "mlddddlm",
            "ddmmmddd",
            "mlddddlm",
            "mllmmllm",
            "dmllllmd",
        ),
        {
            "d": (0.055, 0.013, 0.004, 1.0),
            "m": (0.220, 0.062, 0.014, 1.0),
            "l": (0.405, 0.160, 0.036, 1.0),
        },
        roughness=0.90,
    )
    oak_shadow = make_pixel_material(
        "buckler_material_oak_shadow",
        (
            "dddddddd",
            "ddmmmmdd",
            "dmllllmd",
            "dmddddmd",
            "dmddddmd",
            "dmllllmd",
            "ddmmmmdd",
            "dddddddd",
        ),
        {
            "d": (0.036, 0.008, 0.003, 1.0),
            "m": (0.150, 0.034, 0.008, 1.0),
            "l": (0.285, 0.095, 0.022, 1.0),
        },
        roughness=0.95,
    )
    forged_iron = make_material(
        "buckler_material_iron", (0.155, 0.185, 0.205, 1.0), metallic=0.80, roughness=0.45
    )
    hardened_steel = make_material(
        "buckler_material_steel", (0.560, 0.655, 0.685, 1.0), metallic=0.88, roughness=0.30
    )
    leather_grip = make_pixel_material(
        "buckler_material_leather_grip",
        (
            "dddddddd",
            "dmmmmmmd",
            "dmllllmd",
            "dmmmmmmd",
            "dddddddd",
            "dmmmmmmd",
            "dmllllmd",
            "dmmmmmmd",
        ),
        {
            "d": (0.028, 0.006, 0.003, 1.0),
            "m": (0.100, 0.020, 0.009, 1.0),
            "l": (0.200, 0.058, 0.021, 1.0),
        },
        roughness=0.93,
    )

    root = make_root("voxel_buckler")
    parts: list[bpy.types.Object] = []

    def add(
        name: str,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        parts.append(box_px(name, center, size, material))

    def add_x_pair(
        prefix: str,
        x: float,
        depth: float,
        length: float,
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        add(f"{prefix}_left", (-x, depth, length), size, material)
        add(f"{prefix}_right", (x, depth, length), size, material)

    # ── Round wooden face, built from stepped horizontal slabs so the front
    # view reads as a ringed round shield, not a flat rectangle. ──
    rows: list[tuple[float, float]] = []  # (z_center, half_width)
    z = -RADIUS_PX + ROW_HEIGHT_PX * 0.5
    while z + ROW_HEIGHT_PX * 0.5 <= RADIUS_PX:
        half_width = math.sqrt(max(0.0, RADIUS_PX * RADIUS_PX - z * z))
        rows.append((z, half_width))
        z += ROW_HEIGHT_PX
    for i, (z_center, half_width) in enumerate(rows):
        width = max(1.0, math.floor(half_width * 2.0))
        if width < 3.0:
            continue
        material = oak_shadow if i % 2 else oak
        add(f"body_slab_{i:02d}", (0.0, 0.0, z_center), (width, THICKNESS_PX, ROW_HEIGHT_PX), material)

    # ── Front concentric ring bands (face-attached on the outer slab face:
    # slab spans Y -2.5..2.5, so front plates centre at Y 3.0, never entering it). ──
    add_x_pair("front_ring_outer", RADIUS_PX - 2.0, 3.0, 0.0, (2.0, 1.0, RADIUS_PX * 2.0 - 8.0), forged_iron)
    add_x_pair("front_ring_mid", 6.0, 3.0, 0.0, (1.0, 1.0, 10.0), hardened_steel)

    # ── Stepped central boss: octagonal base plate + raised cap + iron ring. ──
    add("front_boss_base", (0.0, 3.0, 0.0), (11.0, 1.0, 11.0), forged_iron)
    add("front_boss_cap", (0.0, 4.0, 0.0), (5.0, 1.0, 5.0), hardened_steel)
    add_x_pair("front_boss_ring", 4.0, 4.0, 0.0, (1.0, 1.0, 6.0), forged_iron)
    add("front_boss_ring_top", (0.0, 4.0, 4.0), (6.0, 1.0, 1.0), forged_iron)
    add("front_boss_ring_bottom", (0.0, 4.0, -4.0), (6.0, 1.0, 1.0), forged_iron)
    add_x_pair("front_rivet_upper", RADIUS_PX - 2.0, 4.0, 7.0, (1.0, 1.0, 1.0), hardened_steel)
    add_x_pair("front_rivet_lower", RADIUS_PX - 2.0, 4.0, -7.0, (1.0, 1.0, 1.0), hardened_steel)

    # ── Rear wrist grip: two iron mounts + leather wrapped bar. ──
    add("back_grip_mount_upper", (0.0, -3.0, 4.5), (2.0, 1.0, 2.0), forged_iron)
    add("back_grip_mount_lower", (0.0, -3.0, -4.5), (2.0, 1.0, 2.0), forged_iron)
    add("back_grip_bar", (0.0, -4.0, 0.0), (2.0, 1.0, 12.0), leather_grip)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def _join_body_parts(root: bpy.types.Object, parts: list[bpy.types.Object]) -> None:
    """Merge all voxel boxes into a single MeshInstance3D named ``Buckler``.

    The runtime mount contract (``pickable_buckler.tscn`` -> ``mesh_node`` =
    ``buckler/Buckler``) expects the GLB to expose one child mesh named
    ``Buckler``. Joining preserves every per-box material slot and vertex
    colour; it only removes the node-per-box split that would otherwise break
    the named-child lookup.
    """
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    if not parts:
        return
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    merged = bpy.context.object
    merged.name = "Buckler"
    merged.parent = root


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_buckler()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    # Keep the source parts validated, then merge for the runtime child contract.
    _join_body_parts(root, parts)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(f"Buckler envelope: {DIAMETER_PX:.0f}px diameter x {THICKNESS_PX:.0f}px thick "
          f"= {DIAMETER_PX * PX:.3f}m x {THICKNESS_PX * PX:.3f}m")


if __name__ == "__main__":
    main()