## The build screen: what the player has right now, on one page. The class, the two actives
## and two passives (with cooldowns and their full descriptions), the innate and the weapon
## skill, every equipment slot with the item's lines, and the stat sheet with where each
## number comes from. This is where "what do I have?" is answered; the compare screen and the
## floor tooltip read the same rows (`LoadoutModel`, `CompareRows`), so the numbers agree.
##
## Opened by the `map` action (Tab, or Back on a pad) from the run, and embedded as the
## pause menu's Build tab (`standalone = false`). Two columns, each scrolling on its own: the
## build on the left, the sheet on the right; left/right pick the column, up/down scroll it.
## Fully controller-driven, and nothing on it needs a mouse.
class_name LoadoutScreen
extends Control

signal closed

## Pixels one ui_up/ui_down step scrolls the focused column.
const SCROLL_STEP := 24
const ICON := 16
## Width of the slot / stat caption column, set by the longest caption ("Weapon skill").
const CAPTION_WIDTH := 60.0
## Width of the value column on the sheet, and of the since-last-look delta beside it.
const VALUE_WIDTH := 32.0
const DELTA_WIDTH := 12.0
## Width the sheet column keeps, so a source line is never squeezed to a word a line by a
## long ability name on the other side.
const SHEET_WIDTH := 184.0
## Captions.
const ABILITIES_HEADING := "Abilities"
const GEAR_HEADING := "Gear"
const STATS_HEADING := "Stats"
const ACTIVE_CAPTIONS: PackedStringArray = ["Active 1", "Active 2"]
const PASSIVE_CAPTIONS: PackedStringArray = ["Passive 1", "Passive 2"]
const INNATE_CAPTION := "Innate"
const SKILL_CAPTION := "Weapon skill"
const POTION_CAPTION := "Potion"
const EMPTY_TEXT := "Empty"
## Actions the two active slots fire, for the glyph beside each.
const ACTIVE_ACTIONS: Array[StringName] = [&"active_1", &"active_2"]
const SKILL_ACTION := &"secondary"
## The seed line, the one technical detail the screen carries, tucked into its footer.
const SEED_LINE := "Seed %d"

## Whether to draw as its own overlay (dim, panel, close button, footer) or as a page inside
## the pause menu, which supplies all of those itself.
@export var standalone: bool = true

var player: Node
## Which column the pad is scrolling: 0 the build, 1 the sheet.
var column: int = 0
## The model the page was last built from (tests read it rather than the nodes).
var model: Dictionary = {}

var _is_open: bool = false
## Primary totals as of the last `mark_seen`; the sheet marks what moved since.
var _baseline: Dictionary = {}
var _floor_text: String = ""
var _run_seed: int = 0
var _headings: Array[Label] = []

@onready var _dim: PanelContainer = %Dim
@onready var _panel: PanelContainer = %Panel
@onready var _header: HBoxContainer = %Header
@onready var _title: Label = %Title
@onready var _context: Label = %Context
@onready var _close: Button = %Close
@onready var _build_scroll: ScrollContainer = %BuildScroll
@onready var _build_list: VBoxContainer = %BuildList
@onready var _stats_scroll: ScrollContainer = %StatsScroll
@onready var _stats_list: VBoxContainer = %StatsList
@onready var _footer: HBoxContainer = %Footer
@onready var _hint: UiPrompt = %Hint
@onready var _technical: Label = %Technical


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiTheme.apply(self)
	UiStickNav.serve(self)
	_close.pressed.connect(close)
	_close.focus_mode = Control.FOCUS_NONE
	_dim.visible = standalone
	_footer.visible = standalone
	_close.visible = standalone
	# The pause menu has its own header; a second one under it was the class name floating
	# between the tab strip and the page.
	_header.visible = standalone
	_stats_scroll.custom_minimum_size.x = SHEET_WIDTH
	if not standalone:
		# The pause menu's panel is the frame; a second border inside it is a box in a box.
		_panel.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
		_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	EventBus.input_device_changed.connect(func(_d: int) -> void: _refresh_hint())
	EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: _refresh_headings())
	_refresh_hint()
	if standalone and not _is_open:
		visible = false


