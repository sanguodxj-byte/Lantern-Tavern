"""Generate the full-plate armour as an INDEPENDENT voxel shell.

The armour is modelled as its own model: a hollow cage of steel plates that
wraps a humanoid body volume, with NO body mesh inside. It is meant to be
equipped onto a character (e.g. scheme_a body). Requirements honoured:

* Each armour plate sits OUTSIDE the body surface (clearance + face-contact),
  so when worn the armour does not penetrate the character (no positive-volume
  overlap with the body).
* The armour envelope is larger than the body envelope ("a ring bigger").
* Adjacent armour plates are face-contact only: zero positive-volume overlap
  among the armour pieces themselves.
* Single-model generator (fixed identity `player_plate`), pixel size table
  first, 1m = 32px.

This is an equipment asset, NOT a registered character, so the single-face-
connected-component rule that applies to character models does NOT apply here
(disconnected plates like helm / cuirass / greaves are expected and correct).
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

from voxel_model_primitives import (  # noqa: E402
    reset_scene,
    make_material,
    cube_px,
    make_root,
    mesh_descendants,
    export_glb,
    bounds_center_scale,
    setup_lights_and_camera,
    configure_real_render,
    render_real_views,
)
from voxel_overlap_guard import (  # noqa: E402
    assert_parts_no_positive_volume_overlap,
)

# --- fixed identity ---------------------------------------------------------
MODEL_ID = "player_plate"
ROOT_NAME = "voxel_player_plate"

PROJECT = Path(__file__).resolve().parent.parent
OUT_GLB = PROJECT / "assets/meshes/characters/voxel_player_plate.glb"
PREVIEW_DIR = PROJECT / "reports/characters_preview"

# The virtual body the armour wraps is deliberately a touch LARGER than the
# real character envelope (24 x 19.5 x 59 px) so the armour always ends up
# OUTSIDE the body (clearance, never inside it).
CLEARANCE_PX = 3.0   # gap between body surface and armour inner face
PLATE_PX = 1.0        # armour plate thickness

AXIS = {"x": 0, "y": 1, "z": 2}


def build_materials():
    steel_blue = make_material("steel_blue", (0.46, 0.52, 0.64, 1.0),
                               roughness=0.42, metallic=0.92)
    steel_dark = make_material("steel_dark", (0.24, 0.28, 0.36, 1.0),
                               roughness=0.55, metallic=0.85)
    steel_high = make_material("steel_high", (0.66, 0.72, 0.82, 1.0),
                               roughness=0.32, metallic=0.95)
    brass = make_material("brass", (0.74, 0.57, 0.23, 1.0),
                          roughness=0.38, metallic=0.85)
    brass_dark = make_material("brass_dark", (0.5, 0.37, 0.14, 1.0),
                               roughness=0.5, metallic=0.8)
    red = make_material("red_plume", (0.62, 0.13, 0.13, 1.0),
                        roughness=0.75, metallic=0.0)
    return {
        "blue": steel_blue, "dark": steel_dark, "high": steel_high,
        "brass": brass, "brass_dark": brass_dark, "red": red,
    }


# region = (name, center(x,y,z) px, size(x,y,z) px, [faces], matkey)
REGIONS = [
    ("head",   (0, 0, 55.0),   (14, 14, 10), ["+z", "+x", "-x", "+y", "-y"], "blue"),
    ("torso",  (0, 0, 37.0),   (22, 20, 16), ["+x", "-x", "+y", "-y"],       "blue"),
    ("pelvis", (0, 0, 25.0),   (20, 18, 7),  ["+x", "-x", "+y", "-y"],       "blue"),
    ("sho_l",  (-11.0, 0, 45.0), (6, 9, 5),  ["+z", "-x", "+y", "-y"],       "blue"),
    ("sho_r",  (11.0, 0, 45.0),  (6, 9, 5),  ["+z", "+x", "+y", "-y"],       "blue"),
    ("uarm_l", (-12.0, 0, 37.0), (5, 6, 12), ["-x", "+y", "-y"],             "blue"),
    ("uarm_r", (12.0, 0, 37.0),  (5, 6, 12), ["+x", "+y", "-y"],             "blue"),
    ("farm_l", (-12.0, 0, 14.0), (5, 6, 12), ["-x", "+y", "-y"],             "blue"),
    ("farm_r", (12.0, 0, 14.0),  (5, 6, 12), ["+x", "+y", "-y"],             "blue"),
    ("hand_l", (-12.0, 0, 6.0),  (5, 6, 6),  ["-x", "+y", "-y"],             "dark"),
    ("hand_r", (12.0, 0, 6.0),   (5, 6, 6),  ["+x", "+y", "-y"],             "dark"),
    ("thigh_l", (-5.0, 0, 17.0), (8, 9, 11), ["-x", "+y", "-y"],             "blue"),
    ("thigh_r", (5.0, 0, 17.0),  (8, 9, 11), ["+x", "+y", "-y"],             "blue"),
    ("shin_l", (-5.0, 0, 6.0),   (7, 8, 11), ["-x", "+y", "-y"],             "blue"),
    ("shin_r", (5.0, 0, 6.0),    (7, 8, 11), ["+x", "+y", "-y"],             "blue"),
    ("foot_l", (-4.0, 2.0, 3.0), (7, 12, 3), ["-z", "+y", "-y", "-x"], "dark"),
    ("foot_r", (4.0, 2.0, 3.0),  (7, 12, 3), ["-z", "+y", "-y", "+x"], "dark"),
]

# Per (region, face) shrink of in-plane size (px) to open joint gaps and stop
# a plate from reaching a neighbour it would otherwise penetrate.
SHRINK = {
    # shoulder top plates: pull inboard edge back so they cover the outer
    # pauldron only (x outboard of the body neck/shoulder mass at x[-10,-7]),
    # never the neck itself -> no armour-vs-body penetration.
    ("sho_l", "+z"): {"x": 4, "y": 2}, ("sho_r", "+z"): {"x": 4, "y": 2},
    ("head", "+x"): {"z": 4}, ("head", "-x"): {"z": 4},
    ("head", "+y"): {"z": 4}, ("head", "-y"): {"z": 4},
    ("sho_l", "+y"): {"x": 4}, ("sho_r", "+y"): {"x": 4},
    ("sho_l", "-y"): {"x": 4}, ("sho_r", "-y"): {"x": 4},
    ("sho_l", "-x"): {"z": 4}, ("sho_r", "+x"): {"z": 4},
    ("uarm_l", "+y"): {"x": 4}, ("uarm_r", "+y"): {"x": 4},
    ("uarm_l", "-y"): {"x": 4}, ("uarm_r", "-y"): {"x": 4},
    ("uarm_l", "-x"): {"z": 3}, ("uarm_r", "+x"): {"z": 3},
    ("farm_l", "+y"): {"x": 4}, ("farm_r", "+y"): {"x": 4},
    ("farm_l", "-y"): {"x": 4}, ("farm_r", "-y"): {"x": 4},
    ("farm_l", "-x"): {"z": 3}, ("farm_r", "+x"): {"z": 3},
    ("hand_l", "-x"): {"z": 3}, ("hand_r", "+x"): {"z": 3},
    ("hand_l", "+y"): {"z": 3}, ("hand_r", "+y"): {"z": 3},
    ("hand_l", "-y"): {"z": 3}, ("hand_r", "-y"): {"z": 3},
    ("foot_l", "-x"): {"z": 5}, ("foot_r", "+x"): {"z": 5},
    ("foot_l", "+y"): {"z": 5}, ("foot_r", "+y"): {"z": 5},
    ("foot_l", "-y"): {"z": 5}, ("foot_r", "-y"): {"z": 5},
    ("thigh_l", "-x"): {"z": 3}, ("thigh_r", "+x"): {"z": 3},
    ("thigh_l", "+y"): {"z": 3}, ("thigh_r", "+y"): {"z": 3},
    ("thigh_l", "-y"): {"z": 3}, ("thigh_r", "-y"): {"z": 3},
    ("shin_l", "-x"): {"z": 6}, ("shin_r", "+x"): {"z": 6},
    ("shin_l", "+y"): {"z": 6}, ("shin_r", "+y"): {"z": 6},
    ("shin_l", "-y"): {"z": 6}, ("shin_r", "-y"): {"z": 6},
    ("pelvis", "+x"): {"z": 3}, ("pelvis", "-x"): {"z": 3},
    ("pelvis", "+y"): {"z": 3}, ("pelvis", "-y"): {"z": 3},
}


def add_plate(root, region_name, center, size, face, mat):
    sign = 1.0 if face[0] == "+" else -1.0
    axis = face[1]
    ai = AXIS[axis]
    off = size[ai] / 2.0 + CLEARANCE_PX + PLATE_PX / 2.0
    loc = list(center)
    sz = [0.0, 0.0, 0.0]
    sz[ai] = PLATE_PX
    for other in ("x", "y", "z"):
        oi = AXIS[other]
        if oi == ai:
            continue
        shrink = SHRINK.get((region_name, face), {}).get(other, 0.0)
        sz[oi] = max(1.0, size[oi] - shrink)
    loc[ai] = center[ai] + sign * off
    name = "%s_%s" % (region_name, face.replace("+", "p").replace("-", "m"))
    obj = cube_px(name, tuple(loc), tuple(sz), mat)
    obj.parent = root
    return obj


def main():
    reset_scene()
    mats = build_materials()
    root = make_root(ROOT_NAME)
    root.location.z = 0.0

    for name, center, size, faces, matkey in REGIONS:
        mat = mats[matkey]
        for f in faces:
            add_plate(root, name, center, size, f, mat)

    parts = mesh_descendants(root)
    print("[player_plate] plate count = %d" % len(parts))

    # Self overlap (armour vs armour) must be zero.
    assert_parts_no_positive_volume_overlap(parts, label="player_plate armour")

    exported = export_glb(root, OUT_GLB)
    print("[player_plate] exported %s" % exported)

    center, scale = bounds_center_scale(root)
    camera = setup_lights_and_camera(center, scale)
    configure_real_render()
    render_real_views(PREVIEW_DIR, "voxel_player_plate", center, scale, camera)
    print("[player_plate] renders written to %s" % PREVIEW_DIR)


if __name__ == "__main__":
    main()
