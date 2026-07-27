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
    make_material,
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

def build_model():
    moss = make_material("dm_moss", (0.28, 0.48, 0.22, 1.0), roughness=0.92)
    moss_dark = make_material("dm_moss_dark", (0.14, 0.28, 0.14, 1.0), roughness=0.94)
    moss_lit = make_material("dm_moss_lit", (0.42, 0.62, 0.28, 1.0), roughness=0.88)
    wet = make_material("dm_wet", (0.18, 0.36, 0.30, 1.0), roughness=0.55)
    spore = make_material("dm_spore", (0.72, 0.78, 0.32, 1.0), roughness=0.70)
    stalk = make_material("dm_stalk", (0.55, 0.48, 0.22, 1.0), roughness=0.80)

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
