## Pause menu with Build / Controls / Settings tabs, lyrics line, Save and Quit and Abandon
## Run (confirmed). Pauses the tree while open. Fully controller-driven: LB/RB (or PgUp/PgDn)
## change tab, the tab strip and the footer buttons are wired to each other with focus
## neighbours. The Build tab is the `LoadoutScreen` embedded, so the pause menu and the Tab
## key show the same page and can never disagree about what the player is carrying.
## `player` is duck-typed the way `LoadoutModel` reads it.
class_name PauseMenu
extends Control

signal save_quit_pressed
signal abandon_pressed
## Emitted when the player dismisses the menu themselves (Resume / cancel), not on
## Save and Quit or Abandon. `closed` fires on every close, whatever the reason.
signal resume_pressed
signal opened
signal closed

enum Tab { BUILD, CONTROLS, SETTINGS }

const TAB_NAMES: PackedStringArray = ["Build", "Controls", "Settings"]
const LOADOUT_SCENE := "res://src/ui/loadout_screen.tscn"
## The Controls page: what every button does, with live glyphs. Nothing in the game taught
## move, attack, secondary, dodge or interact - the only reference was the rebind list, seven
## rows down a scrolling Settings page.
const CONTROL_ROWS: Array[Dictionary] = [
	{"label": "Move", "actions": [&"move_up", &"move_left", &"move_down", &"move_right"]},
	{"label": "Attack", "actions": [&"attack"]},
	{"label": "Weapon skill", "actions": [&"secondary"]},
	{"label": "Dodge", "actions": [&"dodge"]},
	{"label": "Potion", "actions": [&"potion"]},
	{"label": "Ability 1", "actions": [&"active_1"]},
	{"label": "Ability 2", "actions": [&"active_2"]},
	{"label": "Interact", "actions": [&"interact"]},
	{"label": "Build", "actions": [&"map"]},
	{"label": "Pause", "actions": [&"pause"]},
]
## Rows per column on the Controls page.
const CONTROL_COLUMN_ROWS := 5
const LYRIC_POLL := 0.25

var player: Node
var current_tab: int = Tab.BUILD
## Optional `Callable() -> bool`: when set and it returns false, `pause` will not open
## the menu (the Game scene uses it to keep the chest picker exclusive).
var open_guard: Callable = Callable()

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _settings: SettingsPanel
var _loadout: LoadoutScreen
var _lyric_left: float = 0.0
var _is_open: bool = false

@onready var _panel: PanelContainer = %Panel
@onready var _tabs: HBoxContainer = %Tabs
@onready var _content: MarginContainer = %Content
@onready var _lyric: Label = %Lyric
@onready var _save_quit: Button = %SaveQuit
@onready var _abandon: Button = %Abandon
@onready var _resume: Button = %Resume
@onready var _confirm: PanelContainer = %Confirm
@onready var _confirm_yes: Button = %ConfirmYes
@onready var _confirm_no: Button = %ConfirmNo
@onready var _hint: UiPrompt = %Hint


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiTheme.apply(self)
	# Left stick -> menu navigation while the tree is paused (see UiStickNav).
	UiStickNav.serve(self)
	_build_tabs()
	_confirm.visible = false
	_resume.pressed.connect(_on_resume)
	_save_quit.pressed.connect(_on_save_quit)
	_abandon.pressed.connect(_ask_abandon)
	_confirm_yes.pressed.connect(_confirm_abandon)
	_confirm_no.pressed.connect(_hide_confirm)
	EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: _refresh_tab_styles())
	EventBus.input_device_changed.connect(
		func(_d: int) -> void:
			_refresh_title()
			_sync_control_glyphs()
	)
	_refresh_title()
	if not _is_open:
		visible = false


func _process(delta: float) -> void:
	if not _is_open:
		return
	_lyric_left -= delta
	if _lyric_left <= 0.0:
		_lyric_left = LYRIC_POLL
		_refresh_lyric()


