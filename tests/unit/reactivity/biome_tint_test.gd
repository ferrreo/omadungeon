## Per-biome theme tinting (docs §10: "Biomes also pick from different subsets of theme
## keys"). Under one theme the five biomes must resolve to different accent colours, and the
## floor actually built for a biome must use that biome's subset.
class_name BiomeTintTest
extends GdUnitTestSuite

const THEME := "tokyo-night"
const ROOM_SEED := 991


func _accents(biome_id: StringName, palette: ThemePalette) -> Array[Color]:
	var biome := Biome.load_by_id(biome_id)
	var derived := palette.derive_environment(biome.palette_keys)
	var ramp := TileRamp.target_colors(derived, TileRamp.Variant.BASE, ROOM_SEED)
	return [ramp[6], ramp[7]]


func test_every_biome_declares_its_own_theme_keys() -> void:
	var seen: Dictionary = {}
	for id: StringName in Biome.ALL_IDS:
		var biome := Biome.load_by_id(id)
		(
			assert_int(biome.palette_keys.size())
			. override_failure_message("biome %s declares no palette_keys" % id)
			. is_greater(0)
		)
		var key := ",".join(biome.palette_keys)
		(
			assert_bool(seen.has(key))
			. override_failure_message(
				"biomes %s and %s share the key subset %s" % [seen.get(key, ""), id, key]
			)
			. is_false()
		)
		seen[key] = String(id)


func test_a_biome_restricts_the_prop_pool_to_its_own_keys() -> void:
	var palette := ReactivityFixtures.palette_for(THEME)
	for id: StringName in Biome.ALL_IDS:
		var biome := Biome.load_by_id(id)
		var derived := palette.derive_environment(biome.palette_keys)
		var expected: Array[Color] = []
		for key: String in biome.palette_keys:
			if palette.source.has(key):
				expected.append(palette.source[key] as Color)
		assert_int(derived.prop_pool.size()).is_equal(expected.size())
		for i in range(expected.size()):
			assert_bool(derived.prop_pool[i].is_equal_approx(expected[i])).is_true()
		# The base palette is never mutated: every biome derives from the same theme.
		assert_int(palette.prop_pool.size()).is_equal(ThemePalette.PROP_POOL.size())


func test_the_five_biomes_look_different_under_one_theme() -> void:
	var palette := ReactivityFixtures.palette_for(THEME)
	var by_biome: Dictionary = {}
	for id: StringName in Biome.ALL_IDS:
		by_biome[id] = _accents(id, palette)
	for a: StringName in Biome.ALL_IDS:
		for b: StringName in Biome.ALL_IDS:
			if a == b:
				continue
			var left: Array[Color] = by_biome[a]
			var right: Array[Color] = by_biome[b]
			var same := left[0].is_equal_approx(right[0]) and left[1].is_equal_approx(right[1])
			(
				assert_bool(same)
				. override_failure_message(
					"%s and %s resolve to the same accents under %s" % [a, b, THEME]
				)
				. is_false()
			)


func test_biome_tinting_holds_under_every_shipped_theme() -> void:
	for theme: String in ["gruvbox", "catppuccin", "nord", "white"]:
		var palette := ReactivityFixtures.palette_for(theme)
		var forge := _accents(&"forge", palette)
		var frost := _accents(&"frost", palette)
		var library := _accents(&"library", palette)
		(
			assert_bool(forge[0].is_equal_approx(frost[0]))
			. override_failure_message("forge and frost share an accent under %s" % theme)
			. is_false()
		)
		(
			assert_bool(forge[0].is_equal_approx(library[0]))
			. override_failure_message("forge and library share an accent under %s" % theme)
			. is_false()
		)


func test_a_theme_without_the_biome_keys_falls_back_to_the_full_pool() -> void:
	var palette := ReactivityFixtures.palette_for(THEME)
	var derived := palette.derive_environment(PackedStringArray(["no_such_key"]))
	assert_int(derived.prop_pool.size()).is_equal(palette.prop_pool.size())


func test_the_built_floor_uses_its_biome_subset() -> void:
	var root := auto_free(FloorRoot.new()) as FloorRoot
	add_child(root)
	var data := RoomsTestFixtures.three_rooms()
	data.biome = &"forge"
	var forge := Biome.load_by_id(&"forge")
	root.build_with_biome(data, forge, null, ReactivityFixtures.palette_for(THEME))
	assert_array(root.biome_palette_keys()).is_equal(forge.palette_keys)
	var derived := root.environment_palette()
	assert_object(derived).is_not_null()
	# The forge keys, plus whatever the live wallpaper contributed (docs §3.4).
	assert_int(derived.prop_pool.size()).is_greater_equal(forge.palette_keys.size())
	var mat := root.material_for_room(0)
	assert_object(mat).is_not_null()
	var shown: Variant = mat.get_shader_parameter(&"target_colors")
	var colors := shown as PackedColorArray
	var pool_hit := false
	for i: int in [6, 7]:
		for c: Color in derived.prop_pool:
			if ThemePalette.contrast_ratio(colors[i], c) < 1.35:
				pool_hit = true
	(
		assert_bool(pool_hit)
		. override_failure_message("the forge floor's accents do not come from the forge subset")
		. is_true()
	)
