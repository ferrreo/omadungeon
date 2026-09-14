## Floor 9 final boss: The Suit. Three phases, each one a hostile-takeover joke played
## straight:
##
## 1. "Due Diligence" — hires contractors from all three factions in telegraphed waves and
##    fires aimed bursts of gold coins between them.
## 2. "Hostile Takeover" — seizes a growing sector of the arena (a damage-over-time region,
##    see `TheSuitZone`) and buys one of the player's ability slots on the way in.
## 3. "Exit Liquidity" — hires the three faction elites once, shrinks the arena to a circle
##    and buys its own health back (2%/s) until both briefcase adds are broken.
##
## Every phase transition takes one more ability slot; the slots are released when The Suit
## dies. Death emits `EventBus.enemy_died` like any other enemy, which is how RunManager ends
## the run in victory on floor 9.
class_name TheSuit
extends BossBase

const REGISTRY_PATH := "res://data/enemies/registry.tres"
## `gold_coin_shot` cell of assets/sprites/projectiles.png.
const COIN_SPRITE := 10
## Seconds between the volleys of one aimed burst.
const BURST_INTERVAL := 0.16
## The buy-back heals in chunks rather than every frame (fewer HUD updates, same rate).
const HEAL_TICK := 0.25
const PHASE_NAMES: Array[String] = ["", "Due Diligence", "Hostile Takeover", "Exit Liquidity"]

## Arena hazard: the seized sector in phase 2, the shrinking arena in phase 3.
var zone: TheSuitZone

var _coins: ThrowProjectile
var _briefcases: Array[TheSuitBriefcase] = []
var _bought_slots: Array[int] = []
var _slots: AbilitySlots
var _applied_phases: Array[int] = []
var _hire_left: float = 0.0
var _hire_spawn_left: float = -1.0
var _burst_left: int = 0
var _burst_timer: float = 0.0
var _heal_accum: float = 0.0


func _ready() -> void:
	super._ready()
	_coins = add_attack(ThrowProjectile.new()) as ThrowProjectile
	_coins.sprite_index = COIN_SPRITE
	_coins.radius = 4.0
	_hire_left = def.param(&"hire_delay", 3.0) if def != null else 3.0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state == State.DEAD or in_transition or def == null:
		return
	_tick_hiring(delta)
	_tick_buyback(delta)


# --- phase 1: due diligence -------------------------------------------------------------


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	_burst_left = def.param_int(&"coin_volleys", 3)
	_burst_timer = BURST_INTERVAL
	_fire_volley()


func _attack_process(delta: float) -> void:
	super._attack_process(delta)
	if _burst_left <= 0:
		return
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		_burst_timer = BURST_INTERVAL
		_fire_volley()


func _attack_finished() -> bool:
	return _burst_left <= 0 and super._attack_finished()


## Fires one aimed fan of gold coins at the current target.
func _fire_volley() -> void:
	if not is_instance_valid(target) or _burst_left <= 0:
		_burst_left = 0
		return
	_burst_left -= 1
	_coins.count = def.param_int(&"coin_count", 5)
	_coins.spread_degrees = def.param(&"coin_spread", 26.0)
	_coins.speed = def.param(&"coin_speed", 160.0)
	_coins.damage = base_damage() * def.param(&"coin_damage_mult", 0.5)
	_coins.knockback = 45.0
	_coins.lifetime = 2.4
	run_attack(_coins, target.global_position)


func _tick_hiring(delta: float) -> void:
	if _hire_spawn_left > 0.0:
		_hire_spawn_left -= delta
		if _hire_spawn_left <= 0.0:
			_hire_spawn_left = -1.0
			hire_wave()
		return
	if phase > 2 or def.summon_defs.is_empty():
		return
	_hire_left -= delta
	if _hire_left > 0.0:
		return
	_hire_left = def.param(&"hire_interval", 7.0) * (1.0 if phase == 1 else 1.5)
	var tell := def.param(&"hire_telegraph", 0.8)
	telegraph_arc(global_position, def.param(&"hire_radius", 40.0), 0.0, TAU, tell, 2.0)
	_hire_spawn_left = tell


