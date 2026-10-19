from __future__ import annotations

"""Generate the dedicated symmetric one-handed knight sword voxel model."""

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
ANIMATION_PREVIEW_DIR = ROOT / "reports" / "first_person_animation" / "sword_blender"
FPS = 30
ACTION_RANGES = {
    "vm_sword_hold": (1, 30),
    "vm_melee_charge": (31, 60),
    "vm_sword_slash": (61, 78),
    "vm_sword_guard": (79, 95),
}


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


def _build_first_person_armature(root: bpy.types.Object, parts: list[bpy.types.Object]) -> bpy.types.Object:
    """Create the sword-only first-person rig; no hand/arm/body bones exist."""
    bpy.ops.object.armature_add(enter_editmode=True, location=(0.0, 0.0, 0.0))
    armature = bpy.context.object
    armature.name = "SwordRig"
    armature.data.name = "SwordRigData"
    edit_bones = armature.data.edit_bones
    for bone in list(edit_bones):
        edit_bones.remove(bone)
    root_bone = edit_bones.new("WeaponRoot")
    root_bone.head = (0.0, 0.0, 10.0 * PX)
    root_bone.tail = (0.0, 0.0, -8.0 * PX)
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.parent = root
    for part in parts:
        world = part.matrix_world.copy()
        part.parent = armature
        part.parent_type = "BONE"
        part.parent_bone = "WeaponRoot"
        part.matrix_world = world
    return armature


def _set_pose(armature: bpy.types.Object, frame: int, position_px, rotation_deg) -> None:
    bone = armature.pose.bones["WeaponRoot"]
    bone.rotation_mode = "XYZ"
    bone.location = tuple(value * PX for value in position_px)
    bone.rotation_euler = tuple(math.radians(value) for value in rotation_deg)
    bone.keyframe_insert(data_path="location", frame=frame)
    bone.keyframe_insert(data_path="rotation_euler", frame=frame)


def _make_action(
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
    if hasattr(action, "frame_range"):
        action.frame_range = (1, local_end)
    if hasattr(action, "use_cyclic"):
        action.use_cyclic = loop
    track = armature.animation_data.nla_tracks.new()
    track.name = name
    # Each exported NLA track starts at frame 1 so Godot receives a local clip
    # timeline instead of a scene-global offset (which would create long frozen
    # prefixes for charge/slash/guard actions).
    strip = track.strips.new(name, 1, action)
    strip.name = name
    strip.action_frame_start = 1
    strip.action_frame_end = local_end
    armature.animation_data.action = None


def _author_first_person_actions(armature: bpy.types.Object) -> None:
    # All transforms are authored on the sword bone in Blender, not generated at
    # runtime. Rest frame keeps the source model's canonical axis and origin.
    _make_action(
        armature,
        "vm_sword_hold",
        1,
        30,
        [
            (1, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
            (15, (0.0, 0.0, -0.35), (0.6, -0.8, 0.45)),
            (30, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
        ],
        loop=True,
    )
    _make_action(
        armature,
        "vm_melee_charge",
        31,
        60,
        [
            (31, (-0.8, 0.3, -1.0), (4.0, -5.0, 9.0)),
            (39, (0.1, 0.8, -0.6), (-2.0, 4.0, -8.0)),
            (50, (1.0, 1.0, -0.2), (-7.0, 9.0, -16.0)),
            (60, (1.5, 1.2, 0.8), (-10.0, 12.0, -22.0)),
        ],
    )
    _make_action(
        armature,
        "vm_sword_slash",
        61,
        78,
        [
            (61, (1.5, 1.2, 0.8), (-10.0, 12.0, -22.0)),
            (64, (1.8, 1.4, 1.0), (-14.0, 16.0, -28.0)),
            (67, (-0.4, 0.5, -1.4), (7.0, -10.0, 20.0)),
            (70, (-2.2, -0.5, -2.5), (13.0, -24.0, 44.0)),
            (73, (-1.5, -0.8, -1.9), (10.0, -19.0, 36.0)),
            (76, (-0.4, -0.3, -0.6), (4.0, -7.0, 13.0)),
            (78, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
        ],
    )
    _make_action(
        armature,
        "vm_sword_guard",
        79,
        95,
        [
            (79, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
            (85, (-1.3, 1.6, -1.1), (-10.0, 20.0, 32.0)),
            (95, (-1.3, 1.6, -1.1), (-10.0, 20.0, 32.0)),
        ],
    )
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
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = max(end for _, end in ACTION_RANGES.values())
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_attributes=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
    )


def _render_first_person_action_review(root: bpy.types.Object, armature: bpy.types.Object) -> None:
    """Render neutral Blender first-person key poses for visual iteration."""
    ANIMATION_PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 960
    scene.render.resolution_y = 540
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.view_settings.look = "None"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("SwordFirstPersonReviewWorld")
    world.use_nodes = True
    bg = next(node for node in world.node_tree.nodes if node.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.018, 0.021, 0.025, 1.0)
    bg.inputs["Strength"].default_value = 0.30
    scene.world = world
    bpy.ops.object.camera_add(location=(0.0, -0.01, 0.0))
    camera = bpy.context.object
    camera.name = "SwordFirstPersonReviewCamera"
    camera.data.lens = 30.0
    camera.data.sensor_width = 36.0
    scene.camera = camera
    # Reproduce the Godot camera-space ViewModel mount with the Blender source
    # axis: blade length is -Z, camera forward is -Z after export.
    root.location = (0.22, -0.26, -0.58)
    root.rotation_euler = tuple(math.radians(value) for value in (12.0, 4.0, -144.0))
    bpy.ops.object.light_add(type="AREA", location=(1.2, -1.8, 1.4))
    key = bpy.context.object
    key.data.energy = 500.0
    key.data.shape = "DISK"
    key.data.size = 2.2
    key.rotation_euler = (Vector((0.0, 0.0, 0.0)) - key.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.light_add(type="AREA", location=(-1.3, -0.8, 0.4))
    fill = bpy.context.object
    fill.data.energy = 180.0
    fill.data.size = 2.5
    fill.rotation_euler = (Vector((0.0, 0.0, -0.6)) - fill.location).to_track_quat("-Z", "Y").to_euler()
    samples = {
        "00": ("vm_sword_hold", 1),
        "01": ("vm_melee_charge", 20),
        "02": ("vm_sword_slash", 4),
        "03": ("vm_sword_slash", 7),
        "04": ("vm_sword_slash", 10),
        "05": ("vm_sword_slash", 13),
        "06": ("vm_sword_slash", 18),
        "07": ("vm_sword_guard", 12),
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
    root, parts = build_sword()
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    armature = _build_first_person_armature(root, parts)
    _author_first_person_actions(armature)
    _render_first_person_action_review(root, armature)
    _export_animated_glb(root)
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
