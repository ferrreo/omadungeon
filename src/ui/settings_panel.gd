## Settings panel: every GameState.settings key with live apply and persistence.
## Embed it (pause menu) or show it standalone from the title screen.
## `SettingsPanel.apply_all(GameState.settings)` should run once at boot.
##
## Input section: every player action can be rebound separately for keyboard/mouse and for
## the gamepad, conflicts are detected and the losing action is unbound rather than silently
## double-bound, and "Reset bindings" restores the project defaults from `project.godot`.
## Held actions (attack, secondary, map) each choose between hold and toggle.
##
## Advanced section: the run seed, and nothing else. It is last on the page because it is the
## one control here that is not a preference - it is a power-user handle that used to sit in
## the middle of the title menu with a three-line explanation under it, which is a lot of
## screen for a feature most players never want. Down here a curious player finds it and
## everyone else scrolls past it; the field is spent by the next run and cleared, so one
## curious run cannot silently pin every run after it.
##
## Video section: the window is the source of truth, not the stored dictionary. The stored
## value is the preference the next launch starts from; `sync_from_window()` reads the live
## window back every frame and writes what it sees into the settings, so a compositor keybind
## that fullscreens the window cannot leave the checkbox claiming the opposite. On Wayland the
## engine cannot see that keybind at all, so the truth comes from `CompositorWindow` - the
## compositor itself, asked about this process's window off the main thread. Both of Godot's
## fullscreen modes count; a maximised window is not one of them and is left maximised.
##
## Accessibility section: colour-blind glyphs, reduced flashing and reduce motion. Reduce
## motion overrides screen shake without overwriting it — `screen_shake_active()` is the
## effective value (which is what `GameFeel` gates shake on), the stored preference is left
## alone, and the Screen shake checkbox shows Off and greys out while the override holds, so
## the panel never claims a choice the player no longer has.
class_name SettingsPanel
extends Control

signal changed(key: String, value: Variant)
signal back_pressed

