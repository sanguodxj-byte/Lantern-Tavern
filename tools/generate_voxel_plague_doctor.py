#!/usr/bin/env python3
"""Generate the plague_doctor character voxel asset (A/S Tier High Quality Remake).

Barony-style authored voxel plague doctor with elongated bird beak mask,
brass goggles with glowing green lenses, wide-brimmed flat hat, shoulder cape,
3-step flared tailcoat, and glowing reagent bandolier.
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

MODEL_ID = "plague_doctor"
TARGET_ENVELOPE_PX = (21.0, 56.0, 21.0)
HEAD_ENVELOPE_PX = (18.0, 18.0, 18.0)
AUTHORED_PART_COUNT = 41
MIN_SOLID_ENVELOPE_RATIO = 0.12
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_plague_doctor_56px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_plague_doctor_56px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


@dataclass(frozen=True)
class PartSpec:
    name: str
    center_px: tuple[float, float, float]
    size_px: tuple[float, float, float]
    material_key: str
    bone: str


PART_SPECS: tuple[PartSpec, ...] = (
    # Boots with leather straps & trousers.
    PartSpec("boot_left_heel", (-5.0, 0.5, 2.0), (5.0, 7.0, 4.0), "leather_dark", "Foot.L"),
    PartSpec("boot_left_toe", (-5.0, -4.0, 2.0), (5.0, 2.0, 4.0), "leather_dark", "Foot.L"),
    PartSpec("shin_left", (-5.0, 0.5, 8.0), (5.0, 5.0, 8.0), "cloth_black", "LowerLeg.L"),
    PartSpec("thigh_left", (-4.5, 0.5, 18.0), (6.0, 6.0, 10.0), "cloth_black", "UpperLeg.L"),

    PartSpec("boot_right_heel", (5.0, 0.5, 2.0), (5.0, 7.0, 4.0), "leather_dark", "Foot.R"),
    PartSpec("boot_right_toe", (5.0, -4.0, 2.0), (5.0, 2.0, 4.0), "leather_dark", "Foot.R"),
    PartSpec("shin_right", (5.0, 0.5, 8.0), (5.0, 5.0, 8.0), "cloth_black", "LowerLeg.R"),
    PartSpec("thigh_right", (4.5, 0.5, 18.0), (6.0, 6.0, 10.0), "cloth_black", "UpperLeg.R"),

    # Flared 3-tier Tailcoat Skirt (Breaking straight geometry).
    PartSpec("pelvis_core", (0.0, 0.5, 24.0), (12.0, 7.0, 4.0), "cloth_black", "Pelvis"),
    PartSpec("coat_skirt_front", (0.0, -3.5, 20.0), (12.0, 1.0, 10.0), "cloth_black", "Pelvis"),
    PartSpec("coat_skirt_back_upper", (0.0, 4.5, 20.0), (12.0, 1.0, 10.0), "cloth_dark_gray", "Pelvis"),
    PartSpec("coat_skirt_back_mid", (0.0, 5.5, 14.0), (14.0, 1.0, 8.0), "cloth_black", "Pelvis"),
    PartSpec("coat_skirt_back_lower", (0.0, 6.5, 9.0), (14.0, 1.0, 6.0), "cloth_dark_gray", "Pelvis"),
    PartSpec("coat_skirt_left_flare", (-6.5, 0.5, 18.0), (1.0, 8.0, 12.0), "cloth_black", "Pelvis"),
    PartSpec("coat_skirt_right_flare", (6.5, 0.5, 18.0), (1.0, 8.0, 12.0), "cloth_black", "Pelvis"),

    # Torso, Leather Shoulder Cape, & Reagent Bandolier.
    PartSpec("torso_core", (0.0, 0.5, 32.0), (12.0, 7.0, 12.0), "cloth_black", "Torso"),
    PartSpec("shoulder_cape_back", (0.0, 4.5, 35.0), (14.0, 1.0, 8.0), "leather_dark", "Torso"),
    PartSpec("shoulder_cape_left", (-7.5, 0.5, 37.0), (3.0, 7.0, 4.0), "leather_dark", "Torso"),
    PartSpec("shoulder_cape_right", (7.5, 0.5, 37.0), (3.0, 7.0, 4.0), "leather_dark", "Torso"),
    PartSpec("bandolier_strap", (0.0, -3.5, 32.0), (10.0, 1.0, 10.0), "leather_dark", "Torso"),
    PartSpec("reagent_bottle_green", (-3.0, -4.5, 30.0), (2.0, 1.0, 3.0), "reagent_green", "Torso"),
    PartSpec("reagent_bottle_yellow", (3.0, -4.5, 33.0), (2.0, 1.0, 3.0), "reagent_yellow", "Torso"),

    # Sleeves & Gloved Hands.
    PartSpec("shoulder_left", (-8.5, 0.5, 36.0), (4.0, 5.0, 4.0), "cloth_black", "UpperArm.L"),
    PartSpec("upper_arm_left", (-8.5, 0.5, 32.0), (4.0, 5.0, 4.0), "cloth_black", "UpperArm.L"),
    PartSpec("forearm_left", (-8.5, -2.5, 27.0), (4.0, 5.0, 6.0), "cloth_dark_gray", "LowerArm.L"),
    PartSpec("glove_left", (-8.5, -4.5, 23.0), (4.0, 4.0, 4.0), "leather_dark", "Hand.L"),

    PartSpec("shoulder_right", (8.5, 0.5, 36.0), (4.0, 5.0, 4.0), "cloth_black", "UpperArm.R"),
    PartSpec("upper_arm_right", (8.5, 0.5, 32.0), (4.0, 5.0, 4.0), "cloth_black", "UpperArm.R"),
    PartSpec("forearm_right", (8.5, -2.5, 27.0), (4.0, 5.0, 6.0), "cloth_dark_gray", "LowerArm.R"),
    PartSpec("glove_right", (8.5, -4.5, 23.0), (4.0, 4.0, 4.0), "leather_dark", "Hand.R"),

    # Neck, Pale Bird Beak Mask, Brass Goggles & Wide-Brimmed Flat Hat.
    PartSpec("neck_core", (0.0, 0.5, 39.0), (6.0, 5.0, 2.0), "cloth_black", "Neck"),
    PartSpec("head_core", (0.0, 0.5, 45.0), (8.0, 8.0, 8.0), "mask_bone", "Head"),
    PartSpec("beak_step_1", (0.0, -4.5, 44.0), (6.0, 2.0, 6.0), "mask_bone", "Head"),
    PartSpec("beak_step_2", (0.0, -7.5, 43.0), (4.0, 4.0, 4.0), "mask_bone", "Head"),
    PartSpec("beak_tip", (0.0, -10.5, 42.0), (2.0, 2.0, 3.0), "mask_bone", "Head"),

    # Brass Goggles with Glowing Green Lenses.
    PartSpec("goggles_frame", (0.0, -4.0, 47.0), (10.0, 1.0, 3.0), "brass_frame", "Head"),
    PartSpec("goggles_lens_left", (-2.5, -4.5, 47.0), (3.0, 1.0, 2.0), "reagent_green", "Head"),
    PartSpec("goggles_lens_right", (2.5, -4.5, 47.0), (3.0, 1.0, 2.0), "reagent_green", "Head"),

    # Iconic Flat-Topped Wide-Brimmed Hat (reaching Z = 56.0).
    PartSpec("hat_brim", (0.0, 0.5, 49.5), (18.0, 18.0, 1.0), "cloth_black", "Head"),
    PartSpec("hat_band", (0.0, 0.5, 51.0), (12.0, 12.0, 2.0), "hat_ribbon_red", "Head"),
    PartSpec("hat_crown", (0.0, 0.5, 54.0), (12.0, 12.0, 4.0), "cloth_black", "Head"),
)


def _build_palette() -> dict[str, bpy.types.Material]:
    return {
        "cloth_black": make_material("cloth_black", (0.10, 0.10, 0.12, 1.0), roughness=0.8),
        "cloth_dark_gray": make_material("cloth_dark_gray", (0.18, 0.18, 0.20, 1.0), roughness=0.8),
        "leather_dark": make_material("leather_dark", (0.15, 0.10, 0.06, 1.0), roughness=0.6),
        "mask_bone": make_material("mask_bone", (0.85, 0.80, 0.70, 1.0), roughness=0.5),
        "brass_frame": make_material("brass_frame", (0.75, 0.60, 0.20, 1.0), roughness=0.3, metallic=0.8),
        "reagent_green": make_material("reagent_green", (0.10, 0.95, 0.30, 1.0), roughness=0.1, metallic=0.1, emission=2.5),
        "reagent_yellow": make_material("reagent_yellow", (0.95, 0.85, 0.15, 1.0), roughness=0.1, metallic=0.1, emission=2.5),
        "hat_ribbon_red": make_material("hat_ribbon_red", (0.60, 0.10, 0.10, 1.0), roughness=0.6),
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
            f"plague_doctor part count is {len(PART_SPECS)}, expected {AUTHORED_PART_COUNT}"
        )
    envelope = _compute_envelope(PART_SPECS)
    if envelope != TARGET_ENVELOPE_PX:
        raise RuntimeError(
            f"plague_doctor envelope is {envelope}px, expected {TARGET_ENVELOPE_PX}px"
        )
    vol = sum(p.size_px[0] * p.size_px[1] * p.size_px[2] for p in PART_SPECS)
    target_vol = (
        TARGET_ENVELOPE_PX[0] * TARGET_ENVELOPE_PX[1] * TARGET_ENVELOPE_PX[2]
    )
    ratio = vol / target_vol
    if ratio < MIN_SOLID_ENVELOPE_RATIO:
        raise RuntimeError(
            f"plague_doctor volume ratio {ratio:.3f} < threshold {MIN_SOLID_ENVELOPE_RATIO:.3f}"
        )


def build_plague_doctor_mesh() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
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
    root, parts_objs, parts_by_bone = build_plague_doctor_mesh()
    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    STATIC_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(root, STATIC_OUTPUT)

    # 2. 导出 Rigged GLB
    root, parts_objs, parts_by_bone = build_plague_doctor_mesh()
    armature = create_voxel_humanoid_armature(height_px=56.0, name="Armature")
    parent_parts_by_bone(parts_by_bone, armature)
    RIG_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(armature, RIG_OUTPUT)

    # 3. 渲染 3D 视觉图片
    root, parts_objs, _ = build_plague_doctor_mesh()
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
