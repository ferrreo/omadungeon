## Runtime-built UI Theme tinted from the live desktop palette.
## One shared Theme instance is mutated in place, so every Control that called
## `UiTheme.apply(control)` recolours as the palette crossfades (~0.6 s) on
## `EventBus.palette_changed`. Custom-drawn widgets read `UiTheme.color(role)` each draw.
class_name UiTheme
extends RefCounted

## Cell indices in assets/sprites/ui/icons.png (16x16 cells, one row; order defined by
## tools/art/ui.py ICONS).
enum Icon {
	HEART,
	POTION,
	GOLD,
	STAIRS,
	DIE,
	VITALITY,
	MIGHT,
	PRECISION,
	ARCANA,
	SWIFTNESS,
	FORTUNE,
	RARITY_COMMON,
	RARITY_RARE,
	RARITY_EPIC,
	RARITY_LEGENDARY,
	LOCK,
}

## Surfaces a piece of UI text can be drawn on; `_readable` guards text against all of them.
const TEXT_SURFACES: Array[StringName] = [&"floor", &"floor_alt", &"void"]
## The spacing scale every screen lays out on. Four pixels is the step: the internal
## resolution is 480x270 and the body font is 8 px tall, so 4 px is one half-line and a
## column of rows on it reads as a rhythm rather than as an accident. `GAP_TIGHT` is the one
## half-step, for rows inside a single block that should read as one thing.
##
## The owner's report was "lots of ui is sloppy e.g spacing". The screens were laid out on
## 1, 2, 3, 4, 6, 8, 12 and 16 px at the same time, with no rule saying which was which.
## `tests/unit/ui/spacing_grid_test.gd` is the guard that keeps them on this list.
const GAP_NONE := 0
const GAP_TIGHT := 2
const GAP := 4
const GAP_WIDE := 8
const GAP_SECTION := 12
const GAP_COLUMN := 16
## Every separation a screen in `src/ui` may use.
const GRID: Array[int] = [GAP_NONE, GAP_TIGHT, GAP, GAP_WIDE, GAP_SECTION, GAP_COLUMN]
## The slider knob. A focused slider draws the wider one: `text_bright` collapses onto `text`
## on five of the six shipped fixtures, so a focus highlight that is only a colour is no
## highlight at all on most of the themes players actually run. Both are the same *height*, so
## taking focus never changes the row's minimum size.
const GRABBER_SIZE := Vector2i(6, 10)
const GRABBER_FOCUS_WIDTH := 8
const SIZE_S := 8
const SIZE_M := 12
const SIZE_L := 16
const RETINT_DURATION := 0.6
const HEADING_FONT_PATH := "res://assets/fonts/PressStart2P-Regular.ttf"
const BODY_FONT_PATHS: PackedStringArray = [
	"res://assets/fonts/Silkscreen-Regular.ttf", "res://assets/fonts/VT323-Regular.ttf"
]
const ICONS_PATH := "res://assets/sprites/ui/icons.png"
const ABILITY_ICONS_PATH := "res://assets/sprites/ui/ability_icons.png"
const ICON_CELL := 16
## Cell order of assets/sprites/ui/ability_icons.png (tools/art/ui.py ABILITY_ICONS).
const ABILITY_ICON_IDS: PackedStringArray = [
	"fireball",
	"frost_nova",
	"shadowstep",
	"whirlwind",
	"turret",
	"warcry",
	"rm_rf",
	"reboot",
	"bulwark",
	"volley",
	"chain_lightning",
	"hostile_takeover",
	"contract",
	"thorns",
	"glass_cannon",
	"vampiric",
	"tiling_wm",
	"dotfiles",
	"lucky_coin",
	"ricochet",
	"adrenaline",
	"heavy_hands",
	"hotkey",
	"second_wind",
	"sure_footed",
	"overflow",
	"buyout",
]

## Primary stat -> icon index.
const STAT_ICONS: Dictionary = {
	&"vitality": Icon.VITALITY,
	&"might": Icon.MIGHT,
	&"precision": Icon.PRECISION,
	&"arcana": Icon.ARCANA,
	&"swiftness": Icon.SWIFTNESS,
	&"fortune": Icon.FORTUNE,
}

## The three roles the HUD uses to *signal* state rather than to decorate: full health,
## critical health and loot. GDD §3.2's guard keeps each of them readable against a surface,
## but readable is not the same as distinguishable: the `white` fixture ships
## green/red/yellow as #3a3a3a/#2a2a2a/#4a4a4a, three neutral greys that every guard lets
## through and no player can tell apart. These three are therefore also guarded against
## *each other*, and rebuilt from canonical hues when the theme has none to offer.
const SIGNAL_ROLES: Array[StringName] = [&"heal", &"danger", &"loot"]
## Canonical hue (0..1) each signal role falls back to when the theme's own are too alike.
const SIGNAL_HUES: Dictionary = {&"heal": 0.33, &"danger": 0.0, &"loot": 0.12}
## Smallest sRGB distance two signal colours may have before all three are rebuilt.
## Measured across the shipped fixtures: gruvbox's closest pair is 0.20, `white`'s is 0.11.
const SIGNAL_MIN_DISTANCE := 0.16
## Contrast every signal colour keeps against the HUD plate it is drawn on (`void`).
const SIGNAL_MIN_CONTRAST := 4.5
## Saturation/value of a rebuilt signal colour, on a dark and on a light palette.
const SIGNAL_REBUILD_DARK := Vector2(0.62, 0.88)
const SIGNAL_REBUILD_LIGHT := Vector2(0.95, 0.62)


