## The lighting layer on a built floor (`LightRig`): the dark, which is one number on every
## theme and which nothing may move, a lantern on every generator anchor burning in the theme's
## role colour on all six fixtures, the shadow-caster cap, the unexplored shade, the quality
## switch (OFF is the floor as it was), and nothing left behind when the floor clears.
class_name LightingRigTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
## The most the drawn dark may differ between the calmest track and the loudest one. It is not
## a tolerance, it is zero plus float noise: the music drives the lights and may not touch the
## dark at all (`LightingProfile.unlit_floor`).
const MOOD_DARK_BOUND := 0.0001

var _floors: Array[FloorRoot] = []


func after_test() -> void:
	for root: FloorRoot in _floors:
		if is_instance_valid(root):
			root.clear_floor()
			root.free()
	_floors.clear()
	GameState.settings.erase(LightingProfile.SETTING_QUALITY)
	GameState.settings.erase(LightingProfile.SETTING_SHADOWS)
	await get_tree().process_frame
	await get_tree().process_frame


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _floor(theme: String = "tokyo-night", data: FloorData = null) -> FloorRoot:
	var root := FloorRoot.new()
	_floors.append(root)
	add_child(root)
	var layout := data if data != null else RoomsTestFixtures.three_rooms()
	root.build_with_biome(layout, Biome.load_by_id(&"crypt"), null, _palette(theme))
	return root


## A built floor carries the rig, with darkness, a lantern on every anchor, and the occluders.
func test_a_built_floor_carries_darkness_lanterns_and_occluders() -> void:
	var root := _floor()
	var rig := LightRig.of(root)
	assert_object(rig).is_not_null()
	assert_bool(rig.active()).is_true()
	assert_object(rig.darkness).is_not_null()
	assert_float(rig.unlit_level()).is_less(1.0)
	var anchors := LightRig.anchors_for(root.data)
	assert_int(rig.lanterns.size()).is_equal(anchors.size())
	assert_int(rig.lanterns.size()).is_greater(0)
	for lantern: WallLantern in rig.lanterns:
		assert_bool(anchors.has(lantern.tile)).is_true()
		assert_object(lantern.sprite).is_not_null()
		assert_object(lantern.light).is_not_null()
		assert_float(lantern.light.energy).is_greater(0.0)
	assert_int(rig.occluders.size()).is_equal(
		WallOccluders.runs_for(root.data, rig.profile.occluder_inset_px).size()
	)
	assert_object(LightRig.current()).is_same(rig)


## Every light colour comes from the theme: on all six fixtures a lantern burns in the role
## the profile names, turned and raised the way the door torches are, and the darkness is
## the light-theme value on a light theme.
func test_every_light_colour_resolves_from_the_theme_role_on_every_fixture() -> void:
	var light := DungeonLight.resolve()
	for theme: String in THEMES:
		var root := _floor(theme)
		var rig := LightRig.of(root)
		var pal := root.lit_palette()
		var kind := rig.profile.lantern_kind_for(root.data.biome)
		var role := rig.profile.lantern_role_for(kind)
		var want: Color = (
			light.torch_color(pal)
			if role == &"heat"
			else Music.mood_state().light_color(light.light_color(pal.get_color(role)))
		)
		for lantern: WallLantern in rig.lanterns:
			(
				assert_bool(lantern.light.color.is_equal_approx(want))
				. override_failure_message(
					(
						"%s: lantern %s burns %s, want %s"
						% [theme, lantern.tile, lantern.light.color, want]
					)
				)
				. is_true()
			)
		# The dark is one number, and it is the same one on a paper theme as on a navy one.
		var want_dark := rig.profile.unlit_level()
		assert_float(rig.unlit_level()).is_equal_approx(want_dark, 0.0001)
		assert_int(rig.darkness.blend_mode).is_equal(Light2D.BLEND_MODE_MIX)
		assert_float(rig.darkness_strength()).is_equal_approx(1.0 - want_dark, 0.0001)
		# ...and it reaches the bodies standing in it exactly as far as it reaches the floor,
		# which is what `LIT_MASK` on one light says. No light reaches a tell.
		assert_int(rig.darkness.range_item_cull_mask).is_equal(LightRig.LIT_MASK)
		# One light per lantern, plus the sprite, on the same mask the dark is on.
		for lantern: WallLantern in rig.lanterns:
			assert_int(lantern.light.range_item_cull_mask).is_equal(LightRig.LIT_MASK)
			assert_int(lantern.get_child_count()).is_equal(2)
			var pool := rig.lantern_energy() * rig.mood_energy()
			assert_float(lantern.light.energy).is_equal_approx(pool, 0.001)
		for prop: Prop in root.props:
			assert_int(prop.sprite.light_mask).is_equal(LightRig.PROP_MASK)
		# A stairs room has a stairs glow in the theme's bright text colour.
		var kinds: Array[StringName] = []
		for e: LightEmitter in rig.live_emitters():
			kinds.append(e.kind)
		assert_array(kinds).contains([&"stairs"])


