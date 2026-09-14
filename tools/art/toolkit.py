"""Tiny deterministic pixel-art toolkit shared by the Omadungeon art generators.

Everything here is pure: canvases are small RGBA buffers, all randomness comes from an
explicit ``random.Random`` seeded by the caller, so re-running a generator produces byte
identical PNGs.
"""
from __future__ import annotations

import pathlib
import random
from dataclasses import dataclass
from typing import Callable, Iterable, Mapping, Sequence

from PIL import Image

Color = tuple[int, int, int, int]
TRANSPARENT: Color = (0, 0, 0, 0)
OUTLINE: Color = (0x10, 0x10, 0x10, 255)
WHITE: Color = (255, 255, 255, 255)

# The 8-colour authoring ramp used by every environment tile (palette-swap shader input).
RAMP: dict[str, Color] = {
    ".": TRANSPARENT,
    "o": OUTLINE,
    "d": (0x30, 0x30, 0x30, 255),
    "m": (0x50, 0x50, 0x50, 255),
    "l": (0x70, 0x70, 0x70, 255),
    "h": (0x90, 0x90, 0x90, 255),
    "A": (0xB0, 0x00, 0x00, 255),
    "B": (0x00, 0x00, 0xB0, 255),
}
RAMP_COLORS: frozenset[Color] = frozenset(RAMP.values())


def relative_luminance(color: Color) -> float:
    """WCAG relative luminance of an RGBA tuple (alpha ignored)."""
    def lin(v: int) -> float:
        f = v / 255.0
        return f / 12.92 if f <= 0.03928 else ((f + 0.055) / 1.055) ** 2.4

    return 0.2126 * lin(color[0]) + 0.7152 * lin(color[1]) + 0.0722 * lin(color[2])


def contrast_ratio(a: Color, b: Color) -> float:
    """WCAG contrast ratio between two RGBA tuples, 1.0 (same) to 21.0 (black on white)."""
    la, lb = relative_luminance(a), relative_luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def hex_color(value: str, alpha: int = 255) -> Color:
    """``"#rrggbb"`` -> RGBA tuple."""
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


def shade(color: Color, amount: float) -> Color:
    """Darken (amount < 1) or lighten (amount > 1) a colour, keeping alpha."""
    r, g, b, a = color
    if amount <= 1.0:
        return (int(r * amount), int(g * amount), int(b * amount), a)
    return (
        min(255, int(r + (255 - r) * (amount - 1.0))),
        min(255, int(g + (255 - g) * (amount - 1.0))),
        min(255, int(b + (255 - b) * (amount - 1.0))),
        a,
    )


def mix(a: Color, b: Color, t: float) -> Color:
    """Linear blend of two colours."""
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(4))  # type: ignore[return-value]


def ramp3(base: Color) -> tuple[Color, Color, Color]:
    """Shadow / base / highlight triplet for a base colour."""
    return shade(base, 0.62), base, shade(base, 1.35)