## The shared theme; built lazily from `Desktop.palette` on first use.
static func theme() -> Theme:
	var r := UiRuntime.get_shared()
	_ensure()
	return r.theme


## True when `value` is a separation on the spacing grid (see `GRID`).
static func on_grid(value: int) -> bool:
	return GRID.has(value)


## Assigns the shared theme to a control (and thereby its whole subtree).
static func apply(control: Control) -> void:
	control.theme = theme()


## Rebuilds colours immediately from `palette` (no crossfade).
static func rebuild(palette: ThemePalette) -> void:
	var r := UiRuntime.get_shared()
	_ensure()
	if r.tween != null and r.tween.is_valid():
		r.tween.kill()
	r.current = _copy_colors(palette)
	r.from = r.current.duplicate()
	r.to = r.current.duplicate()
	_write()


## Crossfades every theme colour toward `palette` over `duration` seconds.
static func retint(palette: ThemePalette, duration: float = RETINT_DURATION) -> void:
	var r := UiRuntime.get_shared()
	_ensure()
	if r.tween != null and r.tween.is_valid():
		r.tween.kill()
	r.from = r.current.duplicate()
	r.to = _copy_colors(palette)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or duration <= 0.0:
		_apply_blend(1.0)
		return
	r.tween = tree.create_tween()
	r.tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	r.tween.tween_method(UiTheme._apply_blend, 0.0, 1.0, duration)


## Current (possibly mid-crossfade) colour for a palette role.
static func color(role: StringName) -> Color:
	var r := UiRuntime.get_shared()
	_ensure()
	return r.current.get(role, Color.MAGENTA)


## Same as `color` but with alpha applied.
static func color_a(role: StringName, alpha: float) -> Color:
	var c := color(role)
	c.a = alpha
	return c


## The plate custom-drawn HUD widgets sit on (minimap, ability slots, bars). One place, so
## every widget judges its foregrounds against the same surface.
static func plate_color(alpha: float = 0.9) -> Color:
	return color_a(&"void", alpha)


## The colour a HUD widget should draw `role` (`heal`, `danger` or `loot`) in: readable on
## the HUD plate *and* distinguishable from the other two. Any other role is returned with
## the plain plate guard, so callers never have to know which roles are special.
static func signal_color(role: StringName) -> Color:
	_ensure()
	var table := _signal_table()
	if table.has(role):
		return table[role]
	return on(role, &"void", SIGNAL_MIN_CONTRAST)


## Smallest sRGB distance between any two of the current signal colours. Tests assert on it;
## `_signal_table` uses the same measure on the raw palette to decide whether to rebuild.
static func signal_separation() -> float:
	var table := _signal_table()
	var colors: Array[Color] = []
	for role: StringName in SIGNAL_ROLES:
		colors.append(table.get(role, Color.MAGENTA))
	return _min_distance(colors)


## Straight-line distance between two colours in sRGB. Crude next to a perceptual metric,
## but it is monotone in exactly the way this guard needs: three neutral greys score near
## zero however far apart their luminances nominally are, while red/green/amber never do.
static func color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## Resolves (and caches per `_write`) the three signal colours from the live palette.
static func _signal_table() -> Dictionary:
	var r := UiRuntime.get_shared()
	if not r.signal_colors.is_empty():
		return r.signal_colors
	var raw: Array[Color] = []
	for role: StringName in SIGNAL_ROLES:
		raw.append(_c(role))
	var rebuild := _min_distance(raw) < SIGNAL_MIN_DISTANCE
	var out: Dictionary = {}
	for i in SIGNAL_ROLES.size():
		var role := SIGNAL_ROLES[i]
		var base := _rebuilt_signal(role) if rebuild else raw[i]
		out[role] = ThemePalette.ensure_contrast(base, _c(&"void"), SIGNAL_MIN_CONTRAST)
	r.signal_colors = out
	return out


## A signal colour built from its canonical hue, in the polarity the palette already uses.
static func _rebuilt_signal(role: StringName) -> Color:
	var light := ThemePalette.relative_luminance(_c(&"void")) > 0.35
	var sv := SIGNAL_REBUILD_LIGHT if light else SIGNAL_REBUILD_DARK
	return Color.from_hsv(float(SIGNAL_HUES.get(role, 0.0)), sv.x, sv.y)


