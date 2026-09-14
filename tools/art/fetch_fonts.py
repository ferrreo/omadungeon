#!/usr/bin/env python3
"""Download the OFL fonts used by Omadungeon into assets/fonts (idempotent).

Also normalises the Godot import settings of any existing ``*.ttf.import`` file to
pixel-perfect rendering (no antialiasing, no hinting, no subpixel positioning) so an
imported font can be referenced straight from a scene without blurring at 480x270.
"""
from __future__ import annotations

import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEST = ROOT / "assets" / "fonts"
BASE = "https://github.com/google/fonts/raw/main/ofl/"
FONTS = {
    "pressstart2p": "PressStart2P-Regular.ttf",
    "silkscreen": "Silkscreen-Regular.ttf",
    "vt323": "VT323-Regular.ttf",
}


def fetch(url: str, dest: pathlib.Path) -> None:
    if dest.exists() and dest.stat().st_size > 0:
        print(f"keep  {dest.relative_to(ROOT)}")
        return
    print(f"fetch {url}")
    with urllib.request.urlopen(url, timeout=60) as resp:  # noqa: S310 - fixed https URLs
        dest.write_bytes(resp.read())


PIXEL_IMPORT = {"antialiasing": "0", "hinting": "0", "subpixel_positioning": "0"}


def pixel_perfect_import(ttf: pathlib.Path) -> None:
    """Rewrite ttf.import params so Godot imports the font unfiltered (no-op if missing)."""
    meta = ttf.with_suffix(ttf.suffix + ".import")
    if not meta.exists():
        return
    lines = meta.read_text().splitlines()
    for i, line in enumerate(lines):
        key = line.split("=", 1)[0]
        if key in PIXEL_IMPORT:
            lines[i] = f"{key}={PIXEL_IMPORT[key]}"
    meta.write_text("\n".join(lines) + "\n")


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    for folder, ttf in FONTS.items():
        fetch(f"{BASE}{folder}/{ttf}", DEST / ttf)
        fetch(f"{BASE}{folder}/OFL.txt", DEST / f"OFL-{folder}.txt")
        pixel_perfect_import(DEST / ttf)


if __name__ == "__main__":
    main()
