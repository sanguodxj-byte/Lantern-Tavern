from __future__ import annotations

"""Independently authored voxel cellar_mushroom brewing-material model.

Identity: earthy brown cellar toadstool with thick stem and freckled cap
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

MODEL_ID = "cellar_mushroom"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "earthy brown cellar toadstool with thick stem and freckled cap"

# Cellar mushroom pixel palette: earthy brown toadstool - earth browns, pale
# stem, dark spore.
# Each material owns its own seed/pattern; no shared identity table.
_STEM_PALE = (0.82, 0.74, 0.55, 1.0)
_STEM_DARK = (0.55, 0.45, 0.30, 1.0)
_CAP_BROWN = (0.48, 0.28, 0.16, 1.0)
_CAP_DARK = (0.28, 0.14, 0.08, 1.0)
_FRECKLE_TAN = (0.72, 0.58, 0.38, 1.0)
_GILL_PALE = (0.88, 0.78, 0.55, 1.0)
_SPORE_DARK = (0.18, 0.10, 0.06, 1.0)


def build_model():
    stem = make_pixel_material(
        "cm_stem", (0.82, 0.74, 0.55, 1.0),
        roughness=0.86, palette=(_STEM_PALE, _STEM_DARK, _GILL_PALE),
        pixel_size=48, variation=0.40, seed=1301, pattern="vein", normal_strength=0.9,
        edge_darken=0.38, highlight=0.3, detail_noise=0.15,
    )
    stem_dark = make_pixel_material(
        "cm_stem_dark", (0.55, 0.45, 0.30, 1.0),
        roughness=0.88, palette=(_STEM_DARK, _SPORE_DARK, _STEM_PALE),
        pixel_size=48, variation=0.41, seed=1307, pattern="vein", normal_strength=1.0,
        edge_darken=0.38, highlight=0.3, detail_noise=0.15,
    )
    cap = make_pixel_material(
        "cm_cap", (0.48, 0.28, 0.16, 1.0),
        roughness=0.72, palette=(_CAP_BROWN, _CAP_DARK, _FRECKLE_TAN),
        pixel_size=48, variation=0.41, seed=1313, pattern="cracks", normal_strength=1.1,
        edge_darken=0.38, highlight=0.3, detail_noise=0.15,
    )
    cap_dark = make_pixel_material(
        "cm_cap_dark", (0.28, 0.14, 0.08, 1.0),
        roughness=0.75, palette=(_CAP_DARK, _SPORE_DARK, _CAP_BROWN),
        pixel_size=48, variation=0.42, seed=1319, pattern="cracks", normal_strength=1.2,
        edge_darken=0.38, highlight=0.3, detail_noise=0.15,
    )
    freckle = make_pixel_material(
        "cm_freckle", (0.72, 0.58, 0.38, 1.0),
        roughness=0.70, palette=(_FRECKLE_TAN, _GILL_PALE, _CAP_BROWN),
        pixel_size=48, variation=0.41, seed=1323, pattern="speckle", normal_strength=0.8,
        edge_darken=0.38, highlight=0.3, detail_noise=0.15,
    )
    gill = make_pixel_material(
        "cm_gill", (0.88, 0.78, 0.55, 1.0),
        roughness=0.65, palette=(_GILL_PALE, _STEM_PALE, _SPORE_DARK),
        pixel_size=48, variation=0.40, seed=1327, pattern="vein", normal_strength=0.9,
        edge_darken=0.38, highlight=0.3, detail_noise=0.15,
    )

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("stem_base", (0.0, 0.0, stack_center(0.0, 3.0)), (4.0, 4.0, 3.0), stem_dark)
    add("stem_mid", (0.0, 0.5, stack_center(3.0, 5.0)), (3.0, 3.0, 5.0), stem)
    add("stem_bulge", (face_attachment_center(0.0, 1.5, 0.5, 1.0), 0.5, stack_center(4.0, 2.0)), (1.0, 2.0, 2.0), stem_dark)
    add("cap_core", (0.0, 0.0, stack_center(8.0, 3.0)), (9.0, 8.0, 3.0), cap)
    add("cap_dome", (0.5, 0.0, stack_center(11.0, 2.0)), (5.0, 5.0, 2.0), cap_dark)
    add("cap_rim_x", (face_attachment_center(0.0, 4.5, 1.0, 1.0), 0.0, stack_center(8.0, 2.0)), (2.0, 5.0, 2.0), cap_dark)
    add("cap_rim_y", (-1.0, face_attachment_center(0.0, 4.0, 1.0, -1.0), stack_center(8.0, 2.0)), (5.0, 2.0, 2.0), freckle)
    add("freckle_a", (-1.0, 1.0, stack_center(13.0, 1.0)), (2.0, 1.0, 1.0), freckle)
    add("freckle_b", (1.5, -1.0, stack_center(13.0, 1.0)), (1.0, 2.0, 1.0), freckle)
    add("gill_l", (-3.5, 0.0, stack_center(7.0, 1.0)), (1.0, 4.0, 1.0), gill)
    add("gill_r", (3.5, 0.5, stack_center(7.0, 1.0)), (1.0, 3.0, 1.0), gill)
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
