from __future__ import annotations

"""Independently authored voxel rusty_nail brewing-material model.

Identity: bent iron nail with rust blooms, flat head and sharp tip
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

MODEL_ID = "rusty_nail"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "bent iron nail with rust blooms, flat head and sharp tip"

# Each material owns its own seed/pattern; no shared identity table.
_IRON_GRAY = (0.42, 0.40, 0.38, 1.0)
_IRON_DARK = (0.22, 0.20, 0.18, 1.0)
_STEEL_LIGHT = (0.55, 0.52, 0.48, 1.0)
_METAL_PALE = (0.50, 0.48, 0.44, 1.0)
_RUST_ORANGE = (0.62, 0.28, 0.10, 1.0)
_RUST_DEEP = (0.38, 0.14, 0.06, 1.0)
_RUST_RED = (0.50, 0.18, 0.08, 1.0)
# Accent swatches: cool blue on warm rust, deep purple shadow, warm amber.
_COOL_STEEL_BLUE = (0.20, 0.30, 0.45, 1.0)
_DEEP_PURPLE_SHADOW = (0.15, 0.08, 0.22, 1.0)
_WARM_AMBER = (0.85, 0.55, 0.18, 1.0)

def build_model():
    iron = make_pixel_material(
        "rn_iron",
        _IRON_GRAY,
        roughness=0.55,
        metallic=0.50,
        palette=(_IRON_GRAY, _IRON_DARK, _STEEL_LIGHT, _RUST_RED, _COOL_STEEL_BLUE, _DEEP_PURPLE_SHADOW),
        pixel_size=48,
        variation=0.40,
        seed=1001,
        pattern="cracks",
        normal_strength=1.1,
        edge_darken=0.42, highlight=0.30, detail_noise=0.15,
    )
    iron_dark = make_pixel_material(
        "rn_iron_dark",
        _IRON_DARK,
        roughness=0.60,
        metallic=0.45,
        palette=(_IRON_DARK, _IRON_GRAY, _METAL_PALE, _RUST_DEEP, _DEEP_PURPLE_SHADOW, _WARM_AMBER),
        pixel_size=48,
        variation=0.40,
        seed=1013,
        pattern="cracks",
        normal_strength=1.2,
        edge_darken=0.44, highlight=0.25, detail_noise=0.18,
    )
    rust = make_pixel_material(
        "rn_rust",
        _RUST_ORANGE,
        roughness=0.85,
        palette=(_RUST_ORANGE, _RUST_DEEP, _RUST_RED, _IRON_DARK, _DEEP_PURPLE_SHADOW, _COOL_STEEL_BLUE),
        pixel_size=48,
        variation=0.40,
        seed=1027,
        pattern="cracks",
        normal_strength=1.3,
        edge_darken=0.45, highlight=0.30, detail_noise=0.20,
    )
    rust_deep = make_pixel_material(
        "rn_rust_deep",
        _RUST_DEEP,
        roughness=0.85,
        palette=(_RUST_DEEP, _RUST_RED, _RUST_ORANGE, _IRON_DARK, _COOL_STEEL_BLUE, _WARM_AMBER),
        pixel_size=48,
        variation=0.41,
        seed=1041,
        pattern="cracks",
        normal_strength=1.2,
        edge_darken=0.45, highlight=0.25, detail_noise=0.20,
    )
    head = make_pixel_material(
        "rn_head",
        _METAL_PALE,
        roughness=0.50,
        metallic=0.50,
        palette=(_METAL_PALE, _STEEL_LIGHT, _IRON_GRAY, _RUST_ORANGE, _COOL_STEEL_BLUE, _DEEP_PURPLE_SHADOW),
        pixel_size=48,
        variation=0.39,
        seed=1057,
        pattern="cracks",
        normal_strength=1.1,
        edge_darken=0.42, highlight=0.30, detail_noise=0.15,
    )

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("nail_head", (0.0, 0.0, stack_center(0.0, 2.0)), (5.0, 5.0, 2.0), head)
    add("head_rim", (0.0, 0.0, stack_center(2.0, 1.0)), (3.0, 3.0, 1.0), iron_dark)
    shaft1_c = (0.0, 0.0, stack_center(3.0, 8.0))
    add("shaft_upper", shaft1_c, (2.0, 2.0, 8.0), iron)
    shaft2_c = (1.0, 0.0, stack_center(11.0, 7.0))
    add("shaft_lower", shaft2_c, (2.0, 2.0, 7.0), iron_dark)
    add("tip", (1.0, 0.0, stack_center(18.0, 3.0)), (1.0, 1.0, 3.0), iron)
    add("rust_a", (face_attachment_center(0.0, 1.0, 0.5, 1.0), 0.0, shaft1_c[2] + 1.0), (1.0, 1.0, 3.0), rust)
    add("rust_b", (shaft2_c[0], face_attachment_center(0.0, 1.0, 0.5, -1.0), shaft2_c[2] - 1.0), (1.0, 1.0, 2.0), rust_deep)
    add("rust_head", (face_attachment_center(0.0, 2.5, 0.5, 1.0), 1.0, stack_center(0.0, 1.0)), (1.0, 2.0, 1.0), rust)
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
