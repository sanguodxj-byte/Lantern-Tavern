from __future__ import annotations

"""Iron bracers — heavy forearm lames. TARGET_ENVELOPE_PX = (10, 13, 10)."""

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

MODEL_ID = "iron_bracers"
TARGET_ENVELOPE_PX = (10.0, 13.0, 10.0)
OUT_GLB = ROOT / "assets" / "meshes" / "armor" / "armor_voxel_iron_bracers.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_iron_bracers():
    iron_shadow = make_material("ib_shadow", (0.12, 0.14, 0.17, 1.0), metallic=0.82, roughness=0.48)
    iron_base = make_material("ib_base", (0.22, 0.26, 0.30, 1.0), metallic=0.85, roughness=0.40)
    iron_high = make_material("ib_high", (0.45, 0.50, 0.55, 1.0), metallic=0.90, roughness=0.28)
    leather = make_material("ib_leather", (0.10, 0.05, 0.02, 1.0), roughness=0.92)
    rivet = make_material("ib_rivet", (0.38, 0.40, 0.44, 1.0), metallic=0.8, roughness=0.35)

    root = make_root("armor_voxel_iron_bracers")
    parts = []

    def add(name, center, size, mat):
        parts.append(box_px(name, center, size, mat))

    core_c = (0.0, 0.0, 0.0)
    core_s = (7.0, 7.0, 11.0)
    add("underwrap", core_c, core_s, leather)
    add("rim_top", (0.0, 0.0, 6.0), (10.0, 10.0, 1.0), iron_high)
    add("rim_bot", (0.0, 0.0, -6.0), (10.0, 10.0, 1.0), iron_shadow)

    plates = []
    for name, z, h, mat in [
        ("plate_upper", 3.0, 4.0, iron_high),
        ("plate_mid", 0.0, 2.0, iron_base),
        ("plate_lower", -3.0, 4.0, iron_base),
    ]:
        sz = (6.0, 2.0, h)
        c = exterior_plate_center(core_c, core_s, sz, "y", "pos")
        c = (0.0, c[1], z)
        add(name, c, sz, mat)
        plates.append((c, sz))

    band = (1.0, 5.0, 9.0)
    add("band_left", exterior_plate_center(core_c, core_s, band, "x", "neg"), band, iron_shadow)
    add("band_right", exterior_plate_center(core_c, core_s, band, "x", "pos"), band, iron_shadow)

    mid_c, mid_s = plates[1]
    hinge = (2.0, 1.0, 7.0)
    hinge_c = exterior_plate_center(mid_c, mid_s, hinge, "y", "pos")
    add("hinge", (0.0, hinge_c[1], 0.0), hinge, iron_shadow)

    rv = (1.0, 1.0, 1.0)
    up_c, up_s = plates[0]
    lo_c, lo_s = plates[2]
    ry_up = exterior_plate_center(up_c, up_s, rv, "y", "pos")[1]
    ry_lo = exterior_plate_center(lo_c, lo_s, rv, "y", "pos")[1]
    add("rivet_a", (-2.0, ry_up, 3.0), rv, rivet)
    add("rivet_b", (2.0, ry_lo, -3.0), rv, rivet)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main():
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_iron_bracers()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dims = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print(f"Iron bracers envelope: {dims[0]:.1f} x {dims[1]:.1f} x {dims[2]:.1f} px")


if __name__ == "__main__":
    main()
