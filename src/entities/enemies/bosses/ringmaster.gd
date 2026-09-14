## Floor 3 boss — The Ringmaster. Three health-gated acts:
## 1 "Opening Act": telegraphed whip pull that yanks the player in, jugglers every 8 s (cap 4).
## 2 "Ring of Fire": a rotating wall of fire with one moving gap, honkers join the summon pool,
##   the whip becomes a two-hit combo.
## 3 "Final Bow": confetti barrage with moving safe lanes, a clown car rolls in, the whip
##   sweeps a full circle.
class_name Ringmaster
extends BossBase

const PHASE_TITLES: PackedStringArray = ["Opening Act", "Ring of Fire", "Final Bow"]
const PHASE1_POOL: PackedStringArray = ["juggler"]
const PHASE2_POOL: PackedStringArray = ["juggler", "honker"]
const CAR_ID := &"clown_car"
const SUMMON_RING := 34.0
const CAR_RING := 44.0

var whip: RingmasterWhip
var confetti: RingmasterConfetti
var fire_ring: RingmasterFireRing

var _summon_left: float = 0.0
var _attacks_done: int = 0
var _car_summoned: bool = false


func _ready() -> void:
	super._ready()
	whip = add_attack(RingmasterWhip.new()) as RingmasterWhip
	confetti = add_attack(RingmasterConfetti.new()) as RingmasterConfetti
	fire_ring = RingmasterFireRing.new()
	fire_ring.name = "FireRing"
	add_child(fire_ring)
	fire_ring.setup(self)
	_configure_from_def()
	_summon_left = summon_interval()


## Seconds between summon waves (data-driven).
func summon_interval() -> float:
	return def.param(&"summon_interval", 8.0) if def != null else 8.0


## Name of the current act, for the HUD/toasts.
func phase_title() -> String:
	return PHASE_TITLES[clampi(phase - 1, 0, PHASE_TITLES.size() - 1)]


func _configure_from_def() -> void:
	if def == null:
		return
	whip.reach = def.param(&"whip_reach", 88.0)
	whip.width = def.param(&"whip_width", 11.0)
	whip.telegraph_time = def.param(&"whip_telegraph", 0.45)
	whip.pull_strength = def.param(&"whip_pull", 280.0)
	whip.sweep_time = def.param(&"whip_sweep_time", 1.2)
	whip.damage = base_damage()
	confetti.lanes = def.param_int(&"confetti_lanes", 14)
	confetti.safe_lanes = def.param_int(&"confetti_safe_lanes", 3)
	confetti.waves = def.param_int(&"confetti_waves", 3)
	confetti.damage = maxf(1.0, base_damage() * 0.6)
	fire_ring.segments = def.param_int(&"fire_segments", 16)
	fire_ring.gap_slots = def.param_int(&"fire_gap_slots", 3)
	fire_ring.spin_speed = def.param(&"fire_spin", 0.45)
	fire_ring.telegraph_time = def.param(&"fire_telegraph", 1.0)
	fire_ring.damage = maxf(1.0, base_damage() * 0.55)


# --- summons ------------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	# Adds only roll in once the fight is live, so an empty arena never fills up with clowns.
	if state != State.DEAD and not in_transition and is_instance_valid(target):
		_summon_left -= delta
		if _summon_left <= 0.0:
			_summon_left = summon_interval()
			summon_wave()
	super._physics_process(delta)


## Spawns the next wave of clowns (capped by `summon_cap`). Returns the new adds.
func summon_wave() -> Array[EnemyBase]:
	return summon_adds(_summon_pool(), def.param_int(&"summon_count", 2), SUMMON_RING)


## Defs the current phase may summon: jugglers in act 1, jugglers + honkers afterwards.
func _summon_pool() -> Array[EnemyDef]:
	var ids := PHASE1_POOL if phase <= 1 else PHASE2_POOL
	var pool: Array[EnemyDef] = []
	if def == null:
		return pool
	for candidate: EnemyDef in def.summon_defs:
		if candidate != null and ids.has(String(candidate.id)):
			pool.append(candidate)
	return pool


func _summon_car() -> void:
	if _car_summoned or def == null:
		return
	_car_summoned = true
	var cars: Array[EnemyDef] = []
	for candidate: EnemyDef in def.summon_defs:
		if candidate != null and candidate.id == CAR_ID:
			cars.append(candidate)
	summon_adds(cars, 1, CAR_RING)


# --- phases -------------------------------------------------------------------------------


func _on_phase_entered(new_phase: int) -> void:
	whip.damage = base_damage()
	match new_phase:
		2:
			whip.hits = 2
			fire_ring.start(arena_center, arena_radius - Layers.TILE)
		3:
			whip.hits = 1
			whip.sweep = true
			_summon_car()
	_summon_left = minf(_summon_left, 2.0)
	EventBus.toast.emit("%s — %s" % [boss_name(), phase_title()], 2.0)


# --- attacks ------------------------------------------------------------------------------


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	_attacks_done += 1
	if phase >= 3 and _attacks_done % 2 == 0:
		confetti.damage = maxf(1.0, base_damage() * 0.6)
		run_attack(confetti, target.global_position)
		return
	whip.damage = base_damage()
	run_attack(whip, target.global_position)


func telegraph_radius() -> float:
	return whip.reach * 0.5 if whip != null else super.telegraph_radius()


func _on_boss_death(_killer: Node2D) -> void:
	fire_ring.stop()
	EventBus.toast.emit("%s takes a final bow" % boss_name(), 2.5)
