#!/usr/bin/env python3
"""Generate the duergar_miner character voxel asset (A-tier High Detail Remake).

Barony-style authored voxel duergar with stocky low center of gravity,
granite-grey skin, miner helm with glowing headlight, 4-tier braided beard,
iron spaulders, breastplate harness with rivets, and back ore pack with glowing crystal.
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

MODEL_ID = "duergar_miner"
TARGET_ENVELOPE_PX = (25.0, 47.0, 13.5)
HEAD_ENVELOPE_PX = (18.0, 16.0, 16.0)
AUTHORED_PART_COUNT = 44
MIN_SOLID_ENVELOPE_RATIO = 0.12
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_duergar_miner_48px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / "voxel_duergar_miner_48px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"


@dataclass(frozen=True)
class PartSpec:
    name: str
    center_px: tuple[float, float, float]
    size_px: tuple[float, float, float]
    material_key: str
    bone: str


PART_SPECS: tuple[PartSpec, ...] = (
    # Stocky dwarf legs and reinforced steel-toed boots.
    PartSpec("boot_left_heel", (-6.0, 0.5, 2.0), (6.0, 8.0, 4.0), "leather_heavy", "Foot.L"),
    PartSpec("boot_left_toe", (-6.0, -4.5, 2.0), (6.0, 2.0, 4.0), "iron_helm", "Foot.L"),
    PartSpec("shin_left", (-6.0, 0.5, 7.0), (6.0, 6.0, 6.0), "leather_heavy", "LowerLeg.L"),
    PartSpec("thigh_left", (-5.5, 0.5, 14.0), (7.0, 7.0, 8.0), "leather_heavy", "UpperLeg.L"),

    PartSpec("boot_right_heel", (6.0, 0.5, 2.0), (6.0, 8.0, 4.0), "leather_heavy", "Foot.R"),
    PartSpec("boot_right_toe", (6.0, -4.5, 2.0), (6.0, 2.0, 4.0), "iron_helm", "Foot.R"),
    PartSpec("shin_right", (6.0, 0.5, 7.0), (6.0, 6.0, 6.0), "leather_heavy", "LowerLeg.R"),
    PartSpec("thigh_right", (5.5, 0.5, 14.0), (7.0, 7.0, 8.0), "leather_heavy", "UpperLeg.R"),

    # Low wide pelvis and heavy miner apron with tool pouch & iron hooks (Breaking flat front).
    PartSpec("pelvis_core", (0.0, 0.5, 19.0), (14.0, 8.0, 4.0), "leather_heavy", "Pelvis"),
    PartSpec("apron_front", (0.0, -4.0, 15.0), (12.0, 1.0, 10.0), "leather_heavy", "Pelvis"),
    PartSpec("apron_pocket", (0.0, -5.0, 14.0), (6.0, 1.0, 4.0), "skin_duergar", "Pelvis"),
    PartSpec("tool_ring_left", (-7.5, -4.0, 18.0), (1.0, 2.0, 3.0), "iron_helm", "Pelvis"),
    PartSpec("tool_ring_right", (7.5, -4.0, 18.0), (1.0, 2.0, 3.0), "iron_helm", "Pelvis"),
    PartSpec("mini_hook", (4.0, -5.5, 15.0), (1.0, 1.0, 2.0), "iron_helm", "Pelvis"),

    # Wide dwarf torso with iron breastplate plate, rivets, & back ore backpack.
    PartSpec("torso_core", (0.0, 0.5, 27.0), (16.0, 9.0, 12.0), "leather_heavy", "Torso"),
    PartSpec("apron_bib", (0.0, -4.5, 27.0), (12.0, 1.0, 12.0), "leather_heavy", "Torso"),
    PartSpec("breastplate_center", (0.0, -5.5, 27.0), (8.0, 1.0, 8.0), "iron_helm", "Torso"),
    PartSpec("breastplate_rivet_left", (-3.0, -6.0, 29.0), (1.0, 1.0, 1.0), "lamp_light", "Torso"),
    PartSpec("breastplate_rivet_right", (3.0, -6.0, 29.0), (1.0, 1.0, 1.0), "lamp_light", "Torso"),
    PartSpec("suspenders_left", (-5.0, -5.0, 27.0), (2.0, 1.0, 12.0), "iron_helm", "Torso"),
    PartSpec("suspenders_right", (5.0, -5.0, 27.0), (2.0, 1.0, 12.0), "iron_helm", "Torso"),
    PartSpec("ore_backpack", (0.0, 5.5, 27.0), (12.0, 2.0, 10.0), "leather_heavy", "Torso"),
    PartSpec("glowing_crystal_ore", (0.0, 6.5, 33.0), (6.0, 1.0, 4.0), "lamp_light", "Torso"),

    # Iron Spaulders, Sleeves and granite-grey thick forearms.
    PartSpec("spaulder_left", (-10.0, 0.5, 33.5), (5.0, 7.0, 3.0), "iron_helm", "UpperArm.L"),
    PartSpec("shoulder_left", (-10.0, 0.5, 30.0), (4.0, 6.0, 6.0), "leather_heavy", "UpperArm.L"),
    PartSpec("forearm_left", (-10.0, 0.5, 24.0), (5.0, 6.0, 6.0), "skin_duergar", "LowerArm.L"),
    PartSpec("glove_left", (-10.0, -2.0, 21.0), (5.0, 6.0, 4.0), "leather_heavy", "Hand.L"),

    PartSpec("spaulder_right", (10.0, 0.5, 33.5), (5.0, 7.0, 3.0), "iron_helm", "UpperArm.R"),
    PartSpec("shoulder_right", (10.0, 0.5, 30.0), (4.0, 6.0, 6.0), "leather_heavy", "UpperArm.R"),
    PartSpec("forearm_right", (10.0, 0.5, 24.0), (5.0, 6.0, 6.0), "skin_duergar", "LowerArm.R"),
    PartSpec("glove_right", (10.0, -2.0, 21.0), (5.0, 6.0, 4.0), "leather_heavy", "Hand.R"),

    # Neck and low granite head.
    PartSpec("neck_core", (0.0, 0.5, 34.0), (8.0, 6.0, 2.0), "skin_duergar", "Neck"),
    PartSpec("head_core", (0.0, 0.5, 39.0), (10.0, 8.0, 8.0), "skin_duergar", "Head"),

    # 4-tier Braided Grey Beard and Moustache.
    PartSpec("beard_main", (0.0, -4.0, 34.0), (12.0, 2.0, 8.0), "beard_grey", "Head"),
    PartSpec("beard_braid_left", (-4.0, -5.0, 28.0), (3.0, 2.0, 6.0), "beard_grey", "Head"),
    PartSpec("beard_braid_right", (4.0, -5.0, 28.0), (3.0, 2.0, 6.0), "beard_grey", "Head"),
    PartSpec("beard_braid_center", (0.0, -5.0, 26.0), (4.0, 2.0, 6.0), "beard_dark_grey", "Head"),
    PartSpec("moustache", (0.0, -5.0, 37.0), (10.0, 1.0, 2.0), "beard_grey", "Head"),
    PartSpec("eye_left", (-2.5, -4.0, 40.5), (2.0, 1.0, 1.0), "lamp_light", "Head"),
    PartSpec("eye_right", (2.5, -4.0, 40.5), (2.0, 1.0, 1.0), "lamp_light", "Head"),

    # Forged Iron Miner Helmet with glowing headlight (reaching Z = 48.0).
    PartSpec("helm_dome", (0.0, 0.5, 44.5), (12.0, 9.0, 3.0), "iron_helm", "Head"),
    PartSpec("helm_brim", (0.0, -4.5, 43.5), (12.0, 2.0, 1.0), "iron_helm", "Head"),
    PartSpec("lamp_mount", (0.0, -5.0, 45.0), (4.0, 1.0, 4.0), "iron_helm", "Head"),
    PartSpec("lamp_lens_glowing", (0.0, -6.0, 45.0), (2.0, 1.0, 2.0), "lamp_light", "Head"),
)


def _build_palette() -> dict[str, bpy.types.Material]:
    return {
        "skin_duergar": make_material("skin_duergar", (0.35, 0.35, 0.38, 1.0), roughness=0.7),
        "beard_grey": make_material("beard_grey", (0.65, 0.65, 0.68, 1.0), roughness=0.8),
        "beard_dark_grey": make_material("beard_dark_grey", (0.45, 0.45, 0.48, 1.0), roughness=0.8),
        "iron_helm": make_material("iron_helm", (0.22, 0.22, 0.25, 1.0), roughness=0.4, metallic=0.7),
        "lamp_light": make_material("lamp_light", (1.00, 0.85, 0.20, 1.0), roughness=0.1, metallic=0.1, emission=2.5),
        "leather_heavy": make_material("leather_heavy", (0.20, 0.12, 0.06, 1.0), roughness=0.6),
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
            f"duergar_miner part count is {len(PART_SPECS)}, expected {AUTHORED_PART_COUNT}"
        )
    envelope = _compute_envelope(PART_SPECS)
    if envelope != TARGET_ENVELOPE_PX:
        raise RuntimeError(
            f"duergar_miner envelope is {envelope}px, expected {TARGET_ENVELOPE_PX}px"
        )
    vol = sum(p.size_px[0] * p.size_px[1] * p.size_px[2] for p in PART_SPECS)
    target_vol = (
        TARGET_ENVELOPE_PX[0] * TARGET_ENVELOPE_PX[1] * TARGET_ENVELOPE_PX[2]
    )
    ratio = vol / target_vol
    if ratio < MIN_SOLID_ENVELOPE_RATIO:
        raise RuntimeError(
            f"duergar_miner volume ratio {ratio:.3f} < threshold {MIN_SOLID_ENVELOPE_RATIO:.3f}"
        )


def build_duergar_miner_mesh() -> tuple[bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]]:
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
    root, parts_objs, parts_by_bone = build_duergar_miner_mesh()
    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    STATIC_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(root, STATIC_OUTPUT)

    # 2. 导出 Rigged GLB
    root, parts_objs, parts_by_bone = build_duergar_miner_mesh()
    armature = create_voxel_humanoid_armature(height_px=48.0, name="Armature")
    parent_parts_by_bone(parts_by_bone, armature)
    RIG_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    export_glb(armature, RIG_OUTPUT)

    # 3. 渲染 3D 视觉图片
    root, parts_objs, _ = build_duergar_miner_mesh()
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
