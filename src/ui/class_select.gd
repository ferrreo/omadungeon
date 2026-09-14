## Class selection: four cards with portrait, blurb, innate + class ability, and stat bars;
## left/right to browse.
##
## The innate passive and the class-only active are what actually separate a Fighter from a
## Wizard (docs §4.3), and the card used to name neither - so the first decision in the game
## was made off a one-line blurb and six bars. Both are now stated on the card, resolved from
## the ClassDef's `innate_passive_id` / `class_active_id` through the ability registry.
##
## A new player has one class and earns the rest (docs §12), so this screen is also where the
## meta-progression is read: a locked card states what unlocks it and how close the player is,
## and Down opens the unlock board - every gated class and ability, closest first. Before that
## the only thing a locked card said was "Locked: beat floor 3 to unlock", hard-coded, for
## whichever class happened to be locked.
##
## Class data comes from data/classes/*.tres when present (duck-typed ClassDef:
## id, display_name, description, base_stats Dictionary or vitality..fortune ints,
## innate_passive_id, class_active_id), otherwise from the built-in placeholders matching
## docs §4.2.
class_name ClassSelect
extends Control

signal class_chosen(class_id: StringName)
signal back_pressed

const CLASS_DIR := "res://data/classes"
const PORTRAIT_DIR := "res://assets/sprites/player"
const STAT_MAX := 8
## Card width. Four of these plus the row's separation fill the 480 px screen exactly; every
## pixel here is a character the blurb and the trait lines do not have to wrap.
const CARD_WIDTH := 109
## Horizontal padding the card panel's stylebox takes out of `CARD_WIDTH`.
const CARD_PADDING := 12
## Smallest the blurb block may get, so every card's stat grid still starts on the same line.
## The block is an expanding child, so it grows into whatever the card has left over; only its
## minimum is fixed, and no description can push the cards past the screen.
const DESC_MIN_HEIGHT := 56
# The blurb box is the **only** expanding block on a card, and every other block is given the
# height of the tallest card's copy of it (`_shared_heights`). That is what puts the four cards
# on one grid: the portrait, the class name, the two trait lines and the stat bars all start on
# the same line whatever any one class is called or however long its ability's name is. Before
# it, "Ability: Hostile Takeover" wrapped where "Ability: Bulwark" did not, the card with the
# shorter block handed the difference to its blurb box, and the Oligarch's traits sat a full
# line below everybody else's.
## Extra pixels between wrapped lines on a card. The theme default (3) costs a card two whole
## lines at 480x270, and the blurb plus the two trait lines are the text the choice is made on.
const DESC_LINE_SPACING := 0
## Height of the unlock board overlay, in the 480x270 internal resolution, and its width.
const BOARD_SIZE := Vector2(352.0, 196.0)
## How much of the theme's own background the board lays over the cards behind it.
const BOARD_SCRIM_ALPHA := 0.86
## Pixels one ui_up/ui_down step scrolls the board.
const BOARD_SCROLL_STEP := 18
## Capture lever (`--show-unlocks`): opens the unlock board on load, so `tools/run-scenario.sh
## class_select --show-unlocks` can photograph it. The scenario driver presses its own keys and
## is not this screen's to teach, and a board nobody ever renders is a board nobody reviews.
const ARG_SHOW_BOARD := "show-unlocks"
## Smallest the portrait's "Locked" badge may be. Nothing is subtracted from the blurb for it
## any more: the badge overlays the portrait instead of taking a row from the description.
const LOCK_BADGE_HEIGHT := 16
## The two defining traits of a class, in the order the card states them: the caption shown,
## and the key of the ability id in a class entry. The caption is part of the line rather than
## a column of its own - a 94 px card has no room for both a caption column and "Hostile
## Takeover", and a truncated "HOSTILE T..." states nothing.
const TRAIT_ROWS: Array[Dictionary] = [
	{"label": "Innate", "key": "innate"},
	{"label": "Ability", "key": "active"},
]

