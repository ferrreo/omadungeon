## A status effect definition + live instance (duration/stacks). Applied via StatusController.
class_name StatusEffect
extends Resource

enum Kind { BURN, FROST, SHOCK, POISON, STUN, TAUNT, SLOW, HASTE, WEAKEN, EMPOWER }

@export var kind: Kind = Kind.BURN
@export var duration: float = 3.0
## Damage per second for DoT kinds, or magnitude (0.3 = 30%) for slow/haste/weaken/empower.
@export var magnitude: float = 5.0
@export var max_stacks: int = 3
var stacks: int = 1
var remaining: float = 0.0
var source: Node2D = null


static func make(effect_kind: Kind, dur: float, mag: float, from: Node2D = null) -> StatusEffect:
	var s := StatusEffect.new()
	s.kind = effect_kind
	s.duration = dur
	s.magnitude = mag
	s.source = from
	s.remaining = dur
	return s


func is_dot() -> bool:
	return kind == Kind.BURN or kind == Kind.POISON


func damage_tag() -> StringName:
	match kind:
		Kind.BURN:
			return DamageInfo.TAG_FIRE
		Kind.POISON:
			return DamageInfo.TAG_POISON
		Kind.SHOCK:
			return DamageInfo.TAG_SHOCK
		Kind.FROST:
			return DamageInfo.TAG_FROST
	return DamageInfo.TAG_ARCANE


func display_name() -> String:
	return (Kind.keys()[kind] as String).capitalize()
