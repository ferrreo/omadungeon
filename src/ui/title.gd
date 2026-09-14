## Title screen: logo, "Dungeon of <theme>" and the main menu.
## Emits intent signals; RunManager decides what happens next.
##
## The seed is **not** on this screen. It is a power-user handle - most players never want one
## and the field sat in the middle of the menu, above Stats and Settings, with a three-line
## caption under it explaining what a seed is. It lives in Settings -> Advanced now
## (`SettingsPanel`), where somebody looking for it will find it and nobody else has to read
## about it, and this screen just spends whatever is waiting there on the next run.
##
## "New Run" is a destructive action whenever a saved run exists - `RunManager.new_run()`
## deletes `run.json` before it builds the first floor - so it asks first, with the same shape
## as the pause menu's Abandon confirm (danger-styled Yes, "keep it" focused by default). The
## seed field's Enter goes through the same gate; it used to destroy a 30-minute run in one
## keystroke with no button press at all.
class_name Title
extends Control

signal new_run_pressed(run_seed: int)
signal continue_pressed
signal stats_pressed
signal settings_pressed
signal credits_pressed
signal quit_pressed

const LOGO_PATH := "res://assets/sprites/logo.png"
const RUN_SAVE_PATH := "user://run.json"
## What a seed actually pins down. Generation folds the desktop theme, the wallpaper and the
## track playing when a floor is built into its inputs (GAME_DESIGN §3.3, §3.4, §10.2), so a
## seed on its own does not name a dungeon. Shown as the seed field's tooltip.
const SEED_TOOLTIP := """A seed fixes the random rolls: room layout, loot, chest offers.
It does not fix the whole run. Floors are also shaped by the desktop theme, the wallpaper and
the music: the energy and tempo of the track are read at the moment each floor is built, so
even the same seed on the same desktop lays its rooms out differently from run to run.
Leave it blank for a random seed."""
## Settings key a deliberately chosen seed is parked in. Spent by the next run and cleared, so
## one curious run does not silently pin every run after it to the same rolls.
const SEED_SETTING := "custom_seed"
## Size of the "this deletes your saved run" panel, in the 480x270 internal resolution.
const CONFIRM_SIZE := Vector2(244.0, 78.0)
## How much of the theme's own background colour the confirm lays over the menu behind it.
const SCRIM_ALPHA := 0.78
## Suffix SaveManager gives a half-written run file. A run that only exists as a `.tmp` is
## still a run the player can resume, so it still has to be confirmed away.
const RUN_TMP_SUFFIX := ".tmp"
## Node name of the code-built confirm panel, so `focus_ring()` can leave it out.
const CONFIRM_NAME := &"NewRunConfirm"

var _rng := RandomNumberGenerator.new()
var _confirm: Control
var _confirm_scrim: ColorRect
var _confirm_text: Label
var _confirm_yes: Button
var _confirm_no: Button

@onready var _logo_texture: TextureRect = %LogoTexture
@onready var _logo_text: Label = %LogoText
@onready var _subtitle: Label = %Subtitle
@onready var _continue: Button = %Continue
@onready var _new_run: Button = %NewRun
@onready var _stats: Button = %Stats
@onready var _settings: Button = %Settings
@onready var _credits: Button = %Credits
@onready var _quit: Button = %Quit
@onready var _footer: Label = %Footer
@onready var _logo_box: Control = %LogoBox


func _ready() -> void:
	UiTheme.apply(self)
	# Left stick -> menu navigation (see UiStickNav: the raw stick is not bound to ui_*).
	UiStickNav.serve(self)
	_rng.randomize()
	var logo := UiTheme.load_texture(LOGO_PATH)
	if logo != null:
		_logo_texture.texture = logo
		_logo_text.visible = false
	else:
		_logo_texture.visible = false
	_continue.visible = has_saved_run()
	_continue.pressed.connect(func() -> void: continue_pressed.emit())
	_new_run.pressed.connect(_on_new_run)
	_stats.pressed.connect(func() -> void: stats_pressed.emit())
	_settings.pressed.connect(func() -> void: settings_pressed.emit())
	_credits.pressed.connect(func() -> void: credits_pressed.emit())
	_quit.pressed.connect(func() -> void: quit_pressed.emit())
	_build_confirm()
	EventBus.palette_changed.connect(_on_palette_changed)
	EventBus.input_device_changed.connect(func(_d: int) -> void: refresh_focus_ring())
	refresh_focus_ring()
	_refresh_theme_text()
	_footer.text = "v%s" % str(ProjectSettings.get_setting("application/config/version", "0.1"))
	_animate_logo()
	focus_default()


func _input(event: InputEvent) -> void:
	InputGlyphs.observe(event)
	if confirm_visible() and event.is_action_pressed(&"ui_cancel"):
		cancel_new_run()
		get_viewport().set_input_as_handled()


