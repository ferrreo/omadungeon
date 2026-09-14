## The "this one is you" ring under the player's feet, plus a contact shadow.
##
## Three testers could not find their own character in a four-enemy scrum: everything on
## screen is a 16 px figure of roughly the same brightness, and a hit flash makes them all the
## same colour for a moment. No amount of sprite work fixes that, because the answer has to
## survive being overlapped. A ground ring does: it is drawn under every body, it is the only
## ring on the floor, and it is in the theme's own accent guarded against the floor, so it
## reads on a black crypt and on white paper alike (docs §1 pillar 1, docs §3 pillar 3).
##
## The shadow is doing readability work too, not decoration: a figure with a contact shadow
## sits *on* the floor instead of floating in the same plane as the tiles behind it.
class_name PlayerMarker
extends Node2D

## Ring radii in px. Wider than the 16 px sprite so it is never completely hidden by a body
## standing on top of the player, flat enough to read as ground rather than as a bubble.
const RADIUS := Vector2(8.5, 3.5)
## Contact shadow radii in px.
const SHADOW_RADIUS := Vector2(5.5, 2.2)
## Px below the body origin the ring and shadow sit (the sprite's feet).
const FOOT_Y := 5.0
## Points on the ellipse. 20 is smooth at this size and cheap.
const SEGMENTS := 20
## Contrast the ring keeps against the theme's own `floor` role.
const RING_CONTRAST := 4.5
## Contrast it keeps against the floor the dungeon is *painted* in - the role run through
## `ThemePalette.light_environment`, which is a different colour and was never checked. A ring
## with hue is told apart by two channels, so it needs less of the second one; a ring with no
## hue has only value to work with, and the `white` fixture's accent is a grey. That split is
## the whole point: asking every theme for 4.5 here pushes four dark themes' accents to the
## same near-white pastel, which trades pillar 3 for pillar 1 instead of fixing anything.
const LIT_RING_CONTRAST := 3.0
const LIT_RING_CONTRAST_GREY := 4.5
## Chroma (max channel minus min channel) below which a ring counts as grey.
const RING_CHROMA_MIN := 0.15
## Passes the lit-floor guard may take. It converges in one or two; the rest is slack.
const GUARD_PASSES := 6
## Alpha of the halo drawn just outside the ring, so the ring reads on a light floor too.
const HALO_ALPHA := 0.55
## Contrast the halo must keep against the ring itself. A monochrome theme can hand us an
## accent that is nearly the same tone as its own ink, and a halo that close just thickens the
## ring into an unreadable blob.
const HALO_CONTRAST := 2.0
## Alpha of the contact shadow.
const SHADOW_ALPHA := 0.3

var _ring: Color = Color.WHITE
var _halo: Color = Color(0, 0, 0, HALO_ALPHA)
var _shadow: Color = Color(0, 0, 0, SHADOW_ALPHA)


func _ready() -> void:
	# Not a negative z: the dungeon's tile layers sit at z 0 and are opaque, so anything below
	# them is simply not drawn. The marker keeps z 0 and is ordered *before* the sprite among
	# its owner's children instead, which puts it under the body and over the floor.
	z_index = 0
	z_as_relative = true
	EventBus.palette_changed.connect(_on_palette_changed)
	retint(Desktop.palette if Desktop != null else null)


## Recolours the ring from `palette`. Safe with null (keeps the current colours).
func retint(palette: ThemePalette) -> void:
	if palette == null:
		return
	_ring = ring_color(palette)
	_halo = halo_color(palette)
	_shadow = palette.outline_color()
	_shadow.a = SHADOW_ALPHA
	queue_redraw()


## The floors the dungeon is actually painted in, at both ends of the wallpaper's ambient band.
## The `floor` role is not one of them: the world is drawn through `ThemePalette
## .light_environment`, and on catppuccin-latte the ring measured 3.93:1 against the surface it
## was standing on while clearing a 4.5 check against a colour nothing ever draws.
static func lit_floors(palette: ThemePalette) -> Array[Color]:
	var out: Array[Color] = []
	for ambient: float in [WallpaperAnalyzer.AMBIENT_MIN, WallpaperAnalyzer.AMBIENT_MAX]:
		out.append(palette.light_environment(ambient).get_color(&"floor"))
	return out


## Chroma of `c`: how much hue it has to be told apart by, 0 for any grey.
static func chroma(c: Color) -> float:
	return maxf(maxf(c.r, c.g), c.b) - minf(minf(c.r, c.g), c.b)


## The ring colour for `palette`: the theme's accent, cleared against the theme's floor role and
## then against the floors the dungeon actually paints. Theme-derived on purpose - the marker
## must not be one fixed colour bolted onto every theme (docs §3), which is why the second
## guard moves luminance only and leaves the accent's hue and chroma exactly where they were.
static func ring_color(palette: ThemePalette) -> Color:
	if palette == null:
		return Color.WHITE
	var ring := ThemePalette.ensure_contrast(
		palette.get_color(&"accent"), palette.get_color(&"floor"), RING_CONTRAST
	)
	var target := LIT_RING_CONTRAST_GREY if chroma(ring) < RING_CHROMA_MIN else LIT_RING_CONTRAST
	return _clear_floors(ring, lit_floors(palette), target)


## `ring` re-exposed until it clears `target` against every colour in `floors`, keeping its hue
## and chroma: `ThemePalette.with_luminance` scales the linear channels, so the ring is lit
## differently rather than washed toward white, and two themes whose accents are close stay as
## far apart afterwards as they were before.
static func _clear_floors(ring: Color, floors: Array[Color], target: float) -> Color:
	var out := ring
	for _pass in range(GUARD_PASSES):
		var worst := floors[0]
		for candidate: Color in floors:
			if (
				ThemePalette.contrast_ratio(out, candidate)
				< ThemePalette.contrast_ratio(out, worst)
			):
				worst = candidate
		if ThemePalette.contrast_ratio(out, worst) >= target:
			return out
		var floor_lum := ThemePalette.relative_luminance(worst)
		var ring_lum := ThemePalette.relative_luminance(out)
		var want := (
			target * (floor_lum + 0.05) - 0.05
			if ring_lum >= floor_lum
			else (floor_lum + 0.05) / target - 0.05
		)
		out = ThemePalette.with_luminance(out, clampf(want, 0.0, 1.0))
	return out


## The halo just outside the ring: the palette's ink, or the opposite pole when that ink is
## the same tone as the ring (a theme whose accent is a grey).
static func halo_color(palette: ThemePalette) -> Color:
	if palette == null:
		return Color(0, 0, 0, HALO_ALPHA)
	var ring := ring_color(palette)
	var halo := palette.outline_color()
	if ThemePalette.contrast_ratio(halo, ring) < HALO_CONTRAST:
		halo = Color.WHITE if ThemePalette.relative_luminance(ring) < 0.5 else Color.BLACK
	halo.a = HALO_ALPHA
	return halo


func _on_palette_changed(palette: ThemePalette) -> void:
	retint(palette)


func _draw() -> void:
	var centre := Vector2(0.0, FOOT_Y)
	draw_colored_polygon(_ellipse(centre, SHADOW_RADIUS), _shadow)
	draw_polyline(_ellipse(centre, RADIUS + Vector2.ONE, true), _halo, 1.0)
	draw_polyline(_ellipse(centre, RADIUS, true), _ring, 1.0)


static func _ellipse(centre: Vector2, radius: Vector2, closed: bool = false) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := SEGMENTS + (1 if closed else 0)
	for i in range(count):
		var angle := TAU * float(i % SEGMENTS) / float(SEGMENTS)
		points.append(centre + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points
