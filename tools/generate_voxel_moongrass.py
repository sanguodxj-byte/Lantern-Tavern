from __future__ import annotations

"""Independently authored voxel moongrass brewing-material model.

Identity: tall pale grass blades with silver tips
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

MODEL_ID = "moongrass"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "tall pale grass blades with silver tips"

def build_model():
    blade = make_material("mg_blade", (0.55, 0.72, 0.58, 1.0), roughness=0.82)
    blade_dark = make_material("mg_dark", (0.28, 0.42, 0.30, 1.0), roughness=0.85)
    silver = make_material("mg_silver", (0.78, 0.88, 0.92, 1.0), roughness=0.45, emission=0.2)
    root_m = make_material("mg_root", (0.35, 0.28, 0.16, 1.0), roughness=0.90)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("root_clump", (0.0, 0.0, stack_center(0.0, 2.0)), (4.0, 3.0, 2.0), root_m)
    add("blade_a", (-1.0, 0.0, stack_center(2.0, 10.0)), (1.0, 1.0, 10.0), blade)
    add("tip_a", (-1.0, 0.0, stack_center(12.0, 2.0)), (1.0, 1.0, 2.0), silver)
    add("blade_b", (1.0, 0.5, stack_center(2.0, 12.0)), (1.0, 1.0, 12.0), blade_dark)
    add("tip_b", (1.0, 0.5, stack_center(14.0, 2.0)), (1.0, 1.0, 2.0), silver)
    add("blade_c", (0.0, -1.0, stack_center(2.0, 8.0)), (1.0, 1.0, 8.0), blade)
    add("tip_c", (0.0, -1.0, stack_center(10.0, 2.0)), (1.0, 1.0, 2.0), silver)
    add("side_shoot", (face_attachment_center(0.0, 2.0, 0.5, 1.0), 0.0, stack_center(1.0, 3.0)), (1.0, 1.0, 3.0), blade_dark)
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
