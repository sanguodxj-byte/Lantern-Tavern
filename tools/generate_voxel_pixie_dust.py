from __future__ import annotations

"""Independently authored voxel pixie_dust brewing-material model.

Identity: sparkling multicolor dust mound with bright motes
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

MODEL_ID = "pixie_dust"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "sparkling multicolor dust mound with bright motes"

def build_model():
    dust = make_material("pd_dust", (0.72, 0.55, 0.85, 1.0), roughness=0.70, emission=0.4)
    dust_dark = make_material("pd_dark", (0.42, 0.28, 0.55, 1.0), roughness=0.75, emission=0.15)
    gold = make_material("pd_gold", (0.95, 0.78, 0.35, 1.0), roughness=0.35, emission=1.5)
    cyan = make_material("pd_cyan", (0.35, 0.90, 0.95, 1.0), roughness=0.30, emission=1.8)
    pink = make_material("pd_pink", (0.95, 0.45, 0.75, 1.0), roughness=0.32, emission=1.4)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("mound", (0.0, 0.0, stack_center(0.0, 3.0)), (7.0, 6.0, 3.0), dust)
    add("peak", (0.5, 0.0, stack_center(3.0, 2.0)), (4.0, 3.0, 2.0), dust_dark)
    add("mote_gold", (-1.5, 1.0, stack_center(5.0, 1.0)), (1.0, 1.0, 1.0), gold)
    add("mote_cyan", (1.5, -0.5, stack_center(5.0, 1.0)), (1.0, 1.0, 1.0), cyan)
    add("mote_pink", (0.0, 0.5, stack_center(5.0, 1.0)), (1.0, 1.0, 1.0), pink)
    add("lobe", (face_attachment_center(0.0, 3.5, 1.0, 1.0), -1.0, stack_center(0.0, 2.0)), (2.0, 3.0, 2.0), dust_dark)
    add("side_mote", (face_attachment_center(0.0, 3.5, 0.5, -1.0), 0.0, stack_center(1.0, 1.0)), (1.0, 1.0, 1.0), gold)
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
