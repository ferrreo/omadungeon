## Legendary "Omakase": the chef picks. Every cleared room swaps in a random buff
## (registered under owner_id() so it is always exactly one buff at a time).
class_name UniqueOmakase
extends PassiveAbility

## Menu of {stat, mode ("flat"/"percent"), value, label}.
const MENU: Array[Dictionary] = [
	{"stat": &"damage_melee", "mode": "flat", "value": 0.15, "label": "+15% melee damage"},
	{"stat": &"damage_ranged", "mode": "flat", "value": 0.15, "label": "+15% ranged damage"},
	{"stat": &"damage_ability", "mode": "flat", "value": 0.15, "label": "+15% ability damage"},
	{"stat": &"attack_speed", "mode": "percent", "value": 0.12, "label": "+12% attack speed"},
	{"stat": &"move_speed", "mode": "percent", "value": 0.1, "label": "+10% move speed"},
	{"stat": &"armor", "mode": "flat", "value": 8.0, "label": "+8 armor"},
	{"stat": &"crit_chance", "mode": "flat", "value": 0.08, "label": "+8% crit chance"},
	{"stat": &"cooldown_reduction", "mode": "flat", "value": 0.1, "label": "-10% cooldowns"},
]

var current: Dictionary = {}
var rooms_served: int = 0
var _rng: RandomNumberGenerator


func _init() -> void:
	super()
	id = &"omakase"
	display_name = "Omakase"
	description = "Chef's choice: a different buff every cleared room."
	max_tier = 1


func apply(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = RunRng.hash_combine(GameState.run_seed, hash(id))
	if not current.is_empty():
		_serve(player, current)


func remove(player: Node2D) -> void:
	var entity := player as Entity
	if entity == null or not is_instance_valid(entity):
		return
	super(entity)


func on_room_cleared(player: Node2D) -> void:
	if _rng == null:
		apply(player)
	var entity := player as Entity
	if entity == null:
		return
	entity.stats.remove_owner(owner_id())
	var pick: Dictionary = MENU[_rng.randi_range(0, MENU.size() - 1)]
	if pick == current and MENU.size() > 1:
		pick = MENU[(MENU.find(pick) + 1) % MENU.size()]
	current = pick
	rooms_served += 1
	_serve(player, current)
	EventBus.toast.emit("Omakase: %s" % String(current["label"]), 1.6)


func _serve(player: Node2D, dish: Dictionary) -> void:
	var entity := player as Entity
	if entity == null or dish.is_empty():
		return
	if String(dish["mode"]) == "percent":
		entity.stats.add_percent(dish["stat"], owner_id(), float(dish["value"]))
	else:
		entity.stats.add_flat(dish["stat"], owner_id(), float(dish["value"]))