func _input(event: InputEvent) -> void:
	InputGlyphs.observe(event)


## Whether this copy of the screen is actually on screen and may answer - and consume - the
## directional actions.
##
## `standalone and not _is_open` was the whole test, and it covered the in-run overlay only.
## The pause menu builds a *second*, non-standalone copy as its Build tab
## (`PauseMenu._build_pages`), that copy is `PROCESS_MODE_ALWAYS` like every other screen, and
## with `standalone` false the old guard let it through even while the pause menu was shut.
## It then claimed every `ui_left`/`ui_right`/`ui_up`/`ui_down` in the game and called
## `set_input_as_handled()`, and because it sits after `ChestUi` in the overlay it was served
## first: the chest, shop, swap and cursed boards never saw a single directional press, from a
## d-pad, from the left stick (`UiStickNav` sends the stick as d-pad buttons) or from the
## arrow keys. That is the owner's "the controller is not working to move selection in the
## loot menus".
##
## Visibility is the honest question for both copies: the embedded one is visible exactly
## while the pause menu is open on the Build tab, and the standalone one hides itself when it
## is not open (see `_ready`), so `_is_open` stays as the explicit half of the test for it.
func takes_input() -> bool:
	if not is_visible_in_tree():
		return false
	return _is_open if standalone else true


func _unhandled_input(event: InputEvent) -> void:
	if not takes_input():
		return
	if event.is_action_pressed(&"ui_cancel") or (standalone and event.is_action_pressed(&"map")):
		if standalone:
			close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_left"):
		set_column(column - 1)
	elif event.is_action_pressed(&"ui_right"):
		set_column(column + 1)
	elif event.is_action_pressed(&"ui_down"):
		scroll_by(SCROLL_STEP)
	elif event.is_action_pressed(&"ui_up"):
		scroll_by(-SCROLL_STEP)
	else:
		return
	get_viewport().set_input_as_handled()


func bind(new_player: Node) -> void:
	player = new_player
	if _is_open or not standalone:
		refresh()


## The floor line printed beside the class ("Floor 3 - Crypt"), and the seed for the footer.
func set_context(floor_text: String, run_seed: int) -> void:
	_floor_text = floor_text
	_run_seed = run_seed
	_refresh_header()


func is_open() -> bool:
	return _is_open


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


## Shows the screen over the run and pauses it, the way the pause menu does.
func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	if standalone:
		get_tree().paused = true
		EventBus.music_duck.emit(0.4, true)
	refresh()
	set_column(0)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	if standalone:
		get_tree().paused = false
		EventBus.music_duck.emit(0.4, false)
		visible = false
	closed.emit()


## A screen freed while open must not leave the tree paused.
func _exit_tree() -> void:
	if not _is_open or not standalone:
		return
	_is_open = false
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	EventBus.music_duck.emit(0.4, false)


## Which column the pad scrolls; wraps.
func set_column(index: int) -> void:
	column = wrapi(index, 0, 2)
	_refresh_headings()
	_refresh_hint()


## Scrolls the focused column by `delta` pixels, clamped. Returns the new offset.
func scroll_by(delta: int) -> int:
	var scroll := _build_scroll if column == 0 else _stats_scroll
	var list := _build_list if column == 0 else _stats_list
	var limit := maxi(0, int(list.size.y - scroll.size.y))
	scroll.scroll_vertical = clampi(scroll.scroll_vertical + delta, 0, limit)
	return scroll.scroll_vertical


## Snapshots the primaries so the next refresh can say what changed in between. An enemy
## stealing a point is announced live, but "what moved while I was playing" is the question
## this page exists to answer, and the old Stats page showed only the totals.
func mark_seen() -> void:
	var stats := LoadoutModel.stats_of(player)
	if stats == null:
		return
	for stat: StringName in Stats.PRIMARY:
		_baseline[stat] = stats.primary(stat)