## At most `shadow_casters` lights cast shadows at once, the nearest to the view; the rest
## still shine. With shadows off none cast.
func test_shadow_casting_lights_are_capped_to_the_nearest_few() -> void:
	var root := _floor()
	var rig := LightRig.of(root)
	# A cap the fixture can actually exceed. The shipped one is eight and the three-room fixture
	# carries six lights since a door hangs one torch rather than a flanking pair
	# (`FloorRoot._place_torches`), so the shipped number cannot be reached here and a cap that is
	# never reached is a cap nothing is testing.
	rig.profile.shadow_casters = 3
	var cap := rig.profile.shadow_casters
	rig._process(1.0)
	rig._apply_casters()
	var casters := rig.shadow_casters()
	var candidates := rig.shadow_candidates(root.player_spawn_position())
	assert_int(casters.size()).is_equal(mini(cap, candidates.size()))
	assert_int(candidates.size()).is_greater(cap)
	var prop_casters := 0
	for light: Light2D in casters:
		assert_float(light.energy).is_greater(0.0)
		# A shadow dims, never blacks out, and is soft.
		assert_float(light.shadow_color.a).is_less_equal(0.45)
		assert_int(light.shadow_filter).is_equal(Light2D.SHADOW_FILTER_PCF13)
		assert_int(light.shadow_item_cull_mask & LightRig.WALL_OCCLUDER_MASK).is_not_equal(0)
		if light.shadow_item_cull_mask & LightRig.PROP_OCCLUDER_MASK:
			prop_casters += 1
	# Props shadow from the player's own light only (none here: no player); the walls shadow
	# from every caster.
	assert_int(prop_casters).is_equal(0)
	for occluder: LightOccluder2D in rig.occluders:
		assert_int(occluder.occluder_light_mask).is_equal(LightRig.WALL_OCCLUDER_MASK)
	var solid_props := 0
	for prop: Prop in root.props:
		if prop.solid:
			solid_props += 1
			assert_int(prop.occluder().occluder_light_mask).is_equal(LightRig.PROP_OCCLUDER_MASK)
	assert_int(solid_props).is_greater(0)
	GameState.settings[LightingProfile.SETTING_SHADOWS] = false
	EventBus.settings_changed.emit(LightingProfile.SETTING_SHADOWS)
	rig = LightRig.of(root)
	rig._process(1.0)
	assert_int(rig.shadow_casters().size()).is_equal(0)
	assert_bool(rig.active()).is_true()


## Quality OFF is the baseline: no darkness, no lanterns, no occluders, no emitters, the door
## torches exactly as `FloorRoot` placed them.
func test_quality_off_is_the_floor_as_it_was() -> void:
	GameState.settings[LightingProfile.SETTING_QUALITY] = LightingProfile.Quality.OFF
	var root := _floor()
	var rig := LightRig.of(root)
	assert_object(rig).is_not_null()
	assert_bool(rig.active()).is_false()
	assert_float(rig.unlit_level()).is_equal(1.0)
	assert_int(rig.lanterns.size()).is_equal(0)
	assert_int(rig.occluders.size()).is_equal(0)
	assert_int(rig.get_child_count()).is_equal(0)
	assert_object(LightEmitter.attach(root, &"fire")).is_null()
	assert_int(root.torch_lights().size()).is_greater(0)
	# Switching the quality on live rebuilds the layer in place.
	GameState.settings[LightingProfile.SETTING_QUALITY] = LightingProfile.Quality.LOW
	EventBus.settings_changed.emit(LightingProfile.SETTING_QUALITY)
	rig = LightRig.of(root)
	assert_bool(rig.active()).is_true()
	assert_bool(rig.shadows()).is_false()
	assert_int(rig.lanterns.size()).is_greater(0)


