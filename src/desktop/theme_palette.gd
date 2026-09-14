## Environment palette derived from a resolved colors.toml (or otter-shell colours).
## Roles are stable; sources vary. See docs/GAME_DESIGN.md §3.2.
class_name ThemePalette
extends RefCounted

const MIN_CONTRAST := 4.5
## The wallpaper supplies no colour at all. It used to: its dominant colours joined the prop
## pool, its punchiest one was lerped into `floor_alt`, and every room surface was pulled
## toward its hue. The owner took that out (docs/GAME_DESIGN.md, decisions log): an otter-shell
## palette is *already generated from the wallpaper*, so casting the same image over it again
## applied one picture twice and turned a sage-green desktop into an orange dungeon. The
## wallpaper is a generation lever now - it seeds the floor and shapes it - and the theme is
## the colours. See `WallpaperAnalyzer.Result` and `GenParams.build`.
## Smallest luminance gap two environment surfaces may have before they read as one material.
const ENV_MIN_SEPARATION := 0.02
## The surfaces a foreground role can land on: the dungeon floor and panels (`floor`), cards
## and buttons (`floor_alt`), and the HUD plate every custom-drawn widget sits on (`void` -
## the HP bar track, the minimap plate, ability slots, toasts). A role is guarded against all
## three, so whichever one happens to be behind it, it still reads.
##
## `wall` and `wall_top` are deliberately *not* in this list, and that is a design decision
## rather than an oversight: a light theme's floor is near-white while its walls are a mid
## dark grey, so no single ink clears 4.5:1 on both (a colour dark enough for the floor is at
## most 3.1:1 on the wall). Text is therefore never left floating over the level - the HUD
## blocks sit on an opaque `void` plate (`HudPlate`, docs 3.2) so the surface behind them is
## a palette role and not "whatever the dungeon happens to draw there".
const SURFACES: PackedStringArray = ["floor", "floor_alt", "void"]

## Every role that is drawn *on top of* a surface, with the surfaces it sits on and the WCAG
## ratio it has to keep on each of them. Roles absent from this table are surfaces themselves
## and are kept apart by the depth model instead.
const ROLE_GUARDS: Dictionary = {
	"text": [SURFACES, MIN_CONTRAST],
	"text_bright": [SURFACES, MIN_CONTRAST],
	# Secondary text is still text: docs 3.2 puts every UI text/background pair at 4.5:1, and
	# the HP readout - the number you read while you are losing - is drawn in it.
	"text_dim": [SURFACES, MIN_CONTRAST],
	"accent": [SURFACES, 3.0],
	"select": [["floor"], 1.2],
	# docs 3.2 also names the danger/floor pair, but this role is the *environment* tell
	# colour: pinning it at 4.5 against `floor_alt` makes anything that nudges floor detail -
	# a biome's key subset, the depth model - drag the tell colour with it. The 4.5 that 3.2
	# asks for is applied where `danger` is read as UI text instead, by `UiTheme._readable`,
	# against the HUD plate.
	"danger": [SURFACES, 3.0],
	"heal": [SURFACES, 3.0],
	"loot": [SURFACES, 3.0],
	"magic": [SURFACES, 3.0],
	"cold": [SURFACES, 3.0],
	"heat": [SURFACES, 3.0],
	"earth": [SURFACES, 3.0],
	"rarity_common": [SURFACES, 3.0],
	"rarity_rare": [SURFACES, 3.0],
	"rarity_epic": [SURFACES, 3.0],
	"rarity_legendary": [SURFACES, 3.0],
}

## Environment surfaces, in the order collisions are resolved: the earlier a surface appears
## the more it is treated as fixed, so the floor never moves to make room for a wall.
const ENV_ROLES: PackedStringArray = ["floor", "floor_alt", "wall", "wall_top", "void"]

## Roles the player has to *find in the level* rather than read off a plate: the three pickup
## colours. Gold is `loot`, a heart is `heal`, a stat orb is `magic` (see `PickupBase`).
##
## The guard produces a *second* colour for each of them (`world_color`), it does not move the
## role. The same semantic colour has two audiences - `loot` is the coin on the floor and it is
## also the gold counter on the HUD plate, a minimap room tint and a status chip - and they sit on
## different backgrounds. Pushing the role itself until it cleared the dungeon's wall took the
## `white` fixture's `loot`, `heal` and `magic` to the same pure black and collapsed three status
## chips, a minimap kind and the otter-shell mapping with it. The dungeon gets its own answer; the
## HUD keeps the role.
##
## `SURFACES` above is the UI's answer - the surfaces a piece of HUD can sit on - and it is the
## wrong answer for a coin. A drop lands wherever the fight ended: on floor tiles, on the
## decorated `floor_alt` variants, and, once it has popped and while it bobs, over the wall face
## at the edge of the room. Guarding it against the floor alone is what made it invisible: on
## the `white` fixture `loot` measured 8.86:1 on the floor and **1.30:1 on the wall**, and on
## `catppuccin-latte` 1.20:1, so a coin that bounced against the top wall was gone.
##
## Unlike text (see `SURFACES`) this is reachable on every shipped fixture, because the target
## is 3.0 rather than 4.5 and the roles may go all the way to the dark end: on a light theme the
## walls are the darkest surface in the room, so a near-black coin clears the floor by 20:1 and
## still clears the wall - measured worst on the six fixtures is 3.08:1 (`white`, `loot` on
## `wall`). The three roles keep their hue while they move, so a latte dungeon still drops a
## brown coin, a green heart and a violet orb.
const WORLD_ROLES: PackedStringArray = ["loot", "heal", "magic"]
## The roles the *fourth* pickup kind is painted in: an `ItemPickup` diamond takes its colour
## from the rarity of the item lying under it.
##
## This is the node the first pass of the world guard stopped one short of. The three roles
## above belong to `PickupBase`, and routing `PickupBase` through `world_color()` fixed gold,
## hearts and orbs together - but an item drop is not a `PickupBase`. It is an `Interactable`
## (it has to be walked up to and asked for), so it was never on that path and went on reading
## the plain role, which is guarded against `SURFACES` only. Measured on the fixtures, that left
## every rarity between 1.08:1 and 1.21:1 against a `catppuccin-latte` wall - `rarity_common` at
## 1.08:1 is the worst reading in the tree - beside a coin that had just been fixed: the same
## bug, one node further along. The guard takes the same four to 3.01:1 and better, and it is
## not only the light themes that were short: gruvbox's `rarity_legendary` read 2.08:1 on a wall
## cap and nord's 2.43:1.
##
## They are a separate list from `WORLD_ROLES` rather than merged into it because the two carry
## different promises. The three pickup roles are a *legend* - gold, heart and orb are told
## apart by hue, so each has to keep one of its own. The four rarity roles are a *ladder*, and
## several themes author two of its rungs from the same terminal colour (`rarity_epic` and
## `loot` are both `yellow`, `rarity_rare` and `magic` both `magenta`), so a hue-distinctness
## rule is not true over them and must not be asserted over them. The contrast guard is
## identical for both, and `WORLD_GUARDED_ROLES` is what applies it.
const WORLD_RARITY_ROLES: PackedStringArray = [
	"rarity_common", "rarity_rare", "rarity_epic", "rarity_legendary"
]
## Every role `world_color()` answers for: `WORLD_ROLES` followed by `WORLD_RARITY_ROLES`.
## Spelled out rather than concatenated because a `const` may only hold a literal, and
## `PickupWorldRolesTest` fails when it stops being the union of the two.
const WORLD_GUARDED_ROLES: PackedStringArray = [
	"loot",
	"heal",
	"magic",
	"rarity_common",
	"rarity_rare",
	"rarity_epic",
	"rarity_legendary",
]
## Surfaces a dropped pickup can be drawn over: every environment surface. It is `ENV_ROLES`
## rather than a subset because a drop is not placed by a designer - a coin can be knocked into
## a corridor, over a wall cap, or onto the surround a door opens on - and the guard costs
## nothing on the surfaces it was already clearing.
const WORLD_SURFACES: PackedStringArray = ENV_ROLES
## Contrast a `WORLD_ROLES` colour keeps against every one of `WORLD_SURFACES`. Same target as
## the `ROLE_GUARDS` entry these roles already carried - what changes is how many surfaces it
## is measured against, not how hard it is measured.
const WORLD_MIN_CONTRAST := 3.0

