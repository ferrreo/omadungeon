## Laser grid (docs §9, Void only): a beam between this node and `end_offset` that is on for 1 s
## and off for 1.5 s (0.35 s flicker tell + 1.15 s dark). High damage, one hit per pulse.
class_name LaserGrid
extends TrapBase

const BEAM_WIDTH := 3.0
const HIT_WIDTH := 5.0

## Far anchor, relative to this node.
@export var end_offset: Vector2 = Vector2(48.0, 0.0)

var beam: Line2D
var end_sprite: Sprite2D


func _init() -> void:
	kind = &"laser_grid"
	auto_cycle = true
	damage = 30.0
	knockback = 60.0
	telegraph_time = 0.35
	active_time = 1.0
	cooldown_time = 1.15
	tags = [DamageInfo.TAG_TRAP, DamageInfo.TAG_ARCANE]


func configure(extra: Dictionary) -> void:
	super.configure(extra)
	if extra.has("to"):
		var to: Vector2 = extra["to"]
		end_offset = to - position
	elif extra.has("direction") and extra.has("length"):
		var d: Vector2 = extra["direction"]
		end_offset = d.normalized() * float(extra["length"])


func _on_setup() -> void:
	# Hitbox: thin rectangle along the beam.
	var length := end_offset.length()
	var shape := hitbox.get_node_or_null("Shape") as CollisionShape2D
	if shape == null:
		shape = _first_shape(hitbox)
	if shape == null:
		shape = CollisionShape2D.new()
		shape.name = "Shape"
		hitbox.add_child(shape)
	if not (shape.shape is RectangleShape2D):
		shape.shape = RectangleShape2D.new()
	var rect := shape.shape as RectangleShape2D
	rect.size = Vector2(maxf(length - 4.0, 1.0), HIT_WIDTH)
	hitbox.position = end_offset * 0.5
	hitbox.rotation = end_offset.angle()
	beam = Line2D.new()
	beam.name = "Beam"
	beam.width = BEAM_WIDTH
	beam.points = PackedVector2Array([Vector2.ZERO, end_offset])
	beam.default_color = _danger
	beam.visible = false
	add_child(beam)
	end_sprite = Sprite2D.new()
	end_sprite.name = "EndAnchor"
	end_sprite.texture = sprite.texture
	end_sprite.hframes = sprite.hframes
	end_sprite.position = end_offset
	end_sprite.flip_h = true
	add_child(end_sprite)
	tell.polygon = PackedVector2Array([Vector2.ZERO, end_offset])
	tell.visible = false


func _on_telegraph() -> void:
	beam.visible = true
	beam.width = 1.0


func _on_telegraph_process(_delta: float) -> void:
	# Rhythmic flicker: readable "charging" tell.
	var on := int(state_time * 16.0) % 2 == 0
	var c := _danger
	c.a = 0.55 if on else 0.15
	beam.default_color = c


func _on_trigger() -> void:
	beam.visible = true
	beam.width = BEAM_WIDTH
	var c := _danger
	c.a = 1.0
	beam.default_color = c
	if end_sprite != null:
		end_sprite.frame = FRAME_ACTIVE
	if is_inside_tree():
		var tween := create_tween()
		tween.tween_property(beam, "width", BEAM_WIDTH * 2.2, 0.05)
		tween.tween_property(beam, "width", BEAM_WIDTH, 0.12)


func _on_active_process(_delta: float) -> void:
	var c := _danger
	c.a = 0.85 + 0.15 * sin(state_time * TAU * 12.0)
	beam.default_color = c


func _on_cooldown() -> void:
	beam.visible = false
	if end_sprite != null:
		end_sprite.frame = FRAME_IDLE


func _on_idle() -> void:
	if beam != null:
		beam.visible = false


func _set_danger(c: Color) -> void:
	super._set_danger(c)
	if beam != null and state == State.ACTIVE:
		beam.default_color = c


## First CollisionShape2D child of `node` (scene-authored hitboxes may name it anything).
static func _first_shape(node: Node) -> CollisionShape2D:
	for child: Node in node.get_children():
		var shape := child as CollisionShape2D
		if shape != null:
			return shape
	return null
