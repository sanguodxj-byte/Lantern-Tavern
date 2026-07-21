#!/usr/bin/env python3
"""Generate the goblin character voxel asset (A/S tier Remake).

Barony-style authored voxel goblin with hunched posture, big pointed ears,
hooked nose, green skin, leather harness with back fur mantle, and side pouches.
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

MODEL_ID = "goblin"
TARGET_ENVELOPE_PX = (21.0, 35.0, 13.0)
HEAD_ENVELOPE_PX = (18.0, 16.0, 16.0)
AUTHORED_PART_COUNT = 38
MIN_SOLID_ENVELOPE_RATIO = 0.12
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_goblin_32px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_goblin_32px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


@dataclass(frozen=True)
class PartSpec:
    name: str
    center_px: tuple[float, float, float]
    size_px: tuple[float, float, float]
    material_key: str
    bone: str


PART_SPECS: tuple[PartSpec, ...] = (
    # Clawed feet & skinny legs.
    PartSpec("foot_left_heel", (-4.5, 0.5, 1.5), (4.0, 5.0, 3.0), "skin_green_mid", "Foot.L"),
    PartSpec("foot_left_claw", (-4.5, -3.0, 1.5), (4.0, 2.0, 2.0), "claw_bone", "Foot.L"),
    PartSpec("shin_left", (-4.5, 0.5, 6.0), (4.0, 4.0, 6.0), "skin_green_mid", "LowerLeg.L"),
    PartSpec("thigh_left", (-4.0, 0.5, 11.5), (4.0, 5.0, 5.0), "skin_green_dark", "UpperLeg.L"),

    PartSpec("foot_right_heel", (4.5, 0.5, 1.5), (4.0, 5.0, 3.0), "skin_green_mid", "Foot.R"),
    PartSpec("foot_right_claw", (4.5, -3.0, 1.5), (4.0, 2.0, 2.0), "claw_bone", "Foot.R"),
    PartSpec("shin_right", (4.5, 0.5, 6.0), (4.0, 4.0, 6.0), "skin_green_dark", "LowerLeg.R"),
    PartSpec("thigh_right", (4.0, 0.5, 11.5), (4.0, 5.0, 5.0), "skin_green_mid", "UpperLeg.R"),

    # Pelvis, tattered loincloth & side pouches.
    PartSpec("pelvis_core", (0.0, 0.5, 15.0), (9.0, 6.0, 4.0), "skin_green_dark", "Pelvis"),
    PartSpec("loincloth_front", (0.0, -3.0, 13.5), (6.0, 1.0, 5.0), "cloth_red", "Pelvis"),
    PartSpec("belt_harness", (0.0, -3.5, 15.5), (9.0, 1.0, 2.0), "leather_dark", "Pelvis"),
    PartSpec("side_pouch_left", (-5.0, -2.5, 14.5), (2.0, 2.0, 3.0), "leather_harness", "Pelvis"),

    # Hunched Torso with back fur mantle & leather chest harness.
    PartSpec("torso_core", (0.0, 0.5, 21.0), (10.0, 6.0, 8.0), "skin_green_mid", "Torso"),
    PartSpec("torso_hunch_back", (0.0, 3.5, 23.0), (10.0, 2.0, 8.0), "fur_mantle", "Torso"),
    PartSpec("chest_harness_strap", (0.0, -3.0, 22.0), (8.0, 1.0, 6.0), "leather_harness", "Torso"),
    PartSpec("harness_buckle", (0.0, -4.0, 23.0), (2.0, 1.0, 2.0), "claw_bone", "Torso"),

    # Thin arms & clawed hands.
    PartSpec("shoulder_left", (-6.5, 0.5, 23.0), (3.0, 4.0, 4.0), "skin_green_mid", "UpperArm.L"),
    PartSpec("forearm_left", (-7.0, -1.5, 19.0), (3.0, 4.0, 4.0), "skin_green_dark", "LowerArm.L"),
    PartSpec("hand_left", (-7.0, -4.5, 18.0), (3.0, 3.0, 3.0), "skin_green_mid", "Hand.L"),

    PartSpec("shoulder_right", (6.5, 0.5, 23.0), (3.0, 4.0, 4.0), "skin_green_dark", "UpperArm.R"),
    PartSpec("forearm_right", (7.0, -1.5, 19.0), (3.0, 4.0, 4.0), "skin_green_mid", "LowerArm.R"),
    PartSpec("hand_right", (7.0, -4.5, 18.0), (3.0, 3.0, 3.0), "skin_green_dark", "Hand.R"),

    # Neck and forward-leaning Goblin Head.
    PartSpec("neck_core", (0.0, 0.5, 26.0), (4.0, 4.0, 2.0), "skin_green_dark", "Neck"),
    PartSpec("head_cranium", (0.0, -1.0, 31.0), (9.0, 8.0, 8.0), "skin_green_mid", "Head"),
    PartSpec("head_brow", (0.0, -4.5, 33.0), (9.0, 2.0, 2.0), "skin_green_dark", "Head"),

    # Expressive Goblin Face: Hooked Nose, Tusks, Glowing Yellow Eyes.
    PartSpec("nose_hook_base", (0.0, -5.5, 31.5), (3.0, 2.0, 3.0), "skin_green_mid", "Head"),
    PartSpec("nose_hook_tip", (0.0, -7.5, 30.5), (2.0, 2.0, 2.0), "skin_green_dark", "Head"),
    PartSpec("mouth_cavity", (0.0, -5.0, 28.5), (6.0, 1.0, 2.0), "skin_green_dark", "Head"),
    PartSpec("tusk_left", (-2.0, -5.5, 29.0), (1.0, 1.0, 2.0), "claw_bone", "Head"),
    PartSpec("tusk_right", (2.0, -5.5, 29.0), (1.0, 1.0, 2.0), "claw_bone", "Head"),
    PartSpec("eye_left", (-2.5, -4.5, 32.5), (2.0, 1.0, 2.0), "eye_yellow", "Head"),
    PartSpec("eye_right", (2.5, -4.5, 32.5), (2.0, 1.0, 2.0), "eye_yellow", "Head"),

    # Giant Pointed Ears (reaching X = 20.0 envelope).
    PartSpec("ear_base_left", (-5.0, 0.5, 32.0), (2.0, 3.0, 4.0), "skin_green_dark", "Head"),
    PartSpec("ear_mid_left", (-7.5, 1.5, 33.0), (3.0, 3.0, 3.0), "skin_green_mid", "Head"),
    PartSpec("ear_tip_left", (-9.5, 2.5, 34.0), (2.0, 2.0, 2.0), "skin_green_dark", "Head"),

    PartSpec("ear_base_right", (5.0, 0.5, 32.0), (2.0, 3.0, 4.0), "skin_green_mid", "Head"),
    PartSpec("ear_mid_right", (7.5, 1.5, 33.0), (3.0, 3.0, 3.0), "skin_green_dark", "Head"),
    PartSpec("ear_tip_right", (9.5, 2.5, 34.0), (2.0, 2.0, 2.0), "skin_green_mid", "Head"),
)


def _build_palette() -> dict[str, bpy.types.Material]:
    return {
        "skin_green_mid": make_material("skin_green_mid", (0.35, 0.55, 0.20, 1.0), roughness=0.7),
        "skin_green_dark": make_material("skin_green_dark", (0.20, 0.35, 0.12, 1.0), roughness=0.8),
        "cloth_red": make_material("cloth_red", (0.55, 0.10, 0.08, 1.0), roughness=0.8),
        "leather_dark": make_material("leather_dark", (0.16, 0.10, 0.05, 1.0), roughness=0.7),
        "leather_harness": make_material("leather_harness", (0.28, 0.18, 0.10, 1.0), roughness=0.6),
        "fur_mantle": make_material("fur_mantle", (0.22, 0.18, 0.15, 1.0), roughness=0.9),
        "eye_yellow": make_material("eye_yellow", (1.00, 0.85, 0.15, 1.0), roughness=0.1, metallic=0.1, emission=2.0),
        "claw_bone": make_material("claw_bone", (0.85, 0.80, 0.65, 1.0), roughness=0.6),
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
            f"goblin part count is {len(PART_SPECS)}, expected {AUTHORED_PART_COUNT}"
        )
    envelope = _compute_envelope(PART_SPECS)
    if envelope != TARGET_ENVELOPE_PX:
        raise RuntimeError(
            f"goblin envelope is {envelope}px, expected {TARGET_ENVELOPE_PX}px"
        )
    vol = sum(p.size_px[0] * p.size_px[1] * p.size_px[2] for p in PART_SPECS)
    target_vol = (
        TARGET_ENVELOPE_PX[0] * TARGET_ENVELOPE_PX[1] * TARGET_ENVELOPE_PX[2]
    )
    ratio = vol / target_vol
    if ratio < MIN_SOLID_ENVELOPE_RATIO:
        raise RuntimeError(
            f"goblin volume ratio {ratio:.3f} < threshold {MIN_SOLID_ENVELOPE_RATIO:.3f}"
        )


def build_goblin_mesh() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
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
    root, parts_objs, parts_by_bone = build_goblin_mesh()
    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    STATIC_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(root, STATIC_OUTPUT)

    # 2. 导出 Rigged GLB
    root, parts_objs, parts_by_bone = build_goblin_mesh()
    armature = create_voxel_humanoid_armature(height_px=42.0, name="Armature")
    parent_parts_by_bone(parts_by_bone, armature)
    RIG_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(armature, RIG_OUTPUT)

    # 3. 渲染 3D 视觉图片
    root, parts_objs, _ = build_goblin_mesh()
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
