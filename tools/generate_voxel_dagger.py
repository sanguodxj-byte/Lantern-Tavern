from __future__ import annotations

"""Generate the dedicated symmetric leaf-bladed voxel dagger."""

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


MODEL_ID = "dagger"
WIDTH_PX = 11.0
DEPTH_PX = 5.0
LENGTH_PX = 23.0

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_dagger.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_dagger() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a symmetric 11 x 5 x 23px leaf dagger with a paired venom ridge."""
    dark_alloy = make_material(
        "dagger_dark_alloy", (0.10, 0.13, 0.15, 1.0), metallic=0.78, roughness=0.48
    )
    cold_steel = make_material(
        "dagger_cold_steel", (0.43, 0.54, 0.59, 1.0), metallic=0.82, roughness=0.34
    )
    bright_steel = make_material(
        "dagger_bright_steel", (0.79, 0.87, 0.90, 1.0), metallic=0.88, roughness=0.23
    )
    venom_green = make_material(
        "dagger_venom_green", (0.055, 0.29, 0.10, 1.0), roughness=0.76
    )
    blackened_bronze = make_material(
        "dagger_blackened_bronze", (0.30, 0.17, 0.055, 1.0), metallic=0.61, roughness=0.49
    )
    old_brass = make_material(
        "dagger_old_brass", (0.64, 0.40, 0.10, 1.0), metallic=0.67, roughness=0.39
    )
    wine_leather_dark = make_material(
        "dagger_wine_leather_dark", (0.18, 0.022, 0.035, 1.0), roughness=0.93
    )
    wine_leather_mid = make_material(
        "dagger_wine_leather_mid", (0.39, 0.052, 0.070, 1.0), roughness=0.86
    )

    root = make_root("weapons_voxel_dagger")
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

    # Keep the long blade core first for the current runtime collision fallback.
    add("blade_anchor_core", (0.0, 0.0, -7.0), (3.0, 3.0, 12.0), dark_alloy)
    add_x_pair("blade_ricasso_edge", 2.0, 0.0, -2.0, (1.0, 3.0, 2.0), cold_steel)
    add_x_pair("blade_forte_edge", 2.5, 0.0, -5.0, (2.0, 3.0, 4.0), cold_steel)
    add_x_pair("blade_mid_edge", 2.0, 0.0, -9.0, (1.0, 3.0, 4.0), bright_steel)
    add("blade_taper", (0.0, 0.0, -13.5), (3.0, 3.0, 1.0), cold_steel)
    add("blade_tip", (0.0, 0.0, -14.5), (1.0, 3.0, 1.0), bright_steel)
    add("venom_ridge_front", (0.0, 2.0, -7.0), (1.0, 1.0, 12.0), venom_green)
    add("venom_ridge_back", (0.0, -2.0, -7.0), (1.0, 1.0, 12.0), venom_green)

    add("guard_center", (0.0, 0.0, 0.0), (5.0, 5.0, 2.0), blackened_bronze)
    add_x_pair("guard_arm", 3.5, 0.0, 0.0, (2.0, 3.0, 1.0), blackened_bronze)
    add_x_pair("guard_tip", 5.0, 0.0, 0.0, (1.0, 3.0, 3.0), bright_steel)

    add("grip_collar", (0.0, 0.0, 1.5), (4.0, 4.0, 1.0), old_brass)
    add("grip_upper", (0.0, 0.0, 3.0), (3.0, 3.0, 2.0), wine_leather_dark)
    add("grip_band", (0.0, 0.0, 4.5), (4.0, 4.0, 1.0), old_brass)
    add("grip_lower", (0.0, 0.0, 6.0), (3.0, 3.0, 2.0), wine_leather_mid)
    add("pommel_cap", (0.0, 0.0, 7.5), (5.0, 5.0, 1.0), old_brass)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_dagger()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Dagger envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
