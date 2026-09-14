## Shape and legibility rules for the little health bars over enemies
## (`data/enemies/health_bars.tres`).
##
## Every enemy carries one now, not just elites and bosses, so the numbers that decide whether
## forty of them read as a fight or as clutter are data rather than constants in a draw call:
## how wide the bar is, how long a damaged mook keeps showing it, and the contrast ratios the
## palette-derived colours are held to on any theme.
class_name EnemyHpBarStyle
extends Resource

const PATH := "res://data/enemies/health_bars.tres"
## `EnemyBase`'s sprite offset: how far below the node origin a sheet's bottom edge is drawn.
const SPRITE_FOOT_OFFSET := 4.0

static var _cached: EnemyHpBarStyle

## Bar width (px) over a 16 px enemy. A 16 px body with a 14 px bar over it reads as belonging
## to that body; the 24 px bar elites used to wear made a mook look like a boss.
@export var small_width: float = 14.0
## Bar width (px) over a 32 px enemy.
@export var large_width: float = 22.0
## Multiplier on the width for an elite or a boss, which are meant to look heavier.
@export var elite_width_scale: float = 1.35
## Bar height (px) for an ordinary enemy.
@export var height: float = 2.0
## Bar height (px) for an elite or a boss.
@export var elite_height: float = 3.0
## Rim thickness (px) drawn around the bar.
@export var border: float = 1.0
## Gap (px) between the top of the sprite and the bottom of the bar.
@export var gap: float = 4.0
## Seconds an ordinary enemy keeps its bar up after the last hit it took. Elites and bosses
## ignore this and wear theirs for the whole fight.
@export var hide_delay: float = 4.0
## Seconds the bar takes to fade out when the delay runs out.
@export var fade_time: float = 0.35
## Opacity of the rim the bar is drawn inside, which is what separates it from the floor. Not
## fully opaque (a solid black box over a dark floor is its own kind of clutter), but close
## enough that the contrast the guard below computes is close to the one that is drawn.
@export_range(0.0, 1.0, 0.01) var backing_alpha: float = 0.85
## Contrast the empty part of the bar is held to against the rim it is drawn inside, so
## "gone" reads as a channel and not as part of the outline.
@export var track_contrast: float = 2.0
## Contrast the filled part is held to against both the empty part and the rim. This is the
## one that has to survive `white` and `catppuccin-latte`, where the theme's own `danger` is
## a mid-toned red against pale everything.
@export var fill_contrast: float = 3.0
## Contrast at least one of the bar's two elements must have against any surface it floats
## over. A bar is a dark rim around a bright fill on purpose: on a dark floor the fill is what
## separates it from the world, on a light one the rim is, and neither theme needs the other's
## answer. Requiring *both* to clear every surface is the over-constraint that flattens a bar
## into a grey smear on half the themes. 2.75 rather than a round 3 because that is what the
## six shipped themes actually deliver: the worst case measured across all of them is a
## gruvbox bar over a gruvbox wall cap at 2.84:1, and a number chosen above the evidence would
## be a test that fails for being ambitious rather than for a regression.
@export var world_contrast: float = 2.75


## The shipped style, loaded once; a fresh default when the resource is missing.
static func shared() -> EnemyHpBarStyle:
	if _cached != null:
		return _cached
	if ResourceLoader.exists(PATH):
		_cached = load(PATH) as EnemyHpBarStyle
	if _cached == null:
		_cached = EnemyHpBarStyle.new()
	return _cached


## Bar width for a sprite of `sprite_size` px, heavier for an elite or boss.
func width_for(sprite_size: int, heavy: bool) -> float:
	var base := large_width if sprite_size >= 32 else small_width
	return base * (elite_width_scale if heavy else 1.0)


func height_for(heavy: bool) -> float:
	return elite_height if heavy else height


## Where the bar sits above the body: clear of the sprite's *drawn* top edge by `gap`, so it
## never covers the enemy and never reaches down into the telegraph ring drawn under it.
##
## `EnemyBase` offsets a sheet by `-size / 2 + SPRITE_FOOT_OFFSET` so the feet land on the
## body's origin, which puts the top of a 16 px enemy at -12 and not at -16. Measuring from
## the size alone left an eight-pixel hole between a mook and its own bar.
func anchor_for(sprite_size: int, heavy: bool) -> float:
	var sprite_top := SPRITE_FOOT_OFFSET - float(sprite_size)
	return sprite_top - gap - height_for(heavy) - border


## The rim the bar is drawn inside: the theme's darkest ink.
static func backing_for(palette: ThemePalette, style: EnemyHpBarStyle) -> Color:
	if palette == null:
		return Color(0.0, 0.0, 0.0, 0.6)
	var ink := palette.outline_color()
	ink.a = style.backing_alpha if style != null else 0.72
	return ink


## The empty part of the bar: the rim carried part of the way toward the theme's dim text, and
## no further than that. It used to be `text_dim` itself, which on a theme whose dim text is
## pale left the channel brighter than the health in it — and then squeezed the fill between a
## bright track and a dark rim until the guard could not satisfy either.
static func track_for(palette: ThemePalette, style: EnemyHpBarStyle) -> Color:
	if palette == null:
		return Color(0.2, 0.2, 0.25)
	var rim := opaque_backing(palette, style)
	var dim := palette.get_color(&"text_dim")
	var target := style.track_contrast if style != null else 2.0
	return ThemePalette.ensure_contrast_toward(rim.lerp(dim, 0.45), rim, target, dim)


## The remaining health, in the theme's `danger`, pushed until it clears both the empty part
## of the bar and the rim around it. Guarding against both is the point: a theme whose danger
## sits between them would otherwise pass one check and vanish against the other.
static func fill_for(palette: ThemePalette, style: EnemyHpBarStyle) -> Color:
	if palette == null:
		return Color(0.9, 0.3, 0.3)
	var rim := opaque_backing(palette, style)
	var backgrounds: Array[Color] = [track_for(palette, style), rim]
	var target := style.fill_contrast if style != null else 3.0
	var toward := Color.WHITE if ThemePalette.relative_luminance(rim) < 0.5 else Color.BLACK
	return ThemePalette.ensure_contrast_all(
		palette.get_color(&"danger"), backgrounds, target, toward
	)


## The rim as the contrast maths sees it: the same colour with its transparency taken out.
static func opaque_backing(palette: ThemePalette, style: EnemyHpBarStyle) -> Color:
	var rim := backing_for(palette, style)
	rim.a = 1.0
	return rim


## How well the whole widget separates from one surface it can float over: the better of its
## two elements, because they have opposite polarity by design.
static func world_separation(palette: ThemePalette, style: EnemyHpBarStyle, bg: Color) -> float:
	var fill := fill_for(palette, style)
	var rim := opaque_backing(palette, style)
	return maxf(ThemePalette.contrast_ratio(fill, bg), ThemePalette.contrast_ratio(rim, bg))