static func _min_distance(colors: Array[Color]) -> float:
	var out := INF
	for i in colors.size():
		for j in range(i + 1, colors.size()):
			out = minf(out, color_distance(colors[i], colors[j]))
	return 0.0 if out == INF else out


## A role colour pushed until it is readable on another role's surface. Use it for anything
## drawn on a plate the palette's own guard does not already cover, e.g. a minimap room fill
## judged against the minimap plate rather than against the dungeon floor.
static func on(role: StringName, surface: StringName, target: float = 3.0) -> Color:
	_ensure()
	return ThemePalette.ensure_contrast(_c(role), _c(surface), target)


## Same, for a colour that is not a role (a fill already blended from other roles).
static func readable_on(c: Color, surface: Color, target: float = 3.0) -> Color:
	return ThemePalette.ensure_contrast(c, surface, target)


static func heading_font() -> Font:
	var r := UiRuntime.get_shared()
	_ensure()
	return r.heading_font


static func body_font() -> Font:
	var r := UiRuntime.get_shared()
	_ensure()
	return r.body_font


## Sub-texture of the shared icon sheet.
static func icon(index: int) -> Texture2D:
	var r := UiRuntime.get_shared()
	_ensure()
	if r.icon_cache.has(index):
		return r.icon_cache[index]
	var atlas := AtlasTexture.new()
	atlas.atlas = r.icons
	atlas.region = Rect2(index * ICON_CELL, 0, ICON_CELL, ICON_CELL)
	r.icon_cache[index] = atlas
	return atlas


## Icon for an ability id from the shared ability sheet, or null when unknown.
static func ability_icon(id: StringName) -> Texture2D:
	var index := ABILITY_ICON_IDS.find(String(id))
	if index < 0:
		return null
	var r := UiRuntime.get_shared()
	var key := "ability:%d" % index
	if r.icon_cache.has(key):
		return r.icon_cache[key]
	if r.ability_icons == null:
		r.ability_icons = load_texture(ABILITY_ICONS_PATH)
		if r.ability_icons == null:
			return null
	var atlas := AtlasTexture.new()
	atlas.atlas = r.ability_icons
	atlas.region = Rect2(index * ICON_CELL, 0, ICON_CELL, ICON_CELL)
	r.icon_cache[key] = atlas
	return atlas


## Best icon for an ability-like resource: its own `icon`, else the shared sheet by id.
static func icon_for(ability: Resource) -> Texture2D:
	if ability == null:
		return null
	var own: Variant = ability.get("icon")
	if own is Texture2D:
		return own as Texture2D
	var id: Variant = ability.get("id")
	if id == null:
		return null
	return ability_icon(StringName(str(id)))


## Loads a texture even when the .import cache is missing (headless test copies).
static func load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path) as Texture2D
		if res != null:
			return res
	var global := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(global):
		var image := Image.load_from_file(global)
		if image != null:
			return ImageTexture.create_from_image(image)
	return null


