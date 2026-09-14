"""Player class sprite sheets and portraits.

Each class is authored as an explicit 16x16 idle pixel map (facing right); animation rows
are derived: idle bob, run (leg pose swap + bob), class-flavoured dodge, hurt flash, death.

**No class map draws a weapon.** The weapon on screen is the one the player has equipped, drawn
on top by `WeaponSprite` at the grip anchor; a blade painted into the class art too is a second
weapon the player never chose and cannot drop, which is what the owner saw as "every character
carries two weapons". Each silhouette therefore has to read from gear that is not a weapon:
the Fighter's crested helm, pauldrons and shield, the Ranger's hood and cloak, the Wizard's
pointed hat and beard, the Oligarch's top hat and monocle. `tests/unit/player/class_art_test.gd`
fails the build when a class sheet grows a blade, a bow, a staff or a cane back.

Sheet rows: 0 idle x4, 1 run x6, 2 dodge x4, 3 hurt x2, 4 death x6  (16x16 cells, 6 cols).
"""
from __future__ import annotations

import pathlib
from dataclasses import dataclass, field

from toolkit import (
    OUTLINE,
    Canvas,
    Color,
    Sheet,
    bob_frames,
    collapse_death,
    hex_color,
    hover,
    hurt_frames,
)

T = 16
CLASSES = ("fighter", "ranger", "wizard", "oligarch")

SKIN = hex_color("#f0c8a0")
SKIN_SHADE = hex_color("#c88c64")
EYE = hex_color("#202030")
WHITE = hex_color("#ffffff")


def base_palette(**extra: Color) -> dict[str, Color]:
    pal: dict[str, Color] = {
        "o": OUTLINE,
        "s": SKIN,
        "S": SKIN_SHADE,
        "e": EYE,
        "w": WHITE,
    }
    pal.update(extra)
    return pal


# Leg poses: 3 rows (sprite rows 13..15). p = pants, b = boots, o = outline.
LEGS_IDLE = [
    "....oppoppo.....",
    "....obbobbo.....",
    "....ooooooo.....",
]
LEGS_RUN = [
    [  # 0 contact, near leg reaching forward
        "..oppo..oppo....",
        ".obbo....obbo...",
        ".oooo....oooo...",
    ],
    [  # 1 down, weight over the leading foot
        "...oppoppo......",
        "..obbo.obbo.....",
        "..oooo.oooo.....",
    ],
    [  # 2 pass, near leg tucked under the body
        "....opppo.......",
        "....obbbo.......",
        "....ooooo.......",
    ],
    [  # 3 contact, far leg leading (mirrored stride, not a copy of frame 0)
        "....oppo..oppo..",
        "...obbo....obbo.",
        "...oooo....oooo.",
    ],
    [  # 4 down on the other foot
        "......oppoppo...",
        ".....obbo.obbo..",
        ".....oooo.oooo..",
    ],
    [  # 5 pass, far leg tucked
        "......opppo.....",
        "......obbbo.....",
        "......ooooo.....",
    ],
]


@dataclass
class CharacterSpec:
    """A 13-row body map (rows 0..12) plus palette. Legs are appended from LEGS_*."""

    name: str
    palette: dict[str, Color]
    body: list[str]
    dodge: str = "roll"
    portrait_bg: Color = hex_color("#304060")
    portrait: list[str] = field(default_factory=list)

    def frame(self, legs: list[str], dy: int = 0) -> Canvas:
        rows = list(self.body) + legs
        c = Canvas.from_map(rows, self.palette, T, T)
        return c.shift(0, dy) if dy else c

    def idle(self) -> Canvas:
        return self.frame(LEGS_IDLE)


# --------------------------------------------------------------------------- pixel maps
FIGHTER = CharacterSpec(
    "fighter",
    base_palette(
        h=hex_color("#8a4b23"), H=hex_color("#5c2f14"),  # hair
        c=hex_color("#3a6fd8"), C=hex_color("#24488f"), k=hex_color("#6f9ef0"),  # surcoat
        a=hex_color("#b03030"), A=hex_color("#702020"),  # helm crest
        m=hex_color("#d8dce8"), M=hex_color("#8c92a8"),  # pauldrons / breastplate
        p=hex_color("#4a3a30"), b=hex_color("#2a221c"),  # pants / boots
        l=hex_color("#b9c4dc"), g=hex_color("#7d8aa6"),  # shield rim / face
        G=hex_color("#49536b"),  # shield shade
        d=hex_color("#b8862c"), D=hex_color("#7d5a20"),  # shield boss
    ),
    [
        "......oaao......",
        ".....oMaaMo.....",
        "....oMmaaMMo....",
        "...oMMMMMMMMo...",
        "...osssssssso...",
        "...oMesssesMo...",
        "...oMSsssSSMo...",
        ".ooooSssssSo....",
        "olllgoommmmo....",
        "olddgoMmkkmMo...",
        "ogdDGoMcCcMo....",
        ".oGGoocCCCCo....",
        "..oo..oCCCCo....",
    ],
    dodge="roll",
    portrait_bg=hex_color("#2b4a8a"),
)

