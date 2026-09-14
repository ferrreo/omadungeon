"""Pixel maps for the biome props, one string of ramp keys per row.

Split out of ``props.py`` so the drawing code stays readable next to the data. Keys are the
eight authoring-ramp entries from ``toolkit.RAMP`` (``. o d m l h A B``); ``props._prop_map``
checks every map is 16x16 and ``props._assert_inset`` that the finished cell leaves the tile's
border ring empty, which is the clutter half of the visual grammar (see
``assets/tiles/README.md``, "Reading the world at a glance").

Third redraw. The two before it were readable to the person who drew them and to nobody else:
every kind was a rounded grey rectangle with a different texture inside it, all of them the
same size and the same hue once the room tint had landed, and a barrel, a crate, a coffin and
a shelf differed only in their stripes. This set is authored against five rules, and the
review sheet (``tests/out/art_props_all.png``) is judged against them before anything else:

1. **One silhouette per kind, and no two alike in a biome.** Tall-and-thin (candle, lectern,
   monolith), round (urn, snowman, orb), square (crate, ice block, bookshelf), wide-and-low
   (anvil, desk, cart) and pointed (crystal, coffin) are the five shapes; a biome's kinds are
   spread across them, so the outline alone says which is which at one glance.
2. **One feature, not a texture.** A crate has one X, a barrel three dark hoops, a gravestone
   two lines of writing. Nothing is hatched, dithered or striped: at 3x on a 16 px sprite a
   texture is noise.
3. **Big, flat tone areas.** Body ``l``, top face ``h``, shadow side ``m``, deep detail ``d``,
   every area at least 2 px wide. The accent (``A``/``B``) is the *identifying* detail - a
   flame, book spines, ice cracks, a rune - not decoration.
4. **Fill the cell.** Solids are 10-13 px wide; a prop the size of the player is a thing, a
   prop half that size is a speck.
5. **The recipe is the physics.** Solid = 1 px ink outline + contact shadow on row 14 +
   stands tall. Flat = no ink at all, no shadow, starts at row 4 or below, two tones. The
   generator refuses a map that breaks its recipe (``props._assert_recipe``).

Every map here is drawn in-house, by hand, for this game; no third-party art is traced or
copied. Nine kinds a biome (four shared, five of the biome's own) is the whole catalogue: the
fourth round cut cobweb, furnace, ice patch, loose pages and glitch, each of which read as
another kind's texture at one glance rather than as a thing of its own.
"""
from __future__ import annotations

# -- shared by every biome ---------------------------------------------------------------

## A cylinder with three dark hoops; the hoops are `d`, never ink, so the
## body stays one shape instead of a stack of stripes.
BARREL = (
    "................",
    "....oooooooo....",
    "...ohhhhhhhhmo..",
    "..ohhhhhhhhhmmo.",
    "..oddddddddddo..",
    "..olllllllllmo..",
    "..olllllllllmo..",
    "..olllllllllmo..",
    "..oddddddddddo..",
    "..olllllllllmo..",
    "..olllllllllmo..",
    "..oddddddddddo..",
    "..ommmmmmmmmmo..",
    "...oooooooooo...",
    "....oooooooo....",
    "................",
)

## A square box with one X brace and a lit top plank.
CRATE = (
    "................",
    "................",
    "..oooooooooooo..",
    "..ohhhhhhhhhho..",
    "..oldlllllldlo..",
    "..olldllllddlo..",
    "..ollldlldlllo..",
    "..olllldddlllo..",
    "..olllldddlllo..",
    "..ollldlldlllo..",
    "..olldllllddlo..",
    "..oldlllllldlo..",
    "..ommmmmmmmmmo..",
    "..oooooooooooo..",
    "...oooooooooo...",
    "................",
)

## A grain sack: narrow tied neck, wide slumped body.
SACK = (
    "................",
    "................",
    "......oooo......",
    ".....ohhhho.....",
    ".....oddddo.....",
    "....ohllllmo....",
    "...ohlllllmmo...",
    "..ohlllllllmmo..",
    "..ohlllllllmmo..",
    "..olllllllllmo..",
    "..olllllllllmo..",
    "..ommlllllmmmo..",
    "..ommmmmmmmmmo..",
    "...oooooooooo...",
    "....oooooooo....",
    "................",
)

## Three loose stones lying on the floor. Flat: no ink, no shadow.
RUBBLE = (
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "........lll.....",
    ".......lllll....",
    ".......mmmmm....",
    "..lll...........",
    ".lllll....ll....",
    ".mmmmm...llll...",
    "..mmm....mmmm...",
    ".........mm.....",
    "................",
    "................",
)

# -- crypt -------------------------------------------------------------------------------

