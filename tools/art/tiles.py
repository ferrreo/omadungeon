"""Environment tilesets: one 16x5 sheet of 16 px cells per biome, drawn strictly with the
8-colour authoring ramp (see ``toolkit.RAMP``) so the palette-swap shader can retint them.

Sheet layout (documented in assets/tiles/README.md):
  row 0: floor variants x4 (cols 0-3), decorated floors x4 (cols 4-7)
  row 1: wall autotile, 16 cells indexed by 4-bit mask of wall neighbours N=1 E=2 S=4 W=8
  row 2: wall top / cap variants x4
  row 3: pit autotile, 16 cells indexed by 4-bit mask of pit neighbours (same bits)
  row 4: door closed, door open, stairs down, stairs locked, altar, shop counter, shrine, torch x2,
         lantern, brazier, candle, crystal (the wall lanterns the lighting layer hangs)
"""
from __future__ import annotations

import pathlib
import random
from dataclasses import dataclass

from toolkit import RAMP, TRANSPARENT, Canvas, Sheet, rng_for

T = 16
O, D, M, L, H, A, B = (RAMP[k] for k in "odmlhAB")
BIOMES = ("crypt", "forge", "frost", "library", "void")

N_BIT, E_BIT, S_BIT, W_BIT = 1, 2, 4, 8


@dataclass
class Style:
    """Per-biome colour choices inside the ramp.

    The ramp index is *not* a free shade choice: ``src/rooms/tile_ramp.gd`` maps index 1
    to the theme role ``void``, 2 to ``wall``, 3 to ``floor``, 4 to ``floor_alt`` and 5 to
    ``wall_top``, and the palette-swap shader replaces every pixel by that role's colour.
    So floors must be dominated by M (index 3) with L (4) detail, wall faces by D (2) with
    O (1) outlines, and wall caps by H (5). Biome character comes from the *patterns*
    below and from the two accents, never from picking a different shade for a floor.
    """

    floor_base: tuple
    floor_noise: tuple
    floor_light: tuple
    wall_top: tuple
    wall_face: tuple
    wall_face_dark: tuple
    wall_face_light: tuple
    accent: tuple


STYLES: dict[str, Style] = {
    "crypt": Style(M, D, L, H, D, O, H, B),
    "forge": Style(M, D, L, H, D, O, H, A),
    "frost": Style(M, D, L, H, D, O, H, B),
    "library": Style(M, D, L, H, D, O, H, A),
    "void": Style(M, D, L, H, D, O, H, B),
}


# ----------------------------------------------------------------------------- floors
def floor_tile(biome: str, variant: int) -> Canvas:
    st = STYLES[biome]
    rng = rng_for(f"{biome}-floor-{variant}")
    c = Canvas(T, T, st.floor_base)
    if biome == "crypt":
        _flagstones(c, rng, st)
    elif biome == "forge":
        _metal_plates(c, rng, st)
    elif biome == "frost":
        _ice_floor(c, rng, st)
    elif biome == "library":
        _planks(c, rng, st, variant)
    else:
        _void_floor(c, rng, st)
    return c


def _speckle(c: Canvas, rng: random.Random, color: tuple, count: int, avoid: tuple = ()) -> None:
    for _ in range(count):
        x, y = rng.randrange(T), rng.randrange(T)
        if c.get(x, y) not in avoid:
            c.set(x, y, color)


def _flagstones(c: Canvas, rng: random.Random, st: Style) -> None:
    # 2x2 stones of ~8 px with a dark mortar line and light top-left edge.
    off = rng.choice([0, 4])
    for gy in range(2):
        for gx in range(2):
            x0 = (gx * 8 + (off if gy else 0)) % T
            y0 = gy * 8
            c.hline(x0, x0 + 7, y0, st.floor_light)
            c.vline(x0, y0, y0 + 7, st.floor_light)
            c.hline(x0, x0 + 7, y0 + 7, st.floor_noise)
            c.vline((x0 + 7) % T, y0, y0 + 7, st.floor_noise)
    _speckle(c, rng, st.floor_noise, 5, avoid=(st.floor_light,))
    _speckle(c, rng, st.floor_light, 2, avoid=(st.floor_noise,))


