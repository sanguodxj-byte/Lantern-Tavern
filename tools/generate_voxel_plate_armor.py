from __future__ import annotations

"""Generate the dedicated stepped voxel plate armor with canonical equipment materials.

This is the heavy body-slot armor (armor_heavy / plate). It models a standalone
half-body steel plate cuirass — breastplate, back plate, pauldrons, fauld and
leather belt — authored as clustered voxel masses with stepped contours and
material color ramps following the Barony-style art direction.

Scale: 1m = 32px; 1px = 1/32m. All dimensions are authored in pixels first.
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


MODEL_ID = "plate_armor"
OUT_GLB = ROOT / "assets" / "meshes" / "armor" / "armor_voxel_plate_armor.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_plate_armor() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a 26 x 16 x 32px stepped half-body plate cuirass."""

    # ---- Materials: steel color ramp (shadow / base / highlight) ----
    steel_shadow = make_material(
        "plate_armor_steel_shadow", (0.12, 0.15, 0.18, 1.0), metallic=0.78, roughness=0.45
    )
    steel_base = make_material(
        "plate_armor_steel_base", (0.22, 0.26, 0.30, 1.0), metallic=0.82, roughness=0.38
    )
    steel_highlight = make_material(
        "plate_armor_steel_highlight", (0.48, 0.55, 0.60, 1.0), metallic=0.88, roughness=0.28
    )
    meteoric_trim = make_material(
        "plate_armor_meteoric_trim", (0.15, 0.18, 0.21, 1.0), metallic=0.91, roughness=0.30
    )
    iron_rivet = make_material(
        "plate_armor_iron_rivet", (0.35, 0.38, 0.42, 1.0), metallic=0.85, roughness=0.35
    )

    # ---- Leather: pixel material for belt and strapping ----
    leather_dark = make_pixel_material(
        "plate_armor_leather_dark",
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

    root = make_root("armor_voxel_plate_armor")
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
        y: float,
        z: float,
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        add(f"{prefix}_left", (-x, y, z), size, material)
        add(f"{prefix}_right", (x, y, z), size, material)

    # ========================================================================
    # Core body: 6 stacked horizontal bands (Z face contact)
    # The stepped width reduction from shoulders to fauld gives a readable
    # tapered silhouette instead of a featureless slab.
    # ========================================================================
    add("neck_guard", (0.0, 0.0, 13.0), (10.0, 6.0, 4.0), steel_shadow)
    add("shoulder_band", (0.0, 0.0, 8.0), (22.0, 10.0, 6.0), steel_base)
    add("chest_band", (0.0, 0.0, 2.0), (20.0, 10.0, 6.0), steel_base)
    add("waist_band", (0.0, 0.0, -4.0), (16.0, 8.0, 6.0), steel_shadow)
    add("fauld_upper", (0.0, 0.0, -10.0), (14.0, 8.0, 6.0), steel_base)
    add("fauld_lower", (0.0, 0.0, -15.0), (12.0, 6.0, 4.0), steel_shadow)

    # ========================================================================
    # Front detail plates (exterior +Y face, stepped protrusion)
    # Two depth layers give real volumetric breastplate curvature: an inner
    # plate flush on the core, and an outer plate raised one step further.
    # The fauld front splits into upper/lower lames for articulation read.
    # ========================================================================
    add("breast_upper", (0.0, 6.0, 8.0), (18.0, 2.0, 4.0), steel_highlight)
    add("breast_mid", (0.0, 6.0, 2.0), (16.0, 2.0, 4.0), steel_highlight)
    add("breast_upper_outer", (0.0, 8.0, 8.0), (14.0, 2.0, 4.0), steel_base)
    add("breast_mid_outer", (0.0, 8.0, 2.0), (12.0, 2.0, 4.0), steel_base)
    add("belt_front", (0.0, 5.0, -4.0), (14.0, 2.0, 4.0), leather_dark)
    add("fauld_front_upper", (0.0, 5.0, -8.0), (12.0, 2.0, 2.0), steel_highlight)
    add("fauld_front_lower", (0.0, 5.0, -11.0), (10.0, 2.0, 4.0), steel_shadow)
    add("fauld_lower_front", (0.0, 3.5, -15.0), (8.0, 1.0, 2.0), steel_highlight)

    # ========================================================================
    # Back detail (exterior -Y face, stepped protrusion)
    # Mirrors the front: back shoulder plate + back chest plate with outer
    # raised layer, belt, and split fauld lames for full rear coverage.
    # ========================================================================
    add("back_shoulder", (0.0, -6.0, 8.0), (18.0, 2.0, 4.0), steel_highlight)
    add("back_upper", (0.0, -6.0, 2.0), (16.0, 2.0, 4.0), steel_highlight)
    add("back_shoulder_outer", (0.0, -8.0, 8.0), (14.0, 2.0, 4.0), steel_base)
    add("back_upper_outer", (0.0, -8.0, 2.0), (12.0, 2.0, 4.0), steel_base)
    add("belt_back", (0.0, -5.0, -4.0), (14.0, 2.0, 4.0), leather_dark)
    add("fauld_back_upper", (0.0, -5.0, -8.0), (12.0, 2.0, 2.0), steel_shadow)
    add("fauld_back_lower", (0.0, -5.0, -11.0), (10.0, 2.0, 4.0), steel_shadow)
    add("fauld_lower_back", (0.0, -3.5, -15.0), (8.0, 1.0, 2.0), steel_shadow)

    # ========================================================================
    # Pauldrons (exterior ±X on shoulder band, stepped dome)
    # A wide base tier gives protective shoulder volume; a narrower cap tier
    # on top creates a domed read instead of a flat slab. The base is 4px
    # wide (vs the old 2px) for real shoulder-guard presence.
    # ========================================================================
    add_x_pair("pauldron_base", 13.0, 0.0, 8.0, (4.0, 10.0, 6.0), steel_base)
    add_x_pair("pauldron_cap", 13.0, 0.0, 12.0, (4.0, 6.0, 2.0), steel_highlight)
    add_x_pair("pauldron_ridge", 13.0, 0.0, 13.5, (2.0, 3.0, 1.0), meteoric_trim)

    # ========================================================================
    # Side trims (exterior ±X on chest band)
    # Vertical steel trim strips on the ribcage give the side view a broken
    # contour and reinforce the tapered waist read.
    # ========================================================================
    add_x_pair("side_trim", 10.5, 0.0, 2.0, (1.0, 8.0, 4.0), steel_highlight)

    # ========================================================================
    # Neck trim (exterior +Y on neck guard)
    # A meteoric steel band across the collar gives the neck guard a finished
    # edge and a distinct material accent at the top of the silhouette.
    # ========================================================================
    add("neck_trim", (0.0, 3.5, 13.0), (8.0, 1.0, 2.0), meteoric_trim)

    # ========================================================================
    # Center emblem (exterior +Y on breast_mid_outer)
    # A meteoric plate on the center chest serves as the focal point and
    # identity anchor for the front view.
    # ========================================================================
    add("emblem", (0.0, 9.5, 2.0), (4.0, 1.0, 4.0), meteoric_trim)

    # ========================================================================
    # Vertical seam (exterior +Y on breast_upper_outer)
    # A dark steel strip above the emblem gives the upper breastplate a
    # deliberate split line without overlapping the emblem below.
    # ========================================================================
    add("seam", (0.0, 9.5, 8.0), (1.0, 1.0, 3.0), steel_shadow)

    # ========================================================================
    # Rivets (2px cubes, exterior +Y on outer breast plates)
    # Enlarged from 1px to 2px for render visibility. Four breast rivets +
    # two belt rivets add scale cues and material variety.
    # ========================================================================
    add_x_pair("rivet_breast_upper", 6.0, 9.5, 8.0, (2.0, 1.0, 2.0), iron_rivet)
    add_x_pair("rivet_breast_mid", 5.0, 9.5, 2.0, (2.0, 1.0, 2.0), iron_rivet)
    add_x_pair("rivet_belt", 5.0, 6.5, -4.0, (2.0, 1.0, 2.0), iron_rivet)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_plate_armor()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Plate armor envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
