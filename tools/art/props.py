"""Props, chests, pickups, projectiles, traps and FX particles.

* assets/sprites/props/chest.png      4 cells: closed, open, glow (white, modulate to tint), wobble
* assets/sprites/props/<biome>.png    KIND_COUNT props per biome (4 shared + 5 of the biome's
                                      own), drawn in the environment ramp; row 1 holds the
                                      debris frame of every solid kind
* assets/sprites/pickups.png          16 cells: 0-3 gold coin spin, 4 heart, 5-10 stat orbs
                                      (vitality might precision arcana swiftness fortune)
* assets/sprites/projectiles.png      16 cells (see PROJECTILES)
* assets/sprites/traps/<kind>.png     frame strips (see TRAP_FRAMES; frame 0 idle, 1 telegraph,
                                      2 active, as `TrapBase` expects) + traps/arrow.png (8x4)
* assets/sprites/fx/particles.png     4 cells: dust, spark, confetti, smoke (8x8 art in 16x16 cells)

The world's visual grammar lives here: clutter is inset (`_assert_inset`), a hazard fills its
tile and wears `hazard_frame`, and a reward keeps its own gold. See "Reading the world at a
glance" in `assets/tiles/README.md` for what the three classes promise the player, and
`tests/unit/rooms/art_grammar_test.gd` for the assertions on the shipped PNGs.
"""
from __future__ import annotations

import json
import pathlib
from typing import Callable

from prop_maps import (
    ANVIL, BARREL, BONES, BOOKS, BOOKSHELF, BOULDER, BRAZIER, CANDLE, CART, CHAIN, COFFIN,
    CRATE, CRYSTAL, DESK, FLOATER, GLOBE, GRAVESTONE, ICE_BLOCK, LANTERN, LECTERN, MONOLITH,
    ORB, RIFT, RUBBLE, SACK, SLAG, SNOW, SNOWMAN, URN,
)
from tiles import BIOMES
from toolkit import (
    OUTLINE, RAMP, TRANSPARENT, WHITE, Canvas, Color, Sheet, contrast_ratio, hex_color, rng_for,
    shade,
)

Drawer = Callable[[Canvas], None]

T = 16
O, D, M, L, H, A, B = (RAMP[k] for k in "odmlhAB")

WOOD = hex_color("#8b5a2b")
WOOD_D = hex_color("#5a3a1a")
WOOD_L = hex_color("#b07a3b")
GOLD = hex_color("#f2c94c")
GOLD_D = hex_color("#b58b1e")
GOLD_L = hex_color("#fff0a0")
STEEL = hex_color("#c8ccd8")
STEEL_D = hex_color("#7c8298")
STONE = hex_color("#8a8a92")
STONE_D = hex_color("#5a5a62")


# ------------------------------------------------------------------------------ chest
CHEST_PALETTE: dict[str, Color] = {
    "o": OUTLINE,
    "w": WOOD,
    "W": WOOD_L,
    "d": WOOD_D,
    "k": hex_color("#2a1a0c"),
    "g": GOLD,
    "G": GOLD_D,
    "y": GOLD_L,
}

CHEST_CLOSED = (
    "................",
    "................",
    "................",
    "...oooooooooo...",
    "..oWWWWWWWWWWo..",
    ".owwwwwwwwwwwwo.",
    ".owwwwwggwwwwwo.",
    ".oGGGGGyyGGGGGo.",
    ".oooooooooooooo.",
    ".owwwwgGGgwwwwo.",
    ".owwwwgoogwwwwo.",
    ".oddddgGGgddddo.",
    ".oddddddddddddo.",
    ".oGGGGGGGGGGGGo.",
    ".oooooooooooooo.",
    "................",
)

CHEST_OPEN = (
    "................",
    "..oooooooooooo..",
    ".odddddddddddoo.",
    ".odddddddddddo..",
    ".oGGGGGGGGGGGo..",
    ".oooooooooooooo.",
    ".okkkkkkkkkkkko.",
    ".okygyggygygyko.",
    ".oygggyyggyyggo.",
    ".owwwwgGGgwwwwo.",
    ".owwwwgoogwwwwo.",
    ".oddddgGGgddddo.",
    ".oddddddddddddo.",
    ".oGGGGGGGGGGGGo.",
    ".oooooooooooooo.",
    "................",
)


def chest(state: str) -> Canvas:
    """One chest frame: ``closed``, ``open``, ``glow`` (white halo overlay) or ``wobble``."""
    rows = CHEST_OPEN if state == "open" else CHEST_CLOSED
    c = Canvas.from_map(rows, CHEST_PALETTE, T, T)
    if state == "glow":
        body = c.map_pixels(lambda _p: WHITE)
        inner = body.outline(WHITE, diagonal=True)
        outer = inner.outline(WHITE, diagonal=True)
        halo = Canvas(T, T)
        for y in range(T):
            for x in range(T):
                if body.get(x, y)[3]:
                    continue
                if inner.get(x, y)[3]:
                    halo.set(x, y, (255, 255, 255, 200))
                elif outer.get(x, y)[3]:
                    halo.set(x, y, (255, 255, 255, 90))
        return halo
    if state == "wobble":
        return c.scaled(1.12, 0.9)
    return c