func _input(event: InputEvent) -> void:
	InputGlyphs.observe(event)
	if event.is_action_pressed(&"pause"):
		# A rebind capture owns the input stream, and Start is a bindable pad button, so it
		# belongs to the capture while one is open. The capture can always be closed from the
		# device holding it (`SettingsPanel._try_capture`), so this withholds a button for a
		# moment - it cannot strand anyone the way it once could.
		if _settings != null and _settings.is_capturing():
			return
		if not _is_open and _blocked_by_modal():
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _is_open:
		return
	if _settings != null and _settings.is_capturing():
		return
	if event.is_action_pressed(&"ui_cancel"):
		if _confirm.visible:
			_hide_confirm()
		else:
			_on_resume()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var idx := (event as InputEventJoypadButton).button_index
		if idx == JOY_BUTTON_LEFT_SHOULDER:
			set_tab(current_tab - 1)
			get_viewport().set_input_as_handled()
		elif idx == JOY_BUTTON_RIGHT_SHOULDER:
			set_tab(current_tab + 1)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_page_up"):
		set_tab(current_tab - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_page_down"):
		set_tab(current_tab + 1)
		get_viewport().set_input_as_handled()


## Safety net: a menu freed or reparented while open must not leave the tree paused
## (the next scene's Buttons are PAUSABLE and would never see input) or the music ducked.
func _exit_tree() -> void:
	if not _is_open:
		return
	_is_open = false
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	EventBus.music_duck.emit(0.4, false)


## True while a sibling overlay (the chest picker) owns the screen, so `pause` does not
## stack the pause menu on top of a modal the game deliberately guards against.
func _blocked_by_modal() -> bool:
	if open_guard.is_valid():
		return not bool(open_guard.call())
	var parent := get_parent()
	if parent == null:
		return false
	for sibling: Node in parent.get_children():
		if sibling != self and sibling is ChestUi and (sibling as ChestUi).is_open():
			return true
	return false


func bind(new_player: Node) -> void:
	player = new_player
	if _is_open:
		_refresh_pages()
	elif _loadout != null:
		_loadout.bind(player)


func is_open() -> bool:
	return _is_open


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	get_tree().paused = true
	_refresh_pages()
	set_tab(current_tab)
	_panel.pivot_offset = _panel.size * 0.5
	if not Accessibility.animates():
		_panel.scale = Vector2.ONE
		modulate.a = 1.0
		EventBus.music_duck.emit(0.4, true)
		_refresh_lyric()
		opened.emit()
		return
	_panel.scale = Vector2(0.96, 0.96)
	modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	EventBus.music_duck.emit(0.4, true)
	_refresh_lyric()
	opened.emit()


## Hands focus back to nobody. On a pad, A is `ui_accept` *and* `dodge` (Space is the same
## pair on the keyboard), which is only safe while a dismissed menu holds no focus: the panel
## fades for a tenth of a second after `close()`, and a Resume button still holding focus
## through that fade eats the dodge that was meant to get the player out of trouble.
func release_menu_focus() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var owner := viewport.gui_get_focus_owner()
	if owner != null and (owner == self or is_ancestor_of(owner)):
		owner.release_focus()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	if _loadout != null:
		_loadout.mark_seen()
	_hide_confirm()
	release_menu_focus()
	get_tree().paused = false
	EventBus.music_duck.emit(0.4, false)
	if not Accessibility.animates():
		modulate.a = 0.0
		visible = false
		closed.emit()
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, 0.1)
	tween.tween_callback(func() -> void: visible = _is_open)
	closed.emit()


func set_tab(index: int) -> void:
	current_tab = wrapi(index, 0, Tab.size())
	for i in _pages.size():
		_pages[i].visible = i == current_tab
	_refresh_tab_styles()
	_sync_settings_ring()
	if current_tab == Tab.SETTINGS and _settings != null:
		_settings.focus_first()
	else:
		_tab_buttons[current_tab].grab_focus()


