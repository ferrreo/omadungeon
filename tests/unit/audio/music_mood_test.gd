## The per-track mood (docs §10.2): `MusicMood` reads the measured table deterministically,
## `MusicMoodLevers` turns a mood into a look, and that look reaches the screen through the
## dungeon's *lights* and through nothing else.
##
## Two owner rulings meet in this file and this round settled the argument between them. "I
## still see no difference when the song changes" is a floor: calm and loud have to be a quarter
## apart in how hard the fires burn and 30 degrees apart in what colour they burn. "The theme is
## the only thing that says what colour the dungeon is" is a ceiling, and it used to be a 15
## degree budget on a full-frame colour grade. There is no grade now - the third ruling,
## "TORCHES SHOULD CAST THE LIGHT, THERE SHOULD BE NO OTHER LIGHT OTHER THAN PARTICLE EFFECTS,
## TORCHES ETC", deleted it - so the budget is no longer spent at all: the music moves a theme's
## palette by exactly zero degrees, on every theme, under every track, and this file asserts that
## structurally as well as numerically so the grade cannot come back quietly.
class_name MusicMoodTest
extends GdUnitTestSuite

## Least ratio, loud over calm, of the light the dungeon's fires put on a surface
## (`MusicMoodState.luminance_factor`). It used to be measured on a theme's floor colour under
## the full-frame grade; the grade is gone and the fires are what is left, so it is measured on
## them. The number did not move: a quarter is still what a person notices.
const MIN_LUMINANCE_RATIO := 1.25
## Furthest any environment role may be turned from the theme's own hue by the music, in
## degrees. It is the owner's budget and it is a ceiling; what is measured against it is now
## exactly 0.0, because the music has no road to a surface at all.
const MAX_THEME_HUE_DRIFT_DEG := 15.0
## Least hue difference, calm versus loud, on a *light's* own colour. Much larger than the
## surface figure and deliberately so: a floor is the theme's and may only be tinted, a flame
## is fire and may change temperature. With the dungeon lit in pockets (docs 10) the colour of
## those pockets is the largest coloured thing on the screen, so it is where the mood speaks.
const MIN_LIGHT_HUE_DELTA_DEG := 30.0
## Least ratio, loud over calm, of the radius of a light's pool.
const MIN_POOL_RADIUS_RATIO := 1.4
## Every fixture theme; the hue guarantee holds on all of them.
const THEMES: Array[String] = ["tokyo-night", "catppuccin", "catppuccin-latte", "gruvbox", "nord"]
const ROLES: Array[StringName] = [&"floor", &"wall", &"wall_top", &"floor_alt"]


static func _deg(turns: float) -> float:
	return absf(turns) * 360.0


static func _hue_delta_deg(a: Color, b: Color) -> float:
	return _deg(MusicMoodState.hue_delta(a.h, b.h))


func _calm() -> MusicMood:
	var file := MusicMood.extreme_file(false)
	return MusicMood.for_file(file, file)


func _loud() -> MusicMood:
	var file := MusicMood.extreme_file(true)
	return MusicMood.for_file(file, file)


func _state(mood: MusicMood, light: bool = false) -> MusicMoodState:
	return MusicMoodLevers.shared().state_for(mood, light)


func test_the_table_is_measured_and_the_extremes_are_far_apart() -> void:
	var files := MusicMood.measured_files()
	(
		assert_int(files.size())
		. override_failure_message(
			"data/music/track_moods.json is empty; run tools/analyze-radio.py"
		)
		. is_greater_equal(2)
	)
	var calm := _calm()
	var loud := _loud()
	assert_bool(calm.measured).is_true()
	assert_bool(loud.measured).is_true()
	assert_float(calm.energy).is_equal_approx(0.0, 0.001)
	assert_float(loud.energy).is_equal_approx(1.0, 0.001)
	assert_str(calm.file).is_not_equal(loud.file)


