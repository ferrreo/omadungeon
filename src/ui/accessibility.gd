## Accessibility policy for the whole UI: the colour-blind glyph set, the reduced-flash and
## reduce-motion switches, and the shape vocabulary every widget draws from.
##
## Three rules hold everywhere:
##   * colour is never the only channel — `glyphs()` turns on a redundant shape + short text
##     tag for rarity, status effects and danger (docs §11 "colour-blind glyph mode");
##   * `reduce_motion()` scales every animation duration/amplitude through `motion()`, so a
##     widget writes `Accessibility.motion(0.18)` instead of a bare literal and gets 0 for
##     free when the option is on;
##   * `reduced_flash()` scales every strobe/pulse/flash amplitude through `flash()`.
##
## Everything here is static and reads `GameState.settings`; there is no instance to own.
class_name Accessibility
extends RefCounted

## Shapes the badge drawer knows. Chosen to stay apart at 6-8 px, which is all a 480x270
## HUD ever gives a badge.
enum Shape { DOT, RING, DIAMOND, TRIANGLE, SQUARE, STAR, CHEVRON, CROSS, BAR, HATCH }

const SETTING_GLYPHS := "colorblind_glyphs"
const SETTING_REDUCED_FLASH := "reduced_flash"
const SETTING_REDUCE_MOTION := "reduce_motion"

## Item rarity (ItemInstance.Rarity order) -> pip text. Counting pips needs no colour.
const RARITY_MARKS: PackedStringArray = ["*", "**", "***", "****"]
## Item rarity -> badge shape.
const RARITY_SHAPES: Array[int] = [Shape.DOT, Shape.DIAMOND, Shape.TRIANGLE, Shape.STAR]

## StatusEffect.Kind order -> three-letter tag. Tags, not colours, are what a player reads.
const STATUS_MARKS: PackedStringArray = [
	"BRN", "FRZ", "SHK", "PSN", "STN", "TNT", "SLW", "HST", "WKN", "EMP"
]
## StatusEffect.Kind order -> badge shape.
const STATUS_SHAPES: Array[int] = [
	Shape.TRIANGLE,
	Shape.DIAMOND,
	Shape.CHEVRON,
	Shape.DOT,
	Shape.CROSS,
	Shape.RING,
	Shape.BAR,
	Shape.STAR,
	Shape.HATCH,
	Shape.SQUARE,
]
## Status kinds that are bad news for whoever carries them (everything but HASTE/EMPOWER).
const HARMFUL_STATUSES: Array[int] = [0, 1, 2, 3, 4, 5, 6, 8]

## StatusEffect.Kind order -> the palette role its chip is tinted with. Ten kinds, ten roles:
## collapsing them into "danger" and "heal" made a burn, a stun and a poison the same red
## square, so the HUD could say how many things were on the player but never what.
## Every role here is one of `ThemePalette.ROLES`, so a theme swap moves them all together.
const STATUS_ROLES: Array[StringName] = [
	&"heat",  # BURN    - orange
	&"cold",  # FROST   - cyan
	&"loot",  # SHOCK   - yellow
	&"magic",  # POISON  - magenta
	&"text_bright",  # STUN    - white
	&"danger",  # TAUNT   - red
	&"earth",  # SLOW    - brown
	&"accent",  # HASTE   - blue
	&"text_dim",  # WEAKEN  - grey
	&"heal",  # EMPOWER - green
]

## Minimap.RoomKind order -> the shape stamped inside a visited room when glyphs are on.
## COMBAT and START stay blank: the common case must not turn the map into confetti.
const ROOM_SHAPES: Dictionary = {
	2: Shape.CHEVRON,  # ELITE
	3: Shape.CROSS,  # TRAP
	4: Shape.DIAMOND,  # TREASURE
	5: Shape.RING,  # ALTAR
	6: Shape.SQUARE,  # SHOP
	7: Shape.DOT,  # SHRINE
	8: Shape.BAR,  # STAIRS
	9: Shape.STAR,  # BOSS
}

## Smallest badge that still reads; below this the drawer falls back to a filled square.
const MIN_SHAPE := 4.0
## Spacing of the hatch pattern danger states paint over a bar, in pixels.
const HATCH_STEP := 4.0


## Whether the redundant (non-colour) glyph channel is on.
static func glyphs() -> bool:
	return bool(GameState.settings.get(SETTING_GLYPHS, false))


## Whether strobes, pulses and hit flashes must be damped.
static func reduced_flash() -> bool:
	return bool(GameState.settings.get(SETTING_REDUCED_FLASH, false))


## Whether animation (movement, scaling, scrolling, screen shake, hit stop) must be off.
static func reduce_motion() -> bool:
	return bool(GameState.settings.get(SETTING_REDUCE_MOTION, false))


## `value` scaled by the motion policy: 0.0 while reduce-motion is on, unchanged otherwise.
## Use it for tween durations, travel distances and scale punches.
static func motion(value: float) -> float:
	return 0.0 if reduce_motion() else value


## `value` scaled by the flash policy: reduced-flash keeps a tenth of the amplitude (enough
## to see *that* something happened, not enough to strobe), reduce-motion removes it.
static func flash(value: float) -> float:
	if reduce_motion():
		return 0.0
	return value * 0.1 if reduced_flash() else value


## True when a widget should animate at all. Cheaper than tweening for 0 seconds.
static func animates() -> bool:
	return not reduce_motion()