## The four surfaces a player navigates by. `floor_alt` is deliberately absent: it is floor
## *detail*, kept deliberately close to the floor (see LIT_DETAIL_MIN_RATIO), while these four
## carry the shape of the room - where it ends, where the walls are, where the outside is.
const ENV_STRUCTURE: PackedStringArray = ["floor", "wall", "wall_top", "void"]

## Minimum WCAG contrast every pair of `ENV_STRUCTURE` surfaces keeps *after* the floor light
## level has been applied. `ENV_MIN_SEPARATION` is not this number: it is a gamma-encoded
## luminance gap, which near black is satisfied by colours whose real contrast is 1.05:1, which
## is how a dungeon floor came to render at the same value as the void outside it.
const ENV_LIT_MIN_RATIO := 1.25
## The room outline itself: floor against the unlit surround, and floor against wall face.
const ENV_LIT_FLOOR_VOID_RATIO := 1.35
const ENV_LIT_FLOOR_WALL_RATIO := 1.40
## Minimum for any lit pair that involves `floor_alt`.
const ENV_LIT_DETAIL_RATIO := 1.12

## The lit depth ladder, as minimum contrast ratios between *neighbouring* rungs walking away
## from the floor. A dark dungeon is lit from above: wall faces fall away below the floor and
## the unlit surround below them, while wall caps catch the light and sit above it. A light
## theme keeps its paper floor on top and steps down through the surround to the wall face
## (docs 3.2, "mode == light flips the lighting model").
const LIT_LADDER_DARK_BELOW: PackedStringArray = ["wall", "void"]
const LIT_LADDER_DARK_BELOW_STEPS: PackedFloat32Array = [1.50, 1.25]
const LIT_LADDER_DARK_ABOVE: PackedStringArray = ["wall_top"]
const LIT_LADDER_DARK_ABOVE_STEPS: PackedFloat32Array = [1.85]
const LIT_LADDER_LIGHT_BELOW: PackedStringArray = ["void", "wall_top", "wall"]
const LIT_LADDER_LIGHT_BELOW_STEPS: PackedFloat32Array = [1.35, 1.35, 1.45]
## `floor_alt` is placed between the floor and the rung next to it: at least this far from the
## floor, and at least this far back from that neighbour.
const LIT_DETAIL_MIN_RATIO := 1.20
const LIT_DETAIL_NEIGHBOUR_RATIO := 1.12

## Relative luminance band the *lit floor* is exposed into. A theme background is authored to
## sit behind terminal text, so it is near black in every dark theme shipped; used raw it makes
## a dungeon nothing is visible in. `LIT_FLOOR_LUMINANCE_MIN` is the readability guarantee - no
## dungeon is ever darker than this - and `LIT_FLOOR_LUMINANCE_MAX` the top of the band.
##
## Where a theme lands *inside* the band is the theme's own business: `theme_light_position()`
## reads its background luminance and the exposure follows it. An earlier model lerped the band
## by the wallpaper's ambient alone, which pinned every dark theme to the same number and made
## four different themes render the same dungeon - the exposure has to guarantee a minimum, not
## dictate a value.
const LIT_FLOOR_LUMINANCE_MIN := 0.067
## The top is pinned by the text guard, not by taste: at 0.16 nord's lit `floor_alt` reached
## L=0.195, where pure white is 4.29:1 and the HUD text could no longer clear 4.5:1 on it.
const LIT_FLOOR_LUMINANCE_MAX := 0.140
## A light theme keeps its paper floor; this is only the level it may be dimmed to.
const LIT_FLOOR_LUMINANCE_LIGHT_MIN := 0.45
## The span of theme background luminances `theme_light_position()` spreads across. Every dark
## theme shipped sits inside it (tokyo-night 0.012, catppuccin 0.014, gruvbox 0.019,
## nord 0.034); a theme outside it clamps to an end rather than falling off the ladder.
const LIT_THEME_LUMINANCE_LOW := 0.008
const LIT_THEME_LUMINANCE_HIGH := 0.045
## Exponent on that position. Dark theme backgrounds bunch up near black, so the raw ratio
## would put three of the four fixtures inside the bottom fifth of the band; the square root
## opens the crowded end out without changing the order.
const LIT_IDENTITY_CURVE := 0.5
## How far the darkest wallpaper dims a floor below the theme's own exposure. The wallpaper is
## a *lever on* the theme's light level, not a replacement for it, so it scales the theme's
## exposure instead of choosing it - which is what flattened the themes into one another.
const LIT_AMBIENT_DIM := 0.82
## Relative luminance the unlit surround is never taken below. The surround is the largest
## single region on screen, and near black it stops carrying the theme's hue at all: a floor
## exposed so low that the ladder bottoms out at L=0.0007 renders a pure black border round
## every room, identical on every theme. The floor exposure is lifted until the bottom rung of
## the ladder clears this instead. 0.012 was above black by the numbers and black to the eye;
## at 0.02 the surround is a visible dark of the theme's own colour rather than a border.
const LIT_SURROUND_LUMINANCE_MIN := 0.02