## The owner's ruling, as an assertion: the music drives the lights and cannot touch the dark.
##
## The same floor is driven through the calmest measured track and the loudest one. The dark the
## rig draws has to be the *same number* to within float noise - there is no ambient lever left
## for a mood to reach - while the lanterns standing in it have to burn visibly harder, reach
## visibly further and burn a different colour, because that is where the music went.
##
## Proved by making it fail first: putting `DungeonLight.torch_energy_scale()` back into
## `LightRig._apply_dark()` (the shape the deleted `ambient_level(pal, ambient_energy())` had)
## moves the drawn dark from 0.9400 to 0.9580 between the two tracks and this fails on the first
## assertion, naming both numbers.
func test_the_music_drives_the_lights_and_cannot_touch_the_dark() -> void:
	var root := _floor()
	var rig := LightRig.of(root)
	var lights := Music.lights()
	if lights == null:
		return
	var was: bool = bool(GameState.settings.get("music_lights", true))
	GameState.settings["music_lights"] = true
	lights.set_active(true)
	var readings: Dictionary = {}
	for loud: bool in [false, true]:
		lights.set_mood(MusicMood.for_file(MusicMood.extreme_file(loud), "fixture"))
		for _i in range(8):
			lights.step(1.0, 0.5)
		rig._process(1.0 / 60.0)
		readings[loud] = {
			"dark": rig.darkness_strength(),
			"energy": rig.lantern_energy() * rig.mood_energy(),
			"reach": rig.lantern_reach(),
			"color": rig.light_color_for(&"heat"),
		}
	GameState.settings["music_lights"] = was
	lights.set_active(false)
	var calm: Dictionary = readings[false]
	var loud_r: Dictionary = readings[true]
	(
		assert_float(absf(float(loud_r["dark"]) - float(calm["dark"])))
		. override_failure_message(
			(
				(
					"the dark is %.4f under the calmest track and %.4f under the loudest: the "
					+ "music is lighting the room instead of lighting the torches in it"
				)
				% [float(calm["dark"]), float(loud_r["dark"])]
			)
		)
		. is_less_equal(MOOD_DARK_BOUND)
	)
	# ...and it did reach the lights, or the assertion above is only measuring silence.
	(
		assert_float(float(loud_r["energy"]) / maxf(float(calm["energy"]), 0.0001))
		. override_failure_message(
			(
				"a loud track burns the lanterns at x%.3f of a calm one - the mood reaches nothing"
				% (float(loud_r["energy"]) / maxf(float(calm["energy"]), 0.0001))
			)
		)
		. is_greater_equal(1.25)
	)
	assert_float(float(loud_r["reach"])).is_greater(float(calm["reach"]))
	assert_bool((loud_r["color"] as Color).is_equal_approx(calm["color"] as Color)).is_false()


## Rooms nobody has entered stand under a shade; the room the player walks into loses it.
func test_unexplored_rooms_are_shaded_until_entered() -> void:
	var root := _floor()
	var rig := LightRig.of(root)
	var shaded := rig.shaded_room_ids()
	assert_int(shaded.size()).is_equal(root.rooms.size())
	EventBus.room_entered.emit(1)
	await get_tree().process_frame
	assert_bool(rig.shaded_room_ids().has(1)).is_false()
	assert_int(rig.shaded_room_ids().size()).is_equal(root.rooms.size() - 1)
	# A room marked visited by a restore (no signal) loses it on the next poll.
	root.rooms[2].visited = true
	rig._process(1.0)
	assert_bool(rig.shaded_room_ids().has(2)).is_false()


