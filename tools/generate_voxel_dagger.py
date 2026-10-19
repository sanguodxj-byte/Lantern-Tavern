from __future__ import annotations

"""Generate the dedicated symmetric leaf-bladed voxel dagger."""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


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


MODEL_ID = "dagger"
WIDTH_PX = 11.0
DEPTH_PX = 5.0
LENGTH_PX = 23.0

OUT_GLB = ROOT / "assets" / "meshes" / "weapons" / "weapons_voxel_dagger.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"
ANIMATION_PREVIEW_DIR = ROOT / "reports" / "first_person_animation" / "dagger_blender"
FPS = 30
ACTION_RANGES = {
    "vm_dagger_hold": (1, 30),
    "vm_melee_charge": (31, 60),
    "vm_stab_dagger": (61, 75),
    "vm_dagger_guard": (76, 92),
}


def build_dagger() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    """Build a symmetric 11 x 5 x 23px leaf dagger with a paired venom ridge."""
    dark_alloy = make_material(
        "dagger_dark_alloy", (0.10, 0.13, 0.15, 1.0), metallic=0.78, roughness=0.48
    )
    cold_steel = make_material(
        "dagger_cold_steel", (0.43, 0.54, 0.59, 1.0), metallic=0.82, roughness=0.34
    )
    bright_steel = make_material(
        "dagger_bright_steel", (0.79, 0.87, 0.90, 1.0), metallic=0.88, roughness=0.23
    )
    venom_green = make_material(
        "dagger_venom_green", (0.055, 0.29, 0.10, 1.0), roughness=0.76
    )
    blackened_bronze = make_material(
        "dagger_blackened_bronze", (0.30, 0.17, 0.055, 1.0), metallic=0.61, roughness=0.49
    )
    old_brass = make_material(
        "dagger_old_brass", (0.64, 0.40, 0.10, 1.0), metallic=0.67, roughness=0.39
    )
    wine_leather_dark = make_material(
        "dagger_wine_leather_dark", (0.18, 0.022, 0.035, 1.0), roughness=0.93
    )
    wine_leather_mid = make_material(
        "dagger_wine_leather_mid", (0.39, 0.052, 0.070, 1.0), roughness=0.86
    )

    root = make_root("weapons_voxel_dagger")
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
        depth: float,
        length: float,
        size: tuple[float, float, float],
        material: bpy.types.Material,
    ) -> None:
        add(f"{prefix}_left", (-x, depth, length), size, material)
        add(f"{prefix}_right", (x, depth, length), size, material)

    # Keep the long blade core first for the current runtime collision fallback.
    add("blade_anchor_core", (0.0, 0.0, -7.0), (3.0, 3.0, 12.0), dark_alloy)
    add_x_pair("blade_ricasso_edge", 2.0, 0.0, -2.0, (1.0, 3.0, 2.0), cold_steel)
    add_x_pair("blade_forte_edge", 2.5, 0.0, -5.0, (2.0, 3.0, 4.0), cold_steel)
    add_x_pair("blade_mid_edge", 2.0, 0.0, -9.0, (1.0, 3.0, 4.0), bright_steel)
    add("blade_taper", (0.0, 0.0, -13.5), (3.0, 3.0, 1.0), cold_steel)
    add("blade_tip", (0.0, 0.0, -14.5), (1.0, 3.0, 1.0), bright_steel)
    add("venom_ridge_front", (0.0, 2.0, -7.0), (1.0, 1.0, 12.0), venom_green)
    add("venom_ridge_back", (0.0, -2.0, -7.0), (1.0, 1.0, 12.0), venom_green)

    add("guard_center", (0.0, 0.0, 0.0), (5.0, 5.0, 2.0), blackened_bronze)
    add_x_pair("guard_arm", 3.5, 0.0, 0.0, (2.0, 3.0, 1.0), blackened_bronze)
    add_x_pair("guard_tip", 5.0, 0.0, 0.0, (1.0, 3.0, 3.0), bright_steel)

    add("grip_collar", (0.0, 0.0, 1.5), (4.0, 4.0, 1.0), old_brass)
    add("grip_upper", (0.0, 0.0, 3.0), (3.0, 3.0, 2.0), wine_leather_dark)
    add("grip_band", (0.0, 0.0, 4.5), (4.0, 4.0, 1.0), old_brass)
    add("grip_lower", (0.0, 0.0, 6.0), (3.0, 3.0, 2.0), wine_leather_mid)
    add("pommel_cap", (0.0, 0.0, 7.5), (5.0, 5.0, 1.0), old_brass)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def _build_weapon_rig(root: bpy.types.Object, parts: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.armature_add(enter_editmode=True, location=(0.0, 0.0, 0.0))
    armature = bpy.context.object
    armature.name = "DaggerRig"
    armature.data.name = "DaggerRigData"
    edit_bones = armature.data.edit_bones
    for bone in list(edit_bones):
        edit_bones.remove(bone)
    root_bone = edit_bones.new("WeaponRoot")
    root_bone.head = (0.0, 0.0, 6.0 * PX)
    root_bone.tail = (0.0, 0.0, -6.0 * PX)
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.parent = root
    for part in parts:
        world_transform = part.matrix_world.copy()
        part.parent = armature
        part.parent_type = "BONE"
        part.parent_bone = "WeaponRoot"
        part.matrix_world = world_transform
    return armature


def _set_pose(armature: bpy.types.Object, frame: int, position_px, rotation_deg) -> None:
    bone = armature.pose.bones["WeaponRoot"]
    bone.rotation_mode = "XYZ"
    bone.location = tuple(value * PX for value in position_px)
    bone.rotation_euler = tuple(math.radians(value) for value in rotation_deg)
    bone.keyframe_insert(data_path="location", frame=frame)
    bone.keyframe_insert(data_path="rotation_euler", frame=frame)


def _make_action(armature: bpy.types.Object, name: str, frame_start: int, frame_end: int, poses, *, loop: bool = False) -> None:
    action = bpy.data.actions.new(name=name)
    action.name = name
    armature.animation_data_create()
    armature.animation_data.action = action
    local_poses = [
        (frame - frame_start + 1, position_px, rotation_deg)
        for frame, position_px, rotation_deg in poses
    ]
    local_end = frame_end - frame_start + 1
    for frame, position_px, rotation_deg in local_poses:
        _set_pose(armature, frame, position_px, rotation_deg)
    curves = list(action.fcurves) if hasattr(action, "fcurves") else []
    if not curves and hasattr(action, "layers"):
        for layer in action.layers:
            for strip in layer.strips:
                for bag in getattr(strip, "channelbags", []):
                    curves.extend(list(getattr(bag, "fcurves", [])))
    for curve in curves:
        for point in curve.keyframe_points:
            point.interpolation = "BEZIER"
            point.handle_left_type = "AUTO_CLAMPED"
            point.handle_right_type = "AUTO_CLAMPED"
    track = armature.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 1, action)
    strip.name = name
    strip.action_frame_start = 1
    strip.action_frame_end = local_end
    if hasattr(action, "frame_range"):
        action.frame_range = (1, local_end)
    if hasattr(action, "use_cyclic"):
        action.use_cyclic = loop
    armature.animation_data.action = None


