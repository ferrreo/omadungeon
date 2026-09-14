"""Enemy sprite sheets (docs/GAME_DESIGN.md section 7).

Sheet rows: 0 idle x4, 1 move x4, 2 windup x2, 3 attack x3, 4 hurt x1, 5 death x4.
Cells are 16x16 (32x32 for clown_car, dotfile_golem and the bosses). Sprites face right.
"""
from __future__ import annotations

import pathlib
from dataclasses import dataclass

from characters import LEGS_IDLE, LEGS_RUN, base_palette
from toolkit import (
    Canvas,
    Color,
    Sheet,
    bob_frames,
    collapse_death,
    hex_color,
    hover,
    hurt_frames,
    rim,
)

T = 16

ENEMY_IDS = (
    "juggler",
    "honker",
    "balloon_clown",
    "mime",
    "clown_car",
    "manpage_hurler",
    "beard_warden",
    "rant_priest",
    "vim_zealot",
    "kernel_panic",
    "ricer",
    "distro_hopper",
    "config_gremlin",
    "dotfile_golem",
    "ringmaster",
    "elder_greybeard",
    "the_suit",
)

RED_NOSE = hex_color("#e83030")
GREY_BEARD = hex_color("#c8c8c8")
GREY_BEARD_SHADE = hex_color("#8a8a8a")
GOGGLE = hex_color("#f0c030")
GOGGLE_GLASS = hex_color("#40e0d0")


@dataclass
class EnemySpec:
    """An explicit pixel map plus how to animate it."""

    name: str
    palette: dict[str, Color]
    rows: list[str]  # 13 body rows when move == "legs", else full 16 (or 32) rows
    move: str = "legs"  # legs | float | hop | slide
    size: int = 16
    attack: str = "lunge"  # lunge | throw | slam | shout
    flash: Color = hex_color("#ffe060")

    def cell(self, legs: list[str] | None = None, dy: int = 0) -> Canvas:
        rows = list(self.rows)
        if self.move == "legs":
            rows += legs if legs is not None else LEGS_IDLE
        c = Canvas.from_map(rows, self.palette, self.size, self.size)
        return c.shift(0, dy) if dy else c


# ------------------------------------------------------------------------------ clowns
JUGGLER = EnemySpec(
    "juggler",
    base_palette(
        h=hex_color("#ff7a1a"), H=hex_color("#c04f00"),  # orange wig
        c=hex_color("#f2d94a"), C=hex_color("#b89a1e"),  # yellow suit
        a=hex_color("#8a3fd0"), A=hex_color("#5a2a90"),  # purple stripes
        n=RED_NOSE,
        p=hex_color("#8a3fd0"), b=hex_color("#e83030"),
        t=hex_color("#f8f8f8"), r=hex_color("#e83030"),  # pins
    ),
    [
        ".ot..oooo...ot..",
        ".oro.ohhhho.oro.",
        ".ot.ohhhhhho.ot.",
        "....ohhhhhho....",
        "...ohsssssshoot.",
        "...ohesssseho.ro",
        "...ossssnssso.t.",
        "....oSssSSSo.oo.",
        ".....occcco.....",
        "...osoacacosso..",
        "....ocacacaco...",
        "....ocCcCcCo....",
        ".....oCCCCo.....",
    ],
    attack="throw",
)

HONKER = EnemySpec(
    "honker",
    base_palette(
        h=hex_color("#40d040"), H=hex_color("#208020"),  # green hair
        c=hex_color("#e83030"), C=hex_color("#a01c1c"), k=hex_color("#ff7070"),  # red suit
        a=hex_color("#f2f2f2"), A=hex_color("#b8b8b8"),  # ruff
        n=RED_NOSE, g=hex_color("#f2c94c"), G=hex_color("#b58b1e"),  # horn
        p=hex_color("#3060d0"), b=hex_color("#e83030"),
    ),
    [
        "..oo......oo....",
        ".ohhoooooohho...",
        ".ohhhhhhhhhho...",
        ".ohhhssssshho...",
        "..oossesseoo....",
        "...ossssssso....",
        "...oSssnnsSo.oo.",
        "....oSsnnSo.ogo.",
        "...oaaaaaao.ogo.",
        "..occccccco.oGo.",
        "..ockcccCco.ogo.",
        "..occccCCcoooGoo",
        "...oCCCCCoogggGo",
    ],
    attack="lunge",
)