## Rebuilds both columns from the bound player.
func refresh() -> void:
	model = LoadoutModel.build(player)
	_refresh_header()
	_clear(_build_list)
	_clear(_stats_list)
	_headings.clear()
	_build_list.add_child(_heading(ABILITIES_HEADING, 0))
	var actives: Array = model["actives"]
	for i in actives.size():
		_build_list.add_child(_ability_row(ACTIVE_CAPTIONS[i], actives[i], ACTIVE_ACTIONS[i]))
	var passives: Array = model["passives"]
	for i in passives.size():
		_build_list.add_child(_ability_row(PASSIVE_CAPTIONS[i], passives[i], &""))
	for innate: Variant in model["innates"]:
		_build_list.add_child(_ability_row(INNATE_CAPTION, innate, &""))
	var skill := model["skill"] as Ability
	if skill != null:
		_build_list.add_child(_ability_row(SKILL_CAPTION, skill, SKILL_ACTION))
	_build_list.add_child(_heading(GEAR_HEADING, 0))
	for row: Dictionary in model["equipment"]:
		_build_list.add_child(_gear_row(str(row["label"]), row["item"] as ItemInstance))
	_build_list.add_child(_potion_row())
	_stats_list.add_child(_heading(STATS_HEADING, 1))
	var rows: Array[Dictionary] = model["stats"]
	var was_primary := true
	for row: Dictionary in rows:
		if was_primary and not bool(row["primary"]):
			# A blank line between the six primaries and the derived numbers.
			_stats_list.add_child(_spacer())
		was_primary = bool(row["primary"])
		_stats_list.add_child(_stat_row(row))
	_build_scroll.scroll_vertical = 0
	_stats_scroll.scroll_vertical = 0
	_refresh_headings()


func _refresh_header() -> void:
	if _title == null:
		return
	_title.text = str(model.get("class", LoadoutModel.NO_CLASS))
	_context.text = _floor_text
	_technical.text = SEED_LINE % _run_seed if _run_seed != 0 else ""


func _refresh_hint() -> void:
	if _hint == null:
		return
	var pad := InputGlyphs.current_device() == InputGlyphs.Device.GAMEPAD
	var move := "{#dpad}{#lstick}" if pad else "{ui_left}{ui_right}{ui_up}{ui_down}"
	_hint.text = "%s column and scroll   {ui_cancel} close" % move


## The heading of the column the pad is on is drawn bright, the other dim.
func _refresh_headings() -> void:
	for heading: Label in _headings:
		var own := int(heading.get_meta(&"column", 0)) == column
		heading.theme_type_variation = &"Accent" if own else &"Dim"


func _heading(text: String, own_column: int) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = &"Dim"
	label.set_meta(&"column", own_column)
	_headings.append(label)
	return label


## One ability row: caption, icon, name with tier, the cooldown (and what is left of it), the
## button that fires it, and the description in full under them.
func _ability_row(caption: String, ability: Variant, action: StringName) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", UiTheme.GAP)
	line.add_child(_caption(caption))
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(icon)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", UiTheme.GAP_NONE)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(body)
	var ab := ability as Ability
	if ab == null:
		var empty := Label.new()
		empty.theme_type_variation = &"Dim"
		empty.text = EMPTY_TEXT
		body.add_child(empty)
		return line
	icon.texture = UiTheme.icon_for(ab)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", UiTheme.GAP)
	body.add_child(head)
	var name := Label.new()
	name.theme_type_variation = &"Bright"
	name.text = LoadoutModel.ability_title(ab)
	name.add_theme_color_override(&"font_color", UiTheme.text_color(CompareView.role_for(ab)))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	if action != &"":
		var glyph := GlyphIcon.new()
		glyph.action = action
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(glyph)
	if ab is ActiveAbility:
		var meta := Label.new()
		meta.theme_type_variation = &"Dim"
		meta.text = cooldown_text(ab)
		body.add_child(meta)
	var desc := Label.new()
	desc.theme_type_variation = &"Dim"
	desc.text = ab.describe()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CardFit.drop_leading(desc)
	body.add_child(desc)
	return line


## "6s cooldown", "6s cooldown - 2.5s left" while it recharges; "Passive" for a passive.
static func cooldown_text(ability: Ability) -> String:
	var active := ability as ActiveAbility
	if active == null:
		return "Passive"
	var text := "%ss cooldown" % ItemCard.num(active.cooldown)
	if active.cooldown_left > 0.0:
		text += " - %ss left" % ItemCard.num(active.cooldown_left)
	return text


