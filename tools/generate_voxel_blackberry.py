from __future__ import annotations

"""Independently authored voxel blackberry brewing-material model.

Identity: clustered dark drupelet berry with stem nub and leaf bit
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

MODEL_ID = "blackberry"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "clustered dark drupelet berry with stem nub and leaf bit"

def build_model():
    berry = make_material("bb_berry", (0.18, 0.06, 0.18, 1.0), roughness=0.55)
    berry_lit = make_material("bb_lit", (0.38, 0.12, 0.35, 1.0), roughness=0.48)
    berry_deep = make_material("bb_deep", (0.08, 0.02, 0.10, 1.0), roughness=0.60)
    stem = make_material("bb_stem", (0.28, 0.42, 0.16, 1.0), roughness=0.82)
    leaf = make_material("bb_leaf", (0.22, 0.55, 0.18, 1.0), roughness=0.78)
    highlight = make_material("bb_hi", (0.55, 0.28, 0.50, 1.0), roughness=0.40)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("core", (0.0, 0.0, stack_center(0.0, 5.0)), (5.0, 5.0, 5.0), berry)
    add("core_top", (0.0, 0.0, stack_center(5.0, 2.0)), (4.0, 4.0, 2.0), berry_lit)
    add("drupe_x", (face_attachment_center(0.0, 2.5, 1.5, 1.0), 0.0, stack_center(1.0, 4.0)), (3.0, 3.0, 4.0), berry_deep)
    add("drupe_nx", (face_attachment_center(0.0, 2.5, 1.0, -1.0), 0.5, stack_center(1.0, 3.0)), (2.0, 3.0, 3.0), berry_lit)
    add("drupe_y", (0.5, face_attachment_center(0.0, 2.5, 1.5, 1.0), stack_center(0.5, 4.0)), (3.0, 3.0, 4.0), berry)
    add("drupe_ny", (-0.5, face_attachment_center(0.0, 2.5, 1.0, -1.0), stack_center(1.5, 3.0)), (3.0, 2.0, 3.0), berry_deep)
    add("hi_spot", (1.0, 1.0, stack_center(7.0, 1.0)), (2.0, 1.0, 1.0), highlight)
    add("stem_nub", (0.0, 0.0, stack_center(7.0, 2.0)), (1.0, 1.0, 2.0), stem)
    add("leaf_bit", (face_attachment_center(0.0, 0.5, 1.5, 1.0), 0.0, stack_center(8.0, 1.0)), (3.0, 1.0, 1.0), leaf)
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
