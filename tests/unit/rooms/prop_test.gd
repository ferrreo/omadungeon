class_name PropTest
extends GdUnitTestSuite

const CELL := Layers.TILE
## The atlas row a solid prop's contact shadow sits on (`tools/art/props.py::SHADOW_ROW`): the
## last row inside the border ring. Ink there is what says "this stands on a base".
const SHADOW_ROW := CELL - 2
const SHADOW_MIN := 4
## A flat prop starts on or below this row, a solid one on or above it (`props.py::FLAT_TOP`).
const FLAT_TOP := 4
const SOLID_JSON := "res://tools/art/prop_solid.json"
## Fewest ink pixels a solid prop wears (`props.py::INK_MIN`): the outline. A flat wears none.
const INK_MIN := 12
## Atlas columns of the four kinds every biome shares (`Prop.SHARED`).
const BARREL := 0
const CRATE := 1
## Crypt column of the coffin, the first of the biome's own five.
const COFFIN := 4
## Frames a body is pushed at a prop before its position is read.
const PUSH_FRAMES := 30
const PUSH_SPEED := 240.0


func _hit(prop: Prop) -> void:
	var info := DamageInfo.create(10.0, [DamageInfo.TAG_MELEE], null, Layers.Team.PLAYER)
	info.with_knockback(Vector2.RIGHT, 40.0)
	prop.take_hit(info)


func test_breaks_and_may_drop_gold() -> void:
	var drops: Array = []
	var cb := func(kind: StringName, pos: Vector2, amount: int) -> void:
		drops.append([kind, pos, amount])
	EventBus.spawn_pickup.connect(cb)
	var rng := RandomNumberGenerator.new()
	# Find a seed whose first randf() is below the gold chance so the drop path is exercised.
	var seed_value := 0
	while true:
		rng.seed = seed_value
		if rng.randf() < Prop.GOLD_CHANCE:
			break
		seed_value += 1
	rng.seed = seed_value
	var prop: Prop = auto_free(Prop.new())
	prop.setup(&"crypt", BARREL, null, rng, Color.WHITE)  # barrel: one hit
	prop.position = Vector2(50, 50)
	add_child(prop)
	assert_int(prop.collision_layer).is_equal(Layers.PROP)
	assert_str(String(prop.kind)).is_equal("barrel")
	var broken: Array[Prop] = []
	prop.broken.connect(func(p: Prop) -> void: broken.append(p))
	_hit(prop)
	assert_bool(prop.is_broken).is_true()
	assert_int(prop.collision_layer).is_equal(0)
	assert_bool(prop.sprite.visible).is_true()
	assert_that(prop.sprite.region_rect).is_equal(FloorBuilder.atlas_cell(BARREL, Prop.DEBRIS_ROW))
	assert_int(broken.size()).is_equal(1)
	assert_int(drops.size()).is_equal(1)
	assert_str(String(drops[0][0])).is_equal("gold")
	assert_that(drops[0][1]).is_equal(Vector2(50, 50))
	assert_int(int(drops[0][2])).is_between(1, 3)
	_hit(prop)  # already broken: no double drop
	assert_int(drops.size()).is_equal(1)
	EventBus.spawn_pickup.disconnect(cb)


func test_sturdy_prop_takes_two_hits() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var prop: Prop = auto_free(Prop.new())
	prop.setup(&"crypt", COFFIN, null, rng, Color.WHITE)
	assert_str(String(prop.kind)).is_equal("coffin")
	add_child(prop)
	assert_int(prop.hp).is_equal(2)
	_hit(prop)
	assert_bool(prop.is_broken).is_false()
	_hit(prop)
	assert_bool(prop.is_broken).is_true()


func test_kinds_per_biome() -> void:
	for biome: StringName in Prop.KINDS:
		assert_int((Prop.KINDS[biome] as Array).size()).is_equal(Prop.KIND_COUNT)
	var rng := RandomNumberGenerator.new()
	var prop: Prop = auto_free(Prop.new())
	prop.setup(&"void", Prop.KIND_COUNT + CRATE, null, rng, Color.WHITE)
	assert_int(prop.kind_index).is_equal(CRATE)
	assert_str(String(prop.kind)).is_equal("crate")


