## What a player actually experiences when an elite drops an item: the drop stays put, it
## never equips itself, the interact prompt offers a comparison first, and the item it
## replaces lands back on the floor instead of being destroyed (playtest blocker).
class_name ItemPickupTest
extends GdUnitTestSuite

const SEED := 918273


## Player stand-in with a real Equipment, reached exactly the way `Player` is: an `equip(item)`
## method plus an `equipment` property. Carries a body shape so the drop's Area2D sees it.
class GearedPlayer:
	extends Entity

	var equipment: RefCounted

	func _ready() -> void:
		super()
		add_to_group(&"player")
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(10.0, 12.0)
		shape.shape = rect
		add_child(shape)
		var gear := Equipment.new()
		gear.bind(self)
		equipment = gear

	func gear() -> Equipment:
		return equipment as Equipment

	func equip(item: ItemInstance) -> void:
		gear().equip(item, stats)


var _registry: ItemRegistry
var _world: Node2D
var _player: GearedPlayer


func before_test() -> void:
	_registry = ItemRegistry.load_default()
	_world = auto_free(Node2D.new()) as Node2D
	add_child(_world)
	_player = GearedPlayer.new()
	_player.team = Layers.Team.PLAYER
	_world.add_child(_player)
	_player.global_position = Vector2.ZERO
	await _physics_frames(2)


func after_test() -> void:
	Interactable.reset_prompt(get_tree())
	_player.queue_free()
	await _physics_frames(2)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


func _weapon(seed_value: int, rarity: int = 1) -> ItemInstance:
	return ItemGenerator.generate(
		_registry, 4, _rng(seed_value), 0.0, [ItemBase.Slot.WEAPON], rarity
	)


func _drops() -> Array[ItemPickup]:
	var out: Array[ItemPickup] = []
	for child: Node in _world.get_children():
		if child is ItemPickup and not child.is_queued_for_deletion():
			out.append(child as ItemPickup)
	return out


func test_drop_neither_homes_nor_equips_itself() -> void:
	var worn := _weapon(1, 0)
	_player.equip(worn)
	var offered := _weapon(2, 2)
	var drop := ItemPickup.drop(_world, offered, Vector2(40.0, 0.0), _rng(SEED))
	await _physics_frames(40)
	assert_bool(is_instance_valid(drop)).is_true()
	var settled := drop.global_position
	# It stays where it landed: no pickup radius, no homing, nothing to walk past.
	await _physics_frames(40)
	assert_vector(drop.global_position).is_equal_approx(settled, Vector2(0.5, 0.5))
	assert_float(settled.distance_to(_player.global_position)).is_greater(20.0)

	# Standing on it does nothing either - the build only changes when the player asks.
	_player.global_position = drop.global_position
	await _physics_frames(40)
	assert_bool(is_instance_valid(drop)).is_true()
	assert_object(_player.gear().get_item(&"weapon")).is_same(worn)


func test_interact_equips_and_drops_the_replaced_item_back_on_the_floor() -> void:
	var worn := _weapon(10, 0)
	_player.equip(worn)
	var offered := _weapon(11, 2)
	var drop := ItemPickup.drop(_world, offered, Vector2(6.0, 0.0), _rng(SEED))
	await _physics_frames(40)
	assert_bool(drop.can_interact()).is_true()
	assert_object(Interactable.nearest_for(_player)).is_same(drop)
	assert_bool(Interactable.dispatch(_player)).is_true()
	await _physics_frames(4)

	assert_object(_player.gear().get_item(&"weapon")).is_same(offered)
	var left: Array[ItemPickup] = _drops()
	assert_int(left.size()).is_equal(1)
	# The displaced item is on the floor, not destroyed: the swap can be undone.
	assert_object(left[0].item).is_same(worn)

	await _physics_frames(40)
	assert_bool(Interactable.dispatch(_player)).is_true()
	await _physics_frames(4)
	assert_object(_player.gear().get_item(&"weapon")).is_same(worn)
	assert_object(_drops()[0].item).is_same(offered)


