from __future__ import annotations

"""Strip emissive material fields from project-authored GLB assets.

This is a mechanical migration tool for legacy non-light assets. It edits only
the JSON chunk of binary glTF files and preserves BIN chunks byte-for-byte.
Actual light-source visuals are authored as Godot scenes/shaders and are not
passed to this tool.
"""

import json
import struct
import sys
from pathlib import Path

JSON_CHUNK = 0x4E4F534A


def strip_glb(path: Path) -> bool:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        raise ValueError(f"not a binary glTF: {path}")
    magic, version, _length = struct.unpack_from("<4sII", data, 0)
    chunks: list[tuple[int, bytes]] = []
    offset = 12
    changed = False
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset : offset + chunk_length]
        offset += chunk_length
        if chunk_type == JSON_CHUNK:
            doc = json.loads(chunk.decode("utf-8").rstrip(" \t\r\n\x00"))
            for material in doc.get("materials", []):
                if "emissiveFactor" in material:
                    material.pop("emissiveFactor", None)
                    changed = True
                extensions = material.get("extensions")
                if isinstance(extensions, dict) and "KHR_materials_emissive_strength" in extensions:
                    extensions.pop("KHR_materials_emissive_strength", None)
                    changed = True
                    if not extensions:
                        material.pop("extensions", None)
            used = doc.get("extensionsUsed")
            if isinstance(used, list) and "KHR_materials_emissive_strength" in used:
                doc["extensionsUsed"] = [name for name in used if name != "KHR_materials_emissive_strength"]
                if not doc["extensionsUsed"]:
                    doc.pop("extensionsUsed", None)
                changed = True
            required = doc.get("extensionsRequired")
            if isinstance(required, list) and "KHR_materials_emissive_strength" in required:
                doc["extensionsRequired"] = [name for name in required if name != "KHR_materials_emissive_strength"]
                if not doc["extensionsRequired"]:
                    doc.pop("extensionsRequired", None)
                changed = True
            encoded = json.dumps(doc, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            encoded += b" " * ((4 - len(encoded) % 4) % 4)
            chunk = encoded
        chunks.append((chunk_type, chunk))
    if not changed:
        return False
    total_length = 12 + sum(8 + len(chunk) for _chunk_type, chunk in chunks)
    output = bytearray(struct.pack("<4sII", magic, version, total_length))
    for chunk_type, chunk in chunks:
        output += struct.pack("<II", len(chunk), chunk_type)
        output += chunk
    path.write_bytes(output)
    return True


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: strip_non_light_glb_emission.py <glb> [<glb> ...]")
    for raw_path in sys.argv[1:]:
        path = Path(raw_path).resolve()
        print(f"{'stripped' if strip_glb(path) else 'clean'} {path}")


if __name__ == "__main__":
    main()