# ------------------------------------------------------------------------ biome props
# The visual grammar (see assets/tiles/README.md "Reading the world at a glance"):
# clutter is an *object standing on the floor* - it never paints the tile's border ring, it
# carries a contact shadow, and it is drawn in the eight-colour ramp so the theme owns its
# colour. A hazard is the floor itself (full-bleed tile + warning frame) and a reward is a
# free-standing box in its own gold. Those three answers to "how much of the tile do I cover,
# and do I have a frame?" are what separates them at a glance on any theme, in any palette.
#
# Inside the clutter class there is one more rule, and it is the one a player bumps into:
# an *upright* object (barrel, crate, coffin, shelf, anvil...) is solid and breakable, and
# anything *lying on the floor* (bones, rubble, a snowdrift, a glowing slag puddle) is
# walk-over decoration. The sprite carries the rule - `SOLID` below is authored per kind,
# `_assert_recipe` refuses a drawing that contradicts it, and `prop_solid.json` hands the
# same table to the gdUnit tests, which read the shipped PNG back against `Prop.SOLID`.
PROP_PALETTE: dict[str, Color] = dict(RAMP)
## Widest a prop may reach: the border ring (x/y 0 and 15) stays empty so the silhouette of a
## piece of clutter can never be mistaken for a hazard tile, which always fills it.
PROP_MARGIN = 1
## The row a solid prop's contact shadow sits on: the last row inside the border ring.
SHADOW_ROW = T - 2
## Fewest ink pixels on `SHADOW_ROW` that count as a contact shadow.
SHADOW_MIN = 4
## The row that splits the two recipes: a flat prop starts on or below it (it lies low), a
## solid one starts on or above it (it stands tall). The contact shadow is the decisive tell;
## this keeps the silhouettes honest as well.
FLAT_TOP = 4
## The atlas row a solid prop's broken frame lives on (`Prop.DEBRIS_ROW`).
DEBRIS_ROW = 1
## Kinds per biome (`Prop.KIND_COUNT`): the four shared kinds first, then five of the biome's own.
KIND_COUNT = 9
## Fewest ink pixels a solid prop wears: the outline is the second half of "this is an object".
INK_MIN = 12

## Per kind: does the player walk into it (True) or over it (False)? Mirrors `Prop.SOLID` and
## `prop_solid` in `data/rooms/rooms_content.tres`; `tests/unit/rooms/prop_test.gd` compares
## all three with what the PNG says.
SOLID: dict[str, bool] = {
    # upright, solid, breakable: ink outline + contact shadow
    "anvil": True, "barrel": True, "bookshelf": True, "boulder": True, "brazier": True,
    "candle": True, "cart": True, "coffin": True, "crate": True, "crystal": True,
    "desk": True, "floater": True, "globe": True, "gravestone": True, "ice_block": True,
    "lantern": True, "lectern": True, "monolith": True, "orb": True, "sack": True,
    "snowman": True, "urn": True,
    # flat on the floor, walk-over: no ink, no shadow
    "bones": False, "books": False, "chain": False, "rift": False, "rubble": False,
    "slag": False, "snow": False,
}


def _prop_map(rows: tuple[str, ...]) -> Canvas:
    """A 16x16 prop from a pixel map, checked against the clutter grammar."""
    if len(rows) != T:
        raise ValueError(f"prop map has {len(rows)} rows, expected {T}")
    for y, row in enumerate(rows):
        if len(row) != T:
            raise ValueError(f"prop map row {y} is {len(row)} chars, expected {T}")
    return Canvas.from_map(rows, PROP_PALETTE, T, T)


def _assert_inset(c: Canvas, name: str) -> None:
    """Clutter never touches the tile border: that ring belongs to hazards."""
    for i in range(T):
        edges = (c.get(i, 0), c.get(i, T - 1), c.get(0, i), c.get(T - 1, i))
        if any(p[3] for p in edges):
            raise ValueError(f"prop {name!r} paints the tile border ring at {i}")


def shadow_width(c: Canvas) -> int:
    """Ink pixels on the contact-shadow row: the tell that a prop stands on a base."""
    return sum(1 for x in range(T) if c.get(x, SHADOW_ROW) == O)


def ink_count(c: Canvas) -> int:
    """Ink pixels anywhere in the cell: the outline of a solid, and nothing at all on a flat."""
    return sum(1 for p in c.pixels if p == O)


def top_row(c: Canvas) -> int:
    """First row holding a drawn pixel, or T when the cell is empty."""
    for y in range(T):
        if any(c.get(x, y)[3] for x in range(T)):
            return y
    return T


def _assert_recipe(c: Canvas, name: str, solid: bool) -> None:
    """The drawing has to say what the data says.

    A solid stands tall, wears an ink outline and a base shadow; a flat lies low and carries no
    ink at all - the one tone every solid has is the one no flat is allowed, so the two classes
    cannot be confused even in greyscale.
    """
    width = shadow_width(c)
    top = top_row(c)
    ink = ink_count(c)
    if solid:
        if width < SHADOW_MIN:
            raise ValueError(f"solid prop {name!r} has no contact shadow on row {SHADOW_ROW}")
        if top > FLAT_TOP:
            raise ValueError(f"solid prop {name!r} starts at row {top}: it should stand tall")
        if ink < INK_MIN:
            raise ValueError(f"solid prop {name!r} has {ink} ink pixels: it needs an outline")
    else:
        if width or any(c.get(x, SHADOW_ROW)[3] for x in range(T)):
            raise ValueError(f"flat prop {name!r} paints row {SHADOW_ROW}: that is a base")
        if top < FLAT_TOP:
            raise ValueError(f"flat prop {name!r} rises to row {top}: it should lie low")
        if ink:
            raise ValueError(f"flat prop {name!r} wears ink: only a solid has an outline")


def _from(rows: tuple[str, ...]) -> Drawer:
    """Turns a pixel map into a drawer (the table stores drawers, not canvases)."""

    def draw(c: Canvas) -> None:
        c.blit(_prop_map(rows), 0, 0)

    return draw