func test_a_mood_is_deterministic_per_file() -> void:
	for file: String in MusicMood.measured_files():
		var a := MusicMood.for_file(file, "any title")
		var b := MusicMood.for_file(file, "another title")
		var da := a.to_dict()
		var db := b.to_dict()
		da.erase("title")
		db.erase("title")
		assert_dict(da).is_equal(db)
		assert_float(a.hue_seed).is_between(0.0, 1.0)


func test_an_unmeasured_track_gets_a_middling_hashed_mood_and_silence_is_neutral() -> void:
	var a := MusicMood.for_file("", "Arpeggio Run")
	var b := MusicMood.for_file("", "Arpeggio Run")
	var c := MusicMood.for_file("", "Drum Cave")
	assert_bool(a.measured).is_false()
	assert_float(a.energy).is_between(0.35, 0.65)
	assert_float(a.brightness).is_between(0.35, 0.65)
	assert_float(a.hue_seed).is_equal(b.hue_seed)
	assert_float(a.hue_seed).is_not_equal(c.hue_seed)
	assert_bool(MusicMood.silent().is_silent()).is_true()
	(
		assert_bool(MusicMoodLevers.shared().state_for(MusicMood.silent(), false).is_neutral())
		. is_true()
	)


## The neutral state is the identity on every colour, and the slider's zero is that state.
func test_neutral_is_the_identity_and_amount_zero_is_neutral() -> void:
	var neutral := MusicMoodState.neutral()
	for theme: String in THEMES:
		var pal := ReactivityFixtures.palette_for(theme)
		for role: StringName in ROLES:
			var c := pal.get_color(role)
			assert_bool(neutral.graded(c, 0.0).is_equal_approx(c)).is_true()
	var loud := _state(_loud())
	assert_bool(loud.is_neutral()).is_false()
	assert_bool(loud.scaled(0.0).is_neutral()).is_true()
	assert_bool(loud.scaled(1.0).to_dict() == loud.to_dict()).is_true()


## The whole point: calm and loud in the same room are visibly different - in how hard the
## fires burn, and in what colour they burn. Both are properties of a light, which is where the
## whole of the mood now lives.
func test_calm_and_loud_differ_in_the_light_they_put_in_the_room() -> void:
	var calm := _state(_calm())
	var loud := _state(_loud())
	var ratio := loud.luminance_factor() / maxf(calm.luminance_factor(), 0.0001)
	(
		assert_float(ratio)
		. override_failure_message(
			(
				(
					"loud over calm light is x%.3f - not enough of a difference to see between two "
					+ "tracks"
				)
				% ratio
			)
		)
		. is_greater_equal(MIN_LUMINANCE_RATIO)
	)
	var pal := ReactivityFixtures.palette_for("tokyo-night")
	var light := DungeonLight.resolve().light_color(pal.get_color(&"heat"))
	var hue := _hue_delta_deg(calm.light_color(light), loud.light_color(light))
	(
		assert_float(hue)
		. override_failure_message("calm and loud flames are %.1f degrees apart" % hue)
		. is_greater_equal(MIN_LIGHT_HUE_DELTA_DEG)
	)
	print(
		(
			"tokyo-night: calm light x%.3f hue %.1f, loud light x%.3f hue %.1f (x%.2f, %.1f deg)"
			% [
				calm.luminance_factor(),
				calm.light_color(light).h * 360.0,
				loud.luminance_factor(),
				loud.light_color(light).h * 360.0,
				ratio,
				hue
			]
		)
	)


## A light theme gets the same mood as a dark one, because it now has the same dark under it.
##
## It used to get its own, narrower band (`intensity_calm_light`/`_loud_light`) and its torch
## multiplier capped at 1, both because an additive pool had nowhere to land on a floor that was
## already near white. `LightingProfile.unlit_floor` made every theme's unlit floor near black,
## so there is no headroom problem left to special-case and the two are one code path.
func test_a_light_theme_gets_the_same_light_band_as_a_dark_one() -> void:
	for loud: bool in [false, true]:
		var mood := _loud() if loud else _calm()
		var dark := _state(mood, false)
		var light := _state(mood, true)
		(
			assert_bool(dark.to_dict() == light.to_dict())
			. override_failure_message(
				(
					(
						"a %s track resolves differently on a light theme (%s) than on a dark one "
						+ "(%s); there is no ambient wash left for a light theme to need protecting "
						+ "from"
					)
					% ["loud" if loud else "calm", light.to_dict(), dark.to_dict()]
				)
			)
			. is_true()
		)
	# ...and the loud end really does burn the fires past their authored level on both, which is
	# what the light-theme cap used to forbid.
	assert_float(_state(_loud(), true).torch).is_greater(1.0)


