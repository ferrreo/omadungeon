## The generation half of pillar 3, pinned to the sentence in docs §5.1: "Same seed under a
## different Omarchy theme -> a different dungeon. That is the point of pillar 3, not a bug."
##
## It stopped being true once every geometry lever was hung off one derived scalar (mean
## saturation), which three of the four shipped dark fixtures agree on to within 0.09: they
## rounded into the same loop count and the same room spacing and generated a bit-identical
## floor plan, and the only reactivity test that looked at themes compared the *scalars*, not
## the floor. Two things are pinned here, and both are needed:
##
##  1. the shipped fixtures lay out differently from one seed, across every pair; and
##  2. the *biases* are what does it - repeated with the theme identity neutralised, so a
##     future re-flattening of the levers cannot hide behind `FloorGenerator.layout_seed`.
##
## Plus the property this work must not break: none of it may move difficulty, which docs §3.3
## caps at ±10% trap density.
class_name ThemeLayoutTest
extends GdUnitTestSuite

const THEMES: Array[String] = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
const SEED := 20250912
## Shared theme hash used to neutralise the salt, the rounding dither and the fill-template
## tie-break at once, leaving only the derived biases to tell the themes apart.
const NEUTRAL_HASH := 424242
## A floor whose tiles differ by less than this from another theme's is the same dungeon with
## a different coat of paint. Antialiasing aside, the regression measured 0.0027.
const MIN_TILE_DIFF := 0.05
## The same, for the levers-only run: no salt, no dither, no tie-break, biases alone.
const MIN_BIAS_TILE_DIFF := 0.02
## The four dark fixtures and the two light ones, as the room-size effect size is stated
## between the groups rather than between two hand-picked members of them.
const DARK_THEMES: Array[String] = ["tokyo-night", "gruvbox", "catppuccin", "nord"]
const LIGHT_THEMES: Array[String] = ["catppuccin-latte", "white"]
## Seeds averaged per theme for the room-size measurement, and how many standard errors of
## that mean the light-vs-dark gap has to clear. Measured over 30 other seed bases at this
## sample size: mean 5.1 standard errors, never below 3.4 - and at a third of the sample it
## still never fell below 1.2, which is the margin this number is buying.
const AREA_SEEDS := 24
const MIN_AREA_SIGMA := 2.0
## Seeds per theme for the docs §3.3 character table, and the margin its orderings must clear.
## Measured 2026-09-13 over 10 seeds x 9 floors with the widened levers: gruvbox lays 63 and
## white 66 corridor tiles per floor against 69 for the next lowest (nord) and 83-101 for the
## rest, and tokyo-night 101 against 83 for the next highest dark fixture (1.22), so 0.90
## leaves the tokyo-night gap most of its headroom.
const CHARACTER_SEEDS := 10
const CHARACTER_MARGIN := 0.90
## How many times the corridor tiles of the widest fixture exceed the blockiest one's.
## Measured 1.61 (tokyo-night 101 against gruvbox 63).
const CORRIDOR_SPREAD := 1.4
## Floors sampled per theme for the difficulty measurements.
const DIFFICULTY_SEEDS := 12
const DIFFICULTY_FLOORS := 5
## docs §3.3 caps the trap-density lever at ±10% (0.45..0.55), so two themes may differ by at
## most 0.55/0.45. The assertion used to read `< 1.3`, which is a number the docs do not state
## and which no shipped theme could ever reach: it is the derived band that is the design
## statement, so it is the derived band that is asserted. Measured 2026-09-12 across the six
## fixtures: 1.158, comfortably inside it.
const MAX_TRAP_RATIO := 0.55 / 0.45
## Enemy spawn points are not a theme lever at all - the room-size lever must not smuggle extra
## enemies into the extra floor space - so this one is tight on purpose.
const MAX_SPAWN_RATIO := 1.15


## Live inputs a player actually has: a track is playing, so the tempo lever is in the loop.
## The regression hid behind exactly this - the old suite built its params with tempo 0.
func _params(theme: String, floor_index: int) -> GenParams:
	return GenParams.build(
		ReactivityFixtures.profile_for(theme),
		floor_index,
		ReactivityFixtures.music(0.5, 128.0, "Public Code, Private Yacht"),
		null
	)