## Ordered list of role names (used for shader uniform arrays and debug swatches).
const ROLES: PackedStringArray = [
	"void",
	"floor",
	"floor_alt",
	"wall",
	"wall_top",
	"text",
	"text_dim",
	"text_bright",
	"accent",
	"select",
	"danger",
	"heal",
	"loot",
	"magic",
	"cold",
	"heat",
	"earth",
	"rarity_common",
	"rarity_rare",
	"rarity_epic",
	"rarity_legendary",
]

## Saturation the four *room* surfaces (floor, floor detail, wall, wall cap) are washed up to
## when the theme authors them grey (docs §3.2, "the room's cast"). It is deliberately the
## same order as the environment saturation the themes testers called *themed* already carry -
## nord authors its dungeon at 0.28 - and it is a *ceiling on the lift*, not a target every
## theme is pinned to: a theme already past it keeps its own chroma untouched. Raising it is
## not free. The prop ladder (`Prop.accent_colors`) re-hues a prop's body at the room's own
## saturation and places it under the room's light, and measured at 0.34-0.50 the interior
## steps it guarantees fall to 1.07-1.11 against its 1.12 - so the room's own surfaces stay
## here, and the theme's chroma is pushed through the surround, the lights and the prop
## accents instead, which no ladder reads.
const ROOM_CAST_SATURATION := 0.26
## Saturation the *surround* is lifted to on every theme with chroma anywhere. The surround
## is the largest region on screen - a third of the frame on many floors - and nothing the
## readability model measures a prop against, so it is where the theme's colour can be loud:
## a navy dark on tokyo-night, a slate one on nord, a mauve one on catppuccin, a warm brown on
## gruvbox. Hue is the theme's own; only the chroma is lifted, at constant luminance.
const SURROUND_CAST_SATURATION := 0.50
## Environment saturation at or above which a theme needs no help on its room surfaces: it
## already paints its own dungeon and the room wash is a no-op there. Measured on the shipped
## fixtures, the split is not close - tokyo-night 0.34, catppuccin 0.35, nord 0.28 sit above
## it; gruvbox 0.04, catppuccin-latte 0.08 and white 0.00 sit far below, which is exactly the
## set that rendered as greyscale.
const ROOM_CAST_ENV_FULL := 0.26
## Chroma a surface has to carry *before the exposure* before its own hue is trusted over the
## cast hue, measured absolutely (`chroma_of`: the span between a colour's brightest and
## darkest channel) rather than as HSV saturation.
##
## HSV saturation is chroma relative to value, and near black that is a lie a dungeon is then
## painted in. The owner's otter-shell background is `#0F0F0D`: two 8-bit steps of green over
## blue, a hue of 60 degrees that is quantisation noise and nothing else - yet HSV calls it 13%
## saturated, well clear of any saturation gate. The exposure then lifts that surface from
## value 0.06 to value 0.33 keeping its hue exactly, and the noise arrives on screen as a
## visible yellow floor and, at `SURROUND_CAST_SATURATION`, a yellow surround across a third of
## the frame - on a desktop whose actual colour is a sage green at 84 degrees.
##
## Absolute chroma does not lie: `#0F0F0D` carries 0.008 of it and catppuccin-latte's blue-grey
## paper - a real, authored, faint cast - carries 0.023, three times as much. The gate sits
## between them, so latte keeps its paper and the near-blacks take the theme's own cast hue.
const ROOM_CAST_OWN_CHROMA_MIN := 0.012
## Chroma the *theme* has to carry somewhere before the full wash is applied. The wash never
## invents a colour: it scales with what the desktop actually contains, so a theme authored
## entirely in greys (the `white` fixture is one, and it is a legitimate Omarchy theme) keeps
## a grey dungeon instead of being handed a hue it does not own.
const ROOM_CAST_SOURCE_FULL := 0.25
## Roles the wash takes its hue from when the environment itself is neutral: the theme's tell
## colours, which is where a grey-backgrounded theme keeps all of its colour.
const ROOM_CAST_TELL_ROLES: PackedStringArray = [
	"accent", "danger", "heal", "loot", "magic", "cold", "heat", "earth"
]

## Theme keys eligible for per-room prop accent rolls.
const PROP_POOL: PackedStringArray = [
	"red",
	"yellow",
	"orange",
	"green",
	"cyan",
	"blue",
	"magenta",
	"brown",
]

var name: String = "Fallback"
var is_light: bool = false
var colors: Dictionary = {}
## Theme colours eligible for prop accents, in a stable order.
var prop_pool: Array[Color] = []
## `WORLD_ROLES` guarded against every dungeon surface - what a *dropped pickup* is drawn in.
## Read through `world_color()`; `colors` keeps the role the HUD and the minimap use.
var world_colors: Dictionary = {}
## Raw semantic colours (for ThemeProfile statistics and variants).
var source: Dictionary = {}


