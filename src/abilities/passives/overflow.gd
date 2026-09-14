## Overflow (Wizard innate): every Nth active cast is free (no cooldown) and stronger.
## Counts casts via `on_active_used`, then arms `AbilitySlots.free_cast_next` with
## `free_cast_power` so the next cast's damage (AbilityUtil.make_damage) is boosted.
class_name OverflowPassive
extends PassiveAbility

@export var every_n: int = 4
@export var power_bonus: float = 0.25
@export var per_tier: float = 0.1
var casts: int = 0


func power() -> float:
	return 1.0 + power_bonus + per_tier * (tier - 1)


func on_active_used(player: Node2D, _ability: ActiveAbility) -> void:
	var slots := AbilityUtil.slots_of(player)
	if slots == null:
		return
	casts += 1
	if casts % every_n == every_n - 1:
		slots.free_cast_next = true
		slots.free_cast_power = power()
		if player.is_inside_tree():
			AbilityFx.flash(player, &"magic", 0.2)


## Cast counter survives a save/load so the every-Nth cadence does not reset (AbilitySlots
## round-trips this through `to_dict`/`from_dict`).
func to_state() -> Dictionary:
	return {"casts": casts}


func from_state(state: Dictionary) -> void:
	casts = int(state.get("casts", 0))


func remove(player: Node2D) -> void:
	super(player)
	casts = 0
	var slots := AbilityUtil.slots_of(player)
	if slots != null:
		slots.free_cast_next = false
		slots.free_cast_power = 1.0