RANGER = CharacterSpec(
    "ranger",
    base_palette(
        h=hex_color("#3f8a3f"), H=hex_color("#265a26"), k=hex_color("#62b062"),  # hood / cloak
        c=hex_color("#5a7a3a"), C=hex_color("#3c5226"),  # tunic
        A=hex_color("#5a3a1a"),  # leather straps
        p=hex_color("#4a3a30"), b=hex_color("#2a221c"),
    ),
    [
        ".....oooooo.....",
        "....ohhhhhho....",
        "..ohhhkhhhhho...",
        "..ohhhhhhhhho...",
        "...ohssssssho...",
        "...ohesssseho...",
        "...ohSsssSSho...",
        "....oSSsSSo.....",
        "....ohcccho.....",
        "...ohAcccAho....",
        "...ohcCcccho....",
        "....ocCCCco.....",
        ".....oCCCo......",
    ],
    dodge="dash",
    portrait_bg=hex_color("#2e5a2e"),
)

WIZARD = CharacterSpec(
    "wizard",
    base_palette(
        h=hex_color("#6a3fbf"), H=hex_color("#452a80"), k=hex_color("#9a72e8"),  # hat/robe
        c=hex_color("#6a3fbf"), C=hex_color("#452a80"),
        a=hex_color("#f2d24a"), A=hex_color("#b08f2a"),  # stars / brim band
        p=hex_color("#452a80"), b=hex_color("#2a221c"),
        r=hex_color("#e0e0e0"),  # beard
    ),
    [
        "........oo......",
        ".......ohho.....",
        "......ohhHo.....",
        ".....ohhhHo.....",
        "....ohhkhhHo....",
        "..oohaAaAaAoo...",
        "..oSsssssssSo...",
        "...ossessseso...",
        "...oSssssssSo...",
        "....orrrrro.....",
        "...occkccCco....",
        "...ocaccccCo....",
        "...occccCCCo....",
    ],
    dodge="blink",
    portrait_bg=hex_color("#4a2a80"),
)

OLIGARCH = CharacterSpec(
    "oligarch",
    base_palette(
        h=hex_color("#242430"), H=hex_color("#101018"), k=hex_color("#4a4a5c"),  # top hat
        c=hex_color("#303040"), C=hex_color("#1c1c28"),  # suit
        a=hex_color("#c0302e"), A=hex_color("#802020"),  # tie / band
        g=hex_color("#f2c94c"), G=hex_color("#b58b1e"),  # monocle rim and chain
        m=hex_color("#f8f8f8"),  # shirt
        p=hex_color("#303040"), b=hex_color("#101018"),
        n=hex_color("#e8a070"),  # nose blush
    ),
    [
        "....oooooooo....",
        "....ohhhkhho....",
        "....ohhhhhho....",
        "....oHaaaaHo....",
        "..ooooooooooo...",
        "...osssssssso...",
        "...osesssgego...",
        "...oSsssssSgo...",
        "....oSsSSSSo....",
        "....oCmamCo.....",
        "...ocCmamCco....",
        "...occmamcco....",
        "...oCCCaCCCo....",
    ],
    dodge="hop",
    portrait_bg=hex_color("#5a4a20"),
)

SPECS = {s.name: s for s in (FIGHTER, RANGER, WIZARD, OLIGARCH)}


# ------------------------------------------------------------------- the off-hand guard
# The Fighter's off-hand gear inside the idle cell: x, y, width, height. The same box
# `tests/unit/player/class_art_test.gd` reads off the shipped PNG.
SHIELD_BOX = (0, 8, 6, 5)
## Widest the *last* painted row of that box may be. A shield ends in a point; a rounded
## block ends as wide as it started, which is what shipped when the flat red box was merely
## recoloured instead of redrawn.
SHIELD_POINT = 2
## Colours the face carries, outline excluded: a lit rim, a face, a shaded face and a boss.
SHIELD_MIN_SHADES = 4


