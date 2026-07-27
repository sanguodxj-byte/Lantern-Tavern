from __future__ import annotations

"""Independently authored voxel luminous_fern brewing-material model.

Identity: glowing fern fronds with pale stems
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

MODEL_ID = "luminous_fern"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "glowing fern fronds with pale stems"

def build_model():
    frond = make_material("lf_frond", (0.35, 0.85, 0.55, 1.0), roughness=0.55, emission=0.8)
    dark = make_material("lf_dark", (0.12, 0.42, 0.28, 1.0), roughness=0.65, emission=0.25)
    stem = make_material("lf_stem", (0.55, 0.72, 0.40, 1.0), roughness=0.70)
    tip = make_material("lf_tip", (0.75, 1.0, 0.70, 1.0), roughness=0.40, emission=1.6)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("base", (0.0, 0.0, stack_center(0.0, 2.0)), (3.0, 2.0, 2.0), stem)
    add("stalk", (0.0, 0.0, stack_center(2.0, 6.0)), (1.0, 1.0, 6.0), stem)
    add("frond_l", (face_attachment_center(0.0, 0.5, 2.5, -1.0), 0.0, stack_center(5.0, 2.0)), (5.0, 1.0, 2.0), frond)
    add("frond_r", (face_attachment_center(0.0, 0.5, 2.5, 1.0), 0.0, stack_center(6.0, 2.0)), (5.0, 1.0, 2.0), dark)
    add("frond_top", (0.0, 0.0, stack_center(8.0, 2.0)), (3.0, 1.0, 2.0), frond)
    add("tip", (0.0, 0.0, stack_center(10.0, 2.0)), (1.0, 1.0, 2.0), tip)
    add("leaflet", (face_attachment_center(0.0, 0.5, 1.5, -1.0), 0.0, stack_center(3.0, 1.0)), (3.0, 1.0, 1.0), dark)
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
