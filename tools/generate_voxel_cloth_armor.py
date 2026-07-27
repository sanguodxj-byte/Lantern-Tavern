from __future__ import annotations

"""Generate the dedicated voxel cloth armor with canonical equipment materials.

This is the light body-slot armor (armor_light / cloth). It models a
standalone padded cloth gambeson — quilted fabric layers with a rope belt
and simple stitching — authored as clustered voxel masses with stepped
contours and material color ramps following the Barony-style art direction.

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


MODEL_ID = "cloth_armor"
OUT_GLB = ROOT / "assets" / "meshes" / "armor" / "armor_voxel_cloth_armor.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_cloth_armor() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a 20 x 12 x 30px quilted cloth gambeson with rope belt."""

    # ---- Materials: cloth color ramp (shadow / base / highlight) ----
    cloth_shadow = make_material(
        "cloth_armor_shadow", (0.14, 0.12, 0.10, 1.0), metallic=0.0, roughness=0.96
    )
    cloth_base = make_material(
        "cloth_armor_base", (0.24, 0.21, 0.17, 1.0), metallic=0.0, roughness=0.92
    )
    cloth_highlight = make_material(
        "cloth_armor_highlight", (0.36, 0.32, 0.26, 1.0), metallic=0.0, roughness=0.88
    )

    # ---- Cloth texture: pixel material for quilted body ----
    cloth_texture = make_pixel_material(
        "cloth_armor_texture",
        (
            "bhbhbhbh",
            "hbhbhbhb",
            "bhbhbhbh",
            "hbhbhbhb",
            "bhbhbhbh",
            "hbhbhbhb",
            "bhbhbhbh",
            "hbhbhbhb",
        ),
        {
            "b": (0.22, 0.19, 0.15, 1.0),
            "h": (0.30, 0.27, 0.21, 1.0),
        },
        roughness=0.93,
    )

    # ---- Stitching material: darker thread for quilt lines ----
    stitching = make_material(
        "cloth_armor_stitching", (0.08, 0.06, 0.04, 1.0), metallic=0.0, roughness=0.98
    )

    # ---- Rope belt material ----
    rope_belt = make_material(
        "cloth_armor_rope_belt", (0.18, 0.13, 0.07, 1.0), metallic=0.0, roughness=0.94
    )

    root = make_root("armor_voxel_cloth_armor")
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
    # Core body: 4 stacked cloth bands (Z face contact)
    # The gentle taper from chest to waist gives a soft gambeson silhouette.
    # The cloth is lighter and less bulky than leather or plate.
    # ========================================================================
    add("body_neck", (0.0, 0.0, 12.0), (6.0, 4.0, 4.0), cloth_shadow)
    add("body_chest", (0.0, 0.0, 7.0), (16.0, 10.0, 6.0), cloth_texture)
    add("body_waist", (0.0, 0.0, 1.0), (14.0, 8.0, 6.0), cloth_texture)
    add("body_skirt", (0.0, 0.0, -5.0), (12.0, 6.0, 6.0), cloth_shadow)

    # ========================================================================
    # Front quilt lines (exterior +Y on chest and waist)
    # Horizontal stitching strips give the gambeson its quilted read.
    # body_chest occupies Y=-5~5; chest stitch at Y=5.5, Z=7.0 (half=0.5).
    # body_waist occupies Y=-4~4; waist stitch at Y=4.5, Z=-1.5 (half=0.5)
    #   Y face-contact with body_waist (Y=4.0), Z overlap with body_waist
    #   (Z=-2.0~-1.0 inside body_waist Z=-2~4) for a single-axis contact.
    #   Z face-contact with belt_front (Z=-1.0) for component connectivity.
    # body_skirt occupies Y=-3~3; skirt stitch at Y=3.5, Z=-5.0 (half=0.5).
    # ========================================================================
    add("stitch_front_chest", (0.0, 5.5, 7.0), (14.0, 1.0, 1.0), stitching)
    add("stitch_front_waist", (0.0, 4.5, -1.5), (12.0, 1.0, 1.0), stitching)
    add("stitch_front_skirt", (0.0, 3.5, -5.0), (10.0, 1.0, 1.0), stitching)

    # ========================================================================
    # Back quilt lines (exterior -Y on chest and waist)
    # Mirrors the front stitching for consistent quilted appearance.
    # ========================================================================
    add("stitch_back_chest", (0.0, -5.5, 7.0), (14.0, 1.0, 1.0), stitching)
    add("stitch_back_waist", (0.0, -4.5, -1.5), (12.0, 1.0, 1.0), stitching)
    add("stitch_back_skirt", (0.0, -3.5, -5.0), (10.0, 1.0, 1.0), stitching)

    # ========================================================================
    # Vertical stitch line (exterior +Y on chest center)
    # A center front vertical stitch gives the gambeson a split line
    # and reinforces the quilted panel read.
    # Sits at Y=5.5 (on body_chest exterior). Z range 3~6 avoids overlap
    # with the horizontal chest stitch at Z=6.5~7.5 (face contact at 6.0),
    # the waist stitch at Z=-3.0~-2.0 (well below), and the belt knot at
    # Z=-0.5~2.5 (face contact at Z=3.0).
    # ========================================================================
    add("stitch_front_vertical", (0.0, 5.5, 4.5), (1.0, 1.0, 3.0), stitching)
    add("stitch_back_vertical", (0.0, -5.5, 4.5), (1.0, 1.0, 3.0), stitching)

    # ========================================================================
    # Shoulder seam (exterior ±X on body_chest top)
    # A highlight cloth strip along each shoulder gives the seam where
    # the gambeson's sleeves would attach, providing a natural edge.
    # body_chest occupies X=-8~8; seams sit at X=9 (face contact, half=1).
    # ========================================================================
    add_x_pair("shoulder_seam", 9.0, 0.0, 10.0, (2.0, 8.0, 2.0), cloth_highlight)

    # ========================================================================
    # Side panels (exterior ±X on waist)
    # Cloth texture strips complete the torso wrap on the sides.
    # body_waist occupies X=-7~7; panels sit at X=7.5 (face contact, half=0.5).
    # ========================================================================
    add_x_pair("side_panel", 7.5, 0.0, 1.0, (1.0, 6.0, 5.0), cloth_texture)

    # ========================================================================
    # Rope belt (exterior ±Y on waist)
    # A rope belt across the waist gives a cinched read and separates
    # the chest from the skirt section.
    # body_waist occupies Y=-4~4; belt sits at Y=4.5 (face contact, half=0.5).
    # ========================================================================
    add("belt_front", (0.0, 4.5, 1.0), (12.0, 1.0, 4.0), rope_belt)
    add("belt_back", (0.0, -4.5, 1.0), (12.0, 1.0, 4.0), rope_belt)

    # ========================================================================
    # Belt knot (exterior +Y on belt_front)
    # A small highlight cloth knot at the center front gives a tied
    # rope belt its focal point.
    # belt_front occupies Y=4.0~5.0; knot sits at Y=5.5 (face contact, half=0.5).
    # Z range -1~2 avoids overlap with stitch_front_vertical (Z=2~6) via
    # face contact at Z=2, and with stitch_front_waist (Z=0.5~1.5) by
    # sharing Y=5.0~6.0 only on the knot's Y=5.0~6.0 vs stitch Y=4.0~5.0
    # (face contact at Y=5.0, no Z overlap needed since Y separates them).
    # Actually knot Y=5.0~6.0 and stitch_front_waist Y=4.0~5.0: face contact.
    # knot Z=-0.5~2.5, stitch_front_waist Z=0.5~1.5: Z overlap. But Y is
    # face-contact only, so no positive volume overlap. Safe.
    # ========================================================================
    add("belt_knot", (0.0, 5.5, 1.0), (3.0, 1.0, 3.0), cloth_highlight)

    # ========================================================================
    # Hem band (exterior ±Y on skirt bottom)
    # A shadow cloth band at the skirt hem gives a finished edge.
    # body_skirt occupies Y=-3~3; hem sits at Y=3.5 (face contact, half=0.5).
    # ========================================================================
    add("hem_front", (0.0, 3.5, -7.0), (10.0, 1.0, 2.0), cloth_shadow)
    add("hem_back", (0.0, -3.5, -7.0), (10.0, 1.0, 2.0), cloth_shadow)

    # ========================================================================
    # Neck opening trim (exterior ±Y on body_neck)
    # A base-tone cloth trim around the neck opening gives a middle
    # luma accent between the shadow body and highlight shoulder seams.
    # body_neck occupies Y=-2~2; trim sits at Y=2.5 (face contact, half=0.5).
    # ========================================================================
    add("neck_trim_front", (0.0, 2.5, 12.0), (4.0, 1.0, 2.0), cloth_base)
    add("neck_trim_back", (0.0, -2.5, 12.0), (4.0, 1.0, 2.0), cloth_base)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_cloth_armor()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Cloth armor envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
