from __future__ import annotations

"""Leather helmet — light scout soft-cap (clearly NOT the iron Nordic helm).

TARGET_ENVELOPE_PX = (16, 14, 14)
Identity vs iron: soft low crown, wide front brim, hanging ear flaps, chin strap.
NO horns, NO long steel nasal, NO eye-slit mask.

Axis: +Z up, +Y character front, X width. Scale: 1m = 32px.
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

MODEL_ID = "leather_helmet"
TARGET_ENVELOPE_PX = (16.0, 14.0, 14.0)
OUT_GLB = ROOT / "assets" / "meshes" / "armor" / "armor_voxel_leather_helmet.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_leather_helmet() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    leather_shadow = make_material("lh_shadow", (0.07, 0.03, 0.01, 1.0), roughness=0.95)
    leather_base = make_material("lh_base", (0.16, 0.08, 0.03, 1.0), roughness=0.88)
    leather_high = make_material("lh_high", (0.28, 0.15, 0.07, 1.0), roughness=0.78)
    strap = make_material("lh_strap", (0.05, 0.02, 0.01, 1.0), roughness=0.96)
    stitch = make_material("lh_stitch", (0.40, 0.30, 0.16, 1.0), roughness=0.85)
    buckle = make_material("lh_buckle", (0.34, 0.36, 0.40, 1.0), metallic=0.70, roughness=0.45)

    root = make_root("armor_voxel_leather_helmet")
    parts: list[bpy.types.Object] = []

    def add(name, center, size, mat):
        parts.append(box_px(name, center, size, mat))

    # Soft low crown (flatter than iron dome)
    crown_c = (0.0, 0.0, 4.0)
    crown_s = (12.0, 11.0, 6.0)
    add("crown_base", crown_c, crown_s, leather_base)
    add("crown_upper", (0.0, 0.0, 8.0), (10.0, 9.0, 2.0), leather_high)
    add("crown_seam", (0.0, 0.0, 9.5), (2.0, 7.0, 1.0), stitch)

    # Wide soft front brim via lip chain on +Y
    lip_s = (12.0, 2.0, 2.0)
    lip_c = exterior_plate_center(crown_c, (12.0, 11.0, 4.0), lip_s, "y", "pos")
    lip_c = (lip_c[0], lip_c[1], 2.0)
    add("front_lip", lip_c, lip_s, leather_shadow)
    brim_s = (14.0, 2.0, 2.0)
    brim_c = exterior_plate_center(lip_c, lip_s, brim_s, "y", "pos")
    add("front_brim", brim_c, brim_s, leather_high)

    # Ear flaps: side attach + hang down
    flap_attach_s = (2.0, 5.0, 4.0)
    flap_attach_l = exterior_plate_center(crown_c, crown_s, flap_attach_s, "x", "neg")
    flap_attach_r = exterior_plate_center(crown_c, crown_s, flap_attach_s, "x", "pos")
    add("ear_attach_left", flap_attach_l, flap_attach_s, leather_base)
    add("ear_attach_right", flap_attach_r, flap_attach_s, leather_base)
    hang_s = (2.0, 4.0, 4.0)
    hang_l = (
        flap_attach_l[0],
        flap_attach_l[1],
        flap_attach_l[2] - (flap_attach_s[2] + hang_s[2]) * 0.5,
    )
    hang_r = (
        flap_attach_r[0],
        flap_attach_r[1],
        flap_attach_r[2] - (flap_attach_s[2] + hang_s[2]) * 0.5,
    )
    add("ear_flap_left", hang_l, hang_s, leather_shadow)
    add("ear_flap_right", hang_r, hang_s, leather_shadow)

    # Nape soft panel
    nape_s = (10.0, 2.0, 4.0)
    nape_c = exterior_plate_center((0.0, 0.0, 3.0), (12.0, 11.0, 4.0), nape_s, "y", "neg")
    add("nape_panel", nape_c, nape_s, leather_shadow)

            # Chin strap chain: ear hang bottoms → forward cups → front bridge → buckle
    chin_side_s = (2.0, 2.0, 2.0)
    chin_l = (
        hang_l[0],
        hang_l[1],
        hang_l[2] - (hang_s[2] + chin_side_s[2]) * 0.5,
    )
    chin_r = (
        hang_r[0],
        hang_r[1],
        hang_r[2] - (hang_s[2] + chin_side_s[2]) * 0.5,
    )
    add("strap_left", chin_l, chin_side_s, strap)
    add("strap_right", chin_r, chin_side_s, strap)
    cup_s = (2.0, 2.0, 2.0)
    cup_l = exterior_plate_center(chin_l, chin_side_s, cup_s, "y", "pos")
    cup_r = exterior_plate_center(chin_r, chin_side_s, cup_s, "y", "pos")
    add("strap_cup_left", cup_l, cup_s, strap)
    add("strap_cup_right", cup_r, cup_s, strap)
    # Wide front bridge face-contacts both cups on +Y
    bridge_s = (16.0, 2.0, 2.0)
    bridge_c = (0.0, cup_l[1] + (cup_s[1] + bridge_s[1]) * 0.5, cup_l[2])
    add("strap_front", bridge_c, bridge_s, strap)
    buckle_s = (3.0, 1.0, 2.0)
    buckle_c = exterior_plate_center(bridge_c, bridge_s, buckle_s, "y", "pos")
    add("strap_buckle", buckle_c, buckle_s, buckle)

# Stitch marks on ear attaches (outer)
    st_s = (1.0, 1.0, 1.0)
    st_l = exterior_plate_center(flap_attach_l, flap_attach_s, st_s, "x", "neg")
    st_r = exterior_plate_center(flap_attach_r, flap_attach_s, st_s, "x", "pos")
    add("stitch_left", st_l, st_s, stitch)
    add("stitch_right", st_r, st_s, stitch)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, _parts = build_leather_helmet()
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dims = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print(f"Leather helmet envelope: {dims[0]:.1f} x {dims[1]:.1f} x {dims[2]:.1f} px")
    print(f"Target envelope W/H/D: {TARGET_ENVELOPE_PX}")


if __name__ == "__main__":
    main()
