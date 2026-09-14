## Node child of an Entity. Tracks active StatusEffects, ticks DoTs, exposes multipliers.
## Frost at 3 stacks becomes a freeze (stun) — docs §6.
class_name StatusController
extends Node

signal status_added(effect: StatusEffect)
signal status_removed(kind: StatusEffect.Kind)

const DOT_TICK := 0.5
const FROST_FREEZE_DURATION := 1.5

var effects: Dictionary = {}  # Kind -> StatusEffect
var _tick_left: float = DOT_TICK
var _entity: Entity


func _ready() -> void:
	_entity = get_parent() as Entity


func apply(effect: StatusEffect) -> void:
	if is_instance_valid(_entity) and _entity.health != null and _entity.health.is_dead():
		return
	var applier := _live_source(effect)
	var kind := effect.kind
	if effects.has(kind):
		var existing: StatusEffect = effects[kind]
		existing.remaining = maxf(existing.remaining, effect.duration)
		existing.magnitude = maxf(existing.magnitude, effect.magnitude)
		existing.stacks = mini(existing.stacks + 1, effect.max_stacks)
		existing.source = applier if applier != null else _live_source(existing)
	else:
		var inst := effect.duplicate() as StatusEffect
		inst.remaining = effect.duration
		inst.stacks = 1
		inst.source = applier
		effects[kind] = inst
		status_added.emit(inst)
	if kind == StatusEffect.Kind.FROST and (effects[kind] as StatusEffect).stacks >= 3:
		remove(StatusEffect.Kind.FROST)
		apply(StatusEffect.make(StatusEffect.Kind.STUN, FROST_FREEZE_DURATION, 0.0, applier))


func remove(kind: StatusEffect.Kind) -> void:
	if effects.erase(kind):
		status_removed.emit(kind)


func has(kind: StatusEffect.Kind) -> bool:
	return effects.has(kind)


func clear() -> void:
	for kind: StatusEffect.Kind in effects.keys():
		status_removed.emit(kind)
	effects.clear()


func is_stunned() -> bool:
	return has(StatusEffect.Kind.STUN)


func is_taunted() -> bool:
	return has(StatusEffect.Kind.TAUNT)


func taunt_source() -> Node2D:
	return _live_source(effects[StatusEffect.Kind.TAUNT]) if is_taunted() else null


## The node that applied `effect`, or null once it has been freed.
##
## `StatusEffect.source` is the one reference this controller keeps to something it does not
## own, and it routinely outlives it: an enemy that sets a 3 s burn is freed a second and a half
## after it dies (`EnemyBase.DEATH_FALLBACK_TIME`), with a second and a half of burn still to
## tick. Handing that reference on is not a wrong reading, it is a **dropped tick**:
## `DamageInfo.create` declares `from: Node2D`, and GDScript refuses a freed instance at a
## statically typed parameter, which abandons the call. The burn then silently stops dealing
## damage for the rest of its duration with nothing but one stderr line per tick to say so.
## The dangling reference is dropped the first time it is noticed, so nothing pays twice.
func _live_source(effect: StatusEffect) -> Node2D:
	if effect == null or effect.source == null:
		return null
	if is_instance_valid(effect.source):
		return effect.source
	effect.source = null
	return null


## Movement speed multiplier from slow/frost/haste.
func speed_multiplier() -> float:
	var mult := 1.0
	if has(StatusEffect.Kind.FROST):
		mult *= 1.0 - 0.15 * (effects[StatusEffect.Kind.FROST] as StatusEffect).stacks
	if has(StatusEffect.Kind.SLOW):
		mult *= 1.0 - (effects[StatusEffect.Kind.SLOW] as StatusEffect).magnitude
	if has(StatusEffect.Kind.HASTE):
		mult *= 1.0 + (effects[StatusEffect.Kind.HASTE] as StatusEffect).magnitude
	return clampf(mult, 0.1, 3.0)


## Outgoing damage multiplier from weaken/empower.
func damage_multiplier() -> float:
	var mult := 1.0
	if has(StatusEffect.Kind.WEAKEN):
		mult *= 1.0 - (effects[StatusEffect.Kind.WEAKEN] as StatusEffect).magnitude
	if has(StatusEffect.Kind.EMPOWER):
		mult *= 1.0 + (effects[StatusEffect.Kind.EMPOWER] as StatusEffect).magnitude
	return mult


func _physics_process(delta: float) -> void:
	if effects.is_empty():
		return
	_tick_left -= delta
	var do_tick := _tick_left <= 0.0
	if do_tick:
		_tick_left += DOT_TICK
	for kind: StatusEffect.Kind in effects.keys():
		var effect: StatusEffect = effects[kind]
		effect.remaining -= delta
		if do_tick and effect.is_dot() and is_instance_valid(_entity) and _entity.health != null:
			var tags: Array[StringName] = [effect.damage_tag(), DamageInfo.TAG_TRUE]
			var info := DamageInfo.create(
				effect.magnitude * effect.stacks * DOT_TICK,
				tags,
				_live_source(effect),
				Layers.Team.NEUTRAL
			)
			_entity.health.take_damage(info)
		if effect.remaining <= 0.0:
			remove(kind)
