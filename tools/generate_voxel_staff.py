from __future__ import annotations

"""Generate the dedicated symmetric rune-core voxel staff."""

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
    make_pixel_material,
    make_root,
    parent_parts,
    render_true_3d_views,
    reset_scene,
)


MODEL_ID = "staff"
WIDTH_PX = 15.0
DEPTH_PX = 9.0
LENGTH_PX = 49.0

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_staff.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_staff() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a symmetric 15 x 9 x 49px rune-core staff."""
    oak = make_pixel_material(
        "staff_oak_grain",
        (
            "dmllllmd",
            "mlddddlm",
            "ldmmmmdl",
            "lmdmmdml",
            "lmdmmdml",
            "ldmmmmdl",
            "mlddddlm",
            "dmllllmd",
        ),
        {
            "d": (0.16, 0.052, 0.014, 1.0),
            "m": (0.34, 0.145, 0.035, 1.0),
            "l": (0.52, 0.255, 0.075, 1.0),
        },
        roughness=0.86,
    )
    wine_leather = make_pixel_material(
        "staff_wine_leather_crosshatch",
        (
            "dmmhhmmd",
            "mdhmmhdm",
            "mhmddmhm",
            "hmddddmh",
            "hmddddmh",
            "mhmddmhm",
            "mdhmmhdm",
            "dmmhhmmd",
        ),
        {
            "d": (0.12, 0.010, 0.018, 1.0),
            "m": (0.34, 0.028, 0.052, 1.0),
            "h": (0.54, 0.075, 0.105, 1.0),
        },
        roughness=0.94,
    )
    forged_iron = make_material(
        "staff_forged_iron", (0.13, 0.16, 0.17, 1.0), metallic=0.74, roughness=0.49
    )
    rune_metal = make_material(
        "staff_rune_metal", (0.27, 0.32, 0.33, 1.0), metallic=0.70, roughness=0.43
    )
    brass = make_material(
        "staff_old_brass", (0.59, 0.36, 0.085, 1.0), metallic=0.65, roughness=0.40
    )
    brass_bright = make_material(
        "staff_bright_brass", (0.78, 0.53, 0.14, 1.0), metallic=0.69, roughness=0.34
    )
    crystal = make_pixel_material(
        "staff_magic_core_runes",
        (
            "dddddddd",
            "ddmmmmdd",
            "dmhhhhmd",
            "dmhllhmd",
            "dmhllhmd",
            "dmhhhhmd",
            "ddmmmmdd",
            "dddddddd",
        ),
        {
            "d": (0.010, 0.24, 0.23, 1.0),
            "m": (0.020, 0.58, 0.52, 1.0),
            "h": (0.08, 0.90, 0.78, 1.0),
            "l": (0.48, 1.00, 0.88, 1.0),
        },
        roughness=0.22,
        emission=1.8,
    )
    crystal_high = make_pixel_material(
        "staff_magic_crown_facets",
        (
            "dmmhhmmd",
            "mmhllhmm",
            "mhllllhm",
            "hllhhllh",
            "hllhhllh",
            "mhllllhm",
            "mmhllhmm",
            "dmmhhmmd",
        ),
        {
            "d": (0.015, 0.32, 0.29, 1.0),
            "m": (0.04, 0.69, 0.61, 1.0),
            "h": (0.20, 0.96, 0.82, 1.0),
            "l": (0.70, 1.00, 0.92, 1.0),
        },
        roughness=0.18,
        emission=2.4,
    )

    root = make_root("weapons_voxel_staff")
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
        depth: float,
        length: float,
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        add(f"{prefix}_front", (width, depth, length), size, material)
        add(f"{prefix}_back", (width, -depth, length), size, material)

    add("a_staff_spine_core", (0.0, 0.0, -0.5), (3.0, 3.0, 35.0), oak)
    add("head_socket", (0.0, 0.0, -20.0), (5.0, 5.0, 4.0), forged_iron)
    add("core_pedestal", (0.0, 0.0, -23.0), (3.0, 3.0, 2.0), brass)
    add("magic_core", (0.0, 0.0, -26.5), (5.0, 5.0, 5.0), crystal)
    add("core_crown", (0.0, 0.0, -30.0), (3.0, 3.0, 2.0), crystal_high)
    add_x_pair("rune_arm_inner", 4.0, 0.0, -26.5, (3.0, 3.0, 3.0), rune_metal)
    add_x_pair("rune_wing", 6.5, 0.0, -26.5, (2.0, 3.0, 5.0), brass_bright)
    add_y_pair("rune_arm", 0.0, 3.5, -26.5, (3.0, 2.0, 3.0), rune_metal)

    add_x_pair("rune_collar", 2.0, 0.0, -12.0, (1.0, 3.0, 1.0), brass)
    add_y_pair("rune_collar", 0.0, 2.0, -12.0, (3.0, 1.0, 1.0), brass)
    add_x_pair("grip_wrap_upper", 2.0, 0.0, 5.0, (1.0, 3.0, 6.0), wine_leather)
    add_y_pair("grip_wrap_upper", 0.0, 2.0, 5.0, (3.0, 1.0, 6.0), wine_leather)
    add_x_pair("grip_band", 2.0, 0.0, 8.5, (1.0, 3.0, 1.0), brass)
    add_y_pair("grip_band", 0.0, 2.0, 8.5, (3.0, 1.0, 1.0), brass)
    add_x_pair("grip_wrap_lower", 2.0, 0.0, 12.0, (1.0, 3.0, 6.0), wine_leather)
    add_y_pair("grip_wrap_lower", 0.0, 2.0, 12.0, (3.0, 1.0, 6.0), wine_leather)
    add("pommel_cap", (0.0, 0.0, 17.5), (5.0, 5.0, 1.0), forged_iron)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_staff()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Staff envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