BALLOON_CLOWN = EnemySpec(
    "balloon_clown",
    base_palette(
        r=hex_color("#e83030"), R=hex_color("#a01c1c"), k=hex_color("#ff9090"),  # balloon
        g=hex_color("#f0f0f0"),  # string
        h=hex_color("#3080ff"), H=hex_color("#1c50a0"),  # blue wig
        c=hex_color("#40d040"), C=hex_color("#208020"),  # green suit
        n=RED_NOSE, b=hex_color("#e83030"),
    ),
    [
        ".....oooo.......",
        "....orkrrro.....",
        "...orrrrrrro....",
        "...orrrrrrro....",
        "...oRrrrrrRo....",
        "....oRRRRRo.....",
        ".....ooooo......",
        ".......og.......",
        "......oooo......",
        ".....ohhhho.....",
        ".....ossssoh....",
        ".....oesseo.....",
        ".....osnnso.....",
        "......occo......",
        ".....ocCCco.....",
        "......obbo......",
    ],
    move="float",
    attack="lunge",
)

MIME = EnemySpec(
    "mime",
    base_palette(
        h=hex_color("#202020"), H=hex_color("#101010"), k=hex_color("#404040"),  # beret
        c=hex_color("#f0f0f0"), C=hex_color("#b0b0b0"), a=hex_color("#202020"),  # stripes
        f=hex_color("#f8f8f8"), F=hex_color("#c8c8c8"),  # white face paint
        e=hex_color("#202030"), r=hex_color("#e83030"),
        p=hex_color("#202020"), b=hex_color("#202020"),
        w=hex_color("#f8f8f8"),
    ),
    [
        "......oooooo....",
        "...ooohhkhhhoo..",
        "..ohhhhhhhhhhho.",
        "...oofffffffoo..",
        "...ofefffffefo..",
        "...offfffffffo..",
        "...oFffrrrffFo..",
        "....oFFfffFFo...",
        ".....oaaaao.....",
        "..oo.occcco.oo..",
        ".owwooaaaaoowwo.",
        ".owwo.cccc.owwo.",
        "..oo..aaaa..oo..",
    ],
    attack="shout",
)

CLOWN_CAR = EnemySpec(
    "clown_car",
    base_palette(
        c=hex_color("#f2d94a"), C=hex_color("#b89a1e"), k=hex_color("#fff090"),  # yellow body
        a=hex_color("#e83030"), A=hex_color("#a01c1c"),  # red trim
        g=hex_color("#80e0ff"), G=hex_color("#3090c0"),  # glass
        m=hex_color("#d8dce8"), M=hex_color("#8c92a8"),  # chrome
        t=hex_color("#303030"), x=hex_color("#606060"),  # tyres
        h=hex_color("#ff7a1a"), b=hex_color("#3080ff"), v=hex_color("#40d040"),  # wigs
        n=RED_NOSE, w=hex_color("#f8f8f8"), y=hex_color("#f2c94c"),
    ),
    [
        "................................",
        "................................",
        "................................",
        "..........oooo...oooo...........",
        ".........ohhhho.obbbbo..........",
        "........ohhhhhhobbbbbbo.........",
        "........ohwwwwhobwwwwbo.........",
        "........ohwnwwhobwwnwbo..oooo...",
        "........ohwwwwhobwwwwbo.ovvvvo..",
        "......oooooooooooooooooovvvvvvo.",
        ".....okkkkkkkkkkkkkkkkoovwwwwvo.",
        "....occccccccccccccccccovwnwwvo.",
        "...occccaaaaaaaaaaaaaacoovwwwvo.",
        "..occcccaaaaaaaaaaaaaaccoooooo..",
        ".occccccaaaaaaaaaaaaaaccccccco..",
        ".occcccccccccccccccccccccccccco.",
        ".occGggggGocccccccccoGggggGccco.",
        ".ocGgggggggocccccccoGgggggggcco.",
        ".ocGgggggggocccccccoGgggggggcco.",
        ".occGggggGooccccccooGggggGcccco.",
        ".ocCCooooCCCCCCCCCCCCCooooCCCCo.",
        ".oCCCCCCCCCCCCCCCCCCCCCCCCCCCCo.",
        "yoCCCCCCCCCCCCCCCCCCCCCCCCCCCCoy",
        ".oomMMMMmoooooooooooomMMMMmooo..",
        "..otxxxxtoooooooooootxxxxto.....",
        "..otxttxtoo.......ootxttxto.....",
        "..otxxxxto.........otxxxxto.....",
        "...otttto...........otttto......",
        "....oooo.............oooo.......",
        "................................",
        "................................",
        "................................",
    ],
    move="slide",
    size=32,
    attack="lunge",
)

