#!/usr/bin/env python3
"""Generate the bandit_crossbowman character voxel asset (A-tier High Detail Remake).

Barony-style authored voxel bandit with single eyepatch, cloth bandana,
riveted leather cuirass with back fur mantle, steel bracers with metal rivets,
side quiver with red bolts, and potion pouch vials.
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

MODEL_ID = "bandit_crossbowman"
TARGET_ENVELOPE_PX = (21.0, 50.0, 15.0)
HEAD_ENVELOPE_PX = (18.0, 16.0, 16.0)
AUTHORED_PART_COUNT = 46
MIN_SOLID_ENVELOPE_RATIO = 0.12
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_bandit_crossbowman_56px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_bandit_crossbowman_56px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


@dataclass(frozen=True)
class PartSpec:
    name: str
    center_px: tuple[float, float, float]
    size_px: tuple[float, float, float]
    material_key: str
    bone: str


PART_SPECS: tuple[PartSpec, ...] = (
    # Boots and reinforced trousers.
    PartSpec("boot_left_heel", (-5.5, 0.5, 2.0), (5.0, 7.0, 4.0), "leather_dark", "Foot.L"),
    PartSpec("boot_left_toe", (-5.5, -4.0, 2.0), (5.0, 2.0, 4.0), "leather_dark", "Foot.L"),
    PartSpec("shin_left", (-5.5, 0.5, 8.0), (5.0, 5.0, 8.0), "cloth_bandana", "LowerLeg.L"),
    PartSpec("knee_left", (-5.5, 0.5, 14.0), (6.0, 6.0, 4.0), "leather_armor", "UpperLeg.L"),
    PartSpec("thigh_left", (-5.0, 0.5, 19.0), (6.0, 6.0, 6.0), "cloth_bandana", "UpperLeg.L"),

    PartSpec("boot_right_heel", (5.5, 0.5, 2.0), (5.0, 7.0, 4.0), "leather_dark", "Foot.R"),
    PartSpec("boot_right_toe", (5.5, -4.0, 2.0), (5.0, 2.0, 4.0), "leather_dark", "Foot.R"),
    PartSpec("shin_right", (5.5, 0.5, 8.0), (5.0, 5.0, 8.0), "cloth_bandana", "LowerLeg.R"),
    PartSpec("knee_right", (5.5, 0.5, 14.0), (6.0, 6.0, 4.0), "leather_armor", "UpperLeg.R"),
    PartSpec("thigh_right", (5.0, 0.5, 19.0), (6.0, 6.0, 6.0), "cloth_bandana", "UpperLeg.R"),

    # Pelvis, pouch, potion vials, and riveted leather belt.
    PartSpec("pelvis_core", (0.0, 0.5, 24.0), (12.0, 7.0, 4.0), "cloth_bandana", "Pelvis"),
    PartSpec("belt_main", (0.0, -3.5, 24.0), (12.0, 1.0, 4.0), "leather_dark", "Pelvis"),
    PartSpec("belt_buckle", (0.0, -4.5, 24.0), (3.0, 1.0, 3.0), "steel_bright", "Pelvis"),
    PartSpec("potion_pouch", (4.0, -4.0, 23.5), (3.0, 1.0, 3.0), "leather_armor", "Pelvis"),
    PartSpec("potion_vial_red", (5.5, -4.5, 23.5), (1.0, 1.0, 2.0), "fletching_red", "Pelvis"),

    # Side quiver with red-feathered bolts (armor accessory).
    PartSpec("quiver_body", (-8.5, 1.0, 26.0), (3.0, 4.0, 12.0), "leather_armor", "Pelvis"),
    PartSpec("quiver_strap", (-4.0, -3.5, 30.0), (8.0, 1.0, 2.0), "leather_dark", "Torso"),
    PartSpec("bolt_shafts", (-8.5, 1.0, 33.0), (2.0, 2.0, 2.0), "wood_stock", "Pelvis"),
    PartSpec("bolt_feathers", (-8.5, 1.0, 35.0), (3.0, 3.0, 2.0), "fletching_red", "Pelvis"),

    # Torso with riveted cuirass and back fur mantle.
    PartSpec("torso_core", (0.0, 0.5, 32.0), (12.0, 7.0, 12.0), "leather_armor", "Torso"),
    PartSpec("cuirass_front", (0.0, -3.5, 32.0), (10.0, 1.0, 10.0), "leather_dark", "Torso"),
    PartSpec("rivet_left", (-4.0, -4.5, 34.0), (1.0, 1.0, 2.0), "steel_bright", "Torso"),
    PartSpec("rivet_right", (4.0, -4.5, 34.0), (1.0, 1.0, 2.0), "steel_bright", "Torso"),
    PartSpec("fur_mantle_back", (0.0, 4.5, 35.0), (14.0, 2.0, 8.0), "fur_pelt", "Torso"),
    PartSpec("fur_mantle_shoulder_left", (-7.5, 0.5, 39.0), (4.0, 6.0, 3.0), "fur_pelt", "Torso"),
    PartSpec("fur_mantle_shoulder_right", (7.5, 0.5, 39.0), (4.0, 6.0, 3.0), "fur_pelt", "Torso"),

    # Neck and cloth mask/bandana.
    PartSpec("neck_core", (0.0, 0.5, 39.0), (6.0, 5.0, 2.0), "cloth_bandana", "Neck"),
    PartSpec("bandana_front", (0.0, -2.5, 40.0), (8.0, 1.0, 4.0), "cloth_bandana", "Neck"),

    # Left arm with steel bracer & rivets.
    PartSpec("shoulder_left", (-8.5, 0.5, 36.0), (4.0, 5.0, 4.0), "leather_armor", "UpperArm.L"),
    PartSpec("upper_arm_left", (-8.5, -1.5, 32.0), (4.0, 5.0, 4.0), "cloth_bandana", "UpperArm.L"),
    PartSpec("forearm_left", (-8.5, -5.0, 30.0), (4.0, 5.0, 4.0), "steel_dark", "LowerArm.L"),
    PartSpec("bracer_plate_left", (-8.5, -7.5, 30.0), (4.0, 1.0, 3.0), "steel_bright", "LowerArm.L"),
    PartSpec("bracer_rivet_left", (-8.5, -8.5, 30.0), (2.0, 1.0, 2.0), "steel_bright", "LowerArm.L"),
    PartSpec("glove_left", (-8.5, -8.0, 30.0), (4.0, 3.0, 4.0), "leather_dark", "Hand.L"),

    # Right arm with steel bracer & rivets.
    PartSpec("shoulder_right", (8.5, 0.5, 36.0), (4.0, 5.0, 4.0), "leather_armor", "UpperArm.R"),
    PartSpec("upper_arm_right", (8.5, 0.5, 32.0), (4.0, 5.0, 4.0), "cloth_bandana", "UpperArm.R"),
    PartSpec("forearm_right", (8.5, 0.5, 27.0), (4.0, 5.0, 6.0), "steel_dark", "LowerArm.R"),
    PartSpec("bracer_plate_right", (8.5, -2.5, 27.0), (4.0, 1.0, 3.0), "steel_bright", "LowerArm.R"),
    PartSpec("bracer_rivet_right", (8.5, -3.5, 27.0), (2.0, 1.0, 2.0), "steel_bright", "LowerArm.R"),
    PartSpec("glove_right", (8.5, 0.5, 22.0), (4.0, 5.0, 4.0), "leather_dark", "Hand.R"),

    # Head with single eyepatch & messy hair.
    PartSpec("head_core", (0.0, 0.5, 45.0), (9.0, 7.0, 6.0), "cloth_bandana", "Head"),
    PartSpec("eyepatch_lens", (-2.5, -3.5, 46.5), (3.0, 1.0, 2.0), "leather_dark", "Head"),
    PartSpec("eyepatch_strap", (0.0, 0.5, 46.5), (10.0, 8.0, 1.0), "leather_dark", "Head"),
    PartSpec("eye_right", (2.5, -3.5, 46.5), (2.0, 1.0, 1.0), "steel_bright", "Head"),
    PartSpec("hair_messy", (0.0, 1.5, 49.0), (10.0, 7.0, 2.0), "leather_dark", "Head"),
    PartSpec("hair_lock_left", (-4.0, -2.5, 48.0), (2.0, 2.0, 3.0), "leather_dark", "Head"),
)


def _build_palette() -> dict[str, bpy.types.Material]:
    return {
        "leather_armor": make_material("leather_armor", (0.28, 0.18, 0.10, 1.0), roughness=0.6),
        "leather_dark": make_material("leather_dark", (0.14, 0.09, 0.05, 1.0), roughness=0.6),
        "cloth_bandana": make_material("cloth_bandana", (0.20, 0.20, 0.22, 1.0), roughness=0.8),
        "steel_dark": make_material("steel_dark", (0.25, 0.25, 0.28, 1.0), roughness=0.3, metallic=0.7),
        "steel_bright": make_material("steel_bright", (0.75, 0.75, 0.80, 1.0), roughness=0.2, metallic=0.9),
        "wood_stock": make_material("wood_stock", (0.45, 0.28, 0.14, 1.0), roughness=0.6),
        "fletching_red": make_material("fletching_red", (0.65, 0.10, 0.10, 1.0), roughness=0.5),
        "fur_pelt": make_material("fur_pelt", (0.35, 0.28, 0.22, 1.0), roughness=0.9),
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
            f"bandit_crossbowman part count is {len(PART_SPECS)}, expected {AUTHORED_PART_COUNT}"
        )
    envelope = _compute_envelope(PART_SPECS)
    if envelope != TARGET_ENVELOPE_PX:
        raise RuntimeError(
            f"bandit_crossbowman envelope is {envelope}px, expected {TARGET_ENVELOPE_PX}px"
        )
    vol = sum(p.size_px[0] * p.size_px[1] * p.size_px[2] for p in PART_SPECS)
    target_vol = (
        TARGET_ENVELOPE_PX[0] * TARGET_ENVELOPE_PX[1] * TARGET_ENVELOPE_PX[2]
    )
    ratio = vol / target_vol
    if ratio < MIN_SOLID_ENVELOPE_RATIO:
        raise RuntimeError(
            f"bandit_crossbowman volume ratio {ratio:.3f} < threshold {MIN_SOLID_ENVELOPE_RATIO:.3f}"
        )


def build_bandit_crossbowman_mesh() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
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
    root, parts_objs, parts_by_bone = build_bandit_crossbowman_mesh()
    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    STATIC_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(root, STATIC_OUTPUT)

    # 2. 导出 Rigged GLB
    root, parts_objs, parts_by_bone = build_bandit_crossbowman_mesh()
    armature = create_voxel_humanoid_armature(height_px=52.0, name="Armature")
    parent_parts_by_bone(parts_by_bone, armature)
    RIG_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(armature, RIG_OUTPUT)

    # 3. 渲染 3D 视觉图片
    root, parts_objs, _ = build_bandit_crossbowman_mesh()
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
