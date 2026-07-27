from __future__ import annotations

"""Independently authored voxel wolfear_herb brewing-material model.

Identity: paired ear-shaped green leaves on short stem
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

MODEL_ID = "wolfear_herb"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "paired ear-shaped green leaves on short stem"

def build_model():
    leaf = make_material("we_leaf", (0.28, 0.55, 0.22, 1.0), roughness=0.82)
    leaf_dark = make_material("we_dark", (0.14, 0.32, 0.14, 1.0), roughness=0.85)
    vein = make_material("we_vein", (0.45, 0.68, 0.30, 1.0), roughness=0.75)
    stem = make_material("we_stem", (0.35, 0.28, 0.12, 1.0), roughness=0.88)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("stem", (0.0, 0.0, stack_center(0.0, 3.0)), (2.0, 2.0, 3.0), stem)
    leaf_l_c = (face_attachment_center(0.0, 1.0, 3.0, -1.0), 0.0, stack_center(2.0, 2.0))
    leaf_r_c = (face_attachment_center(0.0, 1.0, 3.0, 1.0), 0.5, stack_center(2.0, 2.0))
    add("leaf_l", leaf_l_c, (6.0, 3.0, 2.0), leaf)
    add("leaf_r", leaf_r_c, (6.0, 3.0, 2.0), leaf_dark)
    add("tip_l", (face_attachment_center(leaf_l_c[0], 3.0, 0.5, -1.0), leaf_l_c[1], stack_center(2.0, 1.0)), (1.0, 2.0, 1.0), vein)
    add("tip_r", (face_attachment_center(leaf_r_c[0], 3.0, 0.5, 1.0), leaf_r_c[1], stack_center(2.0, 1.0)), (1.0, 2.0, 1.0), vein)
    add("vein_l", (leaf_l_c[0], leaf_l_c[1], stack_center(4.0, 1.0)), (3.0, 1.0, 1.0), vein)
    add("vein_r", (leaf_r_c[0], leaf_r_c[1], stack_center(4.0, 1.0)), (3.0, 1.0, 1.0), vein)
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
