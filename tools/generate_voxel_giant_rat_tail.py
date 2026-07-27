from __future__ import annotations

"""Independently authored voxel giant_rat_tail brewing-material model.

Identity: thick armored giant-rat tail with heavy segments
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

MODEL_ID = "giant_rat_tail"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "thick armored giant-rat tail with heavy segments"

def build_model():
    mid = make_material("grt_mid", (0.48, 0.28, 0.22, 1.0), roughness=0.86)
    dark = make_material("grt_dark", (0.28, 0.14, 0.12, 1.0), roughness=0.90)
    pale = make_material("grt_pale", (0.62, 0.40, 0.32, 1.0), roughness=0.82)
    armor = make_material("grt_armor", (0.35, 0.22, 0.18, 1.0), roughness=0.75)
    tip = make_material("grt_tip", (0.18, 0.08, 0.06, 1.0), roughness=0.78)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("stump", (2.5, 0.0, stack_center(0.0, 5.0)), (5.0, 5.0, 5.0), dark)
    add("seg_a", (7.5, 0.0, stack_center(0.0, 4.0)), (5.0, 4.0, 4.0), mid)
    add("plate_a", (7.5, 0.0, stack_center(4.0, 1.0)), (4.0, 3.0, 1.0), armor)
    add("seg_b", (12.5, 0.5, stack_center(0.0, 4.0)), (5.0, 4.0, 4.0), pale)
    add("plate_b", (12.5, 0.5, stack_center(4.0, 1.0)), (3.0, 2.0, 1.0), armor)
    add("seg_c", (17.0, 0.0, stack_center(0.0, 3.0)), (4.0, 3.0, 3.0), mid)
    add("seg_d", (20.5, -0.5, stack_center(0.0, 2.0)), (3.0, 2.0, 2.0), dark)
    add("tip", (23.5, -0.5, stack_center(0.0, 1.0)), (3.0, 1.0, 1.0), tip)
    add("side_ridge", (7.5, face_attachment_center(0.0, 2.0, 0.5, 1.0), stack_center(1.0, 2.0)), (3.0, 1.0, 2.0), armor)
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
