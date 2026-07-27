from __future__ import annotations

"""Independently authored voxel stale_water brewing-material model.

Identity: murky greenish puddle with scum film and bubble nubs
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
    make_material,
    make_root,
    reset_scene,
    stack_center,
)
from voxel_single_model_cli import reject_target_override  # noqa: E402

MODEL_ID = "stale_water"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "murky greenish puddle with scum film and bubble nubs"

def build_model():
    water = make_material("sw_water", (0.28, 0.38, 0.22, 1.0), roughness=0.35)
    deep = make_material("sw_deep", (0.14, 0.22, 0.12, 1.0), roughness=0.42)
    scum = make_material("sw_scum", (0.45, 0.52, 0.28, 1.0), roughness=0.70)
    bubble = make_material("sw_bubble", (0.55, 0.62, 0.40, 1.0), roughness=0.30)

    root = make_root(f"materials_{MODEL_ID}")
    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    add("pool", (0.0, 0.0, stack_center(0.0, 1.0)), (10.0, 7.0, 1.0), water)
    add("deep_center", (0.0, 0.0, stack_center(1.0, 1.0)), (4.0, 3.0, 1.0), deep)
    add("scum_a", (-3.5, 2.5, stack_center(1.0, 1.0)), (2.0, 1.0, 1.0), scum)
    add("scum_b", (3.5, -2.5, stack_center(1.0, 1.0)), (2.0, 1.0, 1.0), scum)
    add("lobe_x", (face_attachment_center(0.0, 5.0, 1.5, 1.0), 0.0, stack_center(0.0, 1.0)), (3.0, 3.0, 1.0), deep)
    add("lobe_y", (-1.0, face_attachment_center(0.0, 3.5, 1.0, -1.0), stack_center(0.0, 1.0)), (4.0, 2.0, 1.0), water)
    add("bubble_a", (0.5, 0.0, stack_center(2.0, 1.0)), (1.0, 1.0, 1.0), bubble)
    add("bubble_b", (-1.0, 0.5, stack_center(2.0, 1.0)), (1.0, 1.0, 1.0), bubble)
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
