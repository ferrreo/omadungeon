class_name RoomsContentTest
extends GdUnitTestSuite

## The rooms module's balance tables live in data/rooms/rooms_content.tres (docs §1: content is
## data). The shipped resource must agree with the script constants that mirror it, an empty
## resource must fall back to those constants, and an authored one must win.

const CHEST_ROOM_TYPES: Array[int] = [
	FloorData.RoomType.COMBAT,
	FloorData.RoomType.ELITE,
	FloorData.RoomType.TRAP,
	FloorData.RoomType.TREASURE,
	FloorData.RoomType.BOSS,
]


func test_shipped_resource_matches_the_constants() -> void:
	assert_object(RoomsContent.load_default()).is_not_null()
	for room_type: int in CHEST_ROOM_TYPES:
		var shipped := Chest.weights_for(room_type)
		var constant: Dictionary = Chest.WEIGHTS[room_type]
		for kind: int in constant:
			(
				assert_int(int(shipped.get(kind, -1)))
				. override_failure_message("room type %d, chest kind %d" % [room_type, kind])
				. is_equal(int(constant[kind]))
			)
	assert_int(Chest.cursed_per_floor()).is_equal(Chest.CURSED_PER_FLOOR)
	assert_float(FloorRoot.treasure_trap_chance()).is_equal(FloorRoot.TREASURE_TRAP_CHANCE)
	for biome: StringName in Prop.KINDS:
		(
			assert_array(Prop.kind_names(biome))
			. override_failure_message("prop kinds of " + biome)
			. contains_exactly(Prop.KINDS[biome])
		)
	for sturdy: StringName in Prop.STURDY:
		assert_int(Prop.hp_for_kind(sturdy)).is_equal(2)
	assert_int(Prop.hp_for_kind(&"barrel")).is_equal(1)
	for kind: StringName in Prop.SOLID:
		assert_bool(Prop.is_solid(kind)).override_failure_message(kind).is_equal(Prop.SOLID[kind])
	assert_float(Prop.gold_chance()).is_equal(Prop.GOLD_CHANCE)
	assert_int(Shop.reroll_base_price()).is_equal(Shop.BASE_REROLL_PRICE)
	assert_float(Shop.reroll_growth()).is_equal(Shop.REROLL_GROWTH)
	assert_array(Shop.rarity_price_mult()).contains_exactly(Shop.RARITY_PRICE_MULT)
	var shipped_options := Shrine.default_options()
	assert_int(shipped_options.size()).is_equal(Shrine.DEFAULT_OPTIONS.size())
	for i in range(Shrine.DEFAULT_OPTIONS.size()):
		var constant_option: Dictionary = Shrine.DEFAULT_OPTIONS[i]
		for key: String in constant_option:
			(
				assert_str(str(shipped_options[i].get(key, "")))
				. override_failure_message("shrine option %d key %s" % [i, key])
				. is_equal(str(constant_option[key]))
			)


func test_empty_resource_falls_back_to_the_constants() -> void:
	var content := RoomsContent.new()
	var weights := Chest.weights_for(FloorData.RoomType.COMBAT, content)
	assert_int(int(weights[Chest.Kind.STAT])).is_equal(45)
	assert_int(Chest.cursed_per_floor(content)).is_equal(Chest.CURSED_PER_FLOOR)
	assert_float(FloorRoot.treasure_trap_chance(content)).is_equal(FloorRoot.TREASURE_TRAP_CHANCE)
	assert_array(Prop.kind_names(&"crypt", content)).contains_exactly(Prop.KINDS[&"crypt"])
	assert_int(Prop.hp_for_kind(&"coffin", content)).is_equal(2)
	assert_bool(Prop.is_solid(&"bones", content)).is_false()
	assert_bool(Prop.is_solid(&"barrel", content)).is_true()
	assert_float(Prop.gold_chance(content)).is_equal(Prop.GOLD_CHANCE)
	assert_int(Shop.reroll_base_price(content)).is_equal(Shop.BASE_REROLL_PRICE)
	assert_float(Shop.reroll_growth(content)).is_equal(Shop.REROLL_GROWTH)
	assert_array(Shop.rarity_price_mult(content)).contains_exactly(Shop.RARITY_PRICE_MULT)
	assert_int(Shrine.default_options(content).size()).is_equal(Shrine.DEFAULT_OPTIONS.size())


func test_resource_overrides_the_tables() -> void:
	var sturdy: Array[StringName] = [&"a"]
	var mults: Array[float] = [2.0, 3.0]
	var options: Array[Dictionary] = [{"id": &"only", "label": "Only", "cost": 1}]
	var content := RoomsContent.new()
	content.chest_weights = {
		int(FloorData.RoomType.COMBAT): {Chest.Kind.GOLD: 1},
	}
	content.chest_cursed_per_floor = 7
	content.treasure_trap_chance = 0.25
	content.prop_kinds = {
		&"crypt": [&"a", &"b", &"c", &"d", &"e", &"f", &"g", &"h"],
	}
	content.prop_sturdy_kinds = sturdy
	content.prop_solid = {&"a": false, &"bones": true}
	content.prop_gold_chance = 0.75
	content.shop_reroll_base_price = 10
	content.shop_reroll_growth = 2.0
	content.shop_rarity_price_mult = mults
	content.shrine_options = options
	var weights := Chest.weights_for(FloorData.RoomType.COMBAT, content)
	assert_int(int(weights[Chest.Kind.GOLD])).is_equal(1)
	assert_bool(weights.has(Chest.Kind.STAT)).is_false()
	assert_int(Chest.cursed_per_floor(content)).is_equal(7)
	assert_float(FloorRoot.treasure_trap_chance(content)).is_equal(0.25)
	assert_array(Prop.kind_names(&"crypt", content)).contains_exactly(content.prop_kinds[&"crypt"])
	assert_int(Prop.hp_for_kind(&"a", content)).is_equal(2)
	assert_int(Prop.hp_for_kind(&"coffin", content)).is_equal(1)
	assert_bool(Prop.is_solid(&"a", content)).is_false()
	assert_bool(Prop.is_solid(&"bones", content)).is_true()
	assert_bool(Prop.is_solid(&"barrel", content)).is_true()  # unlisted: solid
	assert_float(Prop.gold_chance(content)).is_equal(0.75)
	assert_int(Shop.reroll_base_price(content)).is_equal(10)
	assert_float(Shop.reroll_growth(content)).is_equal(2.0)
	assert_array(Shop.rarity_price_mult(content)).contains_exactly(mults)
	# A biome the resource does not cover still falls back to the constant.
	assert_array(Prop.kind_names(&"forge", content)).contains_exactly(Prop.KINDS[&"forge"])
	var picked := Shrine.default_options(content)
	assert_int(picked.size()).is_equal(1)
	assert_str(String(picked[0]["id"])).is_equal("only")
