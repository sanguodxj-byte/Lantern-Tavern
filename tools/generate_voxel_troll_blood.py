from __future__ import annotations

"""Independently authored voxel troll_blood brewing-material model.

Identity: clotted dark-red blood puddle with raised scabs
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

MODEL_ID = "troll_blood"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "clotted dark-red blood puddle with raised scabs"

def build_model():
    blood = make_material("tb_blood", (0.55, 0.05, 0.06, 1.0), roughness=0.55)
    blood_deep = make_material("tb_deep", (0.28, 0.02, 0.04, 1.0), roughness=0.62)
    clot = make_material("tb_clot", (0.42, 0.08, 0.10, 1.0), roughness=0.78)
    scab = make_material("tb_scab", (0.32, 0.12, 0.10, 1.0), roughness=0.88)
    sheen = make_material("tb_sheen", (0.72, 0.12, 0.14, 1.0), roughness=0.35)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("puddle_core", (0.0, 0.0, stack_center(0.0, 1.0)), (10.0, 7.0, 1.0), blood)
    add("puddle_rise", (0.5, 0.0, stack_center(1.0, 1.0)), (6.0, 4.0, 1.0), blood_deep)
    add("clot_a", (-2.0, 1.0, stack_center(2.0, 1.0)), (3.0, 2.0, 1.0), clot)
    add("clot_b", (2.5, -1.0, stack_center(2.0, 1.0)), (2.0, 2.0, 1.0), scab)
    add("lobe_x", (face_attachment_center(0.0, 5.0, 1.5, 1.0), 0.5, stack_center(0.0, 1.0)), (3.0, 3.0, 1.0), blood_deep)
    add("lobe_y", (-1.5, face_attachment_center(0.0, 3.5, 1.0, 1.0), stack_center(0.0, 1.0)), (4.0, 2.0, 1.0), blood)
    add("lobe_ny", (1.0, face_attachment_center(0.0, 3.5, 1.0, -1.0), stack_center(0.0, 1.0)), (3.0, 2.0, 1.0), clot)
    add("sheen_spot", (1.0, 1.5, stack_center(2.0, 1.0)), (2.0, 1.0, 1.0), sheen)
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