const PLACEHOLDERS: Array[Dictionary] = [
	{
		"id": &"fighter",
		"name": "Fighter",
		"description": "Melee, sustain, knockback. Rusty sword, three-hit combo.",
		"innate": &"second_wind",
		"active": &"bulwark",
		"stats":
		{"vitality": 6, "might": 6, "precision": 2, "arcana": 1, "swiftness": 3, "fortune": 2},
	},
	{
		"id": &"ranger",
		"name": "Ranger",
		"description": "Ranged, mobile, immune to traps while dashing.",
		"innate": &"sure_footed",
		"active": &"volley",
		"stats":
		{"vitality": 3, "might": 2, "precision": 6, "arcana": 2, "swiftness": 5, "fortune": 2},
	},
	{
		"id": &"wizard",
		"name": "Wizard",
		"description": "Abilities and cooldowns. Fragile. Blinks instead of rolling.",
		"innate": &"overflow",
		"active": &"chain_lightning",
		"stats":
		{"vitality": 2, "might": 1, "precision": 2, "arcana": 7, "swiftness": 4, "fortune": 4},
	},
	{
		"id": &"oligarch",
		"name": "Oligarch",
		"description": "Economy and luck. Pays for chests, hires bodyguards.",
		"innate": &"buyout",
		"active": &"hostile_takeover",
		"stats":
		{"vitality": 4, "might": 3, "precision": 3, "arcana": 2, "swiftness": 2, "fortune": 6},
	},
]

## Class ids that cannot be picked yet (e.g. oligarch before beating floor 3).
## Assigning refreshes the cards, so it can be set before or after the node is ready.
var locked_ids: Array[StringName] = []:
	set(value):
		locked_ids = value
		if is_node_ready() and not _cards.is_empty():
			_refresh_cards()
			_refresh_hint()
var classes: Array[Dictionary] = []
## Unlock progress rows (`SaveManager.progress_rows()`). Read from the autoload when the screen
## is built; assignable so the gallery and the tests can show a known profile.
var unlock_rows: Array[Dictionary] = []:
	set(value):
		unlock_rows = value
		if is_node_ready() and not _cards.is_empty():
			_refresh_cards()
			_refresh_hint()
			_fill_board()

var _selected: int = 0
var _cards: Array[PanelContainer] = []
var _board: Control = null
var _board_scroll: ScrollContainer = null
var _board_grid: GridContainer = null
var _board_scrim: ColorRect = null

@onready var _cards_row: HBoxContainer = %Cards
@onready var _hint: UiPrompt = %Hint
@onready var _back: Button = %Back
@onready var _confirm: Button = %Confirm


func _ready() -> void:
	UiTheme.apply(self)
	# The cards draw their own selection and focus nothing, so the stick has to be served.
	UiStickNav.serve(self)
	classes = load_classes()
	if unlock_rows.is_empty():
		unlock_rows = load_progress()
	_build_cards()
	_build_board()
	if GameState.cli_args.has(ARG_SHOW_BOARD):
		set_board_visible.call_deferred(true)
	_back.pressed.connect(func() -> void: back_pressed.emit())
	_confirm.pressed.connect(confirm)
	_back.focus_mode = Control.FOCUS_NONE
	_confirm.focus_mode = Control.FOCUS_NONE
	EventBus.palette_changed.connect(_on_palette_changed)
	EventBus.input_device_changed.connect(func(_d: int) -> void: _refresh_hint())
	select(0)


