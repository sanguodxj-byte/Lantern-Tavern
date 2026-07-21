from __future__ import annotations

"""Generate the dedicated symmetric dwarven battle-axe voxel model."""

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


MODEL_ID = "axe"
WIDTH_PX = 23.0
DEPTH_PX = 7.0
LENGTH_PX = 45.0

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_axe.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_axe() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a symmetric 23 x 7 x 45px double-bit dwarven battle axe."""
    iron_dark = make_material(
        "axe_iron_dark", (0.15, 0.18, 0.19, 1.0), metallic=0.74, roughness=0.48
    )
    steel_root = make_material(
        "axe_steel_root", (0.28, 0.34, 0.37, 1.0), metallic=0.76, roughness=0.40
    )
    steel_mid = make_material(
        "axe_steel_mid", (0.46, 0.56, 0.61, 1.0), metallic=0.82, roughness=0.32
    )
    steel_outer = make_material(
        "axe_steel_outer", (0.62, 0.71, 0.75, 1.0), metallic=0.84, roughness=0.27
    )
    steel_edge = make_material(
        "axe_steel_edge", (0.80, 0.87, 0.89, 1.0), metallic=0.90, roughness=0.22
    )
    bronze = make_material(
        "axe_old_bronze", (0.58, 0.34, 0.11, 1.0), metallic=0.62, roughness=0.43
    )
    ash_wood = make_material(
        "axe_ash_wood", (0.40, 0.20, 0.075, 1.0), roughness=0.86
    )
    leather_dark = make_material(
        "axe_leather_dark", (0.18, 0.035, 0.025, 1.0), roughness=0.91
    )
    leather_mid = make_material(
        "axe_leather_mid", (0.39, 0.085, 0.045, 1.0), roughness=0.85
    )

    root = make_root("weapons_voxel_axe")
    parts: list[bpy.types.Object] = []

    def add(
        name: str,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        parts.append(box_px(name, center, size, material))

    # The socket owns the full 7px depth; paired cheek plates explain that depth.
    add("head_socket_core", (0.0, 0.0, -16.0), (5.0, 5.0, 10.0), iron_dark)
    add("head_cheek_front", (0.0, 3.0, -16.0), (3.0, 1.0, 6.0), bronze)
    add("head_cheek_back", (0.0, -3.0, -16.0), (3.0, 1.0, 6.0), bronze)
    add("head_crown", (0.0, 0.0, -21.5), (3.0, 5.0, 1.0), iron_dark)

    # Both blades use the same stepped crescent silhouette and material ramp.
    add("blade_root_left", (-4.0, 0.0, -16.0), (3.0, 5.0, 6.0), steel_root)
    add("blade_root_right", (4.0, 0.0, -16.0), (3.0, 5.0, 6.0), steel_root)
    add("blade_mid_left", (-7.0, 0.0, -16.0), (3.0, 5.0, 8.0), steel_mid)
    add("blade_mid_right", (7.0, 0.0, -16.0), (3.0, 5.0, 8.0), steel_mid)
    add("blade_outer_left", (-9.5, 0.0, -16.0), (2.0, 3.0, 10.0), steel_outer)
    add("blade_outer_right", (9.5, 0.0, -16.0), (2.0, 3.0, 10.0), steel_outer)
    add("blade_edge_left", (-11.0, 0.0, -16.0), (1.0, 1.0, 8.0), steel_edge)
    add("blade_edge_right", (11.0, 0.0, -16.0), (1.0, 1.0, 8.0), steel_edge)

    # End-to-end haft and leather sections keep every band face-attached.
    add("haft_neck", (0.0, 0.0, -10.0), (3.0, 3.0, 2.0), bronze)
    add("haft_upper", (0.0, 0.0, -4.5), (3.0, 3.0, 9.0), ash_wood)
    add("grip_band_upper", (0.0, 0.0, 0.5), (5.0, 5.0, 1.0), bronze)
    add("grip_upper", (0.0, 0.0, 4.5), (3.0, 3.0, 7.0), leather_dark)
    add("grip_band_center", (0.0, 0.0, 8.5), (5.0, 5.0, 1.0), bronze)
    add("grip_lower", (0.0, 0.0, 13.0), (3.0, 3.0, 8.0), leather_mid)
    add("grip_band_lower", (0.0, 0.0, 17.5), (5.0, 5.0, 1.0), bronze)
    add("haft_butt", (0.0, 0.0, 20.0), (3.0, 3.0, 4.0), ash_wood)
    add("pommel_cap", (0.0, 0.0, 22.5), (5.0, 5.0, 1.0), bronze)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_axe()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Axe envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
