## Prompts draw buttons; they do not type their names.
##
## Playing with a real controller: "sometimes it shows A B instead of the pad symbols". Two
## causes, both guarded here. The hint line on every board was a `Label` with the button's
## name typed into a sentence ("Stick/D-pad move   A pick   B skip") while the HUD beside it
## drew the sprite from the glyph sheet - so the game had two ways of saying "press this" and
## the typed one was on every board, every menu footer and every rebind prompt. And the
## "sometimes": the player's own `_input` flipped the active device to the keyboard on every
## mouse *motion* event and broadcast it on the signal the glyphs listen to, so a nudged mouse
## turned every prompt into key-caps for a frame.
##
## `UiPrompt` is now the one way to write a prompt: markup naming the *action*, drawn with the
## glyph for it on the live device. The scan at the bottom fails the gate when a string literal
## anywhere in `src/ui` (scripts and scenes) goes back to typing a button's name into a
## sentence. The same scan keeps otter-shell wording off the screen: the desktop the palette
## may come from is named "Otter" to the player and nothing else, by the owner's choice.
class_name PromptGlyphsTest
extends GdUnitTestSuite

const UI_DIR := "res://src/ui"
## Words that are a button's name when they appear inside a sentence. "A" is in the list too,
## but only away from the front of a sentence, where it is the article ("A curse comes with
## the prize", and "A dungeon skinned by your desktop" behind its bbcode colour tag). "Back" is
## not: it is a caption ("Back to defaults") far more often than a pad
## button, and the pad button is drawn as a key-cap by name anyway.
const BUTTON_WORDS: PackedStringArray = [
	"A",
	"B",
	"X",
	"Y",
	"LB",
	"RB",
	"LT",
	"RT",
	"Esc",
	"Enter",
	"PgUp",
	"PgDn",
	"D-pad",
	"Arrows",
	"WASD",
	"Start",
]
## The one otter word a player may read: the theme's display name. Anything else with "otter"
## in it ("otter-shell", "otter-wallpaper", an internal label) is source vocabulary.
const OTTER_NAME := "Otter"
## The screens whose hint line is the prompt, and the node that is it.
const SCREEN_HINTS: Array[Array] = [
	["res://src/ui/chest_ui.tscn", "%Hint"],
	["res://src/ui/pause_menu.tscn", "%Hint"],
	["res://src/ui/class_select.tscn", "%Hint"],
	["res://src/ui/settings_panel.tscn", "%Hint"],
	["res://src/ui/run_summary.tscn", "%MoreHint"],
]

var _device: int = 0


func before_test() -> void:
	_device = int(InputGlyphs.current_device())
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD)
	UiRuntime.get_shared().last_pad_msec = -1


func after_test() -> void:
	UiRuntime.get_shared().last_pad_msec = -1
	InputGlyphs.set_device(_device as InputGlyphs.Device)
	EventBus.input_device_changed.emit(_device)


# ------------------------------------------------------------------ the markup


func test_markup_splits_into_words_gaps_and_glyphs() -> void:
	var parts := UiPrompt.parse("{#dpad}{#lstick} move   {ui_accept} pick (+5g)")
	var kinds: PackedStringArray = []
	for part: Dictionary in parts:
		kinds.append(str(part["kind"]))
	assert_array(kinds).contains_exactly(["glyph", "glyph", "word", "gap", "glyph", "word", "word"])
	assert_str(str(parts[0]["cell"])).is_equal("dpad")
	assert_str(str(parts[4]["action"])).is_equal("ui_accept")
	assert_int(int(parts[4]["device"])).is_equal(-1)
	assert_str(str(parts[6]["text"])).is_equal("(+5g)")


func test_a_token_can_pin_its_device_or_carry_a_literal_label() -> void:
	var parts := UiPrompt.parse("{ui_cancel@pad} or {ui_accept@kb} or {=Start}")
	assert_int(int(parts[0]["device"])).is_equal(int(InputGlyphs.Device.GAMEPAD))
	assert_int(int(parts[2]["device"])).is_equal(int(InputGlyphs.Device.KEYBOARD))
	assert_str(str(parts[4]["literal"])).is_equal("Start")


