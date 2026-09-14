## The music's grip on the enemies themselves (docs §10.2): the floor's `sight_scale`,
## `cadence_scale` and `loot_scale` reach every regular enemy through `EnemyBase.set_mood`,
## and from there its sight range, its attack cooldown and its gold. A summon inherits its
## parent's mood, and an enemy nobody gave one behaves exactly as its def says.
class_name EnemyMoodTest
extends GdUnitTestSuite


func _root() -> Node2D:
	var root := auto_free(Node2D.new()) as Node2D
	add_child(root)
	return root


func test_an_enemy_with_no_mood_is_its_def() -> void:
	var enemy := EnemyTestHelpers.spawn(&"juggler", _root(), Vector2(64, 64))
	var profile := AwarenessProfile.shared()
	assert_float(enemy.awareness.sight).is_equal_approx(
		profile.sight_for(enemy.def.attack_range, enemy.def.sight_range), 0.001
	)
	assert_float(enemy.attack_cooldown()).is_equal_approx(enemy.def.attack_cooldown, 0.001)


func test_the_mood_scales_sight_and_attack_cadence() -> void:
	var enemy := EnemyTestHelpers.spawn(&"juggler", _root(), Vector2(64, 64))
	var base_sight := enemy.awareness.sight
	enemy.set_mood(1.3, 0.75, 1.0)
	assert_float(enemy.awareness.sight).is_equal_approx(base_sight * 1.3, 0.01)
	assert_float(enemy.attack_cooldown()).is_equal_approx(enemy.def.attack_cooldown * 0.75, 0.001)
	enemy.set_mood(0.75, 1.3, 1.0)
	assert_float(enemy.awareness.sight).is_less(base_sight)
	assert_float(enemy.attack_cooldown()).is_greater(enemy.def.attack_cooldown)


## A calm floor may doze an enemy, but never to inside its own reach: a Manpage Hurler on the
## quietest track still notices the player it could already be hitting.
func test_a_calm_mood_never_puts_a_ranged_enemy_to_sleep_inside_its_own_reach() -> void:
	var enemy := EnemyTestHelpers.spawn(&"manpage_hurler", _root(), Vector2(64, 64))
	enemy.set_mood(0.1, 1.0, 1.0)
	assert_float(enemy.awareness.sight).is_greater_equal(enemy.def.attack_range * 1.1 - 0.001)


func test_the_mood_scales_the_gold_an_enemy_drops() -> void:
	var drops: Array[int] = []
	var on_pickup := func(kind: StringName, _pos: Vector2, amount: int) -> void:
		if kind == &"gold":
			drops.append(amount)
	EventBus.spawn_pickup.connect(on_pickup)
	for scale: float in [1.0, 2.0]:
		var enemy := EnemyTestHelpers.spawn(&"juggler", _root(), Vector2(64, 64))
		enemy.set_mood(1.0, 1.0, scale)
		enemy._drop_loot()
	EventBus.spawn_pickup.disconnect(on_pickup)
	assert_int(drops.size()).is_equal(2)
	# Same seeded rng, same roll; only the mood differs.
	assert_int(drops[1]).is_equal(int(roundf(drops[0] * 2.0)))


func test_what_an_enemy_spawns_inherits_its_mood() -> void:
	var root := _root()
	var parent := EnemyTestHelpers.spawn(&"juggler", root, Vector2(64, 64))
	parent.set_mood(1.2, 0.8, 1.1)
	var child := EnemySpawner.instantiate(
		EnemyTestHelpers.def(&"juggler"), 0, Vector2(80, 64), EnemyTestHelpers.seeded(3)
	)
	parent.spawn_sibling(child, Vector2(80, 64))
	assert_float(child.mood_sight).is_equal_approx(1.2, 0.001)
	assert_float(child.mood_cadence).is_equal_approx(0.8, 0.001)
	assert_float(child.mood_loot).is_equal_approx(1.1, 0.001)


## `FloorPopulator` is where the floor's `GenParams` reach the pack.
func test_the_populator_hands_the_floors_mood_to_every_regular_enemy() -> void:
	var populator := FloorPopulator.new()
	populator.registry = EnemyTestHelpers.registry()
	populator.floor_index = 1
	populator.sight_scale = 1.25
	populator.cadence_scale = 0.9
	populator.loot_scale = 1.15
	var room := FloorData.Room.new()
	room.id = 3
	room.type = FloorData.RoomType.COMBAT
	room.rect = Rect2i(2, 2, 10, 8)
	room.enemy_spawns = [Vector2i(4, 4), Vector2i(6, 4), Vector2i(8, 4)]
	var pack := populator.spawn_pack(room, EnemyTestHelpers.seeded(11))
	assert_int(pack.size()).is_greater(0)
	for node: Node2D in pack:
		var enemy := auto_free(node) as EnemyBase
		assert_float(enemy.mood_sight).is_equal_approx(1.25, 0.001)
		assert_float(enemy.mood_cadence).is_equal_approx(0.9, 0.001)
		assert_float(enemy.mood_loot).is_equal_approx(1.15, 0.001)
