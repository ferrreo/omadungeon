class_name InteractablesTest
extends GdUnitTestSuite


func test_altar_emits_once() -> void:
	var used: Array[Node2D] = []
	var cb := func(a: Node2D) -> void: used.append(a)
	EventBus.altar_used.connect(cb)
	var altar: Altar = auto_free(Altar.new())
	altar.setup(FloorBuilder.load_atlas(RoomsTestFixtures.ATLAS), null)
	add_child(altar)
	assert_int(altar.collision_layer).is_equal(Layers.INTERACTABLE)
	assert_bool(altar.interact()).is_true()
	altar.consume()
	assert_bool(altar.interact()).is_false()
	assert_int(used.size()).is_equal(1)
	EventBus.altar_used.disconnect(cb)


func test_shop_offers_and_reroll() -> void:
	var opened: Array[Node2D] = []
	var cb := func(s: Node2D) -> void: opened.append(s)
	EventBus.shop_opened.connect(cb)
	var shop: Shop = auto_free(Shop.new())
	shop.setup(FloorBuilder.load_atlas(RoomsTestFixtures.ATLAS), null)
	add_child(shop)
	var offers: Array[RefCounted] = [
		RefCounted.new(), RefCounted.new(), RefCounted.new(), RefCounted.new()
	]
	shop.set_offers(offers, [10, 20, 30, 40])
	assert_int(shop.offers.size()).is_equal(Shop.MAX_OFFERS)
	assert_array(shop.prices).contains_exactly([10, 20, 30])
	assert_int(shop.reroll_price()).is_equal(25)
	shop.mark_rerolled()
	assert_int(shop.reroll_price()).is_equal(38)
	shop.mark_rerolled()
	assert_int(shop.reroll_price()).is_equal(56)
	var taken := shop.take_offer(1)
	assert_object(taken).is_same(offers[1])
	assert_int(shop.offers.size()).is_equal(2)
	assert_array(shop.prices).contains_exactly([10, 30])
	assert_object(shop.take_offer(7)).is_null()
	assert_bool(shop.interact()).is_true()
	assert_int(opened.size()).is_equal(1)
	EventBus.shop_opened.disconnect(cb)


func test_shrine_options() -> void:
	var used: Array[Node2D] = []
	var cb := func(s: Node2D) -> void: used.append(s)
	EventBus.shrine_used.connect(cb)
	var shrine: Shrine = auto_free(Shrine.new())
	shrine.setup(FloorBuilder.load_atlas(RoomsTestFixtures.ATLAS), null)
	add_child(shrine)
	assert_int(shrine.options.size()).is_equal(Shrine.DEFAULT_OPTIONS.size())
	for opt: Dictionary in shrine.options:
		for key: String in ["id", "label", "cost_kind", "cost", "buff", "amount"]:
			assert_bool(opt.has(key)).is_true()
	assert_int(int(shrine.option_by_id(&"refill_potion")["cost"])).is_equal(30)
	assert_bool(shrine.option_by_id(&"nope").is_empty()).is_true()
	assert_bool(shrine.interact()).is_true()
	shrine.consume()
	assert_bool(shrine.interact()).is_false()
	assert_int(used.size()).is_equal(1)
	EventBus.shrine_used.disconnect(cb)


func _settle(frames: int = 3) -> void:
	for _i in range(frames):
		await get_tree().physics_frame


func test_nearest_interactable_owns_the_prompt() -> void:
	var prompts: Array = []
	var cb := func(text: String, shown: bool) -> void: prompts.append([text, shown])
	EventBus.interact_prompt.connect(cb)
	var player: CharacterBody2D = auto_free(RoomsTestFixtures.make_player())
	player.position = Vector2.ZERO
	add_child(player)
	var near: Interactable = auto_free(RoomsTestFixtures.make_interactable("Near"))
	near.position = Vector2(10, 0)
	add_child(near)
	var far: Interactable = auto_free(RoomsTestFixtures.make_interactable("Far"))
	far.position = Vector2(26, 0)
	add_child(far)
	await _settle()
	assert_bool(near.player_nearby()).is_true()
	assert_bool(far.player_nearby()).is_true()
	assert_array(prompts).contains([["Near", true]])
	assert_object(Interactable.nearest_for(player)).is_same(near)
	# Walking up to the far one hands the prompt over.
	player.global_position = Vector2(30, 0)
	await _settle()
	assert_object(Interactable.nearest_for(player)).is_same(far)
	prompts.clear()
	player.global_position = Vector2(400, 400)
	await _settle()
	# Leaving both hides the prompt exactly once, and the last word is the hide.
	var hides := 0
	for entry: Array in prompts:
		if not bool(entry[1]):
			hides += 1
	assert_int(hides).is_equal(1)
	assert_array(prompts[prompts.size() - 1] as Array).contains_exactly(["Far", false])
	EventBus.interact_prompt.disconnect(cb)


func test_dispatch_handles_zero_argument_interact() -> void:
	var player: CharacterBody2D = auto_free(RoomsTestFixtures.make_player())
	player.position = Vector2(600, 600)
	add_child(player)
	var mimic: RoomsTestFixtures.ArityZeroInteractable = auto_free(
		RoomsTestFixtures.ArityZeroInteractable.new()
	)
	mimic.position = Vector2(604, 600)
	mimic.add_to_group(Interactable.GROUP)
	add_child(mimic)
	await _settle(1)
	assert_bool(Interactable.dispatch(player)).is_true()
	assert_int(mimic.used).is_equal(1)
	assert_bool(Interactable.dispatch(null)).is_false()


func test_mark_taken_spends_altar_and_shrine() -> void:
	var altar: Altar = auto_free(Altar.new())
	add_child(altar)
	altar.mark_taken()
	assert_bool(altar.used).is_true()
	assert_bool(altar.enabled).is_false()
	assert_bool(altar.interact()).is_false()
	var shrine: Shrine = auto_free(Shrine.new())
	add_child(shrine)
	shrine.mark_taken()
	assert_bool(shrine.used).is_true()
	assert_bool(shrine.interact()).is_false()


func test_shop_stock_prices_by_rarity() -> void:
	var shop: Shop = auto_free(Shop.new())
	add_child(shop)
	var common := ItemInstance.new()
	var legendary := ItemInstance.new()
	legendary.rarity = ItemInstance.Rarity.LEGENDARY
	var offers: Array = [common, legendary, null]
	shop.stock(offers, 40)
	assert_int(shop.offers.size()).is_equal(2)
	assert_int(shop.prices[0]).is_equal(40)
	assert_int(shop.prices[1]).is_greater(shop.prices[0])