## A door torch's light is moved off the wall's occluder core, like a lantern's, wherever the
## wall has an open face; a torch on a corner cell with none never casts a shadow (a light
## inside a closed occluder lights nothing), so every shadow caster is outside every core.
func test_door_torch_lights_sit_outside_their_wall_core_or_never_cast() -> void:
	var root := _floor()
	var rig := LightRig.of(root)
	assert_int(root.torch_lights().size()).is_greater(0)
	var moved := 0
	for light: PointLight2D in root.torch_lights():
		var torch := light.get_parent() as Node2D
		var tile := FloorRoot.tile_of(torch.position)
		var open := tile + Vector2i(LightRig.facing_of(root.data, tile))
		if root.data.is_walkable(open.x, open.y):
			moved += 1
			assert_bool(rig.inside_wall(light.global_position - root.global_position)).is_false()
	assert_int(moved).is_greater(0)
	rig._process(1.0)
	for light: Light2D in rig.shadow_casters():
		(
			assert_bool(rig.inside_wall(light.global_position - root.global_position))
			. override_failure_message("%s casts from inside a wall" % light.get_path())
			. is_false()
		)


## The player and every enemy stand on a shadow blob, once.
func test_bodies_stand_on_one_shadow_blob() -> void:
	var player := RoomsTestFixtures.make_player()
	add_child(player)
	var root := _floor()
	var rig := LightRig.of(root)
	assert_bool(LightRig.has_blob(player)).is_true()
	var enemy := Node2D.new()
	enemy.name = "Enemy"
	var bar := Node2D.new()
	bar.name = "HpBar"
	var bar_label := Label.new()
	bar.add_child(bar_label)
	enemy.add_child(bar)
	root.add_child(enemy)
	EventBus.enemy_spawned.emit(enemy)
	assert_bool(LightRig.has_blob(enemy)).is_true()
	# The tells are out of every light's reach, so the darkness never dims a health bar or an
	# alert mark.
	assert_int(bar.light_mask).is_equal(LightRig.TELL_MASK)
	assert_int(bar_label.light_mask).is_equal(LightRig.TELL_MASK)
	EventBus.enemy_spawned.emit(enemy)
	var blobs := 0
	for child: Node in enemy.get_children():
		if child.name == LightRig.BLOB_NAME:
			blobs += 1
	assert_int(blobs).is_equal(1)
	assert_int(enemy.get_child(0).name.length()).is_equal(LightRig.BLOB_NAME.length())
	rig.add_blob(enemy)
	# ...and one set of motes, which are the enemy's own light (`EntitySparks`): the blob, the
	# motes and the health bar it was given, and a second spawn adds none of them twice.
	var sparks := 0
	for child: Node in enemy.get_children():
		if child is EntitySparks:
			sparks += 1
	assert_int(sparks).is_equal(1)
	rig.add_sparks(enemy)
	assert_int(enemy.get_child_count()).is_equal(3)
	player.free()


## Clearing the floor takes the rig, its lanterns and every emitter with it, and the static
## current rig is gone: nothing to leak, nothing to answer a late attach.
func test_clearing_the_floor_leaves_no_light_behind() -> void:
	var root := _floor()
	var rig := LightRig.of(root)
	var e := LightEmitter.attach(root.stairs, &"fire")
	assert_object(e).is_not_null()
	assert_int(rig.emitters.size()).is_greater(0)
	root.clear_floor()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_object(LightRig.of(root)).is_null()
	assert_object(LightRig.current()).is_null()
	assert_bool(is_instance_valid(rig)).is_false()
	assert_bool(is_instance_valid(e)).is_false()
	var stray := Node2D.new()
	add_child(stray)
	assert_object(LightEmitter.attach(stray, &"fire")).is_null()
	stray.free()


