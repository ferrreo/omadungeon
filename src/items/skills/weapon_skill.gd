## Base for weapon skills (RMB / LT): spawns hitboxes and projectiles credited to the player
## (via Entity.make_damage) and reports hits on EventBus.player_hit_dealt so passives react.
## Duck-types player extras: `rng` (combat RNG), `spend_gold`, and an `AbilitySlots` child
## exposing `outgoing_damage_multiplier(target, info)`.
class_name WeaponSkill
extends ActiveAbility

var _fallback_rng: RandomNumberGenerator


## The player's combat RNG when it has one, else a per-skill seeded fallback (deterministic).
func rng_of(player: Node2D) -> RandomNumberGenerator:
	var r: Variant = player.get("rng")
	if r is RandomNumberGenerator:
		return r
	if _fallback_rng == null:
		_fallback_rng = RandomNumberGenerator.new()
		_fallback_rng.seed = hash(id)
	return _fallback_rng


## Node world spawns are parented to (the player's parent, or the player itself).
static func world_of(player: Node) -> Node:
	var parent := player.get_parent()
	return parent if parent != null else player


## Aim direction, falling back to the entity's facing, then +X.
static func aim_dir(player: Node2D, aim: Vector2) -> Vector2:
	if aim.length_squared() > 0.0001:
		return aim.normalized()
	var entity := player as Entity
	if entity != null and entity.facing.length_squared() > 0.0001:
		return entity.facing.normalized()
	return Vector2.RIGHT


## Common precondition: a living, in-tree Entity that may act.
func can_cast(player: Node2D) -> bool:
	var entity := player as Entity
	return entity != null and entity.is_inside_tree() and entity.can_act()


## Outgoing DamageInfo for this skill (tier scaling, stats, crit, knockback, slot multipliers).
func build_damage(
	player: Entity,
	dir: Vector2,
	knockback: float,
	target: Node2D = null,
	base_override: float = -1.0
) -> DamageInfo:
	var base := damage if base_override < 0.0 else base_override
	var info := player.make_damage(base * tier_damage_scale(), tags, dir, knockback, rng_of(player))
	var slots := AbilityUtil.slots_of(player)
	if slots != null:
		info.amount *= slots.outgoing_damage_multiplier(target, info)
	# Unique effects the items module hosts itself (sudo) are not in AbilitySlots.
	var equipment: Variant = player.get("equipment")
	if equipment is Object and (equipment as Object).has_method("outgoing_damage_multiplier"):
		info.amount *= float((equipment as Object).call("outgoing_damage_multiplier", target, info))
	return info


## Forwards a Hitbox hit to the global bus (target resolved to its Entity when a Hurtbox).
static func report_hit(target: Node2D, info: DamageInfo) -> void:
	var node := target
	var hurtbox := target as Hurtbox
	if hurtbox != null and hurtbox.entity != null:
		node = hurtbox.entity
	EventBus.player_hit_dealt.emit(node, info)


## Spawns a player Hitbox with `shape` at `pos` (local to `player` when `attached`, else world),
## active for `duration`, freed afterwards.
func spawn_hitbox(
	player: Entity,
	pos: Vector2,
	shape: Shape2D,
	rotation: float,
	duration: float,
	knockback: float,
	statuses: Array[StatusEffect] = [],
	attached: bool = true,
	multi_hit_interval: float = 0.0,
	base_override: float = -1.0
) -> Hitbox:
	var hitbox := Hitbox.new()
	hitbox.name = "SkillHitbox"
	hitbox.team = player.team
	hitbox.source = player
	hitbox.tags = tags
	hitbox.knockback = knockback
	hitbox.multi_hit_interval = multi_hit_interval
	hitbox.statuses = statuses
	var collision := CollisionShape2D.new()
	collision.shape = shape
	hitbox.add_child(collision)
	hitbox.damage_builder = func(target: Node2D) -> DamageInfo:
		var dir := target.global_position - hitbox.global_position
		if dir.length_squared() < 0.001:
			dir = target.global_position - player.global_position
		var info := build_damage(player, dir, knockback, target, base_override)
		for s: StatusEffect in statuses:
			info.with_status(s)
		return info
	hitbox.hit_dealt.connect(report_hit)
	var parent: Node = player if attached else world_of(player)
	parent.add_child(hitbox)
	if attached:
		hitbox.position = pos
	else:
		hitbox.global_position = pos
	hitbox.rotation = rotation
	hitbox.activate(duration)
	hitbox.get_tree().create_timer(duration + 0.05).timeout.connect(hitbox.queue_free)
	return hitbox


## Spawns a player Projectile (own collision shape so walls stop it) from world `pos`.
func spawn_projectile(
	player: Entity,
	pos: Vector2,
	dir: Vector2,
	speed: float,
	lifetime: float,
	knockback: float,
	statuses: Array[StatusEffect] = [],
	texture: Texture2D = null,
	pierce: int = 0,
	base_override: float = -1.0
) -> Projectile:
	var projectile := Projectile.new()
	projectile.name = "SkillProjectile"
	projectile.pierce = pierce + int(player.stats.get_value(&"pierce"))
	projectile.sprite_texture = texture
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 3.0
	collision.shape = circle
	projectile.add_child(collision)
	var builder := func(target: Node2D) -> DamageInfo:
		var info := build_damage(player, projectile.direction, knockback, target, base_override)
		for s: StatusEffect in statuses:
			info.with_status(s)
		return info
	projectile.setup(
		player,
		player.team,
		dir,
		builder,
		speed * player.stats.get_value(&"projectile_speed"),
		lifetime
	)
	world_of(player).add_child(projectile)
	projectile.global_position = pos
	projectile.hitbox.hit_dealt.connect(report_hit)
	return projectile
