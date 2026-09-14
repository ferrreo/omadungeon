## Draws whole floors to PNG so a layout can be judged at a glance (docs 5.1, the owner's
## "no real map or room variety" report). One sheet per fixture under tests/out/gen/: a row
## per `FloorArchetype`, a column per sampled floor, every room tinted by type, doors, spawns
## and props marked. Every drawn floor also has to pass the validator, so the sheet can never
## show a floor the game would refuse.
class_name FloorAtlasTest
extends GdUnitTestSuite

const OUT_DIR := "res://tests/out/gen"
const THEMES: Array[String] = ["tokyo-night", "white"]
const FLOORS: Array[int] = [0, 2, 4, 6]
const SEED := 20250913
const SCALE := 4
## Tiles one cell shows; a floor past it is clipped (the grid allows 160x120, floors run
## about 70x60), and a floor under it is centred.
const CELL_TILES := Vector2i(104, 84)
const CELL := Vector2i(CELL_TILES.x * SCALE, CELL_TILES.y * SCALE)
const GUTTER := 6

const COLOR_VOID := Color(0.08, 0.08, 0.1)
const COLOR_WALL := Color(0.42, 0.4, 0.46)
const COLOR_CORRIDOR := Color(0.55, 0.5, 0.42)
const COLOR_DOOR := Color(0.95, 0.85, 0.3)
const COLOR_PIT := Color(0.1, 0.15, 0.35)
const COLOR_PROP := Color(0.3, 0.75, 0.35)
const COLOR_SPAWN := Color(0.9, 0.25, 0.25)
const COLOR_BOSS := Color(1.0, 0.3, 0.9)
const COLOR_TRAP := Color(0.95, 0.55, 0.2)
const ROOM_COLORS := {
	FloorData.RoomType.START: Color(0.45, 0.7, 0.95),
	FloorData.RoomType.COMBAT: Color(0.66, 0.64, 0.6),
	FloorData.RoomType.ELITE: Color(0.75, 0.45, 0.45),
	FloorData.RoomType.TRAP: Color(0.75, 0.6, 0.35),
	FloorData.RoomType.TREASURE: Color(0.85, 0.78, 0.35),
	FloorData.RoomType.ALTAR: Color(0.6, 0.5, 0.85),
	FloorData.RoomType.SHOP: Color(0.4, 0.75, 0.7),
	FloorData.RoomType.SHRINE: Color(0.55, 0.8, 0.55),
	FloorData.RoomType.STAIRS: Color(0.9, 0.9, 0.95),
	FloorData.RoomType.BOSS: Color(0.9, 0.35, 0.55),
}


static func generate(
	theme: String, floor_index: int, arch: StringName, seed_value: int
) -> FloorData:
	var params := GenParams.from_profile(GenParamsTest.profile_for(theme), floor_index)
	params.archetype = arch
	var rng := RunRng.new(seed_value).floor_stream(&"gen", floor_index)
	return FloorGenerator.generate(params, rng)


## Paints `data` into `img` at `origin` (top-left), SCALE px per tile.
static func paint(img: Image, data: FloorData, origin: Vector2i) -> void:
	var owner: Dictionary = {}
	for room: FloorData.Room in data.rooms:
		for p: Vector2i in GenUtil.rect_tiles(room.rect):
			owner[p] = room
	for y in range(data.height):
		for x in range(data.width):
			var p := Vector2i(x, y)
			var c := COLOR_VOID
			match data.get_tile(x, y):
				FloorData.Tile.FLOOR:
					var room: FloorData.Room = owner.get(p)
					c = ROOM_COLORS[room.type] if room != null else COLOR_CORRIDOR
				FloorData.Tile.WALL:
					c = COLOR_WALL
				FloorData.Tile.DOOR:
					c = COLOR_DOOR
				FloorData.Tile.CORRIDOR:
					c = COLOR_CORRIDOR
				FloorData.Tile.PIT:
					c = COLOR_PIT
			_dot(img, origin, p, c, SCALE)
	for room: FloorData.Room in data.rooms:
		for p: Vector2i in room.prop_positions:
			_dot(img, origin, p, COLOR_PROP, SCALE - 1)
		for trap: Dictionary in room.trap_positions:
			_dot(img, origin, trap["pos"], COLOR_TRAP, SCALE - 1)
		for i in range(room.enemy_spawns.size()):
			var boss := room.type == FloorData.RoomType.BOSS and i == 0
			_dot(img, origin, room.enemy_spawns[i], COLOR_BOSS if boss else COLOR_SPAWN, SCALE)


static func _dot(img: Image, origin: Vector2i, tile: Vector2i, c: Color, size: int) -> void:
	var base := origin + tile * SCALE
	for dy in range(size):
		for dx in range(size):
			var px := base + Vector2i(dx, dy)
			if px.x >= 0 and px.y >= 0 and px.x < img.get_width() and px.y < img.get_height():
				img.set_pixelv(px, c)


func test_every_archetype_draws_a_valid_floor_per_fixture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var failures: Array[String] = []
	for theme: String in THEMES:
		var cols := FLOORS.size()
		var rows := FloorArchetype.ALL.size()
		var img := Image.create(
			cols * (CELL.x + GUTTER), rows * (CELL.y + GUTTER), false, Image.FORMAT_RGB8
		)
		img.fill(Color(0.2, 0.2, 0.22))
		for r in range(rows):
			var arch: StringName = FloorArchetype.ALL[r]
			for c in range(cols):
				var floor_index: int = FLOORS[c]
				var data := generate(theme, floor_index, arch, SEED + c * 101 + r * 7)
				var origin := Vector2i(c * (CELL.x + GUTTER), r * (CELL.y + GUTTER))
				var cell := Image.create(CELL.x, CELL.y, false, Image.FORMAT_RGB8)
				cell.fill(COLOR_VOID)
				var centred := (CELL_TILES - Vector2i(data.width, data.height)) / 2
				paint(cell, data, centred.max(Vector2i.ZERO) * SCALE)
				img.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL), origin)
				if data.archetype != arch:
					failures.append(
						"%s f%d asked for %s, got %s" % [theme, floor_index, arch, data.archetype]
					)
				for v: String in FloorValidator.validate(data):
					failures.append("%s f%d %s: %s" % [theme, floor_index, arch, v])
		var path := ProjectSettings.globalize_path("%s/floor_atlas_%s.png" % [OUT_DIR, theme])
		assert_int(img.save_png(path)).is_equal(OK)
		print("floor atlas: %s" % path)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()
