## Tinkerer pest: on contact steals a random primary stat point (`player.steal_stat`) and
## drops it back as a stat orb. The debt is paid on ANY despawn, not only on death: a floor
## teardown (quitting, or descending) rebuilds the pack from its EnemyDef, so a thief that
## took the point to the grave with it would cost an honest player a permanent stat.
class_name ConfigGremlin
extends EnemyBase

## Stat stolen from the player, or empty.
var stolen_stat: StringName = &""
var _bite: MeleeLunge


func _ready() -> void:
	super._ready()
	_bite = add_attack(MeleeLunge.new()) as MeleeLunge
	_bite.hitbox.hit_dealt.connect(_on_bite)


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	_bite.damage = base_damage()
	_bite.reach = 12.0
	_bite.knockback = 60.0
	run_attack(_bite, target.global_position)


func _on_bite(hurtbox: Hurtbox, _info: DamageInfo) -> void:
	if stolen_stat != &"" or is_converted:
		return
	var victim: Node2D = (
		hurtbox.entity if hurtbox.entity != null else hurtbox.get_parent() as Node2D
	)
	if victim == null or not victim.has_method(&"steal_stat"):
		return
	var stat: StringName = Stats.PRIMARY[rng.randi_range(0, Stats.PRIMARY.size() - 1)]
	if PickupBase.call_player(victim, &"steal_stat", [stat, 1]):
		stolen_stat = stat


func _on_death(_killer: Node2D) -> void:
	_repay_theft()


func _exit_tree() -> void:
	# Covers every despawn that is not a death: a floor teardown on quit or descent, and any
	# other path that frees the thief while it still owes the player a point.
	_repay_theft()


## Pays the stolen point back as an orb, once. Safe to call from any despawn path.
func _repay_theft() -> void:
	if stolen_stat == &"":
		return
	var stat := stolen_stat
	stolen_stat = &""
	EventBus.spawn_pickup.emit(&"stat_orb", global_position, Stats.PRIMARY.find(stat))
