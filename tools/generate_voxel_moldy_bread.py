from __future__ import annotations

"""Independently authored voxel moldy_bread brewing-material model.

Identity: chunky torn loaf with green mold blooms and crust breaks
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

MODEL_ID = "moldy_bread"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "chunky torn loaf with green mold blooms and crust breaks"

def build_model():
    crumb = make_material("mb_crumb", (0.78, 0.62, 0.38, 1.0), roughness=0.92)
    crumb_dark = make_material("mb_crumb_dark", (0.58, 0.42, 0.24, 1.0), roughness=0.94)
    crust = make_material("mb_crust", (0.42, 0.26, 0.12, 1.0), roughness=0.88)
    crust_burn = make_material("mb_crust_burn", (0.28, 0.16, 0.08, 1.0), roughness=0.86)
    mold_a = make_material("mb_mold_a", (0.34, 0.62, 0.28, 1.0), roughness=0.80)
    mold_b = make_material("mb_mold_b", (0.18, 0.42, 0.30, 1.0), roughness=0.82)
    mold_pale = make_material("mb_mold_pale", (0.55, 0.72, 0.48, 1.0), roughness=0.78)

    root = make_root(f"materials_{MODEL_ID}")

    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    body_h = 5.0
    add("loaf_core", (0.0, 0.0, stack_center(0.0, body_h)), (12.0, 7.0, body_h), crumb)
    crown_h = 2.0
    add("crust_crown", (0.5, 0.0, stack_center(body_h, crown_h)), (10.0, 5.0, crown_h), crust)
    heel_c = (face_attachment_center(0.0, 6.0, 2.0, 1.0), 0.5, stack_center(0.0, 4.0))
    add("torn_heel", heel_c, (4.0, 5.0, 4.0), crumb_dark)
    add("heel_crust", (heel_c[0] + 0.5, heel_c[1], stack_center(4.0, 2.0)), (3.0, 3.0, 2.0), crust_burn)
    add("side_crust", (-1.0, face_attachment_center(0.0, 3.5, 0.5, -1.0), stack_center(1.0, 4.0)), (8.0, 1.0, 4.0), crust)
    add("bite_lip", (2.0, face_attachment_center(0.0, 3.5, 1.0, 1.0), stack_center(1.0, 3.0)), (4.0, 2.0, 3.0), crumb_dark)
    top_z = body_h + crown_h
    add("mold_bloom_a", (-2.5, 1.0, stack_center(top_z, 1.0)), (3.0, 2.0, 1.0), mold_a)
    add("mold_bloom_b", (1.5, -1.0, stack_center(top_z, 1.0)), (2.0, 2.0, 1.0), mold_b)
    add("mold_spot_side", (face_attachment_center(0.0, 6.0, 0.5, -1.0), 1.5, stack_center(2.0, 2.0)), (1.0, 2.0, 2.0), mold_pale)
    add("mold_on_heel", (heel_c[0], face_attachment_center(heel_c[1], 2.5, 0.5, 1.0), stack_center(2.0, 1.0)), (2.0, 1.0, 1.0), mold_a)
    add("crumb_chip", (-3.0, face_attachment_center(0.0, 3.5, 0.5, 1.0), stack_center(4.0, 2.0)), (2.0, 1.0, 2.0), crumb)
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
