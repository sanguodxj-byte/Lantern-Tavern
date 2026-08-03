"""Generate the single expedition-zone pixel map source artifact.

The output is deliberately authored at a low resolution and enlarged with
nearest-neighbour sampling.  It has one fixed identity and one fixed output:
an opaque 768x768 PNG on a pure #00FF00 chroma-key background.  The canonical
project background-removal workflow turns that source into the imported map.
"""

from __future__ import annotations

from pathlib import Path
import random

from PIL import Image, ImageDraw


WORK_SIZE = 384
OUTPUT_SIZE = 768
CHROMA_KEY = (0, 255, 0, 255)
PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = (
    PROJECT_ROOT
    / "reports"
    / "zone_select_background_removal"
    / "input"
    / "expedition_zone_map_source_green.png"
)


def _closed_line(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], fill: tuple[int, ...], width: int) -> None:
    draw.line(points + [points[0]], fill=fill, width=width, joint="curve")


def _polygon_mask(points: list[tuple[int, int]]) -> Image.Image:
    mask = Image.new("1", (WORK_SIZE, WORK_SIZE), 0)
    ImageDraw.Draw(mask).polygon(points, fill=1)
    return mask


def _sprinkle(
    draw: ImageDraw.ImageDraw,
    mask: Image.Image,
    rng: random.Random,
    palette: list[tuple[int, int, int, int]],
    count: int,
    size: int = 2,
) -> None:
    for _ in range(count):
        x = rng.randrange(31, 353)
        y = rng.randrange(31, 353)
        if mask.getpixel((x, y)) == 0:
            continue
        color = rng.choice(palette)
        side = size + rng.randrange(0, 2)
        draw.rectangle((x, y, x + side, y + side), fill=color)


def _draw_tree(draw: ImageDraw.ImageDraw, x: int, y: int, scale: int = 1) -> None:
    trunk = (61, 43, 31, 255)
    dark = (25, 47, 31, 255)
    mid = (42, 76, 45, 255)
    light = (74, 108, 57, 255)
    draw.rectangle((x - scale, y, x + scale, y + 7 * scale), fill=trunk)
    draw.rectangle((x - 5 * scale, y - 3 * scale, x + 5 * scale, y + 2 * scale), fill=dark)
    draw.rectangle((x - 4 * scale, y - 7 * scale, x + 4 * scale, y - 2 * scale), fill=mid)
    draw.rectangle((x - 2 * scale, y - 9 * scale, x + 2 * scale, y - 5 * scale), fill=light)


def _draw_forest(draw: ImageDraw.ImageDraw) -> None:
    for x, y, scale in [
        (72, 98, 1), (91, 79, 1), (110, 99, 2), (132, 76, 1),
        (147, 112, 1), (72, 133, 1), (104, 141, 1), (132, 149, 1),
        (158, 88, 1), (58, 115, 1),
    ]:
        _draw_tree(draw, x, y, scale)
    draw.rectangle((89, 119, 116, 123), fill=(32, 57, 35, 255))
    draw.rectangle((94, 115, 111, 127), outline=(96, 126, 69, 255), width=2)


def _draw_ruins(draw: ImageDraw.ImageDraw) -> None:
    shadow = (43, 36, 50, 255)
    stone = (91, 82, 103, 255)
    edge = (140, 123, 143, 255)
    moss = (69, 86, 60, 255)
    draw.rectangle((183, 72, 188, 111), fill=shadow)
    draw.rectangle((184, 69, 191, 108), fill=stone)
    draw.rectangle((181, 66, 194, 72), fill=edge)
    draw.rectangle((211, 65, 218, 109), fill=stone)
    draw.rectangle((208, 62, 221, 68), fill=edge)
    draw.rectangle((187, 83, 215, 88), fill=edge)
    draw.rectangle((190, 88, 194, 101), fill=stone)
    draw.rectangle((210, 88, 214, 101), fill=stone)
    draw.rectangle((177, 109, 225, 115), fill=shadow)
    draw.rectangle((182, 106, 220, 110), fill=stone)
    draw.rectangle((184, 106, 193, 108), fill=moss)
    draw.rectangle((213, 106, 218, 108), fill=moss)
    draw.rectangle((226, 82, 233, 100), fill=stone)
    draw.rectangle((225, 78, 236, 83), fill=edge)


