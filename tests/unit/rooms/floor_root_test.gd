class_name FloorRootTest
extends GdUnitTestSuite

## Methods the already-written integrator (src/game.gd, src/core/run_manager.gd) calls on
## FloorRoot. Scanned from those sources so the contract cannot silently drift again.
const CONSUMERS: Array[String] = ["res://src/game.gd", "res://src/core/run_manager.gd"]

var _root: FloorRoot
var _cleared: Array[int] = []
var _on_cleared: Callable


func before_test() -> void:
	_cleared.clear()
	_on_cleared = func(id: int) -> void: _cleared.append(id)
	EventBus.room_cleared.connect(_on_cleared)
	_root = auto_free(FloorRoot.new())
	add_child(_root)
	_root.build_from_path(RoomsTestFixtures.three_rooms(), RoomsTestFixtures.ATLAS)


func after_test() -> void:
	EventBus.room_cleared.disconnect(_on_cleared)


func _settle(frames: int = 3) -> void:
	for _i in range(frames):
		await get_tree().physics_frame


func test_integrator_api_exists() -> void:
	var re := RegEx.new()
	re.compile("floor_root\\.([a-zA-Z_][a-zA-Z0-9_]*)\\(")
	var checked := 0
	for path: String in CONSUMERS:
		if not FileAccess.file_exists(path):
			continue
		var src := FileAccess.get_file_as_string(path)
		for m: RegExMatch in re.search_all(src):
			var method := m.get_string(1)
			checked += 1
			(
				assert_bool(_root.has_method(method))
				. override_failure_message(
					"FloorRoot is missing %s(), called in %s" % [method, path]
				)
				. is_true()
			)
	assert_int(checked).is_greater(0)


func test_game_scene_script_compiles() -> void:
	# Guards the FloorRoot <-> Game contract end to end. A failure here means src/game.gd
	# (or something it preloads) no longer compiles -- check the reported parse error first.
	var script: Script = load("res://src/game.gd")
	assert_object(script).is_not_null()
	assert_bool(script.can_instantiate()).is_true()


func test_rebuild_is_clean() -> void:
	var layers_before := _root.built_layers.all_layers().size()
	var children_before := _root.get_child_count()
	_root.build_from_path(RoomsTestFixtures.three_rooms(), RoomsTestFixtures.ATLAS)
	await _settle(2)
	assert_int(_root.rooms.size()).is_equal(3)
	assert_int(_root.props.size()).is_equal(1)
	assert_int(_root.built_layers.all_layers().size()).is_equal(layers_before)
	assert_int(_root.get_child_count()).is_equal(children_before)
	assert_object(_root.stairs).is_not_null()
	assert_bool(_root.stairs.is_inside_tree()).is_true()
	assert_array(_cleared).is_empty()


func test_teardown_does_not_fake_a_clear() -> void:
	var room := _root.get_room(1)
	var enemies: Array[Node2D] = []
	for _i in range(2):
		var e := Entity.new()
		e.team = Layers.Team.ENEMY
		enemies.append(e)
	room.populate(enemies)
	assert_int(room.pending_enemy_count()).is_equal(2)
	assert_object(enemies[0].get_parent()).is_same(room)
	_root.clear_floor()
	await _settle(3)
	assert_array(_cleared).is_empty()
	assert_int(_root.rooms.size()).is_equal(0)


func test_queue_free_teardown_does_not_fake_a_clear() -> void:
	var other := FloorRoot.new()
	add_child(other)
	other.build_from_path(RoomsTestFixtures.three_rooms(), RoomsTestFixtures.ATLAS)
	var room := other.get_room(1)
	var enemies: Array[Node2D] = []
	for _i in range(2):
		var e := Entity.new()
		e.team = Layers.Team.ENEMY
		enemies.append(e)
	room.populate(enemies)
	other.queue_free()
	await _settle(4)
	assert_array(_cleared).is_empty()


func test_minimap_after_clear_floor() -> void:
	var model := _root.minimap()
	assert_int((model["rooms"] as Array).size()).is_equal(3)
	assert_int((model["edges"] as Array).size()).is_equal(2)
	# One drawn route per edge: the widget pairs them by index.
	assert_int((model["links"] as Array).size()).is_equal(2)
	_root.clear_floor()
	await _settle(2)
	assert_array(_root.minimap_rooms()).is_empty()
	assert_array(_root.minimap_edges()).is_empty()
	assert_array(_root.minimap_links()).is_empty()
	assert_array(_root.cleared_ids()).is_empty()
	var empty := _root.minimap()
	assert_int((empty["rooms"] as Array).size()).is_equal(0)