## The same inputs with every theme-identity tie-break forced to one value - and forced there
## *before* `GenParams.build` runs, not after.
##
## Stamping `theme_hash` onto a finished GenParams left a theme-identity tie-break inside the
## measurement that was supposed to have removed it: `build()` had already rounded
## `extra_loops` with the real theme's own dither, and `room_gap_extra()` rounds with it on
## every call, so catppuccin kept a loop count no bias of its own produced. The conclusion was
## right and the procedure did not establish it. Building from a profile copy that already
## carries the shared hash puts every rounding, every tie-break and the layout salt on one
## identity, which is the only way the biases are left holding the difference.
func _bias_only_params(theme: String, floor_index: int) -> GenParams:
	var profile := ReactivityFixtures.profile_for(theme)
	profile.theme_hash = NEUTRAL_HASH
	return GenParams.build(
		profile,
		floor_index,
		ReactivityFixtures.music(0.5, 128.0, "Public Code, Private Yacht"),
		null
	)


func _floors(floor_index: int, bias_only: bool) -> Dictionary:
	var out: Dictionary = {}
	for theme: String in THEMES:
		var params := (
			_bias_only_params(theme, floor_index) if bias_only else _params(theme, floor_index)
		)
		out[theme] = ReactivityFixtures.generate(params, SEED)
	return out


func _assert_all_pairs_differ(floors: Dictionary, floor_index: int, min_diff: float) -> void:
	for i in range(THEMES.size()):
		for j in range(i + 1, THEMES.size()):
			var a: String = THEMES[i]
			var b: String = THEMES[j]
			var da: FloorData = floors[a]
			var db: FloorData = floors[b]
			var diff := ReactivityFixtures.tile_difference(da, db)
			(
				assert_float(diff)
				. override_failure_message(
					(
						"floor %d is the same dungeon under %s and %s: %.2f%% of tiles differ"
						% [floor_index, a, b, diff * 100.0]
					)
				)
				. is_greater(min_diff)
			)
			(
				assert_str(ReactivityFixtures.floor_signature(da))
				. override_failure_message(
					"floor %d has the same signature under %s and %s" % [floor_index, a, b]
				)
				. is_not_equal(ReactivityFixtures.floor_signature(db))
			)


func test_every_shipped_theme_lays_out_a_different_floor_from_one_seed() -> void:
	# Every floor of a run, boss floors included. Sampling three of them was how the climax
	# floors came to ignore the theme entirely for a whole round: `GenParams.build` pinned
	# `extra_loops` to 1 on floors 3, 6 and 9, and nothing that looked at a floor ever looked
	# at one of those. Measured 2026-09-12 across the six fixtures: the closest pair on any
	# floor differs on 33% of its tiles.
	for floor_index: int in range(GenParams.LAST_FLOOR + 1):
		_assert_all_pairs_differ(_floors(floor_index, false), floor_index, MIN_TILE_DIFF)