def _diamond(c: Canvas, cx: int, cy: int, r: int, color: tuple) -> None:
    for dy in range(-r, r + 1):
        span = r - abs(dy)
        c.hline(cx - span, cx + span, cy + dy, color)


def _metal_plates(c: Canvas, rng: random.Random, st: Style) -> None:
    # Tread plate: raised diamonds on a plain deck, seamed on two edges only.
    #
    # It used to be a full 16 px rectangle of ``floor_noise`` with a bevel inside it, and
    # ``floor_noise`` is ramp index 2 - the *wall* colour. That made a forge floor 38% wall
    # colour against a wall face that is 53% of it, so on floor 6 the two surfaces drew the
    # same rectangular motif at the same value and the room outline was unreadable. The deck
    # is now index 3 with index 4 tread, the seam is two edges instead of four, and the motif
    # is diamonds, which is not what the wall's grid of upright plates is made of.
    c.hline(0, 15, 15, st.floor_noise)
    c.vline(15, 0, 15, st.floor_noise)
    off = rng.choice([0, 2])
    for gx, gy in ((4, 4), (12, 4), (4, 12), (12, 12)):
        x, y = (gx + off) % T, gy
        _diamond(c, x, y, 2, st.floor_light)
        c.set((x + 1) % T, min(y + 2, 15), st.floor_noise)
        c.set((x + 2) % T, min(y + 1, 15), st.floor_noise)
    c.set(rng.randrange(T), rng.randrange(T), O)
    _speckle(c, rng, st.floor_light, 3, avoid=(O, st.floor_noise))


def _ice_floor(c: Canvas, rng: random.Random, st: Style) -> None:
    # Sheet ice: pale patches, hairline cracks in the cool accent, a few frozen bubbles.
    for _ in range(3):
        w, h = rng.randrange(4, 8), rng.randrange(3, 6)
        c.rect(rng.randrange(0, T - w), rng.randrange(0, T - h), w, h, st.floor_light)
    x, y = rng.randrange(T), rng.randrange(T)
    for _ in range(rng.randrange(3, 6)):
        nx, ny = x + rng.randrange(-4, 5), y + rng.randrange(-4, 5)
        c.line(x, y, nx, ny, st.accent)
        x, y = nx % T, ny % T
    _speckle(c, rng, st.floor_noise, 5)
    _speckle(c, rng, st.floor_light, 4)


def _planks(c: Canvas, rng: random.Random, st: Style, variant: int) -> None:
    for i in range(4):
        y = i * 4
        c.hline(0, 15, y, st.floor_noise)
        c.hline(0, 15, y + 1, st.floor_light)
        joint = (variant * 5 + i * 7 + rng.randrange(0, 4)) % T
        c.vline(joint, y, y + 3, st.floor_noise)
        if rng.random() < 0.5:
            c.set((joint + 3) % T, y + 2, O)
    _speckle(c, rng, st.floor_noise, 4, avoid=(st.floor_light,))


def _void_floor(c: Canvas, rng: random.Random, st: Style) -> None:
    for _ in range(rng.randrange(3, 6)):
        s = rng.choice([2, 3, 4])
        x, y = rng.randrange(0, T - s), rng.randrange(0, T - s)
        c.rect(x, y, s, s, st.floor_light, filled=rng.random() < 0.5)
    _speckle(c, rng, O, 8)
    _speckle(c, rng, st.floor_noise, 4)


def decorated_floor(biome: str, variant: int) -> Canvas:
    c = floor_tile(biome, variant % 4)
    rng = rng_for(f"{biome}-deco-{variant}")
    deco = {
        "crypt": _deco_crypt,
        "forge": _deco_forge,
        "frost": _deco_frost,
        "library": _deco_library,
        "void": _deco_void,
    }[biome]
    deco(c, rng, variant)
    return c


