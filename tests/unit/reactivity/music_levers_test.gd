## The music generation levers of docs §10.2 (`MusicLevers`): energy scales enemy count, prop
## density, trap density, the ambush, the light, the room size and the enemies' keenness;
## tempo bends the corridors and tightens the rooms; the track identity breaks fill-template
## ties and picks a signature prop. Each is proven to reach the generated floor, the whole set
## is proven deterministic, and one seed under two energies is measured to differ in enemy
## count, layout and light - the numbers the owner's "not enough impact" report is answered
## with.
class_name MusicLeversTest
extends GdUnitTestSuite

const THEME := "nord"
const SEED := 771010
## A wallpaper is deliberately absent here so only the music levers can move anything.
const FLOOR := 4


func _params(music: MusicProfile, floor_index: int = FLOOR) -> GenParams:
	return GenParams.build(ReactivityFixtures.profile_for(THEME), floor_index, music, null)


func test_tempo_bends_the_corridors() -> void:
	var profile := ReactivityFixtures.profile_for(THEME)
	var slow := _params(ReactivityFixtures.music(0.5, 70.0, "Slow Crawl"))
	var fast := _params(ReactivityFixtures.music(0.5, 180.0, "Fast Crawl"))
	var silent := _params(MusicProfile.silent())
	assert_float(fast.corridor_wiggle).is_greater(slow.corridor_wiggle)
	assert_float(absf(fast.corridor_wiggle - slow.corridor_wiggle)).is_greater(0.2)
	# Silence (tempo 0) must leave the theme's own wiggle untouched.
	assert_float(silent.corridor_wiggle).is_equal_approx(profile.corridor_wiggle, 0.0001)
	# Wiggle feeds the loop count, so the tempo reaches the graph as well.
	assert_int(fast.extra_loops).is_not_equal(slow.extra_loops)


func test_tempo_changes_the_corridor_tiles_on_the_built_floor() -> void:
	var slow := _params(ReactivityFixtures.music(0.5, 70.0, "Same Track"))
	var fast := _params(ReactivityFixtures.music(0.5, 180.0, "Same Track"))
	var differing := 0
	for offset in range(6):
		var a := ReactivityFixtures.generate(slow, SEED + offset)
		var b := ReactivityFixtures.generate(fast, SEED + offset)
		if a.layout_hash() != b.layout_hash():
			differing += 1
	assert_int(differing).is_equal(6)


func test_energy_scales_the_spawn_points_a_floor_offers() -> void:
	var quiet := _params(ReactivityFixtures.music(0.0, 0.0, "Quiet"))
	var loud := _params(ReactivityFixtures.music(1.0, 0.0, "Quiet"))
	var levers := MusicLevers.shared()
	assert_float(quiet.enemy_count_scale).is_equal_approx(levers.foes_calm, 0.001)
	assert_float(loud.enemy_count_scale).is_equal_approx(levers.foes_loud, 0.001)
	var quiet_points := 0
	var loud_points := 0
	for offset in range(10):
		quiet_points += ReactivityFixtures.spawn_point_count(
			ReactivityFixtures.generate(quiet, SEED + offset)
		)
		loud_points += ReactivityFixtures.spawn_point_count(
			ReactivityFixtures.generate(loud, SEED + offset)
		)
	(
		assert_int(loud_points)
		. override_failure_message(
			(
				"music energy did not change the number of spawn points (%d vs %d)"
				% [quiet_points, loud_points]
			)
		)
		. is_greater(quiet_points)
	)


func test_energy_scales_the_enemy_budget_the_spawner_spends() -> void:
	var levers := MusicLevers.shared()
	var quiet := EnemySpawner.budget_for(FloorData.RoomType.COMBAT, FLOOR, levers.foes_calm)
	var flat := EnemySpawner.budget_for(FloorData.RoomType.COMBAT, FLOOR)
	var loud := EnemySpawner.budget_for(FloorData.RoomType.COMBAT, FLOOR, levers.foes_loud)
	assert_float(quiet).is_less(flat)
	assert_float(loud).is_greater(flat)
	assert_float(loud / flat).is_equal_approx(levers.foes_loud, 0.001)