def _assert_shield(c: Canvas, crest: Color) -> None:
    """A shield reads as a shield: it tapers to a point, and it is not the plume in a box.

    The owner played two builds of this sprite. In the first the off-hand gear was a flat
    block painted in the helm crest's own red; in the second the block was recoloured and
    kept its shape, so this measures the *silhouette* as well as the palette.
    """
    x0, y0, w, h = SHIELD_BOX
    widths: list[int] = []
    shades: set[tuple[int, int, int, int]] = set()
    for y in range(y0, y0 + h):
        row = 0
        for x in range(x0, x0 + w):
            px = c.get(x, y)
            if not px[3]:
                continue
            row += 1
            if px == crest:
                raise ValueError(f"the shield at {x},{y} is painted in the helm crest's colour")
            if px != OUTLINE:
                shades.add(px)
        widths.append(row)
    painted = [i for i, n in enumerate(widths) if n > 0]
    if not painted:
        raise ValueError("the Fighter has no off-hand gear left")
    widest = max(widths)
    point = widths[painted[-1]]
    if point > SHIELD_POINT:
        raise ValueError(
            f"the shield is {widest}px across and still {point}px at its lowest row - "
            "that is a block with rounded corners, not a shield"
        )
    if widths.index(widest) * 2 > painted[-1]:
        raise ValueError("the shield is widest below its middle - it is upside down")
    if len(shades) < SHIELD_MIN_SHADES:
        raise ValueError(
            f"the shield draws {len(shades)} colours - it needs a rim, a face, a shade and a boss"
        )


# ----------------------------------------------------------------------------- frames
def run_frames(spec: CharacterSpec) -> list[Canvas]:
    """Six distinct frames: contact / down / pass for each leg, with a bounce on the passes."""
    frames = []
    for i, legs in enumerate(LEGS_RUN):
        frames.append(hover(spec.frame(legs), -1 if i in (2, 5) else 0))
    return frames


def dodge_frames(spec: CharacterSpec) -> list[Canvas]:
    base = spec.idle()
    if spec.dodge == "roll":
        ball = base.scaled(0.85, 0.85)
        return [base.scaled(1.15, 0.8), ball.rotate90(1), ball.rotate90(2), ball.rotate90(3)]
    if spec.dodge == "dash":
        lean = base.shift(1, 0)
        trail = Canvas(T, T)
        trail.blit(base.shift(-3, 0).fade(0.35), 0, 0)
        trail.blit(base.shift(-1, 0).fade(0.6), 0, 0)
        trail.blit(base.scaled(1.25, 0.85), 0, 0)
        return [lean.scaled(1.1, 0.9), trail, base.scaled(1.2, 0.9), base]
    if spec.dodge == "blink":
        return [
            base.scaled(0.8, 1.2),
            base.scaled(0.45, 1.35).fade(0.6),
            base.scaled(0.2, 1.5).fade(0.35),
            base.scaled(1.2, 0.9),
        ]
    # hop (Oligarch's "delegation")
    return [
        base.scaled(1.2, 0.8),
        base.scaled(0.9, 1.15).shift(0, -3),
        base.shift(0, -2),
        base.scaled(1.15, 0.85),
    ]


def build_sheet(spec: CharacterSpec) -> Sheet:
    sheet = Sheet(T, T, 6, 5)
    base = spec.idle()
    sheet.put_row(0, bob_frames(base, 4))
    sheet.put_row(1, run_frames(spec))
    sheet.put_row(2, dodge_frames(spec))
    sheet.put_row(3, hurt_frames(base))
    sheet.put_row(4, collapse_death(base, 6))
    return sheet


# --------------------------------------------------------------------------- portraits
def portrait(spec: CharacterSpec) -> Canvas:
    """32x32 bust: the head of the sprite map upscaled 2x over a class-coloured plate."""
    c = Canvas(32, 32, spec.portrait_bg)
    c.rect(0, 0, 32, 32, OUTLINE, filled=False)
    c.rect(1, 1, 30, 30, hex_color("#ffffff", 40), filled=False)
    head = spec.frame(LEGS_IDLE)
    # crop head + shoulders (rows 0..12), scale 2x, anchor at bottom of the plate
    bust = head.crop(0, 0, 16, 13).resized(32, 26)
    c.blit(bust, 0, 6)
    return c


def generate(root: pathlib.Path) -> list[pathlib.Path]:
    _assert_shield(FIGHTER.idle(), FIGHTER.palette["a"])
    out = []
    for name, spec in SPECS.items():
        path = root / "assets" / "sprites" / "player" / f"{name}.png"
        build_sheet(spec).save(path)
        out.append(path)
        ppath = root / "assets" / "sprites" / "player" / f"{name}_portrait.png"
        portrait(spec).save(ppath)
        out.append(ppath)
    return out
