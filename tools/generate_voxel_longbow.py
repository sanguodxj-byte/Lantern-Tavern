from __future__ import annotations

"""Generate the dedicated D-profile voxel longbow."""

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
    make_root,
    parent_parts,
    render_true_3d_views,
    reset_scene,
)


MODEL_ID = "longbow"
WIDTH_PX = 13.0
DEPTH_PX = 7.0
LENGTH_PX = 61.0

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_longbow.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_longbow() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a 13 x 7 x 61px bow with one curved stave and a separate string."""
    yew_dark = make_material(
        "longbow_yew_dark", (0.16, 0.055, 0.018, 1.0), roughness=0.92
    )
    yew_mid = make_material(
        "longbow_yew_mid", (0.36, 0.14, 0.035, 1.0), roughness=0.86
    )
    yew_high = make_material(
        "longbow_yew_high", (0.60, 0.30, 0.08, 1.0), roughness=0.80
    )
    leather_dark = make_material(
        "longbow_leather_dark", (0.12, 0.025, 0.018, 1.0), roughness=0.94
    )
    leather_red = make_material(
        "longbow_leather_red", (0.38, 0.055, 0.025, 1.0), roughness=0.86
    )
    horn = make_material(
        "longbow_horn", (0.78, 0.70, 0.52, 1.0), roughness=0.68
    )
    flax_string = make_material(
        "longbow_flax_string", (0.66, 0.61, 0.49, 1.0), roughness=0.82
    )
    serving = make_material(
        "longbow_serving", (0.16, 0.18, 0.20, 1.0), roughness=0.90
    )

    root = make_root("weapons_voxel_longbow")
    parts: list[bpy.types.Object] = []

    def add(
        name: str,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        parts.append(box_px(name, center, size, material))

    # A real bow needs functional X asymmetry: one curved stave faces one taut string.
    # The long central grip remains first alphabetically for runtime collision fallback.
    add("body_stave_grip_core", (0.0, 0.0, 0.0), (3.0, 5.0, 10.0), leather_dark)
    add("grip_wrap_front", (0.0, 3.0, 0.0), (3.0, 1.0, 8.0), leather_red)
    add("grip_wrap_back", (0.0, -3.0, 0.0), (3.0, 1.0, 8.0), leather_red)
    add("grip_collar_lower", (0.0, 0.0, -5.5), (3.0, 7.0, 1.0), horn)
    add("grip_collar_upper", (0.0, 0.0, 5.5), (3.0, 7.0, 1.0), horn)

    add("lower_limb_root", (0.0, 0.0, -9.0), (3.0, 3.0, 6.0), yew_dark)
    add("lower_limb_shoulder", (1.0, 0.0, -14.5), (3.0, 3.0, 5.0), yew_mid)
    add("lower_limb_belly", (3.0, 0.0, -19.5), (3.0, 3.0, 5.0), yew_high)
    add("lower_limb_belly_front", (3.0, 2.0, -19.5), (3.0, 1.0, 5.0), horn)
    add("lower_limb_belly_back", (3.0, -2.0, -19.5), (3.0, 1.0, 5.0), horn)
    add("lower_limb_recurve", (5.0, 0.0, -24.0), (3.0, 3.0, 4.0), yew_mid)
    add("lower_limb_nock", (7.0, 0.0, -27.0), (3.0, 3.0, 2.0), yew_dark)

    add("upper_limb_root", (0.0, 0.0, 9.0), (3.0, 3.0, 6.0), yew_dark)
    add("upper_limb_shoulder", (1.0, 0.0, 14.5), (3.0, 3.0, 5.0), yew_mid)
    add("upper_limb_belly", (3.0, 0.0, 19.5), (3.0, 3.0, 5.0), yew_high)
    add("upper_limb_belly_front", (3.0, 2.0, 19.5), (3.0, 1.0, 5.0), horn)
    add("upper_limb_belly_back", (3.0, -2.0, 19.5), (3.0, 1.0, 5.0), horn)
    add("upper_limb_recurve", (5.0, 0.0, 24.0), (3.0, 3.0, 4.0), yew_mid)
    add("upper_limb_nock", (7.0, 0.0, 27.0), (3.0, 3.0, 2.0), yew_dark)

    add("nock_bridge_lower", (9.25, 0.0, -28.5), (4.5, 5.0, 1.0), horn)
    add("nock_bridge_upper", (9.25, 0.0, 28.5), (4.5, 5.0, 1.0), horn)
    add("string_lower", (11.0, 0.0, -16.0), (1.0, 1.0, 24.0), flax_string)
    add("string_serving", (11.0, 0.0, 0.0), (1.0, 1.0, 8.0), serving)
    add("string_upper", (11.0, 0.0, 16.0), (1.0, 1.0, 24.0), flax_string)
    add("tip_cap_lower", (11.0, 0.0, -29.75), (1.0, 3.0, 1.5), horn)
    add("tip_cap_upper", (11.0, 0.0, 29.75), (1.0, 3.0, 1.5), horn)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_longbow()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Longbow envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
