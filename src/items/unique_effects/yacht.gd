## Legendary "Yacht": public code, private yacht. Hits have a chance to shake gold loose,
## which is credited to the player straight away (with a coin-coloured burst at the hit).
##
## The payment path is deliberately unconditional. An earlier version asked
## `EventBus.spawn_pickup.get_connections().size()` whether a pickup system was listening and
## paid through the signal when it was: that made a shipping item's behaviour depend on how
## many objects in the process happened to be connected to a global signal, which is not a
## property of the game state. `gold_earned` is now always the gold the player actually got.
class_name UniqueYacht
extends PassiveAbility

const CHANCE := 0.25
const GOLD_MIN := 1
const GOLD_MAX := 3

## Total gold this effect has paid the player. Always equals what the player received.
var gold_earned: int = 0
var _rng: RandomNumberGenerator


func _init() -> void:
	super()
	id = &"yacht"
	display_name = "Yacht"
	description = "Public code, private yacht: 25% chance per hit to shake loose 1-3 gold."
	max_tier = 1


func apply(_player: Node2D) -> void:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = RunRng.hash_combine(GameState.run_seed, hash(id))


func on_hit_dealt(player: Node2D, target: Node2D, _info: DamageInfo) -> void:
	if player == null or not is_instance_valid(player):
		return
	if _rng == null:
		apply(player)
	if _rng.randf() >= CHANCE:
		return
	var amount := _rng.randi_range(GOLD_MIN, GOLD_MAX)
	var entity := player as Entity
	if entity != null:
		amount = maxi(1, int(roundf(amount * (1.0 + entity.stats.get_value(&"gold_find")))))
	if not player.has_method("add_gold"):
		return
	player.call("add_gold", amount)
	gold_earned += amount
	var pos := (
		target.global_position
		if target != null and is_instance_valid(target)
		else player.global_position
	)
	if player.is_inside_tree():
		var world: Node = player.get_parent() if player.get_parent() != null else player
		SkillFx.burst(world, pos, Color("ffd166"), 4, 40.0, 0.3)
