## Cane skill (Oligarch): throw a fistful of gold; whoever it hits stops to count it (stun).
## Costs gold when the player exposes `spend_gold(amount) -> bool`; refused when broke.
class_name SkillBribe
extends WeaponSkill

const GOLD_COST := 10
const SPEED := 240.0
const LIFETIME := 0.8
const KNOCKBACK := 40.0
const STUN_BASE := 1.5
const STUN_PER_TIER := 0.5


func _activate(player: Node2D, aim: Vector2) -> bool:
	if not can_cast(player):
		return false
	var entity := player as Entity
	if entity.has_method("spend_gold") and not bool(entity.call("spend_gold", GOLD_COST)):
		EventBus.toast.emit("Bribe needs %d gold" % GOLD_COST, 1.0)
		return false
	var dir := aim_dir(entity, aim)
	entity.facing = dir
	var stun := StatusEffect.make(
		StatusEffect.Kind.STUN, STUN_BASE + STUN_PER_TIER * float(tier - 1), 0.0, entity
	)
	var statuses: Array[StatusEffect] = [stun]
	var coin := spawn_projectile(
		entity,
		entity.global_position + dir * 8.0,
		dir,
		SPEED,
		LIFETIME,
		KNOCKBACK,
		statuses,
		SkillFx.dot_texture(Color("ffd166"), 2)
	)
	coin.rotate_to_direction = false
	var tween := coin.create_tween()
	tween.tween_property(coin, "rotation", TAU * 2.0, LIFETIME)
	SkillFx.burst(
		world_of(entity), entity.global_position + dir * 8.0, Color("ffd166"), 6, 40.0, 0.25
	)
	return true
