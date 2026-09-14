## A filled ability slot must always read as the stronger element. On light themes it used to
## be the other way round: both slots drew the same opaque plate, so the *empty* one was the
## brightest, emptiest box in the corner. These assertions pin the hierarchy on every fixture.
class_name AbilitySlotTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _slot() -> AbilitySlot:
	var slot: AbilitySlot = auto_free(AbilitySlot.new())
	add_child(slot)
	return slot


func after_test() -> void:
	UiTheme.rebuild(Desktop.palette)


func test_filled_slot_is_more_solid_than_an_empty_one() -> void:
	var slot := _slot()
	assert_float(slot.plate_alpha()).is_equal(AbilitySlot.PLATE_EMPTY)
	slot.set_ability(UiFakes.make_active("fireball", "Fireball", 6.0))
	assert_float(slot.plate_alpha()).is_equal(AbilitySlot.PLATE_FILLED)
	assert_float(AbilitySlot.PLATE_FILLED).is_greater(AbilitySlot.PLATE_EMPTY)


func test_border_hierarchy_holds_on_every_fixture() -> void:
	var empty := _slot()
	var filled := _slot()
	filled.set_ability(UiFakes.make_active("fireball", "Fireball", 6.0))
	for theme: String in THEMES:
		UiTheme.rebuild(_palette(theme))
		var plate := UiTheme.color(&"void")
		var empty_border := empty.border_color()
		var filled_border := filled.border_color()
		(
			assert_float(empty_border.a)
			. override_failure_message("%s: empty border is not faded" % theme)
			. is_less(filled_border.a)
		)
		var lit := ThemePalette.contrast_ratio(filled_border, plate)
		(
			assert_float(lit)
			. override_failure_message("%s: ready slot frame only %.2f on plate" % [theme, lit])
			. is_greater_equal(3.0)
		)
		# "Presence" is how loud a frame is against the plate once its alpha is taken into
		# account; the empty socket must always be the quieter of the two.
		var dim := ThemePalette.contrast_ratio(empty_border, plate) * empty_border.a
		(
			assert_float(dim)
			. override_failure_message("%s: empty slot frame %.2f, too loud" % [theme, dim])
			. is_less(lit * filled_border.a)
		)


func test_cooling_slot_drops_the_accent_frame() -> void:
	var slot := _slot()
	var ability := UiFakes.make_active("fireball", "Fireball", 6.0)
	slot.set_ability(ability)
	var ready_border := slot.border_color()
	ability.cooldown_left = 4.0
	slot.sample(0.016)
	assert_float(slot.cooldown_fraction()).is_greater(0.0)
	assert_that(slot.border_color()).is_not_equal(ready_border)


func test_slot_draws_on_every_fixture() -> void:
	var slot := _slot()
	slot.set_ability(UiFakes.make_active("fireball", "Fireball", 6.0))
	for theme: String in THEMES:
		UiTheme.rebuild(_palette(theme))
		slot.queue_redraw()
		await await_millis(20)
	assert_object(slot.ability).is_not_null()
