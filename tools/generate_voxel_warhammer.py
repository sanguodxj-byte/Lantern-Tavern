from __future__ import annotations

"""Generate the dedicated impact-face and armor-spike voxel warhammer."""

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


MODEL_ID = "warhammer"
WIDTH_PX = 25.0
DEPTH_PX = 9.0
LENGTH_PX = 47.0

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_warhammer.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_warhammer() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a 25 x 9 x 47px warhammer with one impact face and one armor spike."""
    iron_dark = make_material(
        "warhammer_forged_iron", (0.14, 0.17, 0.18, 1.0), metallic=0.76, roughness=0.48
    )
    steel_mid = make_material(
        "warhammer_cold_steel", (0.39, 0.49, 0.54, 1.0), metallic=0.82, roughness=0.34
    )
    steel_bright = make_material(
        "warhammer_hardened_steel", (0.75, 0.83, 0.86, 1.0), metallic=0.90, roughness=0.23
    )
    brass = make_material(
        "warhammer_old_brass", (0.59, 0.36, 0.10, 1.0), metallic=0.64, roughness=0.41
    )
    walnut = make_material(
        "warhammer_walnut", (0.28, 0.12, 0.045, 1.0), roughness=0.89
    )
    leather_dark = make_material(
        "warhammer_leather_dark", (0.035, 0.14, 0.05, 1.0), roughness=0.92
    )
    leather_mid = make_material(
        "warhammer_leather_mid", (0.07, 0.29, 0.10, 1.0), roughness=0.85
    )

    root = make_root("weapons_voxel_warhammer")
    parts: list[bpy.types.Object] = []

    def add(
        name: str,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        parts.append(box_px(name, center, size, material))

    add("head_socket_core", (0.0, 0.0, -17.0), (5.0, 7.0, 8.0), iron_dark)
    add("head_cheek_front", (0.0, 4.0, -17.0), (3.0, 1.0, 4.0), brass)
    add("head_cheek_back", (0.0, -4.0, -17.0), (3.0, 1.0, 4.0), brass)
    add("head_crown", (0.0, 0.0, -21.5), (3.0, 7.0, 1.0), iron_dark)

    # Functional asymmetry: a broad impact face opposes a narrow armor spike.
    add("hammer_neck", (-4.0, 0.0, -17.0), (3.0, 5.0, 6.0), iron_dark)
    add("hammer_block", (-7.0, 0.0, -17.0), (3.0, 7.0, 8.0), steel_mid)
    add("hammer_face", (-9.5, 0.0, -17.0), (2.0, 9.0, 10.0), steel_mid)
    add("hammer_face_plate", (-11.0, 0.0, -17.0), (1.0, 7.0, 8.0), steel_bright)
    add("armor_spike_root", (4.0, 0.0, -17.0), (3.0, 5.0, 6.0), steel_mid)
    add("armor_spike_mid", (7.5, 0.0, -17.0), (4.0, 3.0, 4.0), steel_mid)
    add("armor_spike_tip", (11.5, 0.0, -17.0), (4.0, 1.0, 2.0), steel_bright)

    add("haft_neck", (0.0, 0.0, -11.5), (3.0, 3.0, 3.0), iron_dark)
    add("haft_upper", (0.0, 0.0, -5.5), (3.0, 3.0, 9.0), walnut)
    add("grip_band_upper", (0.0, 0.0, -0.5), (5.0, 5.0, 1.0), brass)
    add("grip_upper", (0.0, 0.0, 4.0), (3.0, 3.0, 8.0), leather_dark)
    add("grip_band_center", (0.0, 0.0, 8.5), (5.0, 5.0, 1.0), brass)
    add("grip_lower", (0.0, 0.0, 13.5), (3.0, 3.0, 9.0), leather_mid)
    add("grip_band_lower", (0.0, 0.0, 18.5), (5.0, 5.0, 1.0), brass)
    add("haft_butt", (0.0, 0.0, 21.5), (3.0, 3.0, 5.0), walnut)
    add("pommel_cap", (0.0, 0.0, 24.5), (5.0, 5.0, 1.0), brass)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_warhammer()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Warhammer envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
