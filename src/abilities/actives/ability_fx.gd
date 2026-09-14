## Small, theme-aware juice helpers for abilities: particle bursts, expanding rings, lightning
## bolts, flashes, squash/stretch and hit-stop. Every spawned node is tinted from the live
## `Desktop.palette` role and retints (0.6 s tween) on `EventBus.palette_changed`.
class_name AbilityFx
extends RefCounted

const RETINT_TIME := 0.6
## Virtual resource paths used to share generated textures through the ResourceCache.
const TEXTURE_CACHE_PREFIX := "res://.ability_fx/"
## Meta keys holding a node's resting modulate/scale and the tween currently animating it, so
## overlapping flashes/squashes restore the resting value instead of a mid-animation one.
const META_BASE_MODULATE := &"fx_base_modulate"
const META_BASE_SCALE := &"fx_base_scale"
const META_FLASH_TWEEN := &"fx_flash_tween"
const META_SQUASH_TWEEN := &"fx_squash_tween"


## Current colour for a palette role (magenta fallback when the palette is not ready).
static func color(role: StringName) -> Color:
	if Desktop.palette == null:
		return Color.MAGENTA
	return Desktop.palette.get_color(role)


## Tints `node.modulate` from `role` now and keeps it in sync with theme changes.
static func bind_palette(node: CanvasItem, role: StringName) -> void:
	node.modulate = color(role)
	node.set_meta(META_BASE_MODULATE, node.modulate)
	var retint := func(palette: ThemePalette) -> void:
		if not is_instance_valid(node) or not node.is_inside_tree():
			return
		# The retint is the new resting tint, so a flash in flight cannot bake the old one in.
		node.set_meta(META_BASE_MODULATE, palette.get_color(role))
		_kill_tween(node, META_FLASH_TWEEN)
		var tween := node.create_tween()
		tween.tween_property(node, "modulate", palette.get_color(role), RETINT_TIME)
	EventBus.palette_changed.connect(retint)
	node.tree_exited.connect(
		func() -> void:
			if EventBus.palette_changed.is_connected(retint):
				EventBus.palette_changed.disconnect(retint)
	)


## Cached white circle texture (tint with modulate).
static func circle_texture(radius: int) -> Texture2D:
	var key := TEXTURE_CACHE_PREFIX + "circle_%d" % radius
	var cached := _cached_texture(key)
	if cached != null:
		return cached
	var size := radius * 2 + 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	for y in range(size):
		for x in range(size):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			img.set_pixel(x, y, Color.WHITE if d <= radius else Color(1, 1, 1, 0))
	return _cache_texture(key, ImageTexture.create_from_image(img))


