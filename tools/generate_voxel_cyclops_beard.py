from __future__ import annotations

"""Independently authored voxel cyclops_beard brewing-material model.

Identity: tuft of coarse gray-brown whiskers
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

MODEL_ID = "cyclops_beard"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "tuft of coarse gray-brown whiskers"

def build_model():
    hair = make_material("cb_hair", (0.55, 0.48, 0.38, 1.0), roughness=0.88)
    dark = make_material("cb_dark", (0.32, 0.26, 0.20, 1.0), roughness=0.90)
    pale = make_material("cb_pale", (0.72, 0.66, 0.55, 1.0), roughness=0.82)
    root_m = make_material("cb_root", (0.42, 0.28, 0.22, 1.0), roughness=0.85)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("root_pad", (0.0, 0.0, stack_center(0.0, 2.0)), (5.0, 3.0, 2.0), root_m)
    add("strand_a", (-1.5, 0.0, stack_center(2.0, 10.0)), (1.0, 1.0, 10.0), hair)
    add("strand_b", (0.0, 0.5, stack_center(2.0, 12.0)), (1.0, 1.0, 12.0), dark)
    add("strand_c", (1.5, -0.5, stack_center(2.0, 9.0)), (1.0, 1.0, 9.0), pale)
    add("strand_d", (-0.5, -1.0, stack_center(2.0, 7.0)), (1.0, 1.0, 7.0), hair)
    add("tip_b", (0.0, 0.5, stack_center(14.0, 2.0)), (1.0, 1.0, 2.0), pale)
    add("clump_side", (face_attachment_center(0.0, 2.5, 0.5, 1.0), 0.0, stack_center(1.0, 3.0)), (1.0, 2.0, 3.0), dark)
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
