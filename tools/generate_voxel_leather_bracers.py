from __future__ import annotations

"""Leather bracers — light-set forearm guards (single mesh, L/R mirrored at mount).

TARGET_ENVELOPE_PX = (9, 12, 9)
Axis: +Z forearm length, +Y outer guard. Scale 1m=32px.
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

MODEL_ID = "leather_bracers"
TARGET_ENVELOPE_PX = (9.0, 12.0, 9.0)
OUT_GLB = ROOT / "assets" / "meshes" / "armor" / "armor_voxel_leather_bracers.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_leather_bracers() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    leather_shadow = make_material("lb_shadow", (0.06, 0.02, 0.01, 1.0), roughness=0.95)
    leather_base = make_material("lb_base", (0.15, 0.07, 0.03, 1.0), roughness=0.88)
    leather_high = make_material("lb_high", (0.26, 0.14, 0.06, 1.0), roughness=0.80)
    strap = make_material("lb_strap", (0.05, 0.02, 0.01, 1.0), roughness=0.96)
    rivet = make_material("lb_rivet", (0.32, 0.34, 0.38, 1.0), metallic=0.7, roughness=0.45)

    root = make_root("armor_voxel_leather_bracers")
    parts: list[bpy.types.Object] = []

    def add(name, center, size, mat):
        parts.append(box_px(name, center, size, mat))

    core_c = (0.0, 0.0, 0.0)
    core_s = (7.0, 7.0, 10.0)
    add("cuff_core", core_c, core_s, leather_base)
    add("cuff_rim_top", (0.0, 0.0, 5.5), (9.0, 9.0, 1.0), leather_high)
    add("cuff_rim_bot", (0.0, 0.0, -5.5), (9.0, 9.0, 1.0), leather_shadow)

    guard_size = (5.0, 2.0, 8.0)
    guard_c = exterior_plate_center(core_c, core_s, guard_size, "y", "pos")
    add("guard_plate", guard_c, guard_size, leather_high)

    ridge_size = (3.0, 1.0, 5.0)
    ridge_c = exterior_plate_center(guard_c, guard_size, ridge_size, "y", "pos")
    add("guard_ridge", ridge_c, ridge_size, leather_shadow)

    for tag, z in (("upper", 3.0), ("lower", -2.0)):
        side = (1.0, 5.0, 1.0)
        host_c = (0.0, 0.0, z)
        host_s = (7.0, 7.0, 1.0)
        add(f"strap_{tag}_l", exterior_plate_center(host_c, host_s, side, "x", "neg"), side, strap)
        add(f"strap_{tag}_r", exterior_plate_center(host_c, host_s, side, "x", "pos"), side, strap)
        back = (5.0, 1.0, 1.0)
        add(f"strap_{tag}_back", exterior_plate_center(host_c, host_s, back, "y", "neg"), back, strap)

    rivet_size = (1.0, 1.0, 1.0)
    rivet_y = exterior_plate_center(guard_c, guard_size, rivet_size, "y", "pos")[1]
    # Keep clear of ridge x-span (±1.5) and ridge z-span (±2.5)
    add("rivet_a", (-2.0, rivet_y, 3.5), rivet_size, rivet)
    add("rivet_b", (2.0, rivet_y, 3.5), rivet_size, rivet)
    add("rivet_c", (-2.0, rivet_y, -3.5), rivet_size, rivet)
    add("rivet_d", (2.0, rivet_y, -3.5), rivet_size, rivet)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_leather_bracers()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dims = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print(f"Leather bracers envelope: {dims[0]:.1f} x {dims[1]:.1f} x {dims[2]:.1f} px")
    print(f"Target envelope: {TARGET_ENVELOPE_PX}")


if __name__ == "__main__":
    main()
