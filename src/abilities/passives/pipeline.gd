## Pipeline: kills chain into each other. Every kill stacks a short damage bonus, so the
## passive is worth nothing on a boss and enormous in a crowded room — the opposite shape to
## a flat damage passive, which is the point of having both in the pool.
class_name PipelinePassive
extends PassiveAbility

## Fraction of extra damage per stack.
@export var per_stack: float = 0.06
## Extra fraction per stack per tier above 1.
@export var per_tier: float = 0.02
@export var max_stacks: int = 5
## Seconds a stack lasts; every new kill refreshes the whole set.
@export var duration: float = 4.0

var _stacks: int = 0
var _generation: int = 0


## Damage fraction one stack is worth at the current tier.
func stack_value() -> float:
	return per_stack + per_tier * float(tier - 1)


## Stacks held right now (0 when the window has lapsed).
func stacks() -> int:
	return _stacks


func on_kill(player: Node2D, _victim: Node2D) -> void:
	var entity := player as Entity
	if entity == null or not entity.is_inside_tree():
		return
	_stacks = mini(_stacks + 1, maxi(1, max_stacks))
	_generation += 1
	var generation := _generation
	AbilityFx.flash(entity, &"heat", 0.1)
	entity.get_tree().create_timer(duration).timeout.connect(
		func() -> void:
			if generation == _generation:
				_stacks = 0
	)


func outgoing_damage_multiplier(_player: Node2D, _target: Node2D, _info: DamageInfo) -> float:
	return 1.0 + stack_value() * float(_stacks)


func remove(player: Node2D) -> void:
	_generation += 1
	_stacks = 0
	super(player)
