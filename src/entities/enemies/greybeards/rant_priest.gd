## Greybeard support: empowers nearby allies every few seconds and screams to knock back.
class_name RantPriest
extends EnemyBase

## Number of aura pulses emitted (tests/debug).
var aura_pulses: int = 0
var _scream: AoEBurst
var _aura_left: float = 1.0


func _ready() -> void:
	super._ready()
	_scream = add_attack(AoEBurst.new()) as AoEBurst


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if def == null or state == State.DEAD or is_asleep():
		return
	_aura_left -= delta
	if _aura_left <= 0.0:
		_aura_left = def.param(&"aura_interval", 3.0)
		pulse_aura()


## The scream is an area attack: the tell must match the blast, not the commit range.
func telegraph_radius() -> float:
	return def.param(&"scream_radius", 40.0) if def != null else super()


## Applies EMPOWER to allies within the aura radius.
func pulse_aura() -> Array[EnemyBase]:
	var allies := nearby_allies(def.param(&"aura_radius", 48.0))
	for ally: EnemyBase in allies:
		ally.status.apply(
			StatusEffect.make(
				StatusEffect.Kind.EMPOWER,
				def.param(&"aura_duration", 3.5),
				def.param(&"aura_magnitude", 0.25),
				self
			)
		)
	aura_pulses += 1
	telegraph.show_area(0.3, def.param(&"aura_radius", 48.0))
	return allies


func _perform_attack() -> void:
	_scream.radius = def.param(&"scream_radius", 40.0)
	_scream.damage = maxf(1.0, base_damage() * 0.6)
	_scream.knockback = def.param(&"scream_knockback", 240.0)
	run_attack(_scream, global_position)
