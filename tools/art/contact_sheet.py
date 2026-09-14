#!/usr/bin/env python3
"""Upscale a PNG (nearest neighbour, 4x) with an optional grid overlay for visual review.

Usage: contact_sheet.py <png> [name] [cell]  -> tests/out/art_<name>.png
"""
from __future__ import annotations

import pathlib
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCALE = 4


def render(src: pathlib.Path, name: str, cell: int = 16) -> pathlib.Path:
    img = Image.open(src).convert("RGBA")
    big = img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)
    bg = Image.new("RGBA", big.size, (40, 44, 52, 255))
    # checker so transparency is visible
    d = ImageDraw.Draw(bg)
    for y in range(0, big.height, 8):
        for x in range(0, big.width, 8):
            if (x // 8 + y // 8) % 2:
                d.rectangle([x, y, x + 7, y + 7], fill=(48, 52, 62, 255))
    bg.alpha_composite(big)
    if cell:
        d = ImageDraw.Draw(bg)
        for x in range(0, big.width, cell * SCALE):
            d.line([(x, 0), (x, big.height)], fill=(90, 200, 90, 90))
        for y in range(0, big.height, cell * SCALE):
            d.line([(0, y), (big.width, y)], fill=(90, 200, 90, 90))
    out = ROOT / "tests" / "out" / f"art_{name}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    bg.save(out)
    return out


def main() -> None:
    src = pathlib.Path(sys.argv[1])
    name = sys.argv[2] if len(sys.argv) > 2 else src.stem
    cell = int(sys.argv[3]) if len(sys.argv) > 3 else 16
    print(render(src, name, cell))


if __name__ == "__main__":
    main()
