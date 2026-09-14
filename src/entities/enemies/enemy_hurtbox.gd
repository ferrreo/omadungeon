## Hurtbox used by every enemy scene: lets the EnemyBase modify incoming damage before
## Health applies it (frontal shields, trap immunity).
class_name EnemyHurtbox
extends Hurtbox


func receive(info: DamageInfo) -> float:
	var enemy := entity as EnemyBase
	if enemy != null:
		enemy.modify_incoming(info)
	return super.receive(info)
