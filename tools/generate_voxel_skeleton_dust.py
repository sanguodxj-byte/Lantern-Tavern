from __future__ import annotations

"""Independently authored voxel skeleton_dust brewing-material model.

Identity: ashy bone dust pile with pale shards and gray cinders
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

MODEL_ID = "skeleton_dust"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "ashy bone dust pile with pale shards and gray cinders"

def build_model():
    ash = make_material("sd_ash", (0.72, 0.70, 0.64, 1.0), roughness=0.95)
    ash_dark = make_material("sd_dark", (0.42, 0.40, 0.36, 1.0), roughness=0.92)
    bone = make_material("sd_bone", (0.88, 0.84, 0.72, 1.0), roughness=0.80)
    cinder = make_material("sd_cinder", (0.28, 0.26, 0.24, 1.0), roughness=0.88)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("pile_base", (0.0, 0.0, stack_center(0.0, 2.0)), (9.0, 7.0, 2.0), ash)
    add("pile_mid", (0.5, 0.0, stack_center(2.0, 2.0)), (6.0, 5.0, 2.0), ash_dark)
    add("pile_peak", (-0.5, 0.5, stack_center(4.0, 1.0)), (3.0, 3.0, 1.0), ash)
    add("shard_a", (face_attachment_center(0.0, 4.5, 1.5, 1.0), 1.0, stack_center(0.0, 1.0)), (3.0, 1.0, 1.0), bone)
    add("shard_b", (-2.0, face_attachment_center(0.0, 3.5, 0.5, 1.0), stack_center(1.0, 1.0)), (2.0, 1.0, 1.0), bone)
    add("cinder_a", (face_attachment_center(0.5, 3.0, 0.5, 1.0), -1.0, stack_center(3.0, 1.0)), (1.0, 1.0, 1.0), cinder)
    add("cinder_b", (-0.5, 0.5, stack_center(5.0, 1.0)), (1.0, 1.0, 1.0), cinder)
    add("lobe", (face_attachment_center(0.0, 4.5, 1.0, -1.0), -1.5, stack_center(0.0, 1.0)), (2.0, 3.0, 1.0), ash_dark)
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
