## Oligarch "Delegation" decoy: a 1 hp player-team target that taunts nearby enemies for its
## short lifetime, then pops. Spawned by `Player` at the start of a DELEGATE dodge.
class_name Decoy
extends Node2D

signal expired

const LIFETIME := 2.0
const TAUNT_RADIUS := 64.0
const TAUNT_DURATION := 2.0
## Enemies that walk into range later must be taunted too, so the scan repeats.
const SCAN_INTERVAL := 0.25

var health: Health
var hurtbox: Hurtbox
var sprite: Sprite2D
var taunted: Array[Node2D] = []
var _time_left: float = LIFETIME
var _scan_timer: float = 0.0
var _popping: bool = false


## Optional look: a frame from the player's sheet, mirrored like the player.
func setup(texture: Texture2D, flip_h: bool = false) -> void:
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		add_child(sprite)
	sprite.texture = texture
	sprite.flip_h = flip_h


func _ready() -> void:
	add_to_group(&"decoys")
	health = Health.new()
	health.name = "Health"
	health.max_hp = 1.0
	add_child(health)
	hurtbox = Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.team = Layers.Team.PLAYER
	hurtbox.health_override = health
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 12)
	shape.shape = rect
	hurtbox.add_child(shape)
	add_child(hurtbox)
	health.died.connect(_on_died)
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		add_child(sprite)
	sprite.modulate = Desktop.palette.get_color(&"accent")
	sprite.modulate.a = 0.75
	EventBus.palette_changed.connect(_on_palette_changed)
	scale = Vector2(0.6, 1.3)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)


func _physics_process(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		taunt_nearby()
	_time_left -= delta
	if _time_left <= 0.0 and not _popping:
		_pop()


## Applies TAUNT (source = this decoy) to every enemy hurtbox within TAUNT_RADIUS. Called on an
## interval, so re-applying simply refreshes the effect's duration. Returns this scan's hits.
func taunt_nearby() -> Array[Node2D]:
	taunted.clear()
	var space := get_world_2d().direct_space_state
	if space == null:
		return taunted
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = TAUNT_RADIUS
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = Layers.ENEMY_HURTBOX
	for hit: Dictionary in space.intersect_shape(query, 32):
		var hb := hit["collider"] as Hurtbox
		if hb == null or hb.entity == null or hb.entity.status == null:
			continue
		if taunted.has(hb.entity):
			continue
		hb.entity.status.apply(
			StatusEffect.make(StatusEffect.Kind.TAUNT, TAUNT_DURATION, 0.0, self)
		)
		taunted.append(hb.entity)
	return taunted


func time_left() -> float:
	return _time_left


func _on_palette_changed(palette: ThemePalette) -> void:
	if sprite == null:
		return
	var target := palette.get_color(&"accent")
	target.a = sprite.modulate.a
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", target, 0.6)


func _on_died(_killer: Node2D) -> void:
	_pop()


func _pop() -> void:
	if _popping:
		return
	_popping = true
	hurtbox.set_deferred("monitorable", false)
	expired.emit()
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.4, 0.2), 0.12).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
