## "Need little health bars on the enemies" — the owner, after playing the shipped build,
## where only elites and bosses had one.
##
## The bar is easy to add and easy to get wrong in three ways, so each one is measured here:
## it must not turn a pack into a wall of red gauges (an ordinary enemy shows one only once it
## is hurt, and puts it away again), it must not cover the thing it describes (it sits clear
## above the sprite, and above the windup ring drawn under it), and it has to be readable on a
## light theme as well as a dark one.
class_name EnemyHpBarTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "nord", "catppuccin-latte", "white"
]
const PHYSICS_HZ := 60.0
## An ordinary 16 px enemy and an elite, by id.
const MOOK := &"config_gremlin"
const ELITE := &"dotfile_golem"


func _style() -> EnemyHpBarStyle:
	return EnemyHpBarStyle.shared()


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _root() -> Node2D:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	return root


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## Steps the bar's own hide clock by hand, so the assertion is about the countdown and not
## about how many frames this machine managed while the test was waiting.
func _advance(bar: EnemyHpBar, seconds: float) -> void:
	var step := 1.0 / PHYSICS_HZ
	var left := seconds
	while left > 0.0:
		bar._process(minf(step, left))
		left -= step


# --- when it is on screen at all --------------------------------------------------------------


func test_an_untouched_enemy_carries_no_bar() -> void:
	var root := _root()
	var enemy := EnemyTestHelpers.spawn(MOOK, root, Vector2.ZERO)
	await _frames(2)
	(
		assert_bool(enemy.hp_bar.visible)
		. override_failure_message("a full-health mook is wearing a health bar")
		. is_false()
	)


func test_the_first_hit_reveals_the_bar_and_it_reads_the_health_that_is_left() -> void:
	var root := _root()
	var enemy := EnemyTestHelpers.spawn(MOOK, root, Vector2.ZERO)
	await _frames(2)
	var half := enemy.health.max_hp * 0.5
	EnemyTestHelpers.hit(enemy, half)
	assert_bool(enemy.hp_bar.visible).is_true()
	(
		assert_float(enemy.hp_bar.fraction)
		. override_failure_message(
			"the bar shows %.2f with half the enemy's health gone" % enemy.hp_bar.fraction
		)
		. is_equal_approx(0.5, 0.05)
	)


func test_a_hurt_enemy_puts_its_bar_away_again_and_a_new_hit_brings_it_back() -> void:
	var root := _root()
	var style := _style()
	var enemy := EnemyTestHelpers.spawn(MOOK, root, Vector2.ZERO)
	await _frames(2)
	EnemyTestHelpers.hit(enemy, 5.0)
	assert_bool(enemy.hp_bar.visible).is_true()
	_advance(enemy.hp_bar, style.hide_delay * 0.5)
	(
		assert_bool(enemy.hp_bar.visible)
		. override_failure_message("the bar vanished halfway through its own delay")
		. is_true()
	)
	_advance(enemy.hp_bar, style.hide_delay + style.fade_time)
	(
		assert_bool(enemy.hp_bar.visible)
		. override_failure_message(
			"a mook nobody has touched for %.1f s is still wearing a bar" % style.hide_delay
		)
		. is_false()
	)
	EnemyTestHelpers.hit(enemy, 5.0)
	assert_bool(enemy.hp_bar.visible).is_true()
	assert_float(enemy.hp_bar.hide_countdown()).is_greater(style.hide_delay)


func test_an_elite_wears_its_bar_from_the_first_frame_and_keeps_it() -> void:
	var root := _root()
	var elite := EnemyTestHelpers.spawn(ELITE, root, Vector2.ZERO)
	await _frames(2)
	assert_bool(elite.def.is_elite).is_true()
	(
		assert_bool(elite.hp_bar.visible)
		. override_failure_message("an elite has to be identifiable before it is hit")
		. is_true()
	)
	_advance(elite.hp_bar, _style().hide_delay * 3.0)
	assert_bool(elite.hp_bar.visible).is_true()
	assert_float(elite.hp_bar.modulate.a).is_equal_approx(1.0, 0.001)


func test_a_dead_enemy_drops_its_bar() -> void:
	var root := _root()
	var enemy := EnemyTestHelpers.spawn(ELITE, root, Vector2.ZERO)
	await _frames(2)
	EnemyTestHelpers.hit(enemy, 99999.0)
	assert_bool(enemy.hp_bar.visible).is_false()


# --- where it sits ---------------------------------------------------------------------------


func test_the_bar_clears_the_body_and_is_no_wider_than_the_enemy_it_belongs_to() -> void:
	var root := _root()
	var style := _style()
	for id: StringName in [MOOK, ELITE]:
		var enemy := EnemyTestHelpers.spawn(id, root, Vector2(0, 0))
		await _frames(2)
		var size := float(enemy.def.sprite_size)
		var sprite_top := EnemyHpBarStyle.SPRITE_FOOT_OFFSET - size
		var bar_bottom := enemy.hp_bar.position.y + enemy.hp_bar.height + style.border
		(
			assert_float(bar_bottom)
			. override_failure_message(
				(
					"%s's bar reaches down to %.1f, over a sprite whose top edge is %.1f"
					% [id, bar_bottom, sprite_top]
				)
			)
			. is_less_equal(sprite_top)
		)
		(
			assert_float(sprite_top - bar_bottom)
			. override_failure_message(
				"%s's bar floats %.1f px above its head" % [id, sprite_top - bar_bottom]
			)
			. is_less_equal(style.gap + 1.0)
		)
		# A gauge wider than the body stops reading as belonging to that body, and two of them
		# side by side in a pack overlap before the enemies do.
		(
			assert_float(enemy.hp_bar.width)
			. override_failure_message(
				"%s is %.0f px wide and its bar is %.0f" % [id, size, enemy.hp_bar.width]
			)
			. is_less_equal(size * 1.1)
		)
		(
			assert_float(enemy.hp_bar.height)
			. override_failure_message("%s's bar is %.0f px tall" % [id, enemy.hp_bar.height])
			. is_less_equal(3.0)
		)