## Focuses the first sensible button (Continue if a save exists).
func focus_default() -> void:
	refresh_focus_ring()
	if _continue.visible:
		_continue.grab_focus()
	else:
		_new_run.grab_focus()


## Every control the menu can land focus on right now, in tab order.
##
## Walked from the tree rather than from a fixed list of buttons: the title menu is edited
## often, and a ring wired from a stale list silently loses whatever row was added last.
func focus_ring() -> Array[Control]:
	var out: Array[Control] = []
	_collect_ring(self, out)
	return out


static func _collect_ring(node: Node, out: Array[Control]) -> void:
	for child: Node in node.get_children():
		var control := child as Control
		if control != null and (not control.visible or control.name == CONFIRM_NAME):
			continue
		if control != null and control.focus_mode == Control.FOCUS_ALL:
			out.append(control)
		_collect_ring(child, out)


## Wires the menu into a ring a controller can go round: down off the last row lands on the
## first, up off the first lands on the last. Godot's geometric guess stops dead at both ends,
## so on a pad the bottom of the menu was a cul-de-sac.
##
## Any `LineEdit` in the menu also drops out of the ring while a gamepad is the active device.
## A text field is a dead end on a controller - there is nothing to type with, and `ui_accept`
## on it does nothing at all, which is the "pressing A does nothing" the owner hit. It stays
## focusable for the keyboard, which is the only device that can use it.
func refresh_focus_ring() -> void:
	var pad := InputGlyphs.current_device() == InputGlyphs.Device.GAMEPAD
	for field: Node in find_children("*", "LineEdit", true, false):
		var edit := field as LineEdit
		if pad and edit.has_focus():
			edit.release_focus()
		edit.focus_mode = Control.FOCUS_NONE if pad else Control.FOCUS_ALL
	var ring := focus_ring()
	if ring.is_empty():
		return
	var viewport := get_viewport()
	if is_visible_in_tree() and viewport != null and viewport.gui_get_focus_owner() == null:
		ring[0].grab_focus()
	for i in ring.size():
		ring[i].focus_neighbor_top = ring[wrapi(i - 1, 0, ring.size())].get_path()
		ring[i].focus_neighbor_bottom = ring[wrapi(i + 1, 0, ring.size())].get_path()


## True when a run can be resumed. Prefers SaveManager (it also parses/migrates the file)
## and falls back to a plain existence check when the autoload is not present (tests).
static func has_saved_run() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var save_manager := tree.root.get_node_or_null(^"/root/SaveManager")
		if save_manager != null and save_manager.has_method(&"has_run"):
			return bool(save_manager.call(&"has_run"))
	return FileAccess.file_exists(RUN_SAVE_PATH)


## Floor number (1-based) of the saved run a fresh run would delete, or 0 when there is none
## or the file cannot be read. Deliberately read-only: `SaveManager.load_run()` would do the
## same parse but also primes the resume counters, which would make the *next* run mis-count
## its floors. Used for the warning text only - whether to warn at all is `has_saved_run()`,
## which stays authoritative even when the floor cannot be worked out.
static func saved_run_floor() -> int:
	for path: String in _run_file_candidates():
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(text)
		if not (parsed is Dictionary):
			continue
		var state := RunState.from_dict(parsed as Dictionary)
		if state != null:
			return state.floor_index + 1
	return 0


## The run file and its half-written sibling, absolute when SaveManager is up (it redirects
## into a per-process sandbox during tests).
static func _run_file_candidates() -> PackedStringArray:
	var path := RUN_SAVE_PATH
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var save_manager := tree.root.get_node_or_null(^"/root/SaveManager")
		if save_manager != null and save_manager.has_method(&"run_file_path"):
			path = str(save_manager.call(&"run_file_path"))
	return PackedStringArray([path, path + RUN_TMP_SUFFIX])


## What the confirm panel says. Names the floor when it could be read, because "floor 7" is
## what tells the player how much of their evening is at stake.
static func overwrite_warning(floor_number: int) -> String:
	if floor_number > 0:
		return "This deletes your saved run on floor %d." % floor_number
	return "This deletes your saved run."


## Seed the next run will use: whatever the player parked in Settings -> Advanced, or a fresh
## random one. Never shown on this screen; a run with no chosen seed is the normal case.
func current_seed() -> int:
	var text := str(GameState.settings.get(SEED_SETTING, "")).strip_edges()
	if text.is_empty():
		return _rng.randi() & 0x7FFFFFFF
	return RunRng.seed_from_string(text)


## The seed for a run that is starting *now*, which also spends it: a chosen seed is a
## one-run instruction, not a setting that quietly pins every run after it.
func _take_seed() -> int:
	var value := current_seed()
	if not str(GameState.settings.get(SEED_SETTING, "")).is_empty():
		GameState.settings[SEED_SETTING] = ""
		GameState.save_settings()
	return value


