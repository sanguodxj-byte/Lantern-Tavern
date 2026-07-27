from __future__ import annotations

"""Leather boots — light-set footwear (single mesh, L/R at mount).

TARGET_ENVELOPE_PX = (9, 13, 11)  # W x length(Y) x height(Z)
Player foot ~5x9x5; boot is chunky and taller ("大一截").

Axis: +Z up, toe toward -Y (Foot bone mount maps Godot +Z toe after export), X width.
Origin near sole bottom center for ankle seating.
Scale: 1m = 32px.
"""

import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from voxel_overlap_guard import (  # noqa: E402
    assert_parts_no_positive_volume_overlap,
    assert_parts_voxel_assembly_valid,
    exterior_plate_center,
)
from voxel_single_model_cli import reject_target_override  # noqa: E402
from voxel_weapon_model_lib import (  # noqa: E402
    bounds_size_px,
    box_px,
    export_glb,
    make_material,
    make_root,
    parent_parts,
    render_true_3d_views,
    reset_scene,
)

MODEL_ID = "leather_boots"
TARGET_ENVELOPE_PX = (9.0, 13.0, 11.0)
OUT_GLB = ROOT / "assets" / "meshes" / "armor" / "armor_voxel_leather_boots.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_leather_boots() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    leather_shadow = make_material("lbt_shadow", (0.05, 0.02, 0.01, 1.0), roughness=0.96)
    leather_base = make_material("lbt_base", (0.14, 0.07, 0.03, 1.0), roughness=0.88)
    leather_high = make_material("lbt_high", (0.24, 0.13, 0.06, 1.0), roughness=0.80)
    sole_mat = make_material("lbt_sole", (0.04, 0.03, 0.02, 1.0), roughness=0.98)
    lace = make_material("lbt_lace", (0.32, 0.26, 0.16, 1.0), roughness=0.85)

    root = make_root("armor_voxel_leather_boots")
    parts: list[bpy.types.Object] = []

    def add(name, center, size, mat):
        parts.append(box_px(name, center, size, mat))

    # Sole slab — long axis Y, toe -Y
    add("sole", (0.0, -0.5, 1.0), (8.0, 12.0, 2.0), sole_mat)
    add("sole_toe", (0.0, -7.0, 1.0), (8.0, 1.0, 2.0), leather_shadow)

    # Vamp / upper over sole (face contact on +Z of sole)
    add("vamp", (0.0, -1.0, 4.0), (8.0, 10.0, 4.0), leather_base)
    add("toe_cap", (0.0, -6.5, 3.5), (8.0, 1.0, 3.0), leather_high)

    # Ankle shaft
    add("ankle", (0.0, 0.5, 7.0), (8.0, 7.0, 2.0), leather_base)
    add("cuff", (0.0, 0.5, 9.5), (9.0, 7.0, 3.0), leather_high)

    # Heel counter on +Y
    heel_size = (8.0, 2.0, 3.0)
    heel_c = exterior_plate_center((0.0, -1.0, 3.5), (8.0, 10.0, 3.0), heel_size, "y", "pos")
    add("heel", (0.0, 5.0, 3.5), heel_size, leather_shadow)

    # Side lace (semantic asymmetry on -X exterior)
    lace_size = (1.0, 5.0, 4.0)
    lace_c = exterior_plate_center((0.0, -1.0, 5.0), (8.0, 10.0, 4.0), lace_size, "x", "neg")
    add("lace_strip", lace_c, lace_size, lace)
    add("lace_knot", (lace_c[0] - 1.0, -2.0, 6.0), (1.0, 2.0, 2.0), leather_high)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_leather_boots()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dims = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print(f"Leather boots envelope: {dims[0]:.1f} x {dims[1]:.1f} x {dims[2]:.1f} px")
    print(f"Target envelope: {TARGET_ENVELOPE_PX}")


if __name__ == "__main__":
    main()
