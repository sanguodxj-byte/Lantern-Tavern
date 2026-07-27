from __future__ import annotations

"""Independently authored voxel black_rye_root brewing-material model.

Identity: gnarled dark root with soil clumps, laid long
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

MODEL_ID = "black_rye_root"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "gnarled dark root with soil clumps, laid long"

def build_model():
    root_m = make_material("brr_root", (0.28, 0.18, 0.10, 1.0), roughness=0.90)
    dark = make_material("brr_dark", (0.14, 0.08, 0.05, 1.0), roughness=0.92)
    soil = make_material("brr_soil", (0.42, 0.28, 0.14, 1.0), roughness=0.95)
    pale = make_material("brr_pale", (0.48, 0.35, 0.22, 1.0), roughness=0.88)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("main", (0.0, 0.0, stack_center(0.0, 3.0)), (16.0, 3.0, 3.0), root_m)
    add("knob_a", (-4.0, 0.0, stack_center(3.0, 2.0)), (3.0, 2.0, 2.0), dark)
    add("knob_b", (3.0, 0.5, stack_center(3.0, 1.0)), (4.0, 2.0, 1.0), pale)
    br_c = (face_attachment_center(0.0, 8.0, 2.0, 1.0), 0.0, stack_center(0.0, 2.0))
    add("branch", br_c, (4.0, 2.0, 2.0), dark)
    add("tip", (face_attachment_center(br_c[0], 2.0, 1.0, 1.0), 0.0, stack_center(0.0, 1.0)), (2.0, 1.0, 1.0), pale)
    add("soil_a", (-2.0, face_attachment_center(0.0, 1.5, 0.5, 1.0), stack_center(0.0, 2.0)), (3.0, 1.0, 2.0), soil)
    add("soil_b", (5.0, face_attachment_center(0.0, 1.5, 0.5, -1.0), stack_center(1.0, 1.0)), (2.0, 1.0, 1.0), soil)
    add("fork", (-6.0, face_attachment_center(0.0, 1.5, 1.0, -1.0), stack_center(0.0, 2.0)), (3.0, 2.0, 2.0), dark)
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