## The rows this page draws - every settings key, its default, its section and its kind - live
## in `SettingsRows`, so a module that needs a row (the lighting quality, the music light
## amount) adds it there without growing this file. These aliases keep the old names.
const ACTION_LABELS: Dictionary = SettingsRows.ACTION_LABELS
## The rebindable actions, in page order. The list and every rule about what a binding *is*
## live in `InputBindings`; this page draws rows for them.
const REBIND_ACTIONS: Array[StringName] = InputBindings.ACTIONS
const HOLD_ROWS: Array[Dictionary] = SettingsRows.HOLD_ROWS
const HOLD_CHOICES: Array[Dictionary] = SettingsRows.HOLD_CHOICES
## Settings key reduce-motion overrides (without overwriting it); see `screen_shake_active`.
const MOTION_OWNED := "screen_shake"
## Pad button that backs out of an in-progress rebind capture without binding anything. It is
## `ui_cancel`'s gamepad event in `project.godot`, so it is the button that leaves every other
## screen: a capture only a keyboard can end is a lock-up, and the build the owner played
## shipped one. A *held* B binds B instead (see `UiNavProfile.capture_hold_seconds`), so
## reserving the cancel button does not cost the player the button itself.
const CAPTURE_CANCEL_BUTTON := JOY_BUTTON_B
## Deflection a stick has to reach before a capture treats it as a deliberate binding.
const CAPTURE_AXIS_THRESHOLD := 0.7
## Actions whose gamepad binding may not be taken away by rebinding something else onto it.
##
## `pause` is the only way a pad reaches this page, the Controls page and Save and Quit; the
## keyboard's Escape is not a way back for somebody holding a controller. A mis-pressed Start
## during a gamepad capture used to bind Start to whatever was being captured and silently
## unbind it from `pause`, ending the run's access to the menu with one wrong button. The press
## is refused by name instead. Rebinding `pause` itself is still allowed - that is the row that
## exists to move it.
const PROTECTED_PAD_ACTIONS: Array[StringName] = [&"pause"]
## Window modes a player would call fullscreen: the borderless `MODE_FULLSCREEN` this panel
## asks for and the `MODE_EXCLUSIVE_FULLSCREEN` a compositor can leave the window in. Comparing
## against one of them is half of why the checkbox could say "off" over a full screen.
const FULLSCREEN_MODES: Array[int] = [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
## Width of one rebind button (two per row: keyboard, then gamepad).
const BIND_BUTTON_WIDTH := 62
## Metadata a rebind button carries so focus and the capture can name the row it belongs to.
const BIND_ACTION_META := &"bind_action"
const BIND_PAD_META := &"bind_pad"
## How far the Keyboard column is dimmed while a gamepad is the live device: it is a column
## that device cannot fill in, and a column that looks exactly like the one next to it is a
## column a player will keep pressing.
const INERT_COLUMN_ALPHA := 0.45
## What the hint line says when nothing more specific is happening.
const HINT_DEFAULT := "Changes apply and save immediately"
## Lines the hint is given room for, whatever it is saying at the time. The page is embedded in
## the pause menu as well as shown standalone, and the pause panel is 96 px narrower: the
## Keyboard column's notice needs 447 px against the 420 px the pause hint line has, so the one
## screen where that explanation is needed is the one screen it ran off both ends of. The line
## wraps (`autowrap_mode`, in the scene) rather than being shortened - it has to name a device,
## a way in and where the other column is - and it is given the second line up front rather than
## growing into it, because it sits under a list a controller is walking and a hint that changed
## height when focus stepped onto a rebind row moved every row under the player's thumb.
const HINT_LINES := 2
## The Advanced section and its one row.
const ADVANCED_TITLE := "Advanced"
const SEED_ROW_LABEL := "Seed"
## What the empty field means. A blank seed is the normal case, not a missing value - and the
## placeholder may not be the word on the button beside it, which is how "Seed [random]
## [Random]" ended up reading as the same control twice.
const SEED_PLACEHOLDER := "blank = random"
## The seed field is wider than a rebind button: its placeholder is a sentence.
const SEED_FIELD_WIDTH := BIND_BUTTON_WIDTH * 2
const DEADZONE_ACTIONS: Array[StringName] = SettingsRows.DEADZONE_ACTIONS
## Defaults for keys GameState does not seed itself (`SettingsRows.DEFAULTS`).
const DEFAULTS: Dictionary = SettingsRows.DEFAULTS
const SECTIONS: Array[Dictionary] = SettingsRows.SECTIONS

## Seconds a change waits before it is written to disk (sliders fire per step).
const SAVE_DEBOUNCE := 0.5

## Whether to draw a Back button (standalone screen) or not (embedded in pause menu).
@export var standalone: bool = true

var _controls: Dictionary = {}
## action -> Button (keyboard/mouse column); the legacy single-column accessor.
var _rebind_buttons: Dictionary = {}
## action -> Button (gamepad column).
var _pad_buttons: Dictionary = {}
var _capturing: StringName = &""
## Which column the in-progress capture writes to: false = keyboard/mouse, true = gamepad.
var _capturing_pad: bool = false
var _seed_edit: LineEdit
var _save_pending: bool = false
var _save_scheduled: bool = false
## Explicit row-to-row focus wiring for the list (see `UiFocusChain`).
var _chain := UiFocusChain.new()
## Where the top and bottom of the list hand focus on: the Back button when this page is
## standalone, the pause menu's tab strip and footer when it is embedded.
var _exit_above: Control
var _exit_below: Control
## Tunables for the held-B-binds-B window.
var _nav_profile: UiNavProfile = UiNavProfile.load_default()
## Seconds the cancel button has been held while a gamepad capture is open; -1 when it is not.
var _cancel_held: float = -1.0
## True while the hint line is holding the Keyboard column's notice, so leaving the column can
## put the line back without having to guess what it used to say.
var _column_notice: bool = false
## The window manager, asked about this game's own window. It lives here rather than in an
## autoload because this is the only page that needs it, so nothing spawns `hyprctl` mid-fight.
var _compositor := CompositorWindow.new()

@onready var _scroll: ScrollContainer = %Scroll
@onready var _list: VBoxContainer = %List
@onready var _back: Button = %Back
@onready var _hint: UiPrompt = %Hint
@onready var _header: HBoxContainer = %Header
@onready var _panel: PanelContainer = %Panel


func _ready() -> void:
	UiTheme.apply(self)
	# Left stick -> row navigation (see UiStickNav).
	UiStickNav.serve(self)
	# Not `follow_focus`: it scrolls the focused row flush to the edge of the viewport and
	# leaves the section heading above it sliced in half under the page header, which is what
	# a verifier saw. `reveal` brings the heading along, or hides it whole. What makes the rows
	# below the fold reachable at all is the explicit focus chain (`UiFocusChain`), not the
	# flag: a clipped row is refused by Godot's *geometric* neighbour search whatever the
	# container does about scrolling.
	_scroll.follow_focus = false
	_hint.custom_minimum_size.y = hint_height(_hint)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_back.visible = standalone
	_header.visible = standalone
	if not standalone:
		var flat := StyleBoxEmpty.new()
		_panel.add_theme_stylebox_override("panel", flat)
		_panel.offset_left = 0
		_panel.offset_top = 0
		_panel.offset_right = 0
		_panel.offset_bottom = 0
	_back.pressed.connect(func() -> void: back_pressed.emit())
	if standalone:
		_exit_above = _back
		_exit_below = _back
	_build()
	# Reality first, then the preference: if the window is already fullscreen when the page opens
	# - the compositor put it there, or the boot-time `apply_all` landed before the window
	# settled - the row shows that rather than overwriting it. The compositor's answer takes a
	# query, started here; until it lands the row shows the engine's own reading.
	_compositor.poll(0.0)
	sync_from_window()
	EventBus.input_device_changed.connect(func(_d: int) -> void: _refresh_rebind_labels())
	# As a standalone screen nothing else focuses a row for us (`Main.show_screen` just adds the
	# scene), so the page opened with no focus at all and the first A press on a controller did
	# nothing. Embedded in the pause menu, `PauseMenu.set_tab` owns the focus instead.
	if standalone:
		focus_first.call_deferred()


func _input(event: InputEvent) -> void:
	# This page is reachable as a standalone screen with nothing else watching the stream, and
	# which device is live decides whether the Keyboard column may open a capture at all, so it
	# reads the device here rather than inheriting whatever the last screen happened to see.
	InputGlyphs.observe(event)
	if _capturing == &"":
		return
	if _try_capture(event):
		get_viewport().set_input_as_handled()


## Focuses the first control (for gamepad users).
func focus_first() -> void:
	var first := _chain.first()
	if first != null:
		first.grab_focus()


## The last row of the list: where a walk down it ends. Null before the page is built.
func focus_last() -> Control:
	return _chain.last()


## Height `HINT_LINES` of `hint` occupy, spacing between them included. Reserved up front so
## the line never changes the height of the list above it (see `HINT_LINES`).
static func hint_height(hint: UiPrompt) -> float:
	return hint.line_height() * HINT_LINES + UiPrompt.LINE_GAP * (HINT_LINES - 1)


## Points the two ends of the list at the controls that surround it. The standalone page wires
## its own Back button; the pause menu hands in its tab strip and its footer, so the bottom of
## the list steps onto Resume instead of stranding focus on Abandon.
func wire_exits(above: Control, below: Control) -> void:
	_exit_above = above
	_exit_below = below
	_chain.wire(_exit_above, _exit_below)


func _unhandled_input(event: InputEvent) -> void:
	if standalone and visible and event.is_action_pressed(&"ui_cancel") and _capturing == &"":
		back_pressed.emit()
		get_viewport().set_input_as_handled()


func _on_focus_changed(control: Control) -> void:
	if control != null and _list != null and _list.is_ancestor_of(control):
		reveal(control)
	_announce_column(control)


## Puts the Keyboard column's notice on the hint line as soon as focus lands there on a pad,
## so the player reads why before pressing anything, and takes it down again on the way out.
func _announce_column(control: Control) -> void:
	if _capturing != &"":
		return
	var action := _inert_keyboard_action(control)
	if action != &"":
		_column_notice = true
		_hint.text = keyboard_column_notice(action)
	elif _column_notice:
		_column_notice = false
		_hint.text = HINT_DEFAULT


## The rebind action `control` sets in the Keyboard column while that column is inert, or
## `&""` for anything else.
func _inert_keyboard_action(control: Control) -> StringName:
	if control == null or keyboard_column_live():
		return &""
	if not control.has_meta(BIND_ACTION_META) or bool(control.get_meta(BIND_PAD_META, true)):
		return &""
	return StringName(control.get_meta(BIND_ACTION_META))


## Scrolls `control` into view, with its section heading (see `UiListReveal`). Returns the
## resulting scroll offset.
func reveal(control: Control) -> int:
	return UiListReveal.reveal(_scroll, _list, control)


func is_capturing() -> bool:
	return _capturing != &""


static func setting(key: String) -> Variant:
	return GameState.settings.get(key, DEFAULTS.get(key))


## Writes one setting, applies it live and schedules a debounced save.
func set_setting(key: String, value: Variant) -> void:
	GameState.settings[key] = value
	if key == "fullscreen":
		# Tell the engine what the compositor already did before asking it for something else.
		_compositor.align_engine_mode(get_window(), window_is_fullscreen(get_window()))
	apply_key(GameState.settings, key, get_window())
	if key == "fullscreen":
		# The cached answer now describes the window as it was, and believing it for another
		# poll interval would flip this row off and straight back on.
		_compositor.invalidate()
	_queue_save()
	_sync_control(key)
	changed.emit(key, value)
	EventBus.settings_changed.emit(key)


## Reconciles the stored settings with the live window and re-renders the rows that show it.
## Returns the keys that moved.
##
## Owner report 12: "the fullscreen toggle can be out of sync, say it is not fullscreen when in
## reality it is". The setting only flowed one way, so the checkbox rendered what the game last
## decided rather than what was true. This is the read half, on `_process` so a change made
## underneath the game shows up with nobody touching the panel. It never pushes - that would
## fight the compositor for the window, frame after frame.
func sync_from_window() -> PackedStringArray:
	var moved := PackedStringArray()
	var observed := observed_window_settings(get_window())
	# The compositor outranks the engine wherever it answered: it is the only one of the two
	# that can see a fullscreen a window-manager keybind made.
	if _compositor.state != CompositorWindow.State.UNKNOWN:
		observed["fullscreen"] = _compositor.state == CompositorWindow.State.FULLSCREEN
	for key: String in observed.keys():
		var live := bool(observed[key])
		if bool(setting(key)) == live:
			continue
		GameState.settings[key] = live
		_queue_save()
		_sync_control(key)
		moved.append(key)
		changed.emit(key, live)
		EventBus.settings_changed.emit(key)
	return moved


func _process(delta: float) -> void:
	_compositor.poll(delta)
	sync_from_window()
	_tick_cancel_hold(delta)


## Counts the cancel button down while it is held during a gamepad capture. A short press
## backs out (that is what B does everywhere else); holding it past the window binds B, so the
## button the capture reserves is still a button the player can use.
func _tick_cancel_hold(delta: float) -> void:
	if _cancel_held < 0.0 or _capturing == &"":
		return
	_cancel_held += delta
	if _cancel_held < _nav_profile.capture_hold_seconds:
		return
	var event := InputEventJoypadButton.new()
	event.button_index = CAPTURE_CANCEL_BUTTON
	event.pressed = true
	_cancel_held = -1.0
	_commit_capture(event, true)


## Persists any pending change right now (called on close and from tests).
func flush_pending_save() -> void:
	if not _save_pending:
		return
	_save_pending = false
	# _exit_tree can run during shutdown, when the autoload may already be gone.
	if is_instance_valid(GameState):
		GameState.save_settings()


func _queue_save() -> void:
	_save_pending = true
	if _save_scheduled:
		return
	var tree := get_tree()
	if tree == null:
		flush_pending_save()
		return
	_save_scheduled = true
	var timer := tree.create_timer(SAVE_DEBOUNCE, true, false, true)
	timer.timeout.connect(
		func() -> void:
			_save_scheduled = false
			flush_pending_save()
	)


func _exit_tree() -> void:
	flush_pending_save()
	# The query thread writes into `_compositor`; never drop the last reference mid-flight.
	_compositor.shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush_pending_save()


## Applies just the setting `key` (cheaper than re-running `apply_all` on every change).
## `window` is the window to apply the video keys to; null means the main window.
static func apply_key(settings: Dictionary, key: String, window: Window = null) -> void:
	match key:
		"fullscreen", "vsync", "integer_scaling":
			_apply_window(settings, window)
		"master_volume":
			_apply_bus("Master", float(settings.get(key, DEFAULTS[key])))
		"music_volume":
			_apply_bus("Music", float(settings.get(key, DEFAULTS[key])))
		"sfx_volume":
			_apply_bus("SFX", float(settings.get(key, DEFAULTS[key])))
		"deadzone":
			_apply_deadzone(settings)
		"reduce_motion":
			apply_motion_policy(settings)
		"bindings":
			var bindings: Variant = settings.get("bindings", {})
			if bindings is Dictionary:
				InputBindings.apply_bindings(bindings as Dictionary)


## Applies every setting to the engine (window, audio buses, deadzones, bindings).
## Snapshots the shipped InputMap first: `apply_bindings` is about to overwrite it, and the
## snapshot is what "Reset to defaults" falls back on if `project.godot`'s `input/*` entries
## are not readable through ProjectSettings in an exported build.
static func apply_all(settings: Dictionary) -> void:
	InputBindings.capture_default_bindings()
	_apply_window(settings)
	_apply_bus("Master", float(settings.get("master_volume", DEFAULTS["master_volume"])))
	_apply_bus("Music", float(settings.get("music_volume", DEFAULTS["music_volume"])))
	_apply_bus("SFX", float(settings.get("sfx_volume", DEFAULTS["sfx_volume"])))
	_apply_deadzone(settings)
	apply_motion_policy(settings)
	var bindings: Variant = settings.get("bindings", {})
	if bindings is Dictionary:
		InputBindings.apply_bindings(bindings as Dictionary)


## Whether screen shake is actually in effect: the player's own choice, unless reduce motion
## is overriding it. Nothing outside the UI stores a derived value; this is the one place the
## two settings are combined.
static func screen_shake_active(settings: Dictionary) -> bool:
	if bool(settings.get("reduce_motion", DEFAULTS["reduce_motion"])):
		return false
	return bool(settings.get(MOTION_OWNED, DEFAULTS[MOTION_OWNED]))


## Applies `reduce_motion` to the runtime state that is not a setting: hit stop (and the
## room-clear slow-motion behind it) is switched off while the option is on. Screen shake
## needs nothing here — `GameFeel.shake_allowed()` reads the option itself.
static func apply_motion_policy(settings: Dictionary) -> void:
	var reduce := bool(settings.get("reduce_motion", DEFAULTS["reduce_motion"]))
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	# Never conjure the feel service just to leave it enabled; only reach for it when the
	# option is on, or when something already made one.
	if reduce or tree.root.has_node(NodePath(HitStop.NODE_NAME)):
		HitStop.set_enabled(tree, not reduce)


## True when `window` is fullscreen, by either of the engine's two fullscreen modes. A
## maximised window is **not** fullscreen, which is the difference that keeps this from
## un-maximising a window the player maximised themselves - and an ordinary *tiled* Hyprland
## window reads as `MODE_MAXIMIZED`, which is why `FULLSCREEN_MODES` stays an exact list.
##
## **This cannot see a fullscreen the compositor made**; on Wayland nothing in the engine's
## GDScript API can (`CompositorWindow` holds the measurement, and the answer). So this is the
## *engine's* reading: the fallback for when no compositor will answer.
static func window_is_fullscreen(window: Window) -> bool:
	if window == null:
		return false
	return FULLSCREEN_MODES.has(int(window.mode))


## Whether `window.mode` is a reading of anything real. An embedded sub-window keeps its mode
## inside the engine, so it always is; a top-level window hands the question to the display
## server, and the headless one drops every write and answers `MODE_MINIMIZED` to every read -
## which would report a fullscreen the game just asked for as "still windowed" and undo it.
static func window_mode_is_observable(window: Window) -> bool:
	if window == null:
		return false
	return window.is_embedded() or DisplayServer.get_name() != "headless"


## What the live window says about itself, keyed the way `GameState.settings` is - the engine's
## half of the video read-back. `sync_from_window` overrides `fullscreen` with the compositor's
## answer where there is one, because the engine cannot see that (see below).
##
## `vsync` is read back only on a real display server - headless never applies it, so reading
## it there would report the driver's default over the player's choice. `integer_scaling` is
## absent on purpose: `Window.content_scale_stretch` is engine state that nothing outside this
## game writes, so it has nothing to disagree with and stays a one-way push.
static func observed_window_settings(window: Window) -> Dictionary:
	var out: Dictionary = {}
	if window == null:
		return out
	if window_mode_is_observable(window):
		out["fullscreen"] = window_is_fullscreen(window)
	if DisplayServer.get_name() != "headless":
		out["vsync"] = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	return out


static func _apply_window(settings: Dictionary, window: Window = null) -> void:
	if window == null:
		var tree := Engine.get_main_loop() as SceneTree
		window = tree.root if tree != null else null
	if window == null:
		return
	# Only move the window when the preference and the window actually disagree. Comparing
	# against `MODE_FULLSCREEN` alone dragged a window the compositor had put in exclusive
	# fullscreen back out of it, and yanked a maximised window down to its restored size every
	# time any video setting was touched. Writing `Window.mode` is safe everywhere - headless
	# drops it, an embedded window keeps it - so only the vsync call is guarded.
	var fullscreen := bool(settings.get("fullscreen", DEFAULTS["fullscreen"]))
	if fullscreen != window_is_fullscreen(window):
		window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	if DisplayServer.get_name() != "headless":
		var vsync := bool(settings.get("vsync", DEFAULTS["vsync"]))
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		)
	var integer := bool(settings.get("integer_scaling", DEFAULTS["integer_scaling"]))
	window.content_scale_stretch = (
		Window.CONTENT_SCALE_STRETCH_INTEGER if integer else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	)


