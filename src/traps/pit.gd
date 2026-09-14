## Pit (docs §9): always visible. A player body that enters while not dodging takes 10 damage and
## `EventBus.player_fell(pos)` fires so the RunManager can respawn them at the room entry.
## Enemies fall too (damage + shoved back out) unless they expose a truthy `floats` property.
class_name Pit
extends TrapBase

signal body_fell(body: Node2D)

const FALL_DAMAGE := 10.0
const REFALL_GRACE := 0.6
const SHOVE_STRENGTH := 180.0
## Meta key of the shared {instance id -> physics frame} re-fall grace map (see `_grace_map`).
const GRACE_META := &"trap_pit_fall_grace"

## Pit rectangle in pixels (a single tile by default).
@export var size: Vector2 = Vector2(16.0, 16.0)

var area: Area2D
var _inside: Array[Node2D] = []


func _init() -> void:
	kind = &"pit"
	damage = FALL_DAMAGE
	tags = [DamageInfo.TAG_TRAP, DamageInfo.TAG_TRUE]
	# Pits are always-on holes: a pressure plate must never put them through the trap cycle.
	plate_controlled = false
	hitbox_size = size


func configure(extra: Dictionary) -> void:
	super.configure(extra)
	if extra.has("size"):
		size = extra["size"]
	hitbox_size = size


func _uses_hitbox() -> bool:
	return false


func _on_setup() -> void:
	hitbox_size = size
	_rebuild_tell()
	area = Area2D.new()
	area.name = "PitArea"
	area.collision_layer = Layers.PIT
	area.collision_mask = Layers.PLAYER | Layers.ENEMY
	area.monitorable = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size - Vector2(4.0, 4.0)
	shape.shape = rect
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	tell.color.a = 0.0
	if sprite != null:
		sprite.scale = size / Vector2(16.0, 16.0)


func _on_body_entered(body: Node2D) -> void:
	if not _inside.has(body):
		_inside.append(body)


func _on_body_exited(body: Node2D) -> void:
	_inside.erase(body)


## {instance id -> physics frame the body may fall again on}, shared by every pit (and keyed on
## the global frame counter, not a per-pit delta) so a body straddling two adjacent pit tiles is
## not damaged twice for the same fall. Lives on the SceneTree (no static vars in this project).
func _grace_map() -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {}
	if not tree.has_meta(GRACE_META):
		tree.set_meta(GRACE_META, {})
	return tree.get_meta(GRACE_META)


func _on_idle_process(_delta: float) -> void:
	var grace := _grace_map()
	var now := Engine.get_physics_frames()
	for id: int in grace.keys():
		if int(grace[id]) <= now:
			grace.erase(id)
	for body: Node2D in _inside.duplicate():
		if not is_instance_valid(body):
			_inside.erase(body)
			continue
		if grace.has(body.get_instance_id()):
			continue
		if _can_fall(body):
			_fall(body)


## Dodging players hop over; floating enemies and trap-immune bodies never fall.
func _can_fall(body: Node2D) -> bool:
	if body.has_method("is_dodging") and bool(body.call("is_dodging")):
		return false
	if body.has_method("is_trap_immune") and bool(body.call("is_trap_immune")):
		return false
	var floats: Variant = body.get("floats")
	if floats is bool and bool(floats):
		return false
	return true


func _fall(body: Node2D) -> void:
	var grace_frames := int(REFALL_GRACE * float(Engine.physics_ticks_per_second))
	_grace_map()[body.get_instance_id()] = Engine.get_physics_frames() + grace_frames
	var info := DamageInfo.create(damage, tags, self, Layers.Team.NEUTRAL)
	var team_value: Variant = body.get("team")
	var is_player := team_value is int and int(team_value) == Layers.Team.PLAYER
	if not is_player:
		var out := body.global_position - global_position
		if out.length_squared() < 0.001:
			out = Vector2.RIGHT
		info.with_knockback(out, SHOVE_STRENGTH)
	# Route through the hurtbox when the body has one so `hit_received` hooks (enemy aggro,
	# ability listeners) see pit damage like any other hit.
	var hurtbox: Variant = body.get("hurtbox")
	if hurtbox is Hurtbox:
		(hurtbox as Hurtbox).receive(info)
	else:
		var health: Variant = body.get("health")
		if health is Health:
			(health as Health).take_damage(info)
	_spawn_hit_particles(body.global_position)
	body_fell.emit(body)
	if is_player:
		EventBus.player_fell.emit(body.global_position)
