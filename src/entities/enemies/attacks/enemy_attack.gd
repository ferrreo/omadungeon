## Base for reusable enemy attack helpers (Node2D so hitboxes follow the enemy). Added under an
## EnemyBase via `add_attack()`;
## the enemy drives it with `start()` / `tick()` while in the ATTACK state.
class_name EnemyAttack
extends Node2D

signal finished

var enemy: EnemyBase
var running: bool = false
## Status templates applied on every hit this attack lands (copied by StatusController).
var statuses: Array[StatusEffect] = []
## Radius (px) of the windup tell this attack deserves; 0 = let the enemy decide.
var telegraph_radius: float = 0.0


func start(target_pos: Vector2) -> void:
	running = true
	_start(target_pos)


## Override: begin the attack toward `target_pos`.
func _start(_target_pos: Vector2) -> void:
	pass


## Called each physics frame while running. Returns the velocity the enemy should use.
func tick(_delta: float) -> Vector2:
	return Vector2.ZERO


## Called after the enemy moved this frame (collision checks).
func after_move() -> void:
	pass


func stop() -> void:
	running = false
	_stop()


## Override: cleanup when interrupted.
func _stop() -> void:
	pass


func finish() -> void:
	if not running:
		return
	running = false
	_stop()
	finished.emit()


## Creates a Hitbox child with `shape` at `offset`, owned by the enemy's team.
##
## The insertion goes through `PhysicsFlush` for the same reason `EnemyBase.spawn_sibling`
## does: an attack built from inside a hit callback (a summoned enemy's `_ready`, an on-hit
## effect adding an attack) would otherwise hand the server a shape mid-flush and get it
## refused. The Hitbox is returned either way, and every caller only wires signals and fields
## on it, which is legal on a node that is not in the tree yet.
func make_hitbox(shape: Shape2D, offset: Vector2 = Vector2.ZERO) -> Hitbox:
	var hitbox := Hitbox.new()
	hitbox.name = "Hitbox"
	hitbox.team = enemy.team
	hitbox.source = enemy
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = offset
	hitbox.add_child(col)
	PhysicsFlush.add_child(self, hitbox)
	return hitbox


## Re-syncs a hitbox with the enemy's (possibly converted) team before use.
func sync_hitbox(hitbox: Hitbox) -> void:
	hitbox.team = enemy.team
	hitbox.collision_mask = Layers.hitbox_mask_for(enemy.team)
	hitbox.source = enemy


## A `damage_builder` Callable for Hitbox/Projectile that applies the enemy's stats/crit.
func damage_builder(base: float, tags: Array[StringName], knockback: float) -> Callable:
	return Callable(self, "build_damage").bind(base, tags, knockback)


func build_damage(
	target: Node2D, base: float, tags: Array[StringName], knockback: float
) -> DamageInfo:
	var dir := target.global_position - enemy.global_position
	if dir.length_squared() < 0.01:
		dir = enemy.facing
	var info := enemy.make_damage(base, tags, dir, knockback, enemy.rng)
	for effect: StatusEffect in statuses:
		info.with_status(effect)
	return info


## Direction from the enemy to `pos`, falling back to the enemy's facing.
func direction_to(pos: Vector2) -> Vector2:
	var d := pos - enemy.global_position
	return d.normalized() if d.length_squared() > 0.01 else enemy.facing
