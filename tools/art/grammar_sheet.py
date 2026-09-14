#!/usr/bin/env python3
"""Review sheet for the world's visual grammar: clutter vs hazard vs reward, side by side.

The three classes have to be separable by *shape*, because the environment ramp is recoloured
at runtime from the desktop theme (see "Reading the world at a glance" in
``assets/tiles/README.md``). So this writes each class twice: as authored, and desaturated to
pure value. If you cannot tell the three bands apart in the grey half, colour is doing work it
is not allowed to do.

Usage: python3 tools/art/grammar_sheet.py [biome]   -> tests/out/art_grammar[_<biome>].png
"""
from __future__ import annotations

import pathlib
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCALE = 6
PAD = 6
LABEL = 11
BG = (26, 28, 34, 255)
INK = (206, 211, 222, 255)
## Idle frame of every hazard that wears a warning frame, then the two deliberate disguises.
HAZARDS = (
    "spike_floor", "fire_vent", "pressure_plate", "laser_grid", "kernel_spike", "pit",
    "ice_slide", "arrow_wall", "mimic_chest", "ricer_trap",
)


def _cells(path: pathlib.Path, count: int | None = None) -> list[Image.Image]:
    img = Image.open(path).convert("RGBA")
    n = img.width // 16 if count is None else count
    return [img.crop((i * 16, 0, i * 16 + 16, 16)) for i in range(n)]


def _grey(cell: Image.Image) -> Image.Image:
    out = cell.convert("LA").convert("RGBA")
    out.putalpha(cell.getchannel("A"))
    return out


def _band(draw: ImageDraw.ImageDraw, img: Image.Image, y: int, title: str,
          cells: list[tuple[str, Image.Image]]) -> int:
    size = 16 * SCALE
    draw.text((PAD, y), title, fill=INK)
    y += LABEL + 2
    for i, (name, cell) in enumerate(cells):
        x = PAD + i * (size + PAD)
        draw.rectangle([x - 1, y - 1, x + size, y + size], outline=(74, 79, 90, 255))
        img.alpha_composite(cell.resize((size, size), Image.NEAREST), (x, y))
        draw.text((x, y + size + 1), name[:13], fill=INK)
    return y + size + LABEL + PAD


def render(biome: str = "crypt") -> pathlib.Path:
    sprites = ROOT / "assets" / "sprites"
    clutter = list(zip(
        ["clutter"] * 8, _cells(sprites / "props" / f"{biome}.png")
    ))
    props = _cells(sprites / "props" / f"{biome}.png")
    names = [f"{biome[:3]}:{i}" for i in range(8)]
    hazards = [(k[:13], _cells(sprites / "traps" / f"{k}.png")[0]) for k in HAZARDS]
    reward = [("chest", _cells(sprites / "props" / "chest.png", 1)[0])]
    del clutter
    rows = [
        ("CLUTTER - inset, no frame, theme-tinted", list(zip(names, props))),
        ("HAZARD - fills the tile, warning frame (last two are the disguises)", hazards),
        ("REWARD - free-standing box, its own gold", reward),
    ]
    cols = max(len(r[1]) for r in rows)
    width = PAD * 2 + cols * (16 * SCALE + PAD)
    height = PAD + 2 * sum(LABEL + 2 + 16 * SCALE + LABEL + PAD for _ in rows) + LABEL * 2
    img = Image.new("RGBA", (width, height), BG)
    draw = ImageDraw.Draw(img)
    y = PAD
    for title, cells in rows:
        y = _band(draw, img, y, title, cells)
    draw.text((PAD, y), "the same three, value only - the theme cannot help you here", fill=INK)
    y += LABEL + 4
    for title, cells in rows:
        y = _band(draw, img, y, title, [(n, _grey(c)) for n, c in cells])
    out = ROOT / "tests" / "out" / (
        "art_grammar.png" if biome == "crypt" else f"art_grammar_{biome}.png"
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    img.crop((0, 0, width, min(height, y + PAD))).save(out)
    return out


if __name__ == "__main__":
    print(render(sys.argv[1] if len(sys.argv) > 1 else "crypt"))
