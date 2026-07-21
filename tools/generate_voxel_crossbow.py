from __future__ import annotations

"""Generate the dedicated left-right-symmetric walnut-tiller voxel crossbow."""

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


MODEL_ID = "crossbow"
WIDTH_PX = 31.0
DEPTH_PX = 9.0
LENGTH_PX = 33.0

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_crossbow.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_crossbow() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a 31 x 9 x 33px light crossbow with a continuous stepped tiller."""
    walnut = make_pixel_material(
        "crossbow_walnut_grain",
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
            "d": (0.075, 0.018, 0.006, 1.0),
            "m": (0.25, 0.075, 0.018, 1.0),
            "l": (0.46, 0.20, 0.052, 1.0),
        },
        roughness=0.88,
    )
    hardwood_dark = make_pixel_material(
        "crossbow_dark_endgrain",
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
            "d": (0.035, 0.008, 0.004, 1.0),
            "m": (0.22, 0.055, 0.014, 1.0),
        },
        roughness=0.95,
    )
    forged_iron = make_material(
        "crossbow_forged_iron", (0.13, 0.16, 0.17, 1.0), metallic=0.76, roughness=0.48
    )
    spring_steel_dark = make_material(
        "crossbow_spring_steel_dark", (0.26, 0.33, 0.36, 1.0), metallic=0.80, roughness=0.40
    )
    spring_steel_mid = make_material(
        "crossbow_spring_steel_mid", (0.43, 0.52, 0.56, 1.0), metallic=0.84, roughness=0.32
    )
    hardened_steel = make_material(
        "crossbow_hardened_steel", (0.72, 0.81, 0.84, 1.0), metallic=0.89, roughness=0.24
    )
    flax_string = make_material(
        "crossbow_flax_string", (0.72, 0.66, 0.51, 1.0), roughness=0.84
    )
    brass_dark = make_material(
        "crossbow_brass_dark", (0.45, 0.26, 0.065, 1.0), metallic=0.62, roughness=0.46
    )
    brass_bright = make_material(
        "crossbow_brass_bright", (0.72, 0.49, 0.13, 1.0), metallic=0.69, roughness=0.36
    )

    root = make_root("weapons_voxel_crossbow")
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

    # Keep the central fore-stock first for the runtime collision fallback. The
    # stock is deliberately segmented into a continuous stepped tiller instead
    # of a sword-like leather grip between two disconnected wooden columns.
    add("body_stock_core", (0.0, 0.0, -7.5), (5.0, 5.0, 9.0), walnut)
    add("stock_lock_housing", (0.0, 0.0, -1.0), (7.0, 5.0, 4.0), hardwood_dark)
    add("stock_grip_neck", (0.0, 0.0, 3.0), (3.0, 5.0, 4.0), walnut)
    add("stock_rear", (0.0, 0.0, 9.0), (7.0, 5.0, 8.0), walnut)
    add("stock_butt", (0.0, 0.0, 14.0), (9.0, 7.0, 2.0), hardwood_dark)
    # A shallow cheek rest gives the rear tiller a deliberate side silhouette;
    # it is a real wood mass attached by its broad face, not a floating plate.
    add("stock_cheek_rest", (0.0, 3.0, 8.0), (7.0, 1.0, 4.0), walnut)
    add("forestock_nose", (0.0, 0.0, -17.0), (3.0, 3.0, 2.0), hardened_steel)
    add("bow_riser", (0.0, 0.0, -14.0), (7.0, 7.0, 4.0), forged_iron)

    add_x_pair("limb_inner", 6.5, 0.0, -14.5, (6.0, 5.0, 3.0), spring_steel_dark)
    add_x_pair("limb_mid", 11.0, 0.0, -13.0, (3.0, 3.0, 3.0), spring_steel_mid)
    add_x_pair("limb_tip", 14.0, 0.0, -11.5, (3.0, 3.0, 2.0), hardened_steel)

    add_x_pair("bowstring_outer", 12.0, 0.0, -10.0, (7.0, 1.0, 1.0), flax_string)
    add_x_pair("bowstring_elbow", 8.0, 0.0, -9.0, (1.0, 1.0, 3.0), flax_string)
    add_x_pair("bowstring_inner", 5.0, 0.0, -8.0, (5.0, 1.0, 1.0), flax_string)

    # The upper rail and latch establish a functional top. The lower lockwork
    # is intentionally not mirrored top-to-bottom, while every part remains
    # centered or paired across the left-right X axis.
    add("bolt_rail_upper", (0.0, 3.0, -5.5), (1.0, 1.0, 13.0), brass_bright)
    add("cocking_latch", (0.0, 4.0, -1.0), (3.0, 1.0, 2.0), brass_dark)
    add_x_pair("lock_plate", 4.0, 0.0, -1.0, (1.0, 3.0, 3.0), brass_dark)
    add_x_pair("trigger_pin", 5.0, 0.0, -1.0, (1.0, 1.0, 1.0), brass_bright)

    # A 1px air channel separates the receiver from the outer bridge. The two
    # stems connect the U-shaped guard by face contact, and the narrow trigger
    # sits inside the opening instead of reading as another surface plate.
    add("trigger_guard_fore_stem", (0.0, -3.5, -2.5), (3.0, 2.0, 1.0), brass_dark)
    add("trigger_guard_rear_stem", (0.0, -3.5, 0.5), (3.0, 2.0, 1.0), brass_dark)
    add("trigger_guard_bridge", (0.0, -4.0, -1.0), (3.0, 1.0, 2.0), brass_dark)
    add("trigger_blade", (0.0, -3.0, -1.0), (1.0, 1.0, 1.0), hardened_steel)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_crossbow()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Crossbow envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
