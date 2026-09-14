## Legendary "sudo": +25% damage against elites and bosses. With great power...
class_name UniqueSudo
extends PassiveAbility

const ELITE_MULTIPLIER := 1.25


func _init() -> void:
	super()
	id = &"sudo"
	display_name = "sudo"
	description = "+25% damage to elites and bosses. You are root here."
	max_tier = 1


func outgoing_damage_multiplier(_player: Node2D, target: Node2D, _info: DamageInfo) -> float:
	return ELITE_MULTIPLIER if is_elite(target) else 1.0


## True when the target carries an EnemyDef flagged elite/boss, or bool `is_elite`/`is_boss`.
static func is_elite(target: Node2D) -> bool:
	if target == null:
		return false
	var node: Node = target
	var hurtbox := target as Hurtbox
	if hurtbox != null and hurtbox.entity != null:
		node = hurtbox.entity
	var def: Variant = node.get("def")
	if def is EnemyDef:
		return (def as EnemyDef).is_elite or (def as EnemyDef).is_boss
	var elite: Variant = node.get("is_elite")
	if elite is bool and elite:
		return true
	var boss: Variant = node.get("is_boss")
	return boss is bool and boss
