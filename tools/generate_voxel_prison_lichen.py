from __future__ import annotations

"""Independently authored voxel prison_lichen brewing-material model.

Identity: flat crusty lichen mat with spore cups
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

MODEL_ID = "prison_lichen"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "flat crusty lichen mat with spore cups"

def build_model():
    lichen = make_material("pl_lichen", (0.55, 0.58, 0.32, 1.0), roughness=0.90)
    dark = make_material("pl_dark", (0.32, 0.36, 0.18, 1.0), roughness=0.92)
    pale = make_material("pl_pale", (0.70, 0.72, 0.48, 1.0), roughness=0.85)
    cup = make_material("pl_cup", (0.62, 0.42, 0.28, 1.0), roughness=0.80)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("mat", (0.0, 0.0, stack_center(0.0, 1.0)), (10.0, 7.0, 1.0), lichen)
    add("lobe_x", (face_attachment_center(0.0, 5.0, 1.5, 1.0), -1.0, stack_center(0.0, 1.0)), (3.0, 3.0, 1.0), pale)
    add("lobe_y", (-2.5, face_attachment_center(0.0, 3.5, 1.0, 1.0), stack_center(0.0, 1.0)), (4.0, 2.0, 1.0), dark)
    add("lobe_ny", (2.0, face_attachment_center(0.0, 3.5, 1.0, -1.0), stack_center(0.0, 1.0)), (3.0, 2.0, 1.0), pale)
    add("cup_a", (-2.0, 1.0, stack_center(1.0, 1.0)), (2.0, 2.0, 1.0), cup)
    add("cup_b", (2.0, -1.0, stack_center(1.0, 1.0)), (1.0, 1.0, 1.0), cup)
    add("spot", (0.5, 0.5, stack_center(1.0, 1.0)), (1.0, 1.0, 1.0), dark)
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
