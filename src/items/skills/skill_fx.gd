## Small juice helpers for weapon skills: telegraph shapes, particle bursts, squash/stretch,
## and cached dot textures for code-spawned projectiles. All nodes free themselves.
class_name SkillFx
extends RefCounted

const FALLBACK_ACCENT := Color("e0af68")

const CACHE_META := &"skill_fx_dot_cache"


## Theme accent colour (player-side FX may use theme colours); falls back when headless.
static func accent_color() -> Color:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return FALLBACK_ACCENT
	var desktop := loop.root.get_node_or_null(^"Desktop")
	if desktop == null:
		return FALLBACK_ACCENT
	var palette: Variant = desktop.get("palette")
	if palette is ThemePalette:
		return (palette as ThemePalette).get_color(&"accent")
	return FALLBACK_ACCENT


## A filled circle texture (diameter = radius*2+1), cached per (colour, radius).
static func dot_texture(color: Color, radius: int) -> ImageTexture:
	var key := "%s|%d" % [color.to_html(), radius]
	var cache := _dot_cache()
	if cache.has(key):
		return cache[key]
	var size := radius * 2 + 1
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(size):
		for x in range(size):
			if Vector2(x - radius, y - radius).length() <= float(radius) + 0.5:
				image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	cache[key] = texture
	return texture


## Sprite2D child of `node` (player art), if any.
static func sprite_of(node: Node) -> Node2D:
	if node == null:
		return null
	var sprite := node.get_node_or_null(^"Sprite2D") as Node2D
	if sprite == null:
		sprite = node.get_node_or_null(^"AnimatedSprite2D") as Node2D
	return sprite


## Squash/stretch pulse on `node` (no-op when null).
static func squash(node: Node2D, stretch: Vector2, duration: float) -> void:
	if node == null or not node.is_inside_tree():
		return
	var tween := node.create_tween()
	tween.tween_property(node, "scale", stretch, duration * 0.35).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector2.ONE, duration * 0.65).set_ease(Tween.EASE_IN_OUT)


## One-shot CPUParticles2D burst at a world position; frees itself.
static func burst(
	parent: Node, pos: Vector2, color: Color, count: int, speed: float, lifetime: float = 0.35
) -> CPUParticles2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.emitting = true
	particles.amount = maxi(1, count)
	particles.lifetime = lifetime
	particles.explosiveness = 1.0
	particles.direction = Vector2.RIGHT
	particles.spread = 180.0
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.damping_min = speed * 1.5
	particles.damping_max = speed * 2.5
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.0
	particles.color = color
	parent.add_child(particles)
	particles.global_position = pos
	particles.get_tree().create_timer(lifetime + 0.1).timeout.connect(particles.queue_free)
	return particles


## Fading polygon telegraph (points in local space, rotated by `rotation`), frees itself.
static func telegraph(
	parent: Node,
	pos: Vector2,
	points: PackedVector2Array,
	rotation: float,
	color: Color,
	duration: float,
	attach_to: Node2D = null
) -> Polygon2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = Color(color, 0.45)
	poly.rotation = rotation
	poly.z_index = 5
	var host: Node = attach_to if attach_to != null else parent
	host.add_child(poly)
	if attach_to != null:
		poly.position = pos
	else:
		poly.global_position = pos
	poly.scale = Vector2(0.7, 0.7)
	var tween := poly.create_tween()
	tween.set_parallel(true)
	tween.tween_property(poly, "scale", Vector2.ONE, duration * 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(poly, "color:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(poly.queue_free)
	return poly


## Circle outline points (for telegraph()).
static func circle_points(radius: float, segments: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		pts.append(Vector2.from_angle(TAU * float(i) / float(segments)) * radius)
	return pts


## Arc wedge points centred on +X (for telegraph()).
static func arc_points(radius: float, half_angle: float, segments: int = 10) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in range(segments + 1):
		var a := -half_angle + 2.0 * half_angle * float(i) / float(segments)
		pts.append(Vector2.from_angle(a) * radius)
	return pts


## Axis-aligned rectangle points centred at origin (for telegraph()).
static func rect_points(size: Vector2) -> PackedVector2Array:
	var h := size * 0.5
	return PackedVector2Array(
		[Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]
	)


## Sprite that drops from `from` to `to` (arrow rain), then frees itself.
static func drop_sprite(
	parent: Node, texture: Texture2D, from: Vector2, to: Vector2, duration: float
) -> Sprite2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.z_index = 6
	parent.add_child(sprite)
	sprite.global_position = from
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "global_position", to, duration).set_ease(Tween.EASE_IN)
	tween.tween_callback(sprite.queue_free)
	return sprite


static func _dot_cache() -> Dictionary:
	var loop := Engine.get_main_loop()
	if loop == null:
		return {}
	if not loop.has_meta(CACHE_META):
		loop.set_meta(CACHE_META, {})
	return loop.get_meta(CACHE_META)