def _draw_graveyard(draw: ImageDraw.ImageDraw) -> None:
    ground = (44, 49, 48, 255)
    stone = (102, 110, 108, 255)
    highlight = (149, 155, 145, 255)
    iron = (36, 34, 35, 255)
    draw.rectangle((268, 104, 315, 130), fill=ground)
    for x in range(260, 326, 12):
        draw.rectangle((x, 92, x + 2, 151), fill=iron)
        draw.rectangle((x - 2, 91, x + 4, 94), fill=iron)
    draw.line((258, 98, 328, 98), fill=iron, width=2)
    for x, y in [(274, 113), (294, 101), (312, 122), (285, 139)]:
        draw.rectangle((x - 3, y - 8, x + 4, y + 7), fill=stone)
        draw.rectangle((x - 1, y - 11, x + 2, y - 7), fill=highlight)
        draw.rectangle((x - 5, y + 7, x + 6, y + 10), fill=(55, 54, 51, 255))
    draw.rectangle((285, 118, 307, 135), fill=(59, 61, 65, 255))
    draw.rectangle((282, 114, 310, 119), fill=highlight)
    draw.rectangle((290, 124, 302, 135), fill=(23, 22, 26, 255))


def _draw_dungeon(draw: ImageDraw.ImageDraw) -> None:
    shadow = (38, 29, 27, 255)
    stone = (93, 75, 64, 255)
    light = (142, 111, 79, 255)
    gold = (184, 126, 49, 255)
    draw.rectangle((160, 180, 226, 230), fill=shadow)
    draw.rectangle((165, 176, 221, 224), fill=stone)
    for x in (164, 211):
        draw.rectangle((x, 164, x + 13, 224), fill=shadow)
        draw.rectangle((x + 2, 160, x + 15, 220), fill=stone)
        draw.rectangle((x - 1, 156, x + 18, 164), fill=light)
        for notch_x in range(x, x + 19, 8):
            draw.rectangle((notch_x, 151, notch_x + 5, 158), fill=light)
    draw.rectangle((174, 169, 214, 181), fill=light)
    draw.rectangle((183, 192, 205, 224), fill=(25, 22, 23, 255))
    draw.rectangle((187, 198, 201, 224), fill=(49, 39, 35, 255))
    for x in (190, 198):
        draw.rectangle((x, 199, x + 1, 222), fill=gold)
    for y in range(184, 220, 10):
        draw.rectangle((167, y, 218, y + 1), fill=(72, 56, 51, 255))
    draw.rectangle((187, 172, 201, 179), fill=(57, 42, 38, 255))


def _draw_cave(draw: ImageDraw.ImageDraw) -> None:
    dark = (31, 34, 40, 255)
    rock = (66, 73, 82, 255)
    mid = (91, 99, 105, 255)
    light = (129, 130, 124, 255)
    points = [(66, 291), (78, 248), (99, 225), (123, 245), (139, 293), (126, 310), (78, 311)]
    draw.polygon(points, fill=dark)
    draw.polygon([(71, 286), (83, 249), (98, 230), (119, 250), (133, 292)], fill=rock)
    draw.polygon([(79, 259), (98, 232), (105, 259), (93, 274)], fill=mid)
    draw.polygon([(108, 253), (119, 251), (130, 287), (118, 279)], fill=light)
    draw.rectangle((86, 281, 119, 306), fill=(22, 22, 27, 255))
    draw.rectangle((91, 273, 114, 287), fill=(22, 22, 27, 255))
    draw.rectangle((98, 291, 106, 306), fill=(40, 51, 55, 255))
    draw.rectangle((101, 292, 104, 297), fill=(90, 143, 139, 255))
    for x, y in [(63, 234), (132, 226), (58, 273), (144, 268), (119, 323)]:
        draw.polygon([(x, y), (x + 5, y - 8), (x + 10, y + 2)], fill=mid)