static func _apply_deadzone(settings: Dictionary) -> void:
	var deadzone := clampf(float(settings.get("deadzone", DEFAULTS["deadzone"])), 0.05, 0.9)
	for action: StringName in DEADZONE_ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, deadzone)


static func _apply_bus(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


## Restores saved bindings: {action: {"kb": [events], "pad": [events]}}.
## A stored empty list means "the player deliberately unbound this device class" (that is
## what conflict resolution leaves behind), so it erases rather than being skipped; a missing
## key means "never touched" and leaves the project default alone.
func _build() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_controls.clear()
	_rebind_buttons.clear()
	_chain.clear()
	for section: Dictionary in SECTIONS:
		_add_heading(str(section["title"]))
		for row: Dictionary in section["rows"]:
			_add_row(row)
		if section["title"] == "Input":
			for hold: Dictionary in HOLD_ROWS:
				_add_hold_row(hold)
			_add_bind_header()
			for action: StringName in REBIND_ACTIONS:
				_add_rebind_row(action)
			_add_reset_row()
	_add_heading(ADVANCED_TITLE)
	_add_seed_row()
	_sync_motion_owned()
	# Explicit neighbours, not Godot's geometric guess: the guess refuses a row the
	# ScrollContainer has clipped, which is every row below the fold (see `UiFocusChain`).
	_chain.wire(_exit_above, _exit_below)
	_hint.text = HINT_DEFAULT


func _add_heading(title: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"Heading"
	label.text = title
	if _list.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, UiTheme.GAP)
		_list.add_child(spacer)
	_list.add_child(label)
	var sep := HSeparator.new()
	_list.add_child(sep)


func _row_container(label_text: String) -> HBoxContainer:
	_chain.begin_row()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.GAP_WIDE)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	_list.add_child(row)
	return row