def _author_actions(armature: bpy.types.Object) -> None:
    _make_action(armature, "vm_dagger_hold", 1, 30, [
        (1, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
        (15, (0.0, 0.0, -0.20), (0.4, -0.6, 0.5)),
        (30, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
    ], loop=True)
    _make_action(armature, "vm_melee_charge", 31, 60, [
        (31, (-0.4, 0.1, -0.5), (2.0, -3.0, 6.0)),
        (40, (0.1, 0.5, -0.2), (-2.0, 5.0, -9.0)),
        (52, (0.6, 0.8, 0.0), (-5.0, 9.0, -15.0)),
        (60, (0.8, 0.9, 0.1), (-6.0, 11.0, -18.0)),
    ])
    _make_action(armature, "vm_stab_dagger", 61, 75, [
        (61, (0.8, 0.9, 0.1), (-6.0, 11.0, -18.0)),
        (64, (0.4, 0.6, -0.4), (-4.0, 6.0, -12.0)),
        (67, (-0.2, 0.1, -1.2), (2.0, -2.0, 7.0)),
        (70, (0.9, -0.2, -2.5), (7.0, -12.0, 24.0)),
        (73, (0.3, -0.1, -1.0), (3.0, -7.0, 14.0)),
        (75, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
    ])
    _make_action(armature, "vm_dagger_guard", 76, 92, [
        (76, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
        (82, (-0.7, 0.8, -0.5), (-6.0, 12.0, 22.0)),
        (92, (-0.7, 0.8, -0.5), (-6.0, 12.0, 22.0)),
    ])
    armature["first_person_only"] = True
    armature["action_names"] = list(ACTION_RANGES.keys())


def _export_animated_glb(root: bpy.types.Object) -> None:
    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.context.scene.render.fps = FPS
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=True, export_attributes=True,
        export_animations=True, export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
    )


def _render_animation_review(root: bpy.types.Object, armature: bpy.types.Object) -> None:
    ANIMATION_PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 960
    scene.render.resolution_y = 540
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("DaggerFirstPersonReviewWorld")
    world.use_nodes = True
    background = next(node for node in world.node_tree.nodes if node.type == "BACKGROUND")
    background.inputs["Color"].default_value = (0.018, 0.021, 0.025, 1.0)
    background.inputs["Strength"].default_value = 0.30
    scene.world = world
    bpy.ops.object.camera_add(location=(0.0, -0.01, 0.0))
    camera = bpy.context.object
    camera.name = "DaggerFirstPersonReviewCamera"
    camera.data.lens = 30.0
    camera.data.sensor_width = 36.0
    scene.camera = camera
    root.location = (0.14, -0.18, -0.52)
    root.rotation_euler = tuple(math.radians(value) for value in (10.0, -12.0, -122.0))
    bpy.ops.object.light_add(type="AREA", location=(1.2, -1.8, 1.4))
    key = bpy.context.object
    key.data.energy = 460.0
    key.data.size = 2.2
    key.rotation_euler = (Vector((0.0, 0.0, 0.0)) - key.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.light_add(type="AREA", location=(-1.3, -0.8, 0.4))
    fill = bpy.context.object
    fill.data.energy = 170.0
    fill.data.size = 2.5
    fill.rotation_euler = (Vector((0.0, 0.0, -0.6)) - fill.location).to_track_quat("-Z", "Y").to_euler()
    samples = {
        "00": ("vm_dagger_hold", 1), "01": ("vm_melee_charge", 20),
        "02": ("vm_stab_dagger", 4), "03": ("vm_stab_dagger", 7),
        "04": ("vm_stab_dagger", 10), "05": ("vm_stab_dagger", 13),
        "06": ("vm_stab_dagger", 15), "07": ("vm_dagger_guard", 12),
    }
    for output_name, (action_name, frame) in samples.items():
        armature.animation_data.action = bpy.data.actions[action_name]
        scene.frame_set(frame)
        scene.render.filepath = str(ANIMATION_PREVIEW_DIR / f"{output_name}.png")
        bpy.ops.render.render(write_still=True)
    armature.animation_data.action = None
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts = build_dagger()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    armature = _build_weapon_rig(root, parts)
    _author_actions(armature)
    _render_animation_review(root, armature)
    _export_animated_glb(root)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dimensions = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print("Scale: 1m = 32px; 1px = 1/32m")
    print(
        "Dagger envelope: "
        f"{dimensions[0]:.1f}px x {dimensions[1]:.1f}px x {dimensions[2]:.1f}px "
        f"= {dimensions[0] * PX:.4f}m x {dimensions[1] * PX:.4f}m x "
        f"{dimensions[2] * PX:.4f}m"
    )


if __name__ == "__main__":
    main()
