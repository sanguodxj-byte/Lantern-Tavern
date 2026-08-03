from __future__ import annotations

"""Independently authored voxel ritual totem for dungeon ritual/trap rooms.

Pixel envelope: 23px wide x 36px tall x 17px deep.
Identity: stepped black-stone plinth, narrow rune pillar, horned crown, cyan soul rune.
This generator owns exactly one model and one output identity.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

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

MODEL_ID = "ritual_totem"
OUT_GLB = ROOT / "assets" / "models" / "props" / f"props_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"

# Authored palette: soot-black dungeon stone, worn violet ritual pigment,
# and a small cold cyan inlay accent. This prop is not a light source: every surface
# is ordinary nearest-filtered pixel PBR with zero emission.
_STONE_DARK = (0.10, 0.11, 0.14, 1.0)
_STONE_MID = (0.22, 0.24, 0.28, 1.0)
_STONE_EDGE = (0.34, 0.36, 0.40, 1.0)
_RITUAL_PURPLE = (0.38, 0.12, 0.46, 1.0)
_RITUAL_MAGENTA = (0.52, 0.16, 0.44, 1.0)
_SOUL_CYAN = (0.14, 0.46, 0.52, 1.0)
_SOUL_WHITE = (0.42, 0.62, 0.64, 1.0)


def build_ritual_totem():
    stone_dark = make_pixel_material(
        "rt_stone_dark",
        _STONE_DARK,
        roughness=0.94,
        palette=(_STONE_DARK, _STONE_MID, _STONE_EDGE),
        pixel_size=48,
        variation=0.42,
        seed=4103,
        pattern="cracks",
        normal_strength=1.5,
        edge_darken=0.52,
        highlight=0.14,
        detail_noise=0.20,
    )
    stone_mid = make_pixel_material(
        "rt_stone_mid",
        _STONE_MID,
        roughness=0.92,
        palette=(_STONE_DARK, _STONE_MID, _STONE_EDGE),
        pixel_size=48,
        variation=0.38,
        seed=4127,
        pattern="blocks",
        normal_strength=1.35,
        edge_darken=0.44,
        highlight=0.20,
        detail_noise=0.18,
    )
    ritual = make_pixel_material(
        "rt_ritual_pigment",
        _RITUAL_PURPLE,
        roughness=0.84,
        palette=(_RITUAL_PURPLE, _RITUAL_MAGENTA, _STONE_DARK),
        pixel_size=48,
        variation=0.40,
        seed=4153,
        pattern="runes",
        normal_strength=1.1,
        edge_darken=0.30,
        highlight=0.32,
        detail_noise=0.14,
    )
    soul = make_pixel_material(
        "rt_soul_rune",
        _SOUL_CYAN,
        roughness=0.58,
        palette=(_SOUL_CYAN, _SOUL_WHITE, _RITUAL_MAGENTA),
        pixel_size=48,
        variation=0.36,
        seed=4177,
        pattern="crystal",
        normal_strength=0.9,
        edge_darken=0.18,
        highlight=0.72,
        detail_noise=0.10,
    )

    root = make_root("props_ritual_totem")

    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    # 23x17 ground footprint, then two stepped stone masses.
    add("plinth_wide", (0.0, 0.0, stack_center(0.0, 3.0)), (23.0, 17.0, 3.0), stone_dark)
    add("plinth_step", (0.0, 0.0, stack_center(3.0, 3.0)), (17.0, 13.0, 3.0), stone_mid)

    # Main pillar occupies most of the silhouette; it is not a decorative micro-part shell.
    pillar_center = (0.0, 0.0, stack_center(6.0, 20.0))
    add("rune_pillar", pillar_center, (9.0, 9.0, 20.0), stone_dark)

    # Exterior pigment bands sit face-flush on the front face, never interpenetrating the pillar.
    front_y = face_attachment_center(0.0, 4.5, 0.5, 1.0)
    add("lower_rune_band", (0.0, front_y, 12.0), (5.0, 1.0, 5.0), ritual)
    add("upper_rune_band", (0.0, front_y, 20.0), (3.0, 1.0, 5.0), ritual)

    # Crown: shoulder slab, asymmetric chipped side blocks, then a compact horned head.
    shoulder_center = (0.0, 0.0, stack_center(26.0, 4.0))
    add("crown_shoulder", shoulder_center, (15.0, 7.0, 4.0), stone_mid)
    add(
        "shoulder_left_chip",
        (face_attachment_center(0.0, 7.5, 2.0, -1.0), 0.5, shoulder_center[2]),
        (4.0, 5.0, 3.0),
        stone_dark,
    )
    add(
        "shoulder_right_chip",
        (face_attachment_center(0.0, 7.5, 1.5, 1.0), -0.5, shoulder_center[2] + 0.5),
        (3.0, 4.0, 3.0),
        ritual,
    )

    head_center = (0.0, 0.0, stack_center(30.0, 6.0))
    add("crown_head", head_center, (11.0, 9.0, 6.0), stone_dark)
    add(
        "horn_left",
        (face_attachment_center(0.0, 5.5, 1.5, -1.0), 0.0, 34.0),
        (3.0, 5.0, 3.0),
        stone_mid,
    )
    add(
        "horn_right",
        (face_attachment_center(0.0, 5.5, 1.5, 1.0), 0.5, 33.0),
        (3.0, 4.0, 5.0),
        stone_mid,
    )

    mask_y = face_attachment_center(0.0, 4.5, 0.5, 1.0)
    add("ritual_mask", (0.0, mask_y, 33.0), (5.0, 1.0, 5.0), ritual)
    rune_y = face_attachment_center(mask_y, 0.5, 0.5, 1.0)
    add("soul_rune", (0.0, rune_y, 33.0), (3.0, 1.0, 3.0), soul)
    return root


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root = build_ritual_totem()
    finish_model(
        root,
        output_path=OUT_GLB,
        preview_dir=PREVIEW_DIR,
        validation_label=MODEL_ID,
        render_stem=f"voxel_{MODEL_ID}",
        ground_offset_px=1.0,
    )
    print(f"Wrote {OUT_GLB}")
    print("authored_envelope_px=23x36x17")


if __name__ == "__main__":
    main()