## The four numbers `lighting_frame` judges a drawn floor by, bounded by literals.
##
## That capture is the lighting layer's only rendered proof, and its verdict is a comparison
## against its own constants, so moving one of them moves the verdict with it. The mechanism has
## teeth - taking `unlit_floor` to 0.30 fails the unlit ceiling, and running the player's pool at
## full energy on a paper floor fails the light ceiling - but nothing stops the lines themselves
## being widened until nothing can fail.
##
## A floor, two ceilings and a radius, and the pair that matters most is the new one: how far the
## player's own pool has to stand off the dark, and how much of the theme's floor unlit ground may
## keep. Either alone is satisfiable by the thing the owner deleted - a wash passes any brightness
## floor, and a black screen passes any darkness ceiling - so they are bounded together.
func test_the_lighting_frame_lines_are_guarantees_not_variables() -> void:
	(
		assert_float(LightingFrameCapture.PLAYER_POOL_MIN)
		. override_failure_message(
			(
				(
					"PLAYER_POOL_MIN is x%.2f: under x1.4 the light the player is carrying is "
					+ "not what they are seeing by, and a dark room stops being playable"
				)
				% LightingFrameCapture.PLAYER_POOL_MIN
			)
		)
		. is_greater_equal(1.4)
	)
	(
		assert_float(LightingFrameCapture.UNLIT_SHARE)
		. override_failure_message(
			(
				(
					"UNLIT_SHARE is %.2f: it is the ceiling on unlit ground, and past a fifth of "
					+ "the theme's own floor the dark is an ambient wash with a smaller number - "
					+ "which is exactly what this round deleted"
				)
				% LightingFrameCapture.UNLIT_SHARE
			)
		)
		. is_less_equal(0.20)
	)
	(
		assert_float(LightingFrameCapture.FIGHT_RADIUS)
		. override_failure_message(
			(
				(
					"FIGHT_RADIUS is %.0f px: over four tiles it stops being 'what the player is "
					+ "fighting' and becomes 'the room', and most of the room is meant to be dark"
				)
				% LightingFrameCapture.FIGHT_RADIUS
			)
		)
		. is_less_equal(64.0)
	)
	(
		assert_float(LightingFrameCapture.POOL_RESTORE_MAX)
		. override_failure_message(
			(
				(
					"POOL_RESTORE_MAX is x%.2f: it is a ceiling, and raising it lets a pool push "
					+ "a floor past the level the room's own tile material authored it at, which "
					+ "is light erasing detail rather than restoring it"
				)
				% LightingFrameCapture.POOL_RESTORE_MAX
			)
		)
		. is_less_equal(1.25)
	)


## The shadow rule's two numbers. It is "a shadow dims the floor, it never blacks it out", and
## each of them can be moved until it says nothing: drop the fraction toward zero and a real
## shadow passes, or shrink the window until only one floor tile falls inside it and nothing
## can fail. The window is wide on purpose now, because the falloff at each tile's own distance
## is divided back out before anything is compared (`LightingFrameCapture._shadow_profile`) -
## which is what lets the window be honest and wide at the same time.
func test_the_shadow_rule_measures_a_real_sample_of_the_lit_floor() -> void:
	var share := LightingFrameCapture.SHADOW_SEARCH_SHARE
	(
		assert_float(share)
		. override_failure_message(
			(
				(
					"SHADOW_SEARCH_SHARE is %.2f of a pool's radius: under half of it the "
					+ "window holds a tile or two and the rule cannot fail"
				)
				% share
			)
		)
		. is_greater_equal(0.5)
	)
	assert_float(share).is_less_equal(1.0)
	(
		assert_int(LightingFrameCapture.SHADOW_MIN_TILES)
		. override_failure_message(
			(
				(
					"SHADOW_MIN_TILES is %d: a darkest-against-the-mean reading taken on fewer than "
					+ "four tiles is a reading of one tile against itself"
				)
				% LightingFrameCapture.SHADOW_MIN_TILES
			)
		)
		. is_greater_equal(4)
	)
	(
		assert_float(LightingFrameCapture.SHADOW_FLOOR_FRACTION)
		. override_failure_message(
			(
				(
					"SHADOW_FLOOR_FRACTION is %.2f: under 0.3 a shadow may take the floor under it "
					+ "to nearly nothing and still pass"
				)
				% LightingFrameCapture.SHADOW_FLOOR_FRACTION
			)
		)
		. is_greater_equal(0.3)
	)


## The percentile the ceiling is read at. Taking it to 1.0 would read the single brightest pixel
## in the frame - an antialiased torch edge - and the ceiling would fire on a floor that is fine;
## taking it much lower would read past the lit part of the tile and stop firing at all.
func test_the_ceiling_is_read_off_the_lit_part_of_a_tile() -> void:
	assert_float(LightingFrameCapture.CEILING_PERCENTILE).is_between(0.95, 0.995)