def _deco_crypt(c: Canvas, rng: random.Random, variant: int) -> None:
    """Crypt floor detail: marks *on* the floor, never things standing on it.

    The fourth clutter round found the owner's "confetti I can't identify" was not the props
    at all but these cells: a skull with ember eyes, a candle, a jar, a cobweb - objects drawn
    on floor tiles, one in eight of them, right in the fight space, with no collision and no
    place in the prop catalogue. A decorated floor is now a surface mark only: a stain, a
    crack, a seam, a patch of mould, a worn flagstone. No ink outline (that is the solid prop's
    tell), no bright `H` shape (that is an object), and the accent pixels - the one place a
    theme's own colour reaches a floor tile - stay as the tint of a stain, low in footprint.
    """
    if variant % 4 == 0:  # patch of mould in the grout
        c.ellipse(10, 10, 4, 2, D)
        c.ellipse(10, 10, 3, 1, B)
        _speckle(c, rng, A, 3, avoid=(B,))
    elif variant % 4 == 1:  # an old dark stain with a rusty rim
        c.ellipse(7, 8, 5, 3, D)
        c.ellipse(7, 8, 3, 2, M)
        c.set(3, 7, A)
        c.set(11, 9, A)
        c.set(6, 11, A)
    elif variant % 4 == 2:  # crack with something seeping along it
        c.line(2, 3, 7, 8, D)
        c.line(7, 8, 13, 10, D)
        c.line(7, 8, 8, 13, D)
        c.set(6, 7, A)
        c.set(9, 9, A)
        c.set(8, 12, B)
    else:  # a flagstone worn smoother than its neighbours
        c.rect(3, 3, 10, 9, M)
        c.rect(4, 4, 8, 7, L)
        c.hline(4, 11, 4, L)
        c.set(12, 11, A)


def _deco_forge(c: Canvas, rng: random.Random, variant: int) -> None:
    if variant % 4 == 0:  # lava seam in the grout
        c.line(0, 9, 5, 7, D)
        c.line(5, 7, 10, 10, D)
        c.line(10, 10, 15, 8, D)
        c.line(1, 9, 5, 8, A)
        c.line(10, 9, 14, 8, A)
        c.set(7, 9, B)
    elif variant % 4 == 1:  # soot patch with two embers left in it
        c.ellipse(8, 8, 5, 3, D)
        c.ellipse(8, 8, 3, 2, O)
        c.set(7, 8, A)
        c.set(10, 9, A)
    elif variant % 4 == 2:  # a small cooling pool
        c.ellipse(8, 9, 4, 2, D)
        c.ellipse(8, 9, 3, 1, A)
        c.set(8, 9, B)
    else:  # scattered embers on a scorch
        c.ellipse(8, 8, 4, 3, D)
        for _ in range(5):
            c.set(rng.randrange(3, 13), rng.randrange(4, 12), A)
        c.set(8, 8, B)


def _deco_frost(c: Canvas, rng: random.Random, variant: int) -> None:
    if variant % 4 == 0:  # shards lying flat on the ice
        # Deliberately *not* upright spikes: a row of points rising off the floor is what a
        # spike plate looks like, and floor detail must never wear a hazard's shape.
        for x0, y0, x1, y1 in ((2, 5, 7, 7), (9, 4, 13, 6), (4, 11, 10, 12)):
            c.line(x0, y0, x1, y1, B)
            c.line(x0, y0 + 1, x1, y1 + 1, L)
    elif variant % 4 == 1:  # big crack
        c.line(1, 2, 6, 7, B)
        c.line(6, 7, 14, 6, B)
        c.line(6, 7, 9, 14, B)
        c.line(2, 3, 6, 8, L)
    elif variant % 4 == 2:  # a smear of snow blown into the corner
        c.ellipse(11, 12, 4, 2, L)
        c.ellipse(12, 12, 2, 1, H)
    else:  # frozen puddle
        c.ellipse(8, 8, 5, 3, B)
        c.ellipse(8, 8, 3, 2, L)
        c.set(6, 7, H)


