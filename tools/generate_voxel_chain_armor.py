from __future__ import annotations

"""Chain armor — heavy-set hauberk body piece.

TARGET_ENVELOPE_PX = (24, 28, 14)
Leather foundation + iron ring outer layers, pauldrons, coif collar.
Axis: +Z up, +Y front. Scale 1m=32px.
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
    make_pixel_material,
    make_root,
    parent_parts,
    render_true_3d_views,
    reset_scene,
)

MODEL_ID = "chain_armor"
TARGET_ENVELOPE_PX = (24.0, 28.0, 14.0)
OUT_GLB = ROOT / "assets" / "meshes" / "armor" / "armor_voxel_chain_armor.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_chain_armor() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    iron_shadow = make_material(
        "chain_armor_iron_shadow", (0.10, 0.11, 0.14, 1.0), metallic=0.72, roughness=0.52
    )
    iron_base = make_material(
        "chain_armor_iron_base", (0.18, 0.20, 0.24, 1.0), metallic=0.78, roughness=0.44
    )
    iron_highlight = make_material(
        "chain_armor_iron_highlight", (0.36, 0.40, 0.46, 1.0), metallic=0.84, roughness=0.34
    )
    leather_foundation = make_pixel_material(
        "chain_armor_leather_foundation",
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
        roughness=0.90,
    )
    ring_pattern = make_pixel_material(
        "chain_armor_ring_pattern",
        (
            "ibibibib",
            "bibibibi",
            "ibibibib",
            "bibibibi",
            "ibibibib",
            "bibibibi",
            "ibibibib",
            "bibibibi",
        ),
        {
            "i": (0.28, 0.32, 0.38, 1.0),
            "b": (0.14, 0.16, 0.20, 1.0),
        },
        roughness=0.42,
        metallic=0.8,
    )

    root = make_root("armor_voxel_chain_armor")
    parts: list[bpy.types.Object] = []

    def add(name, center, size, mat):
        parts.append(box_px(name, center, size, mat))

    def add_x_pair(prefix, x, y, z, size, mat):
        add(f"{prefix}_left", (-x, y, z), size, mat)
        add(f"{prefix}_right", (x, y, z), size, mat)

    # Leather foundation stack (primary mass)
    add("foundation_neck", (0.0, 0.0, 12.0), (10.0, 6.0, 4.0), leather_foundation)
    add("foundation_shoulder", (0.0, 0.0, 7.0), (22.0, 10.0, 6.0), leather_foundation)
    add("foundation_chest", (0.0, 0.0, 1.0), (20.0, 10.0, 6.0), leather_foundation)
    add("foundation_waist", (0.0, 0.0, -5.0), (16.0, 8.0, 6.0), leather_foundation)
    add("foundation_skirt", (0.0, 0.0, -11.0), (14.0, 8.0, 6.0), leather_foundation)

    # Chain outer sheets front (+Y)
    add("chain_front_neck", (0.0, 3.5, 12.0), (8.0, 1.0, 4.0), ring_pattern)
    add("chain_front_shoulder", (0.0, 5.5, 7.0), (20.0, 1.0, 6.0), ring_pattern)
    add("chain_front_chest", (0.0, 5.5, 1.0), (18.0, 1.0, 6.0), ring_pattern)
    add("chain_front_waist", (0.0, 4.5, -5.0), (14.0, 1.0, 6.0), ring_pattern)
    add("chain_front_skirt", (0.0, 4.5, -11.0), (12.0, 1.0, 6.0), ring_pattern)

    # Chain outer sheets back (-Y)
    add("chain_back_neck", (0.0, -3.5, 12.0), (8.0, 1.0, 4.0), ring_pattern)
    add("chain_back_shoulder", (0.0, -5.5, 7.0), (20.0, 1.0, 6.0), ring_pattern)
    add("chain_back_chest", (0.0, -5.5, 1.0), (18.0, 1.0, 6.0), ring_pattern)
    add("chain_back_waist", (0.0, -4.5, -5.0), (14.0, 1.0, 6.0), ring_pattern)
    add("chain_back_skirt", (0.0, -4.5, -11.0), (12.0, 1.0, 6.0), ring_pattern)

    # Pauldrons
    add_x_pair("pauldron_base", 13.0, 0.0, 7.0, (4.0, 10.0, 6.0), iron_base)
    add_x_pair("pauldron_cap", 13.0, 0.0, 11.0, (4.0, 6.0, 2.0), iron_highlight)
    add_x_pair("pauldron_chain", 13.0, 0.0, 3.0, (3.0, 8.0, 2.0), ring_pattern)

    # Side chain breaks
    add_x_pair("side_chain", 10.5, 0.0, 1.0, (1.0, 8.0, 6.0), ring_pattern)

    # Coif collar accent
    add("coif_rim", (0.0, 0.0, 14.5), (12.0, 8.0, 1.0), iron_shadow)
    add("belt_iron", (0.0, 5.5, -5.0), (12.0, 1.0, 2.0), iron_highlight)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_chain_armor()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dims = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print(f"Chain armor envelope: {dims[0]:.1f} x {dims[1]:.1f} x {dims[2]:.1f} px")
    print(f"Target envelope: {TARGET_ENVELOPE_PX}")


if __name__ == "__main__":
    main()
