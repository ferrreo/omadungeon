## The Controls page is the only place the game teaches its controls, and three of its ten
## rows were unreadable: `GlyphIcon` centred the key label in a 16 px cap with no clipping and
## no widening, so "Spc" (18 px), "Tab" and "Esc" (17 px) spilled onto the dark background
## either side and were cut by the cap edge - DODGE read as a fragment plus "p", MAP read "AB",
## PAUSE read "SC".
##
## The suite asserts the thing a player sees: the ink of every key label lands inside the cap
## it is drawn on, on every row of the page, for keyboard bindings both short and long.
class_name KeycapLegibilityTest
extends GdUnitTestSuite


func before_test() -> void:
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD)


func after_test() -> void:
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD)


## The label's measured ink has to fit the cap's *face* - the width it reserves, less the
## transparent gutter and border at each end. Measured against the sprite rather than against
## `LABEL_PAD`, so shrinking the padding back below the border fails here too. False for
## "Spc"/"Tab"/"Esc" at a fixed 16 px cap, which is what the Controls page used to draw.
func _assert_label_inside_cap(action: StringName) -> void:
	var label := InputGlyphs.label_for(action)
	if label.is_empty():
		return
	var needed := InputGlyphs.label_size(label).x + float(InputGlyphs.CAP_EDGE * 2)
	(
		assert_float(InputGlyphs.glyph_width(action))
		. override_failure_message(
			(
				"%s label '%s' needs %.0f px of cap but only gets %.0f"
				% [action, label, needed, InputGlyphs.glyph_width(action)]
			)
		)
		. is_greater_equal(needed)
	)


func test_every_controls_page_row_keeps_its_label_on_the_cap() -> void:
	for entry: Dictionary in PauseMenu.CONTROL_ROWS:
		for action: StringName in entry["actions"] as Array:
			_assert_label_inside_cap(action)


## The three that were broken, named, so a regression says which key stopped reading.
func test_the_multi_character_defaults_widen_their_cap() -> void:
	for action: StringName in [&"dodge", &"map", &"pause"]:
		var label := InputGlyphs.label_for(action)
		(
			assert_bool(InputGlyphs.label_fits(label))
			. override_failure_message("%s label '%s' claims to fit a 16 px cap" % [action, label])
			. is_false()
		)
		(
			assert_float(InputGlyphs.glyph_width(action))
			. override_failure_message("%s did not widen its cap" % action)
			. is_greater(float(InputGlyphs.CELL))
		)


## A one-character binding must not grow: widening every cap would push the HUD around for
## nothing, and the sprite is designed for a single letter.
func test_single_letter_bindings_keep_the_plain_16px_cap() -> void:
	for action: StringName in [&"interact", &"potion", &"active_1", &"active_2"]:
		assert_float(InputGlyphs.glyph_width(action)).is_equal(float(InputGlyphs.CELL))


## Every label the key-name table can produce has to fit the cap it gets, not just the ones
## bound today: a player who rebinds Dodge to Backspace gets "Bks", and it must still read.
func test_every_short_name_the_table_produces_fits_its_cap() -> void:
	for label: String in ["Spc", "Esc", "Sft", "Ctl", "Alt", "Tab", "Ent", "Bks", "W", "F12"]:
		var needed := InputGlyphs.label_size(label).x + float(InputGlyphs.CAP_EDGE * 2)
		(
			assert_float(InputGlyphs.width_for_label(label))
			. override_failure_message("'%s' needs %.0f px" % [label, needed])
			. is_greater_equal(needed)
		)


## The widget itself, not just the measurement: a `GlyphIcon` reserves the width it needs, so
## the container it sits in lays out around a cap that is actually that wide.
func test_the_widget_reserves_the_width_it_draws() -> void:
	var wide: GlyphIcon = auto_free(GlyphIcon.new())
	wide.action = &"dodge"
	add_child(wide)
	assert_bool(wide.is_wide()).is_true()
	assert_float(wide.custom_minimum_size.x).is_equal(InputGlyphs.glyph_width(&"dodge"))
	var narrow: GlyphIcon = auto_free(GlyphIcon.new())
	narrow.action = &"interact"
	add_child(narrow)
	assert_bool(narrow.is_wide()).is_false()
	assert_float(narrow.custom_minimum_size.x).is_equal(float(InputGlyphs.CELL))


## Switching to a gamepad drops the labels entirely (the glyph is a button sprite), so the
## widened caps must go back to 16 px rather than leaving holes in the HUD.
func test_gamepad_glyphs_go_back_to_one_cell() -> void:
	var glyph: GlyphIcon = auto_free(GlyphIcon.new())
	glyph.action = &"dodge"
	add_child(glyph)
	assert_bool(glyph.is_wide()).is_true()
	InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
	EventBus.input_device_changed.emit(int(InputGlyphs.Device.GAMEPAD))
	await get_tree().process_frame
	assert_bool(glyph.is_wide()).is_false()
	assert_float(glyph.custom_minimum_size.x).is_equal(float(InputGlyphs.CELL))


## The HUD's own ability slots carry the same glyph. A rebind to a wide key must leave it
## centred under the 22 px box instead of hanging off one side.
func test_ability_slot_centres_a_wide_cap_under_its_box() -> void:
	var slot: AbilitySlot = auto_free(AbilitySlot.new())
	add_child(slot)
	slot.set_action(&"dodge")
	var glyph := slot.get_child(0) as GlyphIcon
	assert_object(glyph).is_not_null()
	var centre := glyph.position.x + glyph.size.x * 0.5
	assert_float(centre).is_equal_approx(float(AbilitySlot.BOX) * 0.5, 1.0)
