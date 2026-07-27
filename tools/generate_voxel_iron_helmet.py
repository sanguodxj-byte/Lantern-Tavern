from __future__ import annotations

"""Iron helmet — heavy Nordic horned helm (Skyrim / Nord inspired).

TARGET_ENVELOPE_PX = (32, 22, 16)  # W includes outward horns; H includes horn rise
Player head ~10x10x9; steel dome + twin bone horns read clearly larger.

Silhouette vs leather: metal dome, long nasal, eye slots, NO soft brim;
horns are the heavy-set identity anchor (Barony stepped masses).

Axis: +Z up, +Y character front, X width. Scale: 1m = 32px.
"""

import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from voxel_overlap_guard import (  # noqa: E402
    assert_parts_no_positive_volume_overlap,
    assert_parts_voxel_assembly_valid,
    exterior_plate_center,
)
from voxel_single_model_cli import reject_target_override  # noqa: E402
from voxel_weapon_model_lib import (  # noqa: E402
    bounds_size_px,
    box_px,
    export_glb,
    make_material,
    make_root,
    parent_parts,
    render_true_3d_views,
    reset_scene,
)

MODEL_ID = "iron_helmet"
TARGET_ENVELOPE_PX = (32.0, 22.0, 16.0)
OUT_GLB = ROOT / "assets" / "meshes" / "armor" / "armor_voxel_iron_helmet.glb"
PREVIEW_DIR = ROOT / "reports" / "props_preview"