## Upright coffin: shoulders at row 5, tapering foot, a cross on the lid in accent A.
COFFIN = (
    "................",
    ".....oooooo.....",
    "....ohhhhhmo....",
    "...ohlllllmmo...",
    "..ohlllAlllmmo..",
    ".ohllllAlllllmo.",
    ".ohllAAAAAllmmo.",
    ".ohllllAlllmmmo.",
    ".ohllllAlllmmmo.",
    "..ohlllAllmmmo..",
    "..ohlllAllmmmo..",
    "...ohllllmmmo...",
    "...ohllllmmmo...",
    "....oooooooo....",
    "....oooooooo....",
    "................",
)

## Arched headstone with two lines of writing, on a wider plinth.
GRAVESTONE = (
    "................",
    ".....oooooo.....",
    "....ohhhhhmo....",
    "...ohhhhhhmmo...",
    "...ohllllllmo...",
    "...ohldddllmo...",
    "...ohllllllmo...",
    "...ohlddddlmo...",
    "...ohllllllmo...",
    "...ohllllllmo...",
    "...ohllllllmo...",
    "..oohhhhhhmmoo..",
    "..ommmmmmmmmmo..",
    "..oooooooooooo..",
    "...oooooooooo...",
    "................",
)

## Narrow mouth, bulbous belly with an accent band, a crack
## down the side, a foot.
URN = (
    "................",
    "................",
    ".....oooooo.....",
    "....ohddddmo....",
    ".....ohllmo.....",
    ".....ohllmo.....",
    "...ooohllmooo...",
    "..ohhllllllmmo..",
    "..ohAAAAAAAmmo..",
    "..ohllllldlmmo..",
    "..ohlllldllmmo..",
    "...ohlllldlmo...",
    "....ohlllmmo....",
    "....oooooooo....",
    ".....oooooo.....",
    "................",
)

## Tall thin candle in accent A flame on a wide dish.
CANDLE = (
    "................",
    ".......AA.......",
    "......AAAA......",
    "......ABBA......",
    ".......oo.......",
    "......ohhmo.....",
    "......ohhmo.....",
    "......ohhmo.....",
    "......ohhmo.....",
    "......ohhmo.....",
    "......ohhmo.....",
    "....oohhhmmoo...",
    "...ohhllllmmmo..",
    "...oooooooooo...",
    "....oooooooo....",
    "................",
)

## A bone pile: one big pale skull with dark sockets, a long bone crossed beside it. Flat:
## no ink, no shadow, starts at row 4.
BONES = (
    "................",
    "................",
    "................",
    "................",
    "....hhhhh.......",
    "...hhhhhhh......",
    "...hdhhhdh..hh..",
    "...hhhhhhh.hh...",
    "....hdhdh.hh....",
    "....hhhhhhh.....",
    "........hh.hh...",
    ".......hh...hh..",
    "..hh..hh........",
    "...hhhh.........",
    "................",
    "................",
)

# -- forge -------------------------------------------------------------------------------

## Wide horned top, narrow waist, wide base: the anvil silhouette.
ANVIL = (
    "................",
    "................",
    "................",
    ".oooooooooooo...",
    ".ohhhhhhhhhhhoo.",
    ".ohlllllllllllo.",
    "..oomllllllmoo..",
    "....ommlllmo....",
    ".....ommlmo.....",
    ".....ommlmo.....",
    "....ohlllmmo....",
    "...ohlllllmmo...",
    "..oddddddddddo..",
    "..oooooooooooo..",
    "...oooooooooo...",
    "................",
)

## A coal cart: a tapered hopper on two big ink wheels with a heap of coal (dark, accent A
## embers) above the rim. Wide-and-low, the one forge kind with wheels.
CART = (
    "................",
    "................",
    "................",
    "......ddd.......",
    "....ddAddAdd....",
    "...dddddddddd...",
    ".oooooooooooooo.",
    ".ohhhhhhhhhhhmo.",
    ".ohlllllllllmmo.",
    "..ohllllllllmo..",
    "..ohllllllllmo..",
    "...ommmmmmmmo...",
    "...oooooooooo...",
    "..oddo....oddo..",
    "..oooooooooooo..",
    "................",
)

## A brazier: bowl on three legs with a fire in accent A and a hot core in accent B.
BRAZIER = (
    "................",
    ".......AA.......",
    "......AAAA......",
    ".....AABBAA.....",
    ".....ABBBBA.....",
    "....oAABBAAo....",
    "...ohhhhhhhhmo..",
    "...ohlllllllmo..",
    "....ommmmmmmo...",
    ".....oooooo.....",
    "....od.oo.do....",
    "...od..oo..do...",
    "..od...oo...do..",
    "..oooooooooooo..",
    "...oooooooooo...",
    "................",
)