func test_the_biases_alone_still_change_the_run_without_the_theme_salt() -> void:
	# The counter-property, stated at the size it is actually true at - which is a *run*, not
	# a floor, and which is why this reads differently from the guard above.
	#
	# The levers the theme moves are integers: a loop count and a room spacing. With the theme
	# identity neutralised the dither that rounds them is neutralised too, so two themes whose
	# derived scalars land inside one rounding step of each other round to the same pair of
	# integers and can produce the same floor plan - measured, gruvbox and nord do exactly that
	# at floor index 5, and under the derivation shipped a round ago gruvbox and catppuccin did
	# it at floor index 2. That is not a hole in the levers; it is the documented reason
	# `theme_hash` is folded into the layout seed at all (docs §3.3, "even for two themes whose derived scalars
	# happen to coincide"), and a test that claimed otherwise would be claiming something
	# false. Across the nine floors of a run the biases do separate every pair: worst pair
	# measured 2026-09-12 is 9.4% of tiles per floor, and no pair shares a floor *signature* -
	# the template, prop, trap and spawn choices - on any single floor either.
	# Since the floor archetype roll (docs 5.1 #1) one more draw is shared by every theme, so
	# a pair may now coincide on a single floor of the nine, signature and all - measured
	# 2026-09-13, gruvbox and nord at floor index 3. One floor is the coincidence the salt
	# exists for; two would mean the biases have stopped telling the themes apart.
	var floors: Dictionary = {}
	for floor_index: int in range(GenParams.LAST_FLOOR + 1):
		floors[floor_index] = _floors(floor_index, true)
	for i in range(THEMES.size()):
		for j in range(i + 1, THEMES.size()):
			var a: String = THEMES[i]
			var b: String = THEMES[j]
			var total := 0.0
			var same_signature := 0
			for floor_index: int in range(GenParams.LAST_FLOOR + 1):
				var per_floor: Dictionary = floors[floor_index]
				var da: FloorData = per_floor[a]
				var db: FloorData = per_floor[b]
				total += ReactivityFixtures.tile_difference(da, db)
				if ReactivityFixtures.floor_signature(da) == ReactivityFixtures.floor_signature(db):
					same_signature += 1
			(
				assert_int(same_signature)
				. override_failure_message(
					(
						"%s and %s fill identically on %d floors with no theme salt"
						% [a, b, same_signature]
					)
				)
				. is_less_equal(1)
			)
			var mean := total / float(GenParams.LAST_FLOOR + 1)
			(
				assert_float(mean)
				. override_failure_message(
					(
						(
							"%s and %s generate the same run from the biases alone: %.2f%% of tiles "
							+ "differ per floor"
						)
						% [a, b, mean * 100.0]
					)
				)
				. is_greater(MIN_BIAS_TILE_DIFF)
			)


func test_two_themes_that_agree_on_saturation_still_differ_in_the_geometry_levers() -> void:
	# Catppuccin and Nord derive the same mean saturation to two decimal places. That is what
	# collapsed them onto one floor plan, so the geometry levers may not be a function of it.
	var catppuccin := ReactivityFixtures.profile_for("catppuccin")
	var nord := ReactivityFixtures.profile_for("nord")
	assert_float(absf(catppuccin.saturation - nord.saturation)).is_less(0.02)
	(
		assert_float(absf(catppuccin.openness - nord.openness))
		. override_failure_message("openness collapsed back onto saturation")
		. is_greater(0.25)
	)
	(
		assert_float(absf(catppuccin.room_size_bias - nord.room_size_bias))
		. override_failure_message("room_size_bias no longer separates two equally vivid themes")
		. is_greater(0.05)
	)


func test_no_geometry_lever_is_a_function_of_saturation_alone() -> void:
	# Independence, stated as a property rather than as numbers: somewhere in the shipped set
	# two themes must rank one way on saturation and the other way on openness. A lever
	# derived from saturation (however scaled) can never do that.
	var disagreements := 0
	for i in range(THEMES.size()):
		for j in range(THEMES.size()):
			if i == j:
				continue
			var a := ReactivityFixtures.profile_for(THEMES[i])
			var b := ReactivityFixtures.profile_for(THEMES[j])
			if a.saturation < b.saturation and a.openness > b.openness:
				disagreements += 1
	(
		assert_int(disagreements)
		. override_failure_message(
			(
				"openness orders the shipped themes exactly as saturation does - it is the same "
				+ "lever wearing a second name, and the themes will flatten again"
			)
		)
		. is_greater(0)
	)


func test_the_dark_fixtures_no_longer_share_one_loop_and_spacing_bucket() -> void:
	# The two integers the layout actually rounds to. Three dark themes landing in one bucket
	# is the mechanism that made their floors identical - and it was floor 1 only that this
	# looked at, which is how a boss floor that pinned every theme to one loop count went
	# three rounds unnoticed. Every floor of the run is measured now.
	for floor_index: int in range(GenParams.LAST_FLOOR + 1):
		var buckets: Dictionary = {}
		for theme: String in ["tokyo-night", "gruvbox", "catppuccin", "nord"]:
			var p := _params(theme, floor_index)
			assert_int(p.extra_loops).is_between(1, 3)
			assert_int(p.room_gap_extra()).is_between(0, 5)
			buckets["%d:%d" % [p.extra_loops, p.room_gap_extra()]] = true
		(
			assert_int(buckets.size())
			. override_failure_message(
				(
					"floor %d: the four dark fixtures round into %d loop/spacing buckets (%s)"
					% [floor_index, buckets.size(), str(buckets.keys())]
				)
			)
			. is_greater(2)
		)


