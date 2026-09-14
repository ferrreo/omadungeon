#!/usr/bin/env python3
"""Regenerate every Omadungeon pixel-art asset (deterministic; safe to re-run).

Usage: python3 tools/art/gen_all.py [--sheets]
  --sheets  also write 4x review sheets to tests/out/art_<name>.png

Requires Pillow (``uv run --with pillow python3 tools/art/gen_all.py`` if missing).
"""
from __future__ import annotations

import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import characters  # noqa: E402
import enemies  # noqa: E402
import items  # noqa: E402
import props  # noqa: E402
import tiles  # noqa: E402
import ui  # noqa: E402
from contact_sheet import render  # noqa: E402

ROOT = HERE.parents[1]


def main() -> None:
    written: list[pathlib.Path] = []
    for module in (tiles, characters, enemies, props, items, ui):
        written += module.generate(ROOT)
    for path in written:
        print(path.relative_to(ROOT))
    print(f"{len(written)} files")
    if "--sheets" in sys.argv:
        for path in written:
            name = path.relative_to(ROOT / "assets").with_suffix("").as_posix().replace("/", "_")
            cell = 32 if path.stem in ("clown_car", "dotfile_golem") else 16
            render(path, name, 0 if path.stem in ("logo", "cursor") else cell)
        print(props.review_sheet(ROOT).relative_to(ROOT))
        print("review sheets in tests/out/art_*.png")


if __name__ == "__main__":
    main()
