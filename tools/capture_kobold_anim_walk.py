#!/usr/bin/env python3
"""Capture 3D animated pose screenshots of the Kobold character for verification.

Focuses on the locomotion (walk / run) animation suite:
- Frame 1: Right leg forward stride, left arm swing back, right arm forward swing
- Frame 6: Left leg forward stride, right arm swing back, left arm forward swing
- Frame 12: Gait cycle completion
Ensures visual verification of bone rigging, leg striding, and mesh deformations.
"""

from __future__ import annotations

import math
from pathlib import Path
import sys

import bpy

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from generate_voxel_kobold import build_kobold_mesh  # noqa: E402
from voxel_humanoid_rig import (  # noqa: E402
    create_voxel_humanoid_armature,
    parent_parts_by_bone,
)
from voxel_model_primitives import (  # noqa: E402
    bounds_center_scale,
    render_real_views,
    setup_lights_and_camera,
)

OUTPUT_DIR = ROOT / "reports" / "characters_preview"


def capture_anim_pose(
    armature: bpy.types.Object,
    action_name: str,
    frame: int,
    suffix_label: str,
    center: tuple[float, float, float],
    scale: float,
    camera: bpy.types.Object,
) -> None:
    """Set armature action & frame, then render multi-angle 3D views."""
    ad = armature.animation_data
    if ad is None:
        ad = armature.animation_data_create()

    # Find the requested action (e.g. 'run', 'idle', 'slash')
    action = bpy.data.actions.get(action_name)
    if action is None:
        # Fallback: check NLA tracks for matching strip action
        for track in ad.nla_tracks:
            if track.name == action_name:
                for strip in track.strips:
                    if strip.action:
                        action = strip.action
                        break

    if action is not None:
        ad.action = action
    
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()

    # Render multi-angle 3D views
    stem = f"voxel_kobold_anim_{action_name}_f{frame}_{suffix_label}"
    render_real_views(
        OUTPUT_DIR,
        stem,
        center,
        scale,
        camera,
    )
    print(f"Captured animated pose: {stem}")


def main() -> None:
    # 1. Build mesh & armature scene in Blender
    root, parts_objs, parts_by_bone = build_kobold_mesh()
    armature = create_voxel_humanoid_armature(height_px=44.0, name="Armature")
    parent_parts_by_bone(parts_by_bone, armature)

    # 2. Add lighting and camera setup
    center, scale = bounds_center_scale(root)
    camera = setup_lights_and_camera(center, scale)

    # 3. Capture Walk/Run animation frames
    # Frame 1: Right leg forward, left leg back (Right Stride)
    capture_anim_pose(armature, "run", 1, "stride_right", center, scale, camera)

    # Frame 6: Left leg forward, right leg back (Left Stride)
    capture_anim_pose(armature, "run", 6, "stride_left", center, scale, camera)

    # Frame 12: Cycle completion
    capture_anim_pose(armature, "run", 12, "cycle_complete", center, scale, camera)

    # 4. Capture Idle Pose Verification
    capture_anim_pose(armature, "idle", 15, "mid_breath", center, scale, camera)

    print("Successfully rendered all animated pose captures!")


if __name__ == "__main__":
    main()