func test_a_boss_floor_is_still_tighter_than_the_floor_before_it() -> void:
	# What the boss-floor loop band is for. The theme now chooses the climax floor's loop count
	# too, and the property that choice may not cost is docs §5.1's "boss floor is linear-ish":
	# no theme may open a boss floor up as far as it opens an ordinary one.
	for theme: String in THEMES:
		var open_floor := _params(theme, 1)
		var boss := _params(theme, 2)
		assert_bool(boss.is_boss_floor).is_true()
		assert_bool(open_floor.is_boss_floor).is_false()
		(
			assert_int(boss.extra_loops)
			. override_failure_message(
				(
					"%s: boss floor carries %d loops against %d on floor 1"
					% [theme, boss.extra_loops, open_floor.extra_loops]
				)
			)
			. is_less_equal(maxi(open_floor.extra_loops, 1))
		)
		assert_int(boss.extra_loops).is_between(1, GenParams.BOSS_MAX_LOOPS)


func test_a_theme_never_swings_difficulty_beyond_the_documented_band() -> void:
	# Layout may change all it likes; the number of things that can kill you may not: the
	# documented trap-density band for traps, and no theme drift at all in enemy count.
	var traps: Dictionary = {}
	var spawns: Dictionary = {}
	for theme: String in THEMES:
		var trap_total := 0
		var spawn_total := 0
		for offset in range(DIFFICULTY_SEEDS):
			for floor_index in range(DIFFICULTY_FLOORS):
				var data := ReactivityFixtures.generate(
					_params(theme, floor_index), SEED + offset * 31
				)
				for room: FloorData.Room in data.rooms:
					trap_total += room.trap_positions.size()
					spawn_total += room.enemy_spawns.size()
		traps[theme] = trap_total
		spawns[theme] = spawn_total
	var trap_values := traps.values()
	var spawn_values := spawns.values()
	var trap_ratio := float(trap_values.max()) / float(trap_values.min())
	var spawn_ratio := float(spawn_values.max()) / float(spawn_values.min())
	(
		assert_float(trap_ratio)
		. override_failure_message(
			(
				"trap counts per theme spread %.3fx, band is %.3fx: %s"
				% [trap_ratio, MAX_TRAP_RATIO, traps]
			)
		)
		. is_less(MAX_TRAP_RATIO)
	)
	(
		assert_float(spawn_ratio)
		. override_failure_message("enemy spawn points per theme: %s" % str(spawns))
		. is_less(MAX_SPAWN_RATIO)
	)


## Mean interior area per room at `floor_index` over `AREA_SEEDS` seeds from `base`, with the
## standard error of that mean across the seeds. The error is the point: an assertion about a
## per-theme mean is worth exactly as much as the noise on it.
func _room_area(theme: String, base: int) -> Array[float]:
	var per_seed: Array[float] = []
	for offset in range(AREA_SEEDS):
		var data := ReactivityFixtures.generate(_params(theme, 3), base + offset * 17)
		var area := 0.0
		for room: FloorData.Room in data.rooms:
			area += float(room.rect.size.x * room.rect.size.y)
		per_seed.append(area / float(data.rooms.size()))
	var mean := 0.0
	for value: float in per_seed:
		mean += value
	mean /= float(AREA_SEEDS)
	var variance := 0.0
	for value: float in per_seed:
		variance += (value - mean) * (value - mean)
	variance /= float(AREA_SEEDS - 1)
	return [mean, sqrt(variance / float(AREA_SEEDS))]


