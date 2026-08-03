from __future__ import annotations

"""Independently authored voxel dragon_scale brewing-material model.

Identity: curved ridged crimson scale plate with horn tip and underbelly
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

MODEL_ID = "dragon_scale"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "curved ridged crimson scale plate with horn tip and underbelly"

# Dragon-scale pixel palette: ember reds, char black, gold horn, ash underbelly.
# Each material owns its own seed/pattern; no shared identity table.
_EMBER = (0.85, 0.32, 0.12, 1.0)
_CHAR = (0.15, 0.05, 0.05, 1.0)
_GOLD = (0.95, 0.78, 0.35, 1.0)
_ASH = (0.40, 0.22, 0.16, 1.0)
_COOL_BLUE = (0.10, 0.18, 0.42, 1.0)

def build_model():
    scale_mid = make_pixel_material(
        "ds_mid", (0.62, 0.18, 0.14, 1.0),
        roughness=0.50, metallic=0.10, palette=(_EMBER, _CHAR, _GOLD, _COOL_BLUE),
        pixel_size=48, variation=0.40, seed=101, pattern="scales",
        normal_strength=1.3, edge_darken=0.35, highlight=0.40, detail_noise=0.15,
    )
    scale_dark = make_pixel_material(
        "ds_dark", (0.32, 0.08, 0.08, 1.0),
        roughness=0.58, metallic=0.12, palette=(_CHAR, _EMBER, _COOL_BLUE),
        pixel_size=48, variation=0.38, seed=113, pattern="scales",
        normal_strength=1.2, edge_darken=0.40, highlight=0.30, detail_noise=0.15,
    )
    scale_hot = make_pixel_material(
        "ds_hot", (0.85, 0.32, 0.12, 1.0),
        roughness=0.42, metallic=0.15, palette=(_EMBER, _GOLD, _CHAR),
        pixel_size=48, variation=0.42, seed=127, pattern="scales",
        normal_strength=1.3, edge_darken=0.30, highlight=0.50, detail_noise=0.15,
    )
    ridge = make_pixel_material(
        "ds_ridge", (0.92, 0.55, 0.18, 1.0),
        roughness=0.35, metallic=0.35, palette=(_GOLD, _EMBER, _COOL_BLUE),
        pixel_size=48, variation=0.38, seed=131, pattern="cracks",
        normal_strength=1.1, edge_darken=0.38, highlight=0.35, detail_noise=0.15,
    )
    belly = make_pixel_material(
        "ds_belly", (0.55, 0.28, 0.18, 1.0),
        roughness=0.68, metallic=0.08, palette=(_ASH, _CHAR, _COOL_BLUE),
        pixel_size=48, variation=0.38, seed=149, pattern="banded",
        normal_strength=1.0, edge_darken=0.35, highlight=0.20, detail_noise=0.15,
    )
    tip = make_pixel_material(
        "ds_tip", (0.95, 0.78, 0.35, 1.0),
        roughness=0.30, metallic=0.40, palette=(_GOLD, _EMBER),
        pixel_size=48, variation=0.40, seed=157, pattern="speckle",
        normal_strength=1.1, edge_darken=0.25, highlight=0.60, detail_noise=0.12,
    )

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("plate_base", (0.0, 0.0, stack_center(0.0, 2.0)), (12.0, 8.0, 2.0), scale_mid)
    add("plate_mid", (0.5, 0.0, stack_center(2.0, 2.0)), (9.0, 6.0, 2.0), scale_dark)
    tip_c = (face_attachment_center(0.0, 6.0, 2.0, 1.0), 0.5, stack_center(0.0, 3.0))
    add("horn_root", tip_c, (4.0, 4.0, 3.0), scale_hot)
    add("horn_tip", (face_attachment_center(tip_c[0], 2.0, 1.5, 1.0), tip_c[1], stack_center(1.0, 2.0)), (3.0, 2.0, 2.0), tip)
    add("keel", (0.0, 0.0, stack_center(4.0, 2.0)), (7.0, 2.0, 2.0), ridge)
    add("keel_spike", (2.0, 0.0, stack_center(6.0, 1.0)), (2.0, 1.0, 1.0), tip)
    add("scallop_y", (-2.0, face_attachment_center(0.0, 4.0, 1.0, 1.0), stack_center(0.0, 2.0)), (4.0, 2.0, 2.0), scale_hot)
    add("scallop_ny", (1.5, face_attachment_center(0.0, 4.0, 0.5, -1.0), stack_center(0.0, 1.0)), (5.0, 1.0, 1.0), belly)
    add("under_lip", (face_attachment_center(0.0, 6.0, 1.0, -1.0), 1.0, stack_center(0.0, 1.0)), (2.0, 4.0, 1.0), belly)
    add("edge_chip", (3.5, face_attachment_center(0.0, 4.0, 0.5, 1.0), stack_center(1.0, 1.0)), (2.0, 1.0, 1.0), scale_dark)
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