func test_props_use_generator_kinds() -> void:
	assert_int(_root.props.size()).is_equal(1)
	var prop := _root.props[0]
	assert_str(String(prop.kind)).is_equal("coffin")
	assert_int(prop.hp).is_equal(2)


func test_palette_change_retints_every_layer() -> void:
	var mats: Array[ShaderMaterial] = []
	for entry: Dictionary in _root.built_layers.materials:
		mats.append(entry["material"] as ShaderMaterial)
	assert_int(mats.size()).is_equal(2)
	var before: Array[PackedColorArray] = []
	for mat: ShaderMaterial in mats:
		before.append(mat.get_shader_parameter(&"target_colors") as PackedColorArray)
	var palette := ThemePalette.fallback()
	palette.colors["floor"] = Color(0.9, 0.2, 0.6)
	EventBus.palette_changed.emit(palette)
	for i in range(mats.size()):
		assert_float(float(mats[i].get_shader_parameter(&"blend"))).is_equal(0.0)
		var after := mats[i].get_shader_parameter(&"target_colors") as PackedColorArray
		assert_that(after[3]).is_not_equal(before[i][3])


func test_retint_mid_crossfade_starts_from_what_is_shown() -> void:
	var mat := _root.built_layers.ground.material as ShaderMaterial
	var first := ThemePalette.fallback()
	first.colors["floor"] = Color(1.0, 0.0, 0.0)
	TileRamp.retint(mat, first, TileRamp.Variant.BASE, 1, _root)
	mat.set_shader_parameter(&"blend", 0.5)
	var shown := TileRamp.current_colors(mat)
	var second := ThemePalette.fallback()
	second.colors["floor"] = Color(0.0, 0.0, 1.0)
	TileRamp.retint(mat, second, TileRamp.Variant.BASE, 1, _root)
	var previous := mat.get_shader_parameter(&"previous_colors") as PackedColorArray
	assert_that(previous[3]).is_equal(shown[3])
	assert_float(float(mat.get_shader_parameter(&"blend"))).is_equal(0.0)


func test_add_enemy_routes_into_the_room() -> void:
	var enemy: Entity = auto_free(Entity.new())
	enemy.team = Layers.Team.ENEMY
	_root.add_enemy(enemy, 1)
	var room := _root.get_room(1)
	assert_int(room.pending_enemy_count()).is_equal(1)
	assert_object(enemy.get_parent()).is_same(room)


func test_shops_list_and_stock() -> void:
	assert_array(_root.get_shops()).is_empty()
	var shop: Shop = auto_free(Shop.new())
	add_child(shop)
	var offers: Array = [RefCounted.new(), RefCounted.new()]
	shop.stock(offers, 40)
	assert_int(shop.offers.size()).is_equal(2)
	assert_int(shop.prices.size()).is_equal(2)
	for price: int in shop.prices:
		assert_int(price).is_greater(0)


func test_nav_excludes_prop_tiles() -> void:
	var data := RoomsTestFixtures.three_rooms()
	var open_poly := FloorRoot.build_nav_polygon(data)
	var carved := FloorRoot.build_nav_polygon(data, {Vector2i(12, 2): true})
	assert_int(open_poly.get_polygon_count()).is_greater(0)
	assert_int(carved.get_polygon_count()).is_greater(0)
	assert_bool(carved.get_vertices() == open_poly.get_vertices()).is_false()
	# The floor the root baked carved out its own props.
	(
		assert_bool(_root.nav_region.navigation_polygon.get_vertices() == carved.get_vertices())
		. is_true()
	)


func test_atlas_path_prefers_biome_tileset_path() -> void:
	var data := RoomsTestFixtures.three_rooms()
	var biome := Biome.new()
	biome.id = &"crypt"
	biome.tileset_path = "res://assets/tiles/forge.png"
	assert_str(FloorRoot.atlas_path_for_biome(data, biome)).is_equal("res://assets/tiles/forge.png")
	assert_str(FloorRoot.atlas_path_for_biome(data, null)).is_equal("res://assets/tiles/crypt.png")


## The floor is the only thing that can remember a broken prop: the prop frees itself. Docs §12
## rebuilds the floor from the seed on resume, so without this the same barrel pays the same
## (seed, tile, floor)-deterministic coins on every Save & Quit -> Continue.
func test_a_broken_prop_is_remembered_for_the_save() -> void:
	assert_int(_root.props.size()).is_equal(1)
	var prop := _root.props[0]
	var tile := FloorRoot.tile_of(prop.position)
	assert_that(tile).is_equal(Vector2i(12, 2))
	assert_array(_root.broken_prop_tiles()).is_empty()
	var info := DamageInfo.create(10.0, [DamageInfo.TAG_MELEE], null, Layers.Team.PLAYER)
	prop.take_hit(info)  # coffin: sturdy, two hits
	prop.take_hit(info)
	assert_bool(prop.is_broken).is_true()
	assert_array(_root.broken_prop_tiles()).contains([tile])
	(
		assert_int(_root.props.size())
		. override_failure_message("a broken prop is still counted as standing")
		. is_equal(0)
	)


