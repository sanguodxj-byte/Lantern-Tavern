#!/usr/bin/env python3
"""Generate the cultist_pyromancer character voxel asset (A/S Tier High Quality Remake).

Barony-style authored voxel cultist pyromancer with high pointed gold-embroidered hood,
weathered wooden mask with glowing crimson eyes, floating multi-layered fireball,
3-step flared rune robe skirt, shoulder ritual shawl, and back scroll case.
No hand-held weapons built-in per equipment system rule.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from voxel_humanoid_rig import (  # noqa: E402
    create_voxel_humanoid_armature,
    parent_parts_by_bone,
)
from voxel_model_primitives import (  # noqa: E402
    bounds_center_scale,
    cube_px,
    export_glb,
    make_material,
    make_root,
    render_real_views,
    reset_scene,
    setup_lights_and_camera,
)
from voxel_overlap_guard import (  # noqa: E402
    assert_parts_no_positive_volume_overlap,
    assert_parts_single_face_connected_component,
)

MODEL_ID = "cultist_pyromancer"
TARGET_ENVELOPE_PX = (21.0, 68.0, 23.0)
HEAD_ENVELOPE_PX = (18.0, 22.0, 18.0)
AUTHORED_PART_COUNT = 42
MIN_SOLID_ENVELOPE_RATIO = 0.12
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_cultist_pyromancer_68px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_cultist_pyromancer_68px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


@dataclass(frozen=True)
class PartSpec:
    name: str
    center_px: tuple[float, float, float]
    size_px: tuple[float, float, float]
    material_key: str
    bone: str


PART_SPECS: tuple[PartSpec, ...] = (
    # Dark boots & inner trousers.
    PartSpec("boot_left", (-5.0, 0.5, 2.0), (5.0, 6.0, 4.0), "leather_dark", "Foot.L"),
    PartSpec("shin_left", (-5.0, 0.5, 8.0), (5.0, 5.0, 8.0), "robe_dark", "LowerLeg.L"),
    PartSpec("thigh_left", (-4.5, 0.5, 18.0), (6.0, 6.0, 10.0), "robe_dark", "UpperLeg.L"),

    PartSpec("boot_right", (5.0, 0.5, 2.0), (5.0, 6.0, 4.0), "leather_dark", "Foot.R"),
    PartSpec("shin_right", (5.0, 0.5, 8.0), (5.0, 5.0, 8.0), "robe_dark", "LowerLeg.R"),
    PartSpec("thigh_right", (4.5, 0.5, 18.0), (6.0, 6.0, 10.0), "robe_dark", "UpperLeg.R"),

    # Flared 3-step Rune Robe Skirt (Breaking flat blockiness).
    PartSpec("pelvis_core", (0.0, 0.5, 24.0), (12.0, 7.0, 4.0), "robe_dark", "Pelvis"),
    PartSpec("robe_skirt_front", (0.0, -3.5, 18.0), (12.0, 1.0, 14.0), "robe_red", "Pelvis"),
    PartSpec("robe_skirt_back_upper", (0.0, 4.5, 18.0), (12.0, 1.0, 14.0), "robe_dark", "Pelvis"),
    PartSpec("robe_skirt_back_mid", (0.0, 5.5, 12.0), (14.0, 1.0, 10.0), "robe_red", "Pelvis"),
    PartSpec("robe_skirt_back_lower", (0.0, 6.5, 7.0), (14.0, 1.0, 6.0), "robe_dark", "Pelvis"),
    PartSpec("robe_skirt_left_flare", (-6.5, 0.5, 16.0), (1.0, 8.0, 16.0), "robe_dark", "Pelvis"),
    PartSpec("robe_skirt_right_flare", (6.5, 0.5, 16.0), (1.0, 8.0, 16.0), "robe_dark", "Pelvis"),
    PartSpec("robe_gold_trim", (0.0, -4.0, 14.0), (10.0, 1.0, 2.0), "trim_gold", "Pelvis"),

    # Torso, Shoulder Ritual Shawl & Back Scroll Case.
    PartSpec("torso_core", (0.0, 0.5, 33.0), (12.0, 7.0, 14.0), "robe_dark", "Torso"),
    PartSpec("chest_robe_plate", (0.0, -3.5, 33.0), (10.0, 1.0, 12.0), "robe_red", "Torso"),
    PartSpec("ritual_shawl_back", (0.0, 4.5, 37.0), (14.0, 1.0, 6.0), "trim_gold", "Torso"),
    PartSpec("ritual_shawl_left", (-7.5, 0.5, 38.0), (3.0, 7.0, 4.0), "trim_gold", "Torso"),
    PartSpec("ritual_shawl_right", (7.5, 0.5, 38.0), (3.0, 7.0, 4.0), "trim_gold", "Torso"),
    PartSpec("scroll_case_body", (0.0, 5.5, 32.0), (4.0, 3.0, 10.0), "leather_dark", "Torso"),
    PartSpec("scroll_case_buckle", (0.0, 6.0, 32.0), (2.0, 2.0, 2.0), "trim_gold", "Torso"),

    # Sleeves & Forward Cupped Spellcasting Hands.
    PartSpec("shoulder_left", (-8.5, 0.5, 37.0), (4.0, 5.0, 4.0), "robe_dark", "UpperArm.L"),
    PartSpec("upper_arm_left", (-8.5, -1.5, 33.0), (4.0, 5.0, 4.0), "robe_red", "UpperArm.L"),
    PartSpec("forearm_left", (-8.5, -5.5, 33.0), (4.0, 5.0, 4.0), "robe_dark", "LowerArm.L"),
    PartSpec("hand_left", (-8.5, -8.5, 33.0), (4.0, 3.0, 4.0), "mask_wood", "Hand.L"),

    PartSpec("shoulder_right", (8.5, 0.5, 37.0), (4.0, 5.0, 4.0), "robe_dark", "UpperArm.R"),
    PartSpec("upper_arm_right", (8.5, -1.5, 33.0), (4.0, 5.0, 4.0), "robe_red", "UpperArm.R"),
    PartSpec("forearm_right", (8.5, -5.5, 33.0), (4.0, 5.0, 4.0), "robe_dark", "LowerArm.R"),
    PartSpec("hand_right", (8.5, -8.5, 33.0), (4.0, 3.0, 4.0), "mask_wood", "Hand.R"),

    # Floating Multi-layered Fireball (Reaching Y = -16.0px).
    PartSpec("fireball_core", (0.0, -12.0, 33.0), (6.0, 4.0, 6.0), "fire_core", "Torso"),
    PartSpec("fireball_outer", (0.0, -14.0, 33.0), (4.0, 4.0, 4.0), "fire_outer", "Torso"),
    PartSpec("fireball_spark_top", (0.0, -12.0, 37.0), (2.0, 2.0, 2.0), "fire_core", "Torso"),

    # Neck, Weathered Wooden Mask, & High Pointed Hood (Reaching Z = 68.0).
    PartSpec("neck_core", (0.0, 0.5, 41.0), (6.0, 5.0, 2.0), "robe_dark", "Neck"),
    PartSpec("head_core", (0.0, 0.5, 47.0), (8.0, 8.0, 8.0), "mask_wood", "Head"),
    PartSpec("mask_face_front", (0.0, -4.0, 46.0), (8.0, 1.0, 7.0), "mask_wood", "Head"),
    PartSpec("eye_fire_left", (-2.5, -4.5, 47.0), (2.0, 1.0, 2.0), "fire_core", "Head"),
    PartSpec("eye_fire_right", (2.5, -4.5, 47.0), (2.0, 1.0, 2.0), "fire_core", "Head"),

    # High Pointed Gold-Trimmed Hood.
    PartSpec("hood_base", (0.0, 0.5, 52.0), (12.0, 10.0, 4.0), "robe_dark", "Head"),
    PartSpec("hood_cowl_front", (0.0, -4.5, 51.0), (10.0, 2.0, 2.0), "trim_gold", "Head"),
    PartSpec("hood_mid", (0.0, 0.5, 57.0), (10.0, 8.0, 6.0), "robe_red", "Head"),
    PartSpec("hood_tip_lower", (0.0, 1.5, 62.0), (6.0, 6.0, 4.0), "robe_dark", "Head"),
    PartSpec("hood_tip_peak", (0.0, 2.5, 66.0), (4.0, 4.0, 4.0), "trim_gold", "Head"),
)


def _build_palette() -> dict[str, bpy.types.Material]:
    return {
        "robe_dark": make_material("robe_dark", (0.12, 0.08, 0.08, 1.0), roughness=0.8),
        "robe_red": make_material("robe_red", (0.55, 0.08, 0.08, 1.0), roughness=0.7),
        "trim_gold": make_material("trim_gold", (0.85, 0.70, 0.20, 1.0), roughness=0.4, metallic=0.6),
        "leather_dark": make_material("leather_dark", (0.16, 0.10, 0.05, 1.0), roughness=0.6),
        "mask_wood": make_material("mask_wood", (0.25, 0.20, 0.15, 1.0), roughness=0.9),
        "fire_core": make_material("fire_core", (1.00, 0.90, 0.20, 1.0), roughness=0.1, metallic=0.1, emission=3.5),
        "fire_outer": make_material("fire_outer", (1.00, 0.35, 0.05, 1.0), roughness=0.1, metallic=0.1, emission=2.5),
    }


def _compute_envelope(parts: tuple[PartSpec, ...]) -> tuple[float, float, float]:
    min_x = min(p.center_px[0] - p.size_px[0] / 2.0 for p in parts)
    max_x = max(p.center_px[0] + p.size_px[0] / 2.0 for p in parts)
    min_y = min(p.center_px[1] - p.size_px[1] / 2.0 for p in parts)
    max_y = max(p.center_px[1] + p.size_px[1] / 2.0 for p in parts)
    min_z = min(p.center_px[2] - p.size_px[2] / 2.0 for p in parts)
    max_z = max(p.center_px[2] + p.size_px[2] / 2.0 for p in parts)
    return (max_x - min_x, max_z - min_z, max_y - min_y)


def _assert_authored_contract() -> None:
    if len(PART_SPECS) != AUTHORED_PART_COUNT:
        raise RuntimeError(
            f"cultist_pyromancer part count is {len(PART_SPECS)}, expected {AUTHORED_PART_COUNT}"
        )
    envelope = _compute_envelope(PART_SPECS)
    if envelope != TARGET_ENVELOPE_PX:
        raise RuntimeError(
            f"cultist_pyromancer envelope is {envelope}px, expected {TARGET_ENVELOPE_PX}px"
        )
    vol = sum(p.size_px[0] * p.size_px[1] * p.size_px[2] for p in PART_SPECS)
    target_vol = (
        TARGET_ENVELOPE_PX[0] * TARGET_ENVELOPE_PX[1] * TARGET_ENVELOPE_PX[2]
    )
    ratio = vol / target_vol
    if ratio < MIN_SOLID_ENVELOPE_RATIO:
        raise RuntimeError(
            f"cultist_pyromancer volume ratio {ratio:.3f} < threshold {MIN_SOLID_ENVELOPE_RATIO:.3f}"
        )


def build_cultist_pyromancer_mesh() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
    reset_scene()
    materials = _build_palette()
    root = make_root(f"voxel_{MODEL_ID}")
    parts: list[bpy.types.Object] = []
    parts_by_bone: dict[str, list[bpy.types.Object]] = {}

    for spec in PART_SPECS:
        mat = materials[spec.material_key]
        cube = cube_px(spec.name, spec.center_px, spec.size_px, mat)
        cube.parent = root
        parts.append(cube)
        parts_by_bone.setdefault(spec.bone, []).append(cube)

    return root, parts, parts_by_bone


def main() -> None:
    _assert_authored_contract()
    parts = tuple({
        "name": p.name,
        "center_px": p.center_px,
        "size_px": p.size_px,
    } for p in PART_SPECS)

    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_single_face_connected_component(parts, label=MODEL_ID)

    # 1. 导出静态 GLB
    root, parts_objs, parts_by_bone = build_cultist_pyromancer_mesh()
    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    STATIC_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(root, STATIC_OUTPUT)

    # 2. 导出 Rigged GLB
    root, parts_objs, parts_by_bone = build_cultist_pyromancer_mesh()
    armature = create_voxel_humanoid_armature(height_px=68.0, name="Armature")
    parent_parts_by_bone(parts_by_bone, armature)
    RIG_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(armature, RIG_OUTPUT)

    # 3. 渲染 3D 视觉图片
    root, parts_objs, _ = build_cultist_pyromancer_mesh()
    center, scale = bounds_center_scale(root)
    camera = setup_lights_and_camera(center, scale)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    render_real_views(
        PREVIEW_DIR,
        f"voxel_{MODEL_ID}",
        center,
        scale,
        camera,
    )
    print(
        f"Parts: {len(PART_SPECS)}; envelope: {_compute_envelope(PART_SPECS)}px; front: Blender -Y"
    )
    print(f"Wrote {STATIC_OUTPUT}")
    print(f"Wrote {RIG_OUTPUT}")


if __name__ == "__main__":
    main()
