from __future__ import annotations

"""Independently authored voxel mistflower brewing-material model.

Identity: four-petal pale mist flower with glowing center
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

MODEL_ID = "mistflower"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "four-petal pale mist flower with glowing center"

def build_model():
    petal = make_material("mf_petal", (0.78, 0.85, 0.92, 1.0), roughness=0.55)
    petal_dark = make_material("mf_dark", (0.55, 0.62, 0.75, 1.0), roughness=0.60)
    center = make_material("mf_center", (0.55, 0.85, 1.0, 1.0), roughness=0.35, emission=1.5)
    stem = make_material("mf_stem", (0.35, 0.55, 0.32, 1.0), roughness=0.82)
    glow = make_material("mf_glow", (0.85, 0.95, 1.0, 1.0), roughness=0.25, emission=2.2)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("stem", (0.0, 0.0, stack_center(0.0, 3.0)), (2.0, 2.0, 3.0), stem)
    add("disk", (0.0, 0.0, stack_center(3.0, 2.0)), (4.0, 4.0, 2.0), center)
    add("petal_x", (face_attachment_center(0.0, 2.0, 2.0, 1.0), 0.0, stack_center(3.0, 2.0)), (4.0, 3.0, 2.0), petal)
    add("petal_nx", (face_attachment_center(0.0, 2.0, 2.0, -1.0), 0.5, stack_center(3.0, 2.0)), (4.0, 3.0, 2.0), petal_dark)
    add("petal_y", (0.0, face_attachment_center(0.0, 2.0, 2.0, 1.0), stack_center(3.0, 2.0)), (3.0, 4.0, 2.0), petal)
    add("petal_ny", (0.5, face_attachment_center(0.0, 2.0, 1.5, -1.0), stack_center(3.0, 2.0)), (3.0, 3.0, 2.0), petal_dark)
    add("glow_core", (0.0, 0.0, stack_center(5.0, 1.0)), (2.0, 2.0, 1.0), glow)
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