def _deco_library(c: Canvas, rng: random.Random, variant: int) -> None:
    if variant % 4 == 0:  # a strip of rug
        # Woven stripes, never concentric rings: a bright closed border on the floor is the
        # hazard grammar (`props.hazard_frame`), and a rug wearing one taught the player to
        # walk around a carpet and onto a spike plate.
        c.rect(2, 4, 12, 8, A)
        for y in range(5, 12, 2):
            c.hline(3, 12, y, D)
        c.set(4, 6, B)
        c.set(11, 10, B)
    elif variant % 4 == 1:  # ink spilt and dried
        c.ellipse(8, 9, 4, 2, D)
        c.ellipse(8, 9, 3, 1, B)
        c.set(4, 7, B)
        c.set(12, 11, B)
    elif variant % 4 == 2:  # wax drips
        c.ellipse(6, 10, 3, 1, L)
        c.ellipse(10, 6, 2, 1, L)
        c.set(6, 10, A)
    else:  # worn boards
        c.hline(2, 13, 5, D)
        c.hline(2, 13, 10, D)
        c.rect(3, 6, 10, 4, M)
        c.set(12, 6, A)


def _deco_void(c: Canvas, rng: random.Random, variant: int) -> None:
    if variant % 4 == 0:  # glitch bars
        for y in (3, 9, 12):
            x0 = rng.randrange(0, 8)
            c.hline(x0, x0 + rng.randrange(3, 7), y, B if y % 2 else A)
    elif variant % 4 == 1:  # missing texture: a torn checker patch, no bordered square
        c.dither(3, 4, 6, 5, A, O)
        c.set(10, 10, B)
        c.set(4, 11, B)
    elif variant % 4 == 2:  # static
        for _ in range(6):
            c.set(rng.randrange(2, 14), rng.randrange(2, 14), rng.choice([A, B, M]))
    else:  # scattered blocks
        for _ in range(4):
            c.rect(rng.randrange(1, 13), rng.randrange(1, 13), 2, 2, rng.choice([A, B, M]))


# ------------------------------------------------------------------------------ walls
def _face_texture(biome: str, c: Canvas, rng: random.Random, st: Style, y0: int) -> None:
    """Fill rows y0..15 with the biome's wall-face texture."""
    c.rect(0, y0, T, T - y0, st.wall_face)
    if biome == "crypt":
        for row, y in enumerate(range(y0, T, 4)):
            off = 0 if row % 2 == 0 else 4
            c.hline(0, 15, y, st.wall_face_dark)
            for x in range(off, T, 8):
                c.vline(x, y, y + 3, st.wall_face_dark)
                c.hline(x + 1, x + 6, y + 1, st.wall_face_light)
    elif biome == "forge":
        c.hline(0, 15, y0, st.wall_face_dark)
        for x in (0, 8):
            c.rect(x, y0 + 1, 8, T - y0 - 1, st.wall_face_dark, filled=False)
            c.set(x + 2, y0 + 3, st.wall_face_light)
            c.set(x + 5, y0 + 3, st.wall_face_light)
        c.hline(2, 13, T - 3, A)
        c.set(6, T - 3, H)
    elif biome == "frost":
        for row, y in enumerate(range(y0, T, 5)):
            off = 0 if row % 2 == 0 else 5
            c.hline(0, 15, y, st.wall_face_dark)
            for x in range(off, T, 10):
                c.vline(x % T, y, y + 4, st.wall_face_dark)
                c.hline((x + 1) % T, (x + 4) % T, y + 1, st.wall_face_light)
        c.line(3, y0 + 2, 6, y0 + 9, B)
        c.line(11, y0 + 4, 13, y0 + 11, B)
    elif biome == "library":
        # Bookshelf: shelf boards every 5 rows, sparse book spines so the wall colour
        # (ramp index 2) still dominates the face and the shelf reads as recessed.
        for y in range(y0 + 4, T, 5):
            c.hline(1, 14, y, st.wall_face_dark)
            c.hline(1, 14, y - 1, st.wall_face_light)
            x = 2
            while x < 14:
                if rng.random() < 0.7:
                    w = rng.choice([1, 2])
                    c.rect(x, y - 3, w, 3, rng.choice([A, B, H]))
                    x += w + 1
                else:
                    x += 2
        c.vline(1, y0 + 1, 14, st.wall_face_dark)
        c.vline(14, y0 + 1, 14, st.wall_face_dark)
    else:  # void: scanlines + glitch blocks
        for y in range(y0 + 2, T, 3):
            c.hline(0, 15, y, O)
        for _ in range(4):
            s = rng.choice([2, 3])
            c.rect(
                rng.randrange(T - s), rng.randrange(y0, T - s), s, s, rng.choice([H, st.accent, A])
            )
        for _ in range(2):
            c.hline(rng.randrange(0, 8), rng.randrange(8, 16), rng.randrange(y0, T), B)


