## Projectiles against solid geometry: the wall half of "dies on wall/lifetime/pierce".
##
## There was no projectile suite at all, and the wall path had never worked: the shot's own
## Area2D carries no collision shape (its `Hitbox` child holds the only one), so the physics
## server never reported the TileMapLayer walls to it, `body_entered` never fired, and every
## shot in the game flew through solid geometry until `lifetime` ran out. The `ricochet`
## passive - "player projectiles bounce off walls" - therefore bounced off nothing, and the
## tests that shipped with it only ever asserted `Projectile.bounces == 1`, which is the
## setting, not the behaviour.
##
## So these cases fire into a *real* wall - a FloorData room put through `FloorBuilder`, the
## same TileMapLayer with the same WORLD collision polygons the game builds - and measure
## where the shot ends up. They are also the guard on the other half: a shot must still cross
## open floor without stopping and must still damage what it overlaps on the way.
class_name ProjectileWallTest
extends GdUnitTestSuite

const ATLAS := "res://assets/tiles/crypt.png"
## Room interior in tiles: x,y in [2,9], so the wall ring is x,y in {1,10}.
const ROOM_RECT := Rect2i(2, 2, 8, 8)
## World y of the inside face of the bottom wall (tile row 10) and of the top wall (row 1).
const WALL_BOTTOM_Y := 160.0
const WALL_TOP_Y := 32.0
## World x of the inside face of the right wall (tile column 10).
const WALL_RIGHT_X := 160.0
## Spawn point: the centre of tile (6, 3), 104 px above the bottom wall.
const SPAWN := Vector2(104.0, 56.0)
## Long enough for every flight here to end on geometry rather than on the clock.
const LONG_LIFE := 4.0
## Hard cap on the frames a case waits for a shot to finish; ~1.3 s at 60 Hz.
const MAX_FRAMES := 80

var _root: Node2D
var _death_pos: Vector2 = Vector2.ZERO
var _deaths: int = 0


func before_test() -> void:
	_root = auto_free(Node2D.new()) as Node2D
	add_child(_root)
	var atlas := FloorBuilder.load_atlas(ATLAS)
	FloorBuilder.new().build(_walled_room(), atlas, _root, ThemePalette.fallback())
	_death_pos = Vector2.ZERO
	_deaths = 0
	await get_tree().physics_frame


## One closed room: floor over `ROOM_RECT`, a one-tile WALL ring around it, nothing else. No
## doors, so every direction out of the middle meets a wall.
func _walled_room() -> FloorData:
	var data := FloorData.new()
	data.seed_value = 20250912
	data.floor_index = 0
	data.biome = &"crypt"
	data.width = 12
	data.height = 12
	data.tiles.resize(data.width * data.height)
	data.tiles.fill(FloorData.Tile.VOID)
	var room := FloorData.Room.new()
	room.id = 0
	room.type = FloorData.RoomType.COMBAT
	room.rect = ROOM_RECT
	for y in range(ROOM_RECT.position.y, ROOM_RECT.end.y):
		for x in range(ROOM_RECT.position.x, ROOM_RECT.end.x):
			data.set_tile(x, y, FloorData.Tile.FLOOR)
	var ring := ROOM_RECT.grow(1)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if data.get_tile(x, y) == FloorData.Tile.VOID:
				data.set_tile(x, y, FloorData.Tile.WALL)
	data.rooms.append(room)
	data.start_room = 0
	data.stairs_room = 0
	data.boss_room = -1
	return data


## A shot in the room, already in the tree, with its death position recorded on `expired`.
func _fire(dir: Vector2, spd: float, bounces: int, from: Vector2 = SPAWN) -> Projectile:
	var shot := Projectile.new()
	shot.bounces = bounces
	shot.trail_enabled = false
	shot.impact_puff = false
	shot.setup(null, Layers.Team.PLAYER, dir, Callable(), spd, LONG_LIFE)
	shot.expired.connect(
		func(p: Projectile) -> void:
			_death_pos = p.global_position
			_deaths += 1
	)
	_root.add_child(shot)
	shot.global_position = from
	return shot


## Steps physics until `shot` is gone (or `MAX_FRAMES`). Returns the frames it survived.
func _fly_until_gone(shot: Projectile) -> int:
	for i in range(MAX_FRAMES):
		await get_tree().physics_frame
		if not is_instance_valid(shot) or shot.is_queued_for_deletion():
			return i
	return MAX_FRAMES


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