## A fresh flat style using palette roles; useful for one-off custom panels.
static func make_style(
	bg_role: StringName, border_role: StringName = &"", border: int = 1, bg_alpha: float = 1.0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color_a(bg_role, bg_alpha)
	if border_role != &"":
		style.border_color = color(border_role)
		style.set_border_width_all(border)
	style.set_content_margin_all(4)
	return style


static func _ensure() -> void:
	var r := UiRuntime.get_shared()
	if r.theme != null:
		return
	r.theme = Theme.new()
	_load_fonts()
	r.icons = load_texture(ICONS_PATH)
	if r.icons == null:
		r.icons = ImageTexture.create_from_image(
			Image.create(ICON_CELL * 16, ICON_CELL, false, Image.FORMAT_RGBA8)
		)
	var palette: ThemePalette = (
		Desktop.palette if Desktop.palette != null else ThemePalette.fallback()
	)
	r.current = _copy_colors(palette)
	r.from = r.current.duplicate()
	r.to = r.current.duplicate()
	_build_structure()
	_write()
	if not r.theme_connected:
		r.theme_connected = true
		EventBus.palette_changed.connect(UiTheme._on_palette_changed)


static func _on_palette_changed(palette: ThemePalette) -> void:
	retint(palette)


static func _copy_colors(palette: ThemePalette) -> Dictionary:
	var out: Dictionary = {}
	for role: String in ThemePalette.ROLES:
		out[StringName(role)] = palette.get_color(role)
	return out


## One step of the crossfade.
##
## `r.current` is updated every frame, because every custom-drawn widget in the HUD reads its
## colours straight off it (`UiTheme.color`) and redraws itself - that is what makes the retint
## look continuous, and it is nearly free.
##
## The `Theme` resource is a different matter. Writing it marks it changed, and every Control
## in the tree then re-resolves its styleboxes, fonts and icons and redraws. `_write()` itself
## takes under 20 ms; the invalidation it triggers cost ~800 ms of a frame on a real renderer,
## and doing it every frame of a 0.6 s fade is what turned a theme swap into the owner's
## "basically stalled ... maybe one frame of updated colors a second". Measured: 867 ms worst
## frame with a write per step, 69 ms without.
##
## So Controls are handed the finished palette once, at the end. They spend the fade wearing
## the colours they already had, which nobody notices behind a HUD that is crossfading properly
## - and a menu opened mid-fade still calls `apply()` and gets the current state.
static func _apply_blend(t: float) -> void:
	var r := UiRuntime.get_shared()
	for role: StringName in r.to.keys():
		var a: Color = r.from.get(role, r.to[role])
		r.current[role] = a.lerp(r.to[role], t)
	if t >= 1.0:
		_write()


static func _load_fonts() -> void:
	var r := UiRuntime.get_shared()
	r.heading_font = _load_font(HEADING_FONT_PATH)
	for path: String in BODY_FONT_PATHS:
		r.body_font = _load_font(path)
		if r.body_font != null:
			break
	if r.heading_font == null and r.body_font != null:
		r.heading_font = r.body_font
	if r.body_font == null:
		r.body_font = _crisp_default_font()
	if r.heading_font == null:
		r.heading_font = r.body_font


static func _load_font(path: String) -> Font:
	var global := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(global):
		return null
	var font := FontFile.new()
	if font.load_dynamic_font(global) != OK:
		return null
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.generate_mipmaps = false
	return font


static func _crisp_default_font() -> Font:
	var base := ThemeDB.fallback_font
	if base is FontFile:
		var copy := (base as FontFile).duplicate() as FontFile
		copy.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		copy.hinting = TextServer.HINTING_NORMAL
		copy.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		return copy
	return base


static func _style(name: StringName) -> StyleBoxFlat:
	var r := UiRuntime.get_shared()
	if not r.styles.has(name):
		var s := StyleBoxFlat.new()
		r.styles[name] = s
	return r.styles[name]


## Creates every theme entry once; colours are filled by `_write`.
static func _build_structure() -> void:
	var r := UiRuntime.get_shared()
	var t := r.theme
	t.default_font = r.body_font
	t.default_font_size = SIZE_S
	# Labels and variations.
	t.set_font(&"font", &"Label", r.body_font)
	t.set_font_size(&"font_size", &"Label", SIZE_S)
	for variation: StringName in [
		&"Heading",
		&"HeadingLarge",
		&"Title",
		&"Dim",
		&"Bright",
		&"Accent",
		&"Danger",
		&"Heal",
		&"Loot"
	]:
		t.set_type_variation(variation, &"Label")
	t.set_font(&"font", &"Heading", r.heading_font)
	t.set_font_size(&"font_size", &"Heading", SIZE_S)
	t.set_font(&"font", &"HeadingLarge", r.heading_font)
	t.set_font_size(&"font_size", &"HeadingLarge", SIZE_L)
	t.set_font(&"font", &"Title", r.heading_font)
	t.set_font_size(&"font_size", &"Title", SIZE_L)
	# RichTextLabel.
	t.set_font(&"normal_font", &"RichTextLabel", r.body_font)
	t.set_font(&"bold_font", &"RichTextLabel", r.heading_font)
	t.set_font_size(&"normal_font_size", &"RichTextLabel", SIZE_S)
	t.set_font_size(&"bold_font_size", &"RichTextLabel", SIZE_S)
	# Buttons.
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var s := _style(StringName("button_" + state))
		s.set_border_width_all(1)
		s.set_content_margin_all(3)
		s.content_margin_left = 6
		s.content_margin_right = 6
		t.set_stylebox(state, &"Button", s)
	_style(&"button_hover").set_border_width_all(1)
	t.set_font(&"font", &"Button", r.body_font)
	t.set_font_size(&"font_size", &"Button", SIZE_S)
	t.set_type_variation(&"MenuButtonWide", &"Button")
	t.set_type_variation(&"DangerButton", &"Button")
	t.set_type_variation(&"TabButton", &"Button")
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var s := _style(StringName("danger_" + state))
		s.set_border_width_all(1)
		s.set_content_margin_all(3)
		s.content_margin_left = 6
		s.content_margin_right = 6
		t.set_stylebox(state, &"DangerButton", s)
		var tab := _style(StringName("tab_" + state))
		tab.set_content_margin_all(3)
		tab.content_margin_left = 6
		tab.content_margin_right = 6
		tab.border_width_bottom = 1
		t.set_stylebox(state, &"TabButton", tab)
	# Panels.
	var panel := _style(&"panel")
	panel.set_border_width_all(1)
	panel.set_content_margin_all(6)
	t.set_stylebox(&"panel", &"Panel", panel)
	t.set_stylebox(&"panel", &"PanelContainer", panel)
	t.set_type_variation(&"Card", &"PanelContainer")
	t.set_type_variation(&"CardSelected", &"PanelContainer")
	t.set_type_variation(&"Overlay", &"PanelContainer")
	t.set_type_variation(&"Hud", &"PanelContainer")
	var card := _style(&"card")
	card.set_border_width_all(1)
	card.set_content_margin_all(6)
	t.set_stylebox(&"panel", &"Card", card)
	var card_sel := _style(&"card_selected")
	# Three px, not two. Thickness is the one selection channel that does not need the theme to
	# have a spare hue, and it is carrying more weight now that the selected card no longer
	# scales: a card that grows lifts its own contents off the baseline the other three share.
	card_sel.set_border_width_all(3)
	# The same content margin as `Card`, not one pixel less. A selected card is a *thicker*
	# border, not a different box: trading a pixel of margin for the pixel of border moved
	# everything inside the selected card up by one, which on `ClassSelect` is four cards that
	# no longer share a baseline. The thicker border draws inside the margin instead.
	card_sel.set_content_margin_all(6)
	t.set_stylebox(&"panel", &"CardSelected", card_sel)
	var overlay := _style(&"overlay")
	overlay.set_content_margin_all(0)
	t.set_stylebox(&"panel", &"Overlay", overlay)
	var hud := _style(&"hud")
	hud.set_border_width_all(1)
	hud.set_content_margin_all(3)
	t.set_stylebox(&"panel", &"Hud", hud)
	t.set_type_variation(&"HudPlate", &"PanelContainer")
	var hud_plate := _style(&"hud_plate")
	hud_plate.set_border_width_all(1)
	hud_plate.set_content_margin_all(3)
	t.set_stylebox(&"panel", &"HudPlate", hud_plate)
	# LineEdit.
	var le := _style(&"lineedit")
	le.set_border_width_all(1)
	le.set_content_margin_all(3)
	t.set_stylebox(&"normal", &"LineEdit", le)
	t.set_stylebox(&"read_only", &"LineEdit", le)
	var le_focus := _style(&"lineedit_focus")
	le_focus.set_border_width_all(1)
	le_focus.set_content_margin_all(3)
	t.set_stylebox(&"focus", &"LineEdit", le_focus)
	t.set_font(&"font", &"LineEdit", r.body_font)
	t.set_font_size(&"font_size", &"LineEdit", SIZE_S)
	# Sliders. `HSlider` has no `focus` stylebox at all - the engine's whole focus cue for a
	# slider is that it swaps in `grabber_area_highlight` and the `grabber_highlight` icon
	# while `mouse_inside or has_focus()`. `grabber_area_highlight` used to be handed the very
	# same object as `grabber_area`, so a slider the controller was sitting on drew identically
	# to one it was not: the owner's "there is no highlight effect when the sliders for audio
	# have focus via the controller".
	var slider := _style(&"slider")
	slider.set_content_margin_all(2)
	t.set_stylebox(&"slider", &"HSlider", slider)
	var grabber_area := _style(&"grabber_area")
	grabber_area.set_content_margin_all(2)
	t.set_stylebox(&"grabber_area", &"HSlider", grabber_area)
	var grabber_focus := _style(&"grabber_area_focus")
	grabber_focus.set_content_margin_all(2)
	grabber_focus.set_border_width_all(1)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", grabber_focus)
	# ... and the slab the row itself draws behind a focused slider, which is the part a player
	# sees from across the room. Two `PanelContainer` variations rather than a box painted by
	# hand in the panel: the palette refills these same stylebox objects, so a theme change
	# repaints the focus slab with everything else. Worn by `SliderRow`.
	t.set_type_variation(&"SliderSlab", &"PanelContainer")
	t.set_type_variation(&"SliderSlabFocus", &"PanelContainer")
	var slab_idle := StyleBoxEmpty.new()
	slab_idle.set_content_margin_all(2)
	t.set_stylebox(&"panel", &"SliderSlab", slab_idle)
	var slab_focus := _style(&"slider_slab_focus")
	slab_focus.set_border_width_all(1)
	slab_focus.set_content_margin_all(2)
	t.set_stylebox(&"panel", &"SliderSlabFocus", slab_focus)
	# Check boxes / buttons.
	t.set_font(&"font", &"CheckBox", r.body_font)
	t.set_font_size(&"font_size", &"CheckBox", SIZE_S)
	for state: StringName in [
		&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"
	]:
		var s := _style(StringName("check_" + state))
		s.set_content_margin_all(2)
		s.content_margin_left = 4
		t.set_stylebox(state, &"CheckBox", s)
	# The focus state is the only check stylebox that draws an edge. It is the controller's
	# "you are here" marker on a page of identical rows, and the tint on its own is a shade a
	# player has to hunt for; every other focusable control in the UI gets a border.
	_style(&"check_focus").set_border_width_all(1)
	t.set_constant(&"h_separation", &"CheckBox", 4)
	# Progress bars.
	var pb_bg := _style(&"progress_bg")
	pb_bg.set_border_width_all(1)
	t.set_stylebox(&"background", &"ProgressBar", pb_bg)
	var pb_fill := _style(&"progress_fill")
	pb_fill.set_content_margin_all(0)
	t.set_stylebox(&"fill", &"ProgressBar", pb_fill)
	t.set_font(&"font", &"ProgressBar", r.body_font)
	t.set_font_size(&"font_size", &"ProgressBar", SIZE_S)
	# Scroll bars. The stylebox margins are what gives the bar its 4 px thickness.
	var sb := _style(&"scroll")
	sb.set_content_margin_all(2)
	t.set_stylebox(&"scroll", &"VScrollBar", sb)
	t.set_stylebox(&"scroll", &"HScrollBar", sb)
	var grabber := _style(&"scroll_grabber")
	grabber.set_content_margin_all(2)
	for state: StringName in [&"grabber", &"grabber_highlight", &"grabber_pressed"]:
		t.set_stylebox(state, &"VScrollBar", grabber)
		t.set_stylebox(state, &"HScrollBar", grabber)
	# Separators.
	var sep := StyleBoxLine.new()
	sep.thickness = 1
	r.styles[&"separator"] = sep
	t.set_stylebox(&"separator", &"HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.thickness = 1
	vsep.vertical = true
	r.styles[&"vseparator"] = vsep
	t.set_stylebox(&"separator", &"VSeparator", vsep)
	# Tooltips / popups use a plain card.
	t.set_stylebox(&"panel", &"TooltipPanel", card)
	t.set_stylebox(&"panel", &"PopupPanel", card)


static func _grabber_icon(color: Color) -> Texture2D:
	var img := Image.create(GRABBER_SIZE.x, GRABBER_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## The knob a focused slider draws: wider than the idle one and ringed in `ring`. The width is
## what makes the cue survive a theme whose `text_bright` is its `text` (gruvbox, catppuccin,
## catppuccin-latte, nord and white all ship one), and the ring is the same accent edge the
## focused fill and the focus slab carry.
static func _grabber_focus_icon(core: Color, ring: Color) -> Texture2D:
	var img := Image.create(GRABBER_FOCUS_WIDTH, GRABBER_SIZE.y, false, Image.FORMAT_RGBA8)
	for y in GRABBER_SIZE.y:
		for x in GRABBER_FOCUS_WIDTH:
			var edge := x == 0 or y == 0 or x == GRABBER_FOCUS_WIDTH - 1 or y == GRABBER_SIZE.y - 1
			img.set_pixel(x, y, ring if edge else core)
	return ImageTexture.create_from_image(img)


static func _c(role: StringName) -> Color:
	var r := UiRuntime.get_shared()
	return r.current.get(role, Color.MAGENTA)


static func _ca(role: StringName, alpha: float) -> Color:
	var c := _c(role)
	c.a = alpha
	return c


## A role colour pushed until it is readable *as text* on every surface UI text lands on,
## at the 4.5:1 docs 3.2 asks for. Measuring against `floor` alone at 3.0 is how the HP
## readout ended up at 1.9:1 on a light theme: the same label is drawn over panels, over
## cards and over the HUD plate, and it only gets to be one colour.
static func _readable(role: StringName) -> Color:
	return ThemePalette.ensure_contrast_all(
		_c(role), text_surfaces(), ThemePalette.MIN_CONTRAST, ink_direction()
	)


## The surfaces UI text can sit on: panels (`floor`), cards and buttons (`floor_alt`) and the
## HUD plate (`void`). Walls are absent on purpose - see `ThemePalette.SURFACES`.
static func text_surfaces() -> Array[Color]:
	var out: Array[Color] = []
	for role: StringName in TEXT_SURFACES:
		out.append(_c(role))
	return out


## Which extreme a foreground is pushed toward: white on a dark palette, black on a light one.
static func ink_direction() -> Color:
	return Color.BLACK if ThemePalette.relative_luminance(_c(&"floor")) >= 0.5 else Color.WHITE


## Inset surface for fields, tracks and slider grooves. `wall` is the dark-theme answer, but
## on a light palette it is a dark slab under dark text (the seed field on the title screen
## read as a black box), so a light theme gets a shallow well cut out of `floor_alt` instead.
static func _inset() -> Color:
	if ThemePalette.relative_luminance(_c(&"floor")) > 0.35:
		return _c(&"floor_alt").darkened(0.06)
	return _c(&"wall")


## A signal role as *text*: separated from its two siblings, then floored against the panel
## ground it is actually printed on (the plate guard alone is not enough on a light theme,
## where `floor` is brighter than `void`).
static func _signal_text(role: StringName) -> Color:
	return ThemePalette.ensure_contrast(signal_color(role), _c(&"floor"), 3.0)


## Same guard, public: use for text drawn in an accent/rarity colour. The three signal roles
## go through `signal_color` first, so a "YOU DIED" headline or an unaffordable price is red
## rather than whatever near-black the theme happens to call `red`.
static func text_color(role: StringName) -> Color:
	_ensure()
	if SIGNAL_HUES.has(role):
		return _signal_text(role)
	return _readable(role)


## Writes the current blended colours into the theme and shared styleboxes.
static func _write() -> void:
	var r := UiRuntime.get_shared()
	var t := r.theme
	# The signal table is derived from the blended colours, so it dies with every write.
	r.signal_colors = {}
	var text := _c(&"text")
	# Many light themes ship a text_dim that is barely visible on their background
	# (e.g. #c0c0c0 on #ffffff), so secondary text and 1 px borders get a contrast floor.
	var dim := _readable(&"text_dim")
	var bright := _c(&"text_bright")
	var accent := _c(&"accent")
	var select := _c(&"select")
	var floor_c := _c(&"floor")
	var floor_alt := _c(&"floor_alt")
	var inset := _inset()
	var danger := _c(&"danger")
	t.set_color(&"font_color", &"Label", text)
	t.set_color(&"font_color", &"Heading", bright)
	t.set_color(&"font_color", &"HeadingLarge", bright)
	t.set_color(&"font_color", &"Title", _readable(&"accent"))
	t.set_color(&"font_color", &"Dim", dim)
	t.set_color(&"font_color", &"Bright", bright)
	t.set_color(&"font_color", &"Accent", _readable(&"accent"))
	t.set_color(&"font_color", &"Danger", text_color(&"danger"))
	t.set_color(&"font_color", &"Heal", text_color(&"heal"))
	t.set_color(&"font_color", &"Loot", text_color(&"loot"))
	t.set_color(&"default_color", &"RichTextLabel", text)
	t.set_color(&"font_shadow_color", &"RichTextLabel", Color.TRANSPARENT)
	# Buttons.
	_fill(_style(&"button_normal"), floor_alt, dim)
	_fill(_style(&"button_hover"), floor_alt.lerp(select, 0.5), text)
	_fill(_style(&"button_pressed"), select, accent)
	_fill(_style(&"button_focus"), select, accent)
	_fill(_style(&"button_disabled"), _ca(&"floor_alt", 0.5), _ca(&"text_dim", 0.5))
	t.set_color(&"font_color", &"Button", text)
	t.set_color(&"font_hover_color", &"Button", bright)
	t.set_color(&"font_pressed_color", &"Button", bright)
	t.set_color(&"font_focus_color", &"Button", bright)
	t.set_color(&"font_hover_pressed_color", &"Button", bright)
	t.set_color(&"font_disabled_color", &"Button", dim)
	t.set_color(&"icon_normal_color", &"Button", text)
	t.set_color(&"icon_focus_color", &"Button", bright)
	t.set_color(&"icon_hover_color", &"Button", bright)
	t.set_color(&"icon_pressed_color", &"Button", bright)
	_fill(_style(&"danger_normal"), floor_alt, danger)
	_fill(_style(&"danger_hover"), danger.lerp(floor_alt, 0.6), danger)
	_fill(_style(&"danger_pressed"), danger, bright)
	_fill(_style(&"danger_focus"), danger.lerp(floor_alt, 0.4), bright)
	_fill(_style(&"danger_disabled"), _ca(&"floor_alt", 0.5), _ca(&"danger", 0.5))
	t.set_color(&"font_color", &"DangerButton", danger)
	t.set_color(&"font_hover_color", &"DangerButton", bright)
	t.set_color(&"font_pressed_color", &"DangerButton", bright)
	t.set_color(&"font_focus_color", &"DangerButton", bright)
	_fill(_style(&"tab_normal"), Color.TRANSPARENT, dim)
	_fill(_style(&"tab_hover"), _ca(&"select", 0.5), text)
	_fill(_style(&"tab_pressed"), select, accent)
	_fill(_style(&"tab_focus"), select, accent)
	_fill(_style(&"tab_disabled"), Color.TRANSPARENT, _ca(&"text_dim", 0.5))
	t.set_color(&"font_color", &"TabButton", dim)
	t.set_color(&"font_hover_color", &"TabButton", text)
	t.set_color(&"font_pressed_color", &"TabButton", bright)
	t.set_color(&"font_focus_color", &"TabButton", bright)
	# Panels.
	_fill(_style(&"panel"), floor_c, dim)
	_fill(_style(&"card"), floor_alt, dim)
	# A selected card must be legible as selected on a light theme too. `floor_alt.lerp(select)`
	# is a shade step of one hue, and on `white` it lands within a couple of values of the plain
	# card; `CardFit.selected_fill` keeps a floor on the contrast between the two whichever
	# direction the theme runs.
	_fill(_style(&"card_selected"), CardFit.selected_fill(floor_alt, select), accent)
	_fill(_style(&"overlay"), _ca(&"void", 0.82), Color.TRANSPARENT)
	_fill(_style(&"hud"), _ca(&"void", 0.7), _ca(&"text_dim", 0.6))
	# The resource block is the one plate that is never translucent: everything the palette
	# guard promises about HUD text is measured against `void`, and a plate you can see the
	# dungeon through is not `void` - it is void mixed with whatever tile is behind it.
	_fill(_style(&"hud_plate"), _c(&"void"), _ca(&"text_dim", 0.7))
	# LineEdit.
	_fill(_style(&"lineedit"), inset, dim)
	_fill(_style(&"lineedit_focus"), inset, accent)
	t.set_color(&"font_color", &"LineEdit", text)
	t.set_color(&"font_placeholder_color", &"LineEdit", dim)
	t.set_color(&"caret_color", &"LineEdit", accent)
	t.set_color(&"selection_color", &"LineEdit", select)
	# Sliders. Idle: an `accent` bar in an `inset` trough. Focused: the bar goes to `bright`
	# behind an `accent` edge and the row takes the same `select` slab with an `accent` border
	# that a focused check row takes, so "where is the controller" has one answer on this page
	# whichever kind of row it is standing on. `bright` is `text_bright`, which runs the
	# opposite way to the background on a light theme as it does on a dark one, so the bar
	# separates from both the trough and the idle accent on all six fixtures.
	_fill(_style(&"slider"), inset, dim)
	_style(&"slider").set_border_width_all(1)
	_fill(_style(&"grabber_area"), accent, Color.TRANSPARENT)
	_fill(_style(&"grabber_area_focus"), bright, accent)
	_fill(_style(&"slider_slab_focus"), select, accent)
	# Check boxes.
	_fill(_style(&"check_normal"), Color.TRANSPARENT, Color.TRANSPARENT)
	_fill(_style(&"check_hover"), _ca(&"select", 0.5), Color.TRANSPARENT)
	_fill(_style(&"check_pressed"), Color.TRANSPARENT, Color.TRANSPARENT)
	_fill(_style(&"check_hover_pressed"), _ca(&"select", 0.5), Color.TRANSPARENT)
	# The focused settings row is where a controller *is*, and a borderless slab of `select`
	# against `floor_alt` is a shade a player has to hunt for. Same accent border every other
	# focused control gets, so "where am I" has one answer across the whole UI.
	_fill(_style(&"check_focus"), select, accent)
	_fill(_style(&"check_disabled"), Color.TRANSPARENT, Color.TRANSPARENT)
	t.set_color(&"font_color", &"CheckBox", text)
	t.set_color(&"font_hover_color", &"CheckBox", bright)
	t.set_color(&"font_focus_color", &"CheckBox", bright)
	t.set_color(&"font_pressed_color", &"CheckBox", bright)
	t.set_icon(&"checked", &"CheckBox", _check_icon(true, text, accent))
	t.set_icon(&"unchecked", &"CheckBox", _check_icon(false, text, accent))
	t.set_icon(&"checked_disabled", &"CheckBox", _check_icon(true, dim, dim))
	t.set_icon(&"unchecked_disabled", &"CheckBox", _check_icon(false, dim, dim))
	# CheckBox sizes itself from the largest of every icon, radios included.
	t.set_icon(&"radio_checked", &"CheckBox", _check_icon(true, text, accent))
	t.set_icon(&"radio_unchecked", &"CheckBox", _check_icon(false, text, accent))
	t.set_icon(&"radio_checked_disabled", &"CheckBox", _check_icon(true, dim, dim))
	t.set_icon(&"radio_unchecked_disabled", &"CheckBox", _check_icon(false, dim, dim))
	t.set_color(&"icon_normal_color", &"CheckBox", Color.WHITE)
	# Progress bars.
	_fill(_style(&"progress_bg"), inset, dim)
	_fill(_style(&"progress_fill"), accent, Color.TRANSPARENT)
	t.set_color(&"font_color", &"ProgressBar", bright)
	# Scroll bars.
	_fill(_style(&"scroll"), Color(inset.r, inset.g, inset.b, 0.6), Color.TRANSPARENT)
	_fill(_style(&"scroll_grabber"), dim, Color.TRANSPARENT)
	(r.styles[&"separator"] as StyleBoxLine).color = _ca(&"text_dim", 0.6)
	(r.styles[&"vseparator"] as StyleBoxLine).color = _ca(&"text_dim", 0.6)
	t.set_icon(&"grabber", &"HSlider", _grabber_icon(text))
	t.set_icon(&"grabber_highlight", &"HSlider", _grabber_focus_icon(bright, accent))
	t.set_icon(&"grabber_disabled", &"HSlider", _grabber_icon(dim))
	t.emit_changed()


static func _fill(style: StyleBoxFlat, bg: Color, border: Color) -> void:
	style.bg_color = bg
	style.border_color = border


static func _check_icon(checked: bool, border: Color, fill: Color) -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var edge := x == 0 or y == 0 or x == 7 or y == 7
			if edge:
				img.set_pixel(x, y, border)
			elif checked and x >= 2 and x <= 5 and y >= 2 and y <= 5:
				img.set_pixel(x, y, fill)
	return ImageTexture.create_from_image(img)