def _top_texture(biome: str, c: Canvas, rng: random.Random, st: Style) -> None:
    c.fill(st.wall_top)
    if biome == "crypt":
        for y in range(0, T, 4):
            c.hline(0, 15, y, O)
        for y in range(0, T, 4):
            c.vline((y // 4 * 5) % T, y, y + 3, O)
    elif biome == "forge":
        c.rect(0, 0, T, T, O, filled=False)
        for x, y in ((2, 2), (13, 2), (2, 13), (13, 13)):
            c.set(x, y, L)
        c.hline(5, 10, 8, L)
    elif biome == "frost":
        # Rime on a snow cap: sparse pale flecks over the cap colour, cool hairline cracks.
        for i in range(0, T, 2):
            for j in range(0, T, 4):
                c.set((i + (j // 4) * 3) % T, (j + i // 2) % T, L)
        c.line(2, 2, 7, 6, B)
        c.line(9, 12, 14, 9, B)
    elif biome == "library":
        for y in range(0, T, 4):
            c.hline(0, 15, y, O)
        for row, y in enumerate(range(2, T, 4)):
            c.vline((row * 5 + 2) % T, y, y + 1, L)
    else:
        for _ in range(10):
            c.set(rng.randrange(T), rng.randrange(T), O)
        c.rect(rng.randrange(0, 10), rng.randrange(0, 10), 4, 4, L, filled=False)
        c.set(rng.randrange(T), rng.randrange(T), B)


def wall_tile(biome: str, mask: int) -> Canvas:
    st = STYLES[biome]
    rng = rng_for(f"{biome}-wall-{mask}")
    c = Canvas(T, T)
    n_open = not mask & N_BIT
    e_open = not mask & E_BIT
    s_open = not mask & S_BIT
    w_open = not mask & W_BIT
    if s_open:
        # Front face: a cap band on top then the face texture, outlined where it meets floor.
        _top_texture(biome, c, rng, st)
        cap = 3
        _face_texture(biome, c, rng, st, cap)
        c.hline(0, 15, cap - 1, st.wall_face_light)
        c.hline(0, 15, cap, O)
        c.hline(0, 15, 15, O)
        if n_open:
            # No wall above: close the cap with an outline + a shadowed band so the cell
            # differs from the same run with a neighbour to the north.
            c.hline(0, 15, 0, O)
            c.hline(0, 15, 1, D)
    else:
        _top_texture(biome, c, rng, st)
        if n_open:
            c.hline(0, 15, 0, O)
            c.hline(0, 15, 1, D)
    if e_open:
        c.vline(15, 0, 15, O)
        if not s_open:
            c.vline(14, 1 if n_open else 0, 14, L)
    if w_open:
        c.vline(0, 0, 15, O)
        c.vline(1, 1 if n_open else 0, 14, st.wall_face_light if s_open else L)
    return c


def wall_cap(biome: str, variant: int) -> Canvas:
    st = STYLES[biome]
    rng = rng_for(f"{biome}-cap-{variant}")
    c = Canvas(T, T)
    _top_texture(biome, c, rng, st)
    c.rect(0, 0, T, T, O, filled=False)
    c.hline(1, 14, 1, st.wall_face_light)
    c.vline(1, 1, 14, st.wall_face_light)
    if variant == 1:
        c.rect(5, 5, 6, 6, O, filled=False)
        c.rect(6, 6, 4, 4, st.accent)
    elif variant == 2:
        c.line(3, 12, 12, 3, O)
        c.line(4, 12, 12, 4, st.wall_face_light)
    elif variant == 3:
        for x, y in ((4, 4), (11, 4), (4, 11), (11, 11)):
            c.set(x, y, O)
            c.set(x + 1, y, L)
    return c


# ------------------------------------------------------------------------------- pits
def pit_tile(biome: str, mask: int) -> Canvas:
    st = STYLES[biome]
    rng = rng_for(f"{biome}-pit-{mask}")
    c = Canvas(T, T, O)
    # deep interior with sparse dark speckle / accent glints
    for _ in range(6):
        c.set(rng.randrange(T), rng.randrange(T), D)
    if biome == "forge":
        c.dither(0, 10, T, 6, A, O, rng.randrange(2))
        c.hline(0, 15, 9, A)
    elif biome == "void":
        for _ in range(3):
            c.set(rng.randrange(T), rng.randrange(T), B)
    n_open = not mask & N_BIT
    e_open = not mask & E_BIT
    s_open = not mask & S_BIT
    w_open = not mask & W_BIT
    lip = st.floor_base
    if n_open:  # floor above: show the lip and a shadowed inner wall
        c.hline(0, 15, 0, lip)
        c.hline(0, 15, 1, D)
        c.hline(0, 15, 2, D if biome != "void" else O)
        for x in range(0, T, 3):
            c.set(x + rng.randrange(3), 2, O)
    if w_open:
        c.vline(0, 0, 15, lip)
        c.vline(1, 0 if not n_open else 1, 15, D)
    if e_open:
        c.vline(15, 0, 15, lip)
        c.vline(14, 0 if not n_open else 1, 15, D)
    if s_open:
        c.hline(0, 15, 15, lip)
        c.hline(1 if w_open else 0, 14 if e_open else 15, 14, D)
    return c


# ---------------------------------------------------------------------------- specials
def door_closed(biome: str) -> Canvas:
    st = STYLES[biome]
    c = Canvas(T, T, st.wall_face)
    c.rect(0, 0, T, T, O, filled=False)
    c.rect(2, 1, 12, 15, O, filled=False)
    c.rect(3, 2, 10, 14, L if biome != "void" else M)
    for x in (5, 8, 11):
        c.vline(x, 2, 15, D)
    c.hline(3, 12, 6, D)
    c.hline(3, 12, 11, D)
    c.rect(4, 5, 8, 1, H)
    c.set(10, 9, st.accent)
    c.set(11, 9, O)
    return c


def door_open(biome: str) -> Canvas:
    st = STYLES[biome]
    c = Canvas(T, T, st.wall_face)
    c.rect(0, 0, T, T, O, filled=False)
    c.rect(2, 1, 12, 15, O)
    c.rect(3, 2, 10, 14, D)
    c.rect(3, 2, 3, 14, L)
    c.vline(4, 2, 15, D)
    c.rect(6, 12, 7, 3, M)  # floor peeking in
    return c


def stairs_down(biome: str, locked: bool = False) -> Canvas:
    """Descending stairs: four steps widening and lightening toward the camera."""
    st = STYLES[biome]
    c = floor_tile(biome, 0)
    c.rect(1, 1, 14, 14, O)  # the shaft
    shades = (D, M, L, H)
    for i, y in enumerate((2, 5, 8, 11)):
        inset = 4 - i
        x0 = 1 + inset
        w = 14 - 2 * inset
        c.rect(x0, y, w, 3, shades[i])
        c.hline(x0, x0 + w - 1, y, O)  # nosing shadow
        c.hline(x0, x0 + w - 1, y + 2, st.floor_noise)
        c.vline(x0, y, y + 2, O)
        c.vline(x0 + w - 1, y, y + 2, O)
    c.rect(1, 1, 14, 14, O, filled=False)
    if locked:
        c.rect(5, 4, 6, 7, st.accent)
        c.rect(5, 4, 6, 7, O, filled=False)
        c.rect(6, 2, 4, 3, O, filled=False)
        c.hline(6, 9, 2, O)
        c.set(7, 7, O)
        c.set(8, 7, O)
        c.set(8, 8, O)
        c.set(6, 5, H)
    return c


def altar(biome: str) -> Canvas:
    st = STYLES[biome]
    c = floor_tile(biome, 1)
    c.rect(3, 9, 10, 5, M)
    c.rect(3, 9, 10, 5, O, filled=False)
    c.rect(2, 8, 12, 2, L)
    c.rect(2, 8, 12, 2, O, filled=False)
    c.rect(5, 4, 6, 4, st.accent)
    c.rect(5, 4, 6, 4, O, filled=False)
    c.set(6, 5, H)
    c.set(7, 2, H)
    c.set(8, 1, st.accent)
    c.set(9, 3, H)
    return c


def shop_counter(biome: str) -> Canvas:
    st = STYLES[biome]
    c = floor_tile(biome, 2)
    c.rect(1, 6, 14, 8, L)
    c.rect(1, 6, 14, 8, O, filled=False)
    c.rect(1, 5, 14, 2, st.accent)
    c.rect(1, 5, 14, 2, O, filled=False)
    c.hline(2, 13, 9, D)
    c.rect(4, 2, 3, 3, H)
    c.rect(4, 2, 3, 3, O, filled=False)
    c.rect(9, 1, 3, 4, B if st.accent == A else A)
    c.rect(9, 1, 3, 4, O, filled=False)
    return c


def shrine(biome: str) -> Canvas:
    """A small arched stone shrine with a glowing niche (accent) and offering bowl."""
    st = STYLES[biome]
    c = floor_tile(biome, 3)
    c.rect(2, 12, 12, 3, M)  # plinth
    c.rect(2, 12, 12, 3, O, filled=False)
    c.hline(3, 12, 12, L)
    c.rect(3, 3, 10, 10, L)  # arched body
    for x, y in ((3, 3), (12, 3), (3, 4), (12, 4)):
        c.set(x, y, TRANSPARENT)
    c.rect(4, 2, 8, 2, L)
    c.rect(3, 3, 10, 10, O, filled=False)
    c.hline(4, 11, 1, O)
    c.hline(4, 11, 2, H)
    c.set(3, 2, O)
    c.set(12, 2, O)
    c.rect(5, 5, 6, 6, O)  # niche
    c.rect(6, 6, 4, 4, D)
    c.circle(7.5, 7.5, 1.6, st.accent)
    c.set(7, 7, H)
    c.rect(6, 11, 4, 2, M)  # offering bowl
    c.rect(6, 11, 4, 2, O, filled=False)
    c.set(7, 11, st.accent)
    c.set(8, 11, H)
    return c


def torch(biome: str, frame: int) -> Canvas:
    """Wall sconce with a two-tone flame.

    The flame body is accent A and its core accent B, never the wall-cap shade H: those two
    rungs are the only ones ``src/rooms/tile_ramp.gd`` will let a flame own (``flame_colors``
    puts the theme's ``heat`` on A and ``loot`` on B), and a core painted in H came out of the
    palette swap in the colour of the brick behind it.
    """
    st = STYLES[biome]
    c = Canvas(T, T)
    c.rect(7, 8, 2, 7, L)
    c.rect(6, 7, 4, 9, O, filled=False)
    c.rect(6, 7, 4, 2, M)
    c.rect(5, 6, 6, 2, O, filled=False)
    flame_h = 5 if frame == 0 else 6
    top = 6 - flame_h
    c.rect(6, top + 1, 4, flame_h - 1, A)
    c.rect(7, top, 2, 1, A)
    c.rect(7, top + 2, 2, 2, B)
    if frame == 1:
        c.set(5, top + 3, A)
        c.set(10, top + 2, A)
        c.set(8, top + 1, B)
    else:
        c.set(10, top + 3, A)
        c.set(7, top + 1, B)
    return c


def lantern(biome: str) -> Canvas:
    """Hanging cage lantern on a bracket: glass body in accent A, flame core in B."""
    st = STYLES[biome]
    c = Canvas(T, T)
    c.rect(4, 3, 8, 1, O)  # bracket
    c.rect(7, 4, 2, 1, O)  # chain
    c.rect(5, 5, 6, 8, O, filled=False)  # cage
    c.rect(6, 6, 4, 6, A)
    c.rect(7, 7, 2, 3, B)
    c.set(6, 6, H)
    c.set(9, 11, D)
    c.rect(6, 5, 4, 1, M)
    c.rect(6, 12, 4, 1, M)
    c.rect(7, 13, 2, 1, O)
    del st
    return c


def brazier(biome: str) -> Canvas:
    """Wall bowl on an iron bracket, coals in accent A, the hot core in B."""
    c = Canvas(T, T)
    c.rect(3, 9, 10, 4, O, filled=False)  # bowl
    c.rect(4, 10, 8, 2, D)
    c.rect(5, 10, 6, 1, M)
    c.rect(6, 13, 4, 2, O)  # bracket
    c.rect(7, 13, 2, 2, D)
    c.rect(4, 7, 8, 2, A)  # coals
    c.rect(5, 5, 6, 2, A)
    c.rect(6, 4, 4, 1, A)
    c.rect(6, 6, 4, 2, B)
    c.set(7, 5, B)
    c.set(5, 8, H)
    c.set(10, 8, H)
    return c


def candle(biome: str) -> Canvas:
    """Three-arm candelabra: wax in L, flames in accent A with B cores."""
    c = Canvas(T, T)
    c.rect(3, 10, 10, 1, O)  # arm
    c.rect(7, 10, 2, 5, O)  # stem
    c.rect(7, 11, 2, 3, D)
    c.rect(6, 14, 4, 1, O)
    for x in (3, 7, 11):
        c.rect(x, 7, 2, 3, L)
        c.set(x, 7, H)
        c.rect(x, 4, 2, 3, A)
        c.set(x, 5, B)
        c.set(x + 1, 6, B)
    c.set(8, 3, A)
    return c


def crystal(biome: str) -> Canvas:
    """A cluster of wall crystals: facets in accent A and B, one ink outline."""
    c = Canvas(T, T)
    c.rect(4, 12, 8, 2, O)  # rock lip
    c.rect(5, 12, 6, 1, D)
    # big shard
    for i, (y, w) in enumerate(((3, 2), (4, 2), (5, 4), (6, 4), (7, 4), (8, 6), (9, 6), (10, 6), (11, 6))):
        x = 8 - w // 2
        c.rect(x, y, w, 1, O)
        if w > 2:
            c.rect(x + 1, y, w - 2, 1, A if i % 3 else B)
    c.set(7, 6, H)
    c.set(7, 8, B)
    # side shards
    c.rect(3, 8, 2, 4, O)
    c.set(3, 9, A)
    c.set(3, 10, B)
    c.rect(11, 9, 2, 3, O)
    c.set(12, 10, A)
    return c


# ------------------------------------------------------------------------------- sheet
def build_biome_sheet(biome: str) -> Sheet:
    sheet = Sheet(T, T, 16, 5)
    sheet.put_row(0, [floor_tile(biome, i) for i in range(4)])
    sheet.put_row(0, [decorated_floor(biome, i) for i in range(4)], start_col=4)
    sheet.put_row(1, [wall_tile(biome, m) for m in range(16)])
    sheet.put_row(2, [wall_cap(biome, i) for i in range(4)])
    sheet.put_row(3, [pit_tile(biome, m) for m in range(16)])
    sheet.put_row(
        4,
        [
            door_closed(biome),
            door_open(biome),
            stairs_down(biome),
            stairs_down(biome, locked=True),
            altar(biome),
            shop_counter(biome),
            shrine(biome),
            torch(biome, 0),
            torch(biome, 1),
            lantern(biome),
            brazier(biome),
            candle(biome),
            crystal(biome),
        ],
    )
    return sheet


def generate(root: pathlib.Path) -> list[pathlib.Path]:
    out = []
    for biome in BIOMES:
        path = root / "assets" / "tiles" / f"{biome}.png"
        sheet = build_biome_sheet(biome)
        bad = {p for p in sheet.canvas.pixels if p not in RAMP.values()}
        if bad:
            raise ValueError(f"{biome}: non-ramp colours {sorted(bad)[:4]}")
        sheet.save(path)
        out.append(path)
    return out