# -------------------------------------------------------------------------- greybeards
MANPAGE_HURLER = EnemySpec(
    "manpage_hurler",
    base_palette(
        h=GREY_BEARD, H=GREY_BEARD_SHADE,  # hair/beard
        c=hex_color("#787878"), C=hex_color("#505050"), k=hex_color("#a0a0a0"),  # robe
        t=hex_color("#e8dcc0"), a=hex_color("#8b2c2c"), A=hex_color("#5a1c1c"),  # tome
        p=hex_color("#505050"), b=hex_color("#2a221c"),
    ),
    [
        "...........ooooo",
        "..........oaaatao",
        ".....oo...oaaatao",
        "....ohhho.oAaataо".replace("о", "o"),
        "...ohhhhhho.oooo",
        "...osssssso..so.",
        "...osesssesooso.",
        "...ohssssshoso..",
        "...ohhhhhhho....",
        "....ohhhhhoo....",
        "...occhhhcco....",
        "...ockhhhCco....",
        "...occcCCCCo....",
    ],
    attack="throw",
)

BEARD_WARDEN = EnemySpec(
    "beard_warden",
    base_palette(
        h=GREY_BEARD, H=GREY_BEARD_SHADE,
        m=hex_color("#a0a8b8"), M=hex_color("#606878"), k=hex_color("#d0d8e8"),  # helm
        c=hex_color("#606060"), C=hex_color("#404040"),  # robe
        d=hex_color("#8b5a2b"), D=hex_color("#5a3a1a"), g=hex_color("#e8b83a"),  # shield
        p=hex_color("#404040"), b=hex_color("#2a221c"),
    ),
    [
        ".....oooooo.....",
        "....okmmmmmo....",
        "...ommmmmmmmo...",
        "...oMMoooooMo...",
        "...osssssssoooo.",
        "...osesssesoddDo",
        "...ohhssshhodgDo",
        "...ohhhhhhhodgDo",
        "....ohhhhhoodgDo",
        "...occhhhccodgDo",
        "...occhhhcco.DDo",
        "...occcCCCco.oo.",
        "....oCCCCCo.....",
    ],
    attack="slam",
)

RANT_PRIEST = EnemySpec(
    "rant_priest",
    base_palette(
        h=GREY_BEARD, H=GREY_BEARD_SHADE,
        c=hex_color("#4a4a5a"), C=hex_color("#2c2c38"), k=hex_color("#6c6c80"),  # hooded robe
        m=hex_color("#202030"),  # mouth
        g=hex_color("#8b5a2b"), G=hex_color("#5a3a1a"), x=hex_color("#e8b83a"),  # staff + sigil
        p=hex_color("#2c2c38"), b=hex_color("#2c2c38"),
    ),
    [
        ".....oooo.....ox",
        "....occcco...oxo",
        "...ockcccco...go",
        "...occcccco...go",
        "...ocsssssco..go",
        "...ocesssecoogGo",
        "...ocsmmmscoogo.",
        "...oChmmmhCoogo.",
        "...ochhhhhco.go.",
        "...ocChhhCcoogo.",
        "...occhhhcco.go.",
        "...ocCcCcCco.go.",
        "....oCCCCCo..go.",
    ],
    attack="shout",
)

VIM_ZEALOT = EnemySpec(
    "vim_zealot",
    base_palette(
        h=GREY_BEARD, H=GREY_BEARD_SHADE,
        c=hex_color("#1f9e4a"), C=hex_color("#136a30"), k=hex_color("#3ccf6c"),  # vim green
        a=hex_color("#f8f8f8"),  # V emblem
        m=hex_color("#d8dce8"), M=hex_color("#8c92a8"),  # blade
        p=hex_color("#136a30"), b=hex_color("#2a221c"),
    ),
    [
        "......oooo......",
        ".....ohhhho.....",
        "....ohhhhhho....",
        "....osssssso..om",
        "....osesssesoomo",
        "....ohssssho.omo",
        "....ohhhhhho.omo",
        ".....ohhhho.omo.",
        "....ockaaco.oMo.",
        "...ocaccacco.o..",
        "...occaacCco.o..",
        "...occcaCCCo....",
        "....oCCCCCo.....",
    ],
    attack="lunge",
)

