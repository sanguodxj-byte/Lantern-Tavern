from __future__ import annotations

"""Independently authored voxel soul_gem brewing-material model.

Identity: faceted cyan soul crystal with dark socket and inner glow spit
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

MODEL_ID = "soul_gem"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "faceted cyan soul crystal with dark socket and inner glow spit"

def build_model():
    core = make_material("sg_core", (0.35, 0.85, 1.0, 1.0), roughness=0.22, emission=1.8)
    facet = make_material("sg_facet", (0.18, 0.55, 0.92, 1.0), roughness=0.28, emission=0.9)
    deep = make_material("sg_deep", (0.08, 0.22, 0.55, 1.0), roughness=0.35, emission=0.35)
    socket = make_material("sg_socket", (0.12, 0.10, 0.18, 1.0), roughness=0.75, metallic=0.15)
    spit = make_material("sg_spit", (0.75, 0.95, 1.0, 1.0), roughness=0.18, emission=3.2)
    edge = make_material("sg_edge", (0.45, 0.70, 1.0, 1.0), roughness=0.25, emission=1.4)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("socket_base", (0.0, 0.0, stack_center(0.0, 2.0)), (6.0, 5.0, 2.0), socket)
    body_c = (0.0, 0.0, stack_center(2.0, 6.0))
    add("gem_body", body_c, (5.0, 4.0, 6.0), core)
    add("facet_x", (face_attachment_center(0.0, 2.5, 1.0, 1.0), 0.0, body_c[2] + 0.5), (2.0, 2.0, 3.0), facet)
    add("facet_nx", (face_attachment_center(0.0, 2.5, 0.5, -1.0), 0.5, body_c[2]), (1.0, 2.0, 3.0), deep)
    add("facet_y", (0.5, face_attachment_center(0.0, 2.0, 1.0, 1.0), body_c[2] + 0.5), (3.0, 2.0, 3.0), edge)
    add("facet_ny", (-0.5, face_attachment_center(0.0, 2.0, 0.5, -1.0), body_c[2] - 0.5), (2.0, 1.0, 3.0), deep)
    add("gem_tip", (0.0, 0.0, stack_center(8.0, 3.0)), (3.0, 3.0, 3.0), facet)
    add("spit_point", (0.5, 0.0, stack_center(11.0, 2.0)), (1.0, 1.0, 2.0), spit)
    add("claw_l", (face_attachment_center(0.0, 3.0, 0.5, -1.0), 1.0, stack_center(0.0, 2.0)), (1.0, 2.0, 2.0), socket)
    add("claw_r", (face_attachment_center(0.0, 3.0, 0.5, 1.0), -1.0, stack_center(0.0, 2.0)), (1.0, 2.0, 2.0), socket)
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