## Two tracks of the same energy still colour the room differently, by their hue seeds.
func test_two_mid_energy_tracks_with_different_seeds_pull_the_hue_differently() -> void:
	var a := MusicMood.new()
	a.energy = 0.5
	a.hue_seed = 0.0
	a.title = "a"
	var b := MusicMood.new()
	b.energy = 0.5
	b.hue_seed = 1.0
	b.title = "b"
	var pal := ReactivityFixtures.palette_for("tokyo-night")
	var flame := DungeonLight.resolve().light_color(pal.get_color(&"heat"))
	var ca := _state(a).light_color(flame)
	var cb := _state(b).light_color(flame)
	# Measured on the flame, because the flame is the only thing the music colours. Two steady
	# tracks light the same room in two different fires.
	assert_float(_hue_delta_deg(ca, cb)).is_greater_equal(12.0)
	assert_float(absf(_state(a).torch - _state(b).torch)).is_less(0.01)
	# And the two mechanisms never add: at either end of the energy the seed rotates nothing.
	var loud_seeded := _loud()
	loud_seeded.hue_seed = 0.0
	assert_float(_state(loud_seeded).hue_rotate).is_equal_approx(0.0, 0.0001)
	assert_float(_state(a).light_hue_pull).is_equal_approx(0.0, 0.0001)


## The theme survives *exactly*: the music moves no environment role of any fixture theme by any
## amount, under any measured track. Not "within the budget" - by zero.
##
## The budget (`MAX_THEME_HUE_DRIFT_DEG`, the owner's 15 degrees) used to be spent by a
## full-frame colour grade, and the last round measured 9.4 degrees of it across the fixtures
## including the owner's green otter theme. The grade is gone, so the palette reaches the screen
## as the palette authored it and the whole budget is unspent.
##
## Measured *and* structural, because "we deleted it" is not a thing a number can assert on its
## own. The three structural checks are the ways the grade could come back: a method on the state
## that grades a surface, the shader include in the palette swap or the surround, and the shader
## globals it published through.
##
## Proved by making it fail first: re-adding `#include "res://src/desktop/music_grade.gdshaderinc"`
## to `palette_swap.gdshader` fails the shader assertion naming the file, and putting a `grade()`
## back on `MusicMoodState` fails the method assertion.
func test_the_music_moves_no_surface_of_any_theme_by_any_amount() -> void:
	var worst := 0.0
	var worst_where := ""
	var readings := 0
	for theme: String in THEMES:
		var pal := ReactivityFixtures.palette_for(theme)
		for file: String in MusicMood.measured_files():
			var state := _state(MusicMood.for_file(file, file), pal.is_light)
			for role: StringName in ROLES:
				var c := pal.get_color(role)
				# What the dungeon draws this role at: the theme's colour under the dark, with
				# no music anywhere in the expression. That is the assertion.
				var drawn := _as_drawn(c)
				readings += 1
				if TileRamp.chroma(c) < TileRamp.ACCENT_MIN_CHROMA:
					continue
				var d := _hue_delta_deg(c, drawn)
				if d > worst:
					worst = d
					worst_where = "%s %s under %s" % [theme, role, file]
				# `state` is deliberately unused on a surface - that is the point of the test.
				assert_bool(state != null).is_true()
	(
		assert_float(worst)
		. override_failure_message("%s drifted %.1f degrees from the theme" % [worst_where, worst])
		. is_equal_approx(0.0, 0.0001)
	)
	# The three roads the grade could come back by.
	(
		assert_bool(MusicMoodState.neutral().has_method("grade"))
		. override_failure_message(
			(
				"MusicMoodState has a grade() again: a method that grades a *surface* is how a "
				+ "full-frame colour grade comes back, and the owner deleted that road"
			)
		)
		. is_false()
	)
	for shader: String in [
		"res://src/desktop/palette_swap.gdshader", "res://src/rooms/void_surround.gdshader"
	]:
		# Code lines only: both files still *talk* about the grade in their comments, which is
		# where the reasoning for its absence lives and is the last thing that should fail a test.
		for line: String in FileAccess.get_file_as_string(shader).split("\n"):
			var code := line.strip_edges()
			if code.begins_with("//"):
				continue
			(
				assert_bool(code.contains("music_grade") or code.contains("music_tint"))
				. override_failure_message(
					"%s reaches for the music grade again: %s" % [shader, code]
				)
				. is_false()
			)
	(
		assert_bool(ResourceLoader.exists("res://src/desktop/music_grade.gdshaderinc"))
		. override_failure_message("the music grade shader include is back")
		. is_false()
	)
	for global_name: String in ["shader_globals/music_tint", "shader_globals/music_tone"]:
		(
			assert_bool(ProjectSettings.has_setting(global_name))
			. override_failure_message("%s is declared again" % global_name)
			. is_false()
		)
	print("theme hue drift under every track: %.1f degrees over %d readings" % [worst, readings])


