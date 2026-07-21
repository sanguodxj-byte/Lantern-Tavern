from __future__ import annotations

"""Generate the dedicated stepped voxel shield with canonical equipment materials."""

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


MODEL_ID = "shield"
WIDTH_PX = 25.0
DEPTH_PX = 9.0
LENGTH_PX = 29.0
MATERIAL_TIERS = ("wood", "iron", "steel", "meteoric", "mithril", "adamantite")

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_shield.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_shield() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a 25 x 9 x 29px stepped heater shield with a real rear grip."""
    walnut = make_pixel_material(
        "shield_material_wood_grain",
        (
            "ddmmmmdd",
            "dmllllmd",
            "mllmmllm",
            "mlddddlm",
            "ddmmmddd",
            "mlddddlm",
            "mllmmllm",
            "dmllllmd",
        ),
        {
            "d": (0.060, 0.014, 0.004, 1.0),
            "m": (0.235, 0.068, 0.015, 1.0),
            "l": (0.430, 0.175, 0.040, 1.0),
        },
        roughness=0.89,
    )
    walnut_shadow = make_pixel_material(
        "shield_material_wood_shadow",
        (
            "dddddddd",
            "ddmmmmdd",
            "dmllllmd",
            "dmddddmd",
            "dmddddmd",
            "dmllllmd",
            "ddmmmmdd",
            "dddddddd",
        ),
        {
            "d": (0.040, 0.009, 0.003, 1.0),
            "m": (0.160, 0.038, 0.009, 1.0),
            "l": (0.300, 0.105, 0.024, 1.0),
        },
        roughness=0.94,
    )
    endgrain = make_pixel_material(
        "shield_material_wood_endgrain",
        (
            "dddddddd",
            "ddmmmmdd",
            "dmddddmd",
            "dmdmmdmd",
            "dmdmmdmd",
            "dmddddmd",
            "ddmmmmdd",
            "dddddddd",
        ),
        {
            "d": (0.025, 0.005, 0.002, 1.0),
            "m": (0.220, 0.055, 0.014, 1.0),
        },
        roughness=0.96,
    )
    forged_iron_dark = make_material(
        "shield_material_iron_dark", (0.105, 0.125, 0.135, 1.0), metallic=0.77, roughness=0.50
    )
    forged_iron_mid = make_material(
        "shield_material_iron_mid", (0.255, 0.315, 0.335, 1.0), metallic=0.81, roughness=0.40
    )
    hardened_steel = make_material(
        "shield_material_steel_edge", (0.585, 0.680, 0.705, 1.0), metallic=0.88, roughness=0.28
    )
    meteoric = make_material(
        "shield_material_meteoric", (0.150, 0.180, 0.205, 1.0), metallic=0.91, roughness=0.30
    )
    mithril = make_material(
        "shield_material_mithril", (0.665, 0.755, 0.785, 1.0), metallic=0.92, roughness=0.22
    )
    adamantite = make_material(
        "shield_material_adamantite", (0.405, 0.245, 0.075, 1.0), metallic=0.94, roughness=0.26
    )
    hand_grip = make_pixel_material(
        "shield_material_wood_leather_grip",
        (
            "dddddddd",
            "dmmmmmmd",
            "dmllllmd",
            "dmmmmmmd",
            "dddddddd",
            "dmmmmmmd",
            "dmllllmd",
            "dmmmmmmd",
        ),
        {
            "d": (0.030, 0.006, 0.003, 1.0),
            "m": (0.105, 0.022, 0.010, 1.0),
            "l": (0.205, 0.060, 0.022, 1.0),
        },
        roughness=0.93,
    )

    root = make_root("weapons_voxel_shield")
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
        depth: float,
        length: float,
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        add(f"{prefix}_left", (-x, depth, length), size, material)
        add(f"{prefix}_right", (x, depth, length), size, material)

    # A continuous stepped wooden silhouette. Each band changes width only at
    # a face contact, so the shield reads as a carved tiller rather than a
    # single featureless slab.
    add("body_panel_upper", (0.0, 0.0, 7.0), (19.0, 3.0, 7.0), walnut)
    add("body_panel_mid", (0.0, 0.0, 0.0), (21.0, 3.0, 7.0), walnut_shadow)
    add("body_panel_lower", (0.0, 0.0, -7.0), (15.0, 3.0, 7.0), walnut)
    add("body_top_center", (0.0, 0.0, 12.0), (11.0, 3.0, 3.0), walnut_shadow)
    add_x_pair("body_top_shoulder", 7.0, 0.0, 11.5, (3.0, 3.0, 2.0), walnut)
    add("body_top_cap", (0.0, 0.0, 14.0), (5.0, 3.0, 1.0), endgrain)
    add("body_bottom_center", (0.0, 0.0, -12.0), (7.0, 3.0, 3.0), walnut_shadow)
    add_x_pair("body_bottom_shoulder", 5.5, 0.0, -11.5, (4.0, 3.0, 2.0), walnut)
    add("body_bottom_tip", (0.0, 0.0, -14.0), (3.0, 3.0, 1.0), endgrain)

    # Layered wooden side masses give the silhouette deliberate broken steps.
    add_x_pair("body_side_upper", 10.0, 0.0, 7.0, (1.0, 3.0, 7.0), walnut_shadow)
    add_x_pair("body_side_upper_tip", 11.0, 0.0, 7.0, (1.0, 3.0, 5.0), walnut)
    add_x_pair("body_side_mid", 11.0, 0.0, 0.0, (1.0, 3.0, 7.0), walnut_shadow)
    add_x_pair("body_side_mid_tip", 12.0, 0.0, 0.0, (1.0, 3.0, 5.0), walnut)
    add_x_pair("body_side_lower", 8.0, 0.0, -7.0, (1.0, 3.0, 7.0), walnut_shadow)
    add_x_pair("body_side_lower_tip", 9.0, 0.0, -7.0, (1.0, 3.0, 5.0), walnut)

    # Front planks are face-attached wood layers, with alternating grain to
    # keep the large surface readable in both the structural and 3D views.
    for z_name, z, width, x_offset, material_left, material_center, material_right in [
        ["upper", 7.0, 6.25, 6.25, walnut_shadow, walnut, walnut_shadow],
        ["mid", 0.0, 7.0, 7.0, walnut, walnut_shadow, walnut],
        ["lower", -7.0, 5.0, 5.0, walnut_shadow, walnut, walnut_shadow],
    ]:
        add(f"front_panel_{z_name}_left", (-x_offset, 2.0, z), (width, 1.0, 7.0), material_left)
        add(f"front_panel_{z_name}_center", (0.0, 2.0, z), (width, 1.0, 7.0), material_center)
        add(f"front_panel_{z_name}_right", (x_offset, 2.0, z), (width, 1.0, 7.0), material_right)

    # Raised iron rails follow each stepped wooden band instead of forming a
    # single thin outline pasted over the whole shield.
    add_x_pair("front_rim_upper", 9.0, 3.0, 7.0, (1.0, 1.0, 7.0), forged_iron_mid)
    add_x_pair("front_rim_mid", 10.0, 3.0, 0.0, (1.0, 1.0, 7.0), forged_iron_dark)
    add_x_pair("front_rim_lower", 7.0, 3.0, -7.0, (1.0, 1.0, 7.0), forged_iron_mid)
    add("front_rim_top_center", (0.0, 2.0, 13.5), (11.0, 1.0, 1.0), hardened_steel)
    add_x_pair("front_rim_top_shoulder", 7.0, 2.0, 12.5, (3.0, 1.0, 2.0), forged_iron_mid)
    add("front_rim_bottom_center", (0.0, 2.0, -13.0), (7.0, 1.0, 1.0), hardened_steel)
    add_x_pair("front_rim_bottom_shoulder", 5.5, 2.0, -12.5, (4.0, 1.0, 2.0), forged_iron_mid)

    # The boss is a stepped multi-tier impact surface, not a flat decal:
    # iron base, meteoric top/bottom rails, mithril cap, adamantite side rails.
    add("front_boss_base", (0.0, 3.0, 0.0), (7.0, 1.0, 7.0), forged_iron_dark)
    add("front_boss_cap", (0.0, 4.0, 0.0), (3.0, 1.0, 3.0), mithril)
    add("front_boss_ring_top", (0.0, 3.0, 4.0), (5.0, 1.0, 1.0), meteoric)
    add("front_boss_ring_bottom", (0.0, 3.0, -4.0), (5.0, 1.0, 1.0), meteoric)
    add("front_boss_ring_left", (-4.0, 3.0, 0.0), (1.0, 1.0, 5.0), adamantite)
    add("front_boss_ring_right", (4.0, 3.0, 0.0), (1.0, 1.0, 5.0), adamantite)

    # Four face-attached rivets add scale cues without becoming the silhouette.
    add_x_pair("front_rivet_upper", 6.5, 3.0, 8.0, (1.0, 1.0, 1.0), mithril)
    add_x_pair("front_rivet_lower", 5.5, 3.0, -8.0, (1.0, 1.0, 1.0), adamantite)

    # The rear hardware is intentionally a vertical grip: two iron mounts
    # touch the back of the wooden body and the dark wrapped bar between them.
    add("back_grip_mount_upper", (0.0, -2.5, 4.5), (3.0, 2.0, 2.0), forged_iron_dark)
    add("back_grip_mount_lower", (0.0, -2.5, -4.5), (3.0, 2.0, 2.0), forged_iron_dark)
    add("back_grip_bar", (0.0, -4.0, 0.0), (2.0, 1.0, 8.0), hand_grip)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_shield()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Shield envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
