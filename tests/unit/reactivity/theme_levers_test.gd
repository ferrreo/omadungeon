## Docs §3.3: the desktop theme biases generation but "never changes difficulty beyond ±10%
## trap density". This pins the derived value to that bound across every shipped theme and
## checks the flavour difference survives it — muted themes still lay more traps than vivid
## ones, just not twice as many.
class_name ThemeLeversTest
extends GdUnitTestSuite

const THEMES: Array[String] = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
const SEED := 313131


func _trap_count(theme: String, floor_index: int, seed_value: int) -> int:
	var params := GenParams.from_profile(ReactivityFixtures.profile_for(theme), floor_index)
	var data := ReactivityFixtures.generate(params, seed_value)
	var total := 0
	for room: FloorData.Room in data.rooms:
		total += room.trap_positions.size()
	return total


func test_trap_density_stays_inside_the_documented_ten_percent() -> void:
	var low := ThemeProfile.TRAP_DENSITY_MID - ThemeProfile.TRAP_DENSITY_SWING
	var high := ThemeProfile.TRAP_DENSITY_MID + ThemeProfile.TRAP_DENSITY_SWING
	assert_float(ThemeProfile.TRAP_DENSITY_SWING / ThemeProfile.TRAP_DENSITY_MID).is_equal_approx(
		0.1, 0.0001
	)
	var seen: Array[float] = []
	for theme: String in THEMES:
		var density := ReactivityFixtures.profile_for(theme).trap_density
		(
			assert_float(density)
			. override_failure_message("%s derives trap_density %f" % [theme, density])
			. is_between(low, high)
		)
		seen.append(density)
	var lowest := seen.min() as float
	var highest := seen.max() as float
	# The flavour is still there: the themes do not all land on the same number.
	assert_float(highest - lowest).is_greater(0.02)
	assert_float(highest / lowest).is_less(1.25)


func test_muted_themes_still_lay_more_traps_than_vivid_ones() -> void:
	# "white" has zero chroma (the most muted shipped theme), "catppuccin-latte" the most.
	assert_float(ReactivityFixtures.profile_for("white").trap_density).is_greater(
		ReactivityFixtures.profile_for("catppuccin-latte").trap_density
	)
	# Sampled over floors as well as seeds. A trap-gauntlet room lays five times what a combat
	# room does, and which rooms a floor gets is a layout roll, so one floor of fourteen seeds
	# measures the room-type lottery at least as loudly as it measures the density lever.
	var muted := 0
	var vivid := 0
	for offset in range(20):
		for floor_index in range(5):
			muted += _trap_count("white", floor_index, SEED + offset)
			vivid += _trap_count("catppuccin-latte", floor_index, SEED + offset)
	(
		assert_int(muted)
		. override_failure_message("muted themes laid %d traps, vivid ones %d" % [muted, vivid])
		. is_greater(vivid)
	)


func test_the_theme_hash_still_drives_the_fill_template_tie_break() -> void:
	var a := GenParams.from_profile(ReactivityFixtures.profile_for("gruvbox"), 4)
	var b := GenParams.from_profile(ReactivityFixtures.profile_for("nord"), 4)
	assert_int(a.fill_bias_hash).is_equal(a.theme_hash)
	assert_int(a.fill_bias_hash).is_not_equal(b.fill_bias_hash)
	var differing := 0
	for id: StringName in RoomFiller.TEMPLATE_IDS:
		if not is_equal_approx(a.template_bias(id), b.template_bias(id)):
			differing += 1
		assert_float(a.template_bias(id)).is_between(
			GenParams.TEMPLATE_BIAS_MIN, GenParams.TEMPLATE_BIAS_MAX
		)
	assert_int(differing).is_greater(RoomFiller.TEMPLATE_IDS.size() / 2)