## The shared kinds sit in the same four columns of every sheet, so a barrel is column 0
## wherever the player meets it, and each biome adds six kinds of its own after them.
func test_every_biome_shares_the_first_four_columns() -> void:
	for biome: StringName in Biome.ALL_IDS:
		var names: Array = Prop.kind_names(biome)
		assert_int(names.size()).is_equal(Prop.KIND_COUNT)
		for i in range(Prop.SHARED.size()):
			assert_str(String(names[i])).override_failure_message(biome).is_equal(
				String(Prop.SHARED[i])
			)
		var own: Dictionary = {}
		for name: Variant in names:
			own[name] = true
		assert_int(own.size()).override_failure_message("%s repeats a kind" % biome).is_equal(
			Prop.KIND_COUNT
		)


## Resume replay (docs §12). A prop the player already smashed goes back to broken without
## paying for it a second time: `Prop` rolls its gold from a stream derived from (run seed,
## tile, floor index), so it is the *same* coins every rebuild, and a re-break on every
## Save & Quit -> Continue would be an exactly repeatable gold source.
##
## The seed is chosen so a live break *would* have paid, which is what gives this teeth: the
## assertion is "nothing was emitted", and nothing is also what a broken prop emits.
func test_restore_broken_replays_the_break_without_paying_for_it() -> void:
	var probe := EventBusProbe.new()
	var drops: Array = []
	probe.watch(
		EventBus.spawn_pickup,
		func(kind: StringName, _pos: Vector2, _amount: int) -> void: drops.append(kind)
	)
	var rng := RandomNumberGenerator.new()
	var seed_value := 0
	while true:
		rng.seed = seed_value
		if rng.randf() < Prop.GOLD_CHANCE:
			break
		seed_value += 1
	rng.seed = seed_value

	var paid: Prop = auto_free(Prop.new())
	paid.setup(&"crypt", BARREL, null, rng, Color.WHITE)
	paid.position = Vector2(48, 48)
	add_child(paid)
	_hit(paid)
	(
		assert_int(drops.size())
		. override_failure_message("the control break paid nothing, so the seed proves nothing")
		. is_equal(1)
	)

	rng.seed = seed_value
	var replayed: Prop = auto_free(Prop.new())
	replayed.setup(&"crypt", BARREL, null, rng, Color.WHITE)
	replayed.position = Vector2(48, 48)
	add_child(replayed)
	var broken: Array[Prop] = []
	replayed.broken.connect(func(p: Prop) -> void: broken.append(p))
	replayed.restore_broken()

	assert_bool(replayed.is_broken).is_true()
	assert_int(replayed.collision_layer).is_equal(0)
	assert_that(replayed.sprite.region_rect).is_equal(
		FloorBuilder.atlas_cell(BARREL, Prop.DEBRIS_ROW)
	)
	(
		assert_int(drops.size())
		. override_failure_message("a resumed floor paid for a prop the player already smashed")
		. is_equal(1)
	)
	assert_array(broken).is_empty()
	replayed.restore_broken()
	assert_int(drops.size()).is_equal(1)
	probe.release()


## Ink pixels on the contact-shadow row of one atlas cell.
static func _shadow_width(img: Image, col: int) -> int:
	var n := 0
	for x in range(CELL):
		var px := img.get_pixel(col * CELL + x, SHADOW_ROW)
		if px.a > 0.5 and TileRamp.index_of(px) == Prop.INK_RUNG:
			n += 1
	return n


## Ink pixels anywhere in one atlas cell (row 0): a solid's outline, a flat's nothing.
static func _ink_count(img: Image, col: int) -> int:
	var n := 0
	for y in range(CELL):
		for x in range(CELL):
			var px := img.get_pixel(col * CELL + x, y)
			if px.a > 0.5 and TileRamp.index_of(px) == Prop.INK_RUNG:
				n += 1
	return n


## First row of one atlas cell holding a drawn pixel, or CELL when it is empty.
static func _top_row(img: Image, col: int, row: int = 0) -> int:
	for y in range(CELL):
		for x in range(CELL):
			if img.get_pixel(col * CELL + x, row * CELL + y).a > 0.5:
				return y
	return CELL


static func _cell_is_empty(img: Image, col: int, row: int) -> bool:
	return _top_row(img, col, row) == CELL