func _add_row(spec: Dictionary) -> void:
	var key := str(spec["key"])
	var row := _row_container(str(spec["label"]))
	match int(spec["type"]):
		SettingsRows.RowType.BOOL:
			var check := CheckBox.new()
			check.button_pressed = bool(setting(key))
			check.toggled.connect(func(on: bool) -> void: set_setting(key, on))
			check.custom_minimum_size = Vector2(88, 0)
			check.text = "On" if check.button_pressed else "Off"
			row.add_child(check)
			_controls[key] = check
			_track_focus(check)
		SettingsRows.RowType.SLIDER:
			# The slider, its readout and its focus slab are one widget (`SliderRow`): a
			# focused slider has to be as obvious as a focused check row, and the engine gives
			# a slider no focus stylebox to do it with.
			var slider_row := SliderRow.new()
			slider_row.configure(
				float(spec.get("min", 0.0)), float(spec.get("max", 1.0)), float(setting(key))
			)
			slider_row.value_changed.connect(
				func(v: float) -> void: set_setting(key, snappedf(v, 0.01))
			)
			row.add_child(slider_row)
			_controls[key] = slider_row.slider
			_track_focus(slider_row.slider)
		SettingsRows.RowType.CHOICE:
			# One button that steps through the row's choices ("Off", "Low", "High").
			var button := Button.new()
			button.custom_minimum_size = Vector2(BIND_BUTTON_WIDTH * 2, 0)
			button.text = SettingsRows.choice_label(spec, setting(key))
			button.pressed.connect(
				func() -> void: set_setting(key, SettingsRows.next_choice(spec, setting(key)))
			)
			row.add_child(button)
			_controls[key] = button
			_track_focus(button)