KERNEL_PANIC = EnemySpec(
    "kernel_panic",
    base_palette(
        c=hex_color("#1a1a24"), C=hex_color("#0c0c12"), k=hex_color("#33334a"),  # black robe
        s=hex_color("#101014"),  # screen face
        r=hex_color("#ff3030"), R=hex_color("#a01c1c"),  # panic text
        g=hex_color("#40ff70"),  # green cursor
        h=GREY_BEARD, H=GREY_BEARD_SHADE,
        p=hex_color("#0c0c12"), b=hex_color("#0c0c12"),
    ),
    [
        "...oooooooooo...",
        "..osssssssssso..",
        "..osrrr.rrrsso..",
        "..osr.r.r.rsso..",
        "..osrrr.rr.sso..",
        "..osr...r.rsso..",
        "..osr...r.rsgo..",
        "..osssssssssso..",
        "...oooooooooo...",
        "...occchhcCco...",
        "...okcchhcCCo...",
        "...occcCCccco...",
        "...ocCCCCCCCo...",
    ],
    attack="slam",
    flash=hex_color("#ff3030"),
)

# --------------------------------------------------------------------------- tinkerers
RICER = EnemySpec(
    "ricer",
    base_palette(
        h=hex_color("#ff3fa8"), H=hex_color("#b0206e"), k=hex_color("#ff80c8"),  # neon hoodie
        c=hex_color("#ff3fa8"), C=hex_color("#b0206e"),
        g=GOGGLE, G=GOGGLE_GLASS,
        x=hex_color("#40e0d0"), a=hex_color("#a0a0a0"), A=hex_color("#606060"),  # spray can
        p=hex_color("#303040"), b=hex_color("#202030"),
        w=hex_color("#40e0d0"),  # wires
    ),
    [
        ".....oooooo.....",
        "....ohhhhhho....",
        "...ohhkhhhhho...",
        "...ohoggggoho...",
        "...ohoGooGoho...",
        "...ohsssssshoxo.",
        "...ohSssSSshoxo.",
        "....ooSSSSooooo.",
        ".....occcco.oao.",
        "....occkcccooao.",
        "....occcccc.oAo.",
        "...oocCcCCoo.o..",
        "..ow.oCCCCo.w...",
    ],
    attack="throw",
)

DISTRO_HOPPER = EnemySpec(
    "distro_hopper",
    base_palette(
        c=hex_color("#3a8ad0"), C=hex_color("#245a8a"), k=hex_color("#70b8ff"),  # blue jacket
        g=GOGGLE, G=GOGGLE_GLASS,
        h=hex_color("#4a3a30"), H=hex_color("#2a221c"),  # hair
        d=hex_color("#6b4a2b"), D=hex_color("#4a3220"),  # backpack
        r=hex_color("#e83030"), y=hex_color("#f2c94c"),  # stickers
        v=hex_color("#40d040"), m=hex_color("#d040d0"),
        p=hex_color("#245a8a"), b=hex_color("#2a221c"),
    ),
    [
        "......oooo......",
        ".....ohhhho.....",
        "...ooohhhhhoo...",
        "..oggoggggoggo..",
        "..oGGossssoGGo..",
        "...oosesssesoo..",
        "....ossssssso...",
        ".oo..oSssSSo....",
        "odDo..occco.....",
        "odyDooccccco....",
        "odrvDcckcccco...",
        "odDmDocccCcco...",
        ".oooo.oCCCCo....",
    ],
    move="hop",
    attack="throw",
)

CONFIG_GREMLIN = EnemySpec(
    "config_gremlin",
    base_palette(
        s=hex_color("#6cc04a"), S=hex_color("#3f8a2a"), k=hex_color("#9ae87a"),  # green skin
        g=GOGGLE, G=GOGGLE_GLASS,
        e=hex_color("#ffd040"),  # eyes
        w=hex_color("#40e0d0"), x=hex_color("#f0f0f0"),  # wires / teeth
        p=hex_color("#3f8a2a"), b=hex_color("#3f8a2a"),
    ),
    [
        "................",
        "..o.........o...",
        ".oso..oooo..oso.",
        ".osso.ogggo.oso.",
        "..osssogGgssso..",
        "...osksssssso...",
        "...oseesseeso...",
        "...ossssssso.w..",
        "...oSxxxxxSoow..",
        "....oSssssSo.w..",
        ".....osssso.oo..",
        "....oSsSSsSo....",
        ".....ooSSo......",
    ],
    attack="lunge",
)

