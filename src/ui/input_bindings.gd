## The binding model behind the Settings page: which actions can be rebound, how one input
## event is stored and read back, which other actions an input already belongs to, and how to
## get back to what `project.godot` shipped.
##
## Split out of `SettingsPanel` because none of it is UI. A rebind is a change to the live
## `InputMap` plus a line in `GameState.settings["bindings"]`, and the rules for that - one
## device column per action, an unbind stored as an empty list rather than a missing key, the
## boot-time snapshot that "Back to defaults" falls back on - are the same whether a panel, a
## test or a future controller-setup screen is asking.
##
## Storage shape: `{action: {"kb": [event...], "pad": [event...]}}`, each event a small
## dictionary from `serialize_event`. A stored *empty* list means "the player deliberately
## unbound this device class" (which is what conflict resolution leaves behind) and is applied;
## a missing key means "never touched" and leaves the project default alone.
class_name InputBindings
extends RefCounted

## Every action the Settings page offers a row for, in the order it draws them. Also the set
## `conflicts_for` searches: an input taken from one of these is taken from a player.
const ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"attack",
	&"secondary",
	&"dodge",
	&"active_1",
	&"active_2",
	&"interact",
	&"potion",
	&"map",
	&"pause",
]


## Serialises one input event to the stored form; `{}` for an event shape that is not bindable.
static func serialize_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {
			"type": "key",
			"code": int(key.physical_keycode if key.physical_keycode else key.keycode)
		}
	if event is InputEventMouseButton:
		return {"type": "mouse", "button": int((event as InputEventMouseButton).button_index)}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "button": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"type": "joy_axis", "axis": int(motion.axis), "value": signf(motion.axis_value)}
	return {}


static func deserialize_event(data: Dictionary) -> InputEvent:
	match str(data.get("type", "")):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(data.get("code", 0)) as Key
			return key
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(data.get("button", 1)) as MouseButton
			mouse.pressed = true
			return mouse
		"joy_button":
			var button := InputEventJoypadButton.new()
			button.button_index = int(data.get("button", 0)) as JoyButton
			button.pressed = true
			return button
		"joy_axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(data.get("axis", 0)) as JoyAxis
			motion.axis_value = float(data.get("value", 1.0))
			return motion
	return null


static func erase_device_events(action: StringName, pad: bool) -> void:
	for event: InputEvent in InputMap.action_get_events(action):
		var is_pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_pad == pad:
			InputMap.action_erase_event(action, event)


static func apply_bindings(bindings: Dictionary) -> void:
	for action_key: String in bindings.keys():
		var action := StringName(action_key)
		if not InputMap.has_action(action):
			continue
		var entry: Variant = bindings[action_key]
		if not (entry is Dictionary):
			continue
		for device: String in ["kb", "pad"]:
			var events: Variant = (entry as Dictionary).get(device)
			if not (events is Array):
				continue
			erase_device_events(action, device == "pad")
			for data: Variant in events:
				if data is Dictionary:
					var event := deserialize_event(data as Dictionary)
					if event != null:
						InputMap.action_add_event(action, event)


## True when two input events are the same binding (same key, button, or stick direction).
static func events_match(a: InputEvent, b: InputEvent) -> bool:
	var da := serialize_event(a)
	return not da.is_empty() and da == serialize_event(b)


## Rebindable actions other than `action` that `event` would collide with. Public so the
## caller (and the tests) can see a clash without having to perform one.
static func conflicts_for(action: StringName, event: InputEvent) -> Array[StringName]:
	var out: Array[StringName] = []
	if event == null:
		return out
	for other: StringName in ACTIONS:
		if other == action or not InputMap.has_action(other):
			continue
		for existing: InputEvent in InputMap.action_get_events(other):
			if events_match(existing, event):
				out.append(other)
				break
	return out


## Erases every copy of `event` from `action`. Returns true when the erased event was a pad
## one, which is the device column that has to be re-serialised afterwards.
static func drop_event(action: StringName, event: InputEvent) -> bool:
	var was_pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	for existing: InputEvent in InputMap.action_get_events(action):
		if events_match(existing, event):
			InputMap.action_erase_event(action, existing)
	return was_pad


## Snapshots one device column of `action` from the live InputMap into `bindings`.
static func store_events(bindings: Dictionary, action: StringName, pad: bool) -> void:
	var serialised: Array = []
	for existing: InputEvent in InputMap.action_get_events(action):
		var is_pad := existing is InputEventJoypadButton or existing is InputEventJoypadMotion
		if is_pad != pad:
			continue
		var data := serialize_event(existing)
		if not data.is_empty():
			serialised.append(data)
	var entry: Dictionary = bindings.get(String(action), {})
	entry["pad" if pad else "kb"] = serialised
	bindings[String(action)] = entry


## Records the InputMap as it stands, once, for every rebindable action. Call before the
## first `apply_bindings` of a process; later calls are no-ops so a rebound map can never
## overwrite the snapshot.
static func capture_default_bindings() -> void:
	var store := UiRuntime.get_shared().default_bindings
	for action: StringName in ACTIONS:
		if store.has(action) or not InputMap.has_action(action):
			continue
		var events: Array[InputEvent] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event.duplicate() as InputEvent)
		store[action] = events


## The events `project.godot` ships for `action` (never the live, possibly rebound, ones).
## Read from ProjectSettings, falling back to the boot-time snapshot.
static func default_events(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	var raw: Variant = ProjectSettings.get_setting("input/" + String(action), null)
	if raw is Dictionary:
		var events: Variant = (raw as Dictionary).get("events")
		if events is Array:
			for entry: Variant in events as Array:
				if entry is InputEvent:
					out.append((entry as InputEvent).duplicate() as InputEvent)
	if not out.is_empty():
		return out
	var stored: Variant = UiRuntime.get_shared().default_bindings.get(action)
	if stored is Array:
		for entry: Variant in stored as Array:
			if entry is InputEvent:
				out.append((entry as InputEvent).duplicate() as InputEvent)
	return out


## Puts one action's InputMap events back to the project default. No-op for an action the
## project file does not define (nothing to fall back to).
static func restore_default_binding(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	var defaults := default_events(action)
	if defaults.is_empty():
		return
	InputMap.action_erase_events(action)
	for event: InputEvent in defaults:
		InputMap.action_add_event(action, event)
