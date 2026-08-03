from __future__ import annotations

"""Independently authored voxel slime_jelly brewing-material model.

Identity: wobbly translucent green jelly blob with drip lobes
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

MODEL_ID = "slime_jelly"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "wobbly translucent green jelly blob with drip lobes"

# Each material owns its own seed/pattern; no shared identity table.
# Slime-jelly palette swatches: greens, teal, pale yellow, translucent white.
PAL_SLIME_GREEN = (0.28, 0.78, 0.32, 1.0)
PAL_DEEP_GREEN = (0.10, 0.42, 0.18, 1.0)
PAL_MID_GREEN = (0.18, 0.58, 0.28, 1.0)
PAL_DARK_GREEN = (0.06, 0.30, 0.12, 1.0)
PAL_BRIGHT_GREEN = (0.30, 0.70, 0.35, 1.0)
PAL_TEAL = (0.20, 0.72, 0.55, 1.0)
PAL_DEEP_TEAL = (0.12, 0.38, 0.30, 1.0)
PAL_GREEN_TEAL = (0.22, 0.55, 0.40, 1.0)
PAL_LIT_GREEN = (0.55, 0.92, 0.48, 1.0)
PAL_LIGHT_GREEN = (0.40, 0.80, 0.45, 1.0)
PAL_PALE_YELLOW_GREEN = (0.75, 1.0, 0.55, 1.0)
PAL_PALE_YELLOW = (0.90, 1.0, 0.70, 1.0)
PAL_WARM_WHITE = (1.0, 1.0, 0.90, 1.0)
PAL_TRANS_WHITE = (0.85, 0.95, 0.80, 1.0)
# Accent swatches: deep purple shadow and warm amber on green slime.
PAL_DEEP_PURPLE_SHADOW = (0.15, 0.08, 0.25, 1.0)
PAL_WARM_AMBER = (0.85, 0.55, 0.20, 1.0)


def build_model():
    jelly = make_pixel_material(
        "sj_jelly", PAL_SLIME_GREEN,
        roughness=0.35, pixel_size=48, variation=0.40, seed=601,
        pattern="crystal", normal_strength=0.9,
        edge_darken=0.25, highlight=0.55, detail_noise=0.15,
        palette=(PAL_DARK_GREEN, PAL_TEAL, PAL_TRANS_WHITE, PAL_DEEP_PURPLE_SHADOW, PAL_WARM_AMBER),
    )
    jelly_deep = make_pixel_material(
        "sj_deep", PAL_DEEP_GREEN,
        roughness=0.40, pixel_size=48, variation=0.41, seed=613,
        pattern="crystal", normal_strength=1.0,
        edge_darken=0.30, highlight=0.45, detail_noise=0.15,
        palette=(PAL_DARK_GREEN, PAL_DEEP_TEAL, PAL_MID_GREEN, PAL_DEEP_PURPLE_SHADOW, PAL_WARM_AMBER),
    )
    jelly_lit = make_pixel_material(
        "sj_lit", PAL_LIT_GREEN,
        roughness=0.28, pixel_size=48, variation=0.40, seed=627,
        pattern="crystal", normal_strength=0.9,
        edge_darken=0.25, highlight=0.60, detail_noise=0.15,
        palette=(PAL_PALE_YELLOW_GREEN, PAL_TRANS_WHITE, PAL_LIGHT_GREEN, PAL_DEEP_PURPLE_SHADOW, PAL_WARM_AMBER),
    )
    core = make_pixel_material(
        "sj_core", PAL_PALE_YELLOW_GREEN,
        roughness=0.22, pixel_size=48, variation=0.40, seed=641,
        pattern="speckle", normal_strength=1.1,
        edge_darken=0.25, highlight=0.65, detail_noise=0.15,
        palette=(PAL_PALE_YELLOW, PAL_WARM_WHITE, PAL_LIGHT_GREEN, PAL_DEEP_PURPLE_SHADOW, PAL_WARM_AMBER),
    )
    drip = make_pixel_material(
        "sj_drip", PAL_MID_GREEN,
        roughness=0.45, pixel_size=48, variation=0.38, seed=653,
        pattern="speckle", normal_strength=0.8,
        edge_darken=0.30, highlight=0.40, detail_noise=0.15,
        palette=(PAL_DEEP_GREEN, PAL_GREEN_TEAL, PAL_BRIGHT_GREEN, PAL_DEEP_PURPLE_SHADOW, PAL_WARM_AMBER),
    )

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("blob_base", (0.0, 0.0, stack_center(0.0, 3.0)), (8.0, 7.0, 3.0), jelly_deep)
    add("blob_mid", (0.5, 0.0, stack_center(3.0, 3.0)), (6.0, 5.0, 3.0), jelly)
    add("blob_top", (-0.5, 0.5, stack_center(6.0, 2.0)), (4.0, 4.0, 2.0), jelly_lit)
    add("shine_plate", (face_attachment_center(0.5, 3.0, 0.5, 1.0), 0.0, stack_center(4.0, 2.0)), (1.0, 2.0, 2.0), core)
    lobe_x_c = (face_attachment_center(0.0, 4.0, 1.5, 1.0), -1.0, stack_center(0.0, 2.0))
    add("lobe_x", lobe_x_c, (3.0, 3.0, 2.0), jelly)
    add("lobe_y", (-2.0, face_attachment_center(0.0, 3.5, 1.0, 1.0), stack_center(0.0, 2.0)), (3.0, 2.0, 2.0), drip)
    add("lobe_ny", (1.5, face_attachment_center(0.0, 3.5, 1.0, -1.0), stack_center(0.0, 2.0)), (2.0, 2.0, 2.0), jelly_deep)
    add("drip_tip", (face_attachment_center(lobe_x_c[0], 1.5, 0.5, 1.0), lobe_x_c[1], stack_center(0.0, 1.0)), (1.0, 1.0, 1.0), drip)
    add("peak_bubble", (0.5, 0.0, stack_center(8.0, 1.0)), (2.0, 2.0, 1.0), core)
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
