## Base for dropped pickups (gold, hearts, stat orbs). Pops out on spawn, then homes to the
## player once inside their `pickup_radius` stat and calls `_collect(player)` on contact.
##
## `_ready` sets collision state and adds a shape, which the physics server refuses while it
## is flushing queries, so a pickup must never be added to the tree from inside a physics
## callback (an enemy dying in a hitbox overlap). `PickupSpawner` defers the insertion for
## exactly that reason; any other caller has to do the same.
##
## A drop exists *only* as this node: no generator knows about it and "the room is cleared"
## does not imply it, so a resume that rebuilds the floor from the seed comes back swept clean
## unless the save carried it. `to_dict()` is how it is carried (docs §12, "quitting is always
## resumable"); `PickupSpawner.from_dict()` is the inverse and `FloorDrops` the glue.
class_name PickupBase
extends Area2D

signal collected(player: Node2D)

const RETINT_TIME := 0.6
const COLLECT_DISTANCE := 5.0
const HOME_ACCEL := 900.0
const HOME_MAX_SPEED := 260.0
const POP_DECAY := 6.0
const DEFAULT_PICKUP_RADIUS := 24.0

## Palette role used for the main colour.
@export var color_role: StringName = &"loot"
@export var radius: float = 3.0
## Seconds after spawn before homing may begin.
@export var settle_time: float = 0.25

## Identifier of this pickup's kind: the `PickupSpawner.spawn` kind that makes one and the
## `kind` field of a saved entry. Each subclass sets it in `_init`.
var kind: StringName = &""
var amount: int = 1
var color: Color = Color(0.95, 0.8, 0.3)
## The ring behind the body, transparent when the ink clears every surface on its own
## (`LootInk`). Recomputed with the colour, never authored.
var halo: Color = Color.TRANSPARENT
var _pop_velocity: Vector2 = Vector2.ZERO
var _home_speed: float = 0.0
var _age: float = 0.0
var _collected: bool = false
var _bob_phase: float = 0.0
var _retint: Tween


func _ready() -> void:
	collision_layer = Layers.PICKUP
	collision_mask = 0
	monitoring = false
	monitorable = true
	z_index = 2
	# Authored colours out of the lighting layer's dark on a dark theme, where that is what lets
	# loot read in an unlit corner; with the surface under it on a light theme, where the
	# exemption is what costs a dark drop its contrast (`LightRig.loot_mask`, docs 10).
	light_mask = LightRig.loot_mask()
	color = _palette_color()
	halo = LootInk.halo_for(color, PickupBase.world_palette_for(self))
	EventBus.palette_changed.connect(_on_palette_changed)
	if get_child_count() == 0:
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = maxf(4.0, radius + 1.0)
		shape.shape = circle
		add_child(shape)
	scale = Vector2(0.2, 0.2)
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)


## Gives the pickup an initial burst direction (spawn scatter).
func pop(direction: Vector2, strength: float = 70.0) -> void:
	_pop_velocity = direction.normalized() * strength


## True once the pickup has been taken: it is playing its fade-out and is no longer on the
## floor, so a save must not record it and a resume must not put it back.
func is_collected() -> bool:
	return _collected


## This drop as a JSON-safe save entry (`RunState.floor_drops`): kind, amount and where it
## lies, plus whatever `save_extra()` adds. Position is read live rather than from the spawn
## request, because a coin that popped or homed part-way to the player has moved since.
func to_dict() -> Dictionary:
	var out := {
		"kind": String(kind),
		"amount": amount,
		"x": global_position.x,
		"y": global_position.y,
	}
	save_extra(out)
	return out


## Subclass hook: adds the fields `kind` and `amount` cannot carry (a stat orb's stat).
func save_extra(_out: Dictionary) -> void:
	pass


## Subclass hook: reads back what `save_extra()` wrote. Anything missing or unrecognized has
## to leave the constructor's default standing, so an entry from an older save still restores
## a usable pickup instead of one with a broken payload.
func load_extra(_data: Dictionary) -> void:
	pass


func _physics_process(delta: float) -> void:
	if _collected:
		return
	_age += delta
	if _pop_velocity.length_squared() > 1.0:
		global_position += _pop_velocity * delta
		_pop_velocity = _pop_velocity.move_toward(Vector2.ZERO, POP_DECAY * delta * 60.0)
	var player := find_player()
	if player == null or _age < settle_time:
		queue_redraw()
		return
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if dist <= COLLECT_DISTANCE:
		_finish_collect(player)
		return
	if _home_speed > 0.0 or dist <= pickup_radius_of(player):
		_home_speed = minf(HOME_MAX_SPEED, _home_speed + HOME_ACCEL * delta)
		global_position += to_player.normalized() * minf(_home_speed * delta, dist)
	queue_redraw()


## Nearest node in group "player".
func find_player() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var n := node as Node2D
		if n == null:
			continue
		var d := n.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


static func pickup_radius_of(player: Node2D) -> float:
	var entity := player as Entity
	if entity != null and entity.stats != null:
		return entity.stats.get_value(&"pickup_radius")
	return DEFAULT_PICKUP_RADIUS