DOTFILE_GOLEM = EnemySpec(
    "dotfile_golem",
    base_palette(
        c=hex_color("#d8d0b8"), C=hex_color("#a09880"), k=hex_color("#f0ecdc"),  # paper blocks
        t=hex_color("#5a5a6a"),  # text lines
        g=GOGGLE, G=GOGGLE_GLASS,
        e=hex_color("#40e0d0"),
        w=hex_color("#40e0d0"), r=hex_color("#e83030"),
        d=hex_color("#8b5a2b"), D=hex_color("#5a3a1a"),  # folder brown
    ),
    [
        "................................",
        "................................",
        "...........oooooooooo...........",
        "..........okccccccccco..........",
        "..........occtt.tt.cco..........",
        "..........occ.tttt.cco..........",
        "..........ooggggggggoo..........",
        "..........oGGeGGGGeGGo..........",
        "..........ooggggggggoo..........",
        "..........occCCCCCCcco..........",
        "..........oCCCCCCCCCCo..........",
        "......ooooooooooooooooooooo.....",
        ".....oddddDoccccccccccodddddo...",
        "....odddddDokccttttccCoddddddo..",
        "....odddddDocc.tt..ccCodddddo...",
        "....odddddDocctttt.ccCoddddo....",
        "....odDDDDDoccttt..ccCoDDDDo....",
        "....oDDDDDDocc.tttt.cCoDDDDDo...",
        "....oDDDDDDoccttt.ttcCoDDDDDDo..",
        ".....oooooocc.tt.tt.cCooooooo...",
        "..........oCC.tttt..CCo.........",
        "..........oCCCCCCCCCCCo.........",
        "..........ooooooooooooo.........",
        "..........occcccooccccco........",
        "..........ocktttoocttt.o........",
        "..........occ.ttooct.tco........",
        "..........occtt.oocttt.o........",
        "..........oCCCCCooCCCCCo........",
        "..........ooooooooooooo.........",
        "................................",
        "................................",
        "................................",
    ],
    move="slide",
    size=32,
    attack="slam",
)

# ------------------------------------------------------------------------------- bosses
RINGMASTER = EnemySpec(
    "ringmaster",
    base_palette(
        h=hex_color("#3a1030"), H=hex_color("#200a1c"),  # top hat
        g=hex_color("#f2c94c"), G=hex_color("#b58b1e"),  # gold band and trim
        c=hex_color("#d02020"), C=hex_color("#8c1414"),  # tailcoat
        m=hex_color("#ff7a1a"), M=hex_color("#c04f00"),  # wild orange hair
        n=RED_NOSE, b=hex_color("#e83030"),  # nose and painted grin
        t=hex_color("#28283a"), T=hex_color("#181820"),  # trousers and boots
        p=hex_color("#8b5a2b"), P=hex_color("#5a3a1a"),  # coiled whip
    ),
    [
        "................................",
        "................................",
        "...........oooooooooo...........",
        "...........ohhhhhhhho...........",
        "...........ohhhhhhhho...........",
        "...........oggggggggo...........",
        "...........ohhhhhhhho...........",
        "...........oHHHHHHHHo...........",
        "........ohhhhhhhhhhhhhho........",
        "........oHHHHHHHHHHHHHHo........",
        "...........owwwwwwwwo...........",
        "...........owewwwwewo...........",
        "...........owwwnnwwwo...........",
        "...........owbbbbbbwo...........",
        "..........ommwwwwwwmmo..........",
        ".........oMmwwwwwwwwmMo.........",
        "........occcccccccccccco.oppo...",
        "........oCCcccggggcccCCoopPPpo..",
        "........oCCccgwwgccccCCo.oppo...",
        "........ossccccggccccsso..opo...",
        "..........oggggggggggo...opo....",
        ".........occcccccccccco.opo.....",
        ".......oCCoccccccccccoCCo.......",
        ".......oCCoottto.otttoCCo.......",
        ".......oCCoottto.otttoCCo.......",
        ".......oCCoottto.otttoCCo.......",
        "..........oTTTTooTTTTo..........",
        "..........oTTTTooTTTTo..........",
        "..........oooooooooooo..........",
        "................................",
        "................................",
        "................................",
    ],
    move="slide",
    size=32,
    attack="lunge",
    flash=hex_color("#ff4060"),
)