## Column headings over the rebind block, so the two buttons per row are not a guessing game.
func _add_bind_header() -> void:
	var row := _row_container("Buttons")
	for title: String in ["Keyboard", "Gamepad"]:
		var label := Label.new()
		label.theme_type_variation = &"Dim"
		label.text = title
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(BIND_BUTTON_WIDTH, 0)
		row.add_child(label)


func _add_rebind_row(action: StringName) -> void:
	var row := _row_container(action_label(action))
	var kb := _bind_button(action, false)
	var pad := _bind_button(action, true)
	row.add_child(kb)
	row.add_child(pad)
	_rebind_buttons[action] = kb
	_pad_buttons[action] = pad
	_refresh_rebind_label(action)
	# Both columns are in the chain: ui_down walks the keyboard column, ui_right steps across
	# to the gamepad one, and a pad can therefore open a capture in either.
	_track_focus(kb)
	_track_focus(pad)


func _bind_button(action: StringName, pad: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(BIND_BUTTON_WIDTH, 0)
	button.clip_text = true
	button.set_meta(BIND_ACTION_META, action)
	button.set_meta(BIND_PAD_META, pad)
	button.pressed.connect(_begin_capture.bind(action, pad))
	return button


## "Reset bindings" puts every action back to the `project.godot` default and forgets every
## stored override, including the unbinds conflict resolution left behind.
func _add_reset_row() -> void:
	var row := _row_container("Reset")
	var button := Button.new()
	button.text = "Back to defaults"
	button.custom_minimum_size = Vector2(BIND_BUTTON_WIDTH * 2, 0)
	button.pressed.connect(reset_bindings)
	row.add_child(button)
	_controls["reset_bindings"] = button
	_track_focus(button)


## Cycling option row: one button that steps through `spec["choices"]`.
func _add_hold_row(spec: Dictionary) -> void:
	var action := StringName(str(spec["action"]))
	var row := _row_container("%s input" % str(spec["label"]))
	var button := Button.new()
	button.custom_minimum_size = Vector2(BIND_BUTTON_WIDTH * 2, 0)
	button.text = _hold_label(action)
	button.pressed.connect(func() -> void: cycle_hold_mode(action))
	row.add_child(button)
	_controls["hold_mode:" + String(action)] = button
	_track_focus(button)


## The player's name for an action. Never the code identifier.
static func action_label(action: StringName) -> String:
	if ACTION_LABELS.has(action):
		return str(ACTION_LABELS[action])
	return String(action).capitalize()


static func _hold_label(action: StringName) -> String:
	var mode := PlayerInput.hold_mode(action)
	for choice: Dictionary in HOLD_CHOICES:
		if str(choice["value"]) == mode:
			return str(choice["label"])
	return mode.capitalize()


## Steps `action` to the next hold/toggle mode and persists it.
func cycle_hold_mode(action: StringName) -> void:
	var mode := PlayerInput.hold_mode(action)
	var index := 0
	for i in HOLD_CHOICES.size():
		if str(HOLD_CHOICES[i]["value"]) == mode:
			index = i
	set_hold_mode(action, str(HOLD_CHOICES[(index + 1) % HOLD_CHOICES.size()]["value"]))


## Writes one action's hold/toggle mode. `mode` is `PlayerInput.MODE_HOLD` or `MODE_TOGGLE`.
func set_hold_mode(action: StringName, mode: String) -> void:
	var modes: Dictionary = {}
	var stored: Variant = GameState.settings.get("hold_mode", {})
	if stored is Dictionary:
		modes = (stored as Dictionary).duplicate(true)
	modes[String(action)] = mode
	set_setting("hold_mode", modes)
	var button: Variant = _controls.get("hold_mode:" + String(action))
	if button is Button:
		(button as Button).text = _hold_label(action)


## The seed row: a field, a die, and two dim lines saying what a seed does and does not fix.
func _add_seed_row() -> void:
	var row := _row_container(SEED_ROW_LABEL)
	_seed_edit = LineEdit.new()
	_seed_edit.custom_minimum_size = Vector2(SEED_FIELD_WIDTH, 0)
	_seed_edit.max_length = 24
	_seed_edit.placeholder_text = SEED_PLACEHOLDER
	_seed_edit.text = str(setting(Title.SEED_SETTING))
	_seed_edit.tooltip_text = Title.SEED_TOOLTIP
	_seed_edit.text_changed.connect(
		func(text: String) -> void: set_setting(Title.SEED_SETTING, text.strip_edges())
	)
	row.add_child(_seed_edit)
	var random := Button.new()
	random.text = "Random"
	random.custom_minimum_size = Vector2(BIND_BUTTON_WIDTH, 0)
	random.pressed.connect(roll_seed)
	row.add_child(random)
	_controls[Title.SEED_SETTING] = _seed_edit
	_track_focus(_seed_edit)
	_track_focus(random)
	var help := Label.new()
	help.theme_type_variation = &"Dim"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = seed_help_text()
	_list.add_child(help)
	if GameState.run_seed != 0:
		var current := Label.new()
		current.theme_type_variation = &"Dim"
		current.text = "This run: %d" % GameState.run_seed
		_list.add_child(current)


## What the seed field says about itself: that it is spent once, and that a seed is not a
## whole dungeon (the live theme, the wallpaper and the music shape every floor too).
static func seed_help_text() -> String:
	var theme_name := Desktop.palette.name if Desktop.palette != null else "The theme"
	return "Used once, by the next new run. %s" % Title.seed_hint_text(theme_name)


## The seed field, for tests and for anything that wants to focus it.
func get_seed_field() -> LineEdit:
	return _seed_edit


## Puts a fresh random seed in the field, for a player who wants one to write down.
func roll_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	set_seed_text(str(rng.randi() & 0x7FFFFFFF))


## Writes the seed field and the setting behind it. Empty means "roll a new one".
func set_seed_text(text: String) -> void:
	set_setting(Title.SEED_SETTING, text.strip_edges())
	if _seed_edit != null:
		_seed_edit.text = text
		_seed_edit.caret_column = text.length()


## Adds `control` to the row the page is currently building, for the focus chain.
func _track_focus(control: Control) -> void:
	_chain.add(control)


func _sync_control(key: String) -> void:
	var control: Variant = _controls.get(key)
	if control is CheckBox:
		var check := control as CheckBox
		check.set_pressed_no_signal(bool(setting(key)))
		check.text = "On" if check.button_pressed else "Off"
	if control is HSlider:
		var slider := control as HSlider
		var target := float(setting(key))
		if not is_equal_approx(slider.value, target):
			slider.set_value_no_signal(target)
	if control is Button and not (control is CheckBox):
		var row := SettingsRows.row_for(key)
		if not row.is_empty():
			(control as Button).text = SettingsRows.choice_label(row, setting(key))
	if control is LineEdit:
		var edit := control as LineEdit
		var text := str(setting(key))
		# Never while the player is typing into it: that would jump the caret every keystroke.
		if not edit.has_focus() and edit.text != text:
			edit.text = text
	if key == "reduce_motion":
		_sync_motion_owned()


## Reduce motion overrides `screen_shake`: its checkbox shows the *effective* value and greys
## out, so the panel never claims a setting the player can no longer choose. The stored
## preference is untouched, so switching reduce motion back off restores it.
func _sync_motion_owned() -> void:
	var control: Variant = _controls.get(MOTION_OWNED)
	if not (control is CheckBox):
		return
	var check := control as CheckBox
	var locked := bool(setting("reduce_motion"))
	check.disabled = locked
	check.set_pressed_no_signal(screen_shake_active(GameState.settings))
	check.text = "On" if check.button_pressed else "Off"
	check.tooltip_text = "Overridden by Reduce motion" if locked else ""


func _refresh_rebind_labels() -> void:
	for action: StringName in _rebind_buttons.keys():
		_refresh_rebind_label(action)


func _refresh_rebind_label(action: StringName) -> void:
	_write_bind_label(_rebind_buttons.get(action), action, false)
	_write_bind_label(_pad_buttons.get(action), action, true)


func _write_bind_label(button: Variant, action: StringName, pad: bool) -> void:
	if not (button is Button):
		return
	var control := button as Button
	# The Keyboard column is drawn inert while a gamepad is live: it still shows the key it
	# holds, because that is information, but it no longer looks like something to press.
	control.modulate.a = 1.0 if pad or keyboard_column_live() else INERT_COLUMN_ALPHA
	if _capturing == action and _capturing_pad == pad:
		control.text = "Press..."
		return
	control.text = InputGlyphs.binding_name(
		action, InputGlyphs.Device.GAMEPAD if pad else InputGlyphs.Device.KEYBOARD
	)


func _begin_capture(action: StringName, pad: bool = false) -> void:
	if not pad and not keyboard_column_live():
		# Nothing a pad can send is a key, so a capture opened from one can only end in
		# "nothing bound". Say what the column is instead of opening it (see the notice).
		_column_notice = true
		_hint.text = keyboard_column_notice(action)
		return
	_capturing = action
	_capturing_pad = pad
	_refresh_rebind_label(action)
	_hint.text = capture_prompt(action, pad)


## Whether the Keyboard column will open a capture right now.
##
## It will not while a gamepad is the live device. A keyboard binding can only be set by
## pressing the key, a pad has no keys, and the capture takes the whole input stream while it
## is open - so from a controller the row opened a "Press a key..." prompt that the controller
## could only ever back out of. That is the row reading as broken, and it is not fixed by
## making the prompt more apologetic.
##
## The alternative was an on-screen key picker a pad could drive. It was not taken: its entire
## audience is a player setting a key on a machine they have no keyboard for, which is a
## binding they can never press. A player who *does* have a keyboard has a better way to say
## which key they want - press it - and reaches this column by pressing Enter on it, which
## makes the keyboard the live device and opens the capture in the same motion.
static func keyboard_column_live() -> bool:
	return InputGlyphs.current_device() != InputGlyphs.Device.GAMEPAD


## What the Keyboard column says to a controller: which device it needs, how to open it
## anyway, and where the column a pad *can* fill in is.
static func keyboard_column_notice(action: StringName) -> String:
	return (
		"%s: keys need a keyboard - press {ui_accept@kb} on one, or use the Gamepad column"
		% (action_label(action))
	)


## What the hint line says while a capture is open. It names a way out that works on the
## device the player is holding - B on a pad, Escape on a keyboard - because a capture eats
## the input stream and "Esc cancels" is not an instruction a controller can follow. On the
## gamepad column it also names the way to bind B itself, which the cancel button would
## otherwise have cost the player outright.
static func capture_prompt(action: StringName, pad: bool) -> String:
	if pad:
		return (
			"Press a gamepad button for %s - tap {ui_cancel} to cancel, hold it to bind it"
			% action_label(action)
		)
	return "Press a key for %s - {ui_cancel} or {ui_cancel@pad} cancels" % action_label(action)


## What the hint says while the cancel button is being held down: the player is mid-gesture and
## a prompt that still only says "tap B to cancel" is a prompt that lies about what is about to
## happen.
static func hold_prompt(action: StringName) -> String:
	return "Keep holding {ui_cancel} to bind it to %s, let go to cancel" % action_label(action)


## The protected action `event` would take a gamepad button away from, or `&""` when it takes
## nothing protected. See `PROTECTED_PAD_ACTIONS`.
static func protected_conflict(action: StringName, event: InputEvent) -> StringName:
	for other: StringName in InputBindings.conflicts_for(action, event):
		if PROTECTED_PAD_ACTIONS.has(other):
			return other
	return &""


## What the hint line says when a binding is refused for taking a protected button: the button
## by name and what it already does, because "that one is taken" without saying by what is a
## refusal the player cannot act on.
static func protected_refusal(event: InputEvent, action: StringName) -> String:
	return "%s is %s - pick another button" % [InputGlyphs.event_token(event), action_label(action)]


## Consumes `event` as the new binding for the action being captured.
##
## Every accepted input either binds or ends the capture - nothing is swallowed and left
## waiting. The capture takes the whole input stream while it is open (that is what makes it
## a capture), so an input it neither binds nor answers is a screen a player cannot leave:
## on the standalone Settings page there is no pause menu behind it and a pad-only player had
## to kill the process. `CAPTURE_CANCEL_BUTTON` (B) and Escape always back out, and an input
## that belongs to the *other* device column backs out too, saying which column wants it.
func _try_capture(event: InputEvent) -> bool:
	var pad := false
	var accept := false
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_cancel_capture("Rebind cancelled - nothing changed")
			return true
		accept = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		accept = true
	elif event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.button_index == CAPTURE_CANCEL_BUTTON:
			return _handle_cancel_button(button.pressed)
		if not button.pressed:
			return false
		accept = true
		pad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) < CAPTURE_AXIS_THRESHOLD:
			return false
		accept = true
		pad = true
	if not accept:
		return false
	return _commit_capture(event, pad)


