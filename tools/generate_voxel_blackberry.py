from __future__ import annotations

"""Independently authored voxel blackberry brewing-material model.

Identity: clustered dark drupelet berry with stem nub and leaf bit
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

MODEL_ID = "blackberry"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "clustered dark drupelet berry with stem nub and leaf bit"

# Blackberry pixel palette: clustered dark drupelet berry - dark purples, deep
# blue, reddish stems.
# Each material owns its own seed/pattern; no shared identity table.
_BERRY_DARK = (0.18, 0.06, 0.18, 1.0)
_BERRY_LIT = (0.38, 0.12, 0.35, 1.0)
_BERRY_DEEP = (0.08, 0.02, 0.10, 1.0)
_DEEP_BLUE = (0.10, 0.08, 0.28, 1.0)
_HIGHLIGHT = (0.55, 0.28, 0.50, 1.0)
_STEM_GREEN = (0.28, 0.42, 0.16, 1.0)
_STEM_REDDISH = (0.45, 0.20, 0.12, 1.0)
_LEAF_GREEN = (0.22, 0.55, 0.18, 1.0)
# Accent swatches: warm gold and bright magenta on cool purple berry.
_WARM_GOLD = (0.85, 0.65, 0.25, 1.0)
_BRIGHT_MAGENTA = (0.75, 0.20, 0.55, 1.0)


def build_model():
    berry = make_pixel_material(
        "bb_berry", (0.18, 0.06, 0.18, 1.0),
        roughness=0.55, palette=(_BERRY_DARK, _BERRY_LIT, _DEEP_BLUE, _WARM_GOLD, _BRIGHT_MAGENTA),
        pixel_size=48, variation=0.40, seed=1101, pattern="speckle", normal_strength=0.9,
        edge_darken=0.35, highlight=0.30, detail_noise=0.15,
    )
    berry_lit = make_pixel_material(
        "bb_lit", (0.38, 0.12, 0.35, 1.0),
        roughness=0.48, palette=(_BERRY_LIT, _HIGHLIGHT, _BERRY_DARK, _WARM_GOLD, _DEEP_BLUE),
        pixel_size=48, variation=0.41, seed=1107, pattern="speckle", normal_strength=1.0,
        edge_darken=0.30, highlight=0.40, detail_noise=0.15,
    )
    berry_deep = make_pixel_material(
        "bb_deep", (0.08, 0.02, 0.10, 1.0),
        roughness=0.60, palette=(_BERRY_DEEP, _BERRY_DARK, _DEEP_BLUE, _WARM_GOLD, _BRIGHT_MAGENTA),
        pixel_size=48, variation=0.40, seed=1113, pattern="speckle", normal_strength=1.1,
        edge_darken=0.38, highlight=0.25, detail_noise=0.18,
    )
    highlight = make_pixel_material(
        "bb_hi", (0.55, 0.28, 0.50, 1.0),
        roughness=0.40, palette=(_HIGHLIGHT, _BERRY_LIT, _WARM_GOLD, _DEEP_BLUE),
        pixel_size=48, variation=0.39, seed=1119, pattern="speckle", normal_strength=0.8,
        edge_darken=0.25, highlight=0.50, detail_noise=0.15,
    )
    stem = make_pixel_material(
        "bb_stem", (0.28, 0.42, 0.16, 1.0),
        roughness=0.82, palette=(_STEM_GREEN, _STEM_REDDISH, _WARM_GOLD, _DEEP_BLUE),
        pixel_size=48, variation=0.40, seed=1123, pattern="wood", normal_strength=1.0,
        edge_darken=0.35, highlight=0.30, detail_noise=0.15,
    )
    leaf = make_pixel_material(
        "bb_leaf", (0.22, 0.55, 0.18, 1.0),
        roughness=0.78, palette=(_LEAF_GREEN, _STEM_GREEN, _WARM_GOLD, _DEEP_BLUE),
        pixel_size=48, variation=0.41, seed=1129, pattern="banded", normal_strength=1.1,
        edge_darken=0.35, highlight=0.30, detail_noise=0.15,
    )

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("core", (0.0, 0.0, stack_center(0.0, 5.0)), (5.0, 5.0, 5.0), berry)
    add("core_top", (0.0, 0.0, stack_center(5.0, 2.0)), (4.0, 4.0, 2.0), berry_lit)
    add("drupe_x", (face_attachment_center(0.0, 2.5, 1.5, 1.0), 0.0, stack_center(1.0, 4.0)), (3.0, 3.0, 4.0), berry_deep)
    add("drupe_nx", (face_attachment_center(0.0, 2.5, 1.0, -1.0), 0.5, stack_center(1.0, 3.0)), (2.0, 3.0, 3.0), berry_lit)
    add("drupe_y", (0.5, face_attachment_center(0.0, 2.5, 1.5, 1.0), stack_center(0.5, 4.0)), (3.0, 3.0, 4.0), berry)
    add("drupe_ny", (-0.5, face_attachment_center(0.0, 2.5, 1.0, -1.0), stack_center(1.5, 3.0)), (3.0, 2.0, 3.0), berry_deep)
    add("hi_spot", (1.0, 1.0, stack_center(7.0, 1.0)), (2.0, 1.0, 1.0), highlight)
    add("stem_nub", (0.0, 0.0, stack_center(7.0, 2.0)), (1.0, 1.0, 2.0), stem)
    add("leaf_bit", (face_attachment_center(0.0, 0.5, 1.5, 1.0), 0.0, stack_center(8.0, 1.0)), (3.0, 1.0, 1.0), leaf)
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
