class_name GenParamsTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: Array[String] = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]


static func profile_for(theme: String) -> ThemeProfile:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemeProfile.from_palette(ThemePalette.from_colors_toml(toml, theme))


func test_room_counts_follow_docs_table() -> void:
	var expected: PackedInt32Array = [7, 8, 9, 10, 11, 12, 12, 13, 13]
	var profile := profile_for("tokyo-night")
	for i in range(expected.size()):
		assert_int(GenParams.from_profile(profile, i).room_count).is_equal(expected[i])
	assert_int(GenParams.from_profile(profile, 20).room_count).is_equal(13)


func test_boss_floors_are_2_5_8() -> void:
	var profile := profile_for("gruvbox")
	for i in range(9):
		var p := GenParams.from_profile(profile, i)
		assert_bool(p.is_boss_floor).is_equal(i == 2 or i == 5 or i == 8)


func test_biome_progression_per_theme() -> void:
	for theme: String in THEMES:
		var profile := profile_for(theme)
		for i in range(9):
			var p := GenParams.from_profile(profile, i)
			var expected: StringName = &"crypt"
			if i >= 6:
				expected = &"void"
			elif i >= 3:
				expected = profile.biome_middle_id()
			assert_str(String(p.biome)).is_equal(String(expected))
			assert_bool(p.biome in Biome.ALL_IDS).is_true()


func test_music_energy_scales_enemies_and_props() -> void:
	var profile := profile_for("nord")
	var quiet := GenParams.from_profile(profile, 1, 0.0)
	var loud := GenParams.from_profile(profile, 1, 1.0)
	var levers := MusicLevers.shared()
	assert_float(quiet.enemy_count_scale).is_equal_approx(levers.foes_calm, 0.001)
	assert_float(loud.enemy_count_scale).is_equal_approx(levers.foes_loud, 0.001)
	assert_float(loud.prop_density).is_greater(quiet.prop_density)


func test_biomes_load_from_data() -> void:
	for id: StringName in Biome.ALL_IDS:
		var biome := Biome.load_by_id(id)
		assert_str(String(biome.id)).is_equal(String(id))
		assert_bool(biome.trap_kinds.is_empty()).is_false()
		assert_bool(biome.prop_kinds.is_empty()).is_false()
		assert_str(biome.tileset_path).is_equal("res://assets/tiles/%s.png" % id)


func test_room_templates_load_from_data() -> void:
	var templates := RoomFiller.load_templates()
	assert_int(templates.size()).is_equal(RoomFiller.TEMPLATE_IDS.size())
	for t: RoomTemplate in templates:
		assert_bool(t.id in RoomFiller.TEMPLATE_IDS).is_true()
