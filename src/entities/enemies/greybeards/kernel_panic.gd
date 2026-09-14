## Elite greybeard: every few seconds the screen tints `danger` and spikes erupt from random
## walkable tiles around the player (hazards spawned by the traps module).
class_name KernelPanic
extends EnemyBase

## Number of panics triggered (tests/debug).
var panics: int = 0
var _smash: MeleeLunge
var _panic_left: float = 2.0


func _ready() -> void:
	super._ready()
	_smash = add_attack(MeleeLunge.new()) as MeleeLunge


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# `is_asleep` matters more here than anywhere: a panic drops spike hazards *around the
	# player*, so an elite that has not noticed them yet would be attacking across the floor.
	if def == null or state == State.DEAD or is_asleep() or not is_instance_valid(target):
		return
	_panic_left -= delta
	if _panic_left <= 0.0:
		_panic_left = def.param(&"panic_interval", 4.0)
		panic()


## Emits the screen tint and the spike hazards around the target.
func panic() -> void:
	panics += 1
	var tint := Desktop.palette.get_color(&"danger") if Desktop.palette != null else Color.RED
	tint.a = 0.35
	EventBus.screen_tint.emit(tint, def.param(&"tint_duration", 0.6))
	var origin := target.global_position if is_instance_valid(target) else global_position
	var spread := def.param(&"spike_spread", 64.0)
	for i in range(def.param_int(&"spike_count", 6)):
		var offset := Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
		var pos := walkable_point(origin + offset)
		pos = (pos / Layers.TILE).floor() * Layers.TILE + Vector2.ONE * (Layers.TILE * 0.5)
		EventBus.spawn_hazard.emit(&"kernel_spike", pos, def.param(&"spike_duration", 5.0))
	telegraph.show_area(0.4, 20.0)


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	_smash.damage = base_damage()
	_smash.reach = 18.0
	_smash.width = 16.0
	_smash.knockback = 150.0
	run_attack(_smash, target.global_position)
