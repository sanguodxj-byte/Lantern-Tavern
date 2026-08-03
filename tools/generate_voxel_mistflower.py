from __future__ import annotations

"""Independently authored voxel mistflower brewing-material model.

Identity: four-petal pale mist flower with glowing center
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

MODEL_ID = "mistflower"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "four-petal pale mist flower with glowing center"

# Mistflower pixel palette: luminous pale blues, misty whites, vivid glowing
# cyan center, deep teal shadows, pale green stem.
# Each material owns its own seed/pattern; no shared identity table.
_MIST_WHITE = (0.82, 0.90, 0.96, 1.0)
_PETAL_BLUE = (0.48, 0.58, 0.78, 1.0)
_PETAL_DEEP = (0.28, 0.38, 0.58, 1.0)
_CENTER_GLOW = (0.45, 0.90, 1.0, 1.0)
_STEM_GREEN = (0.30, 0.52, 0.28, 1.0)
_GLOW_WHITE = (0.90, 0.98, 1.0, 1.0)
_CYAN_HOT = (0.30, 0.95, 0.95, 1.0)
_VIOLET_SHADE = (0.35, 0.25, 0.55, 1.0)


def build_model():
    petal = make_pixel_material(
        "mf_petal", (0.82, 0.90, 0.96, 1.0),
        roughness=0.30, palette=(_MIST_WHITE, _GLOW_WHITE, _PETAL_BLUE, _CYAN_HOT),
        pixel_size=48, variation=0.38, seed=2401, pattern="crystal", normal_strength=1.1,
        edge_darken=0.3, highlight=0.5, detail_noise=0.15,
    )
    petal_dark = make_pixel_material(
        "mf_dark", (0.48, 0.58, 0.78, 1.0),
        roughness=0.38, palette=(_PETAL_BLUE, _PETAL_DEEP, _VIOLET_SHADE, _MIST_WHITE),
        pixel_size=48, variation=0.40, seed=2413, pattern="crystal", normal_strength=1.2,
        edge_darken=0.3, highlight=0.5, detail_noise=0.15,
    )
    center = make_pixel_material(
        "mf_center", (0.45, 0.90, 1.0, 1.0),
        roughness=0.18, palette=(_CENTER_GLOW, _CYAN_HOT, _GLOW_WHITE, _MIST_WHITE),
        pixel_size=48, variation=0.42, seed=2425, pattern="speckle", normal_strength=1.0,
        edge_darken=0.3, highlight=0.5, detail_noise=0.15,
    )
    stem = make_pixel_material(
        "mf_stem", (0.30, 0.52, 0.28, 1.0),
        roughness=0.72, palette=(_STEM_GREEN, _PETAL_DEEP, _CENTER_GLOW, _VIOLET_SHADE),
        pixel_size=48, variation=0.40, seed=2437, pattern="cracks", normal_strength=1.3,
        edge_darken=0.3, highlight=0.5, detail_noise=0.15,
    )
    glow = make_pixel_material(
        "mf_glow", (0.90, 0.98, 1.0, 1.0),
        roughness=0.12, palette=(_GLOW_WHITE, _CYAN_HOT, _CENTER_GLOW),
        pixel_size=48, variation=0.38, seed=2449, pattern="speckle", normal_strength=0.9,
        edge_darken=0.3, highlight=0.5, detail_noise=0.15,
    )

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("stem", (0.0, 0.0, stack_center(0.0, 3.0)), (2.0, 2.0, 3.0), stem)
    add("disk", (0.0, 0.0, stack_center(3.0, 2.0)), (4.0, 4.0, 2.0), center)
    add("petal_x", (face_attachment_center(0.0, 2.0, 2.0, 1.0), 0.0, stack_center(3.0, 2.0)), (4.0, 3.0, 2.0), petal)
    add("petal_nx", (face_attachment_center(0.0, 2.0, 2.0, -1.0), 0.5, stack_center(3.0, 2.0)), (4.0, 3.0, 2.0), petal_dark)
    add("petal_y", (0.0, face_attachment_center(0.0, 2.0, 2.0, 1.0), stack_center(3.0, 2.0)), (3.0, 4.0, 2.0), petal)
    add("petal_ny", (0.5, face_attachment_center(0.0, 2.0, 1.5, -1.0), stack_center(3.0, 2.0)), (3.0, 3.0, 2.0), petal_dark)
    add("glow_core", (0.0, 0.0, stack_center(5.0, 1.0)), (2.0, 2.0, 1.0), glow)
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