## `plain()` is the prompt spelled out, which is what the older tests read and what the
## comparison against the typed strings this replaces is made with.
func test_plain_spells_the_binding_for_each_device() -> void:
	var markup := "{#dpad}{#lstick} move   {ui_accept} pick   {ui_cancel} skip"
	var pad := UiPrompt.render_plain(markup, InputGlyphs.Device.GAMEPAD)
	assert_str(pad).is_equal("D-pad/Stick move   A pick   B skip")
	var kb := UiPrompt.render_plain(
		"{ui_left}{ui_right} move   {ui_accept} pick", InputGlyphs.Device.KEYBOARD
	)
	assert_str(kb).is_equal("Left/Right move   Enter pick")
	# A pinned token spells the other device's button whatever device is live.
	var pinned := UiPrompt.render_plain(
		"{ui_cancel} or {ui_cancel@pad}", InputGlyphs.Device.KEYBOARD
	)
	assert_str(pinned).is_equal("Escape or B")


# ------------------------------------------------------------------ what is drawn


func test_a_prompt_draws_the_pad_buttons_rather_than_their_letters() -> void:
	_go(InputGlyphs.Device.GAMEPAD)
	var prompt := _prompt("{ui_accept} pick   {ui_cancel} skip")
	var glyphs := _glyphs(prompt)
	assert_int(glyphs.size()).is_equal(2)
	assert_int(glyphs[0].drawn_cell()).is_equal(InputGlyphs.Cell.A)
	assert_int(glyphs[1].drawn_cell()).is_equal(InputGlyphs.Cell.B)
	assert_str(glyphs[0].drawn_label()).is_empty()
	# And no word on the line is a button's name.
	for word: String in _words(prompt):
		assert_array(BUTTON_WORDS).override_failure_message("typed: %s" % word).not_contains([word])


func test_the_same_prompt_draws_key_caps_on_a_keyboard() -> void:
	_go(InputGlyphs.Device.KEYBOARD)
	var prompt := _prompt("{ui_accept} pick   {ui_cancel} skip")
	var glyphs := _glyphs(prompt)
	assert_int(glyphs.size()).is_equal(2)
	assert_int(glyphs[0].drawn_cell()).is_equal(InputGlyphs.Cell.KEYCAP)
	assert_str(glyphs[0].drawn_label()).is_equal("Ent")
	assert_str(glyphs[1].drawn_label()).is_equal("Esc")


func test_the_prompt_follows_the_device_while_it_is_up() -> void:
	_go(InputGlyphs.Device.KEYBOARD)
	var prompt := _prompt("{ui_accept} pick")
	assert_int(_glyphs(prompt)[0].drawn_cell()).is_equal(InputGlyphs.Cell.KEYCAP)
	_go(InputGlyphs.Device.GAMEPAD)
	await await_idle_frame()
	assert_int(_glyphs(prompt)[0].drawn_cell()).is_equal(InputGlyphs.Cell.A)


## Two directions on a keyboard are two keys; on a pad they are one cross, drawn once.
func test_back_to_back_glyphs_that_draw_the_same_thing_collapse() -> void:
	_go(InputGlyphs.Device.KEYBOARD)
	var keys := _prompt("{ui_left}{ui_right} move")
	assert_int(_glyphs(keys).size()).is_equal(2)
	assert_str(_glyphs(keys)[0].drawn_label()).is_equal("<")
	assert_str(_glyphs(keys)[1].drawn_label()).is_equal(">")
	_go(InputGlyphs.Device.GAMEPAD)
	var cross := _prompt("{ui_left}{ui_right} move")
	assert_int(_glyphs(cross).size()).is_equal(1)
	assert_int(_glyphs(cross)[0].drawn_cell()).is_equal(InputGlyphs.Cell.DPAD)


func test_a_literal_token_is_a_labelled_key_cap_and_an_event_has_a_token() -> void:
	var prompt := _prompt("{=Start} is Pause")
	var glyph := _glyphs(prompt)[0]
	assert_int(glyph.drawn_cell()).is_equal(InputGlyphs.Cell.KEYCAP)
	assert_str(glyph.drawn_label()).is_equal("Start")
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	assert_str(InputGlyphs.event_token(start)).is_equal("{=Start}")
	var lb := InputEventJoypadButton.new()
	lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	assert_str(InputGlyphs.event_token(lb)).is_equal("{#lb}")


func test_every_screen_hint_is_a_prompt() -> void:
	for spec: Array in SCREEN_HINTS:
		var screen: Node = auto_free((load(str(spec[0])) as PackedScene).instantiate())
		add_child(screen)
		var hint := screen.get_node(str(spec[1]))
		(
			assert_bool(hint is UiPrompt)
			. override_failure_message("%s %s is a %s" % [spec[0], spec[1], hint.get_class()])
			. is_true()
		)


