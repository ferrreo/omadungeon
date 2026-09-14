class_name ChestTest
extends GdUnitTestSuite


func _roll_many(room_type: FloorData.RoomType, floor_index: int, n: int = 1000) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var counts: Dictionary = {}
	for k: Chest.Kind in Chest.Kind.values():
		counts[k] = 0
	for _i in range(n):
		counts[Chest.roll_kind(rng, room_type, floor_index)] += 1
	return counts


func test_combat_distribution_stat_most_common() -> void:
	var counts := _roll_many(FloorData.RoomType.COMBAT, 0)
	# Weights 45/22/15/12/3 over 1000 rolls; allow a generous band.
	assert_int(int(counts[Chest.Kind.STAT])).is_between(390, 510)
	assert_int(int(counts[Chest.Kind.ITEM])).is_between(160, 280)
	assert_int(int(counts[Chest.Kind.ABILITY])).is_between(100, 200)
	assert_int(int(counts[Chest.Kind.GOLD])).is_between(70, 170)
	assert_int(int(counts[Chest.Kind.CURSED])).is_between(10, 60)
	for k: Chest.Kind in Chest.Kind.values():
		if k != Chest.Kind.STAT:
			assert_int(int(counts[Chest.Kind.STAT])).is_greater(int(counts[k]))


func test_treasure_favours_items_and_gold() -> void:
	var counts := _roll_many(FloorData.RoomType.TREASURE, 0)
	assert_int(int(counts[Chest.Kind.ITEM])).is_greater(int(counts[Chest.Kind.STAT]))
	assert_int(int(counts[Chest.Kind.GOLD])).is_greater(int(counts[Chest.Kind.STAT]))


func test_cursed_grows_with_floor() -> void:
	var low := _roll_many(FloorData.RoomType.COMBAT, 0, 3000)
	var high := _roll_many(FloorData.RoomType.COMBAT, 8, 3000)
	assert_int(int(high[Chest.Kind.CURSED])).is_greater(int(low[Chest.Kind.CURSED]))


func test_roll_is_deterministic() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 5
	b.seed = 5
	for _i in range(50):
		assert_int(Chest.roll_kind(a, FloorData.RoomType.ELITE, 2)).is_equal(
			Chest.roll_kind(b, FloorData.RoomType.ELITE, 2)
		)


func test_interact_opens_once_and_emits() -> void:
	var opened: Array[Node2D] = []
	var cb := func(c: Node2D) -> void: opened.append(c)
	EventBus.chest_opened.connect(cb)
	var chest: Chest = auto_free(Chest.new())
	chest.kind = Chest.Kind.GOLD
	add_child(chest)
	assert_int(chest.collision_layer).is_equal(Layers.INTERACTABLE)
	assert_bool(chest.is_opened).is_false()
	assert_bool(chest.interact()).is_true()
	assert_bool(chest.is_opened).is_true()
	assert_bool(chest.interact()).is_false()
	assert_int(opened.size()).is_equal(1)
	assert_object(opened[0]).is_same(chest)
	assert_int(chest.sprite.frame).is_equal(Chest.FRAME_OPEN)
	assert_str(Chest.kind_name(Chest.Kind.CURSED)).is_equal("Cursed")
	EventBus.chest_opened.disconnect(cb)


func test_prompt_follows_player() -> void:
	var prompts: Array = []
	var cb := func(text: String, visible: bool) -> void: prompts.append([text, visible])
	EventBus.interact_prompt.connect(cb)
	var chest: Chest = auto_free(Chest.new())
	chest.position = Vector2(100, 100)
	add_child(chest)
	var player: CharacterBody2D = auto_free(RoomsTestFixtures.make_player())
	player.position = Vector2(-100, -100)
	add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(chest.player_nearby()).is_false()
	player.global_position = Vector2(100, 100)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(chest.player_nearby()).is_true()
	assert_int(prompts.size()).is_equal(1)
	assert_str(str(prompts[0][0])).is_equal("Open chest")
	assert_bool(bool(prompts[0][1])).is_true()
	player.global_position = Vector2(-100, -100)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(chest.player_nearby()).is_false()
	assert_int(prompts.size()).is_equal(2)
	assert_bool(bool(prompts[1][1])).is_false()
	EventBus.interact_prompt.disconnect(cb)


## The lid and the reward are two different facts, and conflating them is what used to destroy
## a chest's prize. Interacting opens the lid and raises the offer; nothing is *spent* until
## `mark_taken()`, which only `RunManager._finish_offer()` calls once the player has answered.
## The autosave a room clear queues runs while the picker is up (the tree is paused,
## SaveManager is PROCESS_MODE_ALWAYS), so a save taken there has to say "still owed".
func test_opening_a_chest_does_not_spend_its_reward() -> void:
	var probe := EventBusProbe.new()
	var opened: Array[Node2D] = []
	probe.watch(EventBus.chest_opened, func(c: Node2D) -> void: opened.append(c))
	var chest: Chest = auto_free(Chest.new())
	add_child(chest)
	assert_bool(chest.reward_taken).is_false()
	assert_bool(chest.interact()).is_true()
	assert_bool(chest.is_opened).is_true()
	(
		assert_bool(chest.reward_taken)
		. override_failure_message("the reward was marked spent before the offer was answered")
		. is_false()
	)
	assert_int(opened.size()).is_equal(1)
	chest.mark_taken()
	assert_bool(chest.reward_taken).is_true()
	assert_bool(chest.is_opened).is_true()
	probe.release()


## Resume: a chest whose offer was still on screen comes back closed, and RunManager puts the
## lid up itself and re-drives the offer. That path must not re-announce the open — a second
## `chest_opened` would raise a second board on top of the one being restored — and it must
## refuse a chest whose reward is already spent.
func test_reopen_offer_restores_the_lid_without_re_announcing_it() -> void:
	var probe := EventBusProbe.new()
	var opened: Array[Node2D] = []
	probe.watch(EventBus.chest_opened, func(c: Node2D) -> void: opened.append(c))
	var chest: Chest = auto_free(Chest.new())
	add_child(chest)
	assert_bool(chest.reopen_offer()).is_true()
	assert_bool(chest.is_opened).is_true()
	assert_bool(chest.reward_taken).is_false()
	assert_int(chest.sprite.frame).is_equal(Chest.FRAME_OPEN)
	assert_array(opened).is_empty()
	assert_bool(chest.reopen_offer()).is_false()

	var spent: Chest = auto_free(Chest.new())
	add_child(spent)
	spent.mark_taken()
	assert_bool(spent.reopen_offer()).is_false()
	assert_array(opened).is_empty()
	probe.release()
