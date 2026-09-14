## Static helpers shared by concrete abilities: damage building (stats, crit, slot multipliers),
## enemy lookup, and spawning Hitboxes/Projectiles that report hits to `EventBus.player_hit_dealt`.
class_name AbilityUtil
extends RefCounted

const ENEMY_GROUP := &"enemy"
const SLOTS_NODE := &"AbilitySlots"
## SceneTree meta keys for the shared per-frame enemy query: turret, hireling and Tiling WM
## all poll every frame (or every outgoing hit), so re-walking the group list each time is
## pure waste. Kept on the tree rather than in a static so gdlint's definition order holds.
const META_ENEMY_CACHE := &"ability_enemy_cache"
const META_ENEMY_CACHE_FRAME := &"ability_enemy_cache_frame"
const META_ENEMY_CACHE_SIZE := &"ability_enemy_cache_size"
## Per-entity fallback crit stream for owners exposing neither AbilitySlots nor `rng`.
const META_FALLBACK_RNG := &"ability_fallback_rng"


## The AbilitySlots node of `player`, or null when the entity has none (standalone tests).
static func slots_of(player: Node) -> AbilitySlots:
	if player == null:
		return null
	return player.get_node_or_null(NodePath(SLOTS_NODE)) as AbilitySlots


## Node that world-space spawns (projectiles, hitboxes, turrets) are parented to.
static func world_of(player: Node) -> Node:
	var parent := player.get_parent()
	return parent if parent != null else player


## Aim direction, falling back to the entity's facing when the stick/mouse is idle.
static func aim_dir(player: Node2D, aim: Vector2) -> Vector2:
	if aim.length_squared() > 0.0001:
		return aim.normalized()
	if player is Entity:
		var facing := (player as Entity).facing
		if facing.length_squared() > 0.0001:
			return facing.normalized()
	return Vector2.RIGHT


## Builds outgoing DamageInfo for an ability hit: tier scaling, stat multipliers, crit
## (with optional bonus), knockback, then AbilitySlots multipliers (passives, overflow, buffs).
static func make_damage(
	player: Entity,
	ability: ActiveAbility,
	tags: Array[StringName],
	dir: Vector2,
	knockback: float,
	target: Node2D = null,
	crit_bonus: float = 0.0,
	base_override: float = -1.0
) -> DamageInfo:
	# Builders run lazily at impact, which can be long after the cast (turret, fireball orb,
	# hireling): the caster may already be gone when a projectile finally lands.
	if not is_instance_valid(player) or player.stats == null:
		return DamageInfo.create(0.0, tags, null, Layers.Team.PLAYER)
	var slots := slots_of(player)
	var base := ability.damage if base_override < 0.0 else base_override
	var amount := base * ability.tier_damage_scale() * player.damage_multiplier(tags)
	var info := DamageInfo.create(amount, tags, player, player.team)
	var rng := crit_rng(player, slots)
	var roll := rng.randf()
	if roll < player.stats.get_value(&"crit_chance") + crit_bonus:
		info.is_crit = true
		info.amount *= player.stats.get_value(&"crit_mult")
	info.with_knockback(dir, knockback * player.stats.get_value(&"knockback"))
	if slots != null:
		info.amount *= slots.cast_power(ability)
		info.amount *= slots.outgoing_damage_multiplier(target, info)
	return info


## Deterministic RNG for ability crit rolls: the AbilitySlots combat stream, else the owner's
## own `rng` (Player has one). Never the global `randf()` (docs §1).
static func crit_rng(player: Node, slots: AbilitySlots) -> RandomNumberGenerator:
	if slots != null and slots.rng != null:
		return slots.rng
	var owner_rng: Variant = player.get("rng")
	if owner_rng is RandomNumberGenerator:
		return owner_rng
	if not player.has_meta(META_FALLBACK_RNG):
		var fallback := RandomNumberGenerator.new()
		fallback.seed = hash(player.name)
		player.set_meta(META_FALLBACK_RNG, fallback)
	return player.get_meta(META_FALLBACK_RNG) as RandomNumberGenerator


## Living enemy entities, cached for the current frame. Enemies are contractually in the
## "enemy" group (docs §5); `deep` additionally walks the whole tree and exists for tests and
## scratch scenes whose enemies never joined the group - never use it on a hot path.
static func enemies(tree: SceneTree, deep: bool = false) -> Array[Entity]:
	var out: Array[Entity] = []
	if tree == null:
		return out
	var frame := Engine.get_process_frames()
	var group := tree.get_nodes_in_group(ENEMY_GROUP)
	# Reuse this frame's answer, but only while the group is unchanged and every cached entry
	# is still alive, so a spawn or despawn inside the same frame is never missed and a freed
	# entity can never be handed back.
	if (
		not deep
		and int(tree.get_meta(META_ENEMY_CACHE_FRAME, -1)) == frame
		and int(tree.get_meta(META_ENEMY_CACHE_SIZE, -1)) == group.size()
	):
		var cached := tree.get_meta(META_ENEMY_CACHE) as Array[Entity]
		if _all_alive(cached):
			return cached
	for node: Node in group:
		var e := node as Entity
		if e != null and e.team == Layers.Team.ENEMY and not e.is_dying and e.is_inside_tree():
			out.append(e)
	if deep and out.is_empty():
		_collect_enemies(tree.root, out)
	if not deep:
		tree.set_meta(META_ENEMY_CACHE, out)
		tree.set_meta(META_ENEMY_CACHE_FRAME, frame)
		tree.set_meta(META_ENEMY_CACHE_SIZE, group.size())
	return out


