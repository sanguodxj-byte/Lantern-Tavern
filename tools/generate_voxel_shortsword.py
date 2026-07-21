from __future__ import annotations

"""Generate the dedicated shortsword voxel model and true 3D previews."""

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


MODEL_ID = "shortsword"
WIDTH_PX = 15.0
DEPTH_PX = 6.0
LENGTH_PX = 33.0

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_shortsword.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_shortsword() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a symmetric 15 x 6 x 33px lantern-leaf shortsword.

    Pixel layout along Z:
      blade -23..-1, guard -2..1, grip 1..7, pommel 7..10.
    The blade grows 3 -> 5 -> 7px before tapering 5 -> 3 -> 1px. Blade flats,
    edges and exterior ridges meet by faces; no highlight box is embedded.
    """
    steel_flat = make_material(
        "shortsword_steel_flat", (0.47, 0.55, 0.61, 1.0), metallic=0.78, roughness=0.34
    )
    steel_edge = make_material(
        "shortsword_steel_edge", (0.78, 0.84, 0.87, 1.0), metallic=0.84, roughness=0.24
    )
    steel_ridge = make_material(
        "shortsword_steel_ridge", (0.83, 0.86, 0.87, 1.0), metallic=0.92, roughness=0.22
    )
    guard_bronze = make_material(
        "shortsword_guard_bronze", (0.52, 0.29, 0.10, 1.0), metallic=0.72, roughness=0.4
    )
    guard_highlight = make_material(
        "shortsword_guard_highlight", (0.76, 0.48, 0.16, 1.0), metallic=0.68, roughness=0.34
    )
    leather = make_material(
        "shortsword_leather", (0.22, 0.045, 0.025, 1.0), roughness=0.88
    )
    leather_highlight = make_material(
        "shortsword_leather_highlight", (0.42, 0.10, 0.04, 1.0), roughness=0.82
    )
    ember_enamel = make_material(
        "shortsword_ember_enamel", (0.95, 0.38, 0.045, 1.0), metallic=0.10, roughness=0.35
    )

    root = make_root("weapons_voxel_shortsword")
    parts: list[bpy.types.Object] = []

    def add(
        name: str,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        parts.append(box_px(name, center, size, material))

    # Blade sections partition each cross-section into center and mirrored wings.
    add("blade_ricasso", (0.0, 0.0, -2.5), (3.0, 2.0, 3.0), steel_flat)
    add("blade_near_center", (0.0, 0.0, -6.0), (1.0, 2.0, 4.0), steel_flat)
    add("blade_near_left", (-1.5, 0.0, -6.0), (2.0, 2.0, 4.0), steel_edge)
    add("blade_near_right", (1.5, 0.0, -6.0), (2.0, 2.0, 4.0), steel_edge)
    add("blade_belly_center", (0.0, 0.0, -10.5), (1.0, 2.0, 5.0), steel_flat)
    add("blade_belly_left", (-2.0, 0.0, -10.5), (3.0, 2.0, 5.0), steel_edge)
    add("blade_belly_right", (2.0, 0.0, -10.5), (3.0, 2.0, 5.0), steel_edge)
    add("blade_upper_center", (0.0, 0.0, -15.0), (1.0, 2.0, 4.0), steel_flat)
    add("blade_upper_left", (-1.5, 0.0, -15.0), (2.0, 2.0, 4.0), steel_edge)
    add("blade_upper_right", (1.5, 0.0, -15.0), (2.0, 2.0, 4.0), steel_edge)
    add("blade_taper_center", (0.0, 0.0, -18.5), (1.0, 2.0, 3.0), steel_flat)
    add("blade_taper_left", (-1.0, 0.0, -18.5), (1.0, 2.0, 3.0), steel_edge)
    add("blade_taper_right", (1.0, 0.0, -18.5), (1.0, 2.0, 3.0), steel_edge)
    add("blade_tip", (0.0, 0.0, -21.5), (1.0, 2.0, 3.0), steel_edge)

    # A paired exterior ridge gives the leaf blade depth without interpenetration.
    add("blade_ridge_front", (0.0, 1.5, -12.0), (1.0, 1.0, 16.0), steel_ridge)
    add("blade_ridge_back", (0.0, -1.5, -12.0), (1.0, 1.0, 16.0), steel_ridge)

    # Mirror-authored quillons and paired front/back ember studs.
    add("guard_center", (0.0, 0.0, 0.0), (5.0, 4.0, 2.0), guard_bronze)
    add("guard_left", (-4.5, 0.0, 0.5), (4.0, 3.0, 1.0), guard_bronze)
    add("guard_right", (4.5, 0.0, 0.5), (4.0, 3.0, 1.0), guard_bronze)
    add("guard_tip_left", (-7.0, 0.0, -0.5), (1.0, 3.0, 3.0), guard_highlight)
    add("guard_tip_right", (7.0, 0.0, -0.5), (1.0, 3.0, 3.0), guard_highlight)
    add("ember_stud_front", (0.0, 2.5, 0.0), (1.0, 1.0, 1.0), ember_enamel)
    add("ember_stud_back", (0.0, -2.5, 0.0), (1.0, 1.0, 1.0), ember_enamel)

    # Grip and pommel are end-to-end volumes rather than surface overlays.
    add("grip_collar", (0.0, 0.0, 1.5), (4.0, 4.0, 1.0), guard_highlight)
    add("grip_upper", (0.0, 0.0, 3.0), (3.0, 3.0, 2.0), leather)
    add("grip_band", (0.0, 0.0, 4.5), (3.5, 3.5, 1.0), leather_highlight)
    add("grip_lower", (0.0, 0.0, 6.0), (3.0, 3.0, 2.0), leather)
    add("pommel_shoulders", (0.0, 0.0, 8.0), (5.0, 5.0, 2.0), guard_bronze)
    add("pommel_cap", (0.0, 0.0, 9.5), (3.0, 3.0, 1.0), guard_highlight)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_shortsword()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Shortsword envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
