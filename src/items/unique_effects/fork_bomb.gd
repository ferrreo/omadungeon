## Legendary "Fork Bomb": every projectile hit forks into two shards (40% damage, tagged so
## shards never fork again). Also raises the `projectile_fork` flag on the player for the
## weapon controller (meta `fork_bomb` and `flags["projectile_fork"]` when the player has one).
class_name UniqueForkBomb
extends PassiveAbility

const FORK_TAG := &"forked"
const FLAG := &"projectile_fork"
const SPLIT_DAMAGE := 0.4
const SPLIT_SPEED := 200.0
const SPLIT_LIFETIME := 0.6
const SPLIT_ANGLE := PI / 4.0
## Damage tags that mark a hit as a projectile hit. `arcane` is here because a staff bolt is a
## projectile the player fired, and staves carry `arcane`/`ability` rather than `ranged`: each
## weapon family scales off exactly one primary stat (docs §4.2), which is what makes a class's
## own family measurably its own. Without this line the legendary silently did nothing for a
## whole weapon family.
const PROJECTILE_TAGS: Array[StringName] = [DamageInfo.TAG_RANGED, DamageInfo.TAG_ARCANE]

var forks_spawned: int = 0


func _init() -> void:
	super()
	id = &"fork_bomb"
	display_name = "Fork Bomb"
	description = ":(){ :|:& };: — projectile hits fork into two shards."
	max_tier = 1


func apply(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.set_meta(&"fork_bomb", true)
	var flags: Variant = player.get("flags")
	if flags is Dictionary:
		(flags as Dictionary)[FLAG] = true


func remove(player: Node2D) -> void:
	var entity := player as Entity
	if entity == null or not is_instance_valid(entity):
		return
	super(entity)
	if entity.has_meta(&"fork_bomb"):
		entity.remove_meta(&"fork_bomb")
	var flags: Variant = entity.get("flags")
	if flags is Dictionary:
		(flags as Dictionary).erase(FLAG)


## True when `info` is a shot rather than a swing: any of `PROJECTILE_TAGS`.
static func _is_projectile_hit(info: DamageInfo) -> bool:
	for tag: StringName in PROJECTILE_TAGS:
		if info.has_tag(tag):
			return true
	return false


func on_hit_dealt(player: Node2D, target: Node2D, info: DamageInfo) -> void:
	if info == null or info.has_tag(FORK_TAG) or not _is_projectile_hit(info):
		return
	var entity := player as Entity
	if (
		entity == null
		or target == null
		or not entity.is_inside_tree()
		or not is_instance_valid(target)
	):
		return
	var origin := target.global_position
	var base_dir := (
		info.knockback.normalized() if info.knockback.length_squared() > 0.001 else entity.facing
	)
	if base_dir.length_squared() < 0.001:
		base_dir = Vector2.RIGHT
	var tags: Array[StringName] = info.tags.duplicate()
	tags.append(FORK_TAG)
	forks_spawned += 2
	# The hook fires from inside Hitbox._on_area_entered (physics query flush), where enabling
	# a hitbox's monitoring is refused; the shards are therefore spawned next idle frame.
	_spawn_shards.call_deferred(entity, origin, base_dir, info.amount * SPLIT_DAMAGE, tags)


## Spawns the two shards. Deferred from `on_hit_dealt` (never call during a physics flush).
func _spawn_shards(
	entity: Entity, origin: Vector2, base_dir: Vector2, amount: float, tags: Array[StringName]
) -> void:
	if entity == null or not is_instance_valid(entity) or not entity.is_inside_tree():
		return
	var world: Node = entity.get_parent() if entity.get_parent() != null else entity
	for side: float in [-1.0, 1.0]:
		var dir := base_dir.rotated(side * SPLIT_ANGLE)
		var shard := Projectile.new()
		shard.name = "ForkShard"
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 3.0
		shape.shape = circle
		shard.add_child(shape)
		shard.sprite_texture = SkillFx.dot_texture(Color("8be9fd"), 2)
		var builder := func(t: Node2D) -> DamageInfo:
			var d := DamageInfo.create(amount, tags, entity, entity.team)
			d.with_knockback(t.global_position - origin, 20.0)
			return d
		shard.setup(entity, entity.team, dir, builder, SPLIT_SPEED, SPLIT_LIFETIME)
		world.add_child(shard)
		shard.global_position = origin + dir * 6.0
		shard.hitbox.hit_dealt.connect(WeaponSkill.report_hit)
	SkillFx.burst(world, origin, Color("8be9fd"), 6, 50.0, 0.25)
