## No interface text may be clipped, and nothing may be drawn below the pixel fonts' native
## size, at the native internal resolution (480x270) — in a dark theme and a light one.
##
## Two deliberate escapes are honoured, because they are how the chest cards survive a long
## affix list: a Label that sets `text_overrun_behavior` or caps `max_lines_visible` has
## already said "trim me", and a Button with `clip_text` the same. Everything else must fit.
class_name TextFitTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
## The game's internal resolution; every screen is laid out against it (docs §1).
const NATIVE := Vector2(480, 270)
## Font sizes the theme is allowed to use. All three are whole-pixel sizes of the bitmap-ish
## fonts; anything smaller turns Silkscreen and Press Start 2P into mush.
const ALLOWED_SIZES: Array[int] = [UiTheme.SIZE_S, UiTheme.SIZE_M, UiTheme.SIZE_L]

const SCREENS: Array[Dictionary] = [
	{"name": "title", "path": "res://src/ui/title.tscn"},
	{"name": "class_select", "path": "res://src/ui/class_select.tscn"},
	{"name": "settings", "path": "res://src/ui/settings_panel.tscn"},
	{"name": "run_summary", "path": "res://src/ui/run_summary.tscn"},
	{"name": "stats", "path": "res://src/ui/stats_screen.tscn"},
	{"name": "pause", "path": "res://src/ui/pause_menu.tscn"},
	{"name": "chest", "path": "res://src/ui/chest_ui.tscn"},
	{"name": "hud", "path": "res://src/ui/hud.tscn"},
]


func after_test() -> void:
	UiTheme.rebuild(Desktop.palette)


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


## Builds one screen at the native resolution with fake content and settles its layout.
func _screen(spec: Dictionary) -> Control:
	var node: Node = auto_free((load(str(spec["path"])) as PackedScene).instantiate())
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	var host := node as Control
	if node is CanvasLayer:
		add_child(node)
		host = node.get_node("%Root") as Control
	else:
		add_child(node)
	host.size = NATIVE
	match str(spec["name"]):
		"class_select":
			(node as ClassSelect).select(1)
		"run_summary":
			(node as RunSummary).show_summary(UiFakes.summary_data(false))
		"stats":
			(node as StatsScreen).show_stats(UiFakes.profile_stats())
		"pause":
			var pause := node as PauseMenu
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			player.equipment.slots = {
				&"weapon": UiFakes.make_item(rng, ItemInstance.Rarity.EPIC, ItemBase.Slot.WEAPON),
				&"armor": UiFakes.make_item(rng, ItemInstance.Rarity.RARE, ItemBase.Slot.ARMOR),
			}
			pause.bind(player)
			pause.open()
		"chest":
			var chest := node as ChestUi
			chest.show_offers(
				ChestUi.Kind.ITEM,
				UiFakes.make_offers(ChestUi.Kind.ITEM),
				UiFakes.chest_context(player)
			)
		"hud":
			var hud := node as Hud
			hud.bind(player)
			hud.set_floor(3, "Sunken Library")
			hud.set_minimap(UiFakes.minimap_rooms(), UiFakes.minimap_edges())
			hud.show_prompt("Open the enormous chest", true)
	await settled(host)
	return host


## Waits until nothing in `root` is still moving, and returns when two consecutive frames lay
## out identically.
##
## It used to be `for _i in 3: await process_frame`, and a fixed frame count is exactly what
## docs/TESTING.md forbids for anything asynchronous - it reports a different result depending
## on machine load. Measured: `run_summary` had its panel at y 25.9 after three frames when this
## suite ran alone and at y 43.1 after three frames when it ran after the rest of
## `tests/unit/ui`, same host, same viewport, same content. Nothing about the screen differed;
## the layout had simply got further along in one run than the other, and a bounds check on top
## of that reads as a screen that fits in one run and overflows in the next.
static func settled(root: Control, deadline_ms := 3000) -> void:
	var previous := ""
	var until := Time.get_ticks_msec() + deadline_ms
	while Time.get_ticks_msec() < until:
		await root.get_tree().process_frame
		var signature := layout_signature(root)
		if signature == previous:
			return
		previous = signature
	push_error("text_fit: %s never settled in %d ms" % [root.name, deadline_ms])


