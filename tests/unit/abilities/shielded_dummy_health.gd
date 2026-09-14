## Minimal PlayerHealth stand-in: a shield pool that soaks damage before HP and announces how
## much it soaked. Mirrors src/player/player_health.gd without depending on it.
class_name ShieldedDummyHealth
extends Health

signal shield_absorbed(amount: float, info: DamageInfo)

var shield: float = 0.0


func take_damage(info: DamageInfo) -> float:
	if is_dead() or invulnerable or info.amount <= 0.0:
		return 0.0
	if shield <= 0.0:
		return super.take_damage(info)
	var absorbed := minf(shield, info.amount)
	shield -= absorbed
	shield_absorbed.emit(absorbed, info)
	var remaining := info.amount - absorbed
	if remaining <= 0.0:
		info.applied = 0.0
		return 0.0
	var rest := info.duplicate_info()
	rest.amount = remaining
	var dealt := super.take_damage(rest)
	info.applied = rest.applied
	return dealt
