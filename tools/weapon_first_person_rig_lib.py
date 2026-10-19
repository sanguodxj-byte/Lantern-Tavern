from __future__ import annotations

"""Shared Blender mechanics for one weapon-only first-person rig.

This module intentionally contains no model registry, model IDs, model-specific poses,
or output paths. Each dedicated generate_voxel_<model_id>.py owns those decisions and
invokes this helper for exactly one model.
"""

import math
from pathlib import Path

import bpy
from mathutils import Vector

from voxel_weapon_model_lib import PX


def build_weapon_rig(
    root: bpy.types.Object,
    parts: list[bpy.types.Object],
    rig_name: str,
    bone_head_z_px: float,
    bone_tail_z_px: float,
) -> bpy.types.Object:
    bpy.ops.object.armature_add(enter_editmode=True, location=(0.0, 0.0, 0.0))
    armature = bpy.context.object
    armature.name = rig_name
    armature.data.name = f"{rig_name}Data"
    edit_bones = armature.data.edit_bones
    for bone in list(edit_bones):
        edit_bones.remove(bone)
    root_bone = edit_bones.new("WeaponRoot")
    root_bone.head = (0.0, 0.0, bone_head_z_px * PX)
    root_bone.tail = (0.0, 0.0, bone_tail_z_px * PX)
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.parent = root
    for part in parts:
        world_transform = part.matrix_world.copy()
        part.parent = armature
        part.parent_type = "BONE"
        part.parent_bone = "WeaponRoot"
        part.matrix_world = world_transform
    armature["first_person_only"] = True
    return armature


def make_action(
    armature: bpy.types.Object,
    name: str,
    frame_start: int,
    frame_end: int,
    poses,
    *,
    loop: bool = False,
) -> None:
    action = bpy.data.actions.new(name=name)
    action.name = name
    armature.animation_data_create()
    armature.animation_data.action = action
    local_end = frame_end - frame_start + 1
    bone = armature.pose.bones["WeaponRoot"]
    bone.rotation_mode = "XYZ"
    for frame, position_px, rotation_deg in poses:
        local_frame = frame - frame_start + 1
        bone.location = tuple(value * PX for value in position_px)
        bone.rotation_euler = tuple(math.radians(value) for value in rotation_deg)
        bone.keyframe_insert(data_path="location", frame=local_frame)
        bone.keyframe_insert(data_path="rotation_euler", frame=local_frame)
    curves = list(action.fcurves) if hasattr(action, "fcurves") else []
    if not curves and hasattr(action, "layers"):
        for layer in action.layers:
            for layer_strip in layer.strips:
                for bag in getattr(layer_strip, "channelbags", []):
                    curves.extend(list(getattr(bag, "fcurves", [])))
    for curve in curves:
        for point in curve.keyframe_points:
            point.interpolation = "BEZIER"
            point.handle_left_type = "AUTO_CLAMPED"
            point.handle_right_type = "AUTO_CLAMPED"
    if hasattr(action, "frame_range"):
        action.frame_range = (1, local_end)
    if hasattr(action, "use_cyclic"):
        action.use_cyclic = loop
    track = armature.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 1, action)
    strip.name = name
    strip.action_frame_start = 1
    strip.action_frame_end = local_end
    armature.animation_data.action = None


def export_animated_glb(
    root: bpy.types.Object,
    output_path: Path,
    fps: int = 30,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.context.scene.render.fps = fps
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_attributes=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
    )


def render_action_review(
    root: bpy.types.Object,
    armature: bpy.types.Object,
    preview_dir: Path,
    camera_transform: tuple[tuple[float, float, float], tuple[float, float, float]],
    samples: dict[str, tuple[str, int]],
) -> None:
    preview_dir.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 960
    scene.render.resolution_y = 540
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("WeaponFirstPersonReviewWorld")
    world.use_nodes = True
    background = next(node for node in world.node_tree.nodes if node.type == "BACKGROUND")
    background.inputs["Color"].default_value = (0.018, 0.021, 0.025, 1.0)
    background.inputs["Strength"].default_value = 0.30
    scene.world = world
    bpy.ops.object.camera_add(location=(0.0, -0.01, 0.0))
    camera = bpy.context.object
    camera.name = "WeaponFirstPersonReviewCamera"
    camera.data.lens = 30.0
    camera.data.sensor_width = 36.0
    scene.camera = camera
    position, rotation_deg = camera_transform
    root.location = position
    root.rotation_euler = tuple(math.radians(value) for value in rotation_deg)
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
    for output_name, (action_name, frame) in samples.items():
        armature.animation_data.action = bpy.data.actions[action_name]
        scene.frame_set(frame)
        scene.render.filepath = str(preview_dir / f"{output_name}.png")
        bpy.ops.render.render(write_still=True)
    armature.animation_data.action = None
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)
