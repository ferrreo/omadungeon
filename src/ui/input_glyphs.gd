## Static lookup of input glyph textures for an action on the active device.
## Sheet: assets/sprites/ui/glyphs.png, 16x16 cells in one row (see Cell).
## Device tracking: any screen may call `observe(event)` from `_input`; the change is
## broadcast on `EventBus.input_device_changed`, which this class also listens to.
##
## The device policy, in one place (`observe`): a pad button or a stick pushed past
## `PAD_MOTION_THRESHOLD` makes the pad the active device; a key or a mouse *click* makes it
## the keyboard - those are deliberate. Mouse *motion* makes it the keyboard only once the pad
## has been quiet for `UiNavProfile.mouse_grace_seconds`. A pad player's desk is not still: a
## nudged mouse, a cursor warp when the compositor moves focus, the wobble of a laptop
## trackpad - every one of those is a motion event, and each one used to flip every prompt on
## screen to key-caps for a frame or two ("sometimes it shows A B instead of the pad
## symbols"). A player who has put the pad down and reached for the mouse still gets the
## keyboard prompts, a second later.
class_name InputGlyphs
extends RefCounted

enum Device { KEYBOARD, GAMEPAD }

enum Cell {
	A,
	B,
	X,
	Y,
	LB,
	RB,
	LT,
	RT,
	START,
	SELECT,
	LSTICK,
	RSTICK,
	DPAD,
	KEYCAP,
	MOUSE_LEFT,
	MOUSE_RIGHT,
}

const SHEET_PATH := "res://assets/sprites/ui/glyphs.png"
const CELL := 16
## Stick deflection past which a motion event counts as the pad being used. Above every
## deadzone the settings allow, so a resting stick's drift never claims the device.
const PAD_MOTION_THRESHOLD := 0.5
## `Cell` -> the `UiPrompt` cell token that draws it, for glyphs built from a live event.
const CELL_TOKENS: Dictionary = {
	Cell.A: "a",
	Cell.B: "b",
	Cell.X: "x",
	Cell.Y: "y",
	Cell.LB: "lb",
	Cell.RB: "rb",
	Cell.LT: "lt",
	Cell.RT: "rt",
	Cell.LSTICK: "lstick",
	Cell.RSTICK: "rstick",
	Cell.DPAD: "dpad",
}
## Horizontal padding either side of a key label inside its cap. The cap sprite is 2 px of
## margin, 1 px of border and then the face, so 4 px is what it takes for ink to land on the
## key rather than on its edge. A label wider than `CELL - 2 * LABEL_PAD` gets a widened cap
## instead of spilling past the 16 px sprite.
const LABEL_PAD := 4
## Width of the key-cap sprite's rounded end: 2 px margin, 1 px border, 2 px face. A widened
## cap keeps these two slices pixel for pixel and stretches only the flat middle, so "Tab"
## sits on a key rather than on a smear.
const CAP_END := 5
## Pixels at each end of the cap that are not its face - the transparent gutter plus the
## border. Ink inside this band is ink on the edge of the key, which is what "SC" and "AB"
## were. `LABEL_PAD` is this plus a pixel of breathing room.
const CAP_EDGE := 3

## Joypad button index -> short Xbox-layout name. `InputEvent.as_text()` spells these out in
## a full sentence ("Joypad Button 0 (Bottom Action, Sony Cross...)"), which no settings row
## is wide enough for, so the rebind list uses these instead.
const BUTTON_NAMES: Dictionary = {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_DPAD_UP: "D-Up",
	JOY_BUTTON_DPAD_DOWN: "D-Down",
	JOY_BUTTON_DPAD_LEFT: "D-Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Right",
}
## Joypad axis -> the pair of short names for its negative and positive halves.
const AXIS_NAMES: Dictionary = {
	JOY_AXIS_LEFT_X: ["LS Left", "LS Right"],
	JOY_AXIS_LEFT_Y: ["LS Up", "LS Down"],
	JOY_AXIS_RIGHT_X: ["RS Left", "RS Right"],
	JOY_AXIS_RIGHT_Y: ["RS Up", "RS Down"],
	JOY_AXIS_TRIGGER_LEFT: ["LT", "LT"],
	JOY_AXIS_TRIGGER_RIGHT: ["RT", "RT"],
}

