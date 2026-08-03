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
    make_pixel_material,
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

# Pixel-art palette: deep cobalt fractures, pale ice highlights, white-hot core
# specks. Each material picks its own seed/pattern; no shared identity table.
_DEEP_BLUE = (0.10, 0.30, 0.62, 1.0)
_ICE = (0.62, 0.86, 1.0, 1.0)
_WHITE_HOT = (0.92, 0.98, 1.0, 1.0)

def build_model():
    core = make_pixel_material(
        "sg_core", (0.25, 0.62, 0.90, 1.0),
        roughness=0.22, palette=(_DEEP_BLUE, _ICE, _WHITE_HOT),
        pixel_size=48, variation=0.40, seed=11, pattern="cracks",
        normal_strength=1.3, edge_darken=0.25, highlight=0.50, detail_noise=0.15,
    )
    facet = make_pixel_material(
        "sg_facet", (0.16, 0.48, 0.85, 1.0),
        roughness=0.25, palette=(_DEEP_BLUE, _ICE),
        pixel_size=48, variation=0.38, seed=23, pattern="crystal",
        normal_strength=1.2, edge_darken=0.22, highlight=0.45, detail_noise=0.15,
    )
    deep = make_pixel_material(
        "sg_deep", (0.06, 0.18, 0.48, 1.0),
        roughness=0.32, palette=(_DEEP_BLUE, _ICE),
        pixel_size=48, variation=0.40, seed=37, pattern="cracks",
        normal_strength=1.2, edge_darken=0.30, highlight=0.30, detail_noise=0.18,
    )
    socket = make_pixel_material(
        "sg_socket", (0.10, 0.08, 0.15, 1.0),
        roughness=0.65, metallic=0.30, palette=((0.04, 0.04, 0.06, 1.0), (0.18, 0.16, 0.22, 1.0), (0.35, 0.30, 0.40, 1.0)),
        pixel_size=48, variation=0.36, seed=51, pattern="cracks",
        normal_strength=1.5, edge_darken=0.45, highlight=0.20, detail_noise=0.18,
    )
    spit = make_pixel_material(
        "sg_spit", (0.75, 0.95, 1.0, 1.0),
        roughness=0.15, palette=(_WHITE_HOT, _ICE),
        pixel_size=48, variation=0.38, seed=67, pattern="speckle",
        normal_strength=0.9, edge_darken=0.15, highlight=0.80, detail_noise=0.10,
    )
    edge = make_pixel_material(
        "sg_edge", (0.38, 0.62, 0.95, 1.0),
        roughness=0.22, palette=(_ICE, _WHITE_HOT),
        pixel_size=48, variation=0.38, seed=83, pattern="crystal",
        normal_strength=1.2, edge_darken=0.20, highlight=0.55, detail_noise=0.15,
    )

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