## Pip text for an item rarity, or "" when the glyph channel is off.
static func rarity_mark(rarity: int) -> String:
	if not glyphs():
		return ""
	return rarity_mark_always(rarity)


## Pip text for an item rarity regardless of the setting (for tooltips and tests).
static func rarity_mark_always(rarity: int) -> String:
	return RARITY_MARKS[clampi(rarity, 0, RARITY_MARKS.size() - 1)]


static func rarity_shape(rarity: int) -> int:
	return RARITY_SHAPES[clampi(rarity, 0, RARITY_SHAPES.size() - 1)]


## Three-letter tag for a StatusEffect.Kind ("BRN", "FRZ", ...).
static func status_mark(kind: int) -> String:
	return STATUS_MARKS[clampi(kind, 0, STATUS_MARKS.size() - 1)]


static func status_shape(kind: int) -> int:
	return STATUS_SHAPES[clampi(kind, 0, STATUS_SHAPES.size() - 1)]


## Palette role a status badge is tinted with: one role per kind (`STATUS_ROLES`), so burn,
## frost and poison are three colours rather than three copies of red. The three-letter tag
## still carries the meaning on its own; the hue is the fast channel, not the only one.
static func status_role(kind: int) -> StringName:
	return STATUS_ROLES[clampi(kind, 0, STATUS_ROLES.size() - 1)]


## Whether `kind` hurts whoever carries it. Kept separate from `status_role` now that the
## role is per-kind: "is this bad?" is still a question widgets ask.
static func status_is_harmful(kind: int) -> bool:
	return HARMFUL_STATUSES.has(kind)


## Shape stamped into a minimap room of `room_kind`, or -1 when that kind gets none.
static func room_shape(room_kind: int) -> int:
	return int(ROOM_SHAPES.get(room_kind, -1))


## Draws `shape` centred in `rect` on `item`. Filled shapes use `color`; outline shapes use
## `width` px strokes. Anything smaller than MIN_SHAPE degenerates to a filled square, which
## is still a mark and never disappears.
static func draw_shape(
	item: CanvasItem, rect: Rect2, shape: int, color: Color, width: float = 1.0
) -> void:
	if item == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var side := minf(rect.size.x, rect.size.y)
	var centre := rect.get_center().floor() + Vector2(0.5, 0.5)
	if side < MIN_SHAPE:
		item.draw_rect(Rect2(centre - Vector2(1, 1), Vector2(2, 2)), color)
		return
	var r := side * 0.5 - 0.5
	match shape:
		Shape.DOT:
			item.draw_circle(centre, maxf(1.0, r * 0.62), color)
		Shape.RING:
			item.draw_arc(centre, maxf(1.0, r * 0.72), 0.0, TAU, 12, color, width)
		Shape.DIAMOND:
			item.draw_colored_polygon(_diamond(centre, r), color)
		Shape.TRIANGLE:
			item.draw_colored_polygon(_triangle(centre, r), color)
		Shape.SQUARE:
			item.draw_rect(Rect2(centre - Vector2(r, r) * 0.72, Vector2(r, r) * 1.44), color)
		Shape.STAR:
			item.draw_colored_polygon(_star(centre, r), color)
		Shape.CHEVRON:
			item.draw_polyline(_chevron(centre, r), color, width)
		Shape.CROSS:
			item.draw_line(centre - Vector2(r, r) * 0.7, centre + Vector2(r, r) * 0.7, color, width)
			item.draw_line(
				centre + Vector2(-r, r) * 0.7, centre + Vector2(r, -r) * 0.7, color, width
			)
		Shape.BAR:
			item.draw_rect(
				Rect2(centre - Vector2(r * 0.8, width * 0.5), Vector2(r * 1.6, width)), color
			)
		Shape.HATCH:
			draw_hatch(item, rect, color, width)
		_:
			item.draw_rect(Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0), color, false, width)


## Diagonal hatching across `rect`: the non-colour channel for "this bar is in danger".
static func draw_hatch(item: CanvasItem, rect: Rect2, color: Color, width: float = 1.0) -> void:
	if item == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var span := rect.size.x + rect.size.y
	var x := rect.position.x - rect.size.y
	while x < rect.position.x + span:
		var a := Vector2(maxf(x, rect.position.x), rect.position.y)
		var b := Vector2(x + rect.size.y, rect.end.y)
		if b.x > rect.end.x:
			b = Vector2(rect.end.x, rect.position.y + (rect.end.x - x))
		if a.x < rect.end.x and b.y > rect.position.y:
			item.draw_line(a, b, color, width)
		x += HATCH_STEP


static func _diamond(centre: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array(
		[
			centre + Vector2(0, -r),
			centre + Vector2(r, 0),
			centre + Vector2(0, r),
			centre + Vector2(-r, 0)
		]
	)


static func _triangle(centre: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array(
		[centre + Vector2(0, -r), centre + Vector2(r, r * 0.8), centre + Vector2(-r, r * 0.8)]
	)


static func _chevron(centre: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array(
		[centre + Vector2(-r, r * 0.5), centre + Vector2(0, -r * 0.6), centre + Vector2(r, r * 0.5)]
	)


static func _star(centre: Vector2, r: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 8:
		var angle := -PI * 0.5 + TAU * float(i) / 8.0
		var radius := r if i % 2 == 0 else r * 0.42
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points