## A scene that sets a prompt's `alignment` or `wrap` has to do it *after* its `script` line.
## A property written before the script is attached lands on a bare Container, which has no
## such property, and is dropped without a word - which is how every offer board's hint line
## came to draw left-aligned under a centred button row while the scene said `alignment = 1`.
func test_every_prompt_export_in_a_scene_comes_after_its_script() -> void:
	var offenders: PackedStringArray = []
	var dir := DirAccess.open(UI_DIR)
	for file: String in dir.get_files():
		if not file.ends_with(".tscn"):
			continue
		var lines := FileAccess.get_file_as_string(UI_DIR.path_join(file)).split("\n")
		var seen_script := false
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("[node "):
				seen_script = false
			elif line.begins_with("script = "):
				seen_script = true
			elif (
				(line.begins_with("alignment = ") or line.begins_with("wrap = "))
				and not seen_script
			):
				# `alignment` is also a BoxContainer property; only a scripted node is at risk,
				# and a UiPrompt is the only scripted Container that exports it.
				var node_line := i
				while node_line > 0 and not lines[node_line].begins_with("[node "):
					node_line -= 1
				if lines[node_line].contains('type="Container"'):
					offenders.append("%s:%d: %s" % [file, i + 1, line])
	(
		assert_array(offenders)
		. override_failure_message("prompt exports written before the script line: %s" % offenders)
		. is_empty()
	)


# ------------------------------------------------------------------ the device policy


## The "sometimes": a mouse motion event while the pad is in use does not flip the prompts.
func test_mouse_motion_does_not_take_the_device_from_a_pad_in_use() -> void:
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	InputGlyphs.observe(stick, 1000)
	assert_int(int(InputGlyphs.current_device())).is_equal(int(InputGlyphs.Device.GAMEPAD))
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(4, 1)
	InputGlyphs.observe(motion, 1500)
	(
		assert_int(int(InputGlyphs.current_device()))
		. override_failure_message("a nudged mouse flipped the prompts off the pad")
		. is_equal(int(InputGlyphs.Device.GAMEPAD))
	)
	# Every pad event restarts the window.
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	InputGlyphs.observe(button, 1900)
	InputGlyphs.observe(motion, 2500)
	assert_int(int(InputGlyphs.current_device())).is_equal(int(InputGlyphs.Device.GAMEPAD))
	# Once the pad has been quiet for the grace, motion means the player picked the mouse up.
	var grace := int(roundf(UiNavProfile.load_default().mouse_grace_seconds * 1000.0))
	InputGlyphs.observe(motion, 1900 + grace)
	assert_int(int(InputGlyphs.current_device())).is_equal(int(InputGlyphs.Device.KEYBOARD))


func test_a_click_or_a_key_takes_the_device_at_once() -> void:
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	InputGlyphs.observe(button, 1000)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	InputGlyphs.observe(click, 1001)
	assert_int(int(InputGlyphs.current_device())).is_equal(int(InputGlyphs.Device.KEYBOARD))
	InputGlyphs.observe(button, 1002)
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	InputGlyphs.observe(key, 1003)
	assert_int(int(InputGlyphs.current_device())).is_equal(int(InputGlyphs.Device.KEYBOARD))


func test_a_motion_event_that_moved_nothing_never_counts() -> void:
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	InputGlyphs.observe(button, 1000)
	var still := InputEventMouseMotion.new()
	InputGlyphs.observe(still, 999999)
	assert_int(int(InputGlyphs.current_device())).is_equal(int(InputGlyphs.Device.GAMEPAD))


# ------------------------------------------------------------------ the scan


func test_the_scan_knows_a_typed_prompt_from_a_sentence() -> void:
	var typed := typed_prompts(
		"""
	_hint.text = "Stick/D-pad move   A pick   B skip"
	label.text = "PgUp/PgDn tabs   Esc resume"
	notice = "tap B to cancel, hold B to bind B"
""",
		"sample.gd"
	)
	assert_int(typed.size()).is_equal(3)
	assert_str(typed[0]).contains("sample.gd:2:")
	var otter := typed_prompts(
		"""
	toast("Theme: Otter")
	label.text = "Skinned by otter-shell"
	label.text = "Otter Shell"
""",
		"sample.gd"
	)
	assert_int(otter.size()).is_equal(2)
	var clean := typed_prompts(
		"""
	return "A curse comes with the prize"
	out += "[color=#%s]A dungeon skinned by your desktop[/color]\\n\\n" % dim
	title.text = "Reuse seed - A seed fixes the rolls"
	# The old line said "A pick   B skip" and this comment is not a prompt
	_hint.text = "{ui_accept} pick   {ui_cancel} skip"  # was "A pick"
	const NAME := "B"
	title.text = "Starts a new run"
""",
		"sample.gd"
	)
	assert_array(clean).is_empty()


