from __future__ import annotations

"""Iron boots — heavy sabatons.

TARGET_ENVELOPE_PX = (10, 14, 12)
Toe -Y, +Z up. Scale 1m=32px.
"""

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
    bounds_size_px,
    box_px,
    export_glb,
    make_material,
    make_root,
    parent_parts,
    render_true_3d_views,
    reset_scene,
)

MODEL_ID = "iron_boots"
TARGET_ENVELOPE_PX = (10.0, 14.0, 12.0)
OUT_GLB = ROOT / "assets" / "meshes" / "armor" / "armor_voxel_iron_boots.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_iron_boots() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    iron_shadow = make_material("ibt_shadow", (0.12, 0.14, 0.17, 1.0), metallic=0.82, roughness=0.48)
    iron_base = make_material("ibt_base", (0.22, 0.26, 0.30, 1.0), metallic=0.85, roughness=0.40)
    iron_high = make_material("ibt_high", (0.45, 0.50, 0.55, 1.0), metallic=0.90, roughness=0.28)
    sole_mat = make_material("ibt_sole", (0.05, 0.04, 0.03, 1.0), roughness=0.98)
    leather = make_material("ibt_leather", (0.10, 0.05, 0.02, 1.0), roughness=0.92)

    root = make_root("armor_voxel_iron_boots")
    parts: list[bpy.types.Object] = []

    def add(name, center, size, mat):
        parts.append(box_px(name, center, size, mat))

    add("sole", (0.0, -0.5, 1.0), (9.0, 13.0, 2.0), sole_mat)
    add("sabaton", (0.0, -1.0, 3.5), (9.0, 11.0, 3.0), iron_base)
    add("toe_plate", (0.0, -7.0, 3.5), (9.0, 1.0, 3.0), iron_high)
    add("vamp_plate", (0.0, -2.0, 5.5), (8.0, 8.0, 1.0), iron_high)
    add("ankle_shell", (0.0, 0.5, 7.0), (9.0, 8.0, 2.0), iron_base)
    add("shin_plate", (0.0, -2.0, 9.5), (8.0, 3.0, 3.0), iron_high)
    add("cuff_leather", (0.0, 0.5, 11.5), (9.0, 7.0, 1.0), leather)
    add("heel_plate", (0.0, 5.5, 3.5), (9.0, 2.0, 3.0), iron_shadow)
    add("side_lame_left", (-5.0, 0.0, 5.5), (1.0, 6.0, 5.0), iron_shadow)
    add("side_lame_right", (5.0, 0.0, 5.5), (1.0, 6.0, 5.0), iron_shadow)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_iron_boots()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dims = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print(f"Iron boots envelope: {dims[0]:.1f} x {dims[1]:.1f} x {dims[2]:.1f} px")


if __name__ == "__main__":
    main()