## What the dungeon actually draws a surface at: the theme's own colour mixed toward black by
## `LightingProfile.unlit_floor` where nothing lights it. No music term, by construction.
static func _as_drawn(c: Color) -> Color:
	var dark := LightingProfile.resolve().unlit_level()
	return Color(c.r * dark, c.g * dark, c.b * dark, c.a)


## Every lever is a straight line between calm and loud, so a crossfade between two moods
## cannot overshoot either: each field of a blend sits between its ends.
func test_a_blend_never_leaves_the_interval_between_its_ends() -> void:
	var calm := _state(_calm())
	var loud := _state(_loud())
	for i in 11:
		var t := float(i) / 10.0
		var mid := calm.blended(loud, t)
		assert_float(mid.torch).is_between(
			minf(calm.torch, loud.torch), maxf(calm.torch, loud.torch)
		)
		assert_float(mid.saturation).is_between(
			minf(calm.saturation, loud.saturation), maxf(calm.saturation, loud.saturation)
		)
		assert_float(mid.particles).is_between(
			minf(calm.particles, loud.particles), maxf(calm.particles, loud.particles)
		)
		assert_float(mid.flicker).is_between(
			minf(calm.flicker, loud.flicker), maxf(calm.flicker, loud.flicker)
		)
		assert_float(mid.radius).is_between(
			minf(calm.radius, loud.radius), maxf(calm.radius, loud.radius)
		)
		assert_float(mid.light_hue_pull).is_between(
			minf(calm.light_hue_pull, loud.light_hue_pull),
			maxf(calm.light_hue_pull, loud.light_hue_pull)
		)


## The words the banner says: the calmest track is brooding, the loudest fierce, and the
## loudest is never called brooding.
func test_the_mood_words_follow_the_energy() -> void:
	var levers := MusicMoodLevers.shared()
	assert_str(levers.energy_word(0.0)).is_equal("brooding")
	assert_str(levers.energy_word(0.5)).is_equal("steady")
	assert_str(levers.energy_word(1.0)).is_equal("fierce")
	assert_str(levers.brightness_word(0.5)).is_equal("")
	var calm_words := _calm().words_line()
	var loud_words := _loud().words_line()
	assert_str(calm_words).contains("brooding")
	assert_str(loud_words).contains("fierce")
	assert_str(loud_words).not_contains("brooding")
	# A tempo the table knows adds its pace word, in the levers' own vocabulary.
	var slow := MusicMood.new()
	slow.energy = 0.3
	slow.tempo = 80.0
	assert_array(slow.words()).contains(["quiet", "slow"])