## A length of chain lying on the floor. Flat: two tones, no ink.
CHAIN = (
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "..mmm...........",
    ".m...m..mmm.....",
    ".m...mmm...m....",
    "..mmm.dm...m....",
    "......mmmmm.....",
    "........dmmm....",
    "..........m..mm.",
    "..........mmmm..",
    "................",
    "................",
)

## A cooling slag puddle: dark rim, accent A glow, hot core in B. Flat.
SLAG = (
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "....ddddd.......",
    "...ddAAAddd.....",
    "..ddAABBAAdd....",
    "..dAABBBBAAdd...",
    "..ddAAABBAAdd...",
    "...ddAAAAAdd....",
    "....dddddddd....",
    "................",
    "................",
)

# -- frost -------------------------------------------------------------------------------

## A block of ice: a cube with a lit top face and accent B cracks.
ICE_BLOCK = (
    "................",
    "................",
    "..oooooooooooo..",
    "..ohhhhhhhhhhho.",
    "..ohhhhhhhhhhmo.",
    "..ollBllllllmmo.",
    "..olllBlllllmmo.",
    "..ollllBllllmmo.",
    "..olllllBBBlmmo.",
    "..ollllllllBmmo.",
    "..olllllllllmmo.",
    "..olllllllllmmo.",
    "..ommmmmmmmmmmo.",
    "..oooooooooooo..",
    "...oooooooooo...",
    "................",
)

## A hanging lantern: handle loop, glass box with an accent A
## flame, a foot.
LANTERN = (
    "................",
    ".......oo.......",
    "......o..o......",
    "......o..o......",
    "....oooooooo....",
    "....ohhhhhhmo...",
    "....ohlAAllmo...",
    "....ohAAAAlmo...",
    "....ohABBAlmo...",
    "....ohAAAAlmo...",
    "....ohllAllmo...",
    "....oddddddmo...",
    ".....oooooo.....",
    ".....oddddo.....",
    "....oooooooo....",
    "................",
)

## A snowman: three stacked balls, coal eyes and buttons, an accent A carrot nose and an
## accent B scarf.
SNOWMAN = (
    "................",
    "......oooo......",
    ".....ohhhho.....",
    ".....ohdhdho....",
    ".....ohhAAho....",
    "......oBBBo.....",
    "....ooBhhhBoo...",
    "...ohhhhdhhhmo..",
    "...ohhhhhhhhmo..",
    "...ohhhhdhhhmo..",
    "..ohhhhhhhhhmmo.",
    "..ohhhhhhhhhmmo.",
    "..ohhhhhhhhmmmo.",
    "...oooooooooo...",
    "....oooooooo....",
    "................",
)

## A boulder with a snow cap and one deep crack.
BOULDER = (
    "................",
    "................",
    "......oooo......",
    "....oohhhhoo....",
    "...ohhhhhhhho...",
    "..ohhhhhhhhhmo..",
    "..ohllllllllmo..",
    "..ollldlllllmo..",
    "..ollldlllllmo..",
    "..olllldllllmo..",
    "..ollllldlllmo..",
    "..ommmmmmmmmmo..",
    "...ommmmmmmmo...",
    "....oooooooo....",
    ".....oooooo.....",
    "................",
)

## A snowdrift: a low bright mound. Flat, two tones.
SNOW = (
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "......hhhh......",
    "....hhhhhhhh....",
    "...hhhhhhhhhh...",
    "..hhhhhhhhhhhh..",
    "..hhhhhhhhhhhl..",
    "..lllllllllllll.",
    "...lllllllllll..",
    "................",
    "................",
)

# -- library -----------------------------------------------------------------------------

## A tall case with three shelves of books in accents.
BOOKSHELF = (
    "................",
    ".oooooooooooooo.",
    ".ohhhhhhhhhhhho.",
    ".odAAlBBlAAhBdo.",
    ".odAAlBBlAAhBdo.",
    ".odAAlBBlAAhBdo.",
    ".ohhhhhhhhhhhho.",
    ".odBBhAAlBBAldo.",
    ".odBBhAAlBBAldo.",
    ".odBBhAAlBBAldo.",
    ".ohhhhhhhhhhhho.",
    ".odAlBBhAAlBBdo.",
    ".odAlBBhAAlBBdo.",
    ".oooooooooooooo.",
    "..oooooooooooo..",
    "................",
)

