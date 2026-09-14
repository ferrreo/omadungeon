# Fonts

All fonts here are licensed under the SIL Open Font License 1.1 (see the `OFL-*.txt`
files next to each font). Fetched from https://github.com/google/fonts (`ofl/`).

| File | Family | Use in game | Licence |
|------|--------|-------------|---------|
| `PressStart2P-Regular.ttf` | Press Start 2P (cody@zone38.net) | Titles, logo lockup, damage numbers | `OFL-pressstart2p.txt` |
| `Silkscreen-Regular.ttf` | Silkscreen (Jason Kottke) | HUD labels, small UI text, glyph captions | `OFL-silkscreen.txt` |
| `VT323-Regular.ttf` | VT323 (Peter Hull) | Body text, tooltips, terminal-flavoured menus | `OFL-vt323.txt` |

Rendering notes: the committed `*.ttf.import` files already carry the pixel-perfect import
settings (`antialiasing=0`, `hinting=0`, `subpixel_positioning=0`), so the imported
`FontFile` resources are safe to reference directly from a `.tscn` or `Theme`
(`UiTheme._load_font` sets the same flags when it builds a font from raw bytes). Keep those
values if you re-import, and use the native pixel sizes (Press Start 2P: multiples of 8 px; Silkscreen: multiples of 8 px; VT323:
multiples of 16 px) so glyphs land on the 480x270 pixel grid without blur.

Re-download with `python3 tools/art/fetch_fonts.py`.