## The rule is one table in four places - `Prop.SOLID`, `rooms_content.tres`, the generator's
## `prop_solid.json` and the drawing itself - and this holds all four together for every kind
## of every biome. The drawing is judged on the shipped PNG: a solid kind stands tall and on a
## contact shadow, a flat kind lies low and never paints that row, and only a solid kind has
## a debris frame to fall to. This is the test that answers "some has collision but others
## don't?? it is very random": a player can read the answer off the sprite, and the sprite
## cannot disagree with the physics.
func test_every_kind_is_solid_or_flat_and_the_art_says_which() -> void:
	var raw := FileAccess.get_file_as_string(SOLID_JSON)
	assert_str(raw).override_failure_message("%s missing" % SOLID_JSON).is_not_empty()
	var authored: Dictionary = JSON.parse_string(raw) as Dictionary
	var content := RoomsContent.load_default()
	assert_object(content).is_not_null()
	assert_bool(content.prop_solid.is_empty()).is_false()
	for biome: StringName in Biome.ALL_IDS:
		var img := Image.load_from_file("%s%s.png" % [Prop.PROPS_DIR, biome])
		assert_object(img).override_failure_message("no prop atlas for %s" % biome).is_not_null()
		var names: Array = Prop.kind_names(biome)
		for col in range(names.size()):
			var kind := StringName(names[col])
			var where := "%s %s" % [biome, kind]
			(
				assert_bool(Prop.SOLID.has(kind))
				. override_failure_message("%s has no Prop.SOLID entry" % where)
				. is_true()
			)
			var solid: bool = Prop.SOLID[kind]
			assert_bool(Prop.is_solid(kind)).override_failure_message(where).is_equal(solid)
			(
				assert_bool(bool(content.prop_solid.get(kind, not solid)))
				. override_failure_message(
					"%s: rooms_content.tres disagrees with Prop.SOLID" % where
				)
				. is_equal(solid)
			)
			(
				assert_bool(bool(authored.get(String(kind), not solid)))
				. override_failure_message("%s: the art was authored the other way" % where)
				. is_equal(solid)
			)
			var shadow := _shadow_width(img, col)
			var top := _top_row(img, col)
			var ink := _ink_count(img, col)
			if solid:
				(
					assert_int(ink)
					. override_failure_message("%s is solid but wears no ink outline" % where)
					. is_greater_equal(INK_MIN)
				)
				(
					assert_int(shadow)
					. override_failure_message(
						"%s is solid but stands on no contact shadow" % where
					)
					. is_greater_equal(SHADOW_MIN)
				)
				(
					assert_int(top)
					. override_failure_message("%s is solid but does not stand tall" % where)
					. is_less_equal(FLAT_TOP)
				)
				(
					assert_bool(_cell_is_empty(img, col, Prop.DEBRIS_ROW))
					. override_failure_message("%s is solid but has no debris frame" % where)
					. is_false()
				)
			else:
				(
					assert_int(ink)
					. override_failure_message(
						"%s is flat but wears ink: that is the solid tell" % where
					)
					. is_equal(0)
				)
				(
					assert_int(shadow)
					. override_failure_message("%s is flat but stands on a contact shadow" % where)
					. is_equal(0)
				)
				(
					assert_int(top)
					. override_failure_message("%s is flat but rises off the floor" % where)
					. is_greater_equal(FLAT_TOP)
				)
				(
					assert_bool(_cell_is_empty(img, col, Prop.DEBRIS_ROW))
					. override_failure_message("%s is flat: nothing to break, so no debris" % where)
					. is_true()
				)


func test_every_biome_has_both_solid_and_flat_kinds() -> void:
	for biome: StringName in Biome.ALL_IDS:
		var solid := 0
		var flat := 0
		for kind: StringName in Prop.kind_names(biome):
			if Prop.is_solid(kind):
				solid += 1
			else:
				flat += 1
		assert_int(solid).override_failure_message("%s has no solid kind" % biome).is_greater(0)
		assert_int(flat).override_failure_message("%s has no flat kind" % biome).is_greater(0)