def debris(intact: Canvas, name: str) -> Canvas:
    """The broken frame of a solid prop: four chunks of its own body strewn across the floor.

    Each chunk is a crop of the intact drawing - so a smashed barrel leaves barrel-coloured
    staves and a smashed shelf leaves book spines - set low in the cell, rimmed in the dark
    tone, with a few loose dark specks. It follows the *flat* recipe in full (nothing above
    `FLAT_TOP`, no contact shadow, and no ink at all), which is exactly the state the prop is
    in once broken: walk-over, and drawn like everything else the player walks over.
    """
    rng = rng_for(f"debris-{name}")
    body = [
        (x, y) for y in range(T) for x in range(T)
        if intact.get(x, y)[3] and intact.get(x, y) != O and y < SHADOW_ROW - 1
    ]
    out = Canvas(T, T)
    # Four chunk slots across the lower half of the tile, jittered so no two kinds tile alike.
    slots = ((2, 7), (8, 6), (4, 11), (10, 10))
    for sx, sy in slots:
        w, h = rng.randrange(2, 4), rng.randrange(2, 4)
        bx, by = rng.choice(body)
        bx, by = max(1, min(T - 1 - w, bx - w // 2)), max(1, min(T - 1 - h, by - h // 2))
        dx, dy = sx + rng.randrange(0, 2), sy + rng.randrange(0, 2)
        for yy in range(h):
            for xx in range(w):
                px = intact.get(bx + xx, by + yy)
                if px[3] and px != O:
                    out.set(dx + xx, dy + yy, px)
    rimmed = out.map_pixels(lambda px: D if px == O else px).outline(D)
    for _ in range(3):  # loose specks
        rimmed.set(rng.randrange(2, T - 2), rng.randrange(FLAT_TOP + 2, SHADOW_ROW - 1), D)
    # Clip to the flat recipe: nothing on the border ring, nothing above FLAT_TOP, no row 14.
    for y in range(T):
        for x in range(T):
            if x in (0, T - 1) or y < FLAT_TOP or y >= SHADOW_ROW:
                rimmed.set(x, y, TRANSPARENT)
    _assert_recipe(rimmed, f"{name} debris", False)
    return rimmed


def _prop(biome: str, index: int) -> Canvas:
    c = Canvas(T, T)
    name, draw = PROP_TABLE[biome][index]
    draw(c)
    _assert_inset(c, f"{biome}:{name}")
    _assert_recipe(c, f"{biome}:{name}", SOLID[name])
    return c


def _debris(biome: str, index: int, intact: Canvas) -> Canvas:
    """Row 1 of the atlas: a debris frame for a solid kind, an empty cell for a flat one."""
    name, _ = PROP_TABLE[biome][index]
    if not SOLID[name]:
        return Canvas(T, T)
    cell = debris(intact, f"{biome}:{name}")
    _assert_inset(cell, f"{biome}:{name} debris")
    return cell


## The four kinds every biome shares, in the atlas' first four columns.
SHARED: list[tuple[str, Drawer]] = [
    ("barrel", _from(BARREL)), ("crate", _from(CRATE)), ("sack", _from(SACK)),
    ("rubble", _from(RUBBLE)),
]

PROP_TABLE: dict[str, list[tuple[str, Drawer]]] = {
    "crypt": SHARED + [
        ("coffin", _from(COFFIN)), ("gravestone", _from(GRAVESTONE)), ("urn", _from(URN)),
        ("candle", _from(CANDLE)), ("bones", _from(BONES)),
    ],
    "forge": SHARED + [
        ("anvil", _from(ANVIL)), ("cart", _from(CART)), ("brazier", _from(BRAZIER)),
        ("chain", _from(CHAIN)), ("slag", _from(SLAG)),
    ],
    "frost": SHARED + [
        ("ice_block", _from(ICE_BLOCK)), ("lantern", _from(LANTERN)),
        ("snowman", _from(SNOWMAN)), ("boulder", _from(BOULDER)), ("snow", _from(SNOW)),
    ],
    "library": SHARED + [
        ("bookshelf", _from(BOOKSHELF)), ("desk", _from(DESK)), ("lectern", _from(LECTERN)),
        ("globe", _from(GLOBE)), ("books", _from(BOOKS)),
    ],
    "void": SHARED + [
        ("crystal", _from(CRYSTAL)), ("monolith", _from(MONOLITH)), ("floater", _from(FLOATER)),
        ("orb", _from(ORB)), ("rift", _from(RIFT)),
    ],
}

## Column order per biome. MUST equal `Prop.KINDS` / `Biome.prop_kinds` (data/biomes/*.tres):
## `Prop.setup()` picks the sprite by kind index while hp/STURDY/SOLID come from the kind name.
## `prop_kinds.json` next to this file pins the order for the gdUnit test.
PROP_NAMES: dict[str, list[str]] = {b: [n for n, _ in rows] for b, rows in PROP_TABLE.items()}
PROP_DRAWERS = {b: [fn for _, fn in rows] for b, rows in PROP_TABLE.items()}
for _biome, _names in PROP_NAMES.items():
    if len(_names) != KIND_COUNT:
        raise ValueError(f"{_biome} lists {len(_names)} props, expected {KIND_COUNT}")
    for _name in _names:
        if _name not in SOLID:
            raise ValueError(f"{_biome} prop {_name!r} has no SOLID entry")


# ---------------------------------------------------------------------------- pickups
STAT_ORB_COLORS: dict[str, Color] = {
    "vitality": hex_color("#e04848"),
    "might": hex_color("#f08030"),
    "precision": hex_color("#f2d94a"),
    "arcana": hex_color("#9a5ae8"),
    "swiftness": hex_color("#40d070"),
    "fortune": hex_color("#40d0e0"),
}


def coin(frame: int) -> Canvas:
    c = Canvas(T, T)
    widths = [5, 3, 1, 3]
    w = widths[frame]
    c.ellipse(8, 8, w, 5, OUTLINE)
    c.ellipse(8, 8, w - 1 if w > 1 else 0.4, 4, GOLD)
    if w >= 3:
        c.vline(8 - (w - 2), 6, 10, GOLD_D if frame == 3 else GOLD_L)
    if w == 5:
        c.rect(7, 6, 2, 4, GOLD_D)
        c.set(7, 5, GOLD_L)
    return c


def heart() -> Canvas:
    c = Canvas(T, T)
    red = hex_color("#e83048")
    c.circle(5.5, 6, 2.5, red)
    c.circle(10.5, 6, 2.5, red)
    c.rect(3, 6, 10, 3, red)
    for i in range(4):
        c.hline(4 + i, 11 - i, 9 + i, red)
    out = c.outline(OUTLINE)
    out.set(5, 5, hex_color("#ff90a0"))
    out.set(4, 6, hex_color("#ff90a0"))
    return out


def stat_orb(color: Color) -> Canvas:
    c = Canvas(T, T)
    c.circle(8, 8, 4, OUTLINE)
    c.circle(8, 8, 3, color)
    c.circle(8, 8, 1.4, shade(color, 1.5))
    c.set(6, 6, WHITE)
    c.set(10, 11, shade(color, 0.6))
    c.set(8, 3, shade(color, 1.4))
    c.set(3, 8, shade(color, 1.4))
    return c


def pickups_sheet() -> Sheet:
    s = Sheet(T, T, 16, 1)
    s.put_row(0, [coin(i) for i in range(4)])
    s.put(4, 0, heart())
    for i, col in enumerate(STAT_ORB_COLORS.values()):
        s.put(5 + i, 0, stat_orb(col))
    return s


# ------------------------------------------------------------------------- projectiles
PROJECTILES = (
    "arrow", "bolt", "pin", "tome", "fireball", "ice_shard", "spark", "knife",
    "confetti", "laser_dot", "gold_coin_shot", "caltrop", "honk_ring", "book", "wire", "glitch",
)


def projectile(name: str) -> Canvas:
    c = Canvas(T, T)
    if name == "arrow":
        c.hline(2, 12, 8, WOOD)
        c.rect(12, 7, 3, 3, STEEL)
        c.set(15, 8, STEEL)
        c.rect(1, 6, 3, 2, hex_color("#e04040"))
        c.rect(1, 9, 3, 2, hex_color("#e04040"))
        return c.outline()
    if name == "bolt":
        c.ellipse(8, 8, 4, 2.5, hex_color("#8a5ae8"))
        c.ellipse(7, 8, 2, 1, hex_color("#e0d0ff"))
        c.set(3, 7, hex_color("#c0a0ff"))
        c.set(2, 9, hex_color("#c0a0ff"))
        return c.outline()
    if name == "pin":
        c.rect(6, 2, 4, 3, WHITE)
        c.rect(7, 5, 2, 3, WHITE)
        c.rect(5, 8, 6, 6, WHITE)
        c.hline(5, 10, 10, hex_color("#e83030"))
        c.hline(5, 10, 12, hex_color("#e83030"))
        c.set(6, 3, hex_color("#e83030"))
        return c.outline()
    if name == "tome":
        c.rect(3, 4, 10, 9, hex_color("#8b2c2c"))
        c.rect(4, 5, 8, 7, hex_color("#e8dcc0"))
        c.rect(3, 4, 2, 9, hex_color("#5a1c1c"))
        c.hline(6, 10, 7, hex_color("#8a8a8a"))
        c.hline(6, 10, 9, hex_color("#8a8a8a"))
        return c.outline()
    if name == "fireball":
        c.circle(9, 8, 4, hex_color("#ff6020"))
        c.circle(10, 8, 2.2, hex_color("#ffd040"))
        c.set(11, 8, WHITE)
        c.rect(2, 7, 4, 3, hex_color("#ff6020"))
        c.rect(1, 8, 2, 1, hex_color("#ffa040"))
        c.set(4, 5, hex_color("#ff8030"))
        c.set(4, 11, hex_color("#ff8030"))
        return c.outline(hex_color("#7a1c00"))
    if name == "ice_shard":
        c.line(2, 12, 13, 4, hex_color("#80e8ff"))
        c.line(2, 11, 12, 3, hex_color("#d0f8ff"))
        c.line(3, 13, 14, 5, hex_color("#3090d0"))
        c.set(13, 3, WHITE)
        return c.outline(hex_color("#104060"))
    if name == "spark":
        y = hex_color("#ffe040")
        c.vline(8, 3, 13, y)
        c.hline(3, 13, 8, y)
        c.line(5, 5, 11, 11, hex_color("#fff8c0"))
        c.line(11, 5, 5, 11, hex_color("#fff8c0"))
        c.circle(8, 8, 2, WHITE)
        return c
    if name == "knife":
        c.line(3, 12, 11, 4, STEEL)
        c.line(4, 12, 12, 4, hex_color("#f0f4ff"))
        c.line(5, 13, 12, 6, STEEL_D)
        c.rect(2, 12, 3, 3, WOOD_D)
        c.set(12, 3, WHITE)
        return c.outline()
    if name == "confetti":
        rng = rng_for("confetti")
        cols = [hex_color(h) for h in ("#e83030", "#f2d94a", "#40d040", "#3080ff", "#ff3fa8", "#40e0d0")]
        for i in range(9):
            x, y = rng.randrange(2, 14), rng.randrange(2, 14)
            c.rect(x, y, 2 if i % 2 else 1, 1 if i % 2 else 2, cols[i % len(cols)])
        return c
    if name == "laser_dot":
        c.circle(8, 8, 2.5, hex_color("#ff2020"))
        c.circle(8, 8, 1.2, hex_color("#ffb0b0"))
        c.set(8, 4, hex_color("#ff2020", 160))
        c.set(8, 12, hex_color("#ff2020", 160))
        c.set(4, 8, hex_color("#ff2020", 160))
        c.set(12, 8, hex_color("#ff2020", 160))
        return c
    if name == "gold_coin_shot":
        c = coin(0)
        c.line(1, 10, 3, 8, GOLD_L)
        c.line(1, 6, 3, 8, GOLD_L)
        return c
    if name == "caltrop":
        d = STEEL_D
        c.line(8, 9, 8, 2, d)
        c.line(8, 9, 3, 13, d)
        c.line(8, 9, 13, 13, d)
        c.line(8, 9, 12, 6, STEEL)
        c.set(8, 2, WHITE)
        c.set(13, 13, WHITE)
        return c.outline()
    if name == "honk_ring":
        c.circle(8, 8, 6, hex_color("#f2d94a"), filled=False)
        c.circle(8, 8, 3.5, hex_color("#fff0a0"), filled=False)
        return c.outline(hex_color("#8a6a10"))
    if name == "book":
        c.rect(2, 5, 12, 7, hex_color("#2c4a8b"))
        c.rect(3, 6, 10, 5, hex_color("#e8dcc0"))
        c.vline(8, 6, 10, hex_color("#8a8a8a"))
        c.rect(2, 5, 12, 1, hex_color("#1c2c5a"))
        c.set(7, 4, WHITE)
        c.set(9, 12, WHITE)
        return c.outline()
    if name == "wire":
        c.line(1, 10, 5, 6, hex_color("#40e0d0"))
        c.line(5, 6, 9, 10, hex_color("#40e0d0"))
        c.line(9, 10, 14, 5, hex_color("#40e0d0"))
        c.set(14, 4, hex_color("#ff3fa8"))
        c.set(15, 5, hex_color("#ff3fa8"))
        return c.outline(hex_color("#104040"))
    # glitch
    rng = rng_for("glitch-proj")
    for _ in range(10):
        c.rect(rng.randrange(2, 13), rng.randrange(3, 13), rng.randrange(1, 4), 1,
               rng.choice([hex_color("#ff3fa8"), hex_color("#40e0d0"), WHITE, hex_color("#6a3fbf")]))
    return c


def projectiles_sheet() -> Sheet:
    s = Sheet(T, T, 16, 1)
    s.put_row(0, [projectile(n) for n in PROJECTILES])
    return s


# ------------------------------------------------------------------------------- traps
TRAP_FRAMES = {
    "spike_floor": 4,
    "arrow_wall": 3,
    "fire_vent": 4,
    "pressure_plate": 2,
    "ice_slide": 1,
    "laser_grid": 3,
    "ricer_trap": 3,
    "kernel_spike": 3,
    "pit": 3,
    "mimic_chest": 3,
}
PLATE = hex_color("#6c6c74")
PLATE_D = hex_color("#44444c")
PLATE_L = hex_color("#9a9aa4")
## The hazard warning colours. Traps keep their own colours through the theme swap (docs
## §10), so this pair is the one thing on the floor whose meaning never moves with the
## desktop: amber means "this tile can hurt you".
WARN = hex_color("#ffb01c")
WARN_D = hex_color("#8a5a00")
## The same bracket in a cold pair for the hazards that move you but do not damage you
## (ice, pressure plates), so the shape still says "hazard" while the colour says "not a hit".
CHILL = hex_color("#7fd8ff")
CHILL_D = hex_color("#2a6a94")
## Deep variants of each pair, for a hazard whose own fill is bright.
##
## A warning frame nobody can see is not a warning. The ice slide is painted in #a8e8ff, and the
## bright cold pair above lands on it at a contrast ratio of 1.19 - the frame the last pass
## added to teach the player "this tile is a hazard" was invisible on the one hazard whose
## colour is closest to it. Hue carries the meaning (amber hurts, blue moves you) and value
## carries the visibility, so each meaning gets a bright and a deep pair and
## `hazard_frame` picks by measuring the tile it is about to stamp.
WARN_DEEP = hex_color("#9c5a00")
CHILL_DEEP = hex_color("#15567e")
## Contrast a stamped bracket keeps against the fill it is stamped on: the corner pixels, then
## the tail and edge ticks that finish the border. The tail is allowed less because it is the
## bracket's own shading, but not so little that a mid-grey plate swallows the whole border and
## leaves four lit corners floating on it.
FRAME_MIN_CONTRAST = 2.4
FRAME_TAIL_CONTRAST = 1.8
## Shades of the bracket colour the tail is tried at, darkest first: the darkest one that still
## stands off the fill wins, so the bracket keeps as much internal shape as the tile allows.
FRAME_TAIL_SHADES = (0.55, 0.65, 0.75, 0.85)
## Hazards that wear no warning frame, and why. Both are *meant* to be mistaken for something
## else - that is their whole mechanic (docs §9 "Mimic chest", §7 the Ricer's dropped props) -
## so framing them would delete the trap rather than make it readable.
DISGUISED_TRAPS = ("mimic_chest", "ricer_trap")


def frame_fill(c: Canvas) -> Color:
    """The tile colour a warning frame will be stamped over: the modal interior pixel."""
    counts: dict[Color, int] = {}
    for y in range(2, T - 2):
        for x in range(2, T - 2):
            px = c.get(x, y)
            if px[3] == 0:
                continue
            counts[px] = counts.get(px, 0) + 1
    if not counts:
        return OUTLINE
    return max(counts.items(), key=lambda kv: kv[1])[0]


def frame_pair(damaging: bool, fill: Color) -> tuple[Color, Color]:
    """The bright or the deep half of a warning pair, whichever stands off `fill`.

    Both halves carry the same hue, so the meaning (amber hurts, blue only moves you) never
    changes with the tile; only the value does, which is what makes the bracket visible on a
    dark spike plate and on bright ice alike.
    """
    bright = WARN if damaging else CHILL
    deep = WARN_DEEP if damaging else CHILL_DEEP
    hi = bright
    if contrast_ratio(bright, fill) < FRAME_MIN_CONTRAST and contrast_ratio(
        deep, fill
    ) > contrast_ratio(bright, fill):
        hi = deep
    lo = shade(hi, FRAME_TAIL_SHADES[-1])
    for amount in FRAME_TAIL_SHADES:
        candidate = shade(hi, amount)
        if contrast_ratio(candidate, fill) >= FRAME_TAIL_CONTRAST:
            lo = candidate
            break
    return hi, lo


def hazard_frame(c: Canvas, damaging: bool = True) -> None:
    """Stamps the shared warning border that marks a tile as a hazard.

    The grammar (`assets/tiles/README.md`, "Reading the world at a glance"): a hazard *is*
    the floor, so it fills the tile edge to edge and wears corner brackets pointing inward; a
    prop never touches the border ring at all, and a chest is a free-standing box in its own
    gold. Silhouette carries the meaning, so the three stay apart in every theme, light or
    dark, and in greyscale.

    The bracket colour is chosen against the tile underneath (`frame_pair`), because a frame
    that matches its own fill is a frame the player never sees.
    """
    hi, lo = frame_pair(damaging, frame_fill(c))
    c.rect(0, 0, T, T, OUTLINE, filled=False)
    for cx, cy, sx, sy in ((1, 1, 1, 1), (14, 1, -1, 1), (1, 14, 1, -1), (14, 14, -1, -1)):
        c.set(cx, cy, hi)
        for i in (1, 2):
            c.set(cx + sx * i, cy, hi if i == 1 else lo)
            c.set(cx, cy + sy * i, hi if i == 1 else lo)
    for x, y, dx, dy in ((7, 1, 1, 0), (7, 14, 1, 0), (1, 7, 0, 1), (14, 7, 0, 1)):
        c.set(x, y, lo)
        c.set(x + dx, y + dy, lo)


def _base_plate(c: Canvas, holes: bool = True) -> None:
    c.rect(0, 0, T, T, PLATE)
    c.hline(1, 14, 1, PLATE_L)
    c.vline(1, 1, 14, PLATE_L)
    c.hline(1, 14, 14, PLATE_D)
    c.vline(14, 2, 14, PLATE_D)
    if holes:
        for x in (4, 8, 12):
            for y in (4, 8, 12):
                c.rect(x - 1, y - 1, 2, 2, PLATE_D)
                c.set(x - 1, y - 1, OUTLINE)


def _spike(c: Canvas, x: int, base_y: int, height: int, light: Color, mid: Color, dark: Color) -> None:
    """A triangular spike: 3 px base tapering to a 1 px lit tip."""
    for i in range(height):
        y = base_y - i
        wide = i < height - 2
        c.set(x, y, mid)
        if wide:
            c.set(x - 1, y, dark)
            c.set(x + 1, y, dark)
    c.set(x, base_y - height + 1, light)
    c.set(x, base_y - height, OUTLINE)


def trap_frame(kind: str, frame: int) -> Canvas:
    """One frame of a hazard strip. Every kind but the two disguises wears `hazard_frame`."""
    c = _trap_art(kind, frame)
    if kind not in DISGUISED_TRAPS:
        hazard_frame(c, damaging=kind not in ("ice_slide", "pressure_plate"))
    return c


def _trap_art(kind: str, frame: int) -> Canvas:
    c = Canvas(T, T)
    if kind == "spike_floor":
        _base_plate(c)
        if frame == 1:
            c.rect(1, 1, 14, 14, PLATE_D)
            for x in (4, 8, 12):
                for y in (4, 8, 12):
                    c.rect(x - 1, y - 1, 2, 2, OUTLINE)
        elif frame >= 2:
            h = 5 if frame == 2 else 3
            for y, xs in ((8, (5, 11)), (14, (2, 8, 14))):
                for x in xs:
                    _spike(c, x, y, h, WHITE, STEEL, STEEL_D)
        return c
    if kind == "arrow_wall":
        c.rect(0, 0, T, T, STONE_D)
        c.rect(4, 5, 8, 6, OUTLINE)
        c.rect(5, 6, 6, 4, hex_color("#14141c"))
        if frame == 1:
            c.rect(6, 7, 4, 2, hex_color("#ff9030"))
        if frame == 2:
            c.rect(6, 7, 4, 2, hex_color("#ffe060"))
            c.blit(projectile("arrow").shift(4, 0), 0, 0)
        return c
    if kind == "fire_vent":
        _base_plate(c, holes=False)
        c.circle(8, 8, 4, OUTLINE)
        c.circle(8, 8, 3, PLATE_D)
        for y in (6, 8, 10):
            c.hline(6, 9, y, hex_color("#24242c"))
        if frame == 1:
            c.circle(8, 8, 2, hex_color("#c0c0c0", 160))
            c.set(7, 4, hex_color("#e0e0e0", 160))
        elif frame >= 2:
            hgt = 9 if frame == 2 else 12
            c.rect(5, 12 - hgt + 3, 6, hgt - 3, hex_color("#ff6020"))
            c.rect(6, 12 - hgt + 4, 4, hgt - 5, hex_color("#ffb030"))
            c.rect(7, 12 - hgt + 6, 2, hgt - 8, hex_color("#fff0a0"))
            c.set(4, 9, hex_color("#ff6020"))
            c.set(11, 8, hex_color("#ff6020"))
            c.set(8, 12 - hgt + 2, hex_color("#ff6020"))
        return c
    if kind == "pressure_plate":
        c.rect(0, 0, T, T, PLATE_D)
        if frame == 0:
            c.rect(3, 3, 10, 10, PLATE_L)
            c.rect(4, 4, 8, 8, PLATE)
            c.rect(3, 3, 10, 10, OUTLINE, filled=False)
            c.hline(6, 9, 6, PLATE_L)
            c.hline(6, 9, 9, PLATE_L)
        else:
            c.rect(4, 5, 8, 8, PLATE)
            c.rect(5, 6, 6, 6, PLATE_D)
            c.rect(4, 5, 8, 8, OUTLINE, filled=False)
        return c
    if kind == "ice_slide":
        c.rect(0, 0, T, T, hex_color("#a8e8ff"))
        c.dither(1, 1, 14, 14, hex_color("#a8e8ff"), hex_color("#c8f4ff"))
        c.line(3, 4, 7, 8, hex_color("#60b0e0"))
        c.line(7, 8, 12, 6, hex_color("#60b0e0"))
        c.line(9, 11, 13, 13, hex_color("#60b0e0"))
        c.set(5, 11, WHITE)
        c.set(11, 4, WHITE)
        return c
    if kind == "laser_grid":
        c.rect(0, 0, T, T, hex_color("#1a1a22"))
        for x in (2, 13):
            c.rect(x - 1, 5, 3, 6, STEEL_D)
            c.rect(x - 1, 5, 3, 6, OUTLINE, filled=False)
            c.set(x, 8, hex_color("#ff2020") if frame else hex_color("#602020"))
        if frame == 1:
            c.hline(3, 12, 8, hex_color("#ff2020", 120))
        elif frame == 2:
            c.hline(3, 12, 8, hex_color("#ff2020"))
            c.hline(3, 12, 7, hex_color("#ff2020", 90))
            c.hline(3, 12, 9, hex_color("#ff2020", 90))
        return c
    if kind == "ricer_trap":
        # A cute "decorative" plant pot that reveals wires and a blade: deliberately wears no
        # warning frame, because being mistaken for clutter is the Ricer's whole mechanic.
        c.rect(5, 9, 6, 5, hex_color("#c05a2a"))
        c.rect(5, 9, 6, 5, OUTLINE, filled=False)
        c.hline(6, 9, 10, hex_color("#e0804a"))
        if frame == 0:
            c.rect(6, 4, 4, 5, hex_color("#40c050"))
            c.set(5, 5, hex_color("#40c050"))
            c.set(10, 6, hex_color("#40c050"))
            c.set(8, 3, hex_color("#ff3fa8"))
            return c.outline()
        c.line(4, 8, 2, 4, hex_color("#40e0d0"))
        c.line(11, 8, 13, 3, hex_color("#40e0d0"))
        c.set(2, 3, hex_color("#ff3fa8"))
        if frame == 2:
            c.rect(7, 1, 2, 8, STEEL)
            c.set(7, 1, WHITE)
        else:
            c.rect(7, 5, 2, 4, STEEL)
        return c.outline()
    if kind == "pit":
        # crumbling floor -> cracked -> open hole with a lit rim
        rim_l, rim_d, deep = PLATE_L, PLATE_D, hex_color("#0a0a10")
        c.rect(0, 0, T, T, PLATE)
        if frame == 0:
            c.hline(2, 13, 2, rim_l)
            for x0, y0, x1, y1 in ((3, 5, 7, 4), (9, 7, 12, 9), (5, 11, 8, 12)):
                c.line(x0, y0, x1, y1, rim_d)
            return c
        if frame == 1:
            for x1, y1 in ((2, 2), (13, 3), (2, 13), (13, 12), (8, 1), (8, 14)):
                c.line(8, 8, x1, y1, rim_d)  # cracks radiating out of the sagging floor
            c.ellipse(8, 8, 4.5, 3.6, hex_color("#3a3a44"))
            c.ellipse(8, 8, 3.6, 2.8, hex_color("#22222c"))
            c.hline(5, 11, 5, rim_d)
            return c
        c.ellipse(8, 8, 6.0, 5.2, OUTLINE)
        c.ellipse(8, 8, 5.0, 4.2, deep)
        c.ellipse(8, 7, 4.5, 3.4, hex_color("#141420"))
        for x in range(4, 13, 2):
            c.set(x, 4 if x % 4 else 3, rim_l)  # lit lip
        c.hline(5, 10, 12, hex_color("#1e1e28"))
        return c
    if kind == "mimic_chest":
        # A chest that grows eyes, then a mouth full of teeth. No warning frame: looking
        # exactly like loot until it bites is the mechanic (docs §9).
        c.blit(chest("closed"), 0, 0)
        if frame == 0:
            return c
        eye = hex_color("#ffe040")
        c.set(5, 6, eye)
        c.set(10, 6, eye)
        c.set(5, 5, OUTLINE)
        c.set(10, 5, OUTLINE)
        if frame == 1:
            return c
        mouth, gum = WHITE, hex_color("#c02840")
        c.rect(3, 8, 10, 4, gum)
        c.rect(3, 8, 10, 4, OUTLINE, filled=False)
        for x in range(4, 13, 2):
            c.set(x, 9, mouth)
            c.set(x + 1, 10, mouth)
        c.set(2, 7, hex_color("#ff5050"))
        c.set(13, 7, hex_color("#ff5050"))
        return c
    # kernel_spike: dark tile that flashes danger then erupts red spikes
    c.rect(0, 0, T, T, hex_color("#14141c"))
    if frame == 0:
        # dormant: a faint panic rune so the tile is still readable on a dark floor
        c.rect(4, 4, 8, 8, hex_color("#3a1c22"), filled=False)
        c.hline(6, 9, 8, hex_color("#5a2430"))
        c.vline(8, 6, 9, hex_color("#5a2430"))
        for x in (3, 12):
            c.set(x, 3, hex_color("#5a2430"))
            c.set(x, 12, hex_color("#5a2430"))
    if frame == 1:
        c.rect(2, 2, 12, 12, hex_color("#a01c1c"))
        c.rect(2, 2, 12, 12, hex_color("#ff3030"), filled=False)
    elif frame == 2:
        for y, xs in ((8, (5, 11)), (13, (3, 8, 13))):
            for x in xs:
                _spike(c, x, y, 5, WHITE, hex_color("#ff3030"), hex_color("#a01c1c"))
    return c


# --------------------------------------------------------------------------------- fx
def particle(kind: str) -> Canvas:
    c = Canvas(T, T)
    if kind == "dust":
        c.circle(8, 8, 3, hex_color("#e0d8c8", 200))
        c.circle(7, 7, 1.5, hex_color("#f8f4ec", 220))
        c.set(11, 6, hex_color("#e0d8c8", 160))
        c.set(5, 11, hex_color("#e0d8c8", 160))
    elif kind == "spark":
        c.vline(8, 4, 12, hex_color("#fff0a0"))
        c.hline(4, 12, 8, hex_color("#fff0a0"))
        c.rect(7, 7, 2, 2, WHITE)
    elif kind == "confetti":
        c.rect(5, 5, 2, 3, hex_color("#e83030"))
        c.rect(9, 4, 3, 2, hex_color("#40d040"))
        c.rect(7, 9, 2, 2, hex_color("#3080ff"))
        c.rect(10, 9, 2, 3, hex_color("#f2d94a"))
        c.rect(4, 10, 2, 2, hex_color("#ff3fa8"))
    else:  # smoke
        c.circle(8, 9, 4, hex_color("#808088", 170))
        c.circle(6, 7, 2.5, hex_color("#a0a0a8", 170))
        c.circle(10, 6, 2, hex_color("#9090a0", 170))
    return c


def particles_sheet() -> Sheet:
    s = Sheet(T, T, 4, 1)
    s.put_row(0, [particle(k) for k in ("dust", "spark", "confetti", "smoke")])
    return s


# ------------------------------------------------------------------------------ driver
def arrow_sprite() -> Canvas:
    """The 8x4 arrow the arrow_wall trap fires (points right)."""
    c = Canvas(8, 4)
    shaft, feather, head = hex_color("#b08040"), hex_color("#e8e0d0"), STEEL
    c.hline(1, 5, 2, shaft)
    c.set(1, 1, feather)
    c.set(0, 2, feather)
    c.set(1, 3, feather)
    c.set(6, 2, head)
    c.set(7, 2, WHITE)
    c.set(6, 1, STEEL_D)
    c.set(6, 3, STEEL_D)
    return c


def review_sheet(root: pathlib.Path, scale: int = 4) -> pathlib.Path:
    """`tests/out/art_props_all.png`: every biome's row, intact over debris, named, at `scale`x.

    This is the picture the five rules in `prop_maps.py` are judged on. It is drawn from the
    same canvases the atlases are, so what it shows is what ships.
    """
    from PIL import Image, ImageDraw  # noqa: PLC0415 - review only, never in the asset path

    cell = T * scale
    label_h = 12
    width = KIND_COUNT * (cell + 4) + 4
    height = len(BIOMES) * (2 * cell + label_h + 8) + 4
    img = Image.new("RGBA", (width, height), (54, 48, 80, 255))
    draw = ImageDraw.Draw(img)
    for row, biome in enumerate(BIOMES):
        y0 = 4 + row * (2 * cell + label_h + 8)
        for col in range(KIND_COUNT):
            name = PROP_NAMES[biome][col]
            intact = _prop(biome, col)
            broken = _debris(biome, col, intact)
            x0 = 4 + col * (cell + 4)
            for i, canvas in enumerate((intact, broken)):
                big = canvas.to_image().resize((cell, cell), Image.NEAREST)
                img.alpha_composite(big, (x0, y0 + i * cell))
            tag = name if SOLID[name] else f"{name} (flat)"
            draw.text((x0 + 1, y0 + 2 * cell), tag, fill=(255, 220, 130, 255))
    out = root / "tests" / "out" / "art_props_all.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    return out


def generate(root: pathlib.Path) -> list[pathlib.Path]:
    sprites = root / "assets" / "sprites"
    out: list[pathlib.Path] = []

    # Pin the atlas column order for the gdUnit test (tests/unit/art) so a future reshuffle
    # of PROP_TABLE cannot silently diverge from `Prop.KINDS` / `Biome.prop_kinds`.
    kinds = root / "tools" / "art" / "prop_kinds.json"
    kinds.write_text(json.dumps(PROP_NAMES, indent=2) + "\n")
    # ... and the solidity rule beside it, so the same test can hold `Prop.SOLID`, the
    # shipped `rooms_content.tres` and the PNG to one table.
    solid = root / "tools" / "art" / "prop_solid.json"
    solid.write_text(json.dumps(dict(sorted(SOLID.items())), indent=2) + "\n")

    chest_sheet = Sheet(T, T, 4, 1)
    chest_sheet.put_row(0, [chest(s) for s in ("closed", "open", "glow", "wobble")])
    p = sprites / "props" / "chest.png"
    chest_sheet.save(p)
    out.append(p)

    for biome in BIOMES:
        # Row 0: the prop as placed. Row 1 (`DEBRIS_ROW`): what a solid kind leaves behind.
        sheet = Sheet(T, T, KIND_COUNT, 2)
        intact = [_prop(biome, i) for i in range(KIND_COUNT)]
        sheet.put_row(0, intact)
        sheet.put_row(DEBRIS_ROW, [_debris(biome, i, intact[i]) for i in range(KIND_COUNT)])
        bad = {px for px in sheet.canvas.pixels if px not in RAMP.values()}
        if bad:
            raise ValueError(f"{biome} props: non-ramp colours {sorted(bad)[:4]}")
        p = sprites / "props" / f"{biome}.png"
        sheet.save(p)
        out.append(p)

    p = sprites / "pickups.png"
    pickups_sheet().save(p)
    out.append(p)
    p = sprites / "projectiles.png"
    projectiles_sheet().save(p)
    out.append(p)
    for kind, n in TRAP_FRAMES.items():
        sheet = Sheet(T, T, n, 1)
        sheet.put_row(0, [trap_frame(kind, i) for i in range(n)])
        p = sprites / "traps" / f"{kind}.png"
        sheet.save(p)
        out.append(p)
    p = sprites / "traps" / "arrow.png"
    arrow_sprite().save(p)
    out.append(p)
    p = sprites / "fx" / "particles.png"
    particles_sheet().save(p)
    out.append(p)
    return out
