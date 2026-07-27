"""Mechanical finish helpers for single-material voxel generators.

No material identities, silhouettes, color tables, or multi-output loops live here.
Each caller supplies its own model_id, parts, and output paths.
"""

from __future__ import annotations

import json
from pathlib import Path

from mathutils import Vector


def mesh_world_bbox_m(root) -> tuple[float, float, float]:
    coords = []
    for obj in root.children_recursive:
        if getattr(obj, "type", None) != "MESH":
            continue
        coords.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not coords:
        return (0.0, 0.0, 0.0)
    mins = Vector(tuple(min(c[i] for c in coords) for i in range(3)))
    maxs = Vector(tuple(max(c[i] for c in coords) for i in range(3)))
    size = maxs - mins
    return (float(size.x), float(size.y), float(size.z))


def update_material_manifest_entry(
    *,
    manifest_path: Path,
    model_id: str,
    bbox_m: tuple[float, float, float],
    shape_note: str,
    generator_name: str,
) -> None:
    data = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    updated = False
    for entry in data.get("materials", []):
        if entry.get("id") == model_id:
            entry["bbox"] = [round(bbox_m[0], 4), round(bbox_m[1], 4), round(bbox_m[2], 4)]
            entry["shape_note"] = shape_note
            entry["generated_by"] = generator_name
            updated = True
            break
    if not updated:
        raise SystemExit(f"manifest missing material id {model_id}")
    Path(manifest_path).write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def publish_material_preview_aliases(*, preview_dir: Path, model_id: str) -> None:
    preview_dir = Path(preview_dir)
    stem = f"voxel_{model_id}"
    for view in ("front", "side", "top", "preview"):
        src = preview_dir / f"{stem}_render_{view}.png"
        if src.exists():
            (preview_dir / f"{stem}_{view}.png").write_bytes(src.read_bytes())
