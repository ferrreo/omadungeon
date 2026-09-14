## Shared helpers for the player module tests (not a test suite).
class_name PlayerTestHelpers
extends RefCounted

const PLAYER_SCENE := "res://src/player/player.tscn"


static func make_player() -> Player:
	var scene := load(PLAYER_SCENE) as PackedScene
	return scene.instantiate() as Player


static func load_class(id: String) -> ClassDef:
	return load("res://data/classes/%s.tres" % id) as ClassDef


## A bare enemy-team Entity with the default auto-created hurtbox.
static func make_dummy(pos: Vector2) -> Entity:
	var dummy := Entity.new()
	dummy.team = Layers.Team.ENEMY
	dummy.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 12)
	shape.shape = rect
	dummy.add_child(shape)
	return dummy


static func enemy_hit(amount: float, from: Node2D = null) -> DamageInfo:
	var tags: Array[StringName] = [DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL]
	return DamageInfo.create(amount, tags, from, Layers.Team.ENEMY)


static func wall(pos: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	return body


static func physics_frames(tree: SceneTree, count: int) -> void:
	for _i in range(count):
		await tree.physics_frame