## No string literal in `src/ui` types a button's name into a sentence, or names otter-shell.
## The fix for a prompt is `UiPrompt` markup: `{ui_accept}` where the "A" was.
func test_no_prompt_in_src_ui_types_a_button_name() -> void:
	var found: PackedStringArray = []
	var dir := DirAccess.open(UI_DIR)
	assert_object(dir).is_not_null()
	for file: String in dir.get_files():
		if not (file.ends_with(".gd") or file.ends_with(".tscn")):
			continue
		var path := UI_DIR.path_join(file)
		found.append_array(typed_prompts(FileAccess.get_file_as_string(path), file))
	(
		assert_array(found)
		. override_failure_message(
			(
				"literals typing a button's name (write UiPrompt markup) or naming otter-shell:\n"
				+ "\n".join(found)
			)
		)
		. is_empty()
	)


## Every string literal in `source` that reads as a typed prompt, as "file:line: literal".
static func typed_prompts(source: String, file: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var literal := RegEx.create_from_string('"((?:[^"\\\\]|\\\\.)*)"')
	var lines := source.split("\n")
	for i in lines.size():
		var code := _strip_comment(lines[i])
		for found: RegExMatch in literal.search_all(code):
			var text := found.get_string(1)
			if reads_as_prompt(text) or names_otter_shell(text):
				out.append('%s:%d: "%s"' % [file, i + 1, text])
	return out


## Whether a literal has a button's name in it as a word of a sentence.
static func reads_as_prompt(text: String) -> bool:
	if not text.contains(" "):
		return false
	var words := RegEx.create_from_string("[A-Za-z][A-Za-z-]*")
	for found: RegExMatch in words.search_all(text):
		var word := found.get_string()
		if BUTTON_WORDS.has(word) and not (word == "A" and _starts_sentence(text, found)):
			return true
	return false


## Whether the word at `found` opens a sentence: nothing before it but a bbcode tag, a line
## break, punctuation that ends a clause, or the start of the literal.
static func _starts_sentence(text: String, found: RegExMatch) -> bool:
	var before := text.substr(0, found.get_start()).strip_edges(false, true)
	if before.is_empty() or before.ends_with("\\n"):
		return true
	return "].-:(".contains(before.right(1))


## Whether a literal says "otter" in any form other than the theme name `OTTER_NAME` on its
## own: "otter-shell", "otter-wallpaper", "Otter Shell" are all source vocabulary.
static func names_otter_shell(text: String) -> bool:
	var words := RegEx.create_from_string("[A-Za-z][A-Za-z-]*")
	for found: RegExMatch in words.search_all(text):
		var word := found.get_string()
		if word.to_lower().contains("otter") and word != OTTER_NAME:
			return true
	# "Otter Shell": the allowed word followed by the half that is not allowed.
	return text.contains(OTTER_NAME + " Shell")


## `line` up to its first `#` outside a string, so a comment quoting the old prompt is not
## reported as the prompt.
static func _strip_comment(line: String) -> String:
	var in_string := false
	var escaped := false
	for i in line.length():
		var c := line[i]
		if in_string:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == '"':
				in_string = false
		elif c == '"':
			in_string = true
		elif c == "#":
			return line.substr(0, i)
	return line


# ------------------------------------------------------------------ helpers


func _go(device: InputGlyphs.Device) -> void:
	InputGlyphs.set_device(device)
	EventBus.input_device_changed.emit(int(device))


func _prompt(markup: String) -> UiPrompt:
	var prompt: UiPrompt = auto_free(UiPrompt.new())
	add_child(prompt)
	prompt.text = markup
	return prompt


static func _glyphs(prompt: UiPrompt) -> Array[GlyphIcon]:
	var out: Array[GlyphIcon] = []
	for child: Node in prompt.get_children():
		if child is GlyphIcon:
			out.append(child as GlyphIcon)
	return out


static func _words(prompt: UiPrompt) -> PackedStringArray:
	var out: PackedStringArray = []
	for child: Node in prompt.get_children():
		if child is Label:
			out.append((child as Label).text)
	return out