## The cancel button, press and release. A tap backs out; a hold binds B (`_tick_cancel_hold`),
## so the button the capture has to reserve is not a button the player loses.
func _handle_cancel_button(pressed: bool) -> bool:
	if not _capturing_pad:
		# Nothing to bind in the keyboard column, so B is purely the way out here.
		if pressed:
			_cancel_capture("Rebind cancelled - nothing changed")
		return true
	if pressed:
		if _cancel_held < 0.0:
			_cancel_held = 0.0
			_hint.text = hold_prompt(_capturing)
		return true
	if _cancel_held >= 0.0:
		_cancel_held = -1.0
		_cancel_capture("Rebind cancelled - nothing changed")
	return true


## Binds `event` to the action being captured, or says why it cannot. Returns true when the
## event was consumed, which every input that reaches here is.
func _commit_capture(event: InputEvent, pad: bool) -> bool:
	# A row has one column per device class: a pad button cannot land in the keyboard column.
	if pad != _capturing_pad:
		_cancel_capture(
			(
				"Nothing bound - %s live in the %s column"
				% [
					"pad buttons" if pad else "keys and mouse buttons",
					"Gamepad" if pad else "Keyboard"
				]
			)
		)
		return true
	if pad:
		var guarded := protected_conflict(_capturing, event)
		if guarded != &"":
			_cancel_capture(protected_refusal(event, guarded))
			return true
	rebind(_capturing, event, pad)
	_end_capture()
	return true