static func from_colors_toml(toml: ColorsToml, theme_name: String) -> ThemePalette:
	var p := ThemePalette.new()
	p.name = theme_name
	p.is_light = toml.is_light()
	p.source = toml.colors.duplicate()
	var c := func(key: String, fallback: String = "background") -> Color:
		return toml.get_color(key, toml.get_color(fallback, Color.MAGENTA))
	p.colors = {
		"void": c.call("darker_background", "dark_background"),
		"floor": c.call("background"),
		"floor_alt": c.call("lighter_background"),
		"wall": c.call("dark_background"),
		"wall_top": c.call("muted", "dark_foreground"),
		"text": c.call("foreground"),
		"text_dim": c.call("dark_foreground", "foreground"),
		"text_bright": c.call("bright_foreground", "foreground"),
		"accent": c.call("accent", "blue"),
		"select": c.call("selection", "lighter_background"),
		"danger": c.call("red"),
		"heal": c.call("green"),
		"loot": c.call("yellow"),
		"magic": c.call("magenta"),
		"cold": c.call("cyan"),
		"heat": c.call("orange", "yellow"),
		"earth": c.call("brown", "orange"),
		"rarity_common": c.call("blue"),
		"rarity_rare": c.call("magenta"),
		"rarity_epic": c.call("yellow"),
		"rarity_legendary": c.call("bright_red", "red"),
	}
	for key: String in PROP_POOL:
		if toml.colors.has(key):
			p.prop_pool.append(toml.colors[key])
	p._apply_depth_model()
	p._apply_contrast_guard()
	return p


## Builds a palette from otter-shell's 12 semantic keys.
static func from_otter_colors(otter: Dictionary, theme_name: String) -> ThemePalette:
	var p := ThemePalette.new()
	p.name = theme_name
	var g := func(key: String, fallback: Color) -> Color: return otter.get(key, fallback)
	var bg: Color = g.call("background", Color("#1a1b26"))
	var fg: Color = g.call("foreground", Color("#c0caf5"))
	p.is_light = (bg.r8 + bg.g8 + bg.b8) > 382
	var accent: Color = g.call("accent", Color("#7aa2f7"))
	var danger: Color = g.call("danger", Color("#f7768e"))
	var success: Color = g.call("success", Color("#9ece6a"))
	var warning: Color = g.call("warning", Color("#e0af68"))
	p.colors = {
		"void": bg.darkened(0.4),
		"floor": bg,
		"floor_alt": g.call("surface_alt", bg.lightened(0.08)),
		"wall": g.call("surface", bg.darkened(0.2)),
		"wall_top": g.call("muted", fg.darkened(0.4)),
		"text": fg,
		"text_dim": g.call("muted", fg.darkened(0.3)),
		"text_bright": fg.lightened(0.2),
		"accent": accent,
		"select": g.call("selected", accent.darkened(0.5)),
		"danger": danger,
		"heal": success,
		"loot": warning,
		"magic": accent.lerp(danger, 0.5),
		"cold": accent.lerp(success, 0.5),
		"heat": warning.lerp(danger, 0.5),
		"earth": warning.darkened(0.5),
		"rarity_common": accent,
		"rarity_rare": accent.lerp(danger, 0.5),
		"rarity_epic": warning,
		"rarity_legendary": danger,
	}
	p.source = {
		"background": bg,
		"foreground": fg,
		"accent": accent,
		"red": danger,
		"green": success,
		"yellow": warning,
		"blue": accent,
		"magenta": p.colors["magic"],
		"cyan": p.colors["cold"],
	}
	p.prop_pool = [accent, danger, success, warning]
	p._apply_depth_model()
	p._apply_contrast_guard()
	return p


static func fallback() -> ThemePalette:
	var toml := ColorsToml.load_file("res://data/themes/fallback/colors.toml")
	if toml == null:
		push_error("Fallback theme missing")
		return ThemePalette.new()
	return from_colors_toml(toml, "Tokyo Night")


func get_color(role: StringName) -> Color:
	return colors.get(role, Color.MAGENTA)


## Darkest ink in the palette: tile outlines, sprite edges, anything meant to read as a line
## rather than a surface. On a dark theme that is the `void` surround; on a light one `void`
## has to stay a mid tone for the HUD plate, so the ink is derived from the floor instead.
func outline_color() -> Color:
	if not is_light:
		return colors["void"]
	return _shade(colors["floor"], colors["text"], 0.76, 0.45)


## Gives the five environment surfaces a legible ladder, then repairs any collision left.
func _apply_depth_model() -> void:
	if is_light:
		_apply_light_mode()
	_separate_surfaces()


## Light themes get their own depth model rather than a mirrored dark one: the floor stays the
## theme's paper, floor detail sits just beneath it, wall caps take a clear step down and wall
## faces a much bigger one, so walls read as solid mass against a bright floor instead of a
## wash of grey. Every step is also pulled a little toward the theme's own ink, so a light
## theme with a colour cast keeps it. `void` is the unlit surround *and* the HUD plate, so on a
## light theme it stays light too - just under the floor - and every foreground role keeps one
## polarity across the whole game instead of flipping between panel and plate.
func _apply_light_mode() -> void:
	var floor_c: Color = colors["floor"]
	var ink: Color = colors["text"]
	colors["floor_alt"] = _shade(floor_c, ink, 0.09, 0.07)
	colors["void"] = _shade(floor_c, ink, 0.20, 0.05)
	colors["wall_top"] = _shade(floor_c, ink, 0.34, 0.16)
	colors["wall"] = _shade(floor_c, ink, 0.52, 0.26)


## Walks `ENV_ROLES` and pushes each surface off every surface declared before it. Only
## collisions move, so a theme whose ladder is already legible comes through untouched.
func _separate_surfaces() -> void:
	for i in range(1, ENV_ROLES.size()):
		var role := ENV_ROLES[i]
		for j in range(i):
			colors[role] = push_apart(colors[role], colors[ENV_ROLES[j]])


## Applies `ROLE_GUARDS`. Idempotent, so re-deriving a palette per biome or per light level
## cannot drift a role further than the guard already put it.
func _apply_contrast_guard() -> void:
	var toward := Color.BLACK if is_light else Color.WHITE
	for role: String in ROLE_GUARDS:
		var guard: Array = ROLE_GUARDS[role]
		var target := float(guard[1])
		for surface: String in guard[0] as PackedStringArray:
			var background: Color = colors[surface]
			colors[role] = ensure_contrast_toward(colors[role], background, target, toward)
	_apply_world_guard()