## The two numbers the owner's ruling turns on, pinned against the reasoning that chose them,
## so no later tuning pass can walk the room back to an even wash.
##
## `unlit_floor` is a *ceiling*: it is what a surface keeps of itself where nothing is lighting
## it, and past a twentieth of its colour that stops being "dark" and becomes an ambient level
## with a smaller number - which is the state the owner deleted rather than dimmed, in the words
## "THERE SHOULD BE NO OTHER LIGHT OTHER THAN PARTICLE EFFECTS, TORCHES ETC". `lantern_energy` is
## pinned to the complement exactly - the pool is the dark undone and never more - which is the
## invariant the readable-prop ladders have depended on since the layer was written. The sum is
## the assertion; each half on its own would let the pair drift apart.
##
## Proved by making it fail first: at the shipped-before-this-round `unlit_floor` of 0.32 the
## first assertion fails naming 0.320, and at a `lantern_energy` of 0.68 against a 0.06 dark the
## pocket assertion fails naming x12.3 - a pool that does not reach the level the theme authored.
func test_the_pool_is_the_dark_exactly_undone_and_the_dark_is_deep() -> void:
	var profile := LightingProfile.resolve()
	(
		assert_float(profile.unlit_floor)
		. override_failure_message(
			(
				(
					"unlit_floor is %.3f: a surface that keeps more than a twentieth of itself "
					+ "with nothing lighting it is an ambient wash under another name, and no "
					+ "pool laid on top of it can be the thing the player sees"
				)
				% profile.unlit_floor
			)
		)
		. is_less_equal(0.05001 * 1.2)
	)
	# ...and not zero either: the frame would band to flat black and take the room's shape with
	# it. One code point of an eight-bit channel is the floor under the floor.
	(
		assert_float(profile.unlit_floor)
		. override_failure_message(
			(
				"unlit_floor is %.3f: at zero an unlit room is not dark, it is absent"
				% profile.unlit_floor
			)
		)
		. is_greater(0.0)
	)
	(
		assert_float(profile.unlit_floor + profile.lantern_energy)
		. override_failure_message(
			(
				(
					"dark %.3f + lantern pool %.3f is %.3f, over 1: a pool that restores a "
					+ "surface past the level it was authored at is light the readability "
					+ "ladders were never measured under"
				)
				% [
					profile.unlit_floor,
					profile.lantern_energy,
					profile.unlit_floor + profile.lantern_energy
				]
			)
		)
		. is_less_equal(1.005)
	)
	# ...and the pool reaches that level rather than stopping short of it: the pocket is the
	# whole of the difference between a lit floor and an unlit one, so it has to be all of it.
	(
		assert_float(profile.unlit_floor + profile.lantern_energy)
		. override_failure_message(
			(
				(
					"a lantern's pool restores a surface to x%.3f of the level the theme "
					+ "authored it at; under 0.95 the lit floor is dim as well as the unlit one "
					+ "and the theme never reaches the screen at full"
				)
				% (profile.unlit_floor + profile.lantern_energy)
			)
		)
		. is_greater_equal(0.95)
	)
	# The same invariant on the door torches, which are the other half of the room's light.
	var light := DungeonLight.resolve()
	assert_float(profile.unlit_floor + light.torch_energy).is_between(0.95, 1.005)


## A body takes exactly the dark the floor it stands on takes, and one pool undoes both.
##
## It did not, for a round: `prop_exposure_power` left a crate at x0.85 of itself over a floor
## at x0.32, which is what made a prop readable in an unlit room. At a floor this dark the same
## exponent would put every prop, chest and enemy in the dungeon at x0.65 with nothing lighting
## them, which is the ambient wash the owner deleted wearing a crate's clothes - so the exponent
## is gone and the second light every lantern carried to undo it is gone with it.
##
## Proved by making it fail first: restoring the exponent (`pow(unlit, 0.144)` for the body mask)
## puts the body dark at 0.351 against the floor's 0.940 and both assertions below fail.
func test_a_body_takes_the_same_dark_as_the_floor_it_stands_on() -> void:
	var root := _floor()
	var rig := LightRig.of(root)
	# One dark light, reaching the environment and the bodies alike.
	var darks := 0
	for child: Node in rig.get_children():
		if child is PointLight2D and (child as PointLight2D).blend_mode == Light2D.BLEND_MODE_MIX:
			if (child as PointLight2D).name.begins_with("Darkness"):
				darks += 1
	(
		assert_int(darks)
		. override_failure_message(
			(
				(
					"the rig carries %d full-floor dark lights; a second one is how a body gets a "
					+ "gentler dark than the floor, which is an ambient wash for bodies"
				)
				% darks
			)
		)
		. is_equal(1)
	)
	assert_int(rig.darkness.range_item_cull_mask).is_equal(LightRig.LIT_MASK)
	# ...and one pool per lantern, on the same mask.
	for lantern: WallLantern in rig.lanterns:
		var pools := 0
		for child: Node in lantern.get_children():
			if child is PointLight2D:
				pools += 1
		(
			assert_int(pools)
			. override_failure_message(
				"lantern %s carries %d lights; one dark needs one pool" % [lantern.tile, pools]
			)
			. is_equal(1)
		)
		assert_int(lantern.light.range_item_cull_mask).is_equal(LightRig.LIT_MASK)


