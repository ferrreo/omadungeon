## The owner's report, measured: "theme/wallpaper doesn't do enough". `ThemeLayoutTest` pins
## that every fixture lays a *different* floor from one seed; this suite pins that the
## difference is one a player would describe - a tight, straight-halled dungeon against a
## sprawling, looping one - by putting numbers on the shape of the floor per fixture and
## asserting the spread between the extremes, not just that the extremes differ.
##
## What "shape" is here: mean room area, open tiles per floor (floor + corridor), corridor
## tiles per floor and loop count. Difficulty is deliberately not in the list - the trap and
## spawn bands are `ThemeLayoutTest`'s and this work must not move them - but the *kind* of
## hazard is, because that is flavour, not difficulty.
class_name ThemeShapeTest
extends GdUnitTestSuite

const THEMES: Array[String] = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
const SEED := 20250913
## Seeds x floors averaged per fixture. Enough to put the spreads below well clear of their
## noise (measured 2026-09-13 over 10 seeds x 9 floors: open tiles 1055..1475, corridor
## 63..101, loops 1.00..2.38, mean room area 97..135).
const SEEDS := 8
const FLOORS: Array[int] = [0, 3, 6]
## The spreads a player reads as two different dungeons: the most open fixture lays at least
## this many times the open tiles of the tightest, and so on. Each is roughly two thirds of the
## measured spread, so the assertion has headroom without being toothless.
const MIN_OPEN_RATIO := 1.20
const MIN_CORRIDOR_RATIO := 1.35
const MIN_AREA_RATIO := 1.20
const MIN_LOOP_SPREAD := 0.8
## The warm fixture and the cool one the hazard tilt is measured between.
const WARM := "gruvbox"
const COOL := "tokyo-night"


## Live inputs: a track is playing, so the tempo lever is in the loop, as in `ThemeLayoutTest`.
func _params(theme: String, floor_index: int) -> GenParams:
	return GenParams.build(
		ReactivityFixtures.profile_for(theme),
		floor_index,
		ReactivityFixtures.music(0.5, 128.0, "Public Code, Private Yacht"),
		null
	)


## Shape statistics of one floor: rooms, open tiles, corridor tiles, loops, mean room area.
static func shape_of(data: FloorData) -> Dictionary:
	var open_tiles := 0
	var corridor := 0
	for y in range(data.height):
		for x in range(data.width):
			var t := data.get_tile(x, y)
			if t == FloorData.Tile.CORRIDOR:
				corridor += 1
			if t == FloorData.Tile.FLOOR or t == FloorData.Tile.CORRIDOR:
				open_tiles += 1
	var edges := 0
	var area := 0
	for room: FloorData.Room in data.rooms:
		edges += room.neighbors.size()
		area += room.rect.size.x * room.rect.size.y
	return {
		"rooms": data.rooms.size(),
		"open": open_tiles,
		"corridor": corridor,
		"loops": edges / 2 - (data.rooms.size() - 1),
		"area": float(area) / float(maxi(data.rooms.size(), 1)),
	}


## Mean shape over `SEEDS` x `FLOORS` for one fixture, plus the trap kinds it laid.
func _mean_shape(theme: String) -> Dictionary:
	var sum := {"rooms": 0.0, "open": 0.0, "corridor": 0.0, "loops": 0.0, "area": 0.0}
	var kinds: Dictionary = {}
	var n := 0
	for offset in range(SEEDS):
		for floor_index: int in FLOORS:
			var data := ReactivityFixtures.generate(
				_params(theme, floor_index), SEED + offset * 7919
			)
			var shape := shape_of(data)
			for key: String in sum:
				sum[key] = float(sum[key]) + float(shape[key])
			for room: FloorData.Room in data.rooms:
				for trap: Dictionary in room.trap_positions:
					var kind := String(trap["kind"])
					kinds[kind] = int(kinds.get(kind, 0)) + 1
			n += 1
	for key: String in sum:
		sum[key] = float(sum[key]) / float(n)
	sum["kinds"] = kinds
	return sum


func _extremes(shapes: Dictionary, key: String) -> Array:
	var low := INF
	var high := -INF
	var low_theme := ""
	var high_theme := ""
	for theme: String in shapes:
		var value := float((shapes[theme] as Dictionary)[key])
		if value < low:
			low = value
			low_theme = theme
		if value > high:
			high = value
			high_theme = theme
	return [low, high, low_theme, high_theme]


func test_every_fixture_hashes_to_its_own_floor_on_every_sampled_floor() -> void:
	for floor_index: int in FLOORS:
		var hashes: Dictionary = {}
		for theme: String in THEMES:
			var data := ReactivityFixtures.generate(_params(theme, floor_index), SEED)
			assert_bool(data.is_fallback).is_false()
			var h := data.layout_hash()
			(
				assert_bool(hashes.has(h))
				. override_failure_message(
					(
						"floor %d: %s and %s hash to the same layout (%d)"
						% [floor_index, theme, str(hashes.get(h, "")), h]
					)
				)
				. is_false()
			)
			hashes[h] = theme


