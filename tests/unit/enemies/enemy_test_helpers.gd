## Shared helpers for the enemy test suites.
class_name EnemyTestHelpers
extends RefCounted

const REGISTRY_PATH := "res://data/enemies/registry.tres"


static func registry() -> EnemyRegistry:
	return load(REGISTRY_PATH) as EnemyRegistry


static func def(id: StringName) -> EnemyDef:
	var found := registry().find(id)
	assert(found != null, "missing enemy def %s" % id)
	return found


static func seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Instantiates an enemy under `parent` at `pos` (floor 0, seeded rng).
static func spawn(id: StringName, parent: Node, pos: Vector2, floor_index: int = 0) -> EnemyBase:
	var enemy := EnemySpawner.instantiate(def(id), floor_index, pos, seeded(7))
	parent.add_child(enemy)
	enemy.global_position = pos
	return enemy


## A static blocker. `layer` defaults to WORLD; pass `Layers.PROP` for a solid prop, which an
## enemy body collides with just the same (`enemy_base.tscn` masks 4097 = WORLD | PROP).
static func wall(
	parent: Node, pos: Vector2, size: Vector2, layer: int = Layers.WORLD
) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = pos
	return body


static func count_children(parent: Node, type_check: Callable) -> int:
	var n := 0
	for child: Node in parent.get_children():
		if type_check.call(child):
			n += 1
	return n


static func hit(entity: Entity, amount: float, from: Node2D = null) -> float:
	var tags: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]
	var info := DamageInfo.create(amount, tags, from, Layers.Team.PLAYER)
	return entity.hurtbox.receive(info)