## Cached white bar texture (arrows, bolts), `length` x `thickness` px.
static func bar_texture(length: int, thickness: int) -> Texture2D:
	var key := TEXTURE_CACHE_PREFIX + "bar_%dx%d" % [length, thickness]
	var cached := _cached_texture(key)
	if cached != null:
		return cached
	var img := Image.create(length, thickness, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return _cache_texture(key, ImageTexture.create_from_image(img))


static func _cached_texture(key: String) -> Texture2D:
	if ResourceLoader.has_cached(key):
		return ResourceLoader.load(key) as Texture2D
	return null


static func _cache_texture(key: String, tex: Texture2D) -> Texture2D:
	tex.take_over_path(key)
	return tex


## One-shot radial particle burst that frees itself.
static func burst(
	parent: Node,
	pos: Vector2,
	role: StringName,
	count: int = 16,
	radius: float = 24.0,
	life: float = 0.45
) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Burst"
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(1, count)
	p.lifetime = life
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(1.0, radius * 0.25)
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = radius * 1.2
	p.initial_velocity_max = radius * 2.4
	p.damping_min = radius * 2.0
	p.damping_max = radius * 3.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.texture = circle_texture(1)
	bind_palette(p, role)
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(life + 0.2).timeout.connect(p.queue_free)
	return p


## Continuous trail emitter attached to `node` (e.g. a projectile); frees with its parent.
static func trail(node: Node2D, role: StringName, rate: int = 12) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Trail"
	p.amount = rate
	p.lifetime = 0.35
	p.local_coords = false
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0
	p.spread = 180.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.texture = circle_texture(1)
	bind_palette(p, role)
	node.add_child(p)
	p.emitting = true
	return p


## Expanding, fading ring (telegraph/impact). Frees itself after `duration`.
static func ring(
	parent: Node, pos: Vector2, radius: float, role: StringName, duration: float = 0.35
) -> AbilityRing:
	var r := AbilityRing.new()
	r.radius = radius
	r.duration = duration
	bind_palette(r, role)
	parent.add_child(r)
	r.global_position = pos
	return r


## Jagged lightning line through `points`, fading out over `duration`.
static func bolt(
	parent: Node, points: PackedVector2Array, role: StringName, duration: float = 0.25
) -> Line2D:
	var line := Line2D.new()
	line.name = "Bolt"
	line.width = 2.0
	line.default_color = Color.WHITE
	line.top_level = true
	var jagged := PackedVector2Array()
	for i in range(points.size()):
		jagged.append(points[i])
		if i + 1 < points.size():
			var mid := points[i].lerp(points[i + 1], 0.5)
			var normal := (points[i + 1] - points[i]).orthogonal().normalized()
			jagged.append(mid + normal * (4.0 if i % 2 == 0 else -4.0))
	line.points = jagged
	bind_palette(line, role)
	parent.add_child(line)
	line.global_position = Vector2.ZERO
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, duration)
	tween.tween_callback(line.queue_free)
	return line


## Brief modulate flash toward a palette colour, restoring the node's resting tint. Repeated
## flashes on the same node never bake a mid-flash colour in.
static func flash(node: CanvasItem, role: StringName, duration: float = 0.15) -> void:
	if node == null or not node.is_inside_tree():
		return
	var back: Color = node.modulate
	if node.has_meta(META_BASE_MODULATE):
		back = node.get_meta(META_BASE_MODULATE)
	else:
		node.set_meta(META_BASE_MODULATE, back)
	_kill_tween(node, META_FLASH_TWEEN)
	node.modulate = color(role).lightened(0.3)
	var tween := node.create_tween()
	node.set_meta(META_FLASH_TWEEN, tween)
	tween.tween_property(node, "modulate", back, duration)


## Squash/stretch pulse on a Node2D's scale, restoring its resting scale.
static func squash(node: Node2D, amount: float = 0.25, duration: float = 0.18) -> void:
	if node == null or not node.is_inside_tree():
		return
	var base: Vector2 = node.scale
	if node.has_meta(META_BASE_SCALE):
		base = node.get_meta(META_BASE_SCALE)
	else:
		node.set_meta(META_BASE_SCALE, base)
	_kill_tween(node, META_SQUASH_TWEEN)
	node.scale = base * Vector2(1.0 + amount, 1.0 - amount)
	var tween := node.create_tween()
	node.set_meta(META_SQUASH_TWEEN, tween)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", base, duration)


## Records the value `flash`/`squash` must return to (call after a deliberate, permanent
## change such as a spawn-in scale tween).
static func set_resting(node: CanvasItem) -> void:
	if node == null:
		return
	node.set_meta(META_BASE_MODULATE, node.modulate)
	if node is Node2D:
		node.set_meta(META_BASE_SCALE, (node as Node2D).scale)


static func _kill_tween(node: Object, key: StringName) -> void:
	if not node.has_meta(key):
		return
	var tween := node.get_meta(key) as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	node.remove_meta(key)


## Freezes the game for a few frames. Delegates to the shared `HitStop` helper so ability and
## weapon stops share one generation-safe restore timer and the accessibility toggle.
static func hit_stop(tree: SceneTree, seconds: float = HitStop.DEFAULT_DURATION) -> void:
	HitStop.apply(tree, seconds)
