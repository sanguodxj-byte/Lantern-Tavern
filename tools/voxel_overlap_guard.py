"""Shared voxel overlap / face-contact checks for Blender generators.

Enforces docs/17:
- face contact required for whole-body connectivity (no floating parts)
- positive volume overlap forbidden (z-fighting)
- decoration plates sit outside host faces

Usage:

    from voxel_overlap_guard import assert_parts_voxel_assembly_valid
    assert_parts_voxel_assembly_valid(parts, label="goblin")
"""
from __future__ import annotations

from mathutils import Vector

# 1px = 1/32m
PX_M = 1.0 / 32.0
# Contact: axis gap/overlap within this is "touching" (face-flush, including float error).
CONTACT_EPS_M = PX_M * 0.15  # 0.15 px
# Positive volume: all three axes must exceed this to count as z-fighting overlap.
VOLUME_EPS_M = PX_M * 0.35  # 0.35 px


def _world_aabb(obj) -> tuple[Vector, Vector]:
    coords = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    mn = Vector((min(c.x for c in coords), min(c.y for c in coords), min(c.z for c in coords)))
    mx = Vector((max(c.x for c in coords), max(c.y for c in coords), max(c.z for c in coords)))
    return mn, mx


def _axis_overlap(a_min: float, a_max: float, b_min: float, b_max: float) -> float:
    return min(a_max, b_max) - max(a_min, b_min)


def boxes_positive_volume_overlap(a_mn: Vector, a_mx: Vector, b_mn: Vector, b_mx: Vector) -> bool:
    return (
        _axis_overlap(a_mn.x, a_mx.x, b_mn.x, b_mx.x) > VOLUME_EPS_M
        and _axis_overlap(a_mn.y, a_mx.y, b_mn.y, b_mx.y) > VOLUME_EPS_M
        and _axis_overlap(a_mn.z, a_mx.z, b_mn.z, b_mx.z) > VOLUME_EPS_M
    )


def boxes_face_contact(a_mn: Vector, a_mx: Vector, b_mn: Vector, b_mx: Vector) -> bool:
    """Face contact: one axis is flush (touch/near-touch), other two solidly overlap.

    Near-touch includes 0 and tiny positive overlaps up to VOLUME_EPS so float
    error and exact exterior_plate placement still count as attached — without
    treating deep interpenetration as attachment.
    """
    ox = _axis_overlap(a_mn.x, a_mx.x, b_mn.x, b_mx.x)
    oy = _axis_overlap(a_mn.y, a_mx.y, b_mn.y, b_mx.y)
    oz = _axis_overlap(a_mn.z, a_mx.z, b_mn.z, b_mx.z)
    vals = (ox, oy, oz)

    # Separated on any axis → not in contact
    if any(v < -CONTACT_EPS_M for v in vals):
        return False

    def is_flush(v: float) -> bool:
        # gap tiny or shallow kiss (not deep volume)
        return -CONTACT_EPS_M <= v <= VOLUME_EPS_M

    def is_solid(v: float) -> bool:
        return v > VOLUME_EPS_M

    flush = sum(1 for v in vals if is_flush(v))
    solid = sum(1 for v in vals if is_solid(v))
    # classic face contact: 1 flush + 2 solid
    if flush == 1 and solid == 2:
        return True
    # edge case: exact zero on one and large on others already covered
    return False


def exterior_plate_center(
    host_center: tuple[float, float, float],
    host_size: tuple[float, float, float],
    plate_size: tuple[float, float, float],
    axis: str,
    side: str,
) -> tuple[float, float, float]:
    """Place a decoration plate flush on the outside of a host box (pixel units)."""
    cx, cy, cz = host_center
    hx, hy, hz = host_size
    px, py, pz = plate_size
    if axis == "x":
        half = hx / 2.0 + px / 2.0
        return (cx - half if side == "neg" else cx + half, cy, cz)
    if axis == "y":
        half = hy / 2.0 + py / 2.0
        return (cx, cy - half if side == "neg" else cy + half, cz)
    half = hz / 2.0 + pz / 2.0
    return (cx, cy, cz - half if side == "neg" else cz + half)


def collect_mesh_objects(parts) -> list:
    if isinstance(parts, dict):
        objs = []
        for group in parts.values():
            objs.extend(group)
        return [o for o in objs if o is not None and getattr(o, "type", None) == "MESH"]
    return [o for o in parts if o is not None and getattr(o, "type", None) == "MESH"]


def find_positive_volume_overlaps(parts) -> list[tuple[str, str, Vector, Vector]]:
    meshes = collect_mesh_objects(parts)
    bounds = []
    for obj in meshes:
        mn, mx = _world_aabb(obj)
        bounds.append((obj.name, mn, mx))
    hits: list[tuple[str, str, Vector, Vector]] = []
    for i in range(len(bounds)):
        na, amn, amx = bounds[i]
        for j in range(i + 1, len(bounds)):
            nb, bmn, bmx = bounds[j]
            if boxes_positive_volume_overlap(amn, amx, bmn, bmx):
                hits.append((na, nb, amn, amx))
    return hits


def assert_parts_no_positive_volume_overlap(parts, *, label: str = "") -> None:
    hits = find_positive_volume_overlaps(parts)
    if not hits:
        return
    prefix = f"[{label}] " if label else ""
    lines = [f"{prefix}positive volume overlap (z-fighting risk):"]
    for na, nb, amn, amx in hits[:40]:
        lines.append(
            f"  {na} vs {nb}  A=({amn.x:.4f},{amn.y:.4f},{amn.z:.4f})->({amx.x:.4f},{amx.y:.4f},{amx.z:.4f})"
        )
    if len(hits) > 40:
        lines.append(f"  ... and {len(hits) - 40} more")
    raise RuntimeError("\n".join(lines))


def assert_parts_single_face_connected_component(parts, *, label: str = "") -> None:
    """Every mesh reachable via face contact (docs/17). Catches floating hair/spikes."""
    meshes = collect_mesh_objects(parts)
    if len(meshes) <= 1:
        return
    bounds = []
    for obj in meshes:
        mn, mx = _world_aabb(obj)
        bounds.append((obj.name, mn, mx))
    n = len(bounds)
    adj: list[list[int]] = [[] for _ in range(n)]
    for i in range(n):
        _, amn, amx = bounds[i]
        for j in range(i + 1, n):
            _, bmn, bmx = bounds[j]
            if boxes_face_contact(amn, amx, bmn, bmx):
                adj[i].append(j)
                adj[j].append(i)
    visited = {0}
    stack = [0]
    while stack:
        cur = stack.pop()
        for nb in adj[cur]:
            if nb not in visited:
                visited.add(nb)
                stack.append(nb)
    if len(visited) != n:
        prefix = f"[{label}] " if label else ""
        missing = [bounds[i][0] for i in range(n) if i not in visited]
        raise RuntimeError(
            f"{prefix}mesh parts are not one face-contact component; "
            f"disconnected (floating/detached): {missing[:20]}"
        )


def assert_parts_voxel_assembly_valid(parts, *, label: str = "") -> None:
    """Full docs/17 assembly check: no positive volume overlap + single face-contact component."""
    assert_parts_no_positive_volume_overlap(parts, label=label)
    assert_parts_single_face_connected_component(parts, label=label)
