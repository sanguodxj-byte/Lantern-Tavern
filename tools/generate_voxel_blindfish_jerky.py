from __future__ import annotations

"""Independently authored voxel blindfish_jerky brewing-material model.

Identity: long dried fish strip with salt crust
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

MODEL_ID = "blindfish_jerky"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "long dried fish strip with salt crust"

def build_model():
    meat = make_material("bj_meat", (0.62, 0.48, 0.32, 1.0), roughness=0.88)
    dark = make_material("bj_dark", (0.38, 0.26, 0.16, 1.0), roughness=0.90)
    salt = make_material("bj_salt", (0.88, 0.88, 0.82, 1.0), roughness=0.75)
    skin = make_material("bj_skin", (0.50, 0.55, 0.48, 1.0), roughness=0.70)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("strip", (0.0, 0.0, stack_center(0.0, 2.0)), (18.0, 3.0, 2.0), meat)
    add("head_end", (face_attachment_center(0.0, 9.0, 2.0, -1.0), 0.0, stack_center(0.0, 3.0)), (4.0, 4.0, 3.0), dark)
    add("tail_end", (face_attachment_center(0.0, 9.0, 2.0, 1.0), 0.5, stack_center(0.0, 1.0)), (4.0, 2.0, 1.0), skin)
    add("salt_a", (-3.0, 0.0, stack_center(2.0, 1.0)), (4.0, 1.0, 1.0), salt)
    add("salt_b", (4.0, 0.5, stack_center(2.0, 1.0)), (3.0, 1.0, 1.0), salt)
    add("ridge", (1.0, face_attachment_center(0.0, 1.5, 0.5, 1.0), stack_center(1.0, 1.0)), (6.0, 1.0, 1.0), dark)
    add("fin_nub", (-6.0, face_attachment_center(0.0, 1.5, 0.5, -1.0), stack_center(0.0, 2.0)), (2.0, 1.0, 2.0), skin)
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
