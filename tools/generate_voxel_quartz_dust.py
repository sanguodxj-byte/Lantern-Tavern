from __future__ import annotations

"""Independently authored voxel quartz_dust brewing-material model.

Identity: sparkling quartz crystal dust with shard tips
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

MODEL_ID = "quartz_dust"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "sparkling quartz crystal dust with shard tips"

# Quartz crystal dust identity palette: whites, pale blues, pale pinks, silver.
# Each material owns its own seed/pattern; no shared identity table.
_CRYSTAL_WHITE = (0.95, 0.97, 1.0, 1.0)
_PALE_BLUE = (0.72, 0.88, 1.0, 1.0)
_PALE_PINK = (1.0, 0.92, 0.94, 1.0)
_SILVER = (0.82, 0.84, 0.88, 1.0)
# Accent swatches: deep indigo shadow and warm rose on cool crystal.
_DEEP_INDIGO_SHADOW = (0.10, 0.12, 0.35, 1.0)
_WARM_ROSE = (0.85, 0.45, 0.55, 1.0)

def build_model():
    dust = make_pixel_material(
        "qd_dust",
        (0.85, 0.88, 0.92, 1.0),
        roughness=0.55,
        palette=(_CRYSTAL_WHITE, _PALE_BLUE, _SILVER, _DEEP_INDIGO_SHADOW, _WARM_ROSE),
        pixel_size=48,
        variation=0.40,
        seed=401,
        pattern="crystal",
        normal_strength=0.9,
        edge_darken=0.30, highlight=0.45, detail_noise=0.15,
    )
    dark = make_pixel_material(
        "qd_dark",
        (0.55, 0.58, 0.65, 1.0),
        roughness=0.60,
        palette=(_PALE_BLUE, _SILVER, _CRYSTAL_WHITE, _DEEP_INDIGO_SHADOW, _WARM_ROSE),
        pixel_size=48,
        variation=0.41,
        seed=413,
        pattern="crystal",
        normal_strength=1.0,
        edge_darken=0.35, highlight=0.35, detail_noise=0.15,
    )
    crystal = make_pixel_material(
        "qd_crystal",
        (0.75, 0.90, 1.0, 1.0),
        roughness=0.25,
        palette=(_CRYSTAL_WHITE, _PALE_BLUE, _PALE_PINK, _DEEP_INDIGO_SHADOW, _WARM_ROSE),
        pixel_size=48,
        variation=0.40,
        seed=427,
        pattern="crystal",
        normal_strength=1.1,
        edge_darken=0.30, highlight=0.60, detail_noise=0.15,
    )
    tip = make_pixel_material(
        "qd_tip",
        (0.95, 0.98, 1.0, 1.0),
        roughness=0.18,
        palette=(_CRYSTAL_WHITE, _PALE_BLUE, _PALE_PINK, _SILVER, _DEEP_INDIGO_SHADOW, _WARM_ROSE),
        pixel_size=48,
        variation=0.41,
        seed=441,
        pattern="speckle",
        normal_strength=1.2,
        edge_darken=0.25, highlight=0.65, detail_noise=0.15,
    )

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("pile", (0.0, 0.0, stack_center(0.0, 2.0)), (8.0, 6.0, 2.0), dust)
    add("rise", (0.5, 0.0, stack_center(2.0, 2.0)), (5.0, 4.0, 2.0), dark)
    add("shard_a", (-1.0, 0.5, stack_center(4.0, 3.0)), (2.0, 1.0, 3.0), crystal)
    add("shard_b", (1.5, -0.5, stack_center(4.0, 2.0)), (1.0, 1.0, 2.0), tip)
    add("lobe", (face_attachment_center(0.0, 4.0, 1.5, 1.0), 1.0, stack_center(0.0, 1.0)), (3.0, 3.0, 1.0), dark)
    add("side_crystal", (face_attachment_center(0.0, 4.0, 0.5, -1.0), -1.0, stack_center(1.0, 2.0)), (1.0, 1.0, 2.0), crystal)
    add("glint", (0.5, -1.0, stack_center(4.0, 1.0)), (1.0, 1.0, 1.0), tip)
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