## The levers the owner's report added: a calm track means a darker floor with more traps,
## a bigger ambush in its trap rooms and dozier, slower, poorer enemies; a loud one the
## reverse. Every one of them is a `GenParams` field a save can carry.
func test_energy_moves_the_light_the_traps_the_ambush_and_the_enemies_keenness() -> void:
	var quiet := _params(ReactivityFixtures.music(0.0, 0.0, "Same"))
	var loud := _params(ReactivityFixtures.music(1.0, 0.0, "Same"))
	var silent := _params(MusicProfile.silent())
	var theme := ReactivityFixtures.profile_for(THEME)
	assert_float(loud.light_scale).is_greater(quiet.light_scale)
	assert_float(loud.light_scale - quiet.light_scale).is_greater_equal(0.3)
	assert_float(quiet.trap_density).is_greater(loud.trap_density)
	assert_float(quiet.trap_density - loud.trap_density).is_greater_equal(0.3)
	assert_float(quiet.ambush_scale).is_greater(loud.ambush_scale)
	assert_float(loud.sight_scale).is_greater(quiet.sight_scale)
	assert_float(loud.cadence_scale).is_less(quiet.cadence_scale)
	assert_float(loud.loot_scale).is_greater(quiet.loot_scale)
	assert_float(loud.room_size_bias).is_greater(quiet.room_size_bias)
	# Silence is the theme's own floor: every lever at its middle, nothing pushed.
	assert_float(silent.light_scale).is_equal_approx(MusicLevers.shared().light_scale(0.5), 0.001)
	assert_float(silent.trap_density).is_equal_approx(theme.trap_density, 0.001)
	assert_int(silent.accent_prop).is_equal(-1)
	assert_int(quiet.accent_prop).is_greater_equal(0)


## Tempo tightens the rooms as well as bending the corridors (docs 10.2).
func test_tempo_tightens_the_rooms() -> void:
	var slow := _params(ReactivityFixtures.music(0.5, 70.0, "Same"))
	var fast := _params(ReactivityFixtures.music(0.5, 180.0, "Same"))
	assert_float(fast.room_size_bias).is_less(slow.room_size_bias)


## Two tracks in the same biome furnish it differently: the track hash picks a signature
## prop kind and `MusicLevers.accent_share` of every room's props are that kind.
func test_the_track_identity_picks_a_signature_prop() -> void:
	var a := _params(ReactivityFixtures.music(0.5, 0.0, "No Title Bar"))
	var b := _params(ReactivityFixtures.music(0.5, 0.0, "Public Code, Private Yacht"))
	var biome := Biome.load_by_id(a.biome)
	var kinds := biome.prop_kinds.size()
	assert_int(kinds).is_greater(1)
	var ka := a.accent_prop % kinds
	var kb := b.accent_prop % kinds
	var floor := ReactivityFixtures.generate(a, SEED)
	var counts: Dictionary = {}
	var total := 0
	for room: FloorData.Room in floor.rooms:
		for kind: StringName in room.prop_kinds:
			counts[kind] = int(counts.get(kind, 0)) + 1
			total += 1
	assert_int(total).is_greater(10)
	var share := float(counts.get(biome.prop_kinds[ka], 0)) / float(total)
	(
		assert_float(share)
		. override_failure_message(
			"the signature prop is %.0f%% of the floor's props" % (share * 100.0)
		)
		. is_greater(MusicLevers.shared().accent_share * 0.7)
	)
	if ka != kb:
		var other := ReactivityFixtures.generate(b, SEED)
		var other_counts: Dictionary = {}
		for room: FloorData.Room in other.rooms:
			for kind: StringName in room.prop_kinds:
				other_counts[kind] = int(other_counts.get(kind, 0)) + 1
		assert_int(int(other_counts.get(biome.prop_kinds[kb], 0))).is_greater(
			int(counts.get(biome.prop_kinds[kb], 0))
		)


