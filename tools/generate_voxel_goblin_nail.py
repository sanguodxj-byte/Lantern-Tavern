from __future__ import annotations

"""Independently authored voxel goblin_nail brewing-material model.

Identity: curved dirty claw nail with yellow keratin
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

MODEL_ID = "goblin_nail"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "curved dirty claw nail with yellow keratin"

def build_model():
    nail = make_material("gn_nail", (0.72, 0.62, 0.28, 1.0), roughness=0.70)
    dark = make_material("gn_dark", (0.42, 0.32, 0.14, 1.0), roughness=0.78)
    tip = make_material("gn_tip", (0.88, 0.82, 0.55, 1.0), roughness=0.55)
    grime = make_material("gn_grime", (0.28, 0.22, 0.12, 1.0), roughness=0.90)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("root_pad", (0.0, 0.0, stack_center(0.0, 3.0)), (4.0, 3.0, 3.0), dark)
    add("shaft", (0.5, 0.0, stack_center(3.0, 6.0)), (3.0, 2.0, 6.0), nail)
    add("curve", (1.5, 0.0, stack_center(9.0, 3.0)), (2.0, 2.0, 3.0), dark)
    add("point", (2.0, 0.0, stack_center(12.0, 2.0)), (1.0, 1.0, 2.0), tip)
    add("grime", (face_attachment_center(0.5, 1.5, 0.5, -1.0), 0.0, stack_center(4.0, 2.0)), (1.0, 1.0, 2.0), grime)
    add("ridge", (face_attachment_center(0.5, 1.5, 0.5, 1.0), 0.0, stack_center(5.0, 3.0)), (1.0, 1.0, 3.0), tip)
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
