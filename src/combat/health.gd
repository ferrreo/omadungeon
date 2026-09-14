## Node child of an Entity. Owns HP, armor application, invulnerability and death.
class_name Health
extends Node

signal damaged(info: DamageInfo)
signal healed(amount: float)
signal died(killer: Node2D)
signal hp_changed(hp: float, max_hp: float)

@export var max_hp: float = 100.0
var hp: float = 100.0
var invulnerable: bool = false
var armor: float = 0.0
## Fraction 0..1 chance to fully dodge an incoming hit (from Stats dodge_chance).
var dodge_chance: float = 0.0
var resistances: Dictionary = {}  # tag -> fraction reduced
var _dead: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	hp = max_hp


func setup(new_max: float, keep_fraction: bool = false) -> void:
	var fraction := hp / max_hp if max_hp > 0.0 else 1.0
	max_hp = maxf(1.0, new_max)
	hp = clampf(max_hp * fraction if keep_fraction else max_hp, 1.0, max_hp)
	hp_changed.emit(hp, max_hp)


func is_dead() -> bool:
	return _dead


func fraction() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0


## Applies damage. Returns the HP actually removed (0 if dodged/invulnerable), never more than
## the target had left; the excess lands in `info.overkill` so statistics never over-count.
func take_damage(info: DamageInfo) -> float:
	if _dead or invulnerable or info.amount <= 0.0:
		return 0.0
	if dodge_chance > 0.0 and not info.has_tag(DamageInfo.TAG_TRUE) and _rng.randf() < dodge_chance:
		return 0.0
	var amount := info.amount
	if not info.has_tag(DamageInfo.TAG_TRUE):
		amount *= Stats.armor_multiplier(armor)
		for tag: StringName in info.tags:
			amount *= 1.0 - clampf(float(resistances.get(tag, 0.0)), 0.0, 0.9)
	amount = maxf(1.0, roundf(amount)) if info.amount >= 1.0 else amount
	var hp_before := hp
	hp = maxf(0.0, hp - amount)
	var dealt := hp_before - hp
	info.applied = dealt
	info.overkill = amount - dealt
	damaged.emit(info)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_dead = true
		died.emit(info.source)
	return dealt


func heal(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var before := hp
	hp = minf(max_hp, hp + amount)
	var gained := hp - before
	if gained > 0.0:
		healed.emit(gained)
		hp_changed.emit(hp, max_hp)
	return gained


func revive(fraction_hp: float = 1.0) -> void:
	_dead = false
	hp = clampf(max_hp * fraction_hp, 1.0, max_hp)
	hp_changed.emit(hp, max_hp)