def _draw_volcano(draw: ImageDraw.ImageDraw) -> None:
    shadow = (53, 27, 26, 255)
    ash = (91, 49, 42, 255)
    rock = (124, 62, 45, 255)
    lava = (231, 91, 28, 255)
    hot = (255, 176, 49, 255)
    draw.polygon([(245, 310), (267, 251), (286, 225), (303, 250), (329, 311)], fill=shadow)
    draw.polygon([(252, 304), (273, 253), (287, 232), (299, 256), (320, 305)], fill=ash)
    draw.polygon([(271, 253), (287, 236), (303, 255), (295, 266), (278, 266)], fill=(40, 27, 27, 255))
    draw.rectangle((278, 254, 297, 259), fill=lava)
    draw.line((287, 259, 284, 284, 294, 306), fill=lava, width=5)
    draw.line((286, 261, 285, 282), fill=hot, width=2)
    draw.line((312, 282, 323, 290, 330, 302), fill=lava, width=3)
    for x, y in [(254, 246), (315, 242), (331, 271), (242, 279)]:
        draw.rectangle((x, y, x + 4, y + 4), fill=rock)
        draw.point((x + 2, y + 1), fill=hot)


def _draw_route(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]]) -> None:
    draw.line(points, fill=(47, 34, 27, 255), width=8, joint="curve")
    draw.line(points, fill=(145, 111, 69, 255), width=4, joint="curve")
    for index in range(1, len(points) - 1):
        x, y = points[index]
        draw.rectangle((x - 1, y - 1, x + 1, y + 1), fill=(211, 165, 88, 255))