## One gear row: the slot, the item's name in its rarity colour and its lines under it.
func _gear_row(caption: String, item: ItemInstance) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", UiTheme.GAP)
	line.add_child(_caption(caption))
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", UiTheme.GAP_NONE)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(body)
	var name := Label.new()
	if item == null:
		name.theme_type_variation = &"Dim"
		name.text = EMPTY_TEXT
		body.add_child(name)
		return line
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", UiTheme.GAP)
	body.add_child(head)
	var badge := ShapeBadge.new()
	badge.shape = Accessibility.rarity_shape(item.rarity)
	badge.role = item.rarity_role()
	badge.surface = &"floor"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(badge)
	var pips := Accessibility.rarity_mark(item.rarity)
	name.text = item.display_name if pips.is_empty() else "%s %s" % [pips, item.display_name]
	name.add_theme_color_override(&"font_color", UiTheme.text_color(item.rarity_role()))
	head.add_child(name)
	var summary := Label.new()
	summary.theme_type_variation = &"Dim"
	summary.text = LoadoutModel.item_summary(item)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	CardFit.drop_leading(summary)
	body.add_child(summary)
	return line


## One sheet row: the caption, the value and the since-last-look delta on one line, and where
## the number comes from on a dim line under them. The sources used to be a fourth grid
## column, which on a 216 px sheet wrapped "Class 6, Rusty Sword +2" onto three lines and made
## every primary row three lines tall; a line of its own has the whole sheet's width.
func _stat_row(row: Dictionary) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override(&"separation", UiTheme.GAP_NONE)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", UiTheme.GAP_WIDE)
	block.add_child(line)
	var name := Label.new()
	name.text = str(row["label"])
	name.custom_minimum_size.x = CAPTION_WIDTH
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.theme_type_variation = &"" if bool(row["primary"]) else &"Dim"
	line.add_child(name)
	var value := Label.new()
	value.theme_type_variation = &"Bright"
	value.text = str(row["value"])
	value.custom_minimum_size.x = VALUE_WIDTH
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value)
	line.add_child(_delta_label(StringName(str(row["stat"])), bool(row["primary"])))
	var text := str(row["sources"])
	if not text.is_empty():
		var sources := Label.new()
		sources.name = "Sources"
		sources.theme_type_variation = &"Dim"
		sources.text = text
		sources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		CardFit.drop_leading(sources)
		block.add_child(sources)
	return block


## The signed change in a primary since the page was last closed, or a blank spacer.
func _delta_label(stat: StringName, primary: bool) -> Label:
	var label := Label.new()
	label.name = "Delta" + String(stat).capitalize()
	label.custom_minimum_size.x = DELTA_WIDTH
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var delta := 0
	var stats := LoadoutModel.stats_of(player)
	if primary and stats != null and _baseline.has(stat):
		delta = stats.primary(stat) - int(_baseline[stat])
	label.text = "" if delta == 0 else "%+d" % delta
	label.theme_type_variation = &"Heal" if delta > 0 else &"Danger"
	return label


## What the potion actually does. The HUD shows an icon, "x1" and the key, and nothing in the
## game ever said it heals 40% of max HP or that the run allows one at a time.
func _potion_row() -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", UiTheme.GAP)
	line.add_child(_caption(POTION_CAPTION))
	var label := Label.new()
	label.name = "PotionRow"
	label.theme_type_variation = &"Dim"
	label.text = LoadoutModel.potion_text(player)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CardFit.drop_leading(label)
	line.add_child(label)
	return line


func _caption(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"Dim"
	label.text = text
	label.custom_minimum_size.x = CAPTION_WIDTH
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return label


static func _spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = UiTheme.GAP
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## Rows are freed at once rather than queued: the page is rebuilt on every bind and open, and a
## queue of a few hundred labels waiting for the next frame is what gdUnit counts as orphans.
static func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()


## Every text on the page, for tests.
func texts() -> PackedStringArray:
	var out: PackedStringArray = []
	for node: Node in _panel.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return out
