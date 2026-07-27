from __future__ import annotations

"""Independently authored voxel goblin_ear brewing-material model.

Identity: pointed green goblin ear tip with cartilage ridge
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

MODEL_ID = "goblin_ear"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "pointed green goblin ear tip with cartilage ridge"

def build_model():
    skin = make_material("ge_skin", (0.32, 0.55, 0.22, 1.0), roughness=0.82)
    skin_dark = make_material("ge_dark", (0.18, 0.32, 0.12, 1.0), roughness=0.85)
    skin_lit = make_material("ge_lit", (0.45, 0.68, 0.30, 1.0), roughness=0.78)
    cartilage = make_material("ge_cart", (0.55, 0.62, 0.35, 1.0), roughness=0.70)
    tip = make_material("ge_tip", (0.25, 0.40, 0.18, 1.0), roughness=0.80)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("base", (0.0, 0.0, stack_center(0.0, 3.0)), (5.0, 3.0, 3.0), skin_dark)
    add("mid", (0.5, 0.0, stack_center(3.0, 4.0)), (4.0, 2.0, 4.0), skin)
    add("upper", (0.0, 0.0, stack_center(7.0, 3.0)), (3.0, 2.0, 3.0), skin_lit)
    add("point", (0.5, 0.0, stack_center(10.0, 3.0)), (2.0, 1.0, 3.0), tip)
    add("ridge", (face_attachment_center(0.5, 2.0, 0.5, 1.0), 0.0, stack_center(4.0, 4.0)), (1.0, 1.0, 4.0), cartilage)
    add("inner_cup", (-0.5, face_attachment_center(0.0, 1.0, 0.5, -1.0), stack_center(3.0, 3.0)), (2.0, 1.0, 3.0), skin_dark)
    add("notch", (face_attachment_center(0.0, 1.5, 0.5, -1.0), 0.0, stack_center(8.0, 1.0)), (1.0, 1.0, 1.0), skin_dark)
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
