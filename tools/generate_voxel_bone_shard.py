from __future__ import annotations

"""Independently authored voxel bone_shard brewing-material model.

Identity: jagged pale bone splinter with marrow notch and cracks
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

MODEL_ID = "bone_shard"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "jagged pale bone splinter with marrow notch and cracks"

def build_model():
    bone = make_material("bs_bone", (0.90, 0.86, 0.72, 1.0), roughness=0.78)
    bone_dark = make_material("bs_dark", (0.62, 0.55, 0.42, 1.0), roughness=0.82)
    marrow = make_material("bs_marrow", (0.72, 0.48, 0.38, 1.0), roughness=0.70)
    crack = make_material("bs_crack", (0.45, 0.38, 0.30, 1.0), roughness=0.85)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("shaft", (0.0, 0.0, stack_center(0.0, 2.0)), (14.0, 3.0, 2.0), bone)
    thick_c = (face_attachment_center(0.0, 7.0, 2.0, -1.0), 0.0, stack_center(0.0, 3.0))
    add("thick_end", thick_c, (4.0, 4.0, 3.0), bone_dark)
    point_c = (face_attachment_center(0.0, 7.0, 2.0, 1.0), 0.5, stack_center(0.0, 1.0))
    add("point_a", point_c, (4.0, 2.0, 1.0), bone)
    add("point_spike", (face_attachment_center(point_c[0], 2.0, 1.0, 1.0), point_c[1], stack_center(0.0, 1.0)), (2.0, 1.0, 1.0), crack)
    add("marrow_notch", (thick_c[0], face_attachment_center(0.0, 2.0, 0.5, 1.0), stack_center(1.0, 2.0)), (2.0, 1.0, 2.0), marrow)
    add("crack_line", ( -2.0, face_attachment_center(0.0, 1.5, 0.5, 1.0), stack_center(1.0, 1.0)), (4.0, 1.0, 1.0), crack)
    add("top_ridge", (1.0, 0.0, stack_center(2.0, 1.0)), (6.0, 1.0, 1.0), bone_dark)
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