def generate() -> Path:
    rng = random.Random(4706)
    image = Image.new("RGBA", (WORK_SIZE, WORK_SIZE), CHROMA_KEY)
    draw = ImageDraw.Draw(image)

    # Square pixel-map tablet with chamfered corners; the surrounding source
    # remains exact chroma green for the mandatory project cutout workflow.
    board = [(20, 12), (364, 12), (372, 20), (372, 364), (364, 372), (20, 372), (12, 364), (12, 20)]
    draw.polygon(board, fill=(20, 15, 17, 255))
    _closed_line(draw, board, (91, 55, 29, 255), 5)
    inner = [(28, 22), (356, 22), (362, 28), (362, 356), (356, 362), (28, 362), (22, 356), (22, 28)]
    draw.polygon(inner, fill=(22, 32, 38, 255))
    _closed_line(draw, inner, (185, 124, 48, 255), 2)

    # Ocean/abyss texture stays inside the map tablet.
    for _ in range(210):
        x = rng.randrange(29, 355)
        y = rng.randrange(29, 355)
        color = rng.choice([(27, 42, 49, 255), (31, 48, 54, 255), (39, 53, 57, 255)])
        draw.rectangle((x, y, x + rng.randrange(1, 4), y + 1), fill=color)

    island = [
        (48, 72), (71, 50), (116, 39), (157, 48), (190, 35), (235, 44),
        (274, 55), (321, 76), (337, 111), (345, 151), (334, 184),
        (348, 222), (339, 263), (347, 300), (323, 334), (281, 346),
        (238, 337), (202, 352), (158, 341), (116, 349), (76, 329),
        (52, 294), (42, 250), (53, 210), (39, 172), (53, 130), (44, 96),
    ]
    draw.polygon(island, fill=(102, 83, 51, 255))
    _closed_line(draw, island, (42, 31, 25, 255), 5)
    _closed_line(draw, island, (158, 117, 64, 255), 2)

    regions: list[tuple[list[tuple[int, int]], tuple[int, int, int, int], list[tuple[int, int, int, int]]]] = [
        ([(52, 70), (116, 42), (177, 62), (173, 130), (136, 174), (62, 158)], (43, 72, 41, 255), [(54, 88, 49, 255), (67, 96, 57, 255)]),
        ([(157, 54), (229, 44), (258, 77), (244, 143), (177, 151), (159, 112)], (77, 66, 83, 255), [(99, 85, 105, 255), (69, 80, 65, 255)]),
        ([(239, 70), (318, 76), (339, 119), (321, 184), (248, 164), (231, 123)], (69, 76, 75, 255), [(89, 94, 90, 255), (54, 63, 60, 255)]),
        ([(126, 139), (249, 136), (270, 226), (224, 252), (145, 248), (111, 200)], (84, 65, 57, 255), [(108, 79, 61, 255), (70, 59, 55, 255)]),
        ([(50, 166), (116, 173), (154, 235), (141, 326), (76, 337), (42, 281)], (47, 52, 61, 255), [(63, 69, 77, 255), (78, 80, 82, 255)]),
        ([(238, 168), (326, 181), (344, 262), (316, 334), (238, 335), (216, 257)], (91, 45, 38, 255), [(116, 55, 39, 255), (77, 38, 37, 255)]),
    ]
    for polygon, base, texture_palette in regions:
        draw.polygon(polygon, fill=base)
        mask = _polygon_mask(polygon)
        _sprinkle(draw, mask, rng, texture_palette, 68, 1)
        _closed_line(draw, polygon, (52, 40, 34, 255), 2)

    # Roads converge on the initial dungeon and make the six destinations read
    # as one coherent expedition map instead of unrelated icon cards.
    _draw_route(draw, [(190, 197), (158, 172), (132, 145), (105, 119)])
    _draw_route(draw, [(194, 185), (197, 146), (199, 108), (201, 88)])
    _draw_route(draw, [(211, 195), (244, 167), (271, 143), (292, 121)])
    _draw_route(draw, [(179, 220), (150, 236), (128, 256), (104, 279)])
    _draw_route(draw, [(211, 221), (242, 238), (265, 258), (289, 281)])

    _draw_forest(draw)
    _draw_ruins(draw)
    _draw_graveyard(draw)
    _draw_dungeon(draw)
    _draw_cave(draw)
    _draw_volcano(draw)

    # Pixel compass and corner studs reinforce that this is a navigable map.
    compass = (191, 328)
    draw.polygon([(191, 312), (196, 328), (191, 344), (186, 328)], fill=(198, 139, 55, 255))
    draw.polygon([(175, 328), (191, 323), (207, 328), (191, 333)], fill=(111, 80, 50, 255))
    draw.rectangle((188, 325, 194, 331), fill=(36, 29, 27, 255))
    for x, y in [(20, 20), (356, 20), (20, 356), (356, 356)]:
        draw.rectangle((x - 3, y - 3, x + 3, y + 3), fill=(63, 38, 25, 255))
        draw.rectangle((x - 1, y - 1, x + 1, y + 1), fill=(215, 151, 53, 255))

    source = image.resize((OUTPUT_SIZE, OUTPUT_SIZE), Image.Resampling.NEAREST)
    alpha_extrema = source.getchannel("A").getextrema()
    if alpha_extrema != (255, 255):
        raise RuntimeError(f"source must be fully opaque, got alpha extrema {alpha_extrema}")
    for point in [(0, 0), (OUTPUT_SIZE - 1, 0), (0, OUTPUT_SIZE - 1), (OUTPUT_SIZE - 1, OUTPUT_SIZE - 1)]:
        if source.getpixel(point) != CHROMA_KEY:
            raise RuntimeError(f"source background is not pure #00FF00 at {point}")

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    source.save(OUTPUT_PATH, format="PNG", optimize=False)
    return OUTPUT_PATH


if __name__ == "__main__":
    output = generate()
    print(output)