## Joins the Settings list into the menu's own focus ring while its tab is up, and takes it
## back out again afterwards.
##
## Without this the bottom of the settings list dropped into whatever Godot's geometric guess
## found under it - which was Abandon, the destructive button, with no way further down. The
## list now ends on Resume and Resume climbs back into the list, so the ring closes.
func _sync_settings_ring() -> void:
	if _settings == null:
		return
	var on_settings := current_tab == Tab.SETTINGS
	if on_settings:
		_settings.wire_exits(_tab_buttons[Tab.SETTINGS], _resume)
	else:
		_resume.focus_neighbor_top = _tab_buttons[0].get_path()
		_tab_buttons[Tab.SETTINGS].focus_neighbor_bottom = _resume.get_path()


func settings_panel() -> SettingsPanel:
	return _settings


func _build_tabs() -> void:
	for i in TAB_NAMES.size():
		var button := Button.new()
		button.text = TAB_NAMES[i]
		button.theme_type_variation = &"TabButton"
		button.pressed.connect(set_tab.bind(i))
		_tabs.add_child(button)
		_tab_buttons.append(button)
		var page := VBoxContainer.new()
		page.name = TAB_NAMES[i]
		page.add_theme_constant_override("separation", UiTheme.GAP_TIGHT)
		page.visible = false
		_content.add_child(page)
		_pages.append(page)
	for i in _tab_buttons.size():
		var b := _tab_buttons[i]
		b.focus_neighbor_left = _tab_buttons[wrapi(i - 1, 0, _tab_buttons.size())].get_path()
		b.focus_neighbor_right = _tab_buttons[wrapi(i + 1, 0, _tab_buttons.size())].get_path()
	_wire_footer_focus()
	_settings = (
		(load("res://src/ui/settings_panel.tscn") as PackedScene).instantiate() as SettingsPanel
	)
	_settings.standalone = false
	_settings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages[Tab.SETTINGS].add_child(_settings)
	_loadout = (load(LOADOUT_SCENE) as PackedScene).instantiate() as LoadoutScreen
	_loadout.standalone = false
	_loadout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages[Tab.BUILD].add_child(_loadout)


## Explicit focus ring for the controller: the tab strip drops into the footer and the footer
## climbs back into it. The Build and Controls pages are pure Labels, so without this
## the only thing between the tabs and the footer is Godot's geometric guess.
func _wire_footer_focus() -> void:
	var footer: Array[Button] = [_resume, _save_quit, _abandon]
	for i in footer.size():
		var b := footer[i]
		b.focus_neighbor_left = footer[wrapi(i - 1, 0, footer.size())].get_path()
		b.focus_neighbor_right = footer[wrapi(i + 1, 0, footer.size())].get_path()
		b.focus_neighbor_top = _tab_buttons[mini(i, _tab_buttons.size() - 1)].get_path()
	for i in _tab_buttons.size():
		_tab_buttons[i].focus_neighbor_bottom = footer[mini(i, footer.size() - 1)].get_path()
	_confirm_no.focus_neighbor_right = _confirm_yes.get_path()
	_confirm_yes.focus_neighbor_left = _confirm_no.get_path()


## Every control a controller can land on while the menu is open, in tab order. Tests walk
## this to prove nothing on the screen needs a mouse.
func focusable_controls() -> Array[Control]:
	var out: Array[Control] = []
	_collect_focusable(self, out)
	return out


static func _collect_focusable(node: Node, out: Array[Control]) -> void:
	for child: Node in node.get_children():
		var control := child as Control
		if control != null and not control.visible:
			continue
		if control != null and control.focus_mode == Control.FOCUS_ALL:
			out.append(control)
		_collect_focusable(child, out)


func _refresh_tab_styles() -> void:
	for i in _tab_buttons.size():
		var b := _tab_buttons[i]
		if i == current_tab:
			b.add_theme_stylebox_override(
				"normal", UiTheme.theme().get_stylebox(&"pressed", &"TabButton")
			)
			b.add_theme_color_override("font_color", UiTheme.color(&"text_bright"))
		else:
			b.remove_theme_stylebox_override("normal")
			b.remove_theme_color_override("font_color")


func _refresh_title() -> void:
	_hint.text = "{ui_page_up}{ui_page_down} tabs   {ui_cancel} resume"


func _refresh_pages() -> void:
	if _loadout != null:
		_loadout.bind(player)
	_fill_controls(_pages[Tab.CONTROLS])


