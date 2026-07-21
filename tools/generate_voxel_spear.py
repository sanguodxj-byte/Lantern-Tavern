from __future__ import annotations

"""Generate the dedicated symmetric leaf-bladed voxel spear."""

import sys
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from voxel_overlap_guard import (  # noqa: E402
    assert_parts_no_positive_volume_overlap,
    assert_parts_voxel_assembly_valid,
)
from voxel_single_model_cli import reject_target_override  # noqa: E402
from voxel_weapon_model_lib import (  # noqa: E402
    PX,
    bounds_size_px,
    box_px,
    export_glb,
    make_material,
    make_root,
    parent_parts,
    render_true_3d_views,
    reset_scene,
)


MODEL_ID = "spear"
WIDTH_PX = 13.0
DEPTH_PX = 9.0
LENGTH_PX = 73.0

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_spear.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_spear() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a symmetric 13 x 9 x 73px regulation leaf spear."""
    ash_wood = make_material("spear_ash_wood", (0.30, 0.17, 0.075, 1.0), roughness=0.88)
    leather_dark = make_material(
        "spear_leather_dark", (0.16, 0.035, 0.025, 1.0), roughness=0.92
    )
    leather_mid = make_material(
        "spear_leather_mid", (0.34, 0.085, 0.035, 1.0), roughness=0.84
    )
    bronze_dark = make_material(
        "spear_bronze_dark", (0.42, 0.23, 0.07, 1.0), metallic=0.64, roughness=0.44
    )
    bronze_high = make_material(
        "spear_bronze_high", (0.72, 0.46, 0.14, 1.0), metallic=0.70, roughness=0.33
    )
    steel_spine = make_material(
        "spear_steel_spine", (0.20, 0.27, 0.31, 1.0), metallic=0.74, roughness=0.46
    )
    steel_flat = make_material(
        "spear_steel_flat", (0.43, 0.54, 0.59, 1.0), metallic=0.80, roughness=0.34
    )
    steel_edge = make_material(
        "spear_steel_edge", (0.78, 0.86, 0.89, 1.0), metallic=0.86, roughness=0.24
    )

    root = make_root("weapons_voxel_spear")
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

    def add_y_pair(
        prefix: str,
        width: float,
        y: float,
        length: float,
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        add(f"{prefix}_front", (width, y, length), size, material)
        add(f"{prefix}_back", (width, -y, length), size, material)

    # Create the long central shaft first so runtime fallback collision uses a useful mesh.
    add("body_shaft_core", (0.0, 0.0, -4.0), (3.0, 3.0, 48.0), ash_wood)

    add("head_tip", (0.0, 0.0, -50.0), (1.0, 1.0, 2.0), steel_edge)
    add("head_point_spine", (0.0, 0.0, -47.5), (3.0, 3.0, 3.0), steel_spine)
    add_x_pair("head_point_edge", 2.0, 0.0, -47.5, (1.0, 3.0, 3.0), steel_edge)
    add_y_pair("head_point_ridge", 0.0, 2.0, -47.5, (1.0, 1.0, 3.0), steel_spine)

    add("head_upper_spine", (0.0, 0.0, -44.0), (3.0, 5.0, 4.0), steel_spine)
    add_x_pair("head_upper_edge", 3.0, 0.0, -44.0, (3.0, 5.0, 4.0), steel_edge)
    add("head_belly_spine", (0.0, 0.0, -39.5), (3.0, 5.0, 5.0), steel_spine)
    add_x_pair("head_belly_flat", 3.0, 0.0, -39.5, (3.0, 5.0, 5.0), steel_flat)
    add_x_pair("head_belly_edge", 5.5, 0.0, -39.5, (2.0, 3.0, 5.0), steel_edge)
    add("head_base_spine", (0.0, 0.0, -35.5), (3.0, 5.0, 3.0), steel_spine)
    add_x_pair("head_base_flat", 3.0, 0.0, -35.5, (3.0, 5.0, 3.0), steel_flat)
    add_y_pair("head_ridge", 0.0, 3.0, -40.0, (1.0, 1.0, 12.0), steel_spine)

    add("socket_crown_core", (0.0, 0.0, -32.5), (3.0, 7.0, 3.0), bronze_dark)
    add_x_pair("socket_crown", 2.5, 0.0, -32.5, (2.0, 7.0, 3.0), bronze_high)
    add_x_pair("socket_rivet", 4.0, 0.0, -32.5, (1.0, 3.0, 1.0), bronze_high)
    add_y_pair("socket_rivet", 0.0, 4.0, -32.5, (3.0, 1.0, 1.0), bronze_high)
    add("socket_neck_core", (0.0, 0.0, -29.5), (3.0, 5.0, 3.0), bronze_dark)
    add_x_pair("socket_neck", 2.0, 0.0, -29.5, (1.0, 5.0, 3.0), bronze_high)

    # Four-sided collars and leather wraps are exterior face-attached to the shaft.
    add_x_pair("grip_fore_collar", 2.5, 0.0, -8.0, (2.0, 3.0, 2.0), bronze_high)
    add_y_pair("grip_fore_collar", 0.0, 2.5, -8.0, (7.0, 2.0, 2.0), bronze_high)
    add_x_pair("grip_fore", 2.0, 0.0, -4.0, (1.0, 3.0, 6.0), leather_dark)
    add_y_pair("grip_fore", 0.0, 2.0, -4.0, (5.0, 1.0, 6.0), leather_dark)
    add_x_pair("grip_center_band", 2.5, 0.0, 0.0, (2.0, 3.0, 2.0), bronze_high)
    add_y_pair("grip_center_band", 0.0, 2.5, 0.0, (7.0, 2.0, 2.0), bronze_high)
    add_x_pair("grip_rear", 2.0, 0.0, 4.0, (1.0, 3.0, 6.0), leather_mid)
    add_y_pair("grip_rear", 0.0, 2.0, 4.0, (5.0, 1.0, 6.0), leather_mid)
    add_x_pair("grip_end_band", 2.5, 0.0, 8.0, (2.0, 3.0, 2.0), bronze_high)
    add_y_pair("grip_end_band", 0.0, 2.5, 8.0, (7.0, 2.0, 2.0), bronze_high)

    add("butt_neck", (0.0, 0.0, 20.5), (5.0, 5.0, 1.0), bronze_dark)
    add("butt_cap_center", (0.0, 0.0, 21.5), (5.0, 9.0, 1.0), bronze_high)
    add_x_pair("butt_cap", 3.5, 0.0, 21.5, (2.0, 5.0, 1.0), bronze_dark)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_spear()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Spear envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
