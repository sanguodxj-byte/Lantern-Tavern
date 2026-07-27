from __future__ import annotations

"""Leather armor — light-set body cuirass.

TARGET_ENVELOPE_PX = (22, 26, 14)  # W x H x D
Player torso ~12x12x9 with shoulders ~18–20 wide; cuirass reads clearly larger.

Axis: +Z up, +Y character front, X width.
Barony stepped masses: shoulder → chest → waist → skirt, pauldrons, dual-depth breast.
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
    make_pixel_material,
    make_root,
    parent_parts,
    render_true_3d_views,
    reset_scene,
)

MODEL_ID = "leather_armor"
TARGET_ENVELOPE_PX = (22.0, 26.0, 14.0)
OUT_GLB = ROOT / "assets" / "meshes" / "armor" / "armor_voxel_leather_armor.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_leather_armor() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    leather_shadow = make_material(
        "leather_armor_shadow", (0.09, 0.04, 0.02, 1.0), metallic=0.0, roughness=0.92
    )
    leather_base = make_material(
        "leather_armor_base", (0.16, 0.08, 0.03, 1.0), metallic=0.0, roughness=0.85
    )
    leather_highlight = make_material(
        "leather_armor_highlight", (0.26, 0.14, 0.06, 1.0), metallic=0.0, roughness=0.78
    )
    iron_rivet = make_material(
        "leather_armor_iron_rivet", (0.35, 0.38, 0.42, 1.0), metallic=0.85, roughness=0.35
    )
    strap_material = make_material(
        "leather_armor_strap", (0.05, 0.02, 0.01, 1.0), metallic=0.0, roughness=0.96
    )
    leather_texture = make_pixel_material(
        "leather_armor_texture",
        (
            "dddmdddm",
            "dmllmllm",
            "dlmmlmmd",
            "dmlmmlmd",
            "dmllmllm",
            "dddmdddm",
            "dmllmllm",
            "dlmmlmmd",
        ),
        {
            "d": (0.08, 0.04, 0.02, 1.0),
            "m": (0.14, 0.07, 0.03, 1.0),
            "l": (0.22, 0.11, 0.05, 1.0),
        },
        roughness=0.88,
    )

    root = make_root("armor_voxel_leather_armor")
    parts: list[bpy.types.Object] = []

    def add(name, center, size, mat):
        parts.append(box_px(name, center, size, mat))

    def add_x_pair(prefix, x, y, z, size, mat):
        add(f"{prefix}_left", (-x, y, z), size, mat)
        add(f"{prefix}_right", (x, y, z), size, mat)

    # Core stepped body (Z face-contact stack) — primary volume
    add("neck_guard", (0.0, 0.0, 11.0), (10.0, 6.0, 4.0), leather_shadow)
    add("shoulder_band", (0.0, 0.0, 6.0), (20.0, 10.0, 6.0), leather_texture)
    add("chest_band", (0.0, 0.0, 0.0), (18.0, 10.0, 6.0), leather_texture)
    add("waist_band", (0.0, 0.0, -5.5), (16.0, 8.0, 5.0), leather_base)
    add("skirt_band", (0.0, 0.0, -10.5), (14.0, 8.0, 5.0), leather_shadow)

    # Front dual-depth plates (+Y)
    add("breast_upper", (0.0, 6.0, 6.0), (16.0, 2.0, 4.0), leather_highlight)
    add("breast_mid", (0.0, 6.0, 0.0), (14.0, 2.0, 4.0), leather_highlight)
    add("breast_upper_outer", (0.0, 8.0, 6.0), (12.0, 2.0, 4.0), leather_base)
    add("breast_mid_outer", (0.0, 8.0, 0.0), (10.0, 2.0, 4.0), leather_base)
    add("belt_front", (0.0, 5.0, -5.5), (14.0, 2.0, 3.0), strap_material)
    add("skirt_front", (0.0, 5.0, -10.0), (12.0, 2.0, 4.0), leather_shadow)

    # Back dual-depth (-Y)
    add("back_shoulder", (0.0, -6.0, 6.0), (16.0, 2.0, 4.0), leather_highlight)
    add("back_mid", (0.0, -6.0, 0.0), (14.0, 2.0, 4.0), leather_highlight)
    add("back_shoulder_outer", (0.0, -8.0, 6.0), (12.0, 2.0, 4.0), leather_base)
    add("back_mid_outer", (0.0, -8.0, 0.0), (10.0, 2.0, 4.0), leather_base)
    add("belt_back", (0.0, -5.0, -5.5), (14.0, 2.0, 3.0), strap_material)
    add("skirt_back", (0.0, -5.0, -10.0), (12.0, 2.0, 4.0), leather_shadow)

    # Pauldrons ±X — real shoulder volume
    add_x_pair("pauldron_base", 12.0, 0.0, 6.0, (4.0, 10.0, 6.0), leather_base)
    add_x_pair("pauldron_cap", 12.0, 0.0, 10.0, (4.0, 6.0, 2.0), leather_highlight)

    # Side breaks
    add_x_pair("side_trim", 9.5, 0.0, 0.0, (1.0, 8.0, 4.0), leather_highlight)

    # Neck trim + buckle identity
    add("neck_trim", (0.0, 3.5, 11.0), (8.0, 1.0, 2.0), leather_highlight)
    add("belt_buckle", (0.0, 6.5, -5.5), (3.0, 1.0, 3.0), iron_rivet)

    # Rivets on breast outer
    add_x_pair("rivet_breast", 4.0, 9.5, 6.0, (1.0, 1.0, 1.0), iron_rivet)
    add_x_pair("rivet_waist", 3.0, 9.5, 0.0, (1.0, 1.0, 1.0), iron_rivet)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_leather_armor()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dims = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print(f"Leather armor envelope: {dims[0]:.1f} x {dims[1]:.1f} x {dims[2]:.1f} px")
    print(f"Target envelope: {TARGET_ENVELOPE_PX}")


if __name__ == "__main__":
    main()
