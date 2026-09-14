## Slow diagonal scroll of a woven floor / floor_alt texture with a soft vignette.
## Used behind menus; reads palette colours every draw so it retints for free.
##
## It used to be a 16 px two-tone checkerboard, and on a light theme that is not a texture, it
## is a *signifier*: at (239,241,245) against (213,216,222) the catppuccin-latte menu margin
## was pixel for pixel the chequerboard an image editor draws behind an empty layer, so the
## first screen a light-theme player ever saw looked like a failed asset load. On a dark theme
## the same pattern was nearly invisible, which is how it survived three rounds of review.
##
## Two things changed and both matter. The motif is a diagonal weave, which nothing uses to
## mean "nothing is here"; and the tone step is held at a fixed *contrast ratio* rather than a
## fixed lerp, because a lerp toward `floor_alt` is not symmetric between polarities - the same
## 0.6 that vanished on navy shouted on paper.
class_name ScrollingBackdrop
extends Control

## Spacing of the weave's diagonals, in px, and how wide each band is drawn.
const WEAVE_SPACING := 12
const WEAVE_WIDTH := 3.0
const SPEED := Vector2(6.0, 4.0)
## Contrast the weave keeps against the ground it is drawn on. One number for both polarities:
## a ratio is symmetric where a lerp is not, so paper and navy get the same faint texture.
const WEAVE_CONTRAST := 1.1

## Height of the vignette ramp texture; it is stretched over the real band.
const VIGNETTE_STEPS := 64

var _offset: Vector2 = Vector2.ZERO
var _vignette: ImageTexture
var _vignette_key: Color = Color(0, 0, 0, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if Accessibility.reduced_flash() or not Accessibility.animates():
		return
	_offset = (_offset + SPEED * delta).posmod(WEAVE_SPACING)
	queue_redraw()


## The weave's tone: `floor_alt`'s hue placed exactly `WEAVE_CONTRAST` from `ground`, away from
## whichever pole the ground is nearer. Static so a test can measure the step a theme gets
## without standing a menu up.
static func weave_color(ground: Color, detail: Color) -> Color:
	var lum := ThemePalette.relative_luminance(ground)
	var target := (
		(lum + 0.05) / WEAVE_CONTRAST - 0.05 if lum > 0.5 else WEAVE_CONTRAST * (lum + 0.05) - 0.05
	)
	return ThemePalette.with_luminance(detail, clampf(target, 0.0, 1.0))


func _draw() -> void:
	var a := UiTheme.color(&"floor")
	var b := weave_color(a, UiTheme.color(&"floor_alt"))
	draw_rect(Rect2(Vector2.ZERO, size), a)
	# One family of diagonals, scrolling along itself. Lines, not tiles: a 480x270 checker was
	# ~500 draw_rect calls a frame, and this is about 60 draw_line calls.
	var start := -size.y - float(WEAVE_SPACING) + fmod(_offset.x + _offset.y, WEAVE_SPACING)
	var x := start
	while x < size.x + float(WEAVE_SPACING):
		draw_line(Vector2(x, 0.0), Vector2(x + size.y, size.y), b, WEAVE_WIDTH)
		x += float(WEAVE_SPACING)
	var void_c := UiTheme.color(&"void")
	var is_light := Desktop.palette != null and Desktop.palette.is_light
	var strength := 0.3 if is_light else 0.75
	var band := floorf(size.y * 0.25)
	if band < 1.0:
		return
	# One cached gradient strip stretched twice, instead of ~135 draw_line calls per frame.
	var tex := _vignette_texture(void_c, strength)
	draw_texture_rect(tex, Rect2(0.0, 0.0, size.x, band), false)
	draw_texture_rect(tex, Rect2(0.0, size.y, size.x, -band), false)


## Cached top-down alpha ramp of the void colour (rebuilt only when the palette moves).
func _vignette_texture(void_c: Color, strength: float) -> ImageTexture:
	var key := Color(void_c.r, void_c.g, void_c.b, strength)
	if _vignette != null and _vignette_key.is_equal_approx(key):
		return _vignette
	var image := Image.create(1, VIGNETTE_STEPS, false, Image.FORMAT_RGBA8)
	for i in VIGNETTE_STEPS:
		var t := 1.0 - float(i) / float(VIGNETTE_STEPS)
		var c := void_c
		c.a = t * t * strength
		image.set_pixel(0, i, c)
	_vignette = ImageTexture.create_from_image(image)
	_vignette_key = key
	return _vignette