func _input(event: InputEvent) -> void:
	InputGlyphs.observe(event)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if board_visible():
		if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"ui_accept"):
			set_board_visible(false)
			accept_event()
		elif event.is_action_pressed(&"ui_down"):
			scroll_board(BOARD_SCROLL_STEP)
			accept_event()
		elif event.is_action_pressed(&"ui_up"):
			scroll_board(-BOARD_SCROLL_STEP)
			accept_event()
		return
	if event.is_action_pressed(&"ui_down"):
		set_board_visible(true)
		accept_event()
	elif event.is_action_pressed(&"ui_right"):
		select(_selected + 1)
		accept_event()
	elif event.is_action_pressed(&"ui_left"):
		select(_selected - 1)
		accept_event()
	elif event.is_action_pressed(&"ui_accept"):
		confirm()
		accept_event()
	elif event.is_action_pressed(&"ui_cancel"):
		back_pressed.emit()
		accept_event()


## Loads ClassDef resources from data/classes, falling back to placeholders.
## Loads a fixed id list rather than scanning the directory: in an exported build the
## .tres files become .res / .tres.remap inside the pack and a DirAccess scan finds none.
static func load_classes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in class_ids():
		var res := _load_class(id)
		if res == null:
			continue
		var entry := _entry_from_resource(res)
		if not entry.is_empty():
			out.append(entry)
	if out.is_empty():
		for p: Dictionary in PLACEHOLDERS:
			out.append(p.duplicate(true))
	else:
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _order(a) < _order(b))
	return out


## Known class ids: the built-in order, plus any extra .tres/.res found on disk (editor runs).
static func class_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in PLACEHOLDERS:
		ids.append(entry["id"])
	var dir := DirAccess.open(CLASS_DIR)
	if dir == null:
		return ids
	var files := dir.get_files()
	files.sort()
	for file: String in files:
		var id := StringName(file.trim_suffix(".remap").get_basename())
		if not ids.has(id):
			ids.append(id)
	return ids


