## "What hurt you?" used to be unanswerable. `Accessibility.status_role` collapsed all ten
## status kinds into `danger` and `heal`, so burn, frost, poison, shock, stun, slow and weaken
## were the same red chip; with the glyph setting off the chips carried no letters at all, so
## the HUD said how many things were on the player and never which; and the stack digit - the
## only cue that frost is one hit from freezing you - was drawn outside the 12 px chip and
## clipped by its own border.
##
## This suite asserts what a player can read off the strip, not how it is drawn.
class_name StatusLegibilityTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
## The pairs a player actually confuses: two harmful effects with different answers.
const CONFUSABLE: Array[Vector2i] = [
	Vector2i(StatusEffect.Kind.BURN, StatusEffect.Kind.FROST),
	Vector2i(StatusEffect.Kind.BURN, StatusEffect.Kind.POISON),
	Vector2i(StatusEffect.Kind.FROST, StatusEffect.Kind.SLOW),
	Vector2i(StatusEffect.Kind.SHOCK, StatusEffect.Kind.STUN),
	Vector2i(StatusEffect.Kind.POISON, StatusEffect.Kind.WEAKEN),
]

var _saved: Dictionary


func before_test() -> void:
	_saved = GameState.settings.duplicate(true)


func after_test() -> void:
	GameState.settings = _saved
	UiTheme.rebuild(Desktop.palette)


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _row() -> StatusRow:
	var row: StatusRow = auto_free(StatusRow.new())
	add_child(row)
	return row


## Ten kinds, ten roles. One blanket `danger` is what made a stun look like a burn.
func test_every_status_kind_has_its_own_palette_role() -> void:
	var roles: Array[String] = []
	for kind in StatusEffect.Kind.size():
		var role := String(Accessibility.status_role(kind))
		(
			assert_bool(roles.has(role))
			. override_failure_message(
				"%s reuses the '%s' role" % [Accessibility.status_mark(kind), role]
			)
			. is_false()
		)
		roles.append(role)
	assert_int(roles.size()).is_equal(StatusEffect.Kind.size())


## Every role has to be one the theme actually defines, or a swap leaves a chip magenta.
func test_every_status_role_exists_in_the_palette() -> void:
	for kind in StatusEffect.Kind.size():
		var role := String(Accessibility.status_role(kind))
		(
			assert_bool(ThemePalette.ROLES.has(role))
			. override_failure_message("'%s' is not a theme role" % role)
			. is_true()
		)


## The elemental kinds take the colour a player already expects them to be.
func test_the_elements_take_the_element_colours() -> void:
	assert_str(String(Accessibility.status_role(StatusEffect.Kind.BURN))).is_equal("heat")
	assert_str(String(Accessibility.status_role(StatusEffect.Kind.FROST))).is_equal("cold")
	assert_str(String(Accessibility.status_role(StatusEffect.Kind.EMPOWER))).is_equal("heal")


## Colour is the fast channel, so the confusable pairs must not land on the same chip colour
## on any shipped theme - light ones included, where contrast guards push colours around.
func test_confusable_pairs_draw_different_colours_on_every_theme() -> void:
	var row := _row()
	for theme: String in THEMES:
		UiTheme.rebuild(_palette(theme))
		var plate := UiTheme.plate_color(0.8)
		for pair: Vector2i in CONFUSABLE:
			var a := UiTheme.readable_on(
				UiTheme.color(Accessibility.status_role(pair.x)), plate, 3.5
			)
			var b := UiTheme.readable_on(
				UiTheme.color(Accessibility.status_role(pair.y)), plate, 3.5
			)
			(
				assert_bool(a.is_equal_approx(b))
				. override_failure_message(
					(
						"%s: %s and %s are the same chip colour"
						% [
							theme,
							Accessibility.status_mark(pair.x),
							Accessibility.status_mark(pair.y)
						]
					)
				)
				. is_false()
			)
	assert_int(row.shown_kinds().size()).is_equal(0)


## The tag is the channel that names the effect, so it is drawn on a default install and not
## only for someone who found the accessibility page. The chip reserves room for it either way.
func test_the_three_letter_tag_is_drawn_without_any_setting_turned_on() -> void:
	var row := _row()
	GameState.settings[Accessibility.SETTING_GLYPHS] = false
	var plain := row.chip_width()
	GameState.settings[Accessibility.SETTING_GLYPHS] = true
	(
		assert_float(plain)
		. override_failure_message("the chip reserves no room for its tag by default")
		. is_equal(row.chip_width())
	)
	assert_float(plain).is_greater_equal(float(StatusRow.CHIP) + row.tag_width())


## Frost at three stacks freezes you; the digit that says so used to be drawn past the chip's
## right edge and clipped by its own border.
func test_the_stack_digit_stays_inside_the_chip() -> void:
	var row := _row()
	var chip := Rect2(Vector2.ZERO, Vector2(StatusRow.CHIP, StatusRow.CHIP))
	for stacks: int in [2, 3, 9, 12]:
		var box := row.stack_rect(Vector2.ZERO, stacks)
		(
			assert_bool(chip.encloses(box))
			. override_failure_message(
				"the '%d' stack digit at %s escapes the chip" % [stacks, box]
			)
			. is_true()
		)


## The strip is bound to the player and lists what is on them, in a stable order, with the
## tags a player would read out.
func test_the_row_names_what_is_on_the_player() -> void:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	player.status.add(StatusEffect.Kind.POISON)
	player.status.add(StatusEffect.Kind.BURN, 2)
	var row := _row()
	row.bind(player)
	var tags := PackedStringArray()
	for kind: int in row.shown_kinds():
		tags.append(Accessibility.status_mark(kind))
	assert_array(tags).is_equal(["BRN", "PSN"])
