#!/usr/bin/env python3
"""Colour-blindness simulator and legibility check for Omadungeon screenshots.

Takes the PNGs `tools/run-scenario.sh` writes into `tests/out/`, re-renders each one as a
protanope, deuteranope, tritanope and a fully achromatic viewer would see it, and (given
named swatches) reports whether the things the UI expects a player to tell apart are still
distinguishable once hue is gone.

Why it exists: rarity borders, status effects and danger states are colour-coded. The rule
in `docs/GAME_DESIGN.md` is that colour is never the only channel, and `colorblind_glyphs`
adds shapes and pip counts behind a setting. This is how that claim gets checked instead of
asserted: run a scenario twice (setting off, setting on), sample the swatches, and look at
whether the pairs separate.

Pure stdlib on purpose (zlib + struct): it is a development tool that has to run on any
machine that can run the test suite, with no wheels to install. It reads and writes 8-bit
non-interlaced PNGs, which is what Godot's `--screenshot` and this project's art tools emit.

Usage
-----
    tools/colourblind_check.py tests/out/chest.png
    tools/colourblind_check.py tests/out/chest.png --out tests/out/cb
    tools/colourblind_check.py tests/out/chest.png \\
        --swatch common=40,96,6,6 --swatch rare=152,96,6,6 --swatch epic=264,96,6,6 \\
        --min-delta 12

Exit status is 1 when any swatch pair falls below `--min-delta` in any simulation, so it can
gate a screenshot check the same way a test does.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import struct
import sys
import zlib

# --- PNG I/O -----------------------------------------------------------------------------

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


class Image:
    """An 8-bit RGBA raster. `pixels` is a flat bytearray of w*h*4 bytes."""

    def __init__(self, width: int, height: int, pixels: bytearray) -> None:
        self.width = width
        self.height = height
        self.pixels = pixels

    def get(self, x: int, y: int) -> tuple[int, int, int, int]:
        i = (y * self.width + x) * 4
        return tuple(self.pixels[i : i + 4])  # type: ignore[return-value]

    def region_mean(self, x: int, y: int, w: int, h: int) -> tuple[float, float, float]:
        """Alpha-weighted mean RGB of a rectangle, clipped to the image."""
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(self.width, x + w), min(self.height, y + h)
        if x1 <= x0 or y1 <= y0:
            raise ValueError(f"swatch {x},{y},{w},{h} lies outside {self.width}x{self.height}")
        totals = [0.0, 0.0, 0.0]
        weight = 0.0
        for yy in range(y0, y1):
            base = yy * self.width * 4
            for xx in range(x0, x1):
                i = base + xx * 4
                a = self.pixels[i + 3] / 255.0
                for c in range(3):
                    totals[c] += self.pixels[i + c] * a
                weight += a
        if weight <= 0.0:
            return (0.0, 0.0, 0.0)
        return (totals[0] / weight, totals[1] / weight, totals[2] / weight)


def _unfilter(raw: bytes, width: int, height: int, stride: int, bpp: int) -> bytearray:
    """Reverses the five PNG scanline filters into a flat sample buffer."""
    out = bytearray(width * 0 + stride * height)
    pos = 0
    for row in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        pos += stride
        start = row * stride
        prior = out[start - stride : start] if row else bytearray(stride)
        if ftype == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prior[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prior[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prior[i]
                c = prior[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif ftype != 0:
            raise ValueError(f"unsupported PNG filter {ftype}")
        out[start : start + stride] = line
    return out


def read_png(path: pathlib.Path) -> Image:
    """Reads an 8-bit non-interlaced PNG (grey, grey+alpha, RGB or RGBA) into RGBA."""
    data = path.read_bytes()
    if data[:8] != PNG_MAGIC:
        raise ValueError(f"{path} is not a PNG")
    pos = 8
    header: tuple[int, ...] | None = None
    idat = bytearray()
    palette = b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        kind = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"PLTE":
            palette = body
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    if header is None:
        raise ValueError(f"{path} has no IHDR")
    width, height, depth, colour, _comp, _filt, interlace = header
    if depth != 8:
        raise ValueError(f"{path}: only 8-bit PNGs are supported (got {depth})")
    if interlace:
        raise ValueError(f"{path}: interlaced PNGs are not supported")
    if colour not in CHANNELS:
        raise ValueError(f"{path}: unsupported colour type {colour}")
    nch = CHANNELS[colour]
    stride = width * nch
    samples = _unfilter(zlib.decompress(bytes(idat)), width, height, stride, nch)
    pixels = bytearray(width * height * 4)
    for i in range(width * height):
        s = i * nch
        o = i * 4
        if colour == 0:
            v = samples[s]
            pixels[o : o + 4] = bytes((v, v, v, 255))
        elif colour == 4:
            v = samples[s]
            pixels[o : o + 4] = bytes((v, v, v, samples[s + 1]))
        elif colour == 2:
            pixels[o : o + 3] = samples[s : s + 3]
            pixels[o + 3] = 255
        elif colour == 3:
            p = samples[s] * 3
            pixels[o : o + 3] = palette[p : p + 3]
            pixels[o + 3] = 255
        else:
            pixels[o : o + 4] = samples[s : s + 4]
    return Image(width, height, pixels)


def write_png(path: pathlib.Path, image: Image) -> None:
    """Writes an 8-bit RGBA PNG with no filtering (small images, fast and deterministic)."""
    raw = bytearray()
    stride = image.width * 4
    for y in range(image.height):
        raw.append(0)
        raw += image.pixels[y * stride : (y + 1) * stride]

    def chunk(kind: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + kind
            + body
            + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", image.width, image.height, 8, 6, 0, 0, 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        PNG_MAGIC
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


# --- colour science ----------------------------------------------------------------------

# Viénot, Brettel & Mollon (1999) dichromat simulation, expressed as a single linear-RGB
# matrix per type. Good enough to answer "do these two UI colours collapse into one?", which
# is all this tool is asked.
SIMULATIONS: dict[str, tuple[tuple[float, float, float], ...]] = {
    "normal": ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)),
    "protanopia": (
        (0.1121, 0.8853, -0.0005),
        (0.1127, 0.8897, -0.0001),
        (0.0045, 0.0000, 1.0019),
    ),
    "deuteranopia": (
        (0.2920, 0.7054, -0.0003),
        (0.2934, 0.7089, 0.0000),
        (-0.0209, 0.0270, 0.9942),
    ),
    "tritanopia": (
        (1.0175, 0.0655, -0.0001),
        (-0.0106, 0.9354, 0.0000),
        (-0.0186, 0.4653, 0.5262),
    ),
    # Total colour blindness: the hardest case, and the one glyph mode is really for.
    "achromatopsia": (
        (0.2126, 0.7152, 0.0722),
        (0.2126, 0.7152, 0.0722),
        (0.2126, 0.7152, 0.0722),
    ),
}

_TO_LINEAR = [
    (v / 255.0 / 12.92) if (v / 255.0) <= 0.04045 else (((v / 255.0) + 0.055) / 1.055) ** 2.4
    for v in range(256)
]


def _to_srgb(value: float) -> int:
    value = min(1.0, max(0.0, value))
    encoded = value * 12.92 if value <= 0.0031308 else 1.055 * (value ** (1 / 2.4)) - 0.055
    return min(255, max(0, int(round(encoded * 255.0))))


def simulate(image: Image, kind: str) -> Image:
    """A copy of `image` as a viewer with `kind` colour vision would see it."""
    matrix = SIMULATIONS[kind]
    out = bytearray(image.pixels)
    for i in range(0, len(out), 4):
        r = _TO_LINEAR[out[i]]
        g = _TO_LINEAR[out[i + 1]]
        b = _TO_LINEAR[out[i + 2]]
        for c in range(3):
            m = matrix[c]
            out[i + c] = _to_srgb(m[0] * r + m[1] * g + m[2] * b)
    return Image(image.width, image.height, out)


def simulate_rgb(rgb: tuple[float, float, float], kind: str) -> tuple[float, float, float]:
    """`simulate` for a single colour, kept in 0..255 floats."""
    matrix = SIMULATIONS[kind]
    lin = [_TO_LINEAR[min(255, max(0, int(round(c))))] for c in rgb]
    return tuple(  # type: ignore[return-value]
        float(_to_srgb(m[0] * lin[0] + m[1] * lin[1] + m[2] * lin[2])) for m in matrix
    )


def _lab(rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    lin = [_TO_LINEAR[min(255, max(0, int(round(c))))] for c in rgb]
    x = (0.4124 * lin[0] + 0.3576 * lin[1] + 0.1805 * lin[2]) / 0.95047
    y = 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
    z = (0.0193 * lin[0] + 0.1192 * lin[1] + 0.9505 * lin[2]) / 1.08883

    def f(t: float) -> float:
        return t ** (1 / 3) if t > 0.008856 else (7.787 * t) + 16 / 116

    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def delta_e(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    """CIE76 colour difference. Below ~10 two UI fills read as the same colour."""
    la, lb = _lab(a), _lab(b)
    return sum((la[i] - lb[i]) ** 2 for i in range(3)) ** 0.5


def contrast_ratio(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    """WCAG contrast ratio, the channel that survives every kind of colour blindness."""

    def lum(c: tuple[float, float, float]) -> float:
        lin = [_TO_LINEAR[min(255, max(0, int(round(v))))] for v in c]
        return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]

    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


# --- CLI ---------------------------------------------------------------------------------


def parse_swatch(text: str) -> tuple[str, tuple[int, int, int, int]]:
    """`name=x,y,w,h` -> ("name", (x, y, w, h))."""
    name, _, rect = text.partition("=")
    if not rect:
        raise argparse.ArgumentTypeError(f"swatch must be name=x,y,w,h (got {text!r})")
    parts = rect.split(",")
    if len(parts) != 4:
        raise argparse.ArgumentTypeError(f"swatch rect must be x,y,w,h (got {rect!r})")
    return name, tuple(int(p) for p in parts)  # type: ignore[return-value]


def check_swatches(
    image: Image, swatches: list[tuple[str, tuple[int, int, int, int]]], min_delta: float
) -> tuple[list[dict], bool]:
    """Pairwise separation of every swatch under every simulation.

    Returns the rows and whether all of them passed. A pair passes when it keeps `min_delta`
    of CIE76 difference, or 3:1 of contrast, under every simulation: either channel alone is
    enough to tell two things apart without hue.
    """
    means = {name: image.region_mean(*rect) for name, rect in swatches}
    rows: list[dict] = []
    ok = True
    names = [name for name, _ in swatches]
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = names[i], names[j]
            row: dict = {"pair": f"{a} vs {b}", "worst": None, "sims": {}}
            worst = None
            for kind in SIMULATIONS:
                sa = simulate_rgb(means[a], kind)
                sb = simulate_rgb(means[b], kind)
                de = delta_e(sa, sb)
                cr = contrast_ratio(sa, sb)
                passed = de >= min_delta or cr >= 3.0
                row["sims"][kind] = {
                    "delta_e": round(de, 2),
                    "contrast": round(cr, 2),
                    "pass": passed,
                }
                if worst is None or de < worst[1]:
                    worst = (kind, de)
                if not passed:
                    ok = False
            row["worst"] = {"simulation": worst[0], "delta_e": round(worst[1], 2)}
            rows.append(row)
    return rows, ok


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("images", nargs="+", type=pathlib.Path)
    parser.add_argument(
        "--out",
        type=pathlib.Path,
        default=None,
        help="directory for the simulated PNGs (default: alongside the input)",
    )
    parser.add_argument(
        "--swatch",
        action="append",
        default=[],
        type=parse_swatch,
        metavar="NAME=X,Y,W,H",
        help="a rectangle whose mean colour must stay distinct from the other swatches",
    )
    parser.add_argument(
        "--min-delta",
        type=float,
        default=12.0,
        help="CIE76 difference a swatch pair must keep under every simulation (default 12)",
    )
    parser.add_argument(
        "--simulations",
        default=",".join(k for k in SIMULATIONS if k != "normal"),
        help="comma-separated subset of: " + ", ".join(SIMULATIONS),
    )
    parser.add_argument("--no-write", action="store_true", help="only report, write no PNGs")
    parser.add_argument("--json", action="store_true", help="machine-readable report")
    args = parser.parse_args(argv)

    kinds = [k.strip() for k in args.simulations.split(",") if k.strip()]
    for kind in kinds:
        if kind not in SIMULATIONS:
            parser.error(f"unknown simulation {kind!r}")

    report: list[dict] = []
    ok = True
    for path in args.images:
        image = read_png(path)
        entry: dict = {"image": str(path), "size": [image.width, image.height], "written": []}
        if not args.no_write:
            out_dir = args.out or path.parent
            for kind in kinds:
                target = out_dir / f"{path.stem}_{kind}.png"
                write_png(target, simulate(image, kind))
                entry["written"].append(str(target))
        if args.swatch:
            rows, passed = check_swatches(image, args.swatch, args.min_delta)
            entry["pairs"] = rows
            entry["pass"] = passed
            ok = ok and passed
        report.append(entry)

    if args.json:
        print(json.dumps(report, indent=2))
        return 0 if ok else 1
    for entry in report:
        print(f"{entry['image']}  {entry['size'][0]}x{entry['size'][1]}")
        for written in entry["written"]:
            print(f"  wrote {written}")
        for row in entry.get("pairs", []):
            worst = row["worst"]
            mark = "ok " if all(s["pass"] for s in row["sims"].values()) else "FAIL"
            print(
                f"  {mark} {row['pair']}: worst {worst['simulation']} "
                f"dE {worst['delta_e']}"
            )
            for kind, sim in row["sims"].items():
                print(
                    f"        {kind:<14} dE {sim['delta_e']:>6}  contrast {sim['contrast']:>5}"
                    f"  {'pass' if sim['pass'] else 'FAIL'}"
                )
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