ELDER_GREYBEARD = EnemySpec(
    "elder_greybeard",
    base_palette(
        h=hex_color("#d4d4d4"), H=GREY_BEARD_SHADE,  # the beard, all the way down
        c=hex_color("#4a4a58"), C=hex_color("#2a2a34"), k=hex_color("#6c6c84"),  # robe
        g=hex_color("#40ff70"), x=hex_color("#e8b83a"),  # terminal-green spectacles, gold frame
        t=hex_color("#e8dcc0"), a=hex_color("#8b2c2c"), A=hex_color("#5a1c1c"),  # floating tome
        p=hex_color("#2a2a34"), b=hex_color("#2a221c"),
    ),
    [
        "................................",
        "...........oooooooooo...........",
        "..........ockcccccccco..........",
        ".........occcccccccccco.ooooooo.",
        ".........occsssssssscco.oaataao.",
        ".........occsggxggsscco.oaataao.",
        ".........occsssssssscco.oAataAo.",
        ".........occshhhhhhscco.oAAtAAo.",
        ".........ohhhhhhhhhhhho.ooooooo.",
        ".......occhhhhhhhhhhhhcCo.......",
        "......ockchhhhhhhhhhhhcCCo......",
        "......occchhhhhhhhhhhhcCCo......",
        ".....occcchhhhhhhhhhhhcCCCo.....",
        ".....ockcchhhhhhhhhhhhcCCCo.....",
        "....occccchhhhhhhhhhhhcCCCCo....",
        "....occcccHhhhhhhhhhhHcCCCCo....",
        "....occccchhhhhhhhhhhhcCCCCo....",
        "....occcccHhhhhhhhhhhHcCCCCo....",
        "....occccchhhhhhhhhhhhcCCCCo....",
        "...occcccchhhhhhhhhhhhcCCCCCo...",
        "...ockcccchhhhhhhhhhhhcCCCCCo...",
        "...occcccccHhhhhhhhhHcCCCCCCo...",
        "...occccccccHhhhhhhHcCCCCCCCo...",
        "..occccccccccHhhhhHcCCCCCCCCCo..",
        "..occcccccccchhhhhhcCCCCCCCCCo..",
        "..occccccccccchhhhcCCCCCCCCCCo..",
        "..occcccccccccchhcCCCCCCCCCCCo..",
        ".oCCCCCCCCCCCCCCCCCCCCCCCCCCCCo.",
        ".oCCCCCCCCCCCCCCCCCCCCCCCCCCCCo.",
        "..oooooooooooooooooooooooooooo..",
        "................................",
    ],
    move="slide",
    size=32,
    attack="throw",
    flash=hex_color("#40ff70"),
)


# ------------------------------------------------------------------------------ bosses
THE_SUIT = EnemySpec(
    "the_suit",
    base_palette(
        c=hex_color("#2a2e3c"), C=hex_color("#171a24"),  # charcoal suit
        h=hex_color("#1a1a1e"), H=hex_color("#35353c"),  # slicked hair
        m=hex_color("#10121a"),  # mirrored shades
        t=hex_color("#c81e2e"), T=hex_color("#8a0f1c"),  # power tie
        g=hex_color("#f0c040"), G=hex_color("#a8801e"),  # gold briefcase
        p=hex_color("#22252f"), b=hex_color("#101014"),  # trousers, oxfords
    ),
    [
        "................................",
        "................................",
        "............oooooooo............",
        "...........ohhhhhhhho...........",
        "...........ohHhhhhhho...........",
        "...........osssssssso...........",
        "...........ommmwmmmmo...........",
        "...........ossmmmmsso...........",
        "...........osssssssso...........",
        "...........oSssssssSo...........",
        "............oSSSSSSo............",
        ".............osso...............",
        ".........oooccwwwwccooo.........",
        ".........occcwwttwwccco.........",
        ".........occcwwtTwwccco.........",
        ".........occcwwtTwwccco.........",
        "....oggo.occccwtTwcccco.........",
        ".oooooooooccccwtTwcccco.........",
        ".oggggggooccccCtTCcccco.........",
        ".ogGGGGgooccccCtTCcccco.........",
        ".ogggggGooccccCCCCcccco.........",
        ".ogGGGGGooccccCCCCcccco.........",
        ".oGGGGGGooCCCCCCCCCCCCo.........",
        ".oooooooo..oppppppppo...........",
        "...........oppppppppo...........",
        "...........opppoopppo...........",
        "...........opppoopppo...........",
        "...........opppoopppo...........",
        "...........opppoopppo...........",
        "...........obbboobbbo...........",
        "...........obbboobbbo...........",
        "...........oooooooooo...........",
    ],
    move="slide",
    size=32,
    attack="throw",
    flash=hex_color("#f0c040"),
)