## Applies `WORLD_GUARDED_ROLES` against *every* surface at once (`ensure_contrast_all`), rather
## than one surface at a time the way `_apply_contrast_guard` does.
##
## One at a time is the wrong shape here and is the bug the owner reported: each pass only ever
## asks "does it clear this one background", so a colour that has just been pushed to clear the
## floor is accepted however it reads on the wall - which on a light theme is the surface at the
## other end of the room's luminance range. `ensure_contrast_all` searches for a colour that
## clears them together and, when the theme makes that impossible, keeps the one whose *worst*
## reading is highest, so the answer degrades to "as visible as this theme allows" instead of
## "invisible on one surface in three".
##
## Run on the theme palette rather than on `light_environment()`'s output: a dungeon is exposed
## anywhere in a band, and a role placed for one end of it reads worse at the other. Anchoring
## on the theme's own surfaces keeps the answer stable across the band - and the exposure only
## ever moves the whole room together, so a colour that clears the theme's five surfaces clears
## the lit ones (`PickupsWorldContrastTest` measures both ends of the band and the frames in
## `tests/out/loot_drop*.png` show it).
func _apply_world_guard() -> void:
	var toward := Color.BLACK if is_light else Color.WHITE
	var backgrounds: Array[Color] = []
	for surface: String in WORLD_SURFACES:
		backgrounds.append(colors[surface] as Color)
	world_colors = {}
	for role: String in WORLD_GUARDED_ROLES:
		world_colors[role] = ensure_contrast_all(
			colors[role] as Color, backgrounds, WORLD_MIN_CONTRAST, toward
		)


## The colour a thing *lying in the dungeon* is drawn in: `get_color()` for anything without a
## world guard, and the `WORLD_GUARDED_ROLES` entry pushed clear of every surface for the seven
## that have one. Every pickup kind reads this - `PickupBase` for gold, hearts and orbs,
## `ItemPickup` for the rarity of a dropped item - and the HUD reads `get_color()`.
func world_color(role: StringName) -> Color:
	return world_colors.get(role, get_color(role))


## `base` darkened by `amount` and pulled `hue_mix` toward `ink`, so a shade keeps the theme's
## cast instead of collapsing to neutral grey.
static func _shade(base: Color, ink: Color, amount: float, hue_mix: float) -> Color:
	return base.darkened(amount).lerp(Color(ink.r, ink.g, ink.b, 1.0), hue_mix)


## Moves `c` away from `other` until the two differ by `ENV_MIN_SEPARATION` in luminance, so
## two environment surfaces can never render as the same material. Returns `c` untouched when
## they are already far enough apart.
static func push_apart(c: Color, other: Color) -> Color:
	var reference := other.get_luminance()
	if absf(c.get_luminance() - reference) >= ENV_MIN_SEPARATION:
		return c
	var down := c.get_luminance() <= reference
	if down and reference < ENV_MIN_SEPARATION * 2.0:
		down = false
	var toward := Color.BLACK if down else Color.WHITE
	var out := c
	for _i in range(32):
		out = out.lerp(toward, 0.08)
		if absf(out.get_luminance() - reference) >= ENV_MIN_SEPARATION:
			break
	return out


static func relative_luminance(c: Color) -> float:
	var lin := func(v: float) -> float:
		return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


static func contrast_ratio(a: Color, b: Color) -> float:
	var la := relative_luminance(a)
	var lb := relative_luminance(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)


## Pushes `fg` toward white or black (away from `bg`) until contrast >= target.
static func ensure_contrast(fg: Color, bg: Color, target: float) -> Color:
	var toward := Color.WHITE if relative_luminance(bg) < 0.5 else Color.BLACK
	return ensure_contrast_toward(fg, bg, target, toward)


## Same guard with the direction pinned. Palette roles are pushed toward the *palette's* own
## extreme rather than away from the one background measured, because the HUD plates they land
## on are translucent: on a light theme every plate composites bright, so a role that is too
## close to its background has to go darker even when that background is itself mid-toned.
## Falls back to the opposite direction when `toward` cannot reach the target at all.
static func ensure_contrast_toward(fg: Color, bg: Color, target: float, toward: Color) -> Color:
	if contrast_ratio(fg, bg) >= target:
		return fg
	if contrast_ratio(toward, bg) < target:
		toward = Color.BLACK if toward == Color.WHITE else Color.WHITE
	var out := fg
	for _i in range(24):
		out = out.lerp(toward, 0.1)
		if contrast_ratio(out, bg) >= target:
			return out
	return toward


## Lowest contrast `c` has against any of `backgrounds` (INF when the list is empty). This is
## the number that decides whether a piece of UI is readable: an element sits on one surface
## at a time, but it does not get to choose which.
static func worst_contrast(c: Color, backgrounds: Array[Color]) -> float:
	var worst := INF
	for bg: Color in backgrounds:
		worst = minf(worst, contrast_ratio(c, bg))
	return worst


## Pushes `fg` until it clears `target` against *every* background it can land on, rather
## than against the one background the caller happened to measure. `toward` is tried first
## (the palette's own extreme), then the other direction. When no colour can clear them all -
## a near-white floor beside a mid-grey wall - the colour with the highest *worst* contrast is
## returned, so a guard that cannot fully pass still lands on the most readable ink available.
static func ensure_contrast_all(
	fg: Color, backgrounds: Array[Color], target: float, toward: Color
) -> Color:
	if backgrounds.is_empty():
		return fg
	var best := fg
	var best_worst := worst_contrast(fg, backgrounds)
	if best_worst >= target:
		return fg
	var other := Color.BLACK if toward == Color.WHITE else Color.WHITE
	for direction: Color in [toward, other]:
		var candidate := fg
		# The endpoint is a candidate in its own right. Twenty-four lerps of a tenth close
		# only 92% of the distance to it, which on a light theme left `loot` at 2.97:1 against
		# the wall while pure black - two steps further on - cleared 3.09:1. A function that
		# promises "the highest worst contrast available" must not stop short of the colour it
		# was walking toward.
		for _i in range(25):
			var worst := worst_contrast(candidate, backgrounds)
			if worst > best_worst:
				best_worst = worst
				best = candidate
			if worst >= target:
				return candidate
			candidate = direction if _i == 23 else candidate.lerp(direction, 0.1)
	return best


