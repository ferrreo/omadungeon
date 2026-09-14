## Base for every living thing (player, enemies, hirelings). Owns Health, Stats,
## StatusController, a Hurtbox and knockback handling. Subclasses drive `velocity`.
class_name Entity
extends CharacterBody2D

signal hit_received(info: DamageInfo)
signal died(killer: Node2D)

const KNOCKBACK_DECAY := 12.0

@export var team: Layers.Team = Layers.Team.ENEMY
@export var knockback_resistance: float = 0.0  # 0..1
@export var hurtbox_size: Vector2 = Vector2(10, 12)

var health: Health
var stats: Stats = Stats.new()
var status: StatusController
var hurtbox: Hurtbox
var knockback_velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var is_dying: bool = false


func _ready() -> void:
	collision_layer = Layers.PLAYER if team == Layers.Team.PLAYER else Layers.ENEMY
	collision_mask = Layers.WORLD | Layers.PROP
	health = get_node_or_null("Health") as Health
	if health == null:
		health = Health.new()
		health.name = "Health"
		add_child(health)
	status = get_node_or_null("Status") as StatusController
	if status == null:
		status = StatusController.new()
		status.name = "Status"
		add_child(status)
	hurtbox = get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox == null:
		hurtbox = Hurtbox.new()
		hurtbox.name = "Hurtbox"
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = hurtbox_size
		shape.shape = rect
		hurtbox.add_child(shape)
		add_child(hurtbox)
	hurtbox.team = team
	hurtbox.collision_layer = Layers.hurtbox_layer_for(team)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	stats.changed.connect(_on_stat_changed)
	_sync_health_from_stats(false)


## Applies max_hp/armor/dodge from Stats to Health.
func _sync_health_from_stats(keep_fraction: bool) -> void:
	health.setup(stats.get_value(&"max_hp"), keep_fraction)
	health.armor = stats.get_value(&"armor")
	health.dodge_chance = stats.get_value(&"dodge_chance")
	for tag: StringName in [&"fire", &"frost", &"shock", &"poison", &"arcane"]:
		health.resistances[tag] = stats.get_value(StringName("resist_" + tag))


func _on_stat_changed(stat: StringName, _value: float) -> void:
	if (
		stat == &"vitality"
		or stat == &"max_hp"
		or stat == &"armor"
		or stat == &"dodge_chance"
		or stat == &"fortune"
		or String(stat).begins_with("resist_")
	):
		_sync_health_from_stats(true)


func _on_damaged(info: DamageInfo) -> void:
	if info.knockback != Vector2.ZERO:
		knockback_velocity += info.knockback * (1.0 - clampf(knockback_resistance, 0.0, 1.0))
	for s: StatusEffect in info.statuses:
		status.apply(s)


## Hook for Hurtbox; subclasses may override (e.g. i-frames feedback).
func on_hit_received(info: DamageInfo) -> void:
	hit_received.emit(info)


func _on_died(killer: Node2D) -> void:
	if is_dying:
		return
	is_dying = true
	died.emit(killer)
	_die(killer)


## Override to play death animation; default frees the node.
func _die(_killer: Node2D) -> void:
	queue_free()


## Moves with knockback applied and decayed. Call from _physics_process after setting velocity.
func move_with_knockback(delta: float) -> void:
	var total := velocity + knockback_velocity
	knockback_velocity = knockback_velocity.move_toward(
		Vector2.ZERO, KNOCKBACK_DECAY * delta * 60.0
	)
	velocity = total
	move_and_slide()
	velocity = total - knockback_velocity


func effective_speed() -> float:
	return stats.get_value(&"move_speed") * status.speed_multiplier()


func can_act() -> bool:
	return not is_dying and not status.is_stunned()


## Outgoing damage multiplier for the given tags (stat + status).
func damage_multiplier(tags: Array[StringName]) -> float:
	var mult := status.damage_multiplier()
	var elemental: Array[StringName] = [
		DamageInfo.TAG_FIRE,
		DamageInfo.TAG_FROST,
		DamageInfo.TAG_SHOCK,
		DamageInfo.TAG_POISON,
		DamageInfo.TAG_ARCANE,
		DamageInfo.TAG_PHYSICAL,
	]
	for tag: StringName in tags:
		if (
			tag == DamageInfo.TAG_MELEE
			or tag == DamageInfo.TAG_RANGED
			or tag == DamageInfo.TAG_ABILITY
		):
			mult *= 1.0 + stats.get_value(StringName("damage_" + String(tag)))
		elif elemental.has(tag):
			mult *= 1.0 + stats.get_value(StringName("damage_" + String(tag)))
	return mult


## Builds outgoing DamageInfo with stats, crit and knockback applied.
func make_damage(
	base: float,
	tags: Array[StringName],
	dir: Vector2,
	knockback: float,
	rng: RandomNumberGenerator = null
) -> DamageInfo:
	var amount := base * damage_multiplier(tags)
	var info := DamageInfo.create(amount, tags, self, team)
	var crit_roll := rng.randf() if rng != null else randf()
	if crit_roll < stats.get_value(&"crit_chance"):
		info.is_crit = true
		info.amount *= stats.get_value(&"crit_mult")
	info.with_knockback(dir, knockback * stats.get_value(&"knockback"))
	return info