## The measurement: one seed, one theme, one track, two energies. The two floors must differ
## in what a player counts - enemies, traps, tiles, light - by margins nobody has to squint
## at, and the numbers are printed so a report can quote them.
func test_one_seed_under_two_energies_differs_in_enemies_layout_and_light() -> void:
	var calm := _params(ReactivityFixtures.music(0.1, 128.0, "Same Track"))
	var loud := _params(ReactivityFixtures.music(0.9, 128.0, "Same Track"))
	var calm_floor := ReactivityFixtures.generate(calm, SEED)
	var loud_floor := ReactivityFixtures.generate(loud, SEED)
	var calm_spawns := ReactivityFixtures.spawn_point_count(calm_floor)
	var loud_spawns := ReactivityFixtures.spawn_point_count(loud_floor)
	var calm_traps := _trap_count(calm_floor)
	var loud_traps := _trap_count(loud_floor)
	var calm_props := _prop_count(calm_floor)
	var loud_props := _prop_count(loud_floor)
	var tiles := ReactivityFixtures.tile_difference(calm_floor, loud_floor)
	print(
		(
			(
				"seed %d floor %d, energy 0.1 vs 0.9: spawn points %d vs %d, traps %d vs %d, "
				+ "props %d vs %d, tiles differing %.1f%%, light scale %.2f vs %.2f, "
				+ "room size bias %.2f vs %.2f, sight x%.2f vs x%.2f, cooldown x%.2f vs x%.2f"
			)
			% [
				SEED,
				FLOOR,
				calm_spawns,
				loud_spawns,
				calm_traps,
				loud_traps,
				calm_props,
				loud_props,
				tiles * 100.0,
				calm.light_scale,
				loud.light_scale,
				calm.room_size_bias,
				loud.room_size_bias,
				calm.sight_scale,
				loud.sight_scale,
				calm.cadence_scale,
				loud.cadence_scale
			]
		)
	)
	# The count scale is 0.76 vs 1.24; rooms of three or four spawns round some of that away,
	# so the whole-floor ratio lands lower than the scales' own, and still a fifth apart.
	assert_float(float(loud_spawns) / float(maxi(calm_spawns, 1))).is_greater_equal(1.2)
	assert_int(calm_traps).is_greater(loud_traps)
	assert_int(loud_props).is_greater(calm_props)
	assert_float(tiles).is_greater(0.0)
	assert_float(loud.light_scale - calm.light_scale).is_greater_equal(0.3)
	assert_str(calm_floor.to_ascii()).is_not_equal(loud_floor.to_ascii())


static func _trap_count(data: FloorData) -> int:
	var total := 0
	for room: FloorData.Room in data.rooms:
		total += room.trap_positions.size()
	return total


static func _prop_count(data: FloorData) -> int:
	var total := 0
	for room: FloorData.Room in data.rooms:
		total += room.prop_positions.size()
	return total


func test_a_floors_spawn_points_never_share_a_tile() -> void:
	for offset in range(20):
		var data := ReactivityFixtures.generate(
			_params(ReactivityFixtures.music(1.0, 0.0, "Loud")), SEED + offset
		)
		for room: FloorData.Room in data.rooms:
			var seen: Dictionary = {}
			for tile: Vector2i in room.enemy_spawns:
				(
					assert_bool(seen.has(tile))
					. override_failure_message(
						"room %d lists spawn tile %s twice" % [room.id, tile]
					)
					. is_false()
				)
				seen[tile] = true


func test_the_track_identity_breaks_fill_template_ties() -> void:
	var a := _params(ReactivityFixtures.music(0.5, 0.0, "No Title Bar"))
	var b := _params(ReactivityFixtures.music(0.5, 0.0, "Public Code, Private Yacht"))
	assert_int(a.track_hash).is_not_equal(b.track_hash)
	assert_int(a.fill_bias_hash).is_not_equal(b.fill_bias_hash)
	# Everything else the generator reads is identical.
	assert_float(b.prop_density).is_equal_approx(a.prop_density, 0.0001)
	assert_float(b.corridor_wiggle).is_equal_approx(a.corridor_wiggle, 0.0001)
	assert_float(b.enemy_count_scale).is_equal_approx(a.enemy_count_scale, 0.0001)
	var differing := 0
	for offset in range(12):
		var left := ReactivityFixtures.fill_templates(ReactivityFixtures.generate(a, SEED + offset))
		var right := ReactivityFixtures.fill_templates(
			ReactivityFixtures.generate(b, SEED + offset)
		)
		if left != right:
			differing += 1
	(
		assert_int(differing)
		. override_failure_message(
			(
				(
					"the track hash moved a fill template on only %d of 12 floors - a ±30%% weight "
					+ "nudge that never wins a roll is not a lever"
				)
				% differing
			)
		)
		. is_greater(3)
	)


