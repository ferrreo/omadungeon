## Greybeard with a frontal shield: hits from the front arc are reduced 90%; flank it.
class_name BeardWarden
extends EnemyBase

## Last hit was blocked by the shield (tests/debug).
var last_hit_blocked: bool = false
var _bash: MeleeLunge


func _ready() -> void:
	super._ready()
	_bash = add_attack(MeleeLunge.new()) as MeleeLunge


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_asleep() or state == State.DEAD or state == State.STUNNED:
		return
	if is_instance_valid(target):
		face(target.global_position)


func _perform_attack() -> void:
	if not is_instance_valid(target):
		return
	_bash.damage = base_damage()
	_bash.reach = 16.0
	_bash.width = 14.0
	_bash.knockback = 170.0
	run_attack(_bash, target.global_position)


## True when `dir` (from this warden outward) falls inside the shield arc.
func is_frontal(dir: Vector2) -> bool:
	var half_arc := deg_to_rad(def.param(&"shield_arc_deg", 70.0) * 0.5)
	return facing.dot(dir.normalized()) >= cos(half_arc)


func _modify_incoming(info: DamageInfo) -> void:
	last_hit_blocked = false
	if info.has_tag(DamageInfo.TAG_TRUE):
		return
	if is_frontal(incoming_direction(info)):
		info.amount *= 1.0 - def.param(&"shield_reduction", 0.9)
		info.knockback *= 0.2
		last_hit_blocked = true