## A writing desk: a wide lit top on four dark legs, a page with lines of writing and an
## accent A quill standing in its well. Legs and open space underneath are what say "table"
## rather than "chest" or "bed".
DESK = (
    "................",
    "................",
    "..........A.....",
    ".....hhhh.A.....",
    ".....hddh.A.....",
    ".oooohhhhoAoooo.",
    ".ohhhhhhhhhhhho.",
    ".ohhhhhhhhhhhmo.",
    ".oooooooooooooo.",
    ".oddo......oddo.",
    ".oddo.dddd.oddo.",
    ".oddo.dmmd.oddo.",
    ".oddo......oddo.",
    ".oooo......oooo.",
    ".oooooooooooooo.",
    "................",
)

## A lectern: tall post on a wide foot, sloped top carrying an open book with an accent A
## ribbon.
LECTERN = (
    "................",
    "....oooooooo....",
    "...ohhhhAhhhho..",
    "...ohhhhAhhhhmo.",
    "....oooooooooo..",
    ".......omo......",
    ".......omo......",
    ".......omo......",
    ".......omo......",
    ".......omo......",
    "......ommmo.....",
    ".....ommmmmo....",
    "....odddddddo...",
    "....oooooooooo..",
    ".....oooooooo...",
    "................",
)

## A globe: accent B sea with `h` land, on a dark stand.
GLOBE = (
    "................",
    "......oooo......",
    ".....oBBBBo.....",
    "....oBBhhBBBo...",
    "...oBBhhhBBBBo..",
    "...oBBBhhBBBBo..",
    "...oBBBBBhhBBo..",
    "...oBBBBhhhBBo..",
    "....oBBBBhBBo...",
    ".....oBBBBBo....",
    "......oooo......",
    ".......odo......",
    ".....ooddddoo...",
    "....oddddddddo..",
    ".....oooooooo...",
    "................",
)

## A stack of books lying on the floor, spines in accents. Flat.
BOOKS = (
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "....llllllll....",
    "....AAAAAAAAd...",
    "...llllllllld...",
    "...BBBBBBBBBd...",
    "..lllllllllld...",
    "..AAAAAAAAAAd...",
    "................",
    "................",
)

# -- void --------------------------------------------------------------------------------

## A crystal cluster: one tall accent B shard with a lit edge, two small ones, on dark rock.
CRYSTAL = (
    "................",
    ".......oo.......",
    "......ohBo......",
    "......ohBo......",
    "......ohBBo.....",
    ".....ohBBBo.....",
    ".....ohBBBo.oo..",
    ".....ohBBBooBo..",
    "....ohBBBBohBo..",
    "....ohBBBBohBBo.",
    "....ohBBBBohBBo.",
    "...oddddddddddo.",
    "...oddddddddddo.",
    "....oooooooooo..",
    ".....oooooooo...",
    "................",
)

## A monolith: a tall dark slab with an accent B rune and one lit edge.
MONOLITH = (
    "................",
    ".....oooooo.....",
    "....ohddddmo....",
    "....ohddddmo....",
    "....ohdBBdmo....",
    "....ohdddBmo....",
    "....ohddBBmo....",
    "....ohdBddmo....",
    "....ohdBBBmo....",
    "....ohddddmo....",
    "....ohddddmo....",
    "....ohddddmo....",
    "....ohddddmo....",
    "....oooooooo....",
    "....oooooooo....",
    "................",
)

## A floating stone: a rounded rock hanging in the air, two accent B motes in the gap
## beneath it, and its own shadow on the floor - which is the contact shadow, so it still
## reads as solid: it blocks the tile it hovers over.
FLOATER = (
    "................",
    ".....ooooo......",
    "...oohhhhhoo....",
    "..ohhhhhhhhho...",
    ".ohhhlllllllmo..",
    ".ohllllllllmmo..",
    ".olllllllllmmo..",
    "..ommmmmmmmmo...",
    "...oooooooooo...",
    "................",
    ".....B..........",
    "..........B.....",
    "................",
    "......dddddd....",
    "....oooooooooo..",
    "................",
)

## An orb on a pedestal: accent B sphere with a glint, on a narrow dark stand.
ORB = (
    "................",
    "......oooo......",
    ".....oBhhBo.....",
    "....oBBhBBBo....",
    "....oBBBBBBo....",
    "....oBBBBBBo....",
    ".....oBBBBo.....",
    "......oooo......",
    ".......odo......",
    ".......odo......",
    ".......odo......",
    "......odddo.....",
    ".....oddddddo...",
    ".....oooooooo...",
    "......oooooo....",
    "................",
)

## A rift in the floor: a jagged accent B tear with a dark edge. Flat.
RIFT = (
    "................",
    "................",
    "................",
    "................",
    "................",
    ".......dd.......",
    "......dBBd......",
    ".....dBBBBd.....",
    "....dBBBBBBd....",
    "...dBBBhhBBBd...",
    "....dBBBBBBd....",
    ".....dBBBBd.....",
    "......dBBd......",
    ".......dd.......",
    "................",
    "................",
)