## The windup ring is drawn under the body and the bar above the head, so a bar can never be
## mistaken for part of a telegraph or hide one.
func test_the_bar_never_reaches_into_the_telegraph_ring() -> void:
	var root := _root()
	var enemy := EnemyTestHelpers.spawn(MOOK, root, Vector2.ZERO)
	await _frames(2)
	var bar_bottom := enemy.hp_bar.position.y + enemy.hp_bar.height + _style().border
	(
		assert_float(bar_bottom)
		. override_failure_message("the bar hangs down into the telegraph's radius")
		. is_less_equal(-enemy.telegraph_radius())
	)


# --- readable on every theme -------------------------------------------------------------------


func test_the_bar_is_legible_on_every_theme() -> void:
	var style := _style()
	for theme: String in THEMES:
		var palette := _palette(theme)
		assert_object(palette).override_failure_message("no palette for %s" % theme).is_not_null()
		var fill := EnemyHpBarStyle.fill_for(palette, style)
		var track := EnemyHpBarStyle.track_for(palette, style)
		var rim := EnemyHpBarStyle.opaque_backing(palette, style)
		var fill_track := ThemePalette.contrast_ratio(fill, track)
		var fill_rim := ThemePalette.contrast_ratio(fill, rim)
		var track_rim := ThemePalette.contrast_ratio(track, rim)
		(
			assert_float(fill_track)
			. override_failure_message(
				"%s: the health left and the health gone are %.2f:1 apart" % [theme, fill_track]
			)
			. is_greater_equal(style.fill_contrast - 0.01)
		)
		(
			assert_float(fill_rim)
			. override_failure_message(
				"%s: the bar's fill is %.2f:1 against its own rim" % [theme, fill_rim]
			)
			. is_greater_equal(style.fill_contrast - 0.01)
		)
		(
			assert_float(track_rim)
			. override_failure_message(
				(
					"%s: the empty part of the bar is %.2f:1 against the rim around it"
					% [theme, track_rim]
				)
			)
			. is_greater_equal(style.track_contrast - 0.01)
		)


## The bar floats over whatever the room is made of, and it does not get to choose which
## surface. One of its two elements — the bright fill or the dark rim — has to separate it
## from every one of them; which one does the work flips between a dark theme and a light one,
## which is exactly why a bar is drawn as an outline around a fill.
func test_the_bar_separates_itself_from_every_surface_of_every_theme() -> void:
	var style := _style()
	for theme: String in THEMES:
		var palette := _palette(theme)
		for role: String in ThemePalette.ENV_ROLES:
			var surface := palette.get_color(StringName(role))
			var separation := EnemyHpBarStyle.world_separation(palette, style, surface)
			(
				assert_float(separation)
				. override_failure_message(
					(
						"%s: neither the bar's fill nor its rim clears the %s it floats over (%.2f:1)"
						% [theme, role, separation]
					)
				)
				. is_greater_equal(style.world_contrast)
			)


## Round three of this project bought readability by flattening six themes into one look. The
## bar takes its colour from the theme's own `danger`, so two themes must not come out the same.
func test_each_theme_keeps_its_own_bar_colour() -> void:
	var style := _style()
	var seen: Array[Color] = []
	for theme: String in THEMES:
		var fill := EnemyHpBarStyle.fill_for(_palette(theme), style)
		for other: Color in seen:
			(
				assert_bool(fill.is_equal_approx(other))
				. override_failure_message(
					"%s draws its health bar in another theme's colour" % theme
				)
				. is_false()
			)
		seen.append(fill)
	assert_int(seen.size()).is_equal(THEMES.size())


## `EnemyHpBarStyle.shared()` falls back to a fresh default when the resource is missing, which
## is the right behaviour for a stripped export and a silent one for a typo: every number in
## the shipped file happens to match the script defaults it would fall back to, so nothing else
## here could tell the difference between "the data file is being read" and "it is not".
func test_the_shipped_style_file_is_the_one_the_bar_reads() -> void:
	(
		assert_bool(ResourceLoader.exists(EnemyHpBarStyle.PATH))
		. override_failure_message("%s is missing" % EnemyHpBarStyle.PATH)
		. is_true()
	)
	var on_disk := load(EnemyHpBarStyle.PATH) as EnemyHpBarStyle
	assert_object(on_disk).is_not_null()
	(
		assert_object(EnemyHpBarStyle.shared())
		. override_failure_message("the bars are drawn from code defaults, not from the .tres")
		. is_same(on_disk)
	)