func test_the_flag_follows_the_kind_through_setup() -> void:
	var rng := RandomNumberGenerator.new()
	for biome: StringName in Biome.ALL_IDS:
		var names: Array = Prop.kind_names(biome)
		for col in range(names.size()):
			var prop: Prop = auto_free(Prop.new())
			prop.setup(biome, col, null, rng, Color.WHITE)
			var kind := StringName(names[col])
			assert_bool(prop.solid).override_failure_message(String(kind)).is_equal(
				Prop.SOLID[kind]
			)
			(
				assert_int(prop.collision_layer)
				. override_failure_message("%s %s" % [biome, kind])
				. is_equal(Layers.PROP if Prop.SOLID[kind] else 0)
			)
	# An unknown name is solid: an invisible gap in the rule would be the old bug back.
	var odd: Prop = auto_free(Prop.new())
	odd.setup_by_kind(&"crypt", &"gargoyle", null, rng, Color.WHITE)
	assert_bool(odd.solid).is_true()
	assert_int(odd.collision_layer).is_equal(Layers.PROP)


func _push_body_at(prop: Prop) -> CharacterBody2D:
	var body: CharacterBody2D = auto_free(CharacterBody2D.new())
	body.collision_layer = Layers.PLAYER
	body.collision_mask = Layers.WORLD | Layers.PROP
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(CELL - 4, CELL - 4)
	shape.shape = rect
	body.add_child(shape)
	body.position = prop.position - Vector2(3 * CELL, 0)
	add_child(body)
	return body


## The rule as physics, on a real CharacterBody2D with the player's mask: pushed at a solid
## prop it stops short of the tile, pushed at a flat one it walks straight through.
func test_a_solid_prop_blocks_a_body_and_a_flat_one_does_not() -> void:
	var rng := RandomNumberGenerator.new()
	var solid: Prop = auto_free(Prop.new())
	solid.setup_by_kind(&"crypt", &"barrel", null, rng, Color.WHITE)
	solid.position = Vector2(200, 100)
	add_child(solid)
	var flat: Prop = auto_free(Prop.new())
	flat.setup_by_kind(&"crypt", &"bones", null, rng, Color.WHITE)
	flat.position = Vector2(200, 300)
	add_child(flat)
	var blocked := _push_body_at(solid)
	var free := _push_body_at(flat)
	for i in range(PUSH_FRAMES):
		for body: CharacterBody2D in [blocked, free]:
			body.velocity = Vector2(PUSH_SPEED, 0)
			body.move_and_slide()
		await get_tree().physics_frame
	(
		assert_float(blocked.position.x)
		. override_failure_message("a barrel let the body through to x=%.1f" % blocked.position.x)
		. is_less(solid.position.x - CELL / 2.0)
	)
	(
		assert_float(free.position.x)
		. override_failure_message("bones stopped the body at x=%.1f" % free.position.x)
		. is_greater(flat.position.x + CELL)
	)


## ... and a broken solid prop is a flat one from then on: debris on the floor, nothing to
## walk into, nothing more to hit.
func test_a_broken_prop_becomes_walk_over_debris() -> void:
	var rng := RandomNumberGenerator.new()
	var prop: Prop = auto_free(Prop.new())
	prop.setup_by_kind(&"crypt", &"barrel", null, rng, Color.WHITE)
	prop.position = Vector2(200, 100)
	add_child(prop)
	_hit(prop)
	assert_bool(prop.is_broken).is_true()
	assert_bool(prop.sprite.visible).is_true()
	assert_that(prop.sprite.region_rect).is_equal(
		FloorBuilder.atlas_cell(prop.kind_index, Prop.DEBRIS_ROW)
	)
	var body := _push_body_at(prop)
	for i in range(PUSH_FRAMES):
		body.velocity = Vector2(PUSH_SPEED, 0)
		body.move_and_slide()
		await get_tree().physics_frame
	assert_float(body.position.x).is_greater(prop.position.x + CELL)
	assert_bool(is_instance_valid(prop)).is_true()
	assert_bool(prop.is_inside_tree()).is_true()
	# "Debris takes no further hits" measured as hp was worth nothing: `_break()` ends in
	# `_leave_debris()`, which puts hp back to 0, so a second break left the assertion passing
	# while paying out a second time. Proven by mutation - deleting the `is_broken` guard in
	# `take_hit` did not fail this test. What a second break actually costs is a second gold
	# roll and a second `broken`, so that is what is counted.
	#
	# Two guards stand between a second hit and a second payout now, one in `take_hit` and one
	# at the top of `_break()`, and either alone is enough. That means no single edit falsifies
	# this assertion any more; removing both does, which is the state it has to catch.
	var probe := EventBusProbe.new()
	var drops: Array = []
	probe.watch(
		EventBus.spawn_pickup,
		func(_kind: StringName, _pos: Vector2, _amount: int) -> void: drops.append(1)
	)
	var breaks: Array[Prop] = []
	prop.broken.connect(func(p: Prop) -> void: breaks.append(p))
	_hit(prop)  # debris takes no further hits
	assert_int(prop.hp).is_equal(0)
	(
		assert_int(drops.size())
		. override_failure_message("debris paid out again when it was hit a second time")
		. is_equal(0)
	)
	assert_int(breaks.size()).override_failure_message("debris broke a second time").is_equal(0)


