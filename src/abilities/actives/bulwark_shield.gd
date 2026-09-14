## Temporary damage-absorbing shield for Bulwark, used only for entities whose player script
## does not implement `set_shield` (the shipped Player does — see BulwarkAbility). Routes the
## parent Entity's Hurtbox into a separate Health pool that mirrors the entity's armor, dodge
## and resistances, forwards overkill to the real Health, and emits a reflect pulse on every
## absorbed hit. Frees itself when the pool breaks or the duration ends, restoring whatever
## `health_override` the Hurtbox carried before.
class_name BulwarkShield
extends Node

signal absorbed(amount: float)
signal broken

const PULSE_INTERVAL := 0.2

var ability: ActiveAbility
var amount: float = 30.0
var duration: float = 3.0
var reflect_fraction: float = 0.5
var pulse_radius: float = 28.0
var pulse_knockback: float = 120.0
var pulse_tags: Array[StringName] = [
	DamageInfo.TAG_ABILITY, DamageInfo.TAG_MELEE, DamageInfo.TAG_PHYSICAL
]
var pool: Health
var _entity: Entity
var _time_left: float = 3.0
var _pulse_cooldown: float = 0.0
var _ring: BulwarkRing
var _previous_override: Health
var _broken := false


func setup(source_ability: ActiveAbility, shield_hp: float, seconds: float) -> BulwarkShield:
	ability = source_ability
	amount = maxf(1.0, shield_hp)
	duration = seconds
	_time_left = seconds
	return self


func _ready() -> void:
	_entity = get_parent() as Entity
	if _entity == null or _entity.hurtbox == null:
		queue_free()
		return
	pool = Health.new()
	pool.name = "ShieldPool"
	pool.max_hp = amount
	add_child(pool)
	pool.setup(amount)
	# Mirror the entity's mitigation so the shield never strips armor/dodge/resistances.
	var real := _entity.health
	if real != null:
		pool.armor = real.armor
		pool.dodge_chance = real.dodge_chance
		pool.resistances = real.resistances.duplicate()
	pool.damaged.connect(_on_pool_damaged)
	pool.died.connect(_on_pool_died)
	_previous_override = _entity.hurtbox.health_override
	_entity.hurtbox.health_override = pool
	_ring = BulwarkRing.new()
	_ring.radius = 12.0
	AbilityFx.bind_palette(_ring, &"accent")
	_entity.add_child(_ring)
	AbilityFx.ring(
		AbilityUtil.world_of(_entity), _entity.global_position, pulse_radius, &"accent", 0.3
	)


func _exit_tree() -> void:
	if (
		is_instance_valid(_entity)
		and _entity.hurtbox != null
		and _entity.hurtbox.health_override == pool
	):
		_entity.hurtbox.health_override = _previous_override
	if is_instance_valid(_ring):
		_ring.queue_free()


func remaining() -> float:
	return pool.hp if pool != null else 0.0


func _process(delta: float) -> void:
	_time_left -= delta
	_pulse_cooldown = maxf(0.0, _pulse_cooldown - delta)
	if _ring != null:
		_ring.fill = remaining() / amount
	if _time_left <= 0.0:
		queue_free()


## Overkill beyond the shield pool must still reach the entity's real Health, and hits that
## land in the same frame as the break (queue_free is deferred) must not be swallowed.
func _on_pool_damaged(info: DamageInfo) -> void:
	absorbed.emit(info.applied)
	_forward_overkill(info)
	AbilityFx.flash(_entity, &"accent", 0.12)
	if _pulse_cooldown > 0.0:
		return
	_pulse_cooldown = PULSE_INTERVAL
	# Hits arrive inside physics callbacks, where new Area2D state cannot be set: defer.
	_pulse.bind(maxf(1.0, info.applied * reflect_fraction)).call_deferred()


## Reflect pulse around the player dealing `reflected` damage.
func _pulse(reflected: float) -> void:
	if not is_instance_valid(_entity) or not _entity.is_inside_tree():
		return
	AbilityUtil.spawn_hitbox(
		_entity,
		ability,
		AbilityUtil.world_of(_entity),
		_entity.global_position,
		pulse_radius,
		0.12,
		pulse_tags,
		pulse_knockback,
		[],
		0.0,
		reflected / ability.tier_damage_scale()
	)
	AbilityFx.ring(
		AbilityUtil.world_of(_entity), _entity.global_position, pulse_radius, &"accent", 0.25
	)


## Passes whatever the pool could not soak down to the entity's real Health. The pool applies
## the same armor/dodge/resistances as the entity, so the unsoaked share of the *raw* amount
## is forwarded and mitigated once more to exactly the leftover. `Health` reports the split
## directly: `applied` is what the pool lost, `overkill` is the rest (it used to report the
## whole mitigated figure and this had to subtract the pool's own HP to find the remainder).
func _forward_overkill(info: DamageInfo) -> void:
	var soaked := info.applied
	var leftover := info.overkill
	var mitigated := soaked + leftover
	if leftover <= 0.001 or mitigated <= 0.0:
		return
	if _entity == null or _entity.health == null:
		return
	if _entity.hurtbox != null:
		_entity.hurtbox.health_override = _previous_override
	var rest := info.duplicate_info()
	rest.amount = info.amount * (leftover / mitigated)
	_entity.health.take_damage(rest)
	info.applied = soaked + rest.applied
	info.overkill = rest.overkill


func _on_pool_died(_killer: Node2D) -> void:
	if _broken:
		return
	_broken = true
	if is_instance_valid(_entity) and _entity.hurtbox != null:
		_entity.hurtbox.health_override = _previous_override
	broken.emit()
	AbilityFx.burst(AbilityUtil.world_of(_entity), _entity.global_position, &"accent", 16, 16.0)
	queue_free()