## Ends the capture without binding anything and says so on the hint line.
func _cancel_capture(reason: String) -> void:
	_end_capture()
	_hint.text = reason


## Replaces the keyboard/mouse (or pad) binding of `action` with `event` and persists it.
##
## The new binding always wins: any other rebindable action holding the same input loses it
## (and is persisted as unbound, so the clash does not come back on the next launch). Returns
## the actions that were cleared, which is what the hint line reports.
func rebind(action: StringName, event: InputEvent, pad: bool) -> Array[StringName]:
	var clean := InputBindings.deserialize_event(InputBindings.serialize_event(event))
	var cleared: Array[StringName] = []
	if clean == null:
		return cleared
	var bindings: Dictionary = {}
	var stored: Variant = GameState.settings.get("bindings", {})
	if stored is Dictionary:
		bindings = (stored as Dictionary).duplicate(true)
	for other: StringName in InputBindings.conflicts_for(action, clean):
		var other_pad := InputBindings.drop_event(other, clean)
		InputBindings.store_events(bindings, other, other_pad)
		cleared.append(other)
	InputBindings.erase_device_events(action, pad)
	InputMap.action_add_event(action, clean)
	InputBindings.store_events(bindings, action, pad)
	GameState.settings["bindings"] = bindings
	GameState.save_settings()
	changed.emit("bindings", bindings)
	EventBus.settings_changed.emit("bindings")
	_refresh_rebind_labels()
	if not cleared.is_empty():
		var names := PackedStringArray()
		for name: StringName in cleared:
			names.append(String(name).capitalize())
		_hint.text = "Unbound from %s" % ", ".join(names)
	return cleared


## Restores every rebindable action to its project default and forgets the stored overrides.
func reset_bindings() -> void:
	for action: StringName in REBIND_ACTIONS:
		InputBindings.restore_default_binding(action)
	GameState.settings["bindings"] = {}
	GameState.save_settings()
	_refresh_rebind_labels()
	_hint.text = "Bindings reset to defaults"
	changed.emit("bindings", {})
	EventBus.settings_changed.emit("bindings")


func _end_capture() -> void:
	var action := _capturing
	_capturing = &""
	_capturing_pad = false
	_cancel_held = -1.0
	if action != &"":
		_refresh_rebind_label(action)
	if not _hint.text.begins_with("Unbound from"):
		_hint.text = HINT_DEFAULT
