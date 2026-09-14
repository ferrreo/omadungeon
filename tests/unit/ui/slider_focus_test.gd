## A focused audio slider has to look different from an unfocused one, on every theme.
##
## The owner's report was "there is no highlight effect when the sliders for audio have focus
## via the controller", and it was literally true: `UiTheme` handed `grabber_area_highlight` -
## the one stylebox `HSlider` swaps when it takes focus, since the class has no `focus`
## stylebox at all - the same object as `grabber_area`. Focus changed nothing that got drawn.
##
## So the assertions here are about what is drawn, not about a flag: the styleboxes and icons
## the engine would actually pick for a focused slider are compared against the ones it picks
## for an idle one, and the difference has to clear a floor a player can see. Both a dark
## fixture and a light one, because a "brighter" cue is a *darker* cue on a light theme and a
## treatment that only works one way round is half a fix.
class_name SliderFocusTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
## Every shipped fixture, dark and light. The report is about the Audio page, which looks the
## same on all of them.
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
## How far apart the focused and the idle fill have to be before the cue counts as visible.
## `UiTheme.color_distance` is 0 for the identical styleboxes this replaces, and a shade step
## of one hue lands around 0.1; this is above that and below a hue change.
const MIN_FILL_DISTANCE := 0.2


func after_test() -> void:
	UiTheme.rebuild(Desktop.palette)


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


## The fill the engine draws over the filled half of the track, for each state. `Slider` picks
## `grabber_area_highlight` while `mouse_inside or has_focus()` and `grabber_area` otherwise.
func _track_fills() -> Array[StyleBoxFlat]:
	var theme := UiTheme.theme()
	var idle := theme.get_stylebox(&"grabber_area", &"HSlider") as StyleBoxFlat
	var focused := theme.get_stylebox(&"grabber_area_highlight", &"HSlider") as StyleBoxFlat
	assert_object(idle).is_not_null()
	assert_object(focused).is_not_null()
	return [idle, focused]


func test_the_focused_track_fill_is_not_the_idle_one_on_any_theme() -> void:
	for name: String in THEMES:
		UiTheme.rebuild(_palette(name))
		var fills := _track_fills()
		(
			assert_bool(fills[0] == fills[1])
			. override_failure_message(
				"%s: the focused slider is handed the same stylebox as the idle one" % name
			)
			. is_false()
		)
		(
			assert_float(UiTheme.color_distance(fills[0].bg_color, fills[1].bg_color))
			. override_failure_message(
				(
					"%s: focused fill %s is not far enough from idle fill %s to be seen"
					% [name, fills[1].bg_color, fills[0].bg_color]
				)
			)
			. is_greater(MIN_FILL_DISTANCE)
		)
		# ... and it carries the accent edge every other focused control in the UI carries.
		(
			assert_int(fills[1].border_width_left)
			. override_failure_message("%s: the focused slider fill has no edge" % name)
			. is_greater(0)
		)
		assert_int(fills[0].border_width_left).is_equal(0)


func test_the_focused_grabber_is_not_the_idle_one_on_any_theme() -> void:
	for name: String in THEMES:
		UiTheme.rebuild(_palette(name))
		var theme := UiTheme.theme()
		var idle := theme.get_icon(&"grabber", &"HSlider")
		var focused := theme.get_icon(&"grabber_highlight", &"HSlider")
		assert_object(idle).is_not_null()
		assert_object(focused).is_not_null()
		# Wider, and ringed. Colour alone will not do it: `text_bright` is `text` on five of
		# the six fixtures, so the knob used to be drawn identically whether the controller
		# was on the slider or not.
		(
			assert_int(focused.get_width())
			. override_failure_message("%s: the focused grabber is the idle grabber" % name)
			. is_greater(idle.get_width())
		)
		assert_int(focused.get_height()).is_equal(idle.get_height())
		var ring := focused.get_image().get_pixel(0, 0)
		var core := focused.get_image().get_pixel(3, 5)
		(
			assert_float(UiTheme.color_distance(ring, core))
			. override_failure_message("%s: the focused grabber has no ring" % name)
			. is_greater(0.0)
		)


## The slab is the cue a player sees from across the room; the shade inside a 60-pixel track
## is not. It has to exist as a theme entry, differ from the idle one, and cost no layout.
func test_the_focus_slab_is_a_real_theme_entry_that_costs_no_layout() -> void:
	for name: String in THEMES:
		UiTheme.rebuild(_palette(name))
		var theme := UiTheme.theme()
		(
			assert_bool(theme.is_type_variation(SliderRow.FOCUS_VARIATION, &"PanelContainer"))
			. override_failure_message("%s: there is no focused-slider slab in the theme" % name)
			. is_true()
		)
		var idle := theme.get_stylebox(&"panel", SliderRow.IDLE_VARIATION)
		var focused := theme.get_stylebox(&"panel", SliderRow.FOCUS_VARIATION) as StyleBoxFlat
		assert_object(focused).is_not_null()
		(
			assert_float(focused.bg_color.a)
			. override_failure_message("%s: the focus slab is invisible" % name)
			. is_greater(0.0)
		)
		assert_int(focused.border_width_left).is_greater(0)
		# Same content margins both ways, so the row does not jump when focus lands on it.
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			assert_float(focused.get_margin(side)).is_equal(idle.get_margin(side))


## The whole cue end to end, on the real Audio rows: the pad walks onto Master and the row it
## is on is the only one wearing the slab.
func test_focusing_an_audio_slider_lights_that_row_and_no_other() -> void:
	for name: String in ["tokyo-night", "catppuccin-latte"]:
		UiTheme.rebuild(_palette(name))
		var panel: SettingsPanel = auto_free(
			(load("res://src/ui/settings_panel.tscn") as PackedScene).instantiate()
		)
		add_child(panel)
		await await_idle_frame()
		var master := _row_for(panel, "master_volume")
		var music := _row_for(panel, "music_volume")
		(
			assert_bool(master.is_focus_shown())
			. override_failure_message("%s: an unfocused slider is already lit" % name)
			. is_false()
		)
		master.slider.grab_focus()
		await await_idle_frame()
		(
			assert_bool(master.is_focus_shown())
			. override_failure_message("%s: the focused audio slider shows no highlight" % name)
			. is_true()
		)
		assert_bool(music.is_focus_shown()).is_false()
		# The slab it puts on is the theme's, not a colour this widget invented.
		var drawn := master.get_theme_stylebox(&"panel") as StyleBoxFlat
		assert_object(drawn).is_not_null()
		assert_that(drawn.bg_color).is_equal(UiTheme.color(&"select"))
		assert_that(drawn.border_color).is_equal(UiTheme.color(&"accent"))
		master.slider.release_focus()
		await await_idle_frame()
		assert_bool(master.is_focus_shown()).is_false()
		remove_child(panel)


## The `SliderRow` the panel drew for `key`, found through the slider it registered.
func _row_for(panel: SettingsPanel, key: String) -> SliderRow:
	var slider := panel._controls.get(key) as HSlider
	assert_object(slider).is_not_null()
	var row := slider.get_parent().get_parent() as SliderRow
	assert_object(row).is_not_null()
	return row
