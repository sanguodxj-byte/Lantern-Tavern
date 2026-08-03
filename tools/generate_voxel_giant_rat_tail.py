from __future__ import annotations

"""Independently authored voxel giant_rat_tail brewing-material model.

Identity: thick armored giant-rat tail with heavy segments
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

MODEL_ID = "giant_rat_tail"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "thick armored giant-rat tail with heavy segments"

# Giant rat tail pixel palette: dark armored browns, segment grays, scaly dark tans.
# Each material owns its own seed/pattern; no shared identity table.
_MID_TAN = (0.48, 0.28, 0.22, 1.0)
_DARK_BROWN = (0.28, 0.14, 0.12, 1.0)
_PALE_TAN = (0.62, 0.40, 0.32, 1.0)
_ARMOR_BROWN = (0.35, 0.22, 0.18, 1.0)
_TIP_BLACK = (0.18, 0.08, 0.06, 1.0)
_SEGMENT_GRAY = (0.42, 0.34, 0.30, 1.0)
_RUST_RED = (0.50, 0.18, 0.14, 1.0)  # warm rust red accent
_SHADOW_BLUE = (0.18, 0.20, 0.28, 1.0)  # cool blue shadow accent


def build_model():
    mid = make_pixel_material(
        "grt_mid", (0.48, 0.28, 0.22, 1.0),
        roughness=0.86, palette=(_MID_TAN, _PALE_TAN, _SEGMENT_GRAY, _RUST_RED),
        pixel_size=48, variation=0.40, seed=3001, pattern="cracks", normal_strength=1.0,
        edge_darken=0.38, highlight=0.30, detail_noise=0.15,
    )
    dark = make_pixel_material(
        "grt_dark", (0.28, 0.14, 0.12, 1.0),
        roughness=0.90, palette=(_DARK_BROWN, _TIP_BLACK, _ARMOR_BROWN, _SHADOW_BLUE),
        pixel_size=48, variation=0.42, seed=3007, pattern="scales", normal_strength=1.1,
        edge_darken=0.46, highlight=0.30, detail_noise=0.15,
    )
    pale = make_pixel_material(
        "grt_pale", (0.62, 0.40, 0.32, 1.0),
        roughness=0.82, palette=(_PALE_TAN, _MID_TAN, _SEGMENT_GRAY, _RUST_RED),
        pixel_size=48, variation=0.38, seed=3013, pattern="cracks", normal_strength=0.9,
        edge_darken=0.35, highlight=0.30, detail_noise=0.15,
    )
    armor = make_pixel_material(
        "grt_armor", (0.35, 0.22, 0.18, 1.0),
        roughness=0.75, palette=(_ARMOR_BROWN, _SEGMENT_GRAY, _DARK_BROWN, _SHADOW_BLUE),
        pixel_size=48, variation=0.40, seed=3019, pattern="cracks", normal_strength=1.0,
        edge_darken=0.44, highlight=0.30, detail_noise=0.15,
    )
    tip = make_pixel_material(
        "grt_tip", (0.18, 0.08, 0.06, 1.0),
        roughness=0.78, palette=(_TIP_BLACK, _DARK_BROWN, _ARMOR_BROWN, _RUST_RED),
        pixel_size=48, variation=0.42, seed=3023, pattern="banded", normal_strength=1.1,
        edge_darken=0.50, highlight=0.30, detail_noise=0.15,
    )

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("stump", (2.5, 0.0, stack_center(0.0, 5.0)), (5.0, 5.0, 5.0), dark)
    add("seg_a", (7.5, 0.0, stack_center(0.0, 4.0)), (5.0, 4.0, 4.0), mid)
    add("plate_a", (7.5, 0.0, stack_center(4.0, 1.0)), (4.0, 3.0, 1.0), armor)
    add("seg_b", (12.5, 0.5, stack_center(0.0, 4.0)), (5.0, 4.0, 4.0), pale)
    add("plate_b", (12.5, 0.5, stack_center(4.0, 1.0)), (3.0, 2.0, 1.0), armor)
    add("seg_c", (17.0, 0.0, stack_center(0.0, 3.0)), (4.0, 3.0, 3.0), mid)
    add("seg_d", (20.5, -0.5, stack_center(0.0, 2.0)), (3.0, 2.0, 2.0), dark)
    add("tip", (23.5, -0.5, stack_center(0.0, 1.0)), (3.0, 1.0, 1.0), tip)
    add("side_ridge", (7.5, face_attachment_center(0.0, 2.0, 0.5, 1.0), stack_center(1.0, 2.0)), (3.0, 1.0, 2.0), armor)
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
