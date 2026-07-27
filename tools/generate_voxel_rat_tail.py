from __future__ import annotations

"""Independently authored voxel rat_tail brewing-material model.

Identity: segmented pink-brown rat tail with joints and horn tip
Blank-slate redesign. Shared mechanical helpers only.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from voxel_material_finish import (  # noqa: E402
    mesh_world_bbox_m,
    publish_material_preview_aliases,
    update_material_manifest_entry,
)
from voxel_model_primitives import (  # noqa: E402
    cube_px,
    face_attachment_center,
    finish_model,
    make_material,
    make_root,
    reset_scene,
    stack_center,
)
from voxel_single_model_cli import reject_target_override  # noqa: E402

MODEL_ID = "rat_tail"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "segmented pink-brown rat tail with joints and horn tip"

def build_model():
    flesh_mid = make_material("rt_mid", (0.62, 0.34, 0.30, 1.0), roughness=0.86)
    flesh_dark = make_material("rt_dark", (0.38, 0.16, 0.14, 1.0), roughness=0.90)
    flesh_pale = make_material("rt_pale", (0.78, 0.52, 0.46, 1.0), roughness=0.82)
    tip_horn = make_material("rt_tip", (0.22, 0.10, 0.09, 1.0), roughness=0.78)
    scab = make_material("rt_scab", (0.48, 0.22, 0.18, 1.0), roughness=0.88)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    # Build along +X as a grounded chain of face-contact segments.
    add("stump", (2.0, 0.0, stack_center(0.0, 4.0)), (4.0, 4.0, 4.0), flesh_dark)
    add("stump_ring", (2.0, 0.0, stack_center(4.0, 1.0)), (3.0, 3.0, 1.0), flesh_pale)
    add("seg_a", (6.5, 0.5, stack_center(0.0, 3.0)), (5.0, 3.0, 3.0), flesh_mid)
    add("joint_a", (6.5, 0.5, stack_center(3.0, 1.0)), (3.0, 2.0, 1.0), scab)
    add("seg_b", (11.5, -0.5, stack_center(0.0, 3.0)), (5.0, 3.0, 3.0), flesh_pale)
    add("joint_b", (11.5, -0.5, stack_center(3.0, 1.0)), (3.0, 2.0, 1.0), flesh_dark)
    add("seg_c", (16.0, 0.0, stack_center(0.0, 2.0)), (4.0, 2.0, 2.0), flesh_mid)
    add("joint_c", (16.0, 0.0, stack_center(2.0, 1.0)), (2.0, 1.0, 1.0), scab)
    add("seg_d", (19.5, 0.5, stack_center(0.0, 2.0)), (3.0, 2.0, 2.0), flesh_dark)
    add("tip", (22.5, 0.5, stack_center(0.0, 1.0)), (3.0, 1.0, 1.0), tip_horn)
    add("side_scar", (8.0, face_attachment_center(0.5, 1.5, 0.5, 1.0), stack_center(1.0, 1.0)), (2.0, 1.0, 1.0), scab)
    return root

def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root = build_model()
    finish_model(
        root,
        output_path=OUT_GLB,
        preview_dir=PREVIEW_DIR,
        validation_label=MODEL_ID,
        render_stem=f"voxel_{MODEL_ID}",
        ground_offset_px=1.0,
    )
    bbox = mesh_world_bbox_m(root)
    update_material_manifest_entry(
        manifest_path=MANIFEST_PATH,
        model_id=MODEL_ID,
        bbox_m=bbox,
        shape_note=SHAPE_NOTE,
        generator_name=f"tools/generate_voxel_{MODEL_ID}.py",
    )
    publish_material_preview_aliases(preview_dir=PREVIEW_DIR, model_id=MODEL_ID)
    print(f"Wrote {OUT_GLB}")
    print(f"bbox_m={bbox[0]:.4f},{bbox[1]:.4f},{bbox[2]:.4f}")


if __name__ == "__main__":
    main()
