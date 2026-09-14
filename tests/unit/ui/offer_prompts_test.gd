## The first interactive screen of a new run, the descend prompt, and the live-retint banner:
## three places the game either offered something it could not do, or said nothing at all.
class_name OfferPromptsTest
extends GdUnitTestSuite

const CHEST_SCENE := "res://src/ui/chest_ui.tscn"


func _chest() -> ChestUi:
	var node: ChestUi = auto_free((load(CHEST_SCENE) as PackedScene).instantiate())
	add_child(node)
	return node


## "Skip" on the starting-passive picker closed the dialog and immediately re-opened the same
## cards with a scolding toast, which reads as a bug rather than as a rule.
func test_a_mandatory_pick_hides_the_skip_button() -> void:
	var chest := _chest()
	var context := StartingPassive.CONTEXT.duplicate(true)
	context["no_skip"] = true
	context["gold"] = 0
	context["reroll_cost"] = 25
	chest.show_offers(ChestUi.Kind.ABILITY, UiFakes.make_offers(ChestUi.Kind.ABILITY), context)
	assert_bool(chest.can_skip()).is_false()
	assert_bool((chest.get_node("%Skip") as Button).visible).is_false()
	var monitor := monitor_signals(chest)
	chest._on_skip()
	await assert_signal(monitor).wait_until(100).is_not_emitted("skipped")
	assert_bool(chest.is_open()).is_true()


func test_an_ordinary_chest_still_offers_skip() -> void:
	var chest := _chest()
	var player := auto_free(UiFakes.make_player()) as UiFakes.FakePlayer
	add_child(player)
	chest.show_offers(
		ChestUi.Kind.ITEM, UiFakes.make_offers(ChestUi.Kind.ITEM), UiFakes.chest_context(player)
	)
	assert_bool(chest.can_skip()).is_true()
	assert_bool((chest.get_node("%Skip") as Button).visible).is_true()


## "Reroll (25g)" at 0 gold refused with a shake and no explanation.
func test_an_unaffordable_reroll_states_the_shortfall() -> void:
	assert_str(ChestUi.reroll_label({"reroll_cost": 25, "gold": 0})).is_equal(
		"Reroll 25g - you have 0"
	)
	assert_str(ChestUi.reroll_label({"reroll_cost": 25, "gold": 40})).is_equal("Reroll (25g)")
	assert_str(ChestUi.reroll_label({"reroll_cost": 25, "gold": 0, "free_reroll": true})).is_equal(
		"Reroll (free)"
	)


## The cost of descending is stated on the map, not over the stairs: the prompt stays short
## and the minimap's strip carries the count (owner report 10, round 5).
func test_the_descend_prompt_stays_short_and_the_map_carries_the_cost() -> void:
	var left: Array[String] = ["Altar", "Treasure", "Treasure"]
	assert_str(DescendNotice.prompt()).is_equal("Descend")
	assert_str(DescendNotice.cost_text(left)).is_equal("3 rooms unexplored (Altar, 2 Treasure)")
	assert_str(Minimap.caption_for(3, 1)).is_equal("3 rooms left, 1 item on the floor")
	assert_str(Minimap.caption_for(1, 0)).is_equal("1 room left")
	assert_str(Minimap.caption_for(0, 2)).is_equal("2 items on the floor")
	assert_str(Minimap.caption_for(0, 0)).is_empty()


## The behaviour, not the wording: standing on the stairs with a shop still unexplored, the
## first Descend goes down. No confirmation press, no toast in the way of the exit.
func test_a_descend_at_the_stairs_is_never_held_back() -> void:
	var root := _floor_root_with_stairs(true)
	var notice := DescendNotice.new()
	var data := _floor_with_unvisited_shop()
	assert_bool(notice.intercept(root, data)).is_false()
	assert_bool(root.stairs.enabled).is_true()
	assert_bool(notice.intercept(root, data)).is_false()


## A floor exit asked for without a player on the staircase - a save resume, the scenario
## driver, a test - is taken at its word rather than swallowed.
func test_a_descend_away_from_the_stairs_is_never_intercepted() -> void:
	var notice := DescendNotice.new()
	var data := _floor_with_unvisited_shop()
	assert_bool(notice.intercept(_floor_root_with_stairs(false), data)).is_false()
	assert_bool(notice.intercept(null, data)).is_false()


## With every reward room already seen there is nothing to warn about.
func test_a_fully_explored_floor_descends_on_the_first_press() -> void:
	var root := _floor_root_with_stairs(true)
	var data := _floor_with_unvisited_shop()
	data.rooms = [_room(0, FloorData.RoomType.COMBAT)]
	assert_bool(DescendNotice.new().intercept(root, data)).is_false()


func test_the_prompt_stays_descend_whatever_is_left_behind() -> void:
	var root := _floor_root_with_stairs(true)
	DescendNotice.new().refresh_prompt(root, _floor_with_unvisited_shop())
	assert_str(root.stairs.prompt_text).is_equal("Descend")
	root.stairs.locked = true
	root.stairs.prompt_text = "Sealed"
	DescendNotice.new().refresh_prompt(root, _floor_with_unvisited_shop())
	assert_str(root.stairs.prompt_text).is_equal("Sealed")