## Shallow copy: roles, prop pool and source colours are duplicated, so the copy can be
## retuned per biome and per light level without touching the live Desktop palette.
func copy() -> ThemePalette:
	var p := ThemePalette.new()
	p.name = name
	p.is_light = is_light
	p.colors = colors.duplicate()
	p.prop_pool = prop_pool.duplicate()
	p.source = source.duplicate()
	p.world_colors = world_colors.duplicate()
	return p


## The environment palette one biome draws from (docs §10: "Biomes also pick from different
## subsets of theme keys"). `biome_keys` are `source` keys (e.g. ["orange", "red"]); keys the
## theme does not define are skipped, and an empty result falls back to the full prop pool so
## a sparse theme never loses its accents.
##
## Every colour here comes from the player's theme and nothing else. This function used to
## take the wallpaper analysis as a second argument and mix its dominant colours in; it does
## not any more, and the argument is gone rather than ignored so that nothing can quietly
## start passing one again.
func derive_environment(biome_keys: PackedStringArray = PackedStringArray()) -> ThemePalette:
	var p := copy()
	var pool: Array[Color] = []
	for key: String in biome_keys:
		if source.has(key):
			pool.append(source[key] as Color)
	if pool.is_empty():
		pool = prop_pool.duplicate()
	if not pool.is_empty():
		p.prop_pool = pool
	p._apply_contrast_guard()
	return p


## The palette the dungeon is actually drawn in at a floor light level of `ambient` (docs 3.4).
##
## This is the lighting model, and it is a *ladder*, not a multiplier. Scaling every colour by
## the ambient - which is what a `modulate` does - divides the light out of the relationships
## as well as the light: near black, `floor x 0.55` and `void` land on the same pixel value and
## the room loses its outline. Instead the floor is exposed to a target luminance chosen by the
## light level, and every other surface is placed *relative to that floor* by contrast ratio:
## its own ratio from the theme when the theme already separates them, the ladder's minimum
## step when it does not. Ratios between rungs therefore do not depend on `ambient` at all, so
## floor, wall, wall cap and void stay exactly as separable at the darkest light level as at
## the brightest - only the whole room gets darker.
##
## Feed the result to `TileRamp`/`FloorBuilder` and paint the surround with its `void`; do not
## also dim the nodes.
func light_environment(ambient: float) -> ThemePalette:
	var lit := copy()
	var scales := lit_scales()
	var floor_lum := lit_floor_luminance(ambient, scales)
	for role: String in ENV_ROLES:
		var target := (floor_lum + 0.05) * float(scales[role]) - 0.05
		lit.colors[role] = with_luminance(colors[role], clampf(target, 0.0, 1.0))
	lit.apply_room_cast(self)
	lit._apply_contrast_guard()
	return lit


## Gives the room the theme's colour, loud enough to read.
##
## The exposure model above places the five surfaces by *luminance*, and luminance is all it
## moves: a theme whose three background keys are grey by authorship comes out of it as a grey
## dungeon however well lit, and a theme that authors them at a quarter saturation comes out
## as a quarter-saturated dungeon - which on a dark surface is a tint, not a colour. Testers
## measured the grey ones at 2-6% mean saturation and the owner, from the chair, read the
## coloured ones as "the same look in a different tint". The accent roles carry about 2% of
## the screen on every theme and cannot make up the difference.
##
## The cast is therefore a *coverage* lever, not a tint pass: it hands the room's own surfaces
## the theme's hue at `ROOM_CAST_SATURATION` where the theme authored them grey, and lifts the
## surround - the largest region on screen - to `SURROUND_CAST_SATURATION` on every theme with
## chroma, so the environment is what says which desktop this is. Each surface keeps its own
## hue when it has one (`ROOM_CAST_OWN_CHROMA_MIN`) and takes the theme-wide cast hue when it does
## not - the theme's background cast where it has one, its tell colours where it does not - and
## every surface then keeps that hue. Nothing outside the theme reaches this function: the
## wallpaper used to pull every surface toward its own hue here, and that is what the owner
## removed. Four properties make it safe to run inside the lighting model:
##
## 1. every surface keeps its luminance to the last decimal, so the ladder, the contrast
##    guards and the readability minimums are bit for bit the ones the exposure produced;
## 2. it never changes the hue of a surface that already carries one, and never raises a room
##    surface on a theme past `ROOM_CAST_ENV_FULL`, so nord's slate and tokyo-night's navy stay
##    slate and navy (the prop ladder is built on those colours, see `ROOM_CAST_SATURATION`);
##    and
## 3. it never asks for more chroma than the desktop contains (`ROOM_CAST_SOURCE_FULL`), so a
##    greyscale theme keeps a greyscale dungeon rather than being handed an invented hue; and
## 4. every hue in it came from the player's theme, so the dungeon is the colour of the
##    desktop they chose and nothing else can move it.
##
## A light theme's paper floor is close enough to white that no colour of that luminance can
## be very saturated; there the cast lands on the walls, the caps and the surround, and the
## floor takes what physics leaves it. That is a real limit of a near-white surface, not a
## tuning choice - see docs §3.2.
func apply_room_cast(unlit: ThemePalette = null) -> void:
	var cast := room_cast()
	if cast.a <= 0.0:
		return
	# Whether a surface's own hue means anything is a question about the colour the *theme*
	# authored, not about the one the exposure produced: `with_luminance` keeps a hue exactly,
	# so a near-black's rounding error arrives at the floor's luminance as a real colour.
	var source := unlit if unlit != null else self
	var available := clampf(cast.s / ROOM_CAST_SOURCE_FULL, 0.0, 1.0)
	var room_target := ROOM_CAST_SATURATION * available
	if environment_saturation() >= ROOM_CAST_ENV_FULL:
		room_target = 0.0
	for role: String in ENV_ROLES:
		var c: Color = colors[role]
		var own: Color = source.colors.get(role, c)
		var hue := c.h if chroma_of(own) >= ROOM_CAST_OWN_CHROMA_MIN else cast.h
		var target := SURROUND_CAST_SATURATION * available if role == "void" else room_target
		colors[role] = cast_toward(c, hue, target)


## A colour's absolute chroma: the span between its brightest and darkest channel, 0 for any
## grey at any brightness. Unlike HSV saturation it does not grow as a colour approaches black,
## which is what makes it the honest answer to "does this colour have a hue at all".
static func chroma_of(c: Color) -> float:
	return c.s * c.v


