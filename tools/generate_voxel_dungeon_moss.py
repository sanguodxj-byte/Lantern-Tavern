from __future__ import annotations

"""Independently authored voxel dungeon_moss brewing-material model.

Identity: clumped damp moss mound with spore stalks and wet shade pockets
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

MODEL_ID = "dungeon_moss"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "clumped damp moss mound with spore stalks and wet shade pockets"

# Dungeon moss pixel palette: mossy greens, dark green, damp wet, brown
# stalk, pale spore yellow-green, accent violet and magenta.
# Each material owns its own seed/pattern; no shared identity table.
_MOSS_LIT = (0.42, 0.62, 0.28, 1.0)
_MOSS_GREEN = (0.28, 0.48, 0.22, 1.0)
_DARK_GREEN = (0.14, 0.28, 0.14, 1.0)
_DAMP_WET = (0.18, 0.36, 0.30, 1.0)
_STALK_BROWN = (0.55, 0.48, 0.22, 1.0)
_SPORE_PALE = (0.72, 0.78, 0.32, 1.0)
_ACCENT_VIOLET = (0.18, 0.08, 0.38, 1.0)
_ACCENT_MAGENTA = (0.32, 0.14, 0.52, 1.0)

def build_model():
    moss = make_pixel_material(
        "dm_moss", (0.28, 0.48, 0.22, 1.0),
        roughness=0.92, palette=(_MOSS_GREEN, _MOSS_LIT, _DARK_GREEN, _ACCENT_VIOLET),
        pixel_size=48, variation=0.41, seed=1701, pattern="porous", normal_strength=1.0,
        edge_darken=0.4, highlight=0.25, detail_noise=0.15,
    )
    moss_dark = make_pixel_material(
        "dm_moss_dark", (0.14, 0.28, 0.14, 1.0),
        roughness=0.94, palette=(_DARK_GREEN, _MOSS_GREEN, _ACCENT_MAGENTA, _DAMP_WET),
        pixel_size=48, variation=0.41, seed=1713, pattern="porous", normal_strength=1.1,
        edge_darken=0.4, highlight=0.25, detail_noise=0.15,
    )
    moss_lit = make_pixel_material(
        "dm_moss_lit", (0.42, 0.62, 0.28, 1.0),
        roughness=0.88, palette=(_MOSS_LIT, _SPORE_PALE, _MOSS_GREEN, _ACCENT_VIOLET),
        pixel_size=48, variation=0.40, seed=1725, pattern="porous", normal_strength=0.9,
        edge_darken=0.4, highlight=0.25, detail_noise=0.15,
    )
    wet = make_pixel_material(
        "dm_wet", (0.18, 0.36, 0.30, 1.0),
        roughness=0.55, palette=(_DAMP_WET, _ACCENT_MAGENTA, _DARK_GREEN, _MOSS_GREEN),
        pixel_size=48, variation=0.41, seed=1737, pattern="porous", normal_strength=1.0,
        edge_darken=0.4, highlight=0.25, detail_noise=0.15,
    )
    spore = make_pixel_material(
        "dm_spore", (0.72, 0.78, 0.32, 1.0),
        roughness=0.70, palette=(_SPORE_PALE, _MOSS_LIT, _ACCENT_VIOLET, _STALK_BROWN),
        pixel_size=48, variation=0.41, seed=1749, pattern="speckle", normal_strength=1.2,
        edge_darken=0.4, highlight=0.25, detail_noise=0.15,
    )
    stalk = make_pixel_material(
        "dm_stalk", (0.55, 0.48, 0.22, 1.0),
        roughness=0.80, palette=(_STALK_BROWN, _SPORE_PALE, _DARK_GREEN, _ACCENT_MAGENTA),
        pixel_size=48, variation=0.42, seed=1761, pattern="speckle", normal_strength=0.8,
        edge_darken=0.4, highlight=0.25, detail_noise=0.15,
    )

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("moss_pad", (0.0, 0.0, stack_center(0.0, 3.0)), (11.0, 9.0, 3.0), moss)
    add("moss_rise", (1.0, 0.5, stack_center(3.0, 3.0)), (7.0, 6.0, 3.0), moss_lit)
    add("moss_peak", (-0.5, 0.0, stack_center(6.0, 2.0)), (4.0, 4.0, 2.0), moss_dark)
    add("lobe_x", (face_attachment_center(0.0, 5.5, 1.5, 1.0), -1.0, stack_center(0.0, 2.0)), (3.0, 4.0, 2.0), moss_dark)
    add("lobe_y", (-2.0, face_attachment_center(0.0, 4.5, 1.0, 1.0), stack_center(0.0, 2.0)), (4.0, 2.0, 2.0), wet)
    add("lobe_ny", (2.0, face_attachment_center(0.0, 4.5, 1.0, -1.0), stack_center(0.0, 2.0)), (3.0, 2.0, 2.0), moss)
    add("stalk_a", (-1.0, 0.5, stack_center(8.0, 3.0)), (1.0, 1.0, 3.0), stalk)
    add("stalk_b", (1.0, -0.5, stack_center(8.0, 4.0)), (1.0, 1.0, 4.0), stalk)
    add("spore_a", (-1.0, 0.5, stack_center(11.0, 1.0)), (2.0, 2.0, 1.0), spore)
    add("spore_b", (1.0, -0.5, stack_center(12.0, 1.0)), (2.0, 1.0, 1.0), spore)
    add("wet_pocket", (face_attachment_center(0.0, 5.5, 0.5, -1.0), 1.5, stack_center(1.0, 2.0)), (1.0, 3.0, 2.0), wet)
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