## The embedded build page.
func loadout_screen() -> LoadoutScreen:
	return _loadout


## Two columns of "what this button does", built from the live InputMap so a rebind (or a
## gamepad being picked up) is reflected without any bookkeeping here.
func _fill_controls(page: Control) -> void:
	_clear(page)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", UiTheme.GAP_COLUMN)
	page.add_child(columns)
	var grid: GridContainer = null
	for i in CONTROL_ROWS.size():
		if i % CONTROL_COLUMN_ROWS == 0:
			grid = GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", UiTheme.GAP_WIDE)
			grid.add_theme_constant_override("v_separation", UiTheme.GAP_TIGHT)
			columns.add_child(grid)
		var entry := CONTROL_ROWS[i]
		var name := Label.new()
		name.text = str(entry["label"])
		name.custom_minimum_size = Vector2(62, 0)
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(name)
		var glyphs := HBoxContainer.new()
		glyphs.add_theme_constant_override("separation", UiTheme.GAP_TIGHT)
		for action: StringName in entry["actions"] as Array:
			var glyph := GlyphIcon.new()
			glyph.action = action
			glyphs.add_child(glyph)
		grid.add_child(glyphs)
	var hint := Label.new()
	hint.theme_type_variation = &"Dim"
	hint.text = "Rebind anything on the Settings page."
	page.add_child(hint)
	_sync_control_glyphs()


## Hides the glyphs in a Controls row that draw the same thing as one already in it.
##
## A four-direction row is one control, not four: on a pad all four Move bindings resolve to
## the same left-stick disc, so the row drew four identical grey circles and taught nothing. A
## rebind that pulls the directions onto different buttons brings the separate glyphs straight
## back, because which glyphs are duplicates is asked again every time the device changes.
##
## Hidden rather than rebuilt on purpose. The device can change in the middle of an input
## event, and tearing thirty nodes down and building thirty more from inside a signal handler
## is how a page ends up half-built - and how a closing menu leaves them orphaned.
func _sync_control_glyphs() -> void:
	if _pages.size() <= Tab.CONTROLS or _pages[Tab.CONTROLS] == null:
		return
	for node: Node in _pages[Tab.CONTROLS].find_children("*", "HBoxContainer", true, false):
		var actions: Array[StringName] = []
		for child: Node in node.get_children():
			var glyph := child as GlyphIcon
			if glyph != null:
				actions.append(glyph.action)
		if actions.size() < 2:
			continue
		var keep := InputGlyphs.collapse_actions(actions)
		for child: Node in node.get_children():
			var glyph := child as GlyphIcon
			if glyph != null:
				glyph.visible = keep.has(glyph.action)


static func _clear(page: Control) -> void:
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()


func _refresh_lyric() -> void:
	var music := get_node_or_null("/root/Music")
	var text := ""
	if music != null and bool(GameState.settings.get("lyrics", true)):
		text = _music_text(music, &"current_lyric")
		if text.is_empty():
			text = _music_text(music, &"current_title")
	_lyric.text = text
	_lyric.visible = not text.is_empty()


## Reads `name` off the Music autoload whether it is a method or a plain property.
## `Object.get()` hands back a Callable for methods, whose str() is a debug string.
static func _music_text(music: Node, name: StringName) -> String:
	if music.has_method(name):
		var called: Variant = music.call(name)
		return str(called) if called is String or called is StringName else ""
	var value: Variant = music.get(name)
	return str(value) if value is String or value is StringName else ""


func _on_resume() -> void:
	close()
	resume_pressed.emit()


func _on_save_quit() -> void:
	close()
	save_quit_pressed.emit()


func _ask_abandon() -> void:
	_confirm.visible = true
	_confirm_no.grab_focus()


func _hide_confirm() -> void:
	if not _confirm.visible:
		return
	_confirm.visible = false
	if _is_open:
		_abandon.grab_focus()


func _confirm_abandon() -> void:
	_confirm.visible = false
	abandon_pressed.emit()
	close()


func confirm_visible() -> bool:
	return _confirm.visible