## Mean HSV saturation of the five surfaces the dungeon is painted in. This is the number that
## decides whether a theme colours its own room or renders as greyscale.
func environment_saturation() -> float:
	var total := 0.0
	for role: String in ENV_ROLES:
		total += (colors[role] as Color).s
	return total / float(ENV_ROLES.size())


## The hue the room is washed toward and the chroma the theme can back it with, as a colour
## whose `h` is the hue and whose `s` is that backing. Alpha 0 means the theme has no hue
## anywhere and the dungeon stays exactly as grey as the desktop is.
##
## The environment's own cast wins when it has one, however faint: catppuccin-latte authors a
## blue-grey paper at 4% saturation, and gruvbox - whose `background` is a pure `#282828` -
## still carries a warm grey in `muted`, so its crypt comes out as warm sandstone rather than
## as some colour chosen for it. Only a theme with no chroma in any of the five surfaces asks
## the tell colours instead, because a theme that keeps all of its colour in its accents is
## still that colour. The *strength* is the larger of the two, so a faint cast is still backed
## by vivid accents - what the environment decides is the hue, not how much of it there is.
func room_cast() -> Color:
	var env := _hue_mean(ENV_ROLES)
	var tell := _hue_mean(ROOM_CAST_TELL_ROLES)
	if env.a <= 0.0 and tell.a <= 0.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	var hue := env.h if env.a > 0.0 else tell.h
	return Color.from_hsv(hue, maxf(env.s, tell.s), 1.0, 1.0)


## Saturation-weighted circular mean of `role_names`, as `Color(hue, mean saturation, 1, 1)`.
## The mean is taken on the hue circle, so a theme whose accents straddle the 0/360 seam is
## not averaged into its complement. Alpha 0 when none of the roles carries any chroma.
func _hue_mean(role_names: PackedStringArray) -> Color:
	var list: Array[Color] = []
	for role: String in role_names:
		list.append(colors.get(role, Color.BLACK))
	return hue_mean_of(list)


## What a set of colours *is* as one hue, with how much saturation stands behind it, as
## `Color(hue, mean saturation, 1, 1)`; alpha 0 when nothing in the list carries chroma.
##
## The two numbers are weighted differently on purpose. The **hue** is a circular mean weighted
## by absolute chroma (`chroma_of`), so a colour that has a hue speaks and a near-black that
## merely reports one in HSV does not - the same rounding error that made the owner's floor
## yellow also voted on the theme-wide cast hue, twice over, from `floor` and from `void`.
## Averaging on the circle also keeps a set straddling the 0/360 seam off its own complement.
## The **saturation** is the plain HSV mean, unchanged: it answers "how much colour is there to
## work with", which is a question about the surfaces as they will be drawn.
static func hue_mean_of(list: Array[Color]) -> Color:
	var x := 0.0
	var y := 0.0
	var sum := 0.0
	for c: Color in list:
		var angle := c.h * TAU
		var weight := chroma_of(c)
		x += cos(angle) * weight
		y += sin(angle) * weight
		sum += c.s
	var mean := sum / float(maxi(list.size(), 1))
	if mean <= 0.0 or is_zero_approx(x) and is_zero_approx(y):
		return Color(0.0, 0.0, 0.0, 0.0)
	return Color.from_hsv(fposmod(atan2(y, x) / TAU, 1.0), mean, 1.0, 1.0)


## `c` given `hue` at no less than `saturation`, at exactly the luminance it arrives with - so a
## surface gains colour without moving one step of the depth ladder it sits on. A surface that
## already carries more chroma than asked keeps it, and its hue is still set, so a caller that
## only wants the hue fixed can ask for a saturation the surface already clears.
static func cast_toward(c: Color, hue: float, saturation: float) -> Color:
	var s := maxf(c.s, saturation)
	if s <= 0.0:
		return c
	if c.s >= saturation and TileRamp.hue_distance(c.h, hue) < 0.001:
		return c
	var lum := relative_luminance(c)
	var out := Color.from_hsv(hue, s, maxf(c.v, 0.04), c.a)
	return with_luminance(out, lum)


## `from` moved `t` (0..1) of the way along the shortest arc of the hue circle toward `to`,
## in turns. Shared by the room cast and the dungeon lights.
static func rotate_hue(from: float, to: float, t: float) -> float:
	return hue_toward_capped(from, to, t, 1.0)


## `rotate_hue` with a ceiling: the result is never further than `max_arc` turns from `from`,
## however far round the circle `to` is. A fraction of an unbounded arc is not a bounded
## tint - it is a hue swap whenever the two hues are far apart - so every lever that nudges a
## surface toward a colour the theme did not choose goes through this.
static func hue_toward_capped(from: float, to: float, t: float, max_arc: float) -> float:
	var a := fposmod(from, 1.0)
	var d := fposmod(to, 1.0) - a
	if d > 0.5:
		d -= 1.0
	elif d < -0.5:
		d += 1.0
	d = clampf(d * clampf(t, 0.0, 1.0), -max_arc, max_arc)
	return fposmod(a + d, 1.0)


## Each environment surface's place on the lit ladder, as `(L + 0.05) / (L_floor + 0.05)`.
## Working in this space makes the model exact: the contrast ratio between two surfaces is the
## ratio of their two scales, whatever luminance the floor ends up at.
func lit_scales() -> Dictionary:
	var out: Dictionary = {"floor": 1.0}
	var below := LIT_LADDER_LIGHT_BELOW if is_light else LIT_LADDER_DARK_BELOW
	var below_steps := LIT_LADDER_LIGHT_BELOW_STEPS if is_light else LIT_LADDER_DARK_BELOW_STEPS
	var above := PackedStringArray() if is_light else LIT_LADDER_DARK_ABOVE
	var above_steps := PackedFloat32Array() if is_light else LIT_LADDER_DARK_ABOVE_STEPS
	var floor_c: Color = colors["floor"]
	var k := 1.0
	for i in range(below.size()):
		k = minf(1.0 / contrast_ratio(colors[below[i]], floor_c), k / below_steps[i])
		out[below[i]] = k
	k = 1.0
	for i in range(above.size()):
		k = maxf(contrast_ratio(colors[above[i]], floor_c), k * above_steps[i])
		out[above[i]] = k
	out["floor_alt"] = _lit_detail_scale(float(out["void" if is_light else "wall_top"]))
	return out


