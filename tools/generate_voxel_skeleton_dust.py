from __future__ import annotations

"""Independently authored voxel skeleton_dust brewing-material model.

Identity: ashy bone dust pile with pale shards and gray cinders
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

MODEL_ID = "skeleton_dust"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "ashy bone dust pile with pale shards and gray cinders"

# Each material owns its own seed/pattern; no shared identity table.
_ASH_RUST = (0.58, 0.30, 0.24, 1.0)  # warm rust accent
_ASH_COOL = (0.55, 0.58, 0.66, 1.0)  # cool blue-grey accent
_EMBER_RED = (0.50, 0.22, 0.18, 1.0)  # warm ember accent
SD_ASH_PALETTE = (
    (0.82, 0.80, 0.74, 1.0),  # pale ash highlight
    (0.72, 0.70, 0.64, 1.0),  # mid ash (base)
    (0.62, 0.60, 0.55, 1.0),  # shadowed ash
    (0.88, 0.84, 0.72, 1.0),  # bone fleck
    _ASH_RUST,  # warm rust accent
    _ASH_COOL,  # cool blue-grey accent
)
SD_ASH_DARK_PALETTE = (
    (0.52, 0.50, 0.45, 1.0),  # lighter dark ash
    (0.42, 0.40, 0.36, 1.0),  # dark ash (base)
    (0.32, 0.30, 0.27, 1.0),  # deeper ash
    (0.28, 0.26, 0.24, 1.0),  # cinder fleck
    _ASH_COOL,  # cool blue-grey accent
)
SD_BONE_PALETTE = (
    (0.92, 0.88, 0.78, 1.0),  # pale bone highlight
    (0.88, 0.84, 0.72, 1.0),  # yellowed bone (base)
    (0.78, 0.74, 0.62, 1.0),  # aged bone
    (0.68, 0.64, 0.52, 1.0),  # bone shadow
    _ASH_RUST,  # warm marrow red accent
)
SD_CINDER_PALETTE = (
    (0.45, 0.42, 0.38, 1.0),  # ash-flecked cinder
    (0.38, 0.34, 0.30, 1.0),  # warm cinder
    (0.28, 0.26, 0.24, 1.0),  # dark cinder (base)
    (0.18, 0.16, 0.14, 1.0),  # black cinder
    _EMBER_RED,  # warm ember accent
)

def build_model():
    ash = make_pixel_material(
        "sd_ash", (0.72, 0.70, 0.64, 1.0),
        roughness=0.95,
        palette=SD_ASH_PALETTE,
        pixel_size=48,
        variation=0.40,
        seed=801,
        pattern="porous",
        normal_strength=1.0,
        edge_darken=0.32, highlight=0.40, detail_noise=0.15,
    )
    ash_dark = make_pixel_material(
        "sd_dark", (0.42, 0.40, 0.36, 1.0),
        roughness=0.92,
        palette=SD_ASH_DARK_PALETTE,
        pixel_size=48,
        variation=0.42,
        seed=813,
        pattern="porous",
        normal_strength=1.0,
        edge_darken=0.44, highlight=0.35, detail_noise=0.15,
    )
    bone = make_pixel_material(
        "sd_bone", (0.88, 0.84, 0.72, 1.0),
        roughness=0.80,
        palette=SD_BONE_PALETTE,
        pixel_size=48,
        variation=0.38,
        seed=827,
        pattern="cracks",
        normal_strength=1.2,
        edge_darken=0.30, highlight=0.45, detail_noise=0.15,
    )
    cinder = make_pixel_material(
        "sd_cinder", (0.28, 0.26, 0.24, 1.0),
        roughness=0.88,
        palette=SD_CINDER_PALETTE,
        pixel_size=48,
        variation=0.42,
        seed=841,
        pattern="porous",
        normal_strength=0.9,
        edge_darken=0.50, highlight=0.30, detail_noise=0.15,
    )

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("pile_base", (0.0, 0.0, stack_center(0.0, 2.0)), (9.0, 7.0, 2.0), ash)
    add("pile_mid", (0.5, 0.0, stack_center(2.0, 2.0)), (6.0, 5.0, 2.0), ash_dark)
    add("pile_peak", (-0.5, 0.5, stack_center(4.0, 1.0)), (3.0, 3.0, 1.0), ash)
    add("shard_a", (face_attachment_center(0.0, 4.5, 1.5, 1.0), 1.0, stack_center(0.0, 1.0)), (3.0, 1.0, 1.0), bone)
    add("shard_b", (-2.0, face_attachment_center(0.0, 3.5, 0.5, 1.0), stack_center(1.0, 1.0)), (2.0, 1.0, 1.0), bone)
    add("cinder_a", (face_attachment_center(0.5, 3.0, 0.5, 1.0), -1.0, stack_center(3.0, 1.0)), (1.0, 1.0, 1.0), cinder)
    add("cinder_b", (-0.5, 0.5, stack_center(5.0, 1.0)), (1.0, 1.0, 1.0), cinder)
    add("lobe", (face_attachment_center(0.0, 4.5, 1.0, -1.0), -1.5, stack_center(0.0, 1.0)), (2.0, 3.0, 1.0), ash_dark)
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