## Pad buttons that are drawn as a named key-cap instead of as their own sprite. Start and
## Back are two small unlabelled pills on the sheet and at 480x270 they read as the same
## shape, so the Controls page - the only place the game teaches its controls - could not tell
## you which of them pauses. They borrow the key-cap treatment the rebind rows already use.
const LABELLED_BUTTONS: Array[int] = [JOY_BUTTON_START, JOY_BUTTON_BACK]

## Joypad button index -> cell (Xbox layout).
const BUTTON_CELLS: Dictionary = {
	JOY_BUTTON_A: Cell.A,
	JOY_BUTTON_B: Cell.B,
	JOY_BUTTON_X: Cell.X,
	JOY_BUTTON_Y: Cell.Y,
	JOY_BUTTON_LEFT_SHOULDER: Cell.LB,
	JOY_BUTTON_RIGHT_SHOULDER: Cell.RB,
	JOY_BUTTON_START: Cell.START,
	JOY_BUTTON_BACK: Cell.SELECT,
	JOY_BUTTON_LEFT_STICK: Cell.LSTICK,
	JOY_BUTTON_RIGHT_STICK: Cell.RSTICK,
	JOY_BUTTON_DPAD_UP: Cell.DPAD,
	JOY_BUTTON_DPAD_DOWN: Cell.DPAD,
	JOY_BUTTON_DPAD_LEFT: Cell.DPAD,
	JOY_BUTTON_DPAD_RIGHT: Cell.DPAD,
}


## Mean opaque colour of a sheet cell, cached. The glyph sheet is drawn un-modulated, so
## this - not any palette role - is the background a key label actually lands on.
static func cell_color(cell: int) -> Color:
	var r := UiRuntime.get_shared()
	_ensure()
	var key := "cellcolor:%d" % cell
	if r.glyph_cells.has(key):
		return r.glyph_cells[key]
	var out := _mean_color(cell)
	r.glyph_cells[key] = out
	return out


## Width the key label for `action` needs, in pixels: the plain 16 px cell when the label
## fits on the cap, and a widened cap when it does not.
##
## Three of the ten default bindings are multi-character ("Spc", "Tab", "Esc") and every one
## of them used to be centred in a 16 px cell with no clipping and no widening, so the first
## and last glyph landed on the dark background either side of the cap. On the Controls page -
## the only place the game teaches its controls - DODGE read as a fragment plus "p" and PAUSE
## read "SC".
static func glyph_width(action: StringName) -> float:
	return width_for_label(label_for(action))


## `glyph_width` for an already-resolved label.
static func width_for_label(label: String) -> float:
	if label.is_empty() or label_fits(label):
		return float(CELL)
	return maxf(float(CELL), ceilf(label_size(label).x) + float(LABEL_PAD * 2))


## Whether `label` fits inside the plain 16 px key-cap sprite.
static func label_fits(label: String) -> bool:
	if label.is_empty():
		return true
	return ceilf(label_size(label).x) <= float(CELL - LABEL_PAD * 2)


## Measured size of a key label in the body font at `UiTheme.SIZE_S`.
static func label_size(label: String) -> Vector2:
	return UiTheme.body_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_S)


