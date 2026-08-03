from __future__ import annotations

"""Independently authored voxel spikes_trap dungeon hazard model.

Identity: rusted iron floor plate with three jagged blood-stained spikes
Blank-slate redesign. Shared mechanical helpers only.

Run:
  D:/123/blender/blender.exe --background --python tools/generate_voxel_spikes_trap.py
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

MODEL_ID = "spikes_trap"
OUT_GLB = ROOT / "assets" / "meshes" / "traps" / f"traps_{MODEL_ID}.glb"
PREVIEW_DIR = ROOT / "reports" / "traps_preview"
SHAPE_NOTE = "rusted iron floor plate with three jagged blood-stained spikes"

# Spikes trap identity palette: dark rust irons, blood reds, oxidised bronze,
# pale steel tips, dark soot shadows.
# Each material owns its own seed/pattern; no shared identity table.
_RUST_IRON = (0.38, 0.22, 0.14, 1.0)
_DARK_IRON = (0.22, 0.14, 0.10, 1.0)
_BLOOD_RED = (0.55, 0.08, 0.04, 1.0)
_RUST_BROWN = (0.48, 0.28, 0.12, 1.0)
_PALE_STEEL = (0.62, 0.60, 0.58, 1.0)
_SOOT_BLACK = (0.10, 0.08, 0.06, 1.0)
_OXIDISE_GREEN = (0.28, 0.38, 0.22, 1.0)
_BONE_DRY = (0.42, 0.32, 0.20, 1.0)


def build_model():
    # --- Materials ---
    base_iron = make_pixel_material(
        "st_base", (0.38, 0.22, 0.14, 1.0),
        roughness=0.88, metallic=0.35,
        palette=(_RUST_IRON, _DARK_IRON, _RUST_BROWN, _OXIDISE_GREEN),
        pixel_size=48, variation=0.42, seed=3101, pattern="cracks", normal_strength=1.2,
        edge_darken=0.45, highlight=0.20, detail_noise=0.15,
    )
    base_dark = make_pixel_material(
        "st_base_dark", (0.22, 0.14, 0.10, 1.0),
        roughness=0.90, metallic=0.30,
        palette=(_DARK_IRON, _SOOT_BLACK, _RUST_IRON, _BLOOD_RED),
        pixel_size=48, variation=0.42, seed=3113, pattern="cracks", normal_strength=1.3,
        edge_darken=0.48, highlight=0.15, detail_noise=0.15,
    )
    spike_iron = make_pixel_material(
        "st_spike", (0.48, 0.28, 0.12, 1.0),
        roughness=0.72, metallic=0.50,
        palette=(_RUST_BROWN, _PALE_STEEL, _BLOOD_RED, _DARK_IRON),
        pixel_size=48, variation=0.41, seed=3127, pattern="scales", normal_strength=1.1,
        edge_darken=0.40, highlight=0.35, detail_noise=0.15,
    )
    spike_tip = make_pixel_material(
        "st_tip", (0.62, 0.60, 0.58, 1.0),
        roughness=0.45, metallic=0.65,
        palette=(_PALE_STEEL, _RUST_BROWN, _BLOOD_RED, _SOOT_BLACK),
        pixel_size=48, variation=0.40, seed=3143, pattern="crystal", normal_strength=1.0,
        edge_darken=0.35, highlight=0.50, detail_noise=0.15,
    )
    blood = make_pixel_material(
        "st_blood", (0.55, 0.08, 0.04, 1.0),
        roughness=0.60, metallic=0.10,
        palette=(_BLOOD_RED, _SOOT_BLACK, _RUST_IRON, _DARK_IRON),
        pixel_size=48, variation=0.42, seed=3159, pattern="cracks", normal_strength=1.0,
        edge_darken=0.50, highlight=0.20, detail_noise=0.15,
    )
    rim = make_pixel_material(
        "st_rim", (0.42, 0.32, 0.20, 1.0),
        roughness=0.82, metallic=0.40,
        palette=(_BONE_DRY, _RUST_IRON, _DARK_IRON, _OXIDISE_GREEN),
        pixel_size=48, variation=0.41, seed=3173, pattern="banded", normal_strength=1.1,
        edge_darken=0.42, highlight=0.25, detail_noise=0.15,
    )

    root = make_root(f"traps_{MODEL_ID}")

    def add(name, center, size, material):
        obj = cube_px(name, center, size, material)
        obj.parent = root
        return obj

    # --- Base plate (48px wide × 26px deep × 4px tall) ---
    add("base_slab", (0.0, 0.0, stack_center(0.0, 4.0)), (48.0, 26.0, 4.0), base_iron)
    # Darker under-rim for depth (below base_slab, face-attached at Z=0)
    add("base_under", (0.0, 0.0, stack_center(-2.0, 2.0)), (50.0, 28.0, 2.0), base_dark)
    # Front rim lip
    add("rim_front", (0.0, face_attachment_center(0.0, 13.0, 1.0, -1.0), stack_center(0.0, 3.0)), (48.0, 2.0, 3.0), rim)
    # Back rim lip
    add("rim_back", (0.0, face_attachment_center(0.0, 13.0, 1.0, 1.0), stack_center(0.0, 3.0)), (48.0, 2.0, 3.0), rim)
    # Rust stain
    add("rust_stain_a", (-8.0, 3.0, face_attachment_center(stack_center(0.0, 4.0), 2.0, 0.5, 1.0)), (6.0, 4.0, 1.0), base_dark)
    add("rust_stain_b", (9.0, -4.0, face_attachment_center(stack_center(0.0, 4.0), 2.0, 0.5, 1.0)), (4.0, 3.0, 1.0), base_dark)
    # Blood streak on left side of base (exterior plate)
    add("blood_pool", (face_attachment_center(0.0, 24.0, 0.5, -1.0), 0.0, stack_center(0.5, 3.0)), (1.0, 5.0, 3.0), blood)

    # --- Three spikes at X = -15, 0, 15 ---
    spike_positions = [-15.0, 0.0, 15.0]
    for i, sx in enumerate(spike_positions):
        suffix = ["left", "center", "right"][i]

        # Spike base block (6×6×4)
        add(f"spike_{suffix}_base", (sx, 0.0, stack_center(4.0, 4.0)), (6.0, 6.0, 4.0), spike_iron)
        # Mid block (5×5×4)
        add(f"spike_{suffix}_mid", (sx, 0.0, stack_center(8.0, 4.0)), (5.0, 5.0, 4.0), spike_iron)
        # Upper block (4×4×4)
        add(f"spike_{suffix}_upper", (sx, 0.0, stack_center(12.0, 4.0)), (4.0, 4.0, 4.0), spike_iron)
        # Neck (3×3×4)
        add(f"spike_{suffix}_neck", (sx, 0.0, stack_center(16.0, 4.0)), (3.0, 3.0, 4.0), spike_tip)
        # Tip (2×2×3)
        add(f"spike_{suffix}_tip", (sx, 0.0, stack_center(20.0, 3.0)), (2.0, 2.0, 3.0), spike_tip)
        # Needle (1×1×3)
        add(f"spike_{suffix}_needle", (sx, 0.0, stack_center(23.0, 3.0)), (1.0, 1.0, 3.0), spike_tip)

        # Blood drip on spike base (asymmetric detail)
        if i == 1:  # center spike gets extra blood
            add(f"spike_{suffix}_blood", (face_attachment_center(sx, 3.0, 0.5, 1.0), 0.0, stack_center(5.0, 3.0)), (1.0, 2.0, 3.0), blood)
        if i == 0:  # left spike gets rust accent
            add(f"spike_{suffix}_rust", (face_attachment_center(sx, 3.0, 0.5, -1.0), 0.0, stack_center(6.0, 2.0)), (1.0, 2.0, 2.0), base_dark)

    # --- decorative broken rivets on base corners (on top, overlapping base) ---
    add("rivet_fl", (-23.0, -12.0, stack_center(4.0, 1.0)), (2.0, 2.0, 1.0), rim)
    add("rivet_fr", (23.0, -12.0, stack_center(4.0, 1.0)), (2.0, 2.0, 1.0), rim)
    add("rivet_bl", (-23.0, 12.0, stack_center(4.0, 1.0)), (2.0, 2.0, 1.0), rim)
    add("rivet_br", (23.0, 12.0, stack_center(4.0, 1.0)), (2.0, 2.0, 1.0), rim)

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
        ground_offset_px=3.0,
    )
    print(f"Wrote {OUT_GLB}")


if __name__ == "__main__":
    main()