## Hires one contractor from every faction listed in `def.summon_defs` (capped by `summon_cap`).
func hire_wave() -> Array[EnemyBase]:
	var hired: Array[EnemyBase] = []
	if def == null:
		return hired
	var radius := def.param(&"hire_radius", 40.0)
	for hire_def: EnemyDef in def.summon_defs:
		var one: Array[EnemyDef] = [hire_def]
		hired.append_array(summon_adds(one, 1, radius))
	if not hired.is_empty():
		EventBus.toast.emit("The Suit hires %d contractors" % hired.size(), 1.4)
	return hired


# --- phase changes ------------------------------------------------------------------------


func _on_transition_started(next: int) -> void:
	var label := PHASE_NAMES[clampi(next, 0, PHASE_NAMES.size() - 1)]
	EventBus.toast.emit("The Suit — Phase %d: %s" % [next, label], 2.5)


## Phases are applied in order even when one huge hit skips a threshold, so the player never
## loses a slot (or an elite wave) just because they burst the boss down.
func _on_phase_entered(new_phase: int) -> void:
	for step in range(2, new_phase + 1):
		if _applied_phases.has(step):
			continue
		_applied_phases.append(step)
		if step == 2:
			_start_takeover()
		elif step == 3:
			_start_liquidity()


func _start_takeover() -> void:
	buy_ability_slot()
	_ensure_zone()
	zone.arm(
		TheSuitZone.Mode.SEIZE, def.param(&"zone_telegraph", 1.5), def.param(&"seize_time", 26.0)
	)


func _start_liquidity() -> void:
	buy_ability_slot()
	_ensure_zone()
	zone.arm(
		TheSuitZone.Mode.SHRINK, def.param(&"zone_telegraph", 1.5), def.param(&"shrink_time", 30.0)
	)
	summon_cap += def.param_int(&"elite_extra_cap", 3)
	hire_elites()
	open_briefcases()


func _ensure_zone() -> void:
	if zone != null and is_instance_valid(zone):
		return
	zone = TheSuitZone.new()
	zone.name = "TakeoverZone"
	zone.sector_angle = rng.randf() * TAU
	zone.setup(
		arena_center,
		arena_radius,
		base_damage() * def.param(&"zone_damage_mult", 0.35),
		def.param(&"zone_tick", 0.75),
		self
	)
	spawn_sibling(zone, arena_center)


# --- phase 3: exit liquidity ---------------------------------------------------------------


## The three faction elites available on this floor, one per faction, in faction order.
func elite_defs() -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	var registry := load(REGISTRY_PATH) as EnemyRegistry
	if registry == null:
		return out
	var pool := registry.candidates(floor_index, true)
	var factions: Array[int] = [
		EnemyDef.Faction.CLOWNS, EnemyDef.Faction.GREYBEARDS, EnemyDef.Faction.TINKERERS
	]
	for faction: int in factions:
		for candidate: EnemyDef in pool:
			if int(candidate.faction) == faction:
				out.append(candidate)
				break
	return out


## Spawns the faction elites once (they bypass nothing: the summon cap was raised for them).
func hire_elites() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	var radius := def.param(&"elite_radius", 56.0) if def != null else 56.0
	for elite: EnemyDef in elite_defs():
		var one: Array[EnemyDef] = [elite]
		out.append_array(summon_adds(one, 1, radius))
	if not out.is_empty():
		EventBus.toast.emit("Exit liquidity: the elites cash out", 2.0)
	return out


