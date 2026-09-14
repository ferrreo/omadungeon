## Arrow wall (docs §9): the slot glows for 0.4 s, then fires a Projectile along `direction`.
## Cycles every telegraph + active + cooldown (2.5 s) while the player is in the room.
class_name ArrowWall
extends TrapBase

signal arrow_fired(projectile: Projectile)

const ARROW_SPRITE := "res://assets/sprites/traps/arrow.png"
const GROUP_ENEMY_PROJECTILE := &"enemy_projectile"

@export var direction: Vector2 = Vector2.RIGHT
@export var projectile_speed: float = 220.0
@export var projectile_lifetime: float = 2.5
## Where spawned projectiles are parented; defaults to the trap's parent.
@export var projectile_parent_path: NodePath

var projectiles_fired: int = 0


func _init() -> void:
	kind = &"arrow_wall"
	auto_cycle = true
	damage = 12.0
	knockback = 80.0
	telegraph_time = 0.4
	active_time = 0.1
	cooldown_time = 2.0
	tags = [DamageInfo.TAG_TRAP, DamageInfo.TAG_RANGED, DamageInfo.TAG_PHYSICAL]


func configure(extra: Dictionary) -> void:
	super.configure(extra)
	if extra.has("direction"):
		var d: Vector2 = extra["direction"]
		if d.length_squared() > 0.0:
			direction = d.normalized()


## The arrow carries its own hitbox; the wall itself is harmless.
func _uses_hitbox() -> bool:
	return false


func _on_setup() -> void:
	rotation = direction.angle()
	tell.polygon = PackedVector2Array(
		[Vector2(2, -4), Vector2(8, -2), Vector2(8, 2), Vector2(2, 4)]
	)


func _on_trigger() -> void:
	fire()


## Spawns one arrow. Returns the projectile (already in the tree) or null when not in a tree.
func fire() -> Projectile:
	if not is_inside_tree():
		return null
	var parent: Node = get_parent()
	if not projectile_parent_path.is_empty():
		var custom := get_node_or_null(projectile_parent_path)
		if custom != null:
			parent = custom
	if parent == null:
		parent = self
	var arrow := Projectile.new()
	arrow.name = "Arrow"
	arrow.sprite_texture = _load_arrow_texture()
	arrow.setup(
		self,
		Layers.Team.NEUTRAL,
		direction,
		_build_arrow_damage,
		projectile_speed,
		projectile_lifetime
	)
	arrow.add_to_group(GROUP_ENEMY_PROJECTILE)
	# Parent first: `global_position` on a detached node is just `position`, which the parent
	# transform would then apply a second time.
	parent.add_child(arrow)
	arrow.global_position = global_position + direction * 8.0
	# Traps hurt both teams: widen the mask the projectile derived from its team.
	arrow.hitbox.collision_mask = Layers.PLAYER_HURTBOX | Layers.ENEMY_HURTBOX
	arrow.hitbox.source = self
	projectiles_fired += 1
	arrow_fired.emit(arrow)
	return arrow


func _build_arrow_damage(target: Node2D) -> DamageInfo:
	var info := _build_damage(target)
	if info.amount > 0.0:
		info.with_knockback(direction, knockback)
	return info


static func _load_arrow_texture() -> Texture2D:
	if ResourceLoader.exists(ARROW_SPRITE):
		return load(ARROW_SPRITE) as Texture2D
	var image := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.9, 0.85, 0.7, 1.0))
	return ImageTexture.create_from_image(image)