SPECS: dict[str, EnemySpec] = {
    s.name: s
    for s in (
        JUGGLER,
        HONKER,
        BALLOON_CLOWN,
        MIME,
        CLOWN_CAR,
        MANPAGE_HURLER,
        BEARD_WARDEN,
        RANT_PRIEST,
        VIM_ZEALOT,
        KERNEL_PANIC,
        RICER,
        DISTRO_HOPPER,
        CONFIG_GREMLIN,
        DOTFILE_GOLEM,
        RINGMASTER,
        ELDER_GREYBEARD,
        THE_SUIT,
    )
}


# ----------------------------------------------------------------------------- frames
def move_frames(spec: EnemySpec) -> list[Canvas]:
    base = spec.cell()
    if spec.move == "legs":
        poses = [LEGS_RUN[0], LEGS_RUN[2], LEGS_RUN[3], LEGS_RUN[5]]
        return [spec.cell(p, -1 if i % 2 else 0) for i, p in enumerate(poses)]
    if spec.move == "float":
        # Four distinct frames that never clip: bob (via `hover`) crossed with a drift.
        return [base, hover(base, -1), base.shift(1, 0), hover(base, -1).shift(-1, 0)]
    if spec.move == "hop":
        return [
            base.scaled(1.15, 0.85),
            base.scaled(0.9, 1.1).shift(0, -3),
            base.shift(0, -4),
            base.scaled(1.1, 0.9),
        ]
    # slide: subtle rock left/right
    return [base, base.shift(1, 0), base.shift(0, -1), base.shift(-1, 0)]


def windup_frames(spec: EnemySpec) -> list[Canvas]:
    """Telegraph: crouch, then rear back inside a bright rim so the tell reads at a glance."""
    base = spec.cell()
    crouch = base.scaled(1.12, 0.86)
    rear = rim(base.scaled(0.92, 1.14).shift(-1, -1), spec.flash)
    for x, y in ((2, 1), (spec.size - 3, 2)):
        rear.set(x, y, spec.flash)
    return [rim(crouch, mix_dim(spec.flash)), rear]


def mix_dim(color: Color) -> Color:
    """Half-strength telegraph colour for the first windup frame."""
    return (color[0], color[1], color[2], 150)


def attack_frames(spec: EnemySpec) -> list[Canvas]:
    base = spec.cell()
    if spec.attack == "throw":
        return [base.scaled(0.9, 1.1), base.scaled(1.15, 0.9).shift(2, 0), base.shift(1, 0)]
    if spec.attack == "slam":
        return [base.scaled(0.95, 1.2).shift(0, -2), base.scaled(1.25, 0.75), base.scaled(1.1, 0.9)]
    if spec.attack == "shout":
        return [base.scaled(1.05, 1.05), base.scaled(1.2, 1.1).shift(0, -1), base.scaled(1.1, 1.0)]
    return [base.scaled(0.85, 1.1).shift(-1, 0), base.scaled(1.25, 0.9).shift(2, 0), base.shift(1, 0)]


def build_sheet(spec: EnemySpec) -> Sheet:
    sheet = Sheet(spec.size, spec.size, 4, 6)
    base = spec.cell()
    sheet.put_row(0, bob_frames(base, 4))
    sheet.put_row(1, move_frames(spec))
    sheet.put_row(2, windup_frames(spec))
    sheet.put_row(3, attack_frames(spec))
    # Hurt is a posed recoil, not a white silhouette: EnemyBase already pulses
    # self_modulate on hit and plays this single frame for the whole stun.
    sheet.put_row(4, [hurt_frames(base)[0]])
    sheet.put_row(5, collapse_death(base, 4))
    return sheet


def generate(root: pathlib.Path) -> list[pathlib.Path]:
    out = []
    for name, spec in SPECS.items():
        path = root / "assets" / "sprites" / "enemies" / f"{name}.png"
        build_sheet(spec).save(path)
        out.append(path)
    return out