func test_two_music_profiles_on_one_seed_produce_different_floors() -> void:
	var calm := ReactivityFixtures.music(0.1, 78.0, "Bass Crawl")
	var wild := ReactivityFixtures.music(0.95, 172.0, "Oligarchy")
	for floor_index in range(0, 9, 2):
		var a := ReactivityFixtures.generate(_params(calm, floor_index), SEED)
		var b := ReactivityFixtures.generate(_params(wild, floor_index), SEED)
		(
			assert_str(ReactivityFixtures.floor_signature(a))
			. override_failure_message(
				"floor %d is identical under two very different tracks" % floor_index
			)
			. is_not_equal(ReactivityFixtures.floor_signature(b))
		)


func test_the_same_music_profile_on_one_seed_reproduces_the_floor_exactly() -> void:
	var track := ReactivityFixtures.music(0.62, 128.0, "Hyprland After Dark")
	for floor_index in range(9):
		var a := ReactivityFixtures.generate(_params(track, floor_index), SEED)
		var b := ReactivityFixtures.generate(_params(track, floor_index), SEED)
		assert_str(ReactivityFixtures.floor_signature(a)).is_equal(
			ReactivityFixtures.floor_signature(b)
		)
		assert_str(a.to_ascii()).is_equal(b.to_ascii())


func test_a_saved_run_restores_every_music_lever() -> void:
	var track := ReactivityFixtures.music(0.62, 128.0, "Hyprland After Dark")
	var params := _params(track)
	var restored := GenParams.build(ReactivityFixtures.profile_for(THEME), FLOOR, null, null)
	restored.music_energy = params.music_energy
	restored.music_tempo = params.music_tempo
	restored.track_hash = params.track_hash
	restored.corridor_wiggle = params.corridor_wiggle
	restored.prop_density = params.prop_density
	restored.enemy_count_scale = params.enemy_count_scale
	restored.ambush_scale = params.ambush_scale
	restored.light_scale = params.light_scale
	restored.accent_prop = params.accent_prop
	restored.trap_density = params.trap_density
	restored.room_size_bias = params.room_size_bias
	restored.extra_loops = params.extra_loops
	restored.refresh_fill_bias()
	assert_int(restored.fill_bias_hash).is_equal(params.fill_bias_hash)
	(
		assert_str(ReactivityFixtures.floor_signature(ReactivityFixtures.generate(restored, SEED)))
		. is_equal(ReactivityFixtures.floor_signature(ReactivityFixtures.generate(params, SEED)))
	)


## The seed promise, pinned against the evidence. The music levers are sampled live - energy
## is a 30 s rolling RMS - so one seed, one theme and one *track* still build different floors
## depending on where in the track the floor was generated. That is the contract docs §5.1
## keeps, and it is exactly why no screen may offer to replay a dungeon from a seed, so the
## two captions that used to promise one are asserted here, next to the proof.
func test_live_energy_moves_the_floor_so_no_screen_promises_a_replay() -> void:
	var quiet := _params(ReactivityFixtures.music(0.15, 120.0, "Public Code, Private Yacht"))
	var loud := _params(ReactivityFixtures.music(0.95, 120.0, "Public Code, Private Yacht"))
	assert_int(loud.track_hash).is_equal(quiet.track_hash)
	assert_float(loud.corridor_wiggle).is_equal_approx(quiet.corridor_wiggle, 0.0001)
	assert_float(loud.enemy_count_scale).is_not_equal(quiet.enemy_count_scale)
	var differing := 0
	for offset in range(6):
		var a := ReactivityFixtures.generate(quiet, SEED + offset)
		var b := ReactivityFixtures.generate(loud, SEED + offset)
		if ReactivityFixtures.floor_signature(a) != ReactivityFixtures.floor_signature(b):
			differing += 1
	(
		assert_int(differing)
		. override_failure_message(
			(
				"the live energy no longer reaches the floor - if generation is now "
				+ "reproducible from the seed, docs 5.1 and the seed captions must say so"
			)
		)
		. is_greater(0)
	)
	var hint := Title.seed_hint_text("Tokyo Night").to_lower()
	assert_str(hint).contains("tokyo night")
	assert_str(hint).contains("music")
	(
		assert_bool(hint.contains("same dungeon"))
		. override_failure_message("the title caption promises a dungeon the seed cannot pin")
		. is_false()
	)
	assert_str(RunSummary.RETRY_LABEL.to_lower()).is_not_equal("retry seed")
	assert_str(RunSummary.RETRY_TOOLTIP.to_lower()).contains("will differ")
