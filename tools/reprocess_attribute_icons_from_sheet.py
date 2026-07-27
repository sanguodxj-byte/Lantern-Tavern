"""Extract normalized attribute icons from the approved 4x4 green-screen cutout."""

from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


ICON_NAMES = [
    "level",
    "health",
    "attack",
    "armor",
    "evasion",
    "critical",
    "strength",
    "agility",
    "vitality",
    "intelligence",
    "dexterity",
    "perception",
    "mana",
]
CELL_SIZE = 320
OUTPUT_SIZE = 64
TARGET_MAX_DIMENSION = 48
MIN_COMPONENT_AREA = 128
def _normalise_cell(cell: np.ndarray) -> Image.Image:
    if cell.shape[2] != 4:
        raise ValueError("attribute sheet must be an RGBA cutout")
    foreground = cell[:, :, 3] > 0
    labels, component_count = ndimage.label(foreground, structure=np.ones((3, 3), dtype=np.uint8))
    if component_count == 0:
        raise ValueError("attribute cell contains no icon pixels")
    sizes = ndimage.sum(foreground, labels, range(1, component_count + 1))
    keep = np.concatenate(([False], sizes >= MIN_COMPONENT_AREA))
    clean_mask = keep[labels]
    ys, xs = np.where(clean_mask)
    if len(xs) == 0:
        raise ValueError("attribute cell contains only detached noise")

    left, right = int(xs.min()), int(xs.max()) + 1
    top, bottom = int(ys.min()), int(ys.max()) + 1
    cropped_rgba = cell[top:bottom, left:right].copy()
    cropped_mask = clean_mask[top:bottom, left:right]
    cropped_rgba[:, :, 3] = np.where(cropped_mask, cropped_rgba[:, :, 3], 0)
    height, width = cropped_mask.shape
    scale = TARGET_MAX_DIMENSION / float(max(width, height))
    scaled_width = max(1, round(width * scale))
    scaled_height = max(1, round(height * scale))
    # Keep the opaque bounds centered on the 64px canvas's integer midpoint.
    # An odd non-dominant dimension would otherwise produce a mathematically
    # centered half-pixel span that the asset contract cannot represent.
    if scaled_width % 2 == 1:
        scaled_width -= 1
    if scaled_height % 2 == 1:
        scaled_height -= 1
    scaled_size = (max(2, scaled_width), max(2, scaled_height))
    scaled = Image.fromarray(cropped_rgba, mode="RGBA").resize(scaled_size, Image.Resampling.NEAREST)

    canvas = Image.new("RGBA", (OUTPUT_SIZE, OUTPUT_SIZE), (0, 0, 0, 0))
    position = ((OUTPUT_SIZE - scaled.width) // 2, (OUTPUT_SIZE - scaled.height) // 2)
    canvas.alpha_composite(scaled, position)
    return canvas


def reprocess(source_path: Path, output_dir: Path) -> None:
    source = np.asarray(Image.open(source_path).convert("RGBA"))
    if source.shape[:2] != (CELL_SIZE * 4, CELL_SIZE * 4):
        raise ValueError(f"expected a 1280x1280 4x4 sheet, got {source.shape[1]}x{source.shape[0]}")
    output_dir.mkdir(parents=True, exist_ok=True)
    for index, name in enumerate(ICON_NAMES):
        row, column = divmod(index, 4)
        cell = source[row * CELL_SIZE:(row + 1) * CELL_SIZE, column * CELL_SIZE:(column + 1) * CELL_SIZE]
        _normalise_cell(cell).save(output_dir / f"attribute_{name}_aligned.png")


if __name__ == "__main__":
    project_root = Path(__file__).resolve().parents[1]
    reprocess(
        project_root / "reports/ui_audit/attribute_green_workflow/output_green_cc/attribute_icons_4x4_pure_green_v2_green_cc_cutout.png",
        project_root / "assets/textures/icons/attributes",
    )
