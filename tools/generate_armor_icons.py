#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "textures" / "icons" / "equipment"
OUT.mkdir(parents=True, exist_ok=True)

ARMOR = {
    "cloth_armor": ((140, 120, 160), (200, 180, 210), "cloth"),
    "leather_armor": ((110, 70, 40), (160, 110, 70), "leather"),
    "chain_armor": ((140, 145, 155), (190, 195, 205), "chain"),
    "plate_armor": ((170, 172, 180), (220, 222, 230), "plate"),
}


def main() -> None:
    for eid, (c1, c2, kind) in ARMOR.items():
        img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle(
            [28, 24, 100, 110],
            radius=14,
            fill=c1 + (255,),
            outline=(255, 255, 255, 70),
            width=2,
        )
        d.ellipse([18, 30, 48, 58], fill=c2 + (255,))
        d.ellipse([80, 30, 110, 58], fill=c2 + (255,))
        if kind == "chain":
            for y in range(40, 100, 8):
                for x in range(36, 96, 8):
                    d.ellipse([x, y, x + 5, y + 5], outline=(90, 95, 100, 180))
        elif kind == "plate":
            d.rectangle([40, 50, 88, 90], outline=(240, 240, 245, 160), width=2)
            d.line([64, 50, 64, 90], fill=(240, 240, 245, 120), width=2)
        elif kind == "leather":
            d.arc([40, 48, 88, 96], 200, 340, fill=(80, 50, 30, 180), width=3)
        else:
            d.ellipse([48, 55, 80, 85], fill=(c2[0], c2[1], c2[2], 120))
        path = OUT / f"armor_{eid}.png"
        img.save(path)
        print(f"wrote {path} size={path.stat().st_size}")
    print("done", [p.name for p in sorted(OUT.glob("armor_*.png"))])


if __name__ == "__main__":
    main()
