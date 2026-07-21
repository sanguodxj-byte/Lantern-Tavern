from __future__ import annotations

"""Generate the dedicated layered voxel grimoire.

The book is authored in pixel units first (1m = 32px).  It deliberately uses
separate face-contact boxes for the page block, covers, spine, bindings and
front rune assembly so the imported GLB remains inspectable as voxel parts.
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


MODEL_ID = "grimoire"
WIDTH_PX = 21.0
DEPTH_PX = 12.0
LENGTH_PX = 22.0

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_grimoire.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_grimoire() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a 20 x 10 x 22px standing grimoire with layered page and cover detail."""
    walnut_cover = make_pixel_material(
        "grimoire_walnut_cover",
        (
            "ddmmmmdd",
            "dmmmmlld",
            "mmmmmmmd",
            "mmllmmmm",
            "mmmmmmdd",
            "dmmmmmmm",
            "ddmmllmm",
            "ddmmmmdd",
        ),
        {
            "d": (0.075, 0.026, 0.016, 1.0),
            "m": (0.15, 0.050, 0.026, 1.0),
            "l": (0.24, 0.090, 0.043, 1.0),
        },
        roughness=0.88,
        tile_size_px=8.0,
    )
    parchment_pages = make_pixel_material(
        "grimoire_parchment_pages",
        (
            "ddmmmmdd",
            "ddmmmmdd",
            "dddddddd",
            "dmmmllmd",
            "ddmmmmdd",
            "ddmmmmdd",
            "dddddddd",
            "dmmmllmd",
        ),
        {
            "d": (0.30, 0.23, 0.14, 1.0),
            "m": (0.45, 0.36, 0.22, 1.0),
            "l": (0.63, 0.53, 0.32, 1.0),
        },
        roughness=0.92,
        tile_size_px=8.0,
    )
    leather_spine = make_pixel_material(
        "grimoire_leather_spine",
        (
            "ddmmmmdd",
            "dmmmmhmd",
            "mmmmmmmd",
            "mmhmmmmm",
            "mmmmmmdd",
            "dmmmmmmm",
            "ddmmhmmm",
            "ddmmmmdd",
        ),
        {
            "d": (0.07, 0.012, 0.018, 1.0),
            "m": (0.18, 0.025, 0.040, 1.0),
            "h": (0.34, 0.060, 0.075, 1.0),
        },
        roughness=0.94,
        tile_size_px=8.0,
    )
    forged_iron = make_material(
        "grimoire_forged_iron",
        (0.12, 0.15, 0.17, 1.0),
        metallic=0.76,
        roughness=0.50,
    )
    binding_steel = make_material(
        "grimoire_binding_steel",
        (0.38, 0.43, 0.47, 1.0),
        metallic=0.90,
        roughness=0.32,
    )
    old_brass = make_material(
        "grimoire_old_brass_clasp",
        (0.58, 0.34, 0.075, 1.0),
        metallic=0.68,
        roughness=0.42,
    )
    rune_plate = make_pixel_material(
        "grimoire_rune_plate",
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
            "d": (0.025, 0.08, 0.14, 1.0),
            "m": (0.035, 0.20, 0.30, 1.0),
            "h": (0.07, 0.42, 0.52, 1.0),
            "l": (0.28, 0.82, 0.84, 1.0),
        },
        metallic=0.52,
        roughness=0.30,
        tile_size_px=8.0,
    )
    magic_glyph = make_pixel_material(
        "grimoire_magic_glyph",
        (
            "dddddddd",
            "ddmhhmdd",
            "dmhllhmd",
            "mhllllhm",
            "mhllllhm",
            "dmhllhmd",
            "ddmhhmdd",
            "dddddddd",
        ),
        {
            "d": (0.005, 0.11, 0.18, 1.0),
            "m": (0.015, 0.42, 0.62, 1.0),
            "h": (0.05, 0.78, 0.92, 1.0),
            "l": (0.62, 1.0, 1.0, 1.0),
        },
        roughness=0.18,
        emission=2.2,
        tile_size_px=2.0,
    )

    root = make_root("weapons_voxel_grimoire")
    parts: list[bpy.types.Object] = []

    def add(
        name: str,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        parts.append(box_px(name, center, size, material))

    # Primary book silhouette: the page block is clamped between two oversized covers.
    add("page_block", (0.0, 0.0, 0.0), (16.0, 6.0, 16.0), parchment_pages)
    add("lower_cover", (0.0, 0.0, -9.0), (20.0, 8.0, 2.0), walnut_cover)
    add("upper_cover", (0.0, 0.0, 9.0), (20.0, 8.0, 2.0), walnut_cover)
    add("spine_core", (-9.0, 0.0, 0.0), (2.0, 6.0, 16.0), leather_spine)
    add("fore_edge", (9.0, 0.0, 0.0), (2.0, 5.0, 14.0), parchment_pages)

    # Visible page strata and spine ridges give the thin side and top views real depth.
    for suffix, z in [("lower", -5.0), ("middle", 0.0), ("upper", 5.0)]:
        add(f"page_edge_{suffix}", (0.0, -3.5, z), (12.0, 1.0, 1.0), parchment_pages)
        add(f"spine_band_{suffix}", (-10.5, 0.0, z), (1.0, 6.0, 1.0), old_brass)

    # Layered covers: front plates are exterior, so every decorative piece is face-contacted.
    add("upper_cover_front_panel", (0.0, -4.5, 9.0), (14.0, 1.0, 4.0), binding_steel)
    add("lower_cover_front_panel", (0.0, -4.5, -9.0), (14.0, 1.0, 4.0), binding_steel)
    for prefix, z in [("upper", 9.0), ("lower", -9.0)]:
        add(f"{prefix}_corner_left", (-8.5, -4.5, z), (3.0, 1.0, 3.0), old_brass)
        add(f"{prefix}_corner_right", (8.5, -4.5, z), (3.0, 1.0, 3.0), old_brass)

    # The upper cover carries a compact, three-layer rune medallion; the lower cover keeps a
    # smaller clasp, making front and back views intentionally different.
    add("upper_rune_plate", (0.0, -5.5, 9.0), (6.0, 1.0, 4.0), rune_plate)
    add("upper_rune_core", (0.0, -6.5, 9.0), (3.0, 1.0, 2.0), magic_glyph)
    add("upper_rune_tip", (0.0, -7.5, 9.0), (1.0, 1.0, 4.0), magic_glyph)
    add("lower_clasp", (0.0, -5.5, -9.0), (4.0, 1.0, 2.0), old_brass)
    add("lower_clasp_lock", (0.0, -6.5, -9.0), (2.0, 1.0, 2.0), forged_iron)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_grimoire()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Grimoire envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