func test_the_shape_of_the_floor_spreads_past_what_a_player_can_miss() -> void:
	var shapes: Dictionary = {}
	for theme: String in THEMES:
		shapes[theme] = _mean_shape(theme)
	var checks := {"open": MIN_OPEN_RATIO, "corridor": MIN_CORRIDOR_RATIO, "area": MIN_AREA_RATIO}
	for key: String in checks:
		var ends := _extremes(shapes, key)
		var ratio := float(ends[1]) / maxf(float(ends[0]), 0.0001)
		(
			assert_float(ratio)
			. override_failure_message(
				(
					"%s spreads only %.2fx between %s (%.1f) and %s (%.1f) - below perception"
					% [key, ratio, ends[2], float(ends[0]), ends[3], float(ends[1])]
				)
			)
			. is_greater_equal(float(checks[key]))
		)
	var loops := _extremes(shapes, "loops")
	(
		assert_float(float(loops[1]) - float(loops[0]))
		. override_failure_message(
			(
				"loops spread only %.2f between %s (%.2f) and %s (%.2f)"
				% [float(loops[1]) - float(loops[0]), loops[2], loops[0], loops[3], loops[1]]
			)
		)
		. is_greater_equal(MIN_LOOP_SPREAD)
	)
	# Room count is a property of the floor index, never of the theme (docs §5.1 #1).
	var rooms := _extremes(shapes, "rooms")
	assert_float(float(rooms[1]) - float(rooms[0])).is_less(0.001)


func test_a_tight_theme_pulls_rooms_under_the_default_and_an_open_one_over_it() -> void:
	# The room-size bias is signed now: the generator's default sizes are the middle of the
	# band, not its floor, so the tightest desktop gets a tighter dungeon than "no theme".
	assert_float(ReactivityFixtures.profile_for("gruvbox").room_size_bias).is_less(0.0)
	assert_float(ReactivityFixtures.profile_for("nord").room_size_bias).is_less(0.0)
	assert_float(ReactivityFixtures.profile_for("catppuccin-latte").room_size_bias).is_greater(0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var tight := 0
	var open := 0
	for _i in range(400):
		var small := FloorLayout.size_for(
			FloorData.RoomType.COMBAT, ThemeProfile.ROOM_SIZE_BIAS_MIN, rng
		)
		var large := FloorLayout.size_for(
			FloorData.RoomType.COMBAT, ThemeProfile.ROOM_SIZE_BIAS_MAX, rng
		)
		tight += small.x * small.y
		open += large.x * large.y
	assert_float(float(open) / float(tight)).is_greater(1.4)


func test_warmth_tilts_which_hazards_a_floor_lays_but_not_how_many() -> void:
	var warm := _mean_shape(WARM)
	var cool := _mean_shape(COOL)
	var warm_kinds: Dictionary = warm["kinds"]
	var cool_kinds: Dictionary = cool["kinds"]
	var warm_share := _share(warm_kinds, ThemeProfile.HAZARD_WARM_KINDS)
	var cool_share := _share(cool_kinds, ThemeProfile.HAZARD_WARM_KINDS)
	(
		assert_float(warm_share)
		. override_failure_message(
			(
				"%s lays %.0f%% warm hazards against %s's %.0f%%: %s vs %s"
				% [WARM, warm_share * 100.0, COOL, cool_share * 100.0, warm_kinds, cool_kinds]
			)
		)
		. is_greater(cool_share * 1.5)
	)
	var neutral_warm := _share(warm_kinds, ThemeProfile.HAZARD_NEUTRAL_KINDS)
	var neutral_cool := _share(cool_kinds, ThemeProfile.HAZARD_NEUTRAL_KINDS)
	assert_float(neutral_cool).is_greater(neutral_warm)
	# The weights only ever choose *which* kind: the profile's trap density is untouched and
	# every weight is finite and positive, so no kind the biome allows is ever ruled out.
	for theme: String in THEMES:
		var profile := ReactivityFixtures.profile_for(theme)
		for kind: StringName in profile.hazard_weights:
			assert_float(float(profile.hazard_weights[kind])).is_between(
				1.0, 1.0 + ThemeProfile.HAZARD_TILT
			)
		assert_float(profile.trap_density).is_between(
			ThemeProfile.TRAP_DENSITY_MID - ThemeProfile.TRAP_DENSITY_SWING,
			ThemeProfile.TRAP_DENSITY_MID + ThemeProfile.TRAP_DENSITY_SWING
		)


func test_hazard_weights_survive_a_save_and_resume() -> void:
	var params := _params(WARM, 3)
	assert_dict(params.hazard_weights).is_not_empty()
	var saved := FloorRestore.gen_params_to_dict(params)
	var json := JSON.parse_string(JSON.stringify(saved)) as Dictionary
	var restored := GenParams.new()
	restored.hazard_weights = {}
	for key: Variant in json["hazard_weights"] as Dictionary:
		restored.hazard_weights[StringName(str(key))] = float(
			(json["hazard_weights"] as Dictionary)[key]
		)
	for kind: StringName in params.hazard_weights:
		assert_float(restored.trap_kind_weight(kind)).is_equal_approx(
			params.trap_kind_weight(kind), 0.0001
		)


func test_the_favoured_faction_is_half_of_every_pack_and_none_is_ever_dropped() -> void:
	for theme: String in THEMES:
		var weights := ReactivityFixtures.profile_for(theme).faction_weights
		var top := 0.0
		for faction: String in weights:
			var w := float(weights[faction])
			assert_float(w).is_greater_equal(1.0)
			top = maxf(top, w)
		assert_float(top).is_equal_approx(ThemeProfile.FACTION_FAVOURED, 0.0001)


static func _share(kinds: Dictionary, of: Array[StringName]) -> float:
	var total := 0
	var hit := 0
	for kind: String in kinds:
		var count := int(kinds[kind])
		total += count
		if StringName(kind) in of:
			hit += count
	return float(hit) / float(maxi(total, 1))
