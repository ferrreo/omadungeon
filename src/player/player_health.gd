## Player Health: adds a shield pool that absorbs damage before HP (Bulwark and similar).
## Named "Health" in the player scene so `Entity` adopts it.
class_name PlayerHealth
extends Health

## Emitted when the shield soaked `amount` of an incoming hit (before HP was touched).
signal shield_absorbed(amount: float, info: DamageInfo)
signal shield_changed(amount: float)

var shield: float = 0.0


## Seeds the inherited dodge-chance roll from the run's combat stream so a fixed run seed
## produces a fixed fight (docs §1). Player calls this whenever its `rng` is assigned.
func set_rng(stream: RandomNumberGenerator) -> void:
	if stream != null:
		_rng = stream


## Sets the absorb pool (0 clears it). Not additive: abilities decide stacking rules.
func set_shield(amount: float) -> void:
	shield = maxf(0.0, amount)
	shield_changed.emit(shield)


## Shield soaks first; whatever remains goes through the normal armor/HP path.
func take_damage(info: DamageInfo) -> float:
	if is_dead() or invulnerable or info.amount <= 0.0:
		return 0.0
	if shield <= 0.0:
		return super.take_damage(info)
	var absorbed := minf(shield, info.amount)
	shield -= absorbed
	shield_changed.emit(shield)
	shield_absorbed.emit(absorbed, info)
	var remaining := info.amount - absorbed
	if remaining <= 0.0:
		info.applied = 0.0
		info.overkill = 0.0
		return 0.0
	var rest := info.duplicate_info()
	rest.amount = remaining
	var dealt := super.take_damage(rest)
	info.applied = rest.applied
	info.overkill = rest.overkill
	return dealt
