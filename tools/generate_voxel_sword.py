from __future__ import annotations

"""Generate the dedicated symmetric one-handed knight sword voxel model."""

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


MODEL_ID = "sword"
# Axis contract: author the blade and grip on one Z length axis. After the
# shared export_yup=True conversion this is Godot local +Y; blade width stays
# local X and the one-voxel blade thickness stays local Z.
AUTHORED_LENGTH_AXIS = "Z"
AUTHORED_BLADE_WIDTH_AXIS = "X"
AUTHORED_BLADE_THICKNESS_AXIS = "Y"
WIDTH_PX = 19.0
DEPTH_PX = 7.0
LENGTH_PX = 95.0

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_sword.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_sword() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a 19 x 7 x 95px symmetric one-handed knight sword.

    The blade is a real voxel assembly: integer-pixel boxes share faces
    end-to-end, keep a 1px blade thickness on the depth axis, use odd
    horizontal widths throughout, and narrow only at the terminal tip.
    The broad cutting face is parallel to the horizontal guard; only the
    guard uses cross-like quillons.
    """
    steel_core = make_material(
        "sword_steel_core", (0.24, 0.29, 0.32, 1.0), metallic=0.82, roughness=0.38
    )
    steel_polished = make_material(
        "sword_steel_polished", (0.79, 0.84, 0.86, 1.0), metallic=0.93, roughness=0.20
    )
    steel_edge = make_material(
        "sword_steel_edge", (0.47, 0.56, 0.61, 1.0), metallic=0.84, roughness=0.30
    )
    blackened_iron = make_material(
        "sword_blackened_iron", (0.10, 0.12, 0.12, 1.0), metallic=0.75, roughness=0.48
    )
    old_brass = make_material(
        "sword_old_brass", (0.56, 0.34, 0.095, 1.0), metallic=0.69, roughness=0.39
    )
    knight_brass = make_material(
        "sword_knight_brass", (0.70, 0.47, 0.13, 1.0), metallic=0.73, roughness=0.32
    )
    leather_dark = make_material(
        "sword_forest_leather_dark", (0.025, 0.13, 0.070, 1.0), roughness=0.91
    )
    leather_mid = make_material(
        "sword_forest_leather_mid", (0.045, 0.25, 0.12, 1.0), roughness=0.86
    )

    root = make_root("weapons_voxel_sword")
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
        z: float,
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        add(f"{prefix}_left", (-x, 0.0, z), size, material)
        add(f"{prefix}_right", (x, 0.0, z), size, material)

    # A readable voxel blade is a single symmetric 5px-wide, 3px-thick
    # cutting body. Keeping the broad body as one volume prevents the
    # structural front projection from creating a false one-sided seam.
    # Blade thickness is always one voxel. The final two sections form a
    # stepped triangular silhouette without creating a 1x1 section early.
    add("blade_body", (0.0, 0.0, -41.5), (5.0, 1.0, 77.0), steel_polished)
    add("blade_taper", (0.0, 0.0, -81.0), (3.0, 1.0, 2.0), steel_edge)
    add("blade_point", (0.0, 0.0, -82.5), (1.0, 1.0, 1.0), steel_polished)

    # The stepped quillons rise evenly on both sides.
    add("guard_center", (0.0, 0.0, -1.5), (5.0, 5.0, 3.0), blackened_iron)
    add_x_pair("guard_inner", 4.0, -1.0, (3.0, 5.0, 2.0), blackened_iron)
    add_x_pair("guard_outer", 7.0, 0.0, (3.0, 3.0, 2.0), old_brass)
    add_x_pair("guard_tip", 9.0, 0.5, (1.0, 3.0, 3.0), steel_polished)

    # Grip volumes meet end-to-end; paired widths create readable wrap bands.
    add("grip_collar", (0.0, 0.0, 0.5), (5.0, 5.0, 1.0), knight_brass)
    add("grip_upper", (0.0, 0.0, 2.5), (3.0, 3.0, 3.0), leather_dark)
    add("grip_band_upper", (0.0, 0.0, 4.5), (5.0, 5.0, 1.0), knight_brass)
    add("grip_middle", (0.0, 0.0, 6.5), (3.0, 3.0, 3.0), leather_mid)
    add("grip_band_lower", (0.0, 0.0, 8.5), (5.0, 5.0, 1.0), knight_brass)
    add("grip_lower", (0.0, 0.0, 10.0), (3.0, 3.0, 2.0), leather_dark)
    add("pommel_cap", (0.0, 0.0, 11.5), (7.0, 7.0, 1.0), knight_brass)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_sword()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Sword envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