func _floor_root_with_stairs(player_on_them: bool) -> FloorRoot:
	var root: FloorRoot = auto_free(FloorRoot.new())
	add_child(root)
	var stairs: Stairs = auto_free(Stairs.new())
	root.add_child(stairs)
	root.stairs = stairs
	if player_on_them:
		var body: CharacterBody2D = auto_free(CharacterBody2D.new())
		body.add_to_group(&"player")
		add_child(body)
		stairs._on_body_entered(body)
	return root


func _floor_with_unvisited_shop() -> FloorData:
	var data := FloorData.new()
	data.rooms = [_room(0, FloorData.RoomType.START), _room(1, FloorData.RoomType.SHOP)]
	return data


func test_only_unvisited_reward_rooms_count() -> void:
	var data := FloorData.new()
	data.rooms = [
		_room(0, FloorData.RoomType.START),
		_room(1, FloorData.RoomType.COMBAT),
		_room(2, FloorData.RoomType.SHOP),
		_room(3, FloorData.RoomType.ALTAR),
		_room(4, FloorData.RoomType.TREASURE),
	]
	var visited: Array[int] = [0, 1, 3]
	assert_array(DescendNotice.unexplored(data, visited)).contains_exactly(["Shop", "Treasure"])
	var all_seen: Array[int] = [0, 1, 2, 3, 4]
	assert_array(DescendNotice.unexplored(data, all_seen)).is_empty()


## The weapon skill had no name anywhere in the game: not on the HUD, not on the card that
## granted it, not on the pause Equipment page. `ItemCard.weapon_lines` feeds the last two.
func test_a_weapon_card_names_its_secondary_attack() -> void:
	var weapon := WeaponBase.new()
	weapon.base_damage = 8.0
	weapon.attacks_per_second = 2.0
	weapon.range_px = 20.0
	assert_array(Array(ItemCard.weapon_lines(weapon))).not_contains(["Skill: Lunge"])
	weapon.skill = UiFakes.make_active("whirlwind", "Lunge", 4.0)
	assert_array(Array(ItemCard.weapon_lines(weapon))).contains(["Skill: Lunge"])
	assert_array(Array(ItemCard.weapon_lines(null))).is_empty()


static func _room(id: int, type: int) -> FloorData.Room:
	var room := FloorData.Room.new()
	room.id = id
	room.type = type
	return room


## Boss floors (docs §2: 3, 6 and 9) were computed for generation and signposted nowhere. The
## staircase is the last moment a player can decide to heal first, so it says so there.
func test_the_stairs_name_a_boss_floor_before_it_is_paid_for() -> void:
	assert_str(DescendNotice.prompt(true)).is_equal("Descend to the BOSS floor")
	# An ordinary floor is unchanged.
	assert_str(DescendNotice.prompt(false)).is_equal("Descend")


func test_the_stairs_prompt_carries_the_boss_warning_onto_the_staircase() -> void:
	var root := _floor_root_with_stairs(true)
	DescendNotice.new().refresh_prompt(root, _floor_with_unvisited_shop(), true)
	assert_str(root.stairs.prompt_text).contains("BOSS")
	DescendNotice.new().refresh_prompt(root, _floor_with_unvisited_shop(), false)
	assert_str(root.stairs.prompt_text).not_contains("BOSS")


## The other half of what descending abandons, and the more valuable one: an uncollected
## `ItemPickup` is destroyed by the next `floor_started`. The cost line still counts it, and
## the map strip is where it is printed.
func test_the_cost_line_counts_the_loot_still_on_the_floor() -> void:
	var left: Array[String] = ["Altar"]
	var none: Array[String] = []
	assert_str(DescendNotice.cost_text(left, 1)).is_equal(
		"1 room unexplored (Altar), 1 item on the floor"
	)
	assert_str(DescendNotice.cost_text(none, 2)).is_equal("2 items on the floor")
	assert_str(DescendNotice.cost_text(none, 0)).is_empty()


## A drop lying on the floor reaches the HUD as `floor_leftovers`, so the minimap can print
## it, and the staircase itself never says a word about it.
func test_a_drop_on_the_floor_reaches_the_map_and_not_the_stairs() -> void:
	var root := _floor_root_with_stairs(true)
	var data := _floor_with_unvisited_shop()
	var counts: Array[int] = []
	var listener := func(items: int) -> void: counts.append(items)
	EventBus.floor_leftovers.connect(listener)
	DescendNotice.new().refresh_prompt(root, data)
	assert_str(root.stairs.prompt_text).is_equal("Descend")
	_drop_item(root)
	assert_int(DescendNotice.loose_items(root)).is_equal(1)
	DescendNotice.new().refresh_prompt(root, data)
	EventBus.floor_leftovers.disconnect(listener)
	assert_array(counts).contains_exactly([0, 1])
	assert_str(root.stairs.prompt_text).is_equal("Descend")
	assert_int(DescendNotice.loose_items(null)).is_equal(0)
	# ...and the map prints it under the rooms.
	var map: Minimap = auto_free(Minimap.new())
	add_child(map)
	map.set_items_left(1)
	assert_str(map.caption_text()).is_equal("1 item on the floor")


## An item drop under `root`, built directly rather than through `ItemPickup.drop` (which
## defers its insertion by a frame).
func _drop_item(root: FloorRoot) -> ItemPickup:
	var registry := ItemRegistry.load_default()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var pickup: ItemPickup = auto_free(ItemPickup.new())
	pickup.item = ItemGenerator.generate(registry, 3, rng, 0.0, [ItemBase.Slot.WEAPON], 1)
	root.add_child(pickup)
	return pickup