## The replay half, on a freshly rebuilt floor: the prop goes straight to broken, pays nothing,
## and the tile stays in the list so the *next* save still carries it.
func test_restoring_a_broken_prop_pays_nothing_and_stays_recorded() -> void:
	var probe := EventBusProbe.new()
	var drops: Array = []
	probe.watch(
		EventBus.spawn_pickup,
		func(kind: StringName, _pos: Vector2, _amount: int) -> void: drops.append(kind)
	)
	var tile := Vector2i(12, 2)
	assert_int(_root.restore_broken_props([tile] as Array[Vector2i])).is_equal(1)
	assert_int(_root.props.size()).is_equal(0)
	assert_array(drops).is_empty()
	assert_array(_root.broken_prop_tiles()).contains([tile])
	# A tile with nothing on it any more is skipped rather than invented.
	assert_int(_root.restore_broken_props([tile] as Array[Vector2i])).is_equal(0)
	assert_int(_root.restore_broken_props([] as Array[Vector2i])).is_equal(0)
	probe.release()


## The property the prop fix must not break: a prop the player has *not* touched is still a
## prop. An over-eager replay that swept every tile in the room would "close the farm" by
## deleting the floor's set dressing, and the gate would still be green.
func test_props_the_player_never_touched_survive_the_replay() -> void:
	assert_int(_root.props.size()).is_equal(1)
	(
		assert_int(_root.restore_broken_props([Vector2i(3, 3), Vector2i(15, 3)] as Array[Vector2i]))
		. is_equal(0)
	)
	assert_int(_root.props.size()).is_equal(1)
	assert_bool(_root.props[0].is_broken).is_false()
	assert_array(_root.broken_prop_tiles()).is_empty()


## Mimic chests are the same shape as props: the decoy frees itself when it is sprung, so the
## floor is the only thing left that can remember it. A floor with none of them must say so
## rather than guess.
func test_mimic_bookkeeping_is_empty_on_a_floor_without_mimics() -> void:
	_root.watch_mimics()
	assert_array(_root.mimic_chests()).is_empty()
	assert_array(_root.revealed_mimic_tiles()).is_empty()
	assert_int(_root.restore_revealed_mimics([Vector2i(12, 2)] as Array[Vector2i])).is_equal(0)


## Springing a mimic is recorded, and a resume removes the decoy instead of re-arming it —
## otherwise the enemy it turns into pays its gold, heart and elite drop on every cycle of
## Save & Quit -> Continue. `TrapPlacer` parents traps straight to the floor root, which is
## how the floor can see them at all.
func test_a_sprung_mimic_is_recorded_and_not_re_armed_on_resume() -> void:
	var probe := EventBusProbe.new()
	var requested: Array[StringName] = []
	probe.watch(
		EventBus.spawn_enemy_requested,
		func(id: StringName, _pos: Vector2) -> void: requested.append(id)
	)
	var tile := Vector2i(13, 3)
	var mimic := MimicChest.new()
	_root.add_child(mimic)
	mimic.position = (Vector2(tile) + Vector2(0.5, 0.5)) * float(Layers.TILE)
	assert_int(_root.mimic_chests().size()).is_equal(1)
	_root.watch_mimics()
	_root.watch_mimics()  # idempotent: a second call must not double-connect

	assert_bool(mimic.interact()).is_true()
	assert_int(requested.size()).is_equal(1)
	assert_array(_root.revealed_mimic_tiles()).is_equal([tile] as Array[Vector2i])
	await get_tree().process_frame

	# The rebuilt floor: the decoy is back, and the replay has to take it away again.
	var rebuilt := MimicChest.new()
	_root.add_child(rebuilt)
	rebuilt.position = (Vector2(tile) + Vector2(0.5, 0.5)) * float(Layers.TILE)
	assert_int(_root.restore_revealed_mimics([tile] as Array[Vector2i])).is_equal(1)
	await get_tree().process_frame
	assert_array(_root.mimic_chests()).is_empty()
	(
		assert_int(requested.size())
		. override_failure_message("the replay re-sprang the mimic instead of removing it")
		. is_equal(1)
	)
	probe.release()
