## The settings page as data: every key `SettingsPanel` draws, its default, the section it
## sits in and the kind of control it gets. Split out of the panel so a module that needs a
## row (the lighting quality, the music light amount, a new accessibility switch) adds one
## line here and nothing in the 1200-line panel has to move.
##
## Row shape: `{"key", "label", "type"}` plus, for a SLIDER, optional `"min"`/`"max"` (0..1
## when absent) and, for a CHOICE, `"choices": [{"value", "label"}, ...]` cycled by one button.
## Every key drawn here needs a `DEFAULTS` entry; `tests/unit/ui/settings_panel_test.gd` checks.
## Applying a value is the panel's `apply_key` (window, buses, deadzone) or, for a module
## that owns its own state, `EventBus.settings_changed(key)` which fires on every write.
class_name SettingsRows
extends RefCounted

## Row kinds the panel can draw. BOOL, SLIDER and CHOICE are data-driven from `SECTIONS`;
## OPTION (the hold/toggle rows) and REBIND are appended to the Input section by the panel,
## because they come from action lists rather than from settings keys.
enum RowType { BOOL, SLIDER, OPTION, REBIND, CHOICE }

## What each action is called on screen. `String(action).capitalize()` prints the code name -
## "Secondary", "Active 1", "Move Up" - and the pause menu's Controls page already had the
## player's words for the same ten things. One list, so the two pages cannot disagree.
const ACTION_LABELS: Dictionary = {
	&"move_up": "Move up",
	&"move_down": "Move down",
	&"move_left": "Move left",
	&"move_right": "Move right",
	&"attack": "Attack",
	&"secondary": "Weapon skill",
	&"dodge": "Dodge",
	&"active_1": "Ability 1",
	&"active_2": "Ability 2",
	&"interact": "Interact",
	&"potion": "Drink potion",
	&"map": "Build screen",
	&"pause": "Pause",
}

## Hold/toggle rows, one per action `PlayerInput` can latch.
const HOLD_ROWS: Array[Dictionary] = [
	{"action": &"attack", "label": "Attack"},
	{"action": &"secondary", "label": "Weapon skill"},
	{"action": &"map", "label": "Build screen"},
]
const HOLD_CHOICES: Array[Dictionary] = [
	{"value": PlayerInput.MODE_HOLD, "label": "Hold"},
	{"value": PlayerInput.MODE_TOGGLE, "label": "Toggle"},
]
const DEADZONE_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"aim_up",
	&"aim_down",
	&"aim_left",
	&"aim_right"
]

## Defaults for keys GameState does not seed itself.
const DEFAULTS: Dictionary = {
	"fullscreen": false,
	"vsync": true,
	"integer_scaling": true,
	"screen_shake": true,
	"damage_numbers": true,
	"lighting_quality": 2,
	"lighting_shadows": true,
	"master_volume": 1.0,
	"music_volume": 0.8,
	"sfx_volume": 1.0,
	"explicit_music": true,
	"music_lights": true,
	"music_lights_amount": 1.0,
	"lyrics": true,
	"track_banner": true,
	"deadzone": 0.3,
	"rumble": true,
	"colorblind_glyphs": false,
	"reduced_flash": false,
	"reduce_motion": false,
	"hold_to_toggle": false,
	"hold_mode": {},
	"wallpaper_influence": true,
	"bindings": {},
	"custom_seed": "",
}

const SECTIONS: Array[Dictionary] = [
	{
		"title": "Video",
		"rows":
		[
			{"key": "fullscreen", "label": "Fullscreen", "type": RowType.BOOL},
			{"key": "vsync", "label": "VSync", "type": RowType.BOOL},
			{"key": "integer_scaling", "label": "Sharp pixel scaling", "type": RowType.BOOL},
			{"key": "screen_shake", "label": "Screen shake", "type": RowType.BOOL},
			{"key": "damage_numbers", "label": "Damage numbers", "type": RowType.BOOL},
			{
				"key": "lighting_quality",
				"label": "Lighting",
				"type": RowType.CHOICE,
				"choices":
				[
					{"value": 0, "label": "Off"},
					{"value": 1, "label": "Low"},
					{"value": 2, "label": "High"},
				]
			},
			{"key": "lighting_shadows", "label": "Shadows", "type": RowType.BOOL},
		]
	},
	{
		"title": "Audio",
		"rows":
		[
			# A slider with no "min"/"max" is 0..1.
			{"key": "master_volume", "label": "Master", "type": RowType.SLIDER},
			{"key": "music_volume", "label": "Music", "type": RowType.SLIDER},
			{"key": "sfx_volume", "label": "SFX", "type": RowType.SLIDER},
			{"key": "explicit_music", "label": "Allow explicit tracks", "type": RowType.BOOL},
			{
				"key": "music_lights",
				"label": "Music lights (slow, never flash)",
				"type": RowType.BOOL
			},
			{"key": "music_lights_amount", "label": "Music light amount", "type": RowType.SLIDER},
			{"key": "lyrics", "label": "Show lyrics", "type": RowType.BOOL},
			{"key": "track_banner", "label": "Now-playing banner", "type": RowType.BOOL},
		]
	},
	{
		"title": "Input",
		"rows":
		[
			{
				"key": "deadzone",
				"label": "Stick deadzone",
				"type": RowType.SLIDER,
				"min": 0.05,
				"max": 0.6
			},
			{"key": "rumble", "label": "Rumble", "type": RowType.BOOL},
		]
	},
	{
		"title": "Accessibility",
		"rows":
		[
			{"key": "colorblind_glyphs", "label": "Colour-blind glyphs", "type": RowType.BOOL},
			{"key": "reduced_flash", "label": "Reduced flashing", "type": RowType.BOOL},
			{"key": "reduce_motion", "label": "Reduce motion", "type": RowType.BOOL},
		]
	},
	{
		"title": "Gameplay",
		"rows":
		[
			{
				"key": "wallpaper_influence",
				"label": "Wallpaper shapes the dungeon",
				"type": RowType.BOOL
			}
		]
	},
]


## Every row of every section, flattened, for the checks that walk them.
static func all_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for section: Dictionary in SECTIONS:
		for row: Dictionary in section["rows"] as Array:
			out.append(row)
	return out


## The row drawn for `key`, or `{}`.
static func row_for(key: String) -> Dictionary:
	for row: Dictionary in all_rows():
		if str(row["key"]) == key:
			return row
	return {}


## The label a CHOICE row prints for `value`; the value itself when no choice names it.
static func choice_label(row: Dictionary, value: Variant) -> String:
	for choice: Dictionary in row.get("choices", []) as Array:
		if choice["value"] == value:
			return str(choice["label"])
	return str(value)


## The value after `value` in a CHOICE row's list, wrapping; the first when none matches.
static func next_choice(row: Dictionary, value: Variant) -> Variant:
	var choices: Array = row.get("choices", [])
	if choices.is_empty():
		return value
	for i in choices.size():
		if (choices[i] as Dictionary)["value"] == value:
			return (choices[(i + 1) % choices.size()] as Dictionary)["value"]
	return (choices[0] as Dictionary)["value"]
