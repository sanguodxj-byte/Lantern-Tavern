from __future__ import annotations

"""Generate the dedicated heavy greatsword voxel model and true 3D previews."""

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
from weapon_first_person_rig_lib import (  # noqa: E402
    build_weapon_rig,
    export_animated_glb,
    make_action,
    render_action_review,
)
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


MODEL_ID = "greatsword"
WIDTH_PX = 25.0
DEPTH_PX = 7.0
LENGTH_PX = 61.0

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_greatsword.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"
ANIMATION_PREVIEW_DIR = ROOT / "reports" / "first_person_animation" / "greatsword_blender"


def build_greatsword() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a symmetric 25 x 7 x 61px two-handed demon-ward sword."""
    steel_fuller = make_material(
        "greatsword_steel_fuller", (0.20, 0.25, 0.28, 1.0), metallic=0.70, roughness=0.48
    )
    steel_flat = make_material(
        "greatsword_steel_flat", (0.40, 0.48, 0.52, 1.0), metallic=0.78, roughness=0.36
    )
    steel_edge = make_material(
        "greatsword_steel_edge", (0.72, 0.79, 0.82, 1.0), metallic=0.84, roughness=0.27
    )
    iron_dark = make_material(
        "greatsword_iron_dark", (0.22, 0.24, 0.25, 1.0), metallic=0.72, roughness=0.48
    )
    iron_mid = make_material(
        "greatsword_iron_mid", (0.36, 0.39, 0.40, 1.0), metallic=0.70, roughness=0.42
    )
    brass = make_material(
        "greatsword_brass", (0.64, 0.40, 0.12, 1.0), metallic=0.64, roughness=0.38
    )
    leather_dark = make_material(
        "greatsword_leather_dark", (0.18, 0.045, 0.03, 1.0), roughness=0.90
    )
    leather_mid = make_material(
        "greatsword_leather_mid", (0.34, 0.085, 0.045, 1.0), roughness=0.84
    )

    root = make_root("weapons_voxel_greatsword")
    parts: list[bpy.types.Object] = []

    def add(
        name: str,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        parts.append(box_px(name, center, size, material))

    # Long unsharpened ricasso, partitioned rather than layered.
    add("blade_ricasso_center", (0.0, 0.0, -7.0), (3.0, 3.0, 10.0), steel_fuller)
    add("blade_ricasso_left", (-2.5, 0.0, -7.0), (2.0, 5.0, 10.0), steel_flat)
    add("blade_ricasso_right", (2.5, 0.0, -7.0), (2.0, 5.0, 10.0), steel_flat)

    # Forty-two-pixel blade: broad forte, stepped mid, taper and point.
    add("blade_forte_fuller", (0.0, 0.0, -18.0), (3.0, 1.0, 12.0), steel_fuller)
    add("blade_forte_left", (-3.0, 0.0, -18.0), (3.0, 3.0, 12.0), steel_edge)
    add("blade_forte_right", (3.0, 0.0, -18.0), (3.0, 3.0, 12.0), steel_edge)
    add("blade_mid_fuller", (0.0, 0.0, -29.0), (3.0, 1.0, 10.0), steel_fuller)
    add("blade_mid_left", (-2.5, 0.0, -29.0), (2.0, 3.0, 10.0), steel_edge)
    add("blade_mid_right", (2.5, 0.0, -29.0), (2.0, 3.0, 10.0), steel_edge)
    add("blade_taper_fuller", (0.0, 0.0, -37.0), (1.0, 1.0, 6.0), steel_fuller)
    add("blade_taper_left", (-1.5, 0.0, -37.0), (2.0, 3.0, 6.0), steel_edge)
    add("blade_taper_right", (1.5, 0.0, -37.0), (2.0, 3.0, 6.0), steel_edge)
    add("blade_point_base", (0.0, 0.0, -41.5), (1.0, 1.0, 3.0), steel_fuller)
    add("blade_point_left", (-1.0, 0.0, -41.5), (1.0, 3.0, 3.0), steel_edge)
    add("blade_point_right", (1.0, 0.0, -41.5), (1.0, 3.0, 3.0), steel_edge)
    add("blade_tip", (0.0, 0.0, -43.5), (1.0, 1.0, 1.0), steel_edge)

    # Wide stepped quillons are fully mirrored around X=0.
    add("guard_center", (0.0, 0.0, 0.0), (7.0, 5.0, 4.0), iron_dark)
    add("guard_inner_left", (-6.0, 0.0, 0.0), (5.0, 5.0, 3.0), iron_mid)
    add("guard_inner_right", (6.0, 0.0, 0.0), (5.0, 5.0, 3.0), iron_mid)
    add("guard_outer_left", (-10.0, 0.0, -0.5), (3.0, 5.0, 3.0), iron_dark)
    add("guard_outer_right", (10.0, 0.0, -0.5), (3.0, 5.0, 3.0), iron_dark)
    add("guard_tip_left", (-12.0, 0.0, -1.5), (1.0, 3.0, 3.0), steel_edge)
    add("guard_tip_right", (12.0, 0.0, -1.5), (1.0, 3.0, 3.0), steel_edge)

    # Two-handed grip uses end-to-end material bands, never overlay wraps.
    add("grip_collar", (0.0, 0.0, 2.5), (5.0, 5.0, 1.0), brass)
    add("grip_fore", (0.0, 0.0, 4.5), (3.0, 3.0, 3.0), leather_dark)
    add("grip_band_fore", (0.0, 0.0, 6.5), (5.0, 5.0, 1.0), brass)
    add("grip_middle", (0.0, 0.0, 8.5), (3.0, 3.0, 3.0), leather_mid)
    add("grip_band_rear", (0.0, 0.0, 10.5), (5.0, 5.0, 1.0), brass)
    add("grip_rear", (0.0, 0.0, 13.0), (3.0, 3.0, 4.0), leather_dark)

    # A wheel-like pommel creates the full 7px depth and remains mirrored.
    add("pommel_shoulders_center", (0.0, 0.0, 15.5), (5.0, 7.0, 1.0), iron_dark)
    add("pommel_shoulders_left", (-3.0, 0.0, 15.5), (1.0, 5.0, 1.0), iron_mid)
    add("pommel_shoulders_right", (3.0, 0.0, 15.5), (1.0, 5.0, 1.0), iron_mid)
    add("pommel_cap_center", (0.0, 0.0, 16.5), (3.0, 5.0, 1.0), brass)
    add("pommel_cap_left", (-2.0, 0.0, 16.5), (1.0, 3.0, 1.0), brass)
    add("pommel_cap_right", (2.0, 0.0, 16.5), (1.0, 3.0, 1.0), brass)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def _author_first_person_actions(armature: bpy.types.Object) -> None:
    make_action(armature, "vm_greatsword_hold", 1, 36, [
        (1, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
        (18, (0.0, 0.0, -0.18), (0.35, -0.5, 0.3)),
        (36, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
    ], loop=True)
    make_action(armature, "vm_melee_charge", 37, 72, [
        (37, (-0.8, 0.4, -0.8), (5.0, -6.0, 10.0)),
        (48, (0.2, 1.0, -0.3), (-6.0, 8.0, -14.0)),
        (61, (1.2, 1.6, 0.2), (-13.0, 16.0, -27.0)),
        (72, (1.8, 2.0, 0.6), (-18.0, 22.0, -36.0)),
    ])
    make_action(armature, "vm_greatsword_attack", 73, 96, [
        (73, (0.8, 1.2, 0.0), (-10.0, 12.0, -22.0)),
        (77, (1.0, 1.4, 0.2), (-14.0, 16.0, -28.0)),
        (82, (-0.5, 0.8, -1.4), (8.0, -12.0, 22.0)),
        (87, (-2.4, -0.4, -2.8), (17.0, -30.0, 54.0)),
        (91, (-1.4, -0.6, -2.0), (12.0, -22.0, 42.0)),
        (94, (-0.4, -0.2, -0.7), (5.0, -8.0, 16.0)),
        (96, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
    ])
    make_action(armature, "vm_greatsword_guard", 97, 116, [
        (97, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
        (104, (-1.0, 1.2, -0.8), (-9.0, 16.0, 30.0)),
        (116, (-1.0, 1.2, -0.8), (-9.0, 16.0, 30.0)),
    ])
    armature["action_names"] = [
        "vm_greatsword_hold", "vm_melee_charge",
        "vm_greatsword_attack", "vm_greatsword_guard",
    ]


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_greatsword()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    armature = build_weapon_rig(root, parts, "GreatswordRig", 13.0, -18.0)
    _author_first_person_actions(armature)
    render_action_review(
        root,
        armature,
        ANIMATION_PREVIEW_DIR,
        ((0.05, -0.24, -0.70), (10.0, -8.0, -135.0)),
        {
            "00": ("vm_greatsword_hold", 1),
            "01": ("vm_melee_charge", 25),
            "02": ("vm_greatsword_attack", 5),
            "03": ("vm_greatsword_attack", 10),
            "04": ("vm_greatsword_attack", 15),
            "05": ("vm_greatsword_attack", 19),
            "06": ("vm_greatsword_attack", 24),
            "07": ("vm_greatsword_guard", 12),
        },
    )
    export_animated_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Greatsword envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