func subtitle_text() -> String:
	return _subtitle.text


## New Run. Emits straight away when there is nothing to lose; otherwise asks first and emits
## from `confirm_new_run()`.
func _on_new_run() -> void:
	if confirm_visible():
		return
	if not has_saved_run():
		new_run_pressed.emit(_take_seed())
		return
	_confirm_text.text = overwrite_warning(saved_run_floor())
	_confirm.visible = true
	_confirm_no.grab_focus()


## The scrim that dims the menu behind the panel. Theme-coloured rather than plain black, so a
## light desktop dims to its own background instead of to somebody else's.
func _scrim_color() -> Color:
	var base := Desktop.palette.get_color(&"void") if Desktop.palette != null else Color.BLACK
	return Color(base.r, base.g, base.b, SCRIM_ALPHA)


## True while the "this deletes your saved run" panel is up.
func confirm_visible() -> bool:
	return _confirm != null and _confirm.visible


## The panel's two answers, "keep it" first: tests and the rendered-check driver press the
## real buttons rather than trusting that they are wired to the right thing.
func confirm_buttons() -> Array[Button]:
	return [_confirm_no, _confirm_yes]


## Answers the panel with "delete it": the run starts and the save goes with it.
func confirm_new_run() -> void:
	if not confirm_visible():
		return
	_confirm.visible = false
	new_run_pressed.emit(_take_seed())


## Answers the panel with "keep it": nothing is emitted, so nothing is deleted.
func cancel_new_run() -> void:
	if not confirm_visible():
		return
	_confirm.visible = false
	_new_run.grab_focus()


## Builds the confirm panel in code so the title scene stays the plain menu it is. Same shape
## as `pause_menu.tscn`'s Abandon confirm: a Card panel, danger-coloured text, the destructive
## button danger-styled, and the harmless answer holding focus. The scrim behind it is the one
## addition - the panel sits exactly where the menu is, and without it the half-covered buttons
## underneath read as a rendering bug rather than as a question waiting for an answer.
func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.name = CONFIRM_NAME
	_confirm.visible = false
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_scrim = ColorRect.new()
	_confirm_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_scrim.color = _scrim_color()
	_confirm.add_child(_confirm_scrim)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = &"Card"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -CONFIRM_SIZE.x * 0.5
	panel.offset_right = CONFIRM_SIZE.x * 0.5
	panel.offset_top = -CONFIRM_SIZE.y * 0.5
	panel.offset_bottom = CONFIRM_SIZE.y * 0.5
	_confirm.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", UiTheme.GAP_WIDE)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	_confirm_text = Label.new()
	_confirm_text.theme_type_variation = &"Danger"
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.text = overwrite_warning(0)
	box.add_child(_confirm_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", UiTheme.GAP_WIDE)
	box.add_child(row)
	_confirm_no = Button.new()
	_confirm_no.name = "ConfirmNo"
	_confirm_no.text = "Keep saved run"
	_confirm_no.pressed.connect(cancel_new_run)
	row.add_child(_confirm_no)
	_confirm_yes = Button.new()
	_confirm_yes.name = "ConfirmYes"
	_confirm_yes.text = "Delete it"
	_confirm_yes.theme_type_variation = &"DangerButton"
	_confirm_yes.pressed.connect(confirm_new_run)
	row.add_child(_confirm_yes)
	add_child(_confirm)


func _on_palette_changed(_palette: ThemePalette) -> void:
	_refresh_theme_text()
	if _confirm_scrim != null:
		_confirm_scrim.color = _scrim_color()
	_continue.visible = has_saved_run()


func _refresh_theme_text() -> void:
	var name := Desktop.palette.name if Desktop.palette != null else "Nowhere"
	_subtitle.text = "Dungeon of %s" % name


## One line under the Settings seed field naming the other half of a run's identity. The seed fixes
## every random roll, but not the inputs those rolls are made against: the live theme, the
## wallpaper and the track playing when each floor is built all move the floor plan
## (GAME_DESIGN §5.1), and the music levers are sampled live, so the caption promises a
## reproducible *seed*, never a reproducible dungeon.
static func seed_hint_text(theme_name: String) -> String:
	return (
		"A seed fixes the rolls. %s, the wallpaper and the music shape each floor too." % theme_name
	)


func _animate_logo() -> void:
	if not Accessibility.animates():
		return
	var tween := create_tween().set_loops()
	(
		tween
		. tween_property(_logo_box, "position:y", _logo_box.position.y - 2.0, 1.4)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		tween
		. tween_property(_logo_box, "position:y", _logo_box.position.y, 1.4)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