## The light half of the rule: exactly the solid kinds carry a `LightOccluder2D` (the lighting
## system's shadow caster), sized to the sprite's base and never wider than the tile, and a flat
## kind has no occluder and a *disabled* collision shape - not a live shape on an empty layer,
## no collider at all. One table, and every consequence of it: solid <=> shadow <=> breakable
## <=> occluder.
func test_solid_kinds_cast_and_flat_kinds_have_no_collider_at_all() -> void:
	var rng := RandomNumberGenerator.new()
	for biome: StringName in Biome.ALL_IDS:
		var names: Array = Prop.kind_names(biome)
		for col in range(names.size()):
			var prop: Prop = auto_free(Prop.new())
			prop.setup(biome, col, null, rng, Color.WHITE)
			add_child(prop)
			var where := "%s %s" % [biome, names[col]]
			var occluder := prop.get_node_or_null(NodePath(Prop.OCCLUDER)) as LightOccluder2D
			var shape := prop.get_node(^"Shape") as CollisionShape2D
			if prop.solid:
				(
					assert_object(occluder)
					. override_failure_message(where + " casts no shadow")
					. is_not_null()
				)
				assert_bool(occluder.visible).override_failure_message(where).is_true()
				var poly := occluder.occluder.polygon
				assert_int(poly.size()).override_failure_message(where).is_equal(4)
				var base := Prop.base_rect(biome, col)
				assert_float(base.size.x).override_failure_message(where + " base").is_between(
					4.0, float(Layers.TILE)
				)
				assert_float(base.size.y).override_failure_message(where + " base").is_between(
					1.0, float(Prop.OCCLUDER_BASE_ROWS)
				)
				assert_float(base.end.y).override_failure_message(where + " base").is_less_equal(
					Layers.TILE / 2.0
				)
				assert_bool(shape.disabled).override_failure_message(where).is_false()
				assert_int(prop.hp).override_failure_message(where).is_greater(0)
			else:
				(
					assert_object(occluder)
					. override_failure_message(where + " casts a shadow")
					. is_null()
				)
				(
					assert_bool(shape.disabled)
					. override_failure_message(where + " has a collider")
					. is_true()
				)
				assert_int(prop.collision_layer).override_failure_message(where).is_equal(0)


## ...and a broken solid stops casting with its collision: debris throws no shadow.
func test_a_broken_prop_stops_casting_a_shadow() -> void:
	var rng := RandomNumberGenerator.new()
	var prop: Prop = auto_free(Prop.new())
	prop.setup_by_kind(&"crypt", &"coffin", null, rng, Color.WHITE)
	add_child(prop)
	var occluder := prop.get_node(NodePath(Prop.OCCLUDER)) as LightOccluder2D
	assert_bool(occluder.visible).is_true()
	_hit(prop)
	assert_bool(occluder.visible).override_failure_message("one hit on a sturdy kind").is_true()
	_hit(prop)
	assert_bool(prop.is_broken).is_true()
	assert_bool(occluder.visible).is_false()
	await get_tree().physics_frame
	assert_bool((prop.get_node(^"Shape") as CollisionShape2D).disabled).is_true()
	# A replayed break (resume) lands in the same state without paying.
	var replayed: Prop = auto_free(Prop.new())
	replayed.setup_by_kind(&"crypt", &"urn", null, rng, Color.WHITE)
	add_child(replayed)
	replayed.restore_broken()
	assert_bool((replayed.get_node(NodePath(Prop.OCCLUDER)) as LightOccluder2D).visible).is_false()
