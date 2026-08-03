from __future__ import annotations

"""Independently authored voxel glowshroom brewing-material model.

Identity: warped cave blue-cap with thick pale stalk and rim glow vents.
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

MODEL_ID = "glowshroom"
OUT_GLB = ROOT / "assets" / "models" / "materials" / f"materials_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "materials_preview"
MANIFEST_PATH = ROOT / "data" / "material_model_manifest.json"
SHAPE_NOTE = "warped emissive blue cave mushroom with vented cap"


# Glowshroom pixel palette: bioluminescent blues, pale stalk, spore white.
# Each material owns its own seed/pattern; no shared identity table.
_DEEP_BLUE = (0.08, 0.28, 0.62, 1.0)
_MID_BLUE = (0.14, 0.48, 0.86, 1.0)
_RIM_CYAN = (0.42, 0.82, 1.0, 1.0)
_SPORE_WHITE = (0.78, 0.94, 1.0, 1.0)
_STALK_PALE = (0.72, 0.82, 0.88, 1.0)
_PURPLE_SHADOW = (0.18, 0.08, 0.38, 1.0)
_VIOLET_ACCENT = (0.42, 0.18, 0.62, 1.0)


def build_glowshroom():
    stalk_pale = make_pixel_material(
        "gs_stalk_pale", (0.72, 0.82, 0.88, 1.0),
        roughness=0.75, palette=(_STALK_PALE, _MID_BLUE, _PURPLE_SHADOW),
        pixel_size=48, variation=0.40, seed=201, pattern="vein",
        normal_strength=1.2, edge_darken=0.40, highlight=0.25, detail_noise=0.15,
    )
    stalk_cool = make_pixel_material(
        "gs_stalk_cool", (0.48, 0.62, 0.74, 1.0),
        roughness=0.80, palette=(_MID_BLUE, _DEEP_BLUE, _VIOLET_ACCENT),
        pixel_size=48, variation=0.42, seed=211, pattern="vein",
        normal_strength=1.3, edge_darken=0.42, highlight=0.20, detail_noise=0.15,
    )
    stalk_shadow = make_pixel_material(
        "gs_stalk_shadow", (0.28, 0.38, 0.48, 1.0),
        roughness=0.85, palette=(_DEEP_BLUE, _MID_BLUE, _PURPLE_SHADOW),
        pixel_size=48, variation=0.42, seed=223, pattern="cracks",
        normal_strength=1.4, edge_darken=0.50, highlight=0.15, detail_noise=0.18,
    )
    cap_deep = make_pixel_material(
        "gs_cap_deep", (0.08, 0.28, 0.62, 1.0),
        roughness=0.50, palette=(_DEEP_BLUE, _RIM_CYAN, _VIOLET_ACCENT),
        pixel_size=48, variation=0.40, seed=233, pattern="scales",
        normal_strength=1.4, edge_darken=0.35, highlight=0.45, detail_noise=0.15,
    )
    cap_mid = make_pixel_material(
        "gs_cap_mid", (0.14, 0.48, 0.86, 1.0),
        roughness=0.42, palette=(_MID_BLUE, _RIM_CYAN, _SPORE_WHITE, _VIOLET_ACCENT),
        pixel_size=48, variation=0.42, seed=239, pattern="scales",
        normal_strength=1.4, edge_darken=0.32, highlight=0.50, detail_noise=0.15,
    )
    cap_rim = make_pixel_material(
        "gs_cap_rim", (0.42, 0.82, 1.0, 1.0),
        roughness=0.28, palette=(_RIM_CYAN, _SPORE_WHITE),
        pixel_size=48, variation=0.42, seed=241, pattern="speckle",
        normal_strength=1.0, edge_darken=0.25, highlight=0.70, detail_noise=0.12,
    )
    gill = make_pixel_material(
        "gs_gill", (0.55, 0.78, 0.95, 1.0),
        roughness=0.38, palette=(_RIM_CYAN, _SPORE_WHITE, _PURPLE_SHADOW),
        pixel_size=48, variation=0.40, seed=251, pattern="porous",
        normal_strength=1.0, edge_darken=0.40, highlight=0.35, detail_noise=0.15,
    )
    spore = make_pixel_material(
        "gs_spore", (0.78, 0.94, 1.0, 1.0),
        roughness=0.22, palette=(_SPORE_WHITE, _RIM_CYAN),
        pixel_size=48, variation=0.42, seed=257, pattern="speckle",
        normal_strength=0.8, edge_darken=0.15, highlight=0.80, detail_noise=0.10,
    )

    root = make_root(f"materials_{MODEL_ID}")

    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    base_h = 3.0
    base_c = (0.0, 0.0, stack_center(0.0, base_h))
    add("stalk_base", base_c, (4.0, 4.0, base_h), stalk_shadow)
    add(
        "foot_x",
        (face_attachment_center(0.0, 2.0, 1.0, 1.0), -0.5, stack_center(0.0, 2.0)),
        (2.0, 3.0, 2.0),
        stalk_cool,
    )
    add(
        "foot_y",
        (-0.5, face_attachment_center(0.0, 2.0, 0.5, -1.0), stack_center(0.0, 2.0)),
        (3.0, 1.0, 2.0),
        stalk_pale,
    )

    mid_h = 5.0
    mid_c = (0.5, 0.0, stack_center(base_h, mid_h))
    add("stalk_mid", mid_c, (3.0, 3.0, mid_h), stalk_pale)
    add(
        "stalk_vein",
        (mid_c[0], face_attachment_center(0.0, 1.5, 0.5, 1.0), mid_c[2] + 0.5),
        (1.0, 1.0, 3.0),
        stalk_cool,
    )

    neck_h = 2.0
    neck_bottom = base_h + mid_h
    neck_c = (0.5, 0.0, stack_center(neck_bottom, neck_h))
    add("stalk_neck", neck_c, (2.0, 2.0, neck_h), stalk_cool)

    cap_bottom = neck_bottom + neck_h
    cap_h = 3.0
    cap_c = (0.0, 0.0, stack_center(cap_bottom, cap_h))
    add("cap_core", cap_c, (7.0, 6.0, cap_h), cap_mid)

    rim_x_c = (
        face_attachment_center(cap_c[0], 3.5, 1.0, 1.0),
        0.5,
        cap_c[2] - 0.5,
    )
    add("rim_pos_x", rim_x_c, (2.0, 4.0, 2.0), cap_rim)
    add(
        "rim_neg_x",
        (face_attachment_center(cap_c[0], 3.5, 1.0, -1.0), -0.5, cap_c[2] - 0.5),
        (2.0, 3.0, 2.0),
        cap_deep,
    )
    add(
        "rim_pos_y",
        (0.5, face_attachment_center(cap_c[1], 3.0, 1.0, 1.0), cap_c[2]),
        (4.0, 2.0, 2.0),
        cap_rim,
    )
    add(
        "rim_neg_y",
        (-1.0, face_attachment_center(cap_c[1], 3.0, 0.5, -1.0), cap_c[2] - 0.5),
        (5.0, 1.0, 2.0),
        cap_deep,
    )

    top_h = 2.0
    top_c = (0.5, 0.0, stack_center(cap_bottom + cap_h, top_h))
    add("cap_dome", top_c, (4.0, 4.0, top_h), cap_deep)
    add(
        "spore_vent",
        (1.0, 0.5, stack_center(cap_bottom + cap_h + top_h, 2.0)),
        (2.0, 2.0, 2.0),
        spore,
    )

    # Gill flaps hang from cap underside. Their TOP face is at cap_bottom,
    # contacting cap_core bottom. XY kept outside the 2x2 neck at (0.5,0).
    gill_h = 1.0
    gill_z = stack_center(cap_bottom - gill_h, gill_h)
    add("gill_l", (-3.0, 0.0, gill_z), (1.0, 4.0, gill_h), gill)
    add("gill_r", (3.0, 0.5, gill_z), (1.0, 3.0, gill_h), gill)
    add("gill_f", (0.5, 2.5, gill_z), (3.0, 1.0, gill_h), gill)

    # Spore bead on exterior of rim_pos_x (+X face).
    add(
        "bead_a",
        (
            face_attachment_center(rim_x_c[0], 1.0, 0.5, 1.0),
            rim_x_c[1] + 1.0,
            rim_x_c[2] + 0.5,
        ),
        (1.0, 1.0, 1.0),
        spore,
    )
    return root


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root = build_glowshroom()
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