## Loads one class resource, tolerating the .res / .tres.remap spellings of exported packs.
static func _load_class(id: StringName) -> Resource:
	for ext: String in [".tres", ".res"]:
		var path := "%s/%s%s" % [CLASS_DIR, id, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


static func _order(entry: Dictionary) -> int:
	for i in PLACEHOLDERS.size():
		if PLACEHOLDERS[i]["id"] == entry["id"]:
			return i
	return PLACEHOLDERS.size()


static func _entry_from_resource(res: Resource) -> Dictionary:
	var id: Variant = res.get("id")
	if id == null:
		return {}
	var stats: Dictionary = {}
	var base: Variant = res.get("base_stats")
	if base is Dictionary:
		for key: Variant in (base as Dictionary).keys():
			stats[StringName(str(key))] = int(base[key])
	else:
		for stat: StringName in Stats.PRIMARY:
			var v: Variant = res.get(stat)
			stats[stat] = int(v) if v != null else 0
	var name: Variant = res.get("display_name")
	var desc: Variant = res.get("description")
	var innate: Variant = res.get("innate_passive_id")
	var active: Variant = res.get("class_active_id")
	return {
		"id": StringName(str(id)),
		"name": str(name) if name != null else str(id).capitalize(),
		"description": str(desc) if desc != null else "",
		"innate": StringName(str(innate)) if innate != null else &"",
		"active": StringName(str(active)) if active != null else &"",
		"stats": stats,
	}


## Display name of an ability id, through the registry when it has one and a de-slugged id
## when it does not ("chain_lightning" -> "Chain Lightning"). Never empty for a real id, so a
## card can always state the trait rather than showing a blank row.
static func ability_name(id: StringName) -> String:
	if id == &"":
		return ""
	var registry := _ability_registry()
	if registry != null:
		var ability := registry.find(id)
		if ability != null and not ability.display_name.is_empty():
			return ability.display_name
	return String(id).replace("_", " ").capitalize()


## The trait names a class entry states on its card, in `TRAIT_ROWS` order.
static func trait_names(entry: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in TRAIT_ROWS:
		out.append(ability_name(StringName(str(entry.get(row["key"], &"")))))
	return out


static func _ability_registry() -> AbilityRegistry:
	var shared := UiRuntime.get_shared()
	if shared.ability_registry == null:
		shared.ability_registry = AbilityRegistry.load_default()
	return shared.ability_registry


func select(index: int) -> void:
	if classes.is_empty():
		return
	_selected = wrapi(index, 0, classes.size())
	_refresh_cards()
	_refresh_hint()


func selected_id() -> StringName:
	return classes[_selected]["id"] if not classes.is_empty() else &""


func is_locked(id: StringName) -> bool:
	return locked_ids.has(id)


func confirm() -> void:
	var id := selected_id()
	if id == &"" or is_locked(id):
		_shake_selected()
		return
	class_chosen.emit(id)


func _build_cards() -> void:
	for child in _cards_row.get_children():
		_cards_row.remove_child(child)
		child.queue_free()
	_cards.clear()
	var shared := _shared_heights()
	for i in classes.size():
		var entry := classes[i]
		var card := PanelContainer.new()
		card.theme_type_variation = &"Card"
		card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_card_input.bind(i))
		var box := VBoxContainer.new()
		# No gap between the card's blocks: at 480x270 every pixel between the portrait and the
		# stat bars is a line the blurb does not get, and the blurb is what the choice is made
		# on. The blocks are distinct enough without air between them.
		box.add_theme_constant_override("separation", UiTheme.GAP_NONE)
		card.add_child(box)
		var portrait := TextureRect.new()
		portrait.name = "Portrait"
		portrait.custom_minimum_size = Vector2(32, 32)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var tex := UiTheme.load_texture("%s/%s_portrait.png" % [PORTRAIT_DIR, entry["id"]])
		if tex != null:
			portrait.texture = tex
		else:
			portrait.texture = _placeholder_portrait(str(entry["name"]))
		box.add_child(portrait)
		var name := Label.new()
		name.name = "Name"
		name.theme_type_variation = &"Heading"
		name.text = str(entry["name"])
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.custom_minimum_size.y = float(shared["name"])
		box.add_child(name)
		var desc_box := Control.new()
		desc_box.name = "DescBox"
		desc_box.custom_minimum_size = Vector2(CARD_WIDTH - CARD_PADDING, DESC_MIN_HEIGHT)
		desc_box.clip_contents = true
		desc_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(desc_box)
		var desc := Label.new()
		desc.name = "Description"
		desc.theme_type_variation = &"Dim"
		desc.text = str(entry["description"])
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_constant_override("line_spacing", DESC_LINE_SPACING)
		desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_box.add_child(desc)
		desc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.add_child(_trait_block(entry, float(shared["traits"])))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", UiTheme.GAP)
		grid.add_theme_constant_override("v_separation", UiTheme.GAP_NONE)
		var stats: Dictionary = entry["stats"]
		for stat: StringName in Stats.PRIMARY:
			var label := Label.new()
			label.text = String(stat).substr(0, 3).to_upper()
			label.theme_type_variation = &"Dim"
			label.custom_minimum_size = Vector2(24, 0)
			grid.add_child(label)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(56, 6)
			bar.max_value = STAT_MAX
			bar.value = int(stats.get(stat, 0))
			bar.show_percentage = false
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(bar)
		box.add_child(grid)
		var lock_badge := PanelContainer.new()
		lock_badge.name = "LockIcon"
		lock_badge.theme_type_variation = &"Hud"
		lock_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_badge.custom_minimum_size = Vector2(0, LOCK_BADGE_HEIGHT)
		lock_badge.visible = false
		var lock_row := HBoxContainer.new()
		lock_row.add_theme_constant_override("separation", UiTheme.GAP_TIGHT)
		lock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_badge.add_child(lock_row)
		var lock_icon := TextureRect.new()
		lock_icon.texture = UiTheme.icon(UiTheme.Icon.LOCK)
		lock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock_icon.custom_minimum_size = Vector2(16, 16)
		lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_row.add_child(lock_icon)
		# The stamp rides the padlock badge over the portrait instead of taking a line off the
		# blurb. The Oligarch - the one locked class, whose whole identity is a gimmick its
		# description has to explain - was truncated mid-sentence to make room for it.
		var lock := Label.new()
		lock.name = "Lock"
		lock.theme_type_variation = &"Danger"
		lock.text = ""
		lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_row.add_child(lock)
		portrait.add_child(lock_badge)
		lock_badge.set_anchors_and_offsets_preset(
			Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE
		)
		_cards_row.add_child(card)
		_cards.append(card)


## "Innate: Second Wind" / "Ability: Bulwark": the two lines that say what the class *is*.
## Each takes the whole card width and wraps rather than truncating, because the name is the
## payload. `shared_height` is the tallest card's block, so a class whose ability name fits on
## one line still reserves the room the longest one needs and the stat bars below stay level.
## Named so `find_child("Traits")` can read them back in a test.
func _trait_block(entry: Dictionary, shared_height: float = 0.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Traits"
	box.add_theme_constant_override("separation", UiTheme.GAP_NONE)
	box.custom_minimum_size.y = shared_height
	var body := UiTheme.body_font()
	for text: String in trait_lines(entry):
		var line := Label.new()
		line.text = text
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_constant_override("line_spacing", DESC_LINE_SPACING)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# An autowrapped Label reports a one-line minimum whatever it holds, so the second
		# line a wrapped trait name needs has to be asked for or the block clips it.
		line.custom_minimum_size.y = (
			body.get_height(UiTheme.SIZE_S) * wrapped_lines(text, body, text_width())
		)
		box.add_child(line)
	return box


## The two trait lines of `entry`, exactly as the card prints them.
func trait_lines(entry: Dictionary) -> PackedStringArray:
	var names := trait_names(entry)
	var out: PackedStringArray = []
	for i in TRAIT_ROWS.size():
		out.append("%s: %s" % [TRAIT_ROWS[i]["label"], names[i] if i < names.size() else ""])
	return out


## Width a card's text block has to wrap inside.
func text_width() -> float:
	return float(CARD_WIDTH - CARD_PADDING)


## Lines `text` wraps to in `font` at `width` (at least one).
static func wrapped_lines(text: String, font: Font, width: float) -> int:
	var line_h := maxf(1.0, font.get_height(UiTheme.SIZE_S))
	var total := font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, width, UiTheme.SIZE_S
	)
	return maxi(1, int(roundf(total.y / line_h)))


## The height every card gives its class name and its trait block: the tallest card's. This is
## the one grid the four cards share, and it is measured rather than guessed, so a longer
## ability name in a `.tres` moves all four cards together instead of only its own.
func _shared_heights() -> Dictionary:
	var heading := UiTheme.heading_font()
	var body := UiTheme.body_font()
	var width := text_width()
	var name_lines := 1
	var trait_height := 0.0
	for entry: Dictionary in classes:
		name_lines = maxi(name_lines, wrapped_lines(str(entry["name"]), heading, width))
		var lines := 0
		for text: String in trait_lines(entry):
			lines += wrapped_lines(text, body, width)
		trait_height = maxf(trait_height, body.get_height(UiTheme.SIZE_S) * lines)
	return {
		"name": ceilf(heading.get_height(UiTheme.SIZE_S) * name_lines),
		"traits": ceilf(trait_height)
	}


func _on_palette_changed(_palette: ThemePalette) -> void:
	_refresh_cards()
	if _board_scrim != null:
		_board_scrim.color = _board_scrim_color()


func _placeholder_portrait(name: String) -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var base := UiTheme.color(&"floor_alt")
	var accent := UiTheme.color(&"accent")
	img.fill(base)
	for y in 32:
		for x in 32:
			var edge := x == 0 or y == 0 or x == 31 or y == 31
			var head := Vector2(x - 15.5, y - 11).length() < 6.0
			var body := y > 17 and y < 29 and absi(x - 15) < 6 - (y - 17) / 4
			if edge:
				img.set_pixel(x, y, UiTheme.color(&"text_dim"))
			elif head or body:
				img.set_pixel(x, y, accent if name.hash() % 2 == 0 else UiTheme.color(&"magic"))
	return ImageTexture.create_from_image(img)


func _refresh_cards() -> void:
	for i in _cards.size():
		var card := _cards[i]
		var locked := is_locked(classes[i]["id"])
		card.theme_type_variation = &"CardSelected" if i == _selected else &"Card"
		card.modulate = Color(1, 1, 1, 0.65) if locked else Color.WHITE
		var lock := card.find_child("Lock", true, false) as Label
		if lock != null:
			lock.text = "Locked" if locked else ""
		var lock_badge := card.find_child("LockIcon", true, false) as Control
		if lock_badge != null:
			lock_badge.visible = locked
		# No scale pop on the selected card. Scaling a card about its centre lifts everything in
		# it - the portrait sat about eight native pixels above the other three - and the whole
		# point of this screen is four cards a player can read across. The selection is carried
		# by three channels the layout does not feel instead: `CardSelected` is a different fill
		# (with a contrast floor, so a flat theme cannot collapse the two together), a different
		# border colour, and a border three times as thick. Recolouring the class name was tried
		# as a fourth and dropped: on `white` the accent role is a mid grey, so the selected
		# card's name came out *fainter* than the other three and read as disabled.
		card.scale = Vector2.ONE


func _refresh_hint() -> void:
	var pad := InputGlyphs.current_device() == InputGlyphs.Device.GAMEPAD
	var move := "{#dpad}{#lstick}" if pad else "{ui_left}{ui_right}"
	_hint.text = "%s browse   {ui_accept} confirm   {ui_cancel} back   {ui_down} unlocks" % move
	if not classes.is_empty() and is_locked(selected_id()):
		var text := requirement_text(selected_id())
		_hint.text = "Locked - %s" % text if not text.is_empty() else "Locked"


## Progress rows from the `SaveManager` autoload, or an empty list when it is not up (tests,
## the gallery). Never reaches for the real profile file itself: `SaveManager` owns that, and
## it is the thing that redirects into a sandbox during a test run.
static func load_progress() -> Array[Dictionary]:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return []
	var save_manager := tree.root.get_node_or_null(^"/root/SaveManager")
	if save_manager == null or not save_manager.has_method(&"progress_rows"):
		return []
	var rows: Variant = save_manager.call(&"progress_rows")
	var out: Array[Dictionary] = []
	if rows is Array:
		for row: Variant in rows as Array:
			if row is Dictionary:
				out.append(row as Dictionary)
	return out


## The progress row for an unlock id, or `{}` when the id is not gated.
func row_for(id: StringName) -> Dictionary:
	for row: Dictionary in unlock_rows:
		if StringName(str(row.get("id", ""))) == id:
			return row
	return {}


## "Clear a floor.  0 / 1" - what a locked card says instead of a padlock and nothing else.
func requirement_text(id: StringName) -> String:
	var row := row_for(id)
	if row.is_empty():
		return ""
	var description := str(row.get("description", ""))
	var progress := str(row.get("progress", ""))
	if description.is_empty():
		return progress
	return "%s  %s" % [description, progress] if not progress.is_empty() else description


## True while the unlock board is up.
func board_visible() -> bool:
	return _board != null and _board.visible


## Opens or closes the unlock board.
func set_board_visible(on: bool) -> void:
	if _board == null:
		return
	if on:
		_fill_board()
		_board_scroll.scroll_vertical = 0
	_board.visible = on


## Scrolls the board by `delta` pixels, clamped. Returns the new offset. Nothing inside it can
## take focus, so this is the only way a controller reaches the bottom of the list.
func scroll_board(delta: int) -> int:
	if _board_scroll == null or _board_grid == null:
		return 0
	var limit := maxi(0, int(ceilf(_board_grid.size.y - _board_scroll.size.y)))
	_board_scroll.scroll_vertical = clampi(_board_scroll.scroll_vertical + delta, 0, limit)
	return _board_scroll.scroll_vertical


## Rows currently rendered on the board (tests read this back).
func board_row_count() -> int:
	return 0 if _board_grid == null else _board_grid.get_child_count() / 3


## Every gated class and ability, what earns it and how close it is. Built in code so the class
## select scene stays the row of cards it is.
func _build_board() -> void:
	_board = Control.new()
	_board.name = "UnlockBoard"
	_board.visible = false
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_scrim = ColorRect.new()
	_board_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_scrim.color = _board_scrim_color()
	_board.add_child(_board_scrim)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = &"Card"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -BOARD_SIZE.x * 0.5
	panel.offset_right = BOARD_SIZE.x * 0.5
	panel.offset_top = -BOARD_SIZE.y * 0.5
	panel.offset_bottom = BOARD_SIZE.y * 0.5
	_board.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", UiTheme.GAP_TIGHT)
	panel.add_child(box)
	var heading := Label.new()
	heading.name = "BoardTitle"
	heading.theme_type_variation = &"Heading"
	heading.text = "Unlocks"
	box.add_child(heading)
	_board_scroll = ScrollContainer.new()
	_board_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_board_scroll)
	_board_grid = GridContainer.new()
	_board_grid.columns = 3
	_board_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_grid.add_theme_constant_override("h_separation", UiTheme.GAP)
	_board_grid.add_theme_constant_override("v_separation", UiTheme.GAP_TIGHT)
	_board_scroll.add_child(_board_grid)
	var footer := UiPrompt.new()
	footer.name = "BoardHint"
	footer.text = "{ui_up}{ui_down} scroll   {ui_cancel} or {ui_accept} close"
	box.add_child(footer)
	add_child(_board)
	_fill_board()


