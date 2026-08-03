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
    make_pixel_material,
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

# Each material owns its own seed/pattern; no shared identity table.
_DARK_RED = (0.55, 0.05, 0.06, 1.0)
_DEEP_BLACK_RED = (0.28, 0.02, 0.04, 1.0)
_CLOT_RED = (0.42, 0.08, 0.10, 1.0)
_CLOT_BLACK = (0.12, 0.04, 0.05, 1.0)
_SCAB_BROWN = (0.32, 0.12, 0.10, 1.0)
_SHEEN_PINK = (0.72, 0.12, 0.14, 1.0)
_SICKLY_GREEN = (0.18, 0.22, 0.10, 1.0)
_RUST = (0.42, 0.16, 0.08, 1.0)
# Accent swatches: deep purple shadow and warm orange on dark blood.
_DEEP_PURPLE_SHADOW = (0.10, 0.05, 0.18, 1.0)
_WARM_ORANGE = (0.85, 0.45, 0.15, 1.0)

def build_model():
    blood = make_pixel_material(
        "tb_blood",
        _DARK_RED,
        roughness=0.55,
        palette=(_DARK_RED, _DEEP_BLACK_RED, _RUST, _SICKLY_GREEN, _DEEP_PURPLE_SHADOW, _WARM_ORANGE),
        pixel_size=48,
        variation=0.40,
        seed=501,
        pattern="cracks",
        normal_strength=1.1,
        edge_darken=0.38, highlight=0.40, detail_noise=0.15,
    )
    blood_deep = make_pixel_material(
        "tb_deep",
        _DEEP_BLACK_RED,
        roughness=0.62,
        palette=(_DEEP_BLACK_RED, _CLOT_BLACK, _DARK_RED, _SICKLY_GREEN, _DEEP_PURPLE_SHADOW, _WARM_ORANGE),
        pixel_size=48,
        variation=0.41,
        seed=513,
        pattern="cracks",
        normal_strength=1.2,
        edge_darken=0.42, highlight=0.30, detail_noise=0.18,
    )
    clot = make_pixel_material(
        "tb_clot",
        _CLOT_RED,
        roughness=0.78,
        palette=(_CLOT_RED, _CLOT_BLACK, _RUST, _SICKLY_GREEN, _DEEP_PURPLE_SHADOW, _WARM_ORANGE),
        pixel_size=48,
        variation=0.40,
        seed=527,
        pattern="cracks",
        normal_strength=1.0,
        edge_darken=0.42, highlight=0.30, detail_noise=0.18,
    )
    scab = make_pixel_material(
        "tb_scab",
        _SCAB_BROWN,
        roughness=0.90,
        palette=(_SCAB_BROWN, _CLOT_BLACK, _RUST, _DEEP_BLACK_RED, _DEEP_PURPLE_SHADOW, _WARM_ORANGE),
        pixel_size=48,
        variation=0.40,
        seed=541,
        pattern="speckle",
        normal_strength=1.3,
        edge_darken=0.45, highlight=0.25, detail_noise=0.20,
    )
    sheen = make_pixel_material(
        "tb_sheen",
        _SHEEN_PINK,
        roughness=0.35,
        palette=(_SHEEN_PINK, _DARK_RED, _RUST, _SICKLY_GREEN, _DEEP_PURPLE_SHADOW, _WARM_ORANGE),
        pixel_size=48,
        variation=0.39,
        seed=557,
        pattern="cracks",
        normal_strength=0.9,
        edge_darken=0.30, highlight=0.55, detail_noise=0.15,
    )

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