func test_an_empty_slot_leaves_nothing_behind() -> void:
	var offered := _weapon(20, 1)
	ItemPickup.drop(_world, offered, Vector2(5.0, 0.0), _rng(SEED))
	await _physics_frames(40)
	assert_bool(Interactable.dispatch(_player)).is_true()
	await _physics_frames(4)
	assert_object(_player.gear().get_item(&"weapon")).is_same(offered)
	assert_array(_drops()).is_empty()


func test_a_fresh_drop_refuses_the_same_key_press_that_made_it() -> void:
	var drop := ItemPickup.drop(_world, _weapon(30, 1), Vector2(5.0, 0.0), _rng(SEED))
	await _physics_frames(2)
	assert_bool(drop.can_interact()).is_false()
	assert_bool(drop.interact(_player)).is_false()
	await _physics_frames(40)
	assert_bool(drop.can_interact()).is_true()


func test_the_toast_names_both_items() -> void:
	var worn := _weapon(40, 0)
	_player.equip(worn)
	var offered := _weapon(41, 2)
	var lines: Array[String] = []
	var listener := func(text: String, _duration: float) -> void: lines.append(text)
	EventBus.toast.connect(listener)
	ItemPickup.drop(_world, offered, Vector2(5.0, 0.0), _rng(SEED))
	await _physics_frames(40)
	Interactable.dispatch(_player)
	await _physics_frames(2)
	EventBus.toast.disconnect(listener)
	assert_int(lines.size()).is_greater_equal(1)
	assert_str(lines[0]).contains(offered.display_name)
	assert_str(lines[0]).contains(worn.display_name)


## The drop tells the HUD how close the player is, and the HUD's tooltip turns that into a
## compare card - only while the player stands on it (`CLOSE_RADIUS`), never a world plate
## over the room the moment the detection box is entered.
func test_the_prompt_names_the_item_and_the_hud_card_shows_the_swap() -> void:
	var worn := ItemGenerator.instance_of(_registry.find_base(&"rusty_sword"), _rng(50))
	_player.equip(worn)
	var offered := ItemGenerator.instance_of(_registry.find_base(&"greatsword"), _rng(51))
	var levels: Array[int] = []
	var listener := func(_pickup: Node2D, _item: RefCounted, level: int) -> void:
		levels.append(level)
	EventBus.item_hover.connect(listener)
	var drop := ItemPickup.drop(_world, offered, Vector2(5.0, 0.0), _rng(SEED))
	await _physics_frames(40)
	EventBus.item_hover.disconnect(listener)
	assert_str(drop.prompt_text).contains(offered.display_name)
	assert_int(drop.hover_level()).is_equal(ItemTooltip.Level.CLOSE)
	assert_array(levels).contains([ItemTooltip.Level.CLOSE])
	var tooltip: ItemTooltip = auto_free(ItemTooltip.new())
	add_child(tooltip)
	tooltip.show_item(drop, offered, ItemTooltip.Level.CLOSE, _player.gear(), _player.stats)
	assert_bool(tooltip.visible).is_true()
	var labels: PackedStringArray = []
	for row: Dictionary in tooltip.rows:
		labels.append(str(row["label"]))
	assert_array(labels).contains(["Damage", "Dps"])
	assert_bool(ItemTooltip.within_budget(tooltip.card_size(), Vector2(480, 270))).is_true()


## Further away than `CLOSE_RADIUS` but still in the box, only the name tag is asked for.
func test_standing_in_the_box_but_off_the_drop_shows_only_the_tag() -> void:
	# No scatter hop: the drop has to stay where it is put for the distance to mean anything.
	var drop := ItemPickup.drop(_world, _weapon(70, 1), Vector2(14.0, 0.0), null, false)
	await _physics_frames(40)
	assert_bool(drop.player_nearby()).is_true()
	assert_int(drop.hover_level()).is_equal(ItemTooltip.Level.NEAR)