## A light ends somewhere a person can see it end. The pool is drawn with one shared radial
## texture whose alpha falls as `(1 - t) ^ DungeonLight.FALLOFF_POWER`; on a linear ramp - what
## it was - the faint outer half of the gradient is still a large relative lift over a floor at
## a third of its light, so every lantern threw a halo most of a room wide and six of them
## washed the room back to even. The power is what makes a pool a pool rather than a haze.
func test_a_light_pool_has_an_edge_rather_than_a_haze() -> void:
	(
		assert_float(DungeonLight.FALLOFF_POWER)
		. override_failure_message(
			(
				(
					"FALLOFF_POWER is %.2f: under 2 the pool's tail is a wide haze, the pools "
					+ "of one room reach each other and the room is evenly lit again"
				)
				% DungeonLight.FALLOFF_POWER
			)
		)
		. is_greater_equal(2.0)
	)
	var texture := DungeonLight.make_texture(96) as GradientTexture2D
	assert_object(texture).is_not_null()
	var gradient := texture.gradient
	# Half way out the pool keeps at most a quarter of its centre, and three quarters of the
	# way out at most a twentieth: an edge, not a slope that runs to the far wall.
	assert_float(gradient.sample(0.5).a).is_less_equal(0.25)
	assert_float(gradient.sample(0.75).a).is_less_equal(0.05)
	assert_float(gradient.sample(0.0).a).is_equal_approx(1.0, 0.001)
	assert_float(gradient.sample(1.0).a).is_equal_approx(0.0, 0.001)


## A room is lit in pockets: enough lanterns to find the door, few enough that there is dark
## between them.
##
## Both halves are the owner's, in that order. The round before this one was told to hang fewer
## torches, and it was told that while an ambient wash was lighting the room anyway; with the
## wash gone the instruction is "torches are the light, so put as many as the room needs and no
## more". So the spacing has a floor as well as a ceiling now: under five tiles a wall is a
## continuous strip of light and the pockets close up, and over twelve an ordinary room takes one
## lantern and the player cannot find the door it is standing beside.
##
## Proved by making it fail first: at the previous round's spacings (crypt 14, void 18) the
## ceiling assertion fails naming the biome, and at a spacing of 4 the floor assertion does.
func test_a_room_is_lit_in_pockets_not_ringed_and_not_in_one_spot() -> void:
	for id: StringName in Biome.ALL_IDS:
		var spacing := Biome.load_by_id(id).lantern_spacing
		(
			assert_int(spacing)
			. override_failure_message(
				(
					(
						"biome %s spaces its lanterns every %d tiles; under 5 a wall is a strip of"
						+ " light and the pockets close up"
					)
					% [id, spacing]
				)
			)
			. is_greater_equal(5)
		)
		(
			assert_int(spacing)
			. override_failure_message(
				(
					(
						"biome %s spaces its lanterns every %d tiles; over 12 an ordinary room "
						+ "takes one lantern, and with nothing else lighting it the rest of the "
						+ "room - the door included - is not there"
					)
					% [id, spacing]
				)
			)
			. is_less_equal(12)
		)
	var root := _floor()
	var rig := LightRig.of(root)
	for room: RoomNode in root.rooms:
		if room.data == null:
			continue
		var here := 0
		for lantern: WallLantern in rig.lanterns:
			if room.data.rect.grow(1).has_point(lantern.tile):
				here += 1
		(
			assert_int(here)
			. override_failure_message(
				(
					"room %d hangs %d lanterns on its ring: that is a lit ring, not a pocket"
					% [room.id, here]
				)
			)
			. is_less_equal(6)
		)