func test_room_size_is_the_lever_that_moved_and_it_moved_past_the_noise() -> void:
	# This is the assertion that carries the "players should notice" claim, so it is stated at
	# the size it claims to protect and no larger.
	#
	# It used to average eight seeds and assert two pairwise orderings on its own hard-coded
	# seed base. Re-run through forty other seed bases, one of those orderings came out
	# backwards on eight of them: the effect was real and the measurement was smaller than the
	# noise it sat in, so the test could not fail at the size it was claiming. Two things fixed
	# that - the lever itself got wider (`ThemeProfile.ROOM_SIZE_OPENNESS_SWING`, 0.15 -> 0.34,
	# and since then signed: a tight theme now pulls rooms *under* the default) and the claim is
	# now made in units of its own standard error, measured here rather than assumed. Over
	# thirty other seed bases at this sample size the light-vs-dark gap never fell
	# below 3.4 standard errors and neither dark-theme ordering inverted once (the first of them
	# inverted on 8 of 40 before the lever was widened).
	var mean: Dictionary = {}
	var error: Dictionary = {}
	for theme: String in THEMES:
		var measured := _room_area(theme, SEED)
		mean[theme] = measured[0]
		error[theme] = measured[1]
	var light := 0.0
	var light_variance := 0.0
	for theme: String in LIGHT_THEMES:
		light += float(mean[theme]) / float(LIGHT_THEMES.size())
		light_variance += pow(float(error[theme]) / float(LIGHT_THEMES.size()), 2.0)
	var dark := 0.0
	var dark_variance := 0.0
	for theme: String in DARK_THEMES:
		dark += float(mean[theme]) / float(DARK_THEMES.size())
		dark_variance += pow(float(error[theme]) / float(DARK_THEMES.size()), 2.0)
	var sigma := sqrt(light_variance + dark_variance)
	(
		assert_float((light - dark) / maxf(sigma, 0.0001))
		. override_failure_message(
			(
				(
					"light themes lay %.1f tiles more room than dark ones, and the noise on that "
					+ "measurement is %.1f tiles - the lever is inside its own error bar. Means: %s"
				)
				% [light - dark, sigma, str(mean)]
			)
		)
		. is_greater(MIN_AREA_SIGMA)
	)
	# ...and the ordering inside the dark set, which is `openness` rather than `brightness`:
	# the two dark themes with cool dominant hues lay bigger rooms than the two warm ones.
	for pair: Array in [["catppuccin", "gruvbox"], ["tokyo-night", "nord"]]:
		(
			assert_float(mean[pair[0]] as float)
			. override_failure_message(
				"%s should lay bigger rooms than %s. Means: %s" % [pair[0], pair[1], str(mean)]
			)
			. is_greater(mean[pair[1]] as float)
		)


## Corridor tiles and traps per floor for one theme, over `CHARACTER_SEEDS` seeds x every
## floor of a run. Returns [corridor tiles per floor, traps per floor]. Traps are counted
## outside the trap gauntlet: whether a floor rolls a gauntlet is the per-floor room budget's
## draw (docs 5.1 #4), the same for every theme, and its five-to-eleven traps swamp the one or
## two the theme's `trap_density` lays in an ordinary room - which is the lever being measured.
func _character(theme: String) -> Array[float]:
	var corridor := 0
	var traps := 0
	var floors := 0
	for offset in range(CHARACTER_SEEDS):
		for floor_index: int in range(GenParams.LAST_FLOOR + 1):
			var data := ReactivityFixtures.generate(
				_params(theme, floor_index), SEED + offset * 1009
			)
			for y in range(data.height):
				for x in range(data.width):
					if data.get_tile(x, y) == FloorData.Tile.CORRIDOR:
						corridor += 1
			for room: FloorData.Room in data.rooms:
				if room.type != FloorData.RoomType.TRAP:
					traps += room.trap_positions.size()
			floors += 1
	return [float(corridor) / float(floors), float(traps) / float(floors)]


