## Autoload `Desktop`. Owns the active ThemePalette/ThemeProfile/wallpaper analysis and
## polls the desktop (Omarchy state dir, otter-wallpaper state) for live changes.
## Polling every 300 ms matches what omarchy-shell itself does.
extends Node

enum Source { FALLBACK, OMARCHY, OTTER }

const POLL_INTERVAL := 0.3
## Quiet time after the last observed change before the swap is applied.
##
## This MUST be longer than `POLL_INTERVAL` or it debounces nothing: at 0.15 s the timer
## always expired before the next poll could see the next file land, so switching an Omarchy
## theme - which rewrites the theme link, colors.toml, the background and the hook over a
## couple of seconds - applied a full retint *and* a wallpaper decode on every single poll.
## The owner's report was "it lags like shit when I swap omarchy theme for a few seconds";
## that was roughly seven swaps, not one.
const DEBOUNCE := 0.45
const HOOK_FILE := "omadungeon/theme-changed"

var palette: ThemePalette
var profile: ThemeProfile
var wallpaper: WallpaperAnalyzer.Result
var source: Source = Source.FALLBACK
var omarchy: OmarchyState
var wallpaper_is_video: bool = false

var _last_signature: String = ""
var _pending_kind: int = 0
var _debounce_left: float = -1.0
var _poll_left: float = 0.0
var _analysis_task: int = -1
var _analysis_result: WallpaperAnalyzer.Result
var _analysis_path: String = ""
var _analysis_key: String = ""
var _analysis_mutex := Mutex.new()
## Results already measured, keyed by "<path>|<modified time>". Analysing a wallpaper means
## decoding it at full resolution before it is sampled down, which is the most expensive
## thing a theme swap does; swapping between two themes, or back to one seen a minute ago,
## would otherwise pay it again every time. The key carries the mtime so editing a wallpaper
## in place still re-measures it.
var _analysis_cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var override := ""
	if GameState.cli_args.has("theme-state"):
		override = str(GameState.cli_args["theme-state"])
	omarchy = OmarchyState.new(override)
	reload(true)


func _exit_tree() -> void:
	# Never let a worker thread outlive this node (it touches our mutex and result fields).
	if _analysis_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_analysis_task)
		_analysis_task = -1


func _process(delta: float) -> void:
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = POLL_INTERVAL
		_poll()
	if _debounce_left >= 0.0:
		_debounce_left -= delta
		if _debounce_left < 0.0:
			var kind := _pending_kind
			_pending_kind = 0
			_apply_change(kind)
	_collect_analysis()
	if OS.is_debug_build() and Input.is_action_just_pressed(&"debug_reload_theme"):
		reload(false)


func _poll() -> void:
	var sig := _signature()
	if sig == _last_signature:
		return
	var kind := _diff_kind(_last_signature, sig)
	_last_signature = sig
	_pending_kind |= kind
	_debounce_left = DEBOUNCE


func _signature() -> String:
	var hook := ""
	var runtime := OS.get_environment("XDG_RUNTIME_DIR")
	if not runtime.is_empty():
		hook = str(FileAccess.get_modified_time(runtime.path_join(HOOK_FILE)))
	return "%s||%s||%s" % [omarchy.signature(), OtterWallpaper.signature(), hook]


func _diff_kind(old_sig: String, new_sig: String) -> int:
	var old_parts := old_sig.split("||")
	var new_parts := new_sig.split("||")
	if old_parts.size() < 3 or new_parts.size() < 3:
		return EventBus.DesktopChangeKind.BOTH
	var kind := 0
	var old_om := old_parts[0].split("|")
	var new_om := new_parts[0].split("|")
	if old_om.size() == 3 and new_om.size() == 3:
		if old_om[0] != new_om[0] or old_om[2] != new_om[2]:
			kind |= EventBus.DesktopChangeKind.THEME
		if old_om[1] != new_om[1]:
			kind |= EventBus.DesktopChangeKind.WALLPAPER
	else:
		kind |= EventBus.DesktopChangeKind.BOTH
	var old_otter := old_parts[1].split("|")
	var new_otter := new_parts[1].split("|")
	if old_otter.size() == 2 and new_otter.size() == 2:
		if old_otter[0] != new_otter[0]:
			kind |= EventBus.DesktopChangeKind.WALLPAPER
		if old_otter[1] != new_otter[1]:
			kind |= EventBus.DesktopChangeKind.THEME
	elif old_parts[1] != new_parts[1]:
		kind |= EventBus.DesktopChangeKind.BOTH
	if old_parts[2] != new_parts[2]:
		kind |= EventBus.DesktopChangeKind.THEME
	return kind if kind != 0 else EventBus.DesktopChangeKind.BOTH


