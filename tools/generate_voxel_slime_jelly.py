from __future__ import annotations

"""Independently authored voxel slime_jelly brewing-material model.

Identity: wobbly translucent green jelly blob with drip lobes
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

MODEL_ID = "slime_jelly"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "wobbly translucent green jelly blob with drip lobes"

def build_model():
    jelly = make_material("sj_jelly", (0.28, 0.78, 0.32, 1.0), roughness=0.35, emission=0.25)
    jelly_deep = make_material("sj_deep", (0.10, 0.42, 0.18, 1.0), roughness=0.40, emission=0.1)
    jelly_lit = make_material("sj_lit", (0.55, 0.92, 0.48, 1.0), roughness=0.28, emission=0.55)
    core = make_material("sj_core", (0.75, 1.0, 0.55, 1.0), roughness=0.22, emission=1.2)
    drip = make_material("sj_drip", (0.18, 0.58, 0.28, 1.0), roughness=0.45)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("blob_base", (0.0, 0.0, stack_center(0.0, 3.0)), (8.0, 7.0, 3.0), jelly_deep)
    add("blob_mid", (0.5, 0.0, stack_center(3.0, 3.0)), (6.0, 5.0, 3.0), jelly)
    add("blob_top", (-0.5, 0.5, stack_center(6.0, 2.0)), (4.0, 4.0, 2.0), jelly_lit)
    add("shine_plate", (face_attachment_center(0.5, 3.0, 0.5, 1.0), 0.0, stack_center(4.0, 2.0)), (1.0, 2.0, 2.0), core)
    lobe_x_c = (face_attachment_center(0.0, 4.0, 1.5, 1.0), -1.0, stack_center(0.0, 2.0))
    add("lobe_x", lobe_x_c, (3.0, 3.0, 2.0), jelly)
    add("lobe_y", (-2.0, face_attachment_center(0.0, 3.5, 1.0, 1.0), stack_center(0.0, 2.0)), (3.0, 2.0, 2.0), drip)
    add("lobe_ny", (1.5, face_attachment_center(0.0, 3.5, 1.0, -1.0), stack_center(0.0, 2.0)), (2.0, 2.0, 2.0), jelly_deep)
    add("drip_tip", (face_attachment_center(lobe_x_c[0], 1.5, 0.5, 1.0), lobe_x_c[1], stack_center(0.0, 1.0)), (1.0, 1.0, 1.0), drip)
    add("peak_bubble", (0.5, 0.0, stack_center(8.0, 1.0)), (2.0, 2.0, 1.0), core)
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