## True when every cached entity is still valid, alive and in the tree.
static func _all_alive(cached: Array[Entity]) -> bool:
	for e: Entity in cached:
		if not is_instance_valid(e) or e.is_dying or not e.is_inside_tree():
			return false
	return true


static func _collect_enemies(node: Node, out: Array[Entity]) -> void:
	var e := node as Entity
	if e != null and e.team == Layers.Team.ENEMY and not e.is_dying:
		out.append(e)
	for child: Node in node.get_children():
		_collect_enemies(child, out)


## Enemies within `radius` of `pos`, nearest first.
static func enemies_near(
	tree: SceneTree, pos: Vector2, radius: float, deep: bool = false
) -> Array[Entity]:
	var out: Array[Entity] = []
	var r2 := radius * radius
	for e: Entity in enemies(tree, deep):
		if e.global_position.distance_squared_to(pos) <= r2:
			out.append(e)
	out.sort_custom(
		func(a: Entity, b: Entity) -> bool:
			return (
				a.global_position.distance_squared_to(pos)
				< b.global_position.distance_squared_to(pos)
			)
	)
	return out


## Closest enemy within `radius` (single min scan - no sorting, this runs every frame).
static func nearest_enemy(
	tree: SceneTree, pos: Vector2, radius: float, deep: bool = false
) -> Entity:
	var best: Entity = null
	var best_d2 := radius * radius
	for e: Entity in enemies(tree, deep):
		var d2 := e.global_position.distance_squared_to(pos)
		if d2 <= best_d2:
			best_d2 = d2
			best = e
	return best


## True when the enemy is flagged elite/boss via an EnemyDef `def` or bool properties.
static func is_elite(enemy: Node) -> bool:
	var def: Variant = enemy.get("def")
	if def is EnemyDef:
		return (def as EnemyDef).is_elite or (def as EnemyDef).is_boss
	var elite: Variant = enemy.get("is_elite")
	if elite is bool and elite:
		return true
	var boss: Variant = enemy.get("is_boss")
	return boss is bool and boss


## Forwards a Hitbox hit to the global bus so passives (vampiric, hotkey, ...) react.
static func report_hit(target: Node2D, info: DamageInfo) -> void:
	var node := target
	var hurtbox := target as Hurtbox
	if hurtbox != null and hurtbox.entity != null:
		node = hurtbox.entity
	EventBus.player_hit_dealt.emit(node, info)


## Spawns a circular player Hitbox at `pos` (or as a child of `parent` at local offset when
## `attach` is true), activates it for `duration` and frees it afterwards.
static func spawn_hitbox(
	player: Entity,
	ability: ActiveAbility,
	parent: Node,
	pos: Vector2,
	radius: float,
	duration: float,
	tags: Array[StringName],
	knockback: float,
	statuses: Array[StatusEffect] = [],
	multi_hit_interval: float = 0.0,
	base_override: float = -1.0
) -> Hitbox:
	var hitbox := Hitbox.new()
	hitbox.name = "AbilityHitbox"
	hitbox.team = player.team
	hitbox.source = player
	hitbox.tags = tags
	hitbox.knockback = knockback
	hitbox.multi_hit_interval = multi_hit_interval
	hitbox.statuses = statuses
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	hitbox.add_child(shape)
	hitbox.damage_builder = func(target: Node2D) -> DamageInfo:
		var dir := target.global_position - hitbox.global_position
		if dir.length_squared() < 0.001:
			dir = target.global_position - player.global_position
		var info := make_damage(player, ability, tags, dir, knockback, target, 0.0, base_override)
		for s: StatusEffect in statuses:
			info.with_status(s)
		return info
	hitbox.hit_dealt.connect(report_hit)
	if parent == null or not parent.is_inside_tree():
		hitbox.free()
		return null
	parent.add_child(hitbox)
	hitbox.global_position = pos
	hitbox.activate(duration)
	hitbox.get_tree().create_timer(duration + 0.05).timeout.connect(hitbox.queue_free)
	return hitbox


## Spawns a player Projectile from `pos` in `dir` with a damage builder that credits `player`.
static func spawn_projectile(
	player: Entity,
	ability: ActiveAbility,
	parent: Node,
	pos: Vector2,
	dir: Vector2,
	speed: float,
	lifetime: float,
	tags: Array[StringName],
	knockback: float,
	crit_bonus: float = 0.0,
	statuses: Array[StatusEffect] = [],
	base_override: float = -1.0
) -> Projectile:
	var projectile := Projectile.new()
	projectile.name = "AbilityProjectile"
	var builder := func(target: Node2D) -> DamageInfo:
		var info := make_damage(
			player,
			ability,
			tags,
			projectile.direction,
			knockback,
			target,
			crit_bonus,
			base_override
		)
		for s: StatusEffect in statuses:
			info.with_status(s)
		return info
	projectile.setup(player, player.team, dir, builder, speed, lifetime)
	var slots := slots_of(player)
	if slots != null:
		projectile.bounces = int(slots.get_flag(&"projectile_bounces", 0))
	projectile.position = pos
	if parent == null or not parent.is_inside_tree():
		projectile.free()
		return null
	parent.add_child(projectile)
	projectile.hitbox.hit_dealt.connect(report_hit)
	return projectile


## Applies damage directly to an entity's hurtbox (no physics needed) and reports the hit.
static func hit_directly(target: Entity, info: DamageInfo) -> float:
	if target == null or target.hurtbox == null:
		return 0.0
	var dealt := target.hurtbox.receive(info)
	if dealt > 0.0:
		report_hit(target, info)
	return dealt
