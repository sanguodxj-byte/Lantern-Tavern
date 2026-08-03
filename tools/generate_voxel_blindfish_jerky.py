from __future__ import annotations

"""Independently authored voxel blindfish_jerky brewing-material model.

Identity: long dried fish strip with salt crust
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

MODEL_ID = "blindfish_jerky"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "long dried fish strip with salt crust"

# Blindfish jerky pixel palette: desiccated meat reds, dark dried browns,
# bright salt crust whites, ashy grey skin, oil sheen amber.
# Each material owns its own seed/pattern; no shared identity table.
_MEAT_BROWN = (0.58, 0.38, 0.22, 1.0)
_DARK_BROWN = (0.28, 0.16, 0.08, 1.0)
_SALT_WHITE = (0.92, 0.92, 0.86, 1.0)
_SKIN_DUSK = (0.42, 0.48, 0.40, 1.0)
_SALT_CRUST = (0.82, 0.82, 0.76, 1.0)
_MEAT_RED = (0.52, 0.22, 0.14, 1.0)
_OIL_AMBER = (0.72, 0.52, 0.18, 1.0)
_CHAR = (0.12, 0.08, 0.04, 1.0)
_SMOKE_BLUE = (0.20, 0.22, 0.28, 1.0)  # cool blue smoke accent
_WARM_RUST = (0.52, 0.22, 0.14, 1.0)  # warm rust accent


def build_model():
    meat = make_pixel_material(
        "bj_meat", (0.58, 0.38, 0.22, 1.0),
        roughness=0.85, palette=(_MEAT_BROWN, _MEAT_RED, _OIL_AMBER, _DARK_BROWN, _SMOKE_BLUE),
        pixel_size=48, variation=0.42, seed=2801, pattern="cracks", normal_strength=1.3,
        edge_darken=0.38, highlight=0.30, detail_noise=0.15,
    )
    dark = make_pixel_material(
        "bj_dark", (0.28, 0.16, 0.08, 1.0),
        roughness=0.88, palette=(_DARK_BROWN, _CHAR, _MEAT_RED, _SKIN_DUSK, _SMOKE_BLUE),
        pixel_size=48, variation=0.42, seed=2807, pattern="cracks", normal_strength=1.4,
        edge_darken=0.46, highlight=0.30, detail_noise=0.15,
    )
    salt = make_pixel_material(
        "bj_salt", (0.92, 0.92, 0.86, 1.0),
        roughness=0.65, palette=(_SALT_WHITE, _SALT_CRUST, _OIL_AMBER, _MEAT_BROWN, _SMOKE_BLUE),
        pixel_size=48, variation=0.40, seed=2813, pattern="speckle", normal_strength=1.0,
        edge_darken=0.30, highlight=0.45, detail_noise=0.15,
    )
    skin = make_pixel_material(
        "bj_skin", (0.42, 0.48, 0.40, 1.0),
        roughness=0.68, palette=(_SKIN_DUSK, _CHAR, _MEAT_BROWN, _OIL_AMBER, _WARM_RUST),
        pixel_size=48, variation=0.42, seed=2819, pattern="cracks", normal_strength=1.2,
        edge_darken=0.38, highlight=0.30, detail_noise=0.15,
    )

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("strip", (0.0, 0.0, stack_center(0.0, 2.0)), (18.0, 3.0, 2.0), meat)
    add("head_end", (face_attachment_center(0.0, 9.0, 2.0, -1.0), 0.0, stack_center(0.0, 3.0)), (4.0, 4.0, 3.0), dark)
    add("tail_end", (face_attachment_center(0.0, 9.0, 2.0, 1.0), 0.5, stack_center(0.0, 1.0)), (4.0, 2.0, 1.0), skin)
    add("salt_a", (-3.0, 0.0, stack_center(2.0, 1.0)), (4.0, 1.0, 1.0), salt)
    add("salt_b", (4.0, 0.5, stack_center(2.0, 1.0)), (3.0, 1.0, 1.0), salt)
    add("ridge", (1.0, face_attachment_center(0.0, 1.5, 0.5, 1.0), stack_center(1.0, 1.0)), (6.0, 1.0, 1.0), dark)
    add("fin_nub", (-6.0, face_attachment_center(0.0, 1.5, 0.5, -1.0), stack_center(0.0, 2.0)), (2.0, 1.0, 2.0), skin)
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