def build_iron_helmet() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    iron_shadow = make_material("ih_shadow", (0.10, 0.12, 0.15, 1.0), metallic=0.88, roughness=0.45)
    iron_base = make_material("ih_base", (0.20, 0.24, 0.28, 1.0), metallic=0.90, roughness=0.38)
    iron_high = make_material("ih_high", (0.42, 0.48, 0.54, 1.0), metallic=0.92, roughness=0.26)
    leather = make_material("ih_pad", (0.09, 0.04, 0.02, 1.0), roughness=0.94)
    bone = make_material("ih_horn_bone", (0.72, 0.62, 0.42, 1.0), roughness=0.72)
    bone_tip = make_material("ih_horn_tip", (0.88, 0.80, 0.62, 1.0), roughness=0.55)
    bone_dark = make_material("ih_horn_dark", (0.45, 0.32, 0.18, 1.0), roughness=0.80)
    rivet = make_material("ih_rivet", (0.55, 0.50, 0.35, 1.0), metallic=0.85, roughness=0.32)

    root = make_root("armor_voxel_iron_helmet")
    parts: list[bpy.types.Object] = []

    def add(name: str, center: tuple[float, float, float], size: tuple[float, float, float], mat) -> tuple[float, float, float]:
        parts.append(box_px(name, center, size, mat))
        return center

    # ---- Steel dome stack ----
    dome_low_c = (0.0, 0.0, 3.5)
    dome_low_s = (15.0, 13.0, 5.0)
    add("pad_rim", (0.0, 0.0, 0.0), (14.0, 12.0, 2.0), leather)
    add("dome_low", dome_low_c, dome_low_s, iron_base)
    dome_mid_c = (0.0, 0.0, 7.5)
    dome_mid_s = (13.0, 11.0, 3.0)
    add("dome_mid", dome_mid_c, dome_mid_s, iron_base)
    add("dome_top", (0.0, 0.0, 10.5), (10.0, 9.0, 3.0), iron_high)
    add("dome_apex", (0.0, 0.0, 12.5), (6.0, 5.0, 1.0), iron_shadow)

    # ---- Brow + nasal (Skyrim face read) ----
    brow_s = (13.0, 2.0, 3.0)
    brow_c = exterior_plate_center(dome_low_c, dome_low_s, brow_s, "y", "pos")
    add("brow_band", brow_c, brow_s, iron_high)
    nasal_s = (2.0, 2.0, 6.0)
    nasal_y = exterior_plate_center(brow_c, brow_s, nasal_s, "y", "pos")[1]
    add("nasal_guard", (0.0, nasal_y, 1.0), nasal_s, iron_shadow)

    slit_s = (2.0, 1.0, 1.0)
    slit_y = exterior_plate_center(brow_c, brow_s, slit_s, "y", "pos")[1]
    add("eye_slit_left", (-3.5, slit_y, 4.0), slit_s, iron_shadow)
    add("eye_slit_right", (3.5, slit_y, 4.0), slit_s, iron_shadow)

    # ---- Cheeks ±X ----
    cheek_s = (2.0, 6.0, 5.0)
    cheek_host_c = (0.0, 1.0, 2.5)
    cheek_host_s = (15.0, 11.0, 5.0)
    add("cheek_left", exterior_plate_center(cheek_host_c, cheek_host_s, cheek_s, "x", "neg"), cheek_s, iron_base)
    add("cheek_right", exterior_plate_center(cheek_host_c, cheek_host_s, cheek_s, "x", "pos"), cheek_s, iron_base)

    # ---- Nape ----
    nape_s = (11.0, 2.0, 4.0)
    nape_c = exterior_plate_center((0.0, 0.0, 2.0), (15.0, 13.0, 4.0), nape_s, "y", "neg")
    add("nape_flare", nape_c, nape_s, iron_shadow)

    # ---- Twin Nordic horns (face-contact chain, mirrored) ----
    # socket on dome_mid ±X → root out → post up → sweep out → tip up
    def add_horn(side: str, x_sign: float) -> None:
        """Skyrim-like Nord horn: out from temple, rise, flare wider, ivory tip."""
        axis_dir = "neg" if x_sign < 0 else "pos"
        socket_s = (2.0, 4.0, 3.0)
        socket_c = exterior_plate_center(dome_mid_c, dome_mid_s, socket_s, "x", axis_dir)
        add(f"horn_socket_{side}", socket_c, socket_s, iron_high)

        root_s = (3.0, 3.0, 3.0)
        root_c = exterior_plate_center(socket_c, socket_s, root_s, "x", axis_dir)
        add(f"horn_root_{side}", root_c, root_s, bone_dark)

        wrap_s = (3.0, 1.0, 2.0)
        wrap_c = exterior_plate_center(root_c, root_s, wrap_s, "y", "pos")
        add(f"horn_ring_{side}", wrap_c, wrap_s, rivet)

        # Rise column
        post_s = (3.0, 3.0, 3.0)
        post_c = (root_c[0], root_c[1], root_c[2] + (root_s[2] + post_s[2]) * 0.5)
        add(f"horn_post_{side}", post_c, post_s, bone)

        # Iron collar then big outward flare (readable horn width)
        collar_s = (1.0, 3.0, 2.0)
        collar_c = exterior_plate_center(post_c, post_s, collar_s, "x", axis_dir)
        add(f"horn_band_{side}", collar_c, collar_s, iron_high)

        flare_s = (4.0, 3.0, 3.0)
        flare_c = exterior_plate_center(collar_c, collar_s, flare_s, "x", axis_dir)
        add(f"horn_flare_{side}", flare_c, flare_s, bone)

        # Second rise on flare top
        rise2_s = (3.0, 2.0, 3.0)
        rise2_c = (flare_c[0], flare_c[1], flare_c[2] + (flare_s[2] + rise2_s[2]) * 0.5)
        add(f"horn_rise_{side}", rise2_c, rise2_s, bone)

        # Final outward nub then ivory tip up — classic Nord tip kick
        nub_s = (2.0, 2.0, 2.0)
        nub_c = exterior_plate_center(rise2_c, rise2_s, nub_s, "x", axis_dir)
        add(f"horn_nub_{side}", nub_c, nub_s, bone_dark)

        tip_s = (2.0, 2.0, 4.0)
        tip_c = (nub_c[0], nub_c[1], nub_c[2] + (nub_s[2] + tip_s[2]) * 0.5)
        add(f"horn_tip_{side}", tip_c, tip_s, bone_tip)

    add_horn("left", -1.0)
    add_horn("right", 1.0)

    # Brow rivets
    rv = (1.0, 1.0, 1.0)
    rv_y = exterior_plate_center(brow_c, brow_s, rv, "y", "pos")[1]
    add("rivet_brow_left", (-5.0, rv_y, 4.0), rv, rivet)
    add("rivet_brow_right", (5.0, rv_y, 4.0), rv, rivet)

    parent_parts(root, parts)
    assert_parts_no_positive_volume_overlap(parts, label=MODEL_ID)
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)
    return root, parts


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, _parts = build_iron_helmet()
    export_glb(root, OUT_GLB)
    render_true_3d_views(root, MODEL_ID, PREVIEW_DIR)
    dims = bounds_size_px(root)
    print(f"Wrote {OUT_GLB}")
    print(f"Iron helmet envelope: {dims[0]:.1f} x {dims[1]:.1f} x {dims[2]:.1f} px")
    print(f"Target envelope W/H/D: {TARGET_ENVELOPE_PX}")


if __name__ == "__main__":
    main()