func test_the_character_table_in_the_docs_is_the_one_the_generator_produces() -> void:
	# docs §3.3 used to name two themes and the characters a player "should notice", and
	# neither was what the derivation produced: catppuccin had the straightest, shortest
	# corridors of any dark theme and gruvbox was fourth of six on traps. A design document
	# naming a theme is a promise, so the table it prints now is measured - and measured here,
	# so the two cannot drift apart again.
	var corridor: Dictionary = {}
	var traps: Dictionary = {}
	for theme: String in THEMES:
		var measured := _character(theme)
		corridor[theme] = measured[0]
		traps[theme] = measured[1]
	# The docs 3.3 table is copied from this line; keep them together.
	print("theme character: corridor tiles per floor %s, traps per floor %s" % [corridor, traps])
	# "Gruvbox runs are blocky": the fewest corridor tiles of the six. Asserted without a
	# margin, because `white` - whose wiggle sits at the bottom of the band - is within a few
	# tiles of it and that gap is smaller than its own sampling noise; what *is* asserted with
	# room to spare is the spread, from gruvbox to the widest fixture.
	var lowest := INF
	var highest := 0.0
	for theme: String in THEMES:
		lowest = minf(lowest, float(corridor[theme]))
		highest = maxf(highest, float(corridor[theme]))
	(
		assert_float(corridor["gruvbox"] as float)
		. override_failure_message(
			"gruvbox is no longer the blockiest theme. Corridor tiles per floor: %s" % str(corridor)
		)
		. is_equal(lowest)
	)
	(
		assert_float(highest / lowest)
		. override_failure_message("corridor tiles per floor spread only %s" % str(corridor))
		. is_greater_equal(CORRIDOR_SPREAD)
	)
	# ...and tokyo-night is the dark theme that sprawls: most loops, widest spacing, most
	# corridor to walk.
	var dark_rest := 0.0
	for theme: String in DARK_THEMES:
		if theme != "tokyo-night":
			dark_rest = maxf(dark_rest, float(corridor[theme]))
	(
		assert_float(corridor["tokyo-night"] as float)
		. override_failure_message(
			(
				"tokyo-night is no longer the most connected dark theme. Corridor tiles: %s"
				% str(corridor)
			)
		)
		. is_greater(dark_rest / CHARACTER_MARGIN)
	)
	# The half of the old sentence that was backwards. Traps follow `1 - saturation`, and
	# gruvbox is the second most saturated dark theme shipped, so it can never be the
	# trap-heavy one: the muted fixtures lay more. Only the ends of that ordering are asserted
	# - the theme whose derived `trap_density` is highest lays the most and the one whose is
	# lowest lays the fewest; the middle moves by more than its own gaps at any sample a unit
	# test can afford, which is precisely why no theme should be *named* for its traps.
	var most := THEMES[0]
	var fewest := THEMES[0]
	for theme: String in THEMES:
		if _params(theme, 0).trap_density > _params(most, 0).trap_density:
			most = theme
		if _params(theme, 0).trap_density < _params(fewest, 0).trap_density:
			fewest = theme
	for theme: String in THEMES:
		if theme != most:
			(
				assert_float(traps[most] as float)
				. override_failure_message(
					(
						"%s derives the most traps but lays fewer than %s: %s"
						% [most, theme, str(traps)]
					)
				)
				. is_greater(traps[theme] as float)
			)
		if theme != fewest:
			(
				assert_float(traps[fewest] as float)
				. override_failure_message(
					(
						"%s derives the fewest traps but lays more than %s: %s"
						% [fewest, theme, str(traps)]
					)
				)
				. is_less(traps[theme] as float)
			)


func test_one_theme_and_one_seed_still_reproduce_the_floor_exactly() -> void:
	# Everything above is worthless if the theme made generation non-deterministic: a resumed
	# run rebuilds its floor from the recorded gen_params and has to get the same one back.
	for theme: String in THEMES:
		for floor_index: int in [0, 2, 5]:
			var a := ReactivityFixtures.generate(_params(theme, floor_index), SEED)
			var b := ReactivityFixtures.generate(_params(theme, floor_index), SEED)
			assert_str(a.to_ascii()).is_equal(b.to_ascii())
			assert_int(a.layout_hash()).is_equal(b.layout_hash())
			assert_bool(a.is_fallback).is_false()


func test_a_theme_less_params_rolls_exactly_as_it_did_before_the_salt() -> void:
	var bare := GenParams.new()
	assert_int(bare.theme_hash).is_equal(0)
	assert_int(FloorGenerator.layout_seed(12345, bare)).is_equal(12345)
	var themed := _params("nord", 1)
	assert_int(FloorGenerator.layout_seed(12345, themed)).is_not_equal(12345)
	assert_int(FloorGenerator.layout_seed(12345, themed)).is_equal(
		FloorGenerator.layout_seed(12345, _params("nord", 1))
	)
	assert_int(FloorGenerator.layout_seed(12345, themed)).is_not_equal(
		FloorGenerator.layout_seed(12345, _params("gruvbox", 1))
	)