func test_a_shot_dies_at_the_wall_instead_of_flying_through_it() -> void:
	var shot := _fire(Vector2.DOWN, 200.0, 0)
	var frames := await _fly_until_gone(shot)
	assert_int(_deaths).is_equal(1)
	assert_int(frames).is_less(MAX_FRAMES)
	# It ended on the near face of the wall, not inside it and not past it.
	assert_float(_death_pos.y).is_less(WALL_BOTTOM_Y)
	assert_float(_death_pos.y).is_greater(WALL_BOTTOM_Y - 16.0)
	# ... and it died on the wall, not on the clock: 104 px at 200 px/s is ~0.52 s.
	assert_int(frames).is_less(int(LONG_LIFE * 60.0))


func test_a_fast_shot_cannot_step_over_a_wall_between_frames() -> void:
	# 2000 px/s is 33 px per physics step - twice the 16 px the wall is thick. An overlap test
	# only samples the end of the step, so this is the case a shape on the area would miss.
	var shot := _fire(Vector2.DOWN, 2000.0, 0)
	var frames := await _fly_until_gone(shot)
	assert_int(_deaths).is_equal(1)
	assert_int(frames).is_less(10)
	assert_float(_death_pos.y).is_less(WALL_BOTTOM_Y)


func test_a_shot_with_a_bounce_reflects_off_the_wall_and_keeps_going() -> void:
	var shot := _fire(Vector2.DOWN, 200.0, 1)
	# 104 px down at 200 px/s is 31 frames; 40 is past the wall with room to spare.
	await _frames(40)
	assert_bool(is_instance_valid(shot)).is_true()
	assert_int(_deaths).is_equal(0)
	# It turned around instead of dying, and it is back inside the room.
	assert_float(shot.direction.y).is_less(0.0)
	assert_float(shot.global_position.y).is_less(WALL_BOTTOM_Y)
	assert_float(shot.global_position.y).is_greater(WALL_TOP_Y)
	# The bounce was spent: the far wall kills it.
	var frames := await _fly_until_gone(shot)
	assert_int(frames).is_less(MAX_FRAMES)
	assert_int(_deaths).is_equal(1)
	assert_float(_death_pos.y).is_greater(WALL_TOP_Y)


func test_a_bounce_off_a_side_wall_mirrors_only_that_axis() -> void:
	var shot := _fire(Vector2.RIGHT, 200.0, 1, Vector2(56.0, 88.0))
	await _frames(40)
	assert_bool(is_instance_valid(shot)).is_true()
	assert_float(shot.direction.x).is_less(0.0)
	assert_float(absf(shot.direction.y)).is_less(0.01)
	assert_float(shot.global_position.x).is_less(WALL_RIGHT_X)


func test_open_floor_does_not_stop_a_shot() -> void:
	# The property the wall fix must not break: over floor tiles the shot keeps its full step.
	var shot := _fire(Vector2.RIGHT, 200.0, 0, Vector2(40.0, 88.0))
	await _frames(12)
	assert_bool(is_instance_valid(shot)).is_true()
	assert_float(shot.global_position.x).is_equal_approx(40.0 + 200.0 * 12.0 / 60.0, 1.0)
	assert_float(shot.global_position.y).is_equal_approx(88.0, 0.01)


func test_a_shot_still_damages_what_it_overlaps_before_it_reaches_the_wall() -> void:
	var target := auto_free(Entity.new()) as Entity
	target.team = Layers.Team.ENEMY
	_root.add_child(target)
	target.global_position = Vector2(104.0, 88.0)
	await get_tree().physics_frame
	var before := target.health.hp
	var shot := _fire(Vector2.RIGHT, 200.0, 0, Vector2(48.0, 88.0))
	shot.hitbox.damage = 7.0
	var frames := await _fly_until_gone(shot)
	assert_int(frames).is_less(MAX_FRAMES)
	assert_float(target.health.hp).is_less(before)
	# It died on the target, well short of the right wall.
	assert_float(_death_pos.x).is_less(WALL_RIGHT_X - 32.0)


func test_a_pooled_shot_killed_by_a_wall_goes_back_to_the_pool() -> void:
	Projectile.clear_pool()
	var shot := Projectile.acquire()
	shot.bounces = 0
	shot.trail_enabled = false
	shot.impact_puff = false
	shot.setup(null, Layers.Team.PLAYER, Vector2.DOWN, Callable(), 400.0, LONG_LIFE)
	_root.add_child(shot)
	shot.global_position = SPAWN
	await _frames(20)
	assert_bool(is_instance_valid(shot)).is_true()
	assert_object(shot.get_parent()).is_null()
	assert_int(Projectile.pool().size()).is_greater(0)
	Projectile.clear_pool()