func _finish_collect(player: Node2D) -> void:
	_collected = true
	_collect(player)
	collected.emit(player)
	set_physics_process(false)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "scale", Vector2(1.6, 1.6), 0.12)
	t.tween_property(self, "modulate:a", 0.0, 0.12)
	t.chain().tween_callback(queue_free)


## Override: apply the pickup to the player.
func _collect(_player: Node2D) -> void:
	pass


func _draw() -> void:
	var bob := sin(_age * 6.0 + _bob_phase) * 1.0
	var shadow := Color(0, 0, 0, 0.3)
	draw_circle(Vector2(0.0, radius * 0.6), radius * 0.9, shadow)
	var body := Vector2(0.0, -radius - bob)
	# The halo goes down first and the body covers all but its rim, so what is left is a
	# one-pixel outline in the opposite direction from the ink (`LootInk`).
	if LootInk.has_halo(halo):
		draw_circle(body, radius + LootInk.HALO_WIDTH, halo)
	draw_circle(body, radius, color)
	draw_circle(Vector2(-radius * 0.3, -radius * 1.3 - bob), radius * 0.35, color.lightened(0.5))


## Sets the phase this drop bobs at.
##
## Drawn by `PickupSpawner` from the run's own drop stream, not here from `randf()`. It used to
## be the latter, and it was the only unseeded *global* RNG draw left in `src/`: a drop was a
## slightly different shape on every run, a capture of dropped loot could not be compared pixel
## for pixel, and `pickup_frame` read one kind at 4.31:1 on one run and 2.42:1 on the next
## because a coin frozen a pixel higher put a different share of its rim on the wall speckle.
## A drop made outside the spawner keeps phase 0, which is the phase the colour model is
## written against.
func set_bob_phase(phase: float) -> void:
	_bob_phase = phase
	queue_redraw()


## The palette a drop lying in a room is painted from: the floor's **lit** palette when there is
## a floor above it, and the desktop palette when there is not (a fixture, a menu, a test).
##
## Not `Desktop.palette`, which is the theme as the *desktop* authored it. The room is not drawn
## in that palette: `FloorRoot` exposes the theme into a light band
## (`ThemePalette.light_environment`) before a single tile is painted, and on a dark theme that
## lifts the floor and the wall cap a long way - tokyo-night's cap is authored `565f89` and drawn
## `707bae`. Guarding the ink against the authored surfaces and then drawing it on the exposed
## ones is how a coin measured 2.05:1 against the cap it was supposed to clear at 3.0:1 - on a
## rendered frame, with every unit test green, because no unit test had ever put the two
## palettes in the same sentence. `pickup_frame_capture` is the check that did.
##
## The lit palette runs the same world guard over the surfaces it will actually paint
## (`light_environment` ends in `_apply_contrast_guard`), so reading it is what makes the promise
## and the picture the same statement.
static func world_palette_for(node: Node) -> ThemePalette:
	var parent := node.get_parent()
	while parent != null:
		var root := parent as FloorRoot
		if root != null and root.lit_palette() != null:
			return root.lit_palette()
		parent = parent.get_parent()
	return Desktop.palette


## The colour this drop is painted. It is `ThemePalette.world_color()` and not `get_color()`:
## a pickup is not a piece of HUD sitting on a plate, it is an object lying on the dungeon floor
## that pops, bobs and gets knocked against the wall, so it is guarded against every surface the
## room paints rather than against the three a widget can sit on. On the `white` fixture the plain
## role measured 8.86:1 on the floor and 1.30:1 on the wall, which is the owner's "gold, hearts
## and stat orbs are invisible on the light theme".
func _palette_color() -> Color:
	var palette := PickupBase.world_palette_for(self)
	if palette == null:
		return color
	return palette.world_color(color_role)


## Deferred, not immediate: `FloorRoot` re-exposes its own palette from the same
## `EventBus.palette_changed`, and nothing orders the two handlers. Reading the floor inside the
## signal gets the *previous* theme's lit palette one time in two, and a drop then crossfades to
## a colour guarded against a room that is no longer on screen.
func _on_palette_changed(_palette: ThemePalette) -> void:
	# A swap from a dark theme to a light one moves loot out of the exemption and back again.
	light_mask = LightRig.loot_mask()
	_start_retint.call_deferred()


func _start_retint() -> void:
	if not is_inside_tree():
		return
	if _retint != null:
		_retint.kill()
	_retint = create_tween()
	_retint.tween_method(_set_color, color, _palette_color(), RETINT_TIME)


func _set_color(c: Color) -> void:
	color = c
	# The ring is a function of the ink and the surfaces under it, so it is re-solved with
	# every step of the retint rather than left behind on the previous theme's answer.
	halo = LootInk.halo_for(color, PickupBase.world_palette_for(self))
	queue_redraw()


## Calls `method` on `player` with as many of `args` as its signature accepts.
static func call_player(player: Node2D, method: StringName, args: Array) -> bool:
	if not player.has_method(method):
		return false
	var argc := player.get_method_argument_count(method)
	player.callv(method, args.slice(0, mini(argc, args.size())))
	return true
