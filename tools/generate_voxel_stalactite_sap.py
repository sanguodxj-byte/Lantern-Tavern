from __future__ import annotations

"""Independently authored voxel stalactite_sap brewing-material model.

Identity: hanging amber sap drop with crystal skin
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

MODEL_ID = "stalactite_sap"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "hanging amber sap drop with crystal skin"

def build_model():
    sap = make_material("ss_sap", (0.85, 0.55, 0.18, 1.0), roughness=0.35, emission=0.3)
    deep = make_material("ss_deep", (0.55, 0.28, 0.08, 1.0), roughness=0.42)
    skin = make_material("ss_skin", (0.95, 0.78, 0.45, 1.0), roughness=0.28, emission=0.5)
    tip = make_material("ss_tip", (0.98, 0.88, 0.55, 1.0), roughness=0.22, emission=0.8)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("base_bulb", (0.0, 0.0, stack_center(0.0, 3.0)), (5.0, 5.0, 3.0), deep)
    add("mid", (0.0, 0.0, stack_center(3.0, 4.0)), (4.0, 4.0, 4.0), sap)
    add("neck", (0.0, 0.0, stack_center(7.0, 2.0)), (3.0, 3.0, 2.0), skin)
    add("point", (0.0, 0.0, stack_center(9.0, 3.0)), (2.0, 2.0, 3.0), tip)
    add("side_glint", (face_attachment_center(0.0, 2.0, 0.5, 1.0), 0.0, stack_center(4.0, 2.0)), (1.0, 2.0, 2.0), skin)
    add("drip_bead", (0.5, face_attachment_center(0.0, 2.0, 0.5, -1.0), stack_center(5.0, 1.0)), (1.0, 1.0, 1.0), tip)
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