## Draws the blank key-cap into `rect`, three-sliced so a cap wider than the 16 px sprite
## keeps its rounded ends and stretches only the flat middle.
static func draw_keycap(item: CanvasItem, rect: Rect2) -> void:
	if item == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_ensure()
	var sheet := UiRuntime.get_shared().glyph_sheet
	if sheet == null:
		return
	var src := Rect2(float(Cell.KEYCAP * CELL), 0.0, float(CELL), float(CELL))
	if rect.size.x <= float(CELL) + 0.5:
		item.draw_texture_rect_region(sheet, rect, src)
		return
	var end := float(CAP_END)
	var left_dst := Rect2(rect.position, Vector2(end, rect.size.y))
	var right_dst := Rect2(Vector2(rect.end.x - end, rect.position.y), Vector2(end, rect.size.y))
	var mid_dst := Rect2(
		Vector2(rect.position.x + end, rect.position.y),
		Vector2(rect.size.x - end * 2.0, rect.size.y)
	)
	var mid_src := Rect2(
		src.position + Vector2(end, 0.0), Vector2(src.size.x - end * 2.0, src.size.y)
	)
	item.draw_texture_rect_region(sheet, left_dst, Rect2(src.position, Vector2(end, src.size.y)))
	item.draw_texture_rect_region(sheet, mid_dst, mid_src)
	item.draw_texture_rect_region(
		sheet,
		right_dst,
		Rect2(src.position + Vector2(src.size.x - end, 0.0), Vector2(end, src.size.y))
	)


## Ink that stays readable on the key-cap sprite (WCAG 4.5:1), starting from `preferred`.
## Light themes used to draw a light `void` on a light cap at 1.5:1 because the guard was
## measured against `text_bright` instead of against the cap itself.
static func keycap_ink(preferred: Color) -> Color:
	return ThemePalette.ensure_contrast(preferred, cell_color(Cell.KEYCAP), 4.5)


static func _mean_color(cell: int) -> Color:
	var r := UiRuntime.get_shared()
	if r.glyph_sheet == null:
		return Color.WHITE
	var image := r.glyph_sheet.get_image()
	if image == null:
		return Color.WHITE
	if image.is_compressed():
		image.decompress()
	var total := Color(0, 0, 0, 0)
	var count := 0
	for y in mini(CELL, image.get_height()):
		for x in range(cell * CELL, mini((cell + 1) * CELL, image.get_width())):
			var px := image.get_pixel(x, y)
			if px.a < 0.5:
				continue
			total += Color(px.r, px.g, px.b, 0.0)
			count += 1
	if count == 0:
		return Color.WHITE
	return Color(total.r / count, total.g / count, total.b / count)


## Texture for a sheet cell.
static func cell_texture(cell: int) -> Texture2D:
	var r := UiRuntime.get_shared()
	_ensure()
	if r.glyph_cells.has(cell):
		return r.glyph_cells[cell]
	var atlas := AtlasTexture.new()
	atlas.atlas = r.glyph_sheet
	atlas.region = Rect2(cell * CELL, 0, CELL, CELL)
	r.glyph_cells[cell] = atlas
	return atlas


## Glyph texture for `action` on the current device (keycap for keyboard keys).
static func texture_for(action: StringName) -> Texture2D:
	return cell_texture(cell_for(action))


## `device` when it names one, else the active device.
static func device_or_current(device: int) -> Device:
	return (device as Device) if device >= 0 else current_device()


## Sheet cell for `action` on `device` (-1: the current device).
static func cell_for(action: StringName, device: int = -1) -> int:
	if not InputMap.has_action(action):
		return Cell.KEYCAP
	var pad := device_or_current(device) == Device.GAMEPAD
	for event: InputEvent in InputMap.action_get_events(action):
		if pad:
			if event is InputEventJoypadButton:
				var index := (event as InputEventJoypadButton).button_index
				if LABELLED_BUTTONS.has(int(index)):
					return Cell.KEYCAP
				return BUTTON_CELLS.get(index, Cell.A)
			if event is InputEventJoypadMotion:
				var axis := (event as InputEventJoypadMotion).axis
				if axis == JOY_AXIS_TRIGGER_LEFT:
					return Cell.LT
				if axis == JOY_AXIS_TRIGGER_RIGHT:
					return Cell.RT
				if axis == JOY_AXIS_RIGHT_X or axis == JOY_AXIS_RIGHT_Y:
					return Cell.RSTICK
				return Cell.LSTICK
		else:
			if event is InputEventMouseButton:
				var idx := (event as InputEventMouseButton).button_index
				return Cell.MOUSE_RIGHT if idx == MOUSE_BUTTON_RIGHT else Cell.MOUSE_LEFT
			if event is InputEventKey:
				return Cell.KEYCAP
	return Cell.KEYCAP