func _fill_board() -> void:
	if _board_grid == null:
		return
	for child in _board_grid.get_children():
		_board_grid.remove_child(child)
		child.queue_free()
	if unlock_rows.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"Dim"
		empty.text = "Nothing to unlock."
		_board_grid.add_child(empty)
		_board_grid.add_child(Label.new())
		_board_grid.add_child(Label.new())
		return
	for row: Dictionary in unlock_rows:
		var unlocked := bool(row.get("unlocked", false))
		var name := Label.new()
		name.text = str(row.get("title", ""))
		name.theme_type_variation = &"Bright" if unlocked else &"Accent"
		name.custom_minimum_size = Vector2(78, 0)
		name.size_flags_vertical = Control.SIZE_FILL
		name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_board_grid.add_child(name)
		var what := Label.new()
		what.theme_type_variation = &"Dim"
		what.text = (
			"%s - earned" % str(row.get("kind", ""))
			if unlocked
			else str(row.get("description", ""))
		)
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_board_grid.add_child(what)
		var progress := Label.new()
		progress.theme_type_variation = &"Heal" if unlocked else &"Bright"
		progress.text = str(row.get("progress", ""))
		progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		progress.custom_minimum_size = Vector2(46, 0)
		progress.size_flags_vertical = Control.SIZE_FILL
		progress.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_board_grid.add_child(progress)


## Theme-coloured rather than black, so a light desktop dims to its own background.
func _board_scrim_color() -> Color:
	var base := Desktop.palette.get_color(&"void") if Desktop.palette != null else Color.BLACK
	return Color(base.r, base.g, base.b, BOARD_SCRIM_ALPHA)


func _shake_selected() -> void:
	if _cards.is_empty() or not Accessibility.animates():
		return
	var card := _cards[_selected]
	var origin := card.position
	var tween := create_tween()
	for i in 4:
		var dx := 2.0 if i % 2 == 0 else -2.0
		tween.tween_property(card, "position:x", origin.x + dx, 0.03)
	tween.tween_property(card, "position:x", origin.x, 0.03)


func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if _selected == index:
				confirm()
			else:
				select(index)