class Canvas:
    """A small RGBA pixel buffer with integer drawing helpers."""

    def __init__(self, width: int, height: int, fill: Color = TRANSPARENT) -> None:
        self.width = width
        self.height = height
        self.pixels: list[Color] = [fill] * (width * height)

    # -- basic access -------------------------------------------------------------------
    def in_bounds(self, x: int, y: int) -> bool:
        return 0 <= x < self.width and 0 <= y < self.height

    def get(self, x: int, y: int) -> Color:
        if not self.in_bounds(x, y):
            return TRANSPARENT
        return self.pixels[y * self.width + x]

    def set(self, x: int, y: int, color: Color) -> None:
        if self.in_bounds(x, y):
            self.pixels[y * self.width + x] = color

    def put(self, x: int, y: int, color: Color) -> None:
        """Alpha-aware set: fully transparent colours are skipped."""
        if color[3] == 0:
            return
        self.set(x, y, color)

    def copy(self) -> "Canvas":
        c = Canvas(self.width, self.height)
        c.pixels = list(self.pixels)
        return c

    def is_empty(self) -> bool:
        return all(p[3] == 0 for p in self.pixels)

    # -- primitives ---------------------------------------------------------------------
    def fill(self, color: Color) -> None:
        self.pixels = [color] * (self.width * self.height)

    def rect(self, x: int, y: int, w: int, h: int, color: Color, filled: bool = True) -> None:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                edge = yy in (y, y + h - 1) or xx in (x, x + w - 1)
                if filled or edge:
                    self.put(xx, yy, color)

    def hline(self, x0: int, x1: int, y: int, color: Color) -> None:
        for x in range(min(x0, x1), max(x0, x1) + 1):
            self.put(x, y, color)

    def vline(self, x: int, y0: int, y1: int, color: Color) -> None:
        for y in range(min(y0, y1), max(y0, y1) + 1):
            self.put(x, y, color)

    def line(self, x0: int, y0: int, x1: int, y1: int, color: Color) -> None:
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.put(x0, y0, color)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def circle(self, cx: float, cy: float, r: float, color: Color, filled: bool = True) -> None:
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                d = (x - cx) ** 2 + (y - cy) ** 2
                if filled and d <= r * r + 0.25:
                    self.put(x, y, color)
                elif not filled and abs(d - r * r) <= r + 0.5:
                    self.put(x, y, color)

    def ellipse(self, cx: float, cy: float, rx: float, ry: float, color: Color) -> None:
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0 + 0.15:
                    self.put(x, y, color)

    def dither(self, x: int, y: int, w: int, h: int, a: Color, b: Color, phase: int = 0) -> None:
        """Checkerboard fill of two colours (classic 50% dither)."""
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.put(xx, yy, a if (xx + yy + phase) % 2 == 0 else b)

    def blit(self, other: "Canvas", x: int, y: int) -> None:
        """Composite ``other`` onto this canvas (opaque-over, no partial alpha blending)."""
        for yy in range(other.height):
            for xx in range(other.width):
                self.put(x + xx, y + yy, other.get(xx, yy))

    # -- whole-sprite transforms (return new canvases) -----------------------------------
    def flip_h(self) -> "Canvas":
        c = Canvas(self.width, self.height)
        for y in range(self.height):
            for x in range(self.width):
                c.set(self.width - 1 - x, y, self.get(x, y))
        return c

    def flip_v(self) -> "Canvas":
        c = Canvas(self.width, self.height)
        for y in range(self.height):
            for x in range(self.width):
                c.set(x, self.height - 1 - y, self.get(x, y))
        return c

    def rotate90(self, turns: int = 1) -> "Canvas":
        """Rotate clockwise by 90 degrees ``turns`` times (square canvases only)."""
        c = self
        for _ in range(turns % 4):
            n = Canvas(c.height, c.width)
            for y in range(c.height):
                for x in range(c.width):
                    n.set(c.height - 1 - y, x, c.get(x, y))
            c = n
        return c

    def shift(self, dx: int, dy: int) -> "Canvas":
        c = Canvas(self.width, self.height)
        c.blit(self, dx, dy)
        return c

    def mirror(self, axis: int | None = None) -> "Canvas":
        """Mirror the left half onto the right half (symmetric sprites)."""
        c = self.copy()
        half = self.width // 2 if axis is None else axis
        for y in range(self.height):
            for x in range(half):
                c.set(self.width - 1 - x, y, self.get(x, y))
        return c

    def recolor(self, mapping: Mapping[Color, Color]) -> "Canvas":
        c = self.copy()
        c.pixels = [mapping.get(p, p) for p in c.pixels]
        return c

    def map_pixels(self, fn: Callable[[Color], Color]) -> "Canvas":
        c = self.copy()
        c.pixels = [fn(p) if p[3] else p for p in c.pixels]
        return c

    def flash(self, color: Color = WHITE, keep_outline: bool = True) -> "Canvas":
        """Hurt flash: every opaque non-outline pixel becomes ``color``."""
        return self.map_pixels(lambda p: p if (keep_outline and p == OUTLINE) else color)

    def fade(self, alpha: float) -> "Canvas":
        """Reduce alpha of every pixel (death fade)."""
        return self.map_pixels(lambda p: (p[0], p[1], p[2], int(p[3] * alpha)))

    def bbox(self) -> tuple[int, int, int, int] | None:
        xs = [i % self.width for i, p in enumerate(self.pixels) if p[3]]
        ys = [i // self.width for i, p in enumerate(self.pixels) if p[3]]
        if not xs:
            return None
        return min(xs), min(ys), max(xs) + 1, max(ys) + 1

    def scaled(self, sx: float, sy: float, anchor: str = "bottom") -> "Canvas":
        """Nearest-neighbour squash/stretch of the opaque bbox, anchored at the bottom centre."""
        box = self.bbox()
        if box is None:
            return self.copy()
        x0, y0, x1, y1 = box
        w, h = x1 - x0, y1 - y0
        nw, nh = max(1, int(round(w * sx))), max(1, int(round(h * sy)))
        src = Canvas(w, h)
        for y in range(h):
            for x in range(w):
                src.set(x, y, self.get(x0 + x, y0 + y))
        dst = Canvas(nw, nh)
        for y in range(nh):
            for x in range(nw):
                dst.set(x, y, src.get(int(x * w / nw), int(y * h / nh)))
        out = Canvas(self.width, self.height)
        cx = x0 + w / 2.0
        ox = int(round(cx - nw / 2.0))
        oy = (y1 - nh) if anchor == "bottom" else y0
        out.blit(dst, ox, oy)
        return out

    def outline(self, color: Color = OUTLINE, diagonal: bool = False) -> "Canvas":
        """Add a 1 px outline around all opaque pixels (into transparent neighbours)."""
        c = self.copy()
        offsets = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        if diagonal:
            offsets += [(1, 1), (-1, -1), (1, -1), (-1, 1)]
        for y in range(self.height):
            for x in range(self.width):
                if self.get(x, y)[3]:
                    continue
                if any(self.get(x + dx, y + dy)[3] for dx, dy in offsets):
                    c.set(x, y, color)
        return c

    def crop(self, x: int, y: int, w: int, h: int) -> "Canvas":
        c = Canvas(w, h)
        for yy in range(h):
            for xx in range(w):
                c.set(xx, yy, self.get(x + xx, y + yy))
        return c

    def resized(self, w: int, h: int) -> "Canvas":
        """Nearest-neighbour resize of the whole canvas."""
        out = Canvas(w, h)
        for y in range(h):
            for x in range(w):
                out.set(x, y, self.get(int(x * self.width / w), int(y * self.height / h)))
        return out

    # -- pixel maps -----------------------------------------------------------------------
    @classmethod
    def from_map(cls, rows: Sequence[str], palette: Mapping[str, Color], width: int = 0,
                 height: int = 0) -> "Canvas":
        """Build a canvas from strings of palette keys. ``.`` is always transparent."""
        h = height or len(rows)
        w = width or max(len(r) for r in rows)
        c = cls(w, h)
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in (".", " "):
                    continue
                if ch not in palette:
                    raise KeyError(f"palette key {ch!r} missing (row {y})")
                c.set(x, y, palette[ch])
        return c

    # -- io -------------------------------------------------------------------------------
    def to_image(self) -> Image.Image:
        img = Image.new("RGBA", (self.width, self.height))
        img.putdata(self.pixels)
        return img

    def save(self, path: pathlib.Path | str) -> None:
        path = pathlib.Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        self.to_image().save(path, optimize=True)


@dataclass
class Sheet:
    """A grid of equally sized cells that assembles into one PNG."""

    cell_w: int
    cell_h: int
    cols: int
    rows: int

    def __post_init__(self) -> None:
        self.canvas = Canvas(self.cell_w * self.cols, self.cell_h * self.rows)

    def put(self, col: int, row: int, cell: Canvas) -> None:
        if col >= self.cols or row >= self.rows:
            raise IndexError(f"cell ({col},{row}) outside {self.cols}x{self.rows} sheet")
        self.canvas.blit(cell, col * self.cell_w, row * self.cell_h)

    def put_row(self, row: int, cells: Iterable[Canvas], start_col: int = 0) -> None:
        for i, cell in enumerate(cells):
            self.put(start_col + i, row, cell)

    def save(self, path: pathlib.Path | str) -> None:
        self.canvas.save(path)


def rng_for(name: str) -> random.Random:
    """A ``random.Random`` seeded by a stable string hash (independent of PYTHONHASHSEED)."""
    seed = 0
    for ch in name:
        seed = (seed * 131 + ord(ch)) & 0xFFFFFFFF
    return random.Random(seed)


def noise_grid(w: int, h: int, rng: random.Random) -> list[list[float]]:
    return [[rng.random() for _ in range(w)] for _ in range(h)]


def row_empty(c: Canvas, y: int) -> bool:
    """True when no pixel of row ``y`` is opaque."""
    return all(c.get(x, y)[3] == 0 for x in range(c.width))


def hover(base: Canvas, dy: int, foot_rows: int = 3) -> Canvas:
    """Vertical bob that never clips the sprite.

    16x16 body maps usually touch both row 0 and row 15, so a plain ``shift`` drops the
    top of the head (or the soles) off the canvas and the silhouette flickers as the
    animation loops. This translates the sprite only when there is free margin on the
    side it moves toward; otherwise it sinks the body into the legs and keeps the feet
    planted, which reads as a breath / knee bend and loses no pixels.
    """
    if dy == 0:
        return base.copy()
    if dy < 0 and all(row_empty(base, y) for y in range(-dy)):
        return base.shift(0, dy)
    if dy > 0 and all(row_empty(base, base.height - 1 - y) for y in range(dy)):
        return base.shift(0, dy)
    amount = abs(dy)
    body = Canvas(base.width, base.height)
    for y in range(base.height - foot_rows):
        for x in range(base.width):
            body.set(x, y, base.get(x, y))
    out = body.shift(0, amount)
    for y in range(base.height - foot_rows, base.height):
        for x in range(base.width):
            p = base.get(x, y)
            if p[3]:
                out.set(x, y, p)
    return out


def bob_frames(base: Canvas, count: int, amplitude: int = 1) -> list[Canvas]:
    """Idle bob: alternate between the base and a hovered version (see ``hover``)."""
    frames = []
    for i in range(count):
        phase = i % 4
        dy = -amplitude if phase in (1, 2) else 0
        frames.append(hover(base, dy))
    return frames


def hurt_frames(base: Canvas) -> list[Canvas]:
    """Two hurt frames: a posed recoil with a hot rim, then the settle.

    The consumers already flash the sprite in code (``Player._flash`` drives
    flash.gdshader, ``EnemyBase`` pulses ``self_modulate``), so the art keeps its colours
    and supplies the *pose*: leaning away, squashed, rimmed in hot pink.
    """
    lean = base.scaled(1.1, 0.9).shift(-1, 0)
    return [rim(lean, (255, 140, 140, 255)), lean]


def dissolve(base: Canvas, keep: float, rng: random.Random) -> Canvas:
    """Drop a deterministic subset of pixels (classic pixel dissolve)."""
    c = Canvas(base.width, base.height)
    for y in range(base.height):
        for x in range(base.width):
            p = base.get(x, y)
            if p[3] and rng.random() < keep:
                c.set(x, y, p)
    return c


def rim(base: Canvas, color: Color, diagonal: bool = True) -> Canvas:
    """Base sprite wrapped in a bright 1 px rim (telegraph glow), outline kept."""
    glow = base.outline(color, diagonal=diagonal)
    out = glow.copy()
    for y in range(base.height):
        for x in range(base.width):
            p = base.get(x, y)
            if p[3]:
                out.set(x, y, p)
    return out


def collapse_death(base: Canvas, count: int, ground_y: int | None = None) -> list[Canvas]:
    """Collapse into a heap and dissolve: impact flash, squash, sink, fade to dust.

    Reads far better at 16x16 than rotating the sprite: the silhouette keeps its width
    and loses height, so it always looks like the body hitting the floor.
    """
    del ground_y  # frames are anchored on the sprite's own feet
    rng = random.Random(0xD1E)
    stages: list[Canvas] = [
        base.flash((255, 110, 110, 255)),
        base.scaled(1.25, 0.78),
        base.scaled(1.35, 0.52).map_pixels(lambda p: mix(p, (40, 30, 34, 255), 0.25)),
        dissolve(base.scaled(1.4, 0.34), 0.85, rng).fade(0.8),
        dissolve(base.scaled(1.45, 0.22), 0.6, rng).fade(0.55),
        dissolve(base.scaled(1.5, 0.16), 0.3, rng).fade(0.3),
    ]
    if count <= 4:
        stages = [stages[0], stages[1], stages[2], stages[4]]
    return stages[:count]


def pixel_font_text(text: str, color: Color, spacing: int = 1) -> Canvas:
    """Render text with the built-in 3x5 micro font (uppercase, digits, few symbols)."""
    glyphs = {
        "A": ["010", "101", "111", "101", "101"],
        "B": ["110", "101", "110", "101", "110"],
        "C": ["011", "100", "100", "100", "011"],
        "D": ["110", "101", "101", "101", "110"],
        "E": ["111", "100", "110", "100", "111"],
        "F": ["111", "100", "110", "100", "100"],
        "G": ["011", "100", "101", "101", "011"],
        "H": ["101", "101", "111", "101", "101"],
        "I": ["111", "010", "010", "010", "111"],
        "J": ["001", "001", "001", "101", "010"],
        "K": ["101", "110", "100", "110", "101"],
        "L": ["100", "100", "100", "100", "111"],
        "M": ["101", "111", "111", "101", "101"],
        "N": ["110", "101", "101", "101", "101"],
        "O": ["010", "101", "101", "101", "010"],
        "P": ["110", "101", "110", "100", "100"],
        "Q": ["010", "101", "101", "011", "001"],
        "R": ["110", "101", "110", "101", "101"],
        "S": ["011", "100", "010", "001", "110"],
        "T": ["111", "010", "010", "010", "010"],
        "U": ["101", "101", "101", "101", "011"],
        "V": ["101", "101", "101", "101", "010"],
        "W": ["101", "101", "111", "111", "101"],
        "X": ["101", "101", "010", "101", "101"],
        "Y": ["101", "101", "010", "010", "010"],
        "Z": ["111", "001", "010", "100", "111"],
        "0": ["010", "101", "101", "101", "010"],
        "1": ["010", "110", "010", "010", "111"],
        "2": ["110", "001", "010", "100", "111"],
        "3": ["110", "001", "010", "001", "110"],
        "4": ["101", "101", "111", "001", "001"],
        "5": ["111", "100", "110", "001", "110"],
        "6": ["011", "100", "110", "101", "010"],
        "7": ["111", "001", "010", "010", "010"],
        "8": ["010", "101", "010", "101", "010"],
        "9": ["010", "101", "011", "001", "110"],
        "-": ["000", "000", "111", "000", "000"],
        "+": ["000", "010", "111", "010", "000"],
        "?": ["110", "001", "010", "000", "010"],
        "!": ["010", "010", "010", "000", "010"],
        ".": ["000", "000", "000", "000", "010"],
        " ": ["000", "000", "000", "000", "000"],
    }
    width = sum(3 + spacing for _ in text) - spacing
    c = Canvas(max(1, width), 5)
    x = 0
    for ch in text.upper():
        rows = glyphs.get(ch, glyphs["?"])
        for y, row in enumerate(rows):
            for i, bit in enumerate(row):
                if bit == "1":
                    c.set(x + i, y, color)
        x += 3 + spacing
    return c
