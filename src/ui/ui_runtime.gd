## Mutable state shared by the static UiTheme / InputGlyphs helpers (gdlint forbids
## static vars in this project). One instance lives as metadata on the SceneTree for
## the lifetime of the game.
class_name UiRuntime
extends RefCounted

const META_KEY := &"ui_runtime"

# UiTheme state.
var theme: Theme
var current: Dictionary = {}
var from: Dictionary = {}
var to: Dictionary = {}
var tween: Tween
var styles: Dictionary = {}
var heading_font: Font
var body_font: Font
var icons: Texture2D
var ability_icons: Texture2D
var icon_cache: Dictionary = {}
var theme_connected: bool = false
## Controls the shared theme has been handed to (`UiTheme.apply`). Held so a write can take
## the theme off them first: see `UiTheme._write`.
var themed: Array[Control] = []
## Cache of `UiTheme.signal_color` results; cleared on every theme write.
var signal_colors: Dictionary = {}

# InputGlyphs state.
var device: int = 0
## `Time.get_ticks_msec()` of the last event that made the pad the active device; -1 for never.
var last_pad_msec: int = -1
## `UiNavProfile.mouse_grace_seconds` in ms, read once on first use; -1 until then.
var pad_grace_msec: int = -1
var glyph_sheet: Texture2D
var glyph_cells: Dictionary = {}
var glyphs_connected: bool = false

## Ability catalogue, loaded on first use by the screens that need to turn an ability id into
## a display name (the class cards' innate and class active). Cached here rather than reloaded
## per card: `load_default()` parses a .tres.
var ability_registry: AbilityRegistry

## Boot-time InputMap snapshot (action -> Array[InputEvent]) used by "Reset to defaults" when
## `project.godot`'s `input/*` entries are not readable through ProjectSettings. Written once
## by `SettingsPanel.capture_default_bindings()` before any saved binding is applied.
var default_bindings: Dictionary = {}


## Returns the shared instance, creating it on first use.
static func get_shared() -> UiRuntime:
	var holder := _holder()
	if holder == null:
		return UiRuntime.new()
	if holder.has_meta(META_KEY):
		var existing := holder.get_meta(META_KEY) as UiRuntime
		if existing != null:
			return existing
	var runtime := UiRuntime.new()
	holder.set_meta(META_KEY, runtime)
	return runtime


## The object the shared instance hangs off. The SceneTree outlives every scene and,
## unlike an autoload, cannot be swept up by a test harness auto-free.
static func _holder() -> Object:
	var loop := Engine.get_main_loop()
	if loop != null:
		return loop
	if is_instance_valid(EventBus):
		return EventBus
	return null