## Full reload of palette and wallpaper. `silent` suppresses the change signal.
func reload(silent: bool) -> void:
	_last_signature = _signature()
	_load_palette()
	_start_wallpaper_analysis()
	if not silent:
		EventBus.desktop_changed.emit(EventBus.DesktopChangeKind.BOTH)
	EventBus.palette_changed.emit(palette)


func _apply_change(kind: int) -> void:
	if kind & EventBus.DesktopChangeKind.THEME:
		_load_palette()
	if kind & EventBus.DesktopChangeKind.WALLPAPER or source == Source.OTTER:
		_start_wallpaper_analysis()
	EventBus.desktop_changed.emit(kind)
	if kind & EventBus.DesktopChangeKind.THEME:
		EventBus.palette_changed.emit(palette)
		EventBus.toast.emit("Theme: %s" % palette.name, 2.5)


func _load_palette() -> void:
	var toml := omarchy.load_colors() if omarchy.is_available() else null
	if toml != null and toml.is_complete():
		palette = ThemePalette.from_colors_toml(toml, omarchy.theme_name())
		source = Source.OMARCHY
	else:
		var otter_path := OtterWallpaper.theme_colors_path()
		var otter_colors := (
			OtterWallpaper.load_colors(otter_path) if not otter_path.is_empty() else {}
		)
		if otter_colors.size() >= 6:
			palette = ThemePalette.from_otter_colors(otter_colors, "Otter")
			source = Source.OTTER
		else:
			palette = ThemePalette.fallback()
			source = Source.FALLBACK
			print("Desktop: no Omarchy/otter theme found, using fallback palette")
	profile = ThemeProfile.from_palette(palette)


func _current_wallpaper_path() -> String:
	wallpaper_is_video = false
	if source == Source.OMARCHY or omarchy.is_available():
		var bg := omarchy.background_path()
		if not bg.is_empty():
			if omarchy.background_is_video():
				wallpaper_is_video = true
				return omarchy.preview_path()
			return bg
	var otter := OtterWallpaper.current_wallpaper()
	if not otter.is_empty():
		return otter
	return ""


func _start_wallpaper_analysis() -> void:
	if not bool(GameState.settings.get("wallpaper_influence", true)):
		wallpaper = null
		return
	var path := _current_wallpaper_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		wallpaper = null
		return
	var key := "%s|%d" % [path, FileAccess.get_modified_time(path)]
	if _analysis_cache.has(key):
		wallpaper = _analysis_cache[key] as WallpaperAnalyzer.Result
		return
	if _analysis_task >= 0:
		return
	_analysis_path = path
	_analysis_key = key
	_analysis_task = WorkerThreadPool.add_task(_analyze_in_thread.bind(path), false, "wallpaper")


func _analyze_in_thread(path: String) -> void:
	var result := WallpaperAnalyzer.analyze_file(path)
	_analysis_mutex.lock()
	_analysis_result = result
	_analysis_mutex.unlock()


func _collect_analysis() -> void:
	if _analysis_task < 0 or not WorkerThreadPool.is_task_completed(_analysis_task):
		return
	WorkerThreadPool.wait_for_task_completion(_analysis_task)
	_analysis_task = -1
	_analysis_mutex.lock()
	wallpaper = _analysis_result
	_analysis_result = null
	_analysis_mutex.unlock()
	if wallpaper != null and not _analysis_key.is_empty():
		_analysis_cache[_analysis_key] = wallpaper
	_analysis_key = ""
	if wallpaper != null:
		EventBus.desktop_changed.emit(EventBus.DesktopChangeKind.WALLPAPER)


func source_name() -> String:
	match source:
		Source.OMARCHY:
			return "omarchy"
		Source.OTTER:
			# The one name a player may ever see for this source (owner rule: no otter-shell
			# or internal source labels in player-facing text; `NoOtterWordingTest`).
			return "Otter"
		_:
			return "fallback"
