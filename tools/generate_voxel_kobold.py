#!/usr/bin/env python3
"""Generate the kobold character voxel asset (Full Remake — A/S Tier).

Barony-style authored voxel kobold: a small hunched reptilian dragon-kin
with a forward-leaning posture, large protruding crocodilian snout,
wide-set glowing amber eyes on top of the skull, prominent swept-back
horn pair, large tri-membrane ear frills, hunched scaly back with
5-step dorsal ridge, 5-segment whip-like tail, digitigrade chicken legs,
clawed 3-finger hands, leather waist pouch, and golden belly scutes.
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

MODEL_ID = "kobold"
TARGET_ENVELOPE_PX = (16.0, 38.0, 26.0)
AUTHORED_PART_COUNT = 55
MIN_SOLID_ENVELOPE_RATIO = 0.10
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_kobold_42px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_kobold_42px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


@dataclass(frozen=True)
class PartSpec:
    name: str
    center_px: tuple[float, float, float]
    size_px: tuple[float, float, float]
    material_key: str
    bone: str


PART_SPECS: tuple[PartSpec, ...] = (
    # ===== Digitigrade reptilian legs (chicken-leg style) =====
    PartSpec("foot_left_pad", (-4.0, -2.5, 1.0), (4.0, 7.0, 2.0), "scales_dark", "Foot.L"),
    PartSpec("foot_left_claw1", (-5.5, -5.5, 1.0), (1.0, 1.0, 2.0), "horn_bone", "Foot.L"),
    PartSpec("foot_left_claw2", (-4.0, -6.5, 1.0), (2.0, 1.0, 2.0), "horn_bone", "Foot.L"),
    PartSpec("foot_left_claw3", (-2.5, -5.5, 1.0), (1.0, 1.0, 2.0), "horn_bone", "Foot.L"),
    PartSpec("shank_left", (-4.0, 1.0, 5.0), (3.0, 3.0, 6.0), "scales_red", "LowerLeg.L"),
    PartSpec("thigh_left", (-3.5, 0.5, 12.0), (4.0, 5.0, 6.0), "scales_red", "UpperLeg.L"),

    PartSpec("foot_right_pad", (4.0, -2.5, 1.0), (4.0, 7.0, 2.0), "scales_dark", "Foot.R"),
    PartSpec("foot_right_claw1", (5.5, -5.5, 1.0), (1.0, 1.0, 2.0), "horn_bone", "Foot.R"),
    PartSpec("foot_right_claw2", (4.0, -6.5, 1.0), (2.0, 1.0, 2.0), "horn_bone", "Foot.R"),
    PartSpec("foot_right_claw3", (2.5, -5.5, 1.0), (1.0, 1.0, 2.0), "horn_bone", "Foot.R"),
    PartSpec("shank_right", (4.0, 1.0, 5.0), (3.0, 3.0, 6.0), "scales_red", "LowerLeg.R"),
    PartSpec("thigh_right", (3.5, 0.5, 12.0), (4.0, 5.0, 6.0), "scales_red", "UpperLeg.R"),

    # ===== 5-segment whip tail (extending deep backward Y=+17.0) =====
    PartSpec("tail_root", (0.0, 4.0, 14.0), (4.0, 3.0, 3.0), "scales_red", "Pelvis"),
    PartSpec("tail_seg2", (0.0, 6.5, 12.0), (3.0, 2.0, 3.0), "scales_red", "Pelvis"),
    PartSpec("tail_seg3", (0.0, 9.0, 10.0), (3.0, 3.0, 2.0), "scales_dark", "Pelvis"),
    PartSpec("tail_seg4", (0.0, 12.0, 8.0), (2.0, 3.0, 2.0), "scales_red", "Pelvis"),
    PartSpec("tail_tip", (0.0, 14.5, 6.0), (2.0, 3.0, 2.0), "horn_bone", "Pelvis"),

    # ===== Pelvis / waist with golden belly scutes & leather pouch =====
    PartSpec("pelvis_core", (0.0, 0.5, 16.0), (9.0, 6.0, 4.0), "scales_red", "Pelvis"),
    PartSpec("belly_scutes_lower", (0.0, -3.0, 16.0), (7.0, 1.0, 4.0), "scales_gold", "Pelvis"),
    PartSpec("loincloth_front", (0.0, -3.0, 13.5), (7.0, 1.0, 3.0), "loincloth_leather", "Pelvis"),
    PartSpec("waist_pouch", (4.0, -3.5, 16.0), (3.0, 1.0, 3.0), "loincloth_leather", "Pelvis"),

    # ===== Hunched torso with golden belly & 5 dorsal ridge spikes =====
    PartSpec("torso_core", (0.0, 0.5, 22.0), (9.0, 6.0, 8.0), "scales_red", "Torso"),
    PartSpec("belly_scutes_upper", (0.0, -3.0, 22.0), (7.0, 1.0, 8.0), "scales_gold", "Torso"),
    PartSpec("back_hump", (0.0, 3.5, 24.0), (7.0, 1.0, 6.0), "scales_dark", "Torso"),
    PartSpec("dorsal_ridge_1", (0.0, 4.5, 18.0), (1.0, 1.0, 2.0), "horn_bone", "Torso"),
    PartSpec("dorsal_ridge_2", (0.0, 4.5, 20.5), (1.0, 1.0, 3.0), "horn_bone", "Torso"),
    PartSpec("dorsal_ridge_3", (0.0, 4.5, 23.5), (2.0, 1.0, 3.0), "horn_bone", "Torso"),
    PartSpec("dorsal_ridge_4", (0.0, 4.5, 26.0), (1.0, 1.0, 2.0), "horn_bone", "Torso"),
    PartSpec("dorsal_ridge_5", (0.0, 4.5, 28.0), (1.0, 1.0, 2.0), "horn_bone", "Torso"),

    # ===== Arms with 3-claw hands =====
    PartSpec("shoulder_left", (-6.0, 0.0, 24.0), (3.0, 4.0, 4.0), "scales_red", "UpperArm.L"),
    PartSpec("forearm_left", (-6.5, -2.0, 20.0), (3.0, 3.0, 4.0), "scales_red", "LowerArm.L"),
    PartSpec("claw_hand_left", (-6.5, -4.5, 19.0), (3.0, 2.0, 2.0), "scales_dark", "Hand.L"),
    PartSpec("claw_tip_left", (-6.5, -5.5, 18.5), (2.0, 1.0, 1.0), "horn_bone", "Hand.L"),

    PartSpec("shoulder_right", (6.0, 0.0, 24.0), (3.0, 4.0, 4.0), "scales_red", "UpperArm.R"),
    PartSpec("forearm_right", (6.5, -2.0, 20.0), (3.0, 3.0, 4.0), "scales_red", "LowerArm.R"),
    PartSpec("claw_hand_right", (6.5, -4.5, 19.0), (3.0, 2.0, 2.0), "scales_dark", "Hand.R"),
    PartSpec("claw_tip_right", (6.5, -5.5, 18.5), (2.0, 1.0, 1.0), "horn_bone", "Hand.R"),

    # ===== Neck (forward-leaning) =====
    PartSpec("neck_core", (0.0, -1.0, 27.0), (4.0, 4.0, 2.0), "scales_red", "Neck"),

    # ===== HEAD: large protruding crocodilian snout, wide-set glowing eyes =====
    # Skull — wide and flat, set forward (reptilian proportions: wider than tall)
    PartSpec("skull_rear", (0.0, 1.0, 31.0), (8.0, 6.0, 4.0), "scales_red", "Head"),
    PartSpec("skull_brow_ridge", (0.0, -2.5, 32.0), (8.0, 2.0, 2.0), "scales_dark", "Head"),
    # Snout — long protruding forward 3-step taper (KEY identity feature)
    PartSpec("snout_upper", (0.0, -5.0, 31.0), (6.0, 3.0, 3.0), "scales_red", "Head"),
    PartSpec("snout_bridge", (0.0, -7.5, 30.5), (5.0, 2.0, 2.0), "scales_dark", "Head"),
    PartSpec("snout_tip", (0.0, -9.0, 30.0), (4.0, 1.0, 2.0), "scales_gold", "Head"),
    PartSpec("nostril_left", (-1.5, -9.5, 30.5), (1.0, 1.0, 1.0), "scales_dark", "Head"),
    PartSpec("nostril_right", (1.5, -9.5, 30.5), (1.0, 1.0, 1.0), "scales_dark", "Head"),
    # Jaw — separate lower jaw with visible teeth
    PartSpec("jaw_lower", (0.0, -5.5, 28.5), (5.0, 4.0, 2.0), "scales_red", "Head"),
    PartSpec("jaw_teeth", (0.0, -7.5, 29.0), (4.0, 2.0, 1.0), "horn_bone", "Head"),
    # Eyes — large glowing amber, set wide on top of skull (classic reptile)
    PartSpec("eye_left", (-3.5, -2.0, 33.5), (2.0, 2.0, 2.0), "eye_amber", "Head"),
    PartSpec("eye_right", (3.5, -2.0, 33.5), (2.0, 2.0, 2.0), "eye_amber", "Head"),
    # Large tri-membrane ear frills (bat-wing shape, flared out wide)
    PartSpec("ear_frill_left", (-5.5, 1.0, 32.0), (3.0, 4.0, 4.0), "ear_membrane", "Head"),
    PartSpec("ear_frill_right", (5.5, 1.0, 32.0), (3.0, 4.0, 4.0), "ear_membrane", "Head"),
    # Swept-back horn pair curving upward (reaching Z = 38.0)
    PartSpec("horn_left_base", (-2.5, 3.0, 34.0), (2.0, 2.0, 2.0), "horn_bone", "Head"),
    PartSpec("horn_left_tip", (-2.5, 4.5, 37.0), (1.0, 2.0, 2.0), "horn_bone", "Head"),
    PartSpec("horn_right_base", (2.5, 3.0, 34.0), (2.0, 2.0, 2.0), "horn_bone", "Head"),
    PartSpec("horn_right_tip", (2.5, 4.5, 37.0), (1.0, 2.0, 2.0), "horn_bone", "Head"),
)


def _build_palette() -> dict[str, bpy.types.Material]:
    return {
        "scales_red": make_material("scales_red", (0.60, 0.12, 0.08, 1.0), roughness=0.55),
        "scales_dark": make_material("scales_dark", (0.30, 0.08, 0.05, 1.0), roughness=0.65),
        "scales_gold": make_material("scales_gold", (0.85, 0.65, 0.18, 1.0), roughness=0.45),
        "horn_bone": make_material("horn_bone", (0.72, 0.68, 0.52, 1.0), roughness=0.7),
        "eye_amber": make_material("eye_amber", (1.00, 0.75, 0.10, 1.0), roughness=0.1, metallic=0.1, emission=3.0),
        "ear_membrane": make_material("ear_membrane", (0.80, 0.35, 0.15, 1.0), roughness=0.4, metallic=0.0),
        "loincloth_leather": make_material("loincloth_leather", (0.22, 0.14, 0.07, 1.0), roughness=0.8),
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
            f"kobold part count is {len(PART_SPECS)}, expected {AUTHORED_PART_COUNT}"
        )
    envelope = _compute_envelope(PART_SPECS)
    if envelope != TARGET_ENVELOPE_PX:
        raise RuntimeError(
            f"kobold envelope is {envelope}px, expected {TARGET_ENVELOPE_PX}px"
        )
    vol = sum(p.size_px[0] * p.size_px[1] * p.size_px[2] for p in PART_SPECS)
    target_vol = (
        TARGET_ENVELOPE_PX[0] * TARGET_ENVELOPE_PX[1] * TARGET_ENVELOPE_PX[2]
    )
    ratio = vol / target_vol
    if ratio < MIN_SOLID_ENVELOPE_RATIO:
        raise RuntimeError(
            f"kobold volume ratio {ratio:.3f} < threshold {MIN_SOLID_ENVELOPE_RATIO:.3f}"
        )


def build_kobold_mesh() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
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
    root, parts_objs, parts_by_bone = build_kobold_mesh()
    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    STATIC_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(root, STATIC_OUTPUT)

    # 2. 导出 Rigged GLB
    root, parts_objs, parts_by_bone = build_kobold_mesh()
    armature = create_voxel_humanoid_armature(height_px=42.0, name="Armature")
    parent_parts_by_bone(parts_by_bone, armature)
    RIG_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(armature, RIG_OUTPUT)

    # 3. 渲染 3D 视觉图片
    root, parts_objs, _ = build_kobold_mesh()
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