## Every visible control's rect under `root`, as one string, so two frames can be compared.
static func layout_signature(node: Node, out: PackedStringArray = PackedStringArray()) -> String:
	for child: Node in node.get_children():
		var control := child as Control
		if control != null and control.visible:
			out.append(
				(
					"%s%s%s"
					% [
						control.name,
						control.get_global_rect(),
						(control as Label).text if control is Label else ""
					]
				)
			)
		layout_signature(child, out)
	return "|".join(out)


## Labels and Buttons whose text does not fit the box they were given, **or whose box does not
## fit the screen**.
##
## The second half is not decoration, and it is what this helper was missing. Asking a control
## only "were you given your own minimum size?" cannot see the overflow that matters, because a
## Container *honours* a minimum size: take the wrap flag off the pause menu's hint Label and
## triple the notice it carries, and the Label asks for 1300 px, the VBoxContainer grows to
## 1300 px, the PanelContainer grows with it - and every control in the chain reports that it
## got exactly what it asked for while the notice runs off both ends of a 480 px screen. That
## is the bug `test_the_settings_hint_line_fits_inside_the_pause_menu` exists to catch, and it
## passed with both mutations in place, measured. An autowrapping Label was worse off still: it
## was returned before any measurement at all, so nothing about the hint line was ever checked.
##
## So a control is now also failed when its rect leaves the native 480x270 screen. Controls
## inside a `ScrollContainer` are exempt from the vertical half of that - a list taller than the
## viewport is what scrolling is for - but not from the horizontal half when the container has
## horizontal scrolling switched off, because then a row wider than the container really is cut.
static func clipped(node: Node, out: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	_walk(node, _scroll_ancestor(node), _screen_rect(node), out)
	return out


## The 480x270 the subtree is laid out in, in the coordinates its controls report.
##
## Not `Rect2(Vector2.ZERO, NATIVE)`: a screen built here is anchored against the *test run's*
## root viewport, which is not 480x270 and is not the same height in every run, so the screen's
## own origin lands wherever those anchors put it. Measured: `run_summary` sits at y 31.7 when
## this suite runs alone and at y 48.8 when it runs after the rest of `tests/unit/ui`, with
## every control shifted by the same 17 px. Judging against a fixed origin therefore failed the
## footer buttons for the offset rather than for their size - a case that passes alone and
## fails in the tree, which is the worst shape a check can have. The frame is taken from the
## outermost `Control` above (or at) `node` instead, so what is measured is "does this text fit
## the screen it is on", wherever that screen has been put.
static func _screen_rect(node: Node) -> Rect2:
	var outermost := node as Control
	var walk := node
	while walk != null:
		var control := walk as Control
		if control != null:
			outermost = control
		walk = walk.get_parent()
	if outermost == null:
		return Rect2(Vector2.ZERO, NATIVE)
	return Rect2(outermost.global_position, NATIVE)


## Recurses through `node`, carrying the innermost `ScrollContainer` above it (or null) and the
## screen rect every control is judged against.
static func _walk(
	node: Node, scroll: ScrollContainer, screen: Rect2, out: PackedStringArray
) -> void:
	for child: Node in node.get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		if control is Label:
			_check_label(control as Label, out)
			_check_bounds(control, scroll, screen, control.text, out)
		elif control is Button:
			_check_button(control as Button, out)
			_check_bounds(control, scroll, screen, (control as Button).text, out)
		var inner := control as ScrollContainer
		_walk(child, inner if inner != null else scroll, screen, out)


## The innermost `ScrollContainer` at or above `node`, so a subtree measured from half way down
## the tree still knows it is inside a scrolled list.
static func _scroll_ancestor(node: Node) -> ScrollContainer:
	var walk := node
	while walk != null:
		var scroll := walk as ScrollContainer
		if scroll != null:
			return scroll
		walk = walk.get_parent()
	return null


## Fails a control whose rect leaves the 480x270 screen.
##
## Only text-bearing controls are measured, and only with text in them: an empty spacer or a
## decorative panel drawn past the edge is a layout choice, while a *word* past the edge is
## unreadable by definition. Inside a `ScrollContainer` the vertical bound is the container's
## job (that is what scrolling is), so only the horizontal one is applied there, and only when
## the container has said it will not scroll horizontally.
static func _check_bounds(
	control: Control, scroll: ScrollContainer, screen: Rect2, text: String, out: PackedStringArray
) -> void:
	if text.strip_edges().is_empty():
		return
	var rect := control.get_global_rect()
	if scroll == null:
		if rect.position.x < screen.position.x - 1.0 or rect.end.x > screen.end.x + 1.0:
			out.append(
				(
					"%s: %s runs off the %d px screen (x %.0f..%.0f) saying %s"
					% [
						control.name,
						control.get_class(),
						int(NATIVE.x),
						rect.position.x,
						rect.end.x,
						_q(text)
					]
				)
			)
		if rect.position.y < screen.position.y - 1.0 or rect.end.y > screen.end.y + 1.0:
			out.append(
				(
					"%s: %s runs off the %d px screen (y %.0f..%.0f) saying %s"
					% [
						control.name,
						control.get_class(),
						int(NATIVE.y),
						rect.position.y,
						rect.end.y,
						_q(text)
					]
				)
			)
		return
	if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		return
	var bound := scroll.get_global_rect()
	if rect.position.x < bound.position.x - 1.0 or rect.end.x > bound.end.x + 1.0:
		(
			out
			. append(
				(
					"%s: %s is cut by %s, which does not scroll sideways (x %.0f..%.0f in %.0f..%.0f)"
					% [
						control.name,
						control.get_class(),
						scroll.name,
						rect.position.x,
						rect.end.x,
						bound.position.x,
						bound.end.x,
					]
				)
			)
		)


static func _check_label(label: Label, out: PackedStringArray) -> void:
	if label.text.is_empty():
		return
	# The label asked to be trimmed; that is a layout decision, not a bug.
	if label.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
		return
	if label.max_lines_visible >= 0 or label.clip_text:
		return
	if label.get_visible_line_count() < label.get_line_count():
		out.append(
			(
				"%s: %d of %d lines shown"
				% [label.name, label.get_visible_line_count(), label.get_line_count()]
			)
		)
		return
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return
	var want := label.get_minimum_size()
	if label.size.x + 1.0 < want.x or label.size.y + 1.0 < want.y:
		out.append(
			"%s: %s given, %s needed for %s" % [label.name, label.size, want, _q(label.text)]
		)


static func _check_button(button: Button, out: PackedStringArray) -> void:
	if button.text.is_empty() or button.clip_text:
		return
	var want := button.get_minimum_size()
	if button.size.x + 1.0 < want.x or button.size.y + 1.0 < want.y:
		out.append(
			"%s: %s given, %s needed for %s" % [button.name, button.size, want, _q(button.text)]
		)


## A string in quotes for a failure message. GDScript's `%` has no `%r`, so the three places
## that used one were pushing "String formatting error: unsupported format character" and
## printing nothing useful on the day the assertion finally fired.
static func _q(text: String) -> String:
	return '"%s"' % text


## Controls drawing text smaller than the pixel fonts' native size.
static func too_small(
	node: Node, out: PackedStringArray = PackedStringArray()
) -> PackedStringArray:
	for child: Node in node.get_children():
		var control := child as Control
		if control != null and control.visible and (control is Label or control is Button):
			var size := control.get_theme_font_size(&"font_size")
			if size > 0 and size < UiTheme.SIZE_S:
				out.append("%s draws at %dpx" % [control.name, size])
		too_small(child, out)
	return out


func test_theme_font_sizes_are_all_native_pixel_sizes() -> void:
	var theme := UiTheme.theme()
	for entry: Array in [
		[&"font_size", &"Label"],
		[&"font_size", &"Heading"],
		[&"font_size", &"HeadingLarge"],
		[&"font_size", &"Title"],
		[&"font_size", &"Button"],
		[&"font_size", &"CheckBox"],
		[&"font_size", &"LineEdit"],
		[&"font_size", &"ProgressBar"],
		[&"normal_font_size", &"RichTextLabel"],
		[&"bold_font_size", &"RichTextLabel"],
	]:
		var size := theme.get_font_size(entry[0], entry[1])
		(
			assert_array(ALLOWED_SIZES)
			. override_failure_message(
				"%s/%s is %dpx, not a native pixel-font size" % [entry[1], entry[0], size]
			)
			. contains([size])
		)


func test_nothing_is_clipped_or_undersized_in_a_dark_theme() -> void:
	UiTheme.rebuild(_palette("tokyo-night"))
	for spec: Dictionary in SCREENS:
		var host := await _screen(spec)
		(
			assert_array(clipped(host))
			. override_failure_message(
				"dark theme, %s: clipped text %s" % [spec["name"], clipped(host)]
			)
			. is_empty()
		)
		(
			assert_array(too_small(host))
			. override_failure_message("dark theme, %s: %s" % [spec["name"], too_small(host)])
			. is_empty()
		)


func test_nothing_is_clipped_or_undersized_in_a_light_theme() -> void:
	UiTheme.rebuild(_palette("catppuccin-latte"))
	for spec: Dictionary in SCREENS:
		var host := await _screen(spec)
		(
			assert_array(clipped(host))
			. override_failure_message(
				"light theme, %s: clipped text %s" % [spec["name"], clipped(host)]
			)
			. is_empty()
		)
		(
			assert_array(too_small(host))
			. override_failure_message("light theme, %s: %s" % [spec["name"], too_small(host)])
			. is_empty()
		)


## Every line the Settings page can put on its hint line, measured where the page is narrowest.
##
## The pause menu embeds the same panel 96 px narrower than the standalone screen: the Keyboard
## column's notice - the line that explains why a controller cannot fill that column in - wants
## 447 px and the pause menu's hint line is 420 px wide, so the one screen where a player needs
## that explanation is the one screen it ran off both ends of. The list is built here from the
## page's own constants rather than typed out, so a prompt the page grows is a prompt this case
## measures.
static func settings_hints() -> PackedStringArray:
	var out := PackedStringArray([SettingsPanel.HINT_DEFAULT, UiHintLine.MANDATORY_NOTICE])
	out.append("Bindings reset to defaults")
	out.append("Rebind cancelled - nothing changed")
	(
		out
		. append(
			(
				"Unbound from %s, %s"
				% [
					SettingsPanel.action_label(InputBindings.ACTIONS[0]),
					SettingsPanel.action_label(InputBindings.ACTIONS[1]),
				]
			)
		)
	)
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	for action: StringName in InputBindings.ACTIONS:
		out.append(SettingsPanel.keyboard_column_notice(action))
		out.append(SettingsPanel.capture_prompt(action, false))
		out.append(SettingsPanel.capture_prompt(action, true))
		out.append(SettingsPanel.hold_prompt(action))
		out.append(SettingsPanel.protected_refusal(start, action))
	return out


func test_the_settings_hint_line_fits_inside_the_pause_menu() -> void:
	for theme_name: String in ["tokyo-night", "catppuccin-latte"]:
		UiTheme.rebuild(_palette(theme_name))
		var host := await _screen({"name": "pause", "path": "res://src/ui/pause_menu.tscn"})
		var pause := host as PauseMenu
		pause.set_tab(PauseMenu.Tab.SETTINGS)
		await get_tree().process_frame
		var panel := pause.settings_panel()
		var hint := panel.get_node("%Hint") as UiPrompt
		for text: String in settings_hints():
			hint.text = text
			for _i in 2:
				await get_tree().process_frame
			var problems := clipped(panel)
			(
				assert_array(problems)
				. override_failure_message(
					"%s: %s did not fit the pause menu: %s" % [theme_name, _q(text), problems]
				)
				. is_empty()
			)


## The hint keeps its height whatever it is saying, so a line that grows to two cannot shift the
## list a controller is walking underneath it.
func test_the_settings_hint_line_does_not_move_the_list_when_it_wraps() -> void:
	var host := await _screen({"name": "pause", "path": "res://src/ui/pause_menu.tscn"})
	var pause := host as PauseMenu
	pause.set_tab(PauseMenu.Tab.SETTINGS)
	await get_tree().process_frame
	var panel := pause.settings_panel()
	var hint := panel.get_node("%Hint") as UiPrompt
	var scroll := panel.get_node("%Scroll") as ScrollContainer
	hint.text = SettingsPanel.HINT_DEFAULT
	for _i in 2:
		await get_tree().process_frame
	var settled := scroll.size.y
	hint.text = SettingsPanel.keyboard_column_notice(&"secondary")
	for _i in 2:
		await get_tree().process_frame
	(
		assert_float(scroll.size.y)
		. override_failure_message("the settings list resized when the hint line wrapped")
		. is_equal_approx(settled, 0.5)
	)


func test_glyph_mode_does_not_overflow_a_chest_card() -> void:
	var saved: Variant = GameState.settings.get(Accessibility.SETTING_GLYPHS, false)
	GameState.settings[Accessibility.SETTING_GLYPHS] = true
	var host := await _screen({"name": "chest", "path": "res://src/ui/chest_ui.tscn"})
	var problems := clipped(host)
	GameState.settings[Accessibility.SETTING_GLYPHS] = saved
	assert_array(problems).override_failure_message("glyph mode clipped %s" % problems).is_empty()
