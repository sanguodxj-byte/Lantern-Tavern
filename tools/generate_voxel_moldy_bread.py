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
    make_pixel_material,
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

# Each material owns its own seed/pattern; no shared identity table.
# Accent swatches: deep plum shadow on warm bread, warm amber, cool teal.
_PLUM_SHADOW = (0.18, 0.10, 0.22, 1.0)
_WARM_AMBER = (0.85, 0.55, 0.20, 1.0)
_COOL_TEAL = (0.18, 0.45, 0.42, 1.0)

PALETTE_CRUMB = (
    (0.82, 0.70, 0.48, 1.0),
    (0.74, 0.58, 0.34, 1.0),
    (0.86, 0.76, 0.56, 1.0),
    _PLUM_SHADOW,
    _WARM_AMBER,
)
PALETTE_CRUMB_DARK = (
    (0.64, 0.48, 0.28, 1.0),
    (0.52, 0.36, 0.18, 1.0),
    (0.60, 0.44, 0.26, 1.0),
    _PLUM_SHADOW,
    _COOL_TEAL,
)
PALETTE_CRUST = (
    (0.48, 0.30, 0.14, 1.0),
    (0.36, 0.22, 0.10, 1.0),
    (0.54, 0.34, 0.16, 1.0),
    _WARM_AMBER,
    _PLUM_SHADOW,
)
PALETTE_CRUST_BURN = (
    (0.32, 0.18, 0.08, 1.0),
    (0.22, 0.12, 0.05, 1.0),
    (0.36, 0.20, 0.10, 1.0),
    _PLUM_SHADOW,
    _COOL_TEAL,
)
PALETTE_MOLD_A = (
    (0.40, 0.68, 0.32, 1.0),
    (0.28, 0.54, 0.24, 1.0),
    (0.46, 0.74, 0.36, 1.0),
    _COOL_TEAL,
    _WARM_AMBER,
)
PALETTE_MOLD_B = (
    (0.22, 0.48, 0.34, 1.0),
    (0.14, 0.36, 0.26, 1.0),
    (0.26, 0.54, 0.38, 1.0),
    _PLUM_SHADOW,
    _WARM_AMBER,
)
PALETTE_MOLD_PALE = (
    (0.60, 0.78, 0.52, 1.0),
    (0.50, 0.68, 0.42, 1.0),
    (0.64, 0.80, 0.56, 1.0),
    _COOL_TEAL,
    _WARM_AMBER,
)

def build_model():
    crumb = make_pixel_material(
        "mb_crumb", (0.78, 0.62, 0.38, 1.0), roughness=0.92,
        palette=PALETTE_CRUMB, pixel_size=48, variation=0.40, seed=901,
        pattern="porous", normal_strength=1.0,
        edge_darken=0.35, highlight=0.30, detail_noise=0.15,
    )
    crumb_dark = make_pixel_material(
        "mb_crumb_dark", (0.58, 0.42, 0.24, 1.0), roughness=0.94,
        palette=PALETTE_CRUMB_DARK, pixel_size=48, variation=0.40, seed=913,
        pattern="porous", normal_strength=1.0,
        edge_darken=0.35, highlight=0.30, detail_noise=0.15,
    )
    crust = make_pixel_material(
        "mb_crust", (0.42, 0.26, 0.12, 1.0), roughness=0.88,
        palette=PALETTE_CRUST, pixel_size=48, variation=0.41, seed=927,
        pattern="cracks", normal_strength=1.1,
        edge_darken=0.38, highlight=0.30, detail_noise=0.15,
    )
    crust_burn = make_pixel_material(
        "mb_crust_burn", (0.28, 0.16, 0.08, 1.0), roughness=0.86,
        palette=PALETTE_CRUST_BURN, pixel_size=48, variation=0.40, seed=941,
        pattern="cracks", normal_strength=1.2,
        edge_darken=0.42, highlight=0.25, detail_noise=0.18,
    )
    mold_a = make_pixel_material(
        "mb_mold_a", (0.34, 0.62, 0.28, 1.0), roughness=0.80,
        palette=PALETTE_MOLD_A, pixel_size=48, variation=0.39, seed=953,
        pattern="speckle", normal_strength=1.0,
        edge_darken=0.30, highlight=0.55, detail_noise=0.15,
    )
    mold_b = make_pixel_material(
        "mb_mold_b", (0.18, 0.42, 0.30, 1.0), roughness=0.82,
        palette=PALETTE_MOLD_B, pixel_size=48, variation=0.40, seed=967,
        pattern="speckle", normal_strength=1.1,
        edge_darken=0.30, highlight=0.50, detail_noise=0.15,
    )
    mold_pale = make_pixel_material(
        "mb_mold_pale", (0.55, 0.72, 0.48, 1.0), roughness=0.78,
        palette=PALETTE_MOLD_PALE, pixel_size=48, variation=0.38, seed=983,
        pattern="speckle", normal_strength=1.0,
        edge_darken=0.30, highlight=0.60, detail_noise=0.15,
    )

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