## Opens the briefcases that keep the buy-back running. Returns the cases that were placed.
func open_briefcases() -> Array[TheSuitBriefcase]:
	_briefcases.clear()
	var count := def.param_int(&"briefcase_count", 2) if def != null else 2
	var latches := def.param_int(&"briefcase_latches", 4) if def != null else 4
	var radius := def.param(&"briefcase_radius", 60.0) if def != null else 60.0
	var start := rng.randf() * TAU
	for i in range(count):
		var case := TheSuitBriefcase.new()
		case.name = "Briefcase%d" % i
		case.setup(latches)
		case.broken.connect(_on_briefcase_broken)
		var angle := start + TAU * float(i) / float(maxi(1, count))
		var pos := clamp_to_arena(arena_center + Vector2.from_angle(angle) * radius)
		spawn_sibling(case, walkable_point(pos))
		_briefcases.append(case)
	if not _briefcases.is_empty():
		EventBus.toast.emit("Break the briefcases to stop the buy-back", 3.0)
	return _briefcases


## Briefcases still intact (broken/freed ones are pruned).
func live_briefcases() -> Array[TheSuitBriefcase]:
	var alive: Array[TheSuitBriefcase] = []
	for case: TheSuitBriefcase in _briefcases:
		if is_instance_valid(case) and not case.is_broken:
			alive.append(case)
	_briefcases = alive
	return alive


## True while The Suit is buying its health back (phase 3 with at least one case intact).
func is_buying_back() -> bool:
	return phase >= 3 and not health.is_dead() and not live_briefcases().is_empty()


func _tick_buyback(delta: float) -> void:
	if not is_buying_back():
		_heal_accum = 0.0
		return
	_heal_accum += delta
	if _heal_accum < HEAL_TICK:
		return
	var seconds := _heal_accum
	_heal_accum = 0.0
	health.heal(health.max_hp * def.param(&"heal_percent", 0.02) * seconds)


func _on_briefcase_broken(case: TheSuitBriefcase) -> void:
	_briefcases.erase(case)
	if live_briefcases().is_empty():
		EventBus.toast.emit("Buy-back stopped — The Suit is losing money", 2.5)
	else:
		EventBus.toast.emit("One briefcase down", 1.5)


# --- hostile takeover of the player's loadout ----------------------------------------------


## Disables one of the player's ability slots. Returns the slot index taken, or -1.
func buy_ability_slot() -> int:
	var slots := player_slots()
	if slots == null:
		return -1
	var index := _pick_slot(slots)
	if index < 0:
		EventBus.toast.emit("The Suit finds nothing left worth buying", 2.0)
		return -1
	slots.set_slot_disabled(index, true)
	_bought_slots.append(index)
	var ability := slots.get_ability(index)
	var label := ability.display_name if ability != null else "slot %d" % (index + 1)
	EventBus.toast.emit("The Suit buys out %s — slot %d disabled" % [label, index + 1], 3.5)
	return index


## Re-enables every slot The Suit took (the deal dies with him).
func release_bought_slots() -> void:
	var slots := player_slots()
	if slots != null:
		for index: int in _bought_slots:
			slots.set_slot_disabled(index, false)
	_bought_slots.clear()


## The player's AbilitySlots node, or null when the player has none (tests, dummies).
func player_slots() -> AbilitySlots:
	if _slots != null and is_instance_valid(_slots):
		return _slots
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var found := node.get_node_or_null(NodePath(AbilitySlots.NODE_NAME)) as AbilitySlots
		if found != null:
			_slots = found
			return _slots
	return null


## Prefers a slot that actually holds an ability so the loss is felt and readable.
func _pick_slot(slots: AbilitySlots) -> int:
	var fallback := -1
	for index in range(AbilitySlots.SLOT_COUNT):
		if slots.is_slot_disabled(index):
			continue
		if slots.get_ability(index) != null:
			return index
		if fallback < 0:
			fallback = index
	return fallback


# --- death ---------------------------------------------------------------------------------


func _on_boss_death(_killer: Node2D) -> void:
	release_bought_slots()
	if zone != null and is_instance_valid(zone):
		zone.queue_free()
	for case: TheSuitBriefcase in live_briefcases():
		case.queue_free()
	_briefcases.clear()
	EventBus.toast.emit("The Suit liquidates. The dungeon is yours.", 4.0)