## Short label drawn over a blank keycap ("Q", "Spc", "Esc", "Start"). Empty for a glyph that
## carries its own sprite. `device` -1 is the current device.
static func label_for(action: StringName, device: int = -1) -> String:
	if not InputMap.has_action(action):
		return ""
	if device_or_current(device) == Device.GAMEPAD:
		for event: InputEvent in InputMap.action_get_events(action):
			var pad := event as InputEventJoypadButton
			if pad != null and LABELLED_BUTTONS.has(int(pad.button_index)):
				return str(BUTTON_NAMES.get(pad.button_index, ""))
		return ""
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			return key_label(event as InputEventKey)
		if event is InputEventMouseButton:
			return ""
	return "?"


## Compact human label for a key event.
static func key_label(event: InputEventKey) -> String:
	var code := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	var key := code
	if code != KEY_NONE and DisplayServer.get_name() != "headless":
		var mapped := DisplayServer.keyboard_get_keycode_from_physical(code)
		if mapped != KEY_NONE:
			key = mapped
	match key:
		KEY_SPACE:
			return "Spc"
		KEY_ESCAPE:
			return "Esc"
		KEY_SHIFT:
			return "Sft"
		KEY_CTRL:
			return "Ctl"
		KEY_ALT:
			return "Alt"
		KEY_TAB:
			return "Tab"
		KEY_ENTER:
			return "Ent"
		KEY_BACKSPACE:
			return "Bks"
		# The body font has no arrow glyphs, so the cursor keys borrow the ASCII shapes; "Lef"
		# and "Dow" were what the three-character cut made of them before.
		KEY_LEFT:
			return "<"
		KEY_RIGHT:
			return ">"
		KEY_UP:
			return "^"
		KEY_DOWN:
			return "v"
		KEY_PAGEUP:
			return "PgU"
		KEY_PAGEDOWN:
			return "PgD"
	var text := OS.get_keycode_string(key)
	if text.length() > 3:
		text = text.substr(0, 3)
	return text


## The actions in `actions` that draw a *different* glyph, in order. A row of four identical
## discs is one control drawn four times: on a pad every direction of Move resolves to the
## same left-stick sprite, so the Move row said nothing at all while looking like four
## separate buttons. A rebind that pulls the directions apart brings the separate glyphs back.
static func collapse_actions(actions: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	var seen: Dictionary = {}
	for raw: Variant in actions:
		var action := StringName(raw)
		var key := "%d|%s" % [cell_for(action), label_for(action)]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(action)
	return out


## Full human-readable name of the first binding of an action, for settings rows.
## Returns "-" when the action has nothing bound on that device, which is a real state: a
## rebind that takes an input away from another action leaves it exactly there.
static func binding_name(action: StringName, for_device: Device) -> String:
	if not InputMap.has_action(action):
		return "-"
	for event: InputEvent in InputMap.action_get_events(action):
		if for_device == Device.GAMEPAD:
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				return pad_name(event)
		elif event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code)
		elif event is InputEventMouseButton:
			return mouse_name((event as InputEventMouseButton).button_index)
	return "-"


