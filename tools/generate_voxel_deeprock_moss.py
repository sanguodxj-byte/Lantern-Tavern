from __future__ import annotations

"""Independently authored voxel deeprock_moss brewing-material model.

Identity: wide dark mineral moss mat with stone flecks
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

MODEL_ID = "deeprock_moss"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "wide dark mineral moss mat with stone flecks"

def build_model():
    moss = make_material("drm_moss", (0.18, 0.32, 0.22, 1.0), roughness=0.92)
    dark = make_material("drm_dark", (0.10, 0.18, 0.14, 1.0), roughness=0.94)
    fleck = make_material("drm_fleck", (0.45, 0.48, 0.42, 1.0), roughness=0.70, metallic=0.15)
    wet = make_material("drm_wet", (0.12, 0.28, 0.30, 1.0), roughness=0.50)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("mat", (0.0, 0.0, stack_center(0.0, 2.0)), (14.0, 10.0, 2.0), moss)
    add("rise", (1.0, 0.0, stack_center(2.0, 2.0)), (8.0, 6.0, 2.0), dark)
    add("peak", (-1.0, 0.5, stack_center(4.0, 1.0)), (4.0, 3.0, 1.0), moss)
    add("lobe_x", (face_attachment_center(0.0, 7.0, 2.0, 1.0), -1.0, stack_center(0.0, 2.0)), (4.0, 5.0, 2.0), dark)
    add("lobe_y", (-3.0, face_attachment_center(0.0, 5.0, 1.5, 1.0), stack_center(0.0, 1.0)), (5.0, 3.0, 1.0), wet)
    add("fleck_a", (2.0, 1.0, stack_center(4.0, 1.0)), (2.0, 1.0, 1.0), fleck)
    add("fleck_b", (face_attachment_center(0.0, 7.0, 0.5, -1.0), 2.0, stack_center(1.0, 1.0)), (1.0, 2.0, 1.0), fleck)
    add("wet_pocket", (3.0, face_attachment_center(0.0, 5.0, 0.5, -1.0), stack_center(1.0, 1.0)), (3.0, 1.0, 1.0), wet)
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
