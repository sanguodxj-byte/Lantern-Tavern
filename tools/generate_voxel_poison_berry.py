from __future__ import annotations

"""Independently authored voxel poison_berry brewing-material model.

Identity: dark toxic berry cluster with green venom freckles
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

MODEL_ID = "poison_berry"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "dark toxic berry cluster with green venom freckles"

# Poison berry pixel palette: dark toxic berry - dark purple, toxic green,
# sickly yellow.
# Each material owns its own seed/pattern; no shared identity table.
_BERRY_DARK = (0.22, 0.05, 0.28, 1.0)
_BERRY_LIT = (0.40, 0.12, 0.45, 1.0)
_BERRY_DEEP = (0.10, 0.02, 0.14, 1.0)
_VENOM_GREEN = (0.35, 0.75, 0.18, 1.0)
_SICKLY_YELLOW = (0.55, 0.62, 0.12, 1.0)
_STEM_GREEN = (0.25, 0.38, 0.12, 1.0)
# Accent swatches: deep indigo and warm amber on toxic purple berry.
_DEEP_INDIGO = (0.08, 0.05, 0.30, 1.0)
_WARM_AMBER = (0.85, 0.55, 0.20, 1.0)


def build_model():
    berry = make_pixel_material(
        "pb_berry", (0.22, 0.05, 0.28, 1.0),
        roughness=0.50, palette=(_BERRY_DARK, _VENOM_GREEN, _SICKLY_YELLOW, _DEEP_INDIGO, _WARM_AMBER),
        pixel_size=48, variation=0.40, seed=1201, pattern="speckle", normal_strength=0.9,
        edge_darken=0.30, highlight=0.55, detail_noise=0.15,
    )
    berry_lit = make_pixel_material(
        "pb_lit", (0.40, 0.12, 0.45, 1.0),
        roughness=0.45, palette=(_BERRY_LIT, _BERRY_DARK, _VENOM_GREEN, _DEEP_INDIGO, _WARM_AMBER),
        pixel_size=48, variation=0.41, seed=1207, pattern="speckle", normal_strength=1.0,
        edge_darken=0.30, highlight=0.60, detail_noise=0.15,
    )
    venom = make_pixel_material(
        "pb_venom", (0.35, 0.75, 0.18, 1.0),
        roughness=0.40, palette=(_VENOM_GREEN, _SICKLY_YELLOW, _DEEP_INDIGO, _WARM_AMBER),
        pixel_size=48, variation=0.40, seed=1219, pattern="speckle", normal_strength=1.1,
        edge_darken=0.30, highlight=0.70, detail_noise=0.15,
    )
    stem = make_pixel_material(
        "pb_stem", (0.25, 0.38, 0.12, 1.0),
        roughness=0.82, palette=(_STEM_GREEN, _SICKLY_YELLOW, _DEEP_INDIGO, _WARM_AMBER),
        pixel_size=48, variation=0.40, seed=1223, pattern="wood", normal_strength=1.0,
        edge_darken=0.35, highlight=0.30, detail_noise=0.15,
    )
    deep = make_pixel_material(
        "pb_deep", (0.10, 0.02, 0.14, 1.0),
        roughness=0.55, palette=(_BERRY_DEEP, _BERRY_DARK, _VENOM_GREEN, _DEEP_INDIGO, _WARM_AMBER),
        pixel_size=48, variation=0.40, seed=1213, pattern="speckle", normal_strength=1.2,
        edge_darken=0.35, highlight=0.45, detail_noise=0.18,
    )

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("core", (0.0, 0.0, stack_center(0.0, 5.0)), (5.0, 5.0, 5.0), berry)
    add("top", (0.0, 0.0, stack_center(5.0, 2.0)), (4.0, 4.0, 2.0), berry_lit)
    add("drupe_x", (face_attachment_center(0.0, 2.5, 1.5, 1.0), 0.0, stack_center(1.0, 4.0)), (3.0, 3.0, 4.0), deep)
    add("drupe_y", (0.0, face_attachment_center(0.0, 2.5, 1.0, 1.0), stack_center(1.0, 3.0)), (3.0, 2.0, 3.0), berry_lit)
    add("venom_a", (-1.0, 1.0, stack_center(7.0, 1.0)), (2.0, 1.0, 1.0), venom)
    add("venom_b", (face_attachment_center(0.0, 2.5, 0.5, -1.0), 0.5, stack_center(3.0, 1.0)), (1.0, 1.0, 1.0), venom)
    add("stem", (0.5, 0.0, stack_center(7.0, 2.0)), (1.0, 1.0, 2.0), stem)
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
