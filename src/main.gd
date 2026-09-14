## Boot / menu scene: shows the title screen and every screen reachable from it
## (class select, settings, stats, credits) plus the run summary after a run ended.
## The screens are pure UI; `RunManager` owns everything that happens inside a run.
class_name Main
extends Control

enum Screen { TITLE, CLASS_SELECT, SETTINGS, STATS, CREDITS, SUMMARY }

const SCENES: Dictionary = {
	Screen.TITLE: "res://src/ui/title.tscn",
	Screen.CLASS_SELECT: "res://src/ui/class_select.tscn",
	Screen.SETTINGS: "res://src/ui/settings_panel.tscn",
	Screen.STATS: "res://src/ui/stats_screen.tscn",
	Screen.CREDITS: "res://src/ui/credits.tscn",
	Screen.SUMMARY: "res://src/ui/run_summary.tscn",
}

## Seed the title screen handed over; used by class select and by "retry seed".
var pending_seed: int = 0
var screen: Screen = Screen.TITLE
var current: Control

@onready var _background: ColorRect = %Background
@onready var _screens: Control = %Screens


func _ready() -> void:
	UiTheme.apply(self)
	SettingsPanel.apply_all(GameState.settings)
	Audio.preload_all()
	EventBus.palette_changed.connect(_on_palette_changed)
	_refresh_background()
	Music.play_menu(GameState.class_id)
	if not RunManager.pending_summary.is_empty():
		show_screen(Screen.SUMMARY)
	else:
		show_screen(Screen.TITLE)


## Swaps the visible screen and wires its signals.
func show_screen(next: Screen) -> Control:
	screen = next
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = null
	var packed := load(str(SCENES[next])) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Control
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screens.add_child(node)
	current = node
	match next:
		Screen.TITLE:
			_wire_title(node as Title)
		Screen.CLASS_SELECT:
			_wire_class_select(node as ClassSelect)
		Screen.SETTINGS:
			(node as SettingsPanel).back_pressed.connect(_back_to_title)
		Screen.STATS:
			var stats := node as StatsScreen
			stats.back_pressed.connect(_back_to_title)
			stats.show_stats(SaveManager.profile.to_dict())
		Screen.CREDITS:
			(node as Credits).back_pressed.connect(_back_to_title)
		Screen.SUMMARY:
			_wire_summary(node as RunSummary)
	return node


func _wire_title(title: Title) -> void:
	title.new_run_pressed.connect(_on_new_run_pressed)
	title.continue_pressed.connect(_on_continue_pressed)
	title.stats_pressed.connect(func() -> void: show_screen(Screen.STATS))
	title.settings_pressed.connect(func() -> void: show_screen(Screen.SETTINGS))
	title.credits_pressed.connect(func() -> void: show_screen(Screen.CREDITS))
	title.quit_pressed.connect(_on_quit_pressed)


func _wire_class_select(picker: ClassSelect) -> void:
	var locked: Array[StringName] = []
	for id: StringName in ClassSelect.class_ids():
		if not SaveManager.is_unlocked(id):
			locked.append(id)
	picker.locked_ids = locked
	picker.class_chosen.connect(_on_class_chosen)
	picker.back_pressed.connect(_back_to_title)


func _wire_summary(summary: RunSummary) -> void:
	var data := RunManager.pending_summary.duplicate(true)
	RunManager.pending_summary = {}
	summary.show_summary(data)
	summary.retry_seed_pressed.connect(
		func() -> void: RunManager.new_run(int(data.get("seed", 0)), GameState.class_id)
	)
	summary.new_run_pressed.connect(
		func() -> void:
			pending_seed = _random_seed()
			show_screen(Screen.CLASS_SELECT)
	)
	summary.title_pressed.connect(_back_to_title)


func _back_to_title() -> void:
	show_screen(Screen.TITLE)


func _on_new_run_pressed(seed_value: int) -> void:
	pending_seed = seed_value
	show_screen(Screen.CLASS_SELECT)


func _on_class_chosen(class_id: StringName) -> void:
	RunManager.new_run(pending_seed, class_id)


func _on_continue_pressed() -> void:
	if not RunManager.resume_run():
		EventBus.toast.emit("No run to continue", 2.0)
		show_screen(Screen.TITLE)


func _on_quit_pressed() -> void:
	SaveManager.flush_autosave()
	QuitGuard.request(get_tree())


static func _random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi() & 0x7FFFFFFF


func _on_palette_changed(_palette: ThemePalette) -> void:
	_refresh_background()


func _refresh_background() -> void:
	if Desktop.palette != null:
		_background.color = Desktop.palette.get_color(&"void")