## Floor detail sits between the floor and whichever rung is next to it, so a floor variant
## tile reads as the same material seen differently rather than as a second surface.
func _lit_detail_scale(neighbour: float) -> float:
	var theme := contrast_ratio(colors["floor_alt"], colors["floor"])
	var low := LIT_DETAIL_MIN_RATIO
	var high := neighbour / LIT_DETAIL_NEIGHBOUR_RATIO
	var want := maxf(theme, 1.0)
	if is_light:
		low = neighbour * LIT_DETAIL_NEIGHBOUR_RATIO
		high = 1.0 / LIT_DETAIL_MIN_RATIO
		want = 1.0 / want
	if low > high:
		low = sqrt(neighbour)
		high = low
	return clampf(want, low, high)


## Where this theme sits between the darkest and the brightest dark-theme background, as 0..1.
## This is the number that keeps a theme recognisable in its own dungeon: nord's slate and
## tokyo-night's navy are two and a half stops apart in the terminal, and a lighting model that
## exposes both to one luminance throws that away and leaves hue as the only tell.
##
## Light themes always answer 1.0 - their paper floor is the exposure.
func theme_light_position() -> float:
	if is_light:
		return 1.0
	var span := LIT_THEME_LUMINANCE_HIGH - LIT_THEME_LUMINANCE_LOW
	if span <= 0.0:
		return 0.0
	var base := relative_luminance(colors["floor"])
	var raw := clampf((base - LIT_THEME_LUMINANCE_LOW) / span, 0.0, 1.0)
	return pow(raw, LIT_IDENTITY_CURVE)


## Relative luminance the lit floor is exposed to: the theme's own place in the band, scaled by
## the wallpaper's light level, and never below the readability minimum.
##
## `scales` bounds it at both ends. The bottom bound is not "the darkest rung stays above
## black": that is satisfied by a surround at L=0.0007, which is black to anything with eyes
## and to every theme alike. It is "the darkest rung stays above `LIT_SURROUND_LUMINANCE_MIN`",
## so the biggest region on screen still carries the theme's colour. The top bound is the
## brightest rung staying under white, or the ladder's ratios would clip on the way into a
## Color.
func lit_floor_luminance(ambient: float, scales: Dictionary = {}) -> float:
	var known := scales if not scales.is_empty() else lit_scales()
	var span := WallpaperAnalyzer.AMBIENT_MAX - WallpaperAnalyzer.AMBIENT_MIN
	var t := (
		clampf((ambient - WallpaperAnalyzer.AMBIENT_MIN) / span, 0.0, 1.0) if span > 0.0 else 1.0
	)
	var base := relative_luminance(colors["floor"])
	var target := 0.0
	if is_light:
		target = lerpf(LIT_FLOOR_LUMINANCE_LIGHT_MIN, maxf(base, LIT_FLOOR_LUMINANCE_LIGHT_MIN), t)
	else:
		# The band starts one dim above the minimum, so the darkest theme at the darkest
		# wallpaper lands *on* the guarantee rather than under it - and every step of the
		# wallpaper lever above that still moves the floor.
		var own := lerpf(
			LIT_FLOOR_LUMINANCE_MIN / LIT_AMBIENT_DIM,
			LIT_FLOOR_LUMINANCE_MAX,
			theme_light_position()
		)
		target = maxf(own, base) * lerpf(LIT_AMBIENT_DIM, 1.0, t)
	var lowest := 1.0
	var highest := 1.0
	for role: String in ENV_ROLES:
		lowest = minf(lowest, float(known[role]))
		highest = maxf(highest, float(known[role]))
	var low := (LIT_SURROUND_LUMINANCE_MIN + 0.05) / lowest - 0.05
	if not is_light:
		low = maxf(low, LIT_FLOOR_LUMINANCE_MIN)
	return clampf(target, low, maxf(low, 1.05 / highest - 0.05))


## `c` re-exposed to a target relative luminance. The linear channels are scaled, which keeps
## the hue and the chroma ratios exactly - the colour is lit differently, not tinted - and only
## when that would clip a channel is it taken toward white instead.
static func with_luminance(c: Color, target_luminance: float) -> Color:
	var target := clampf(target_luminance, 0.0, 1.0)
	var current := relative_luminance(c)
	if absf(current - target) < 0.00005:
		return c
	if current > 0.0:
		var linear := Color(c.r, c.g, c.b, 1.0).srgb_to_linear()
		var scale := target / current
		var scaled := Color(linear.r * scale, linear.g * scale, linear.b * scale, 1.0)
		if maxf(scaled.r, maxf(scaled.g, scaled.b)) <= 1.0:
			var out := scaled.linear_to_srgb()
			return Color(out.r, out.g, out.b, c.a)
	return _bisect_luminance(c, target)


static func _bisect_luminance(c: Color, target: float) -> Color:
	var toward := Color.WHITE if relative_luminance(c) < target else Color.BLACK
	var rising := toward == Color.WHITE
	var low := 0.0
	var high := 1.0
	for _i in range(28):
		var mid := (low + high) * 0.5
		var below := relative_luminance(c.lerp(toward, mid)) < target
		if below == rising:
			low = mid
		else:
			high = mid
	var mixed := c.lerp(toward, (low + high) * 0.5)
	return Color(mixed.r, mixed.g, mixed.b, c.a)


## Moves `c` away from `other` until the pair reaches `ratio` contrast, keeping the side of
## `other` it is already on when it can get there and turning round when it cannot. This is the
## contrast-ratio counterpart of `push_apart`, which measures a gamma-encoded luminance gap and
## so cannot tell "two near-black surfaces" from "one surface".
static func separate(c: Color, other: Color, ratio: float) -> Color:
	if contrast_ratio(c, other) >= ratio:
		return c
	var reference := relative_luminance(other) + 0.05
	var down := relative_luminance(c) <= relative_luminance(other)
	var target := reference / ratio - 0.05 if down else reference * ratio - 0.05
	if target < 0.0 or target > 1.0:
		target = reference * ratio - 0.05 if down else reference / ratio - 0.05
	return with_luminance(c, clampf(target, 0.0, 1.0))
