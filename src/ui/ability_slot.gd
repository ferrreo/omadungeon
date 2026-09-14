## HUD slot for an active ability: icon, radial cooldown wedge, ready flash and glyph.
## Duck-types the ability: reads `icon`, `cooldown_left`, `cooldown`.
class_name AbilitySlot
extends Control

const BOX := 22
const GLYPH_GAP := 2
## Plate opacity for a slot that holds an ability, and for an empty one.
const PLATE_FILLED := 0.88
const PLATE_EMPTY := 0.32
const EMPTY_BORDER_ALPHA := 0.5

var action: StringName = &"active_1"
var ability: Resource
var _cooldown_total: float = 0.0
var _last_left: float = 0.0
var _fraction: float = 0.0
var _ready_flash: float = 0.0
var _glyph: GlyphIcon


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(BOX, BOX + GLYPH_GAP + InputGlyphs.CELL)
	_glyph = GlyphIcon.new()
	_glyph.action = action
	add_child(_glyph)
	_layout_glyph()
	EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: queue_redraw())
	EventBus.input_device_changed.connect(func(_d: int) -> void: _layout_glyph())


func set_action(new_action: StringName) -> void:
	action = new_action
	if _glyph != null:
		_glyph.action = new_action
		_layout_glyph()


## Centres the key glyph under the box using its own measured width: a wide cap ("Spc") is
## wider than the 22 px slot, and pinning it to a 16 px box hung it off to one side.
func _layout_glyph() -> void:
	if _glyph == null:
		return
	var width := _glyph.glyph_width()
	_glyph.size = Vector2(width, InputGlyphs.CELL)
	_glyph.position = Vector2(floorf((BOX - width) * 0.5), BOX + GLYPH_GAP)


func set_ability(new_ability: Resource) -> void:
	ability = new_ability
	_cooldown_total = 0.0
	_last_left = 0.0
	_fraction = 0.0
	queue_redraw()


## Cooldown fraction remaining (0 = ready), sampled once per frame in `_process`.
func cooldown_fraction() -> float:
	return _fraction


## Seconds of cooldown left as of the last sample.
func cooldown_left() -> float:
	return _last_left


## Strength of the "ability is ready again" flash (1 at the edge, fading to 0).
func ready_flash() -> float:
	return _ready_flash


## Samples the ability and advances the flash. Kept out of `_draw`, which may be skipped
## for a hidden or occluded canvas item and must stay a pure function of this state.
func sample(delta: float) -> void:
	_ready_flash = maxf(0.0, _ready_flash - delta * 3.0)
	if ability == null:
		_fraction = 0.0
		_last_left = 0.0
		return
	var left := float(ability.get("cooldown_left"))
	if left > _last_left + 0.001:
		_cooldown_total = maxf(left, float(ability.get("cooldown")))
	if _last_left > 0.0 and left <= 0.0:
		_ready_flash = Accessibility.flash(1.0)
	_last_left = left
	if _cooldown_total <= 0.0 or left <= 0.0:
		_fraction = 0.0
	else:
		_fraction = clampf(left / _cooldown_total, 0.0, 1.0)


## Opacity of the slot plate. A filled slot is deliberately the more solid of the two, so an
## empty socket can never out-shout a real ability (which is what happened on light themes,
## where both slots drew the same opaque plate and only the empty one had nothing over it).
func plate_alpha() -> float:
	return PLATE_FILLED if ability != null else PLATE_EMPTY


## Frame colour the next `_draw` will use. A ready ability gets the accent, a cooling one the
## plain dim frame, an empty socket the dim frame at reduced alpha.
func border_color() -> Color:
	var accent := UiTheme.on(&"accent", &"void", 3.0)
	if _ready_flash > 0.0:
		return accent.lerp(UiTheme.on(&"text_bright", &"void", 4.5), _ready_flash)
	if ability != null and _fraction <= 0.0:
		return accent
	var border := UiTheme.on(&"text_dim", &"void", 2.0)
	if ability == null:
		border.a = EMPTY_BORDER_ALPHA
	return border


func _process(delta: float) -> void:
	sample(delta)
	queue_redraw()


func _draw() -> void:
	var box := Rect2(0, 0, BOX, BOX)
	var filled := ability != null
	# A filled slot is always the stronger element: opaque plate, accent frame. An empty slot
	# is a faint socket. Deriving both from the same plate keeps that order on a light theme,
	# where an opaque "empty" box used to be the brightest thing in the corner.
	var plate := UiTheme.plate_color(plate_alpha())
	draw_rect(box, plate)
	var frac := _fraction
	var icon := UiTheme.icon_for(ability)
	if icon != null:
		var icon_pos := (Vector2(BOX, BOX) - icon.get_size()) * 0.5
		draw_texture(icon, icon_pos.floor(), Color(1, 1, 1, 0.45 if frac > 0.0 else 1.0))
	elif ability != null:
		var name := str(ability.get("display_name"))
		var letter := name.substr(0, 1).to_upper() if not name.is_empty() else "?"
		draw_string(
			UiTheme.heading_font(),
			Vector2(7, 15),
			letter,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			UiTheme.SIZE_S,
			UiTheme.color(&"text")
		)
	if frac > 0.0:
		_draw_wedge(frac)
		var seconds := ceilf(_last_left)
		var text := str(int(seconds))
		var font := UiTheme.body_font()
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, UiTheme.SIZE_S)
		draw_string(
			font,
			Vector2(floorf((BOX - ts.x) * 0.5), floorf(BOX * 0.5 + 3)),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			UiTheme.SIZE_S,
			UiTheme.color(&"text_bright")
		)
	var border := border_color()
	if _ready_flash > 0.0:
		var halo := UiTheme.on(&"accent", &"void", 3.0)
		halo.a = _ready_flash * 0.5
		draw_rect(box.grow(1), halo, false, 1.0)
	draw_rect(box, border, false, 1.0)
	if not filled:
		# An empty socket reads as a hole, not as a lit button.
		var mark := border
		mark.a = EMPTY_BORDER_ALPHA * 0.8
		draw_rect(box.grow(-5), mark, false, 1.0)


func _draw_wedge(frac: float) -> void:
	var centre := Vector2(BOX * 0.5, BOX * 0.5)
	var points := PackedVector2Array()
	points.append(centre)
	var steps := 24
	var start := -PI * 0.5
	var sweep := TAU * frac
	for i in range(steps + 1):
		var a := start + sweep * float(i) / float(steps)
		var dir := Vector2(cos(a), sin(a))
		var scale := BOX * 0.5 / maxf(absf(dir.x), absf(dir.y))
		points.append(centre + dir * scale)
	draw_colored_polygon(points, UiTheme.plate_color(0.72))