func test_compare_rows_read_both_sides_of_what_is_worn() -> void:
	var light := ItemGenerator.instance_of(_registry.find_base(&"leather_jerkin"), _rng(60))
	var heavy := ItemGenerator.instance_of(_registry.find_base(&"iron_plate"), _rng(61))
	var roles: Dictionary = {}
	for row: Dictionary in CompareRows.stat_rows(CompareRows.rows_for(light, heavy)):
		roles[str(row["label"])] = StringName(str(row["role"]))
	assert_that(roles.get("Armor")).is_equal(CompareRows.ROLE_UP)
	assert_that(roles.get("Swiftness")).is_equal(CompareRows.ROLE_DOWN)


func test_an_uncollected_drop_does_not_follow_the_player_downstairs() -> void:
	ItemPickup.drop(_world, _weapon(70, 1), Vector2(60.0, 0.0), _rng(SEED))
	await _physics_frames(4)
	assert_int(_drops().size()).is_equal(1)
	EventBus.floor_started.emit(1)
	await _physics_frames(2)
	assert_array(_drops()).is_empty()


## The sibling of the `PickupBase` hole `FloorDropsTest` covers, in the half that carries the
## valuable loot. `FloorPickups.capture()` sweeps the live tree, and a drop whose insertion is
## still sitting in the frame's message queue is not in it - so a save written in the same
## frame as the resume that replayed it recorded a floor with no items on it. That frame is
## reachable: `SaveManager` flushes immediately on `NOTIFICATION_WM_CLOSE_REQUEST`, with no
## autosave debounce in front of it, which is what closing the window right after Continue is.
##
## Outside a physics query flush there is nothing to defer for, and `FloorPickups.apply()` is
## never called from inside one.
func test_a_drop_made_outside_a_physics_flush_is_in_the_tree_at_once() -> void:
	var drop := ItemPickup.drop(_world, _weapon(11, 2), Vector2(40.0, 0.0), _rng(SEED))
	(
		assert_bool(drop.is_inside_tree())
		. override_failure_message(
			"the drop is not on the floor until the next flush, so a save taken now loses it"
		)
		. is_true()
	)
	(
		assert_array(FloorPickups.find_all(_world))
		. override_failure_message("a sweep of the floor in this frame found no items")
		. contains([drop])
	)


## ...and inside one it still defers, because the physics server refuses an Area2D's collider
## state while it is flushing its queries. `tests/unit/tools/physics_deferral_test.gd` is what
## proves the collider comes up whole; this is the cheap statement of the rule next to the
## behaviour it protects.
func test_a_drop_made_inside_a_physics_flush_is_still_deferred() -> void:
	PhysicsFlush.enter()
	var drop := ItemPickup.drop(_world, _weapon(12, 2), Vector2(40.0, 0.0), _rng(SEED))
	PhysicsFlush.exit()
	(
		assert_bool(drop.is_inside_tree())
		. override_failure_message("an item was inserted while the physics server was flushing")
		. is_false()
	)
	await _physics_frames(2)
	assert_bool(drop.is_inside_tree()).is_true()


## The scatter hop belongs to the moment of the drop, so a drop that is being *put back* asks
## for none: `FloorPickups.apply()` replays a save, and a hop on every resume would walk the
## item further from where the player left it each time. It has to be answered in `drop()`,
## before the node is in the tree, because `_ready` is what performs the hop - clearing
## `hop_direction` on the returned node only worked while every insertion was deferred, and
## silently stopped working when they stopped being.
func test_a_drop_put_back_without_scatter_lands_exactly_where_it_was_saved() -> void:
	var where := Vector2(40.0, -24.0)
	var put_back := ItemPickup.drop(_world, _weapon(13, 2), where, null, false)
	assert_vector(put_back.global_position).is_equal(where)
	assert_vector(put_back.hop_direction).is_equal(Vector2.ZERO)
	await _physics_frames(30)
	(
		assert_vector(put_back.global_position)
		. override_failure_message("a restored item hopped away from its saved spot")
		. is_equal_approx(where, Vector2(0.5, 0.5))
	)

	# ...and an ordinary drop still scatters, which is the half this could have destroyed.
	var fresh := ItemPickup.drop(_world, _weapon(14, 2), where, _rng(SEED))
	await _physics_frames(30)
	(
		assert_float(fresh.global_position.distance_to(where))
		. override_failure_message("a fresh drop landed dead on its spawn point instead of popping")
		. is_greater(1.0)
	)