## Short name for a gamepad button or stick/trigger direction ("A", "LB", "LS Left", "RT").
static func pad_name(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		var index := (event as InputEventJoypadButton).button_index
		return str(BUTTON_NAMES.get(index, "Btn %d" % int(index)))
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var pair: Variant = AXIS_NAMES.get(motion.axis)
		if pair is Array:
			return str((pair as Array)[1 if motion.axis_value >= 0.0 else 0])
		return "Axis %d" % int(motion.axis)
	return "-"


## Short name for a mouse button ("Mouse L", "Mouse R", "Mouse M", "Mouse 4").
static func mouse_name(index: MouseButton) -> String:
	match index:
		MOUSE_BUTTON_LEFT:
			return "Mouse L"
		MOUSE_BUTTON_RIGHT:
			return "Mouse R"
		MOUSE_BUTTON_MIDDLE:
			return "Mouse M"
	return "Mouse %d" % int(index)


## The `UiPrompt` token that draws `event` - "{#lb}" for the left shoulder, "{=Start}" for a
## button the sheet spells out on a key-cap - or its plain `pad_name` when nothing draws it.
static func event_token(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		var index := int((event as InputEventJoypadButton).button_index)
		if LABELLED_BUTTONS.has(index):
			return "{=%s}" % str(BUTTON_NAMES.get(index, ""))
		if BUTTON_CELLS.has(index):
			return "{#%s}" % str(CELL_TOKENS.get(int(BUTTON_CELLS[index]), "a"))
	elif event is InputEventJoypadMotion:
		var axis := (event as InputEventJoypadMotion).axis
		if axis == JOY_AXIS_TRIGGER_LEFT:
			return "{#lt}"
		if axis == JOY_AXIS_TRIGGER_RIGHT:
			return "{#rt}"
		return "{#rstick}" if axis == JOY_AXIS_RIGHT_X or axis == JOY_AXIS_RIGHT_Y else "{#lstick}"
	return pad_name(event)


## Updates the active device from a raw input event; emits on change. See the class comment
## for the policy. `now_msec` is the clock, injectable so the grace window can be tested.
static func observe(event: InputEvent, now_msec: int = -1) -> void:
	var r := UiRuntime.get_shared()
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	var next := current_device()
	var pad_event := false
	if event is InputEventJoypadButton:
		pad_event = true
	elif event is InputEventJoypadMotion:
		pad_event = absf((event as InputEventJoypadMotion).axis_value) > PAD_MOTION_THRESHOLD
	elif event is InputEventKey or event is InputEventMouseButton:
		next = Device.KEYBOARD
	elif event is InputEventMouseMotion:
		var moved := (event as InputEventMouseMotion).relative != Vector2.ZERO
		if moved and pad_quiet(now):
			next = Device.KEYBOARD
	if pad_event:
		# Only a pad event restarts the window: a mouse motion inside it must not, or a mouse
		# that keeps moving could never take the device back.
		next = Device.GAMEPAD
		r.last_pad_msec = now
	if next != current_device():
		set_device(next)
		EventBus.input_device_changed.emit(int(next))


## True once the pad has sent nothing for `UiNavProfile.mouse_grace_seconds` (or ever).
static func pad_quiet(now_msec: int) -> bool:
	var r := UiRuntime.get_shared()
	if r.last_pad_msec < 0:
		return true
	if r.pad_grace_msec < 0:
		r.pad_grace_msec = int(roundf(UiNavProfile.load_default().mouse_grace_seconds * 1000.0))
	return now_msec - r.last_pad_msec >= r.pad_grace_msec


## Active input device.
static func current_device() -> Device:
	return UiRuntime.get_shared().device as Device


static func set_device(next: Device) -> void:
	_ensure()
	UiRuntime.get_shared().device = next


static func _ensure() -> void:
	var r := UiRuntime.get_shared()
	if r.glyph_sheet != null:
		return
	r.glyph_sheet = UiTheme.load_texture(SHEET_PATH)
	if r.glyph_sheet == null:
		r.glyph_sheet = ImageTexture.create_from_image(
			Image.create(CELL * 16, CELL, false, Image.FORMAT_RGBA8)
		)
	if not r.glyphs_connected:
		r.glyphs_connected = true
		EventBus.input_device_changed.connect(_on_device_changed)


static func _on_device_changed(new_device: int) -> void:
	UiRuntime.get_shared().device = new_device