## The live gameplay nudge is bounded to the documented tenth either way and is exactly one
## in silence.
func test_the_live_aggression_lever_is_a_tenth_either_way() -> void:
	var levers := MusicLevers.shared()
	assert_float(levers.live_aggression(0.0)).is_equal_approx(0.9, 0.0001)
	assert_float(levers.live_aggression(0.5)).is_equal_approx(1.0, 0.0001)
	assert_float(levers.live_aggression(1.0)).is_equal_approx(1.1, 0.0001)


## A crossfading hue target never cuts through green: from the calm blue to the loud amber it
## goes by way of the reds, the same route the mapping walks.
func test_a_target_crossfade_goes_round_by_the_reds() -> void:
	var calm := _state(_calm())
	var loud := _state(_loud())
	for i in 11:
		var h := calm.blended(loud, float(i) / 10.0).hue_target
		(
			assert_bool(h > 0.2 and h < 0.5)
			. override_failure_message("target passed green at %.2f" % h)
			. is_false()
		)
	assert_float(MusicMoodState.target_route(0.6, 0.08)).is_greater(0.0)
	assert_float(MusicMoodState.target_route(0.1, 0.2)).is_equal_approx(0.1, 0.0001)


## The three numbers this suite judges a mood by, bounded by a literal.
##
## Every assertion above measures against `MIN_LUMINANCE_RATIO`, `MIN_LIGHT_HUE_DELTA_DEG` and
## `MAX_THEME_HUE_DRIFT_DEG`, so the bound and the thing bounded are the same line of this file.
## The mechanism has teeth - setting `torch_loud` to the calm value fails the light delta,
## setting `warm_hue` to `cool_hue` fails the flame hue delta, and putting the surface grade back
## fails the drift budget - but a weakened number would pass silently, and the drift budget in
## particular is the owner's, not a tuning choice: a theme that moves at all under a track is no
## longer the desktop's theme.
##
## Two floors and a ceiling. The deltas are floors: lowering one lets calm and loud converge
## until the mood stops being visible. The drift is a ceiling, and it is now measured at zero
## rather than spent, so raising it would be raising a limit nothing is pushing against - which
## is exactly when a limit gets raised by accident.
func test_the_mood_numbers_are_guarantees_not_variables() -> void:
	(
		assert_float(MIN_LUMINANCE_RATIO)
		. override_failure_message(
			(
				(
					"MIN_LUMINANCE_RATIO is %.3f: under 1.25 a loud track and a calm one do not "
					+ "burn the dungeon's fires a quarter apart and the mood stops reading"
				)
				% MIN_LUMINANCE_RATIO
			)
		)
		. is_greater_equal(1.25)
	)
	(
		assert_float(MAX_THEME_HUE_DRIFT_DEG)
		. override_failure_message(
			(
				(
					"MAX_THEME_HUE_DRIFT_DEG is %.1f: it is a ceiling, and the owner's budget "
					+ "is 15 degrees - past it the music is repainting the desktop's theme "
					+ "rather than leaving it alone"
				)
				% MAX_THEME_HUE_DRIFT_DEG
			)
		)
		. is_less_equal(15.0)
	)


## A flame turns further than the floor it lights. The previous round measured the mood on the
## *surfaces* - 22 to 27 degrees between the calmest and the loudest track - and the owner's
## answer was still "the music STILL doesn't seem to do anything". A surface's budget cannot be
## widened: past 15 degrees a theme stops being the desktop's theme, which is the owner's own
## rule. A light's can, and a light is the thing that changed: with a room lit in a few strong
## pockets rather than evenly, the colour of a pocket is the biggest coloured area on screen.
##
## Measured on the light colour the contract hands the lights (`MusicMoodState.light_color`),
## against the same theme's floor going through the same state, so the test says both halves at
## once: the flame moved a long way and the floor under it did not.
func test_a_flame_turns_further_than_the_floor_it_lights() -> void:
	var pal := ReactivityFixtures.palette_for("tokyo-night")
	var light := DungeonLight.resolve().light_color(pal.get_color(&"heat"))
	var calm := _state(_calm())
	var loud := _state(_loud())
	var calm_flame := calm.light_color(light)
	var loud_flame := loud.light_color(light)
	var flame := _hue_delta_deg(calm_flame, loud_flame)
	(
		assert_float(flame)
		. override_failure_message(
			(
				(
					"a torch burns %.1f degrees apart under the calmest and the loudest track; "
					+ "under %.0f the flame colour is not carrying the mood"
				)
				% [flame, MIN_LIGHT_HUE_DELTA_DEG]
			)
		)
		. is_greater_equal(MIN_LIGHT_HUE_DELTA_DEG)
	)
	# ...while the floor it falls on is not turned at all, because nothing turns it.
	var floor_c := pal.get_color(&"floor")
	assert_float(_hue_delta_deg(floor_c, _as_drawn(floor_c))).is_equal_approx(0.0, 0.0001)
	assert_float(flame).is_greater(MAX_THEME_HUE_DRIFT_DEG)
	# A light keeps its value: graded, tinted and turned, it is still a light and not a surface.
	assert_float(calm_flame.v).is_greater_equal(0.5)
	assert_float(loud_flame.v).is_greater_equal(0.5)
	print(
		(
			"tokyo-night torch: calm hue %.1f, loud hue %.1f (%.1f deg apart)"
			% [calm_flame.h * 360.0, loud_flame.h * 360.0, flame]
		)
	)


## The mood changes the *size* of a pool, not only its level. A shape is what a person notices
## without being told where to look, and once the room is lit in pockets the width of a pocket
## is a shape. Neutral is exactly 1, so silence and the amount slider at zero leave every light
## the radius it was authored with.
func test_the_mood_opens_and_closes_the_pools_of_light() -> void:
	var calm := _state(_calm())
	var loud := _state(_loud())
	var ratio := loud.radius / maxf(calm.radius, 0.001)
	(
		assert_float(ratio)
		. override_failure_message(
			(
				(
					"a pool is x%.2f wider under the loudest track than the calmest; under x%.2f"
					+ " the pools are the same size and the mood is a level change again"
				)
				% [ratio, MIN_POOL_RADIUS_RATIO]
			)
		)
		. is_greater_equal(MIN_POOL_RADIUS_RATIO)
	)
	assert_float(MusicMoodState.neutral().radius).is_equal_approx(1.0, 0.0001)
	assert_float(loud.scaled(0.0).radius).is_equal_approx(1.0, 0.0001)
	(
		assert_bool(MusicMoodLevers.shared().state_for(MusicMood.silent(), false).is_neutral())
		. is_true()
	)
	# The whole band sits either side of the authored radius rather than only above or below it.
	assert_float(calm.radius).is_less(1.0)
	assert_float(loud.radius).is_greater(1.0)


## The two numbers the "make it visible in play" round added, bounded by literals, for the
## reason the three above them are. Both are floors: lowering either lets the lights converge
## back on the theme's own fire at one width, which is the state the owner saw nothing in.
func test_the_light_mood_numbers_are_guarantees_not_variables() -> void:
	(
		assert_float(MIN_LIGHT_HUE_DELTA_DEG)
		. override_failure_message(
			(
				(
					"MIN_LIGHT_HUE_DELTA_DEG is %.1f: under 30 a torch under a brooding track "
					+ "and a torch under a fierce one are the same colour to a person playing"
				)
				% MIN_LIGHT_HUE_DELTA_DEG
			)
		)
		. is_greater_equal(30.0)
	)
	(
		assert_float(MIN_POOL_RADIUS_RATIO)
		. override_failure_message(
			(
				"MIN_POOL_RADIUS_RATIO is %.2f, under the x1.4 a pool is guaranteed to open by"
				% MIN_POOL_RADIUS_RATIO
			)
		)
		. is_greater_equal(1.4)
	)
