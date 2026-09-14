## Verifies the generated pixel-art assets exist with the documented layouts, and that
## every environment tile/prop uses only the 8-colour authoring ramp.
class_name ArtAssetsTest
extends GdUnitTestSuite

const BIOMES: PackedStringArray = ["crypt", "forge", "frost", "library", "void"]
const CLASSES: PackedStringArray = ["fighter", "ranger", "wizard", "oligarch"]
const ENEMIES_16: PackedStringArray = [
	"juggler",
	"honker",
	"balloon_clown",
	"mime",
	"manpage_hurler",
	"beard_warden",
	"rant_priest",
	"vim_zealot",
	"kernel_panic",
	"ricer",
	"distro_hopper",
	"config_gremlin",
]
const ENEMIES_32: PackedStringArray = ["clown_car", "dotfile_golem"]
const TRAP_FRAMES: Dictionary = {
	"spike_floor": 4,
	"arrow_wall": 3,
	"fire_vent": 4,
	"pressure_plate": 2,
	"ice_slide": 1,
	"laser_grid": 3,
	"ricer_trap": 3,
	"kernel_spike": 3,
	"pit": 3,
	"mimic_chest": 3,
}
const RAMP: Array[Color] = [
	Color("#101010"),
	Color("#303030"),
	Color("#505050"),
	Color("#707070"),
	Color("#909090"),
	Color("#b00000"),
	Color("#0000b0"),
]


func _load(path: String) -> Image:
	(
		assert_bool(FileAccess.file_exists(path))
		. override_failure_message("missing %s" % path)
		. is_true()
	)
	var img := Image.new()
	var err := img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	assert_int(err).override_failure_message("unreadable %s" % path).is_equal(OK)
	return img


func _assert_size(path: String, w: int, h: int) -> void:
	var img := _load(path)
	if img == null:
		return
	assert_int(img.get_width()).override_failure_message("%s width" % path).is_equal(w)
	assert_int(img.get_height()).override_failure_message("%s height" % path).is_equal(h)


func _is_ramp(c: Color) -> bool:
	if c.a == 0.0:
		return true
	for r: Color in RAMP:
		if c.is_equal_approx(r):
			return true
	return false


func _assert_ramp_only(path: String) -> void:
	var img := _load(path)
	if img == null:
		return
	var bad := 0
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			if not _is_ramp(img.get_pixel(x, y)):
				bad += 1
	assert_int(bad).override_failure_message("%s has %d non-ramp pixels" % [path, bad]).is_equal(0)


func _cell_has_pixels(img: Image, col: int, row: int, cell: int) -> bool:
	for y: int in range(row * cell, (row + 1) * cell):
		for x: int in range(col * cell, (col + 1) * cell):
			if img.get_pixel(x, y).a > 0.0:
				return true
	return false


func test_tilesets_layout_and_ramp() -> void:
	for biome: String in BIOMES:
		var path := "res://assets/tiles/%s.png" % biome
		_assert_size(path, 256, 80)
		_assert_ramp_only(path)
		var img := _load(path)
		for col: int in range(16):
			(
				assert_bool(_cell_has_pixels(img, col, 1, 16))
				. override_failure_message("%s wall mask %d empty" % [biome, col])
				. is_true()
			)
			(
				assert_bool(_cell_has_pixels(img, col, 3, 16))
				. override_failure_message("%s pit mask %d empty" % [biome, col])
				. is_true()
			)
		for col: int in range(9):
			assert_bool(_cell_has_pixels(img, col, 4, 16)).is_true()


func test_biome_props_ramp_only() -> void:
	for biome: String in BIOMES:
		var path := "res://assets/sprites/props/%s.png" % biome
		# Row 0 is the prop, row 1 (`Prop.DEBRIS_ROW`) its broken frame.
		_assert_size(path, Prop.KIND_COUNT * 16, 32)
		_assert_ramp_only(path)
		var img := _load(path)
		for col: int in range(Prop.KIND_COUNT):
			assert_bool(_cell_has_pixels(img, col, 0, 16)).is_true()


func test_player_sheets_and_portraits() -> void:
	for cls: String in CLASSES:
		_assert_size("res://assets/sprites/player/%s.png" % cls, 96, 80)
		_assert_size("res://assets/sprites/player/%s_portrait.png" % cls, 32, 32)
		var img := _load("res://assets/sprites/player/%s.png" % cls)
		var counts: Array[int] = [4, 6, 4, 2, 6]
		for row: int in range(5):
			for col: int in range(counts[row]):
				(
					assert_bool(_cell_has_pixels(img, col, row, 16))
					. override_failure_message("%s row %d col %d empty" % [cls, row, col])
					. is_true()
				)


func test_enemy_sheets() -> void:
	var counts: Array[int] = [4, 4, 2, 3, 1, 4]
	for id: String in ENEMIES_16:
		var path := "res://assets/sprites/enemies/%s.png" % id
		_assert_size(path, 64, 96)
		var img := _load(path)
		for row: int in range(6):
			for col: int in range(counts[row]):
				(
					assert_bool(_cell_has_pixels(img, col, row, 16))
					. override_failure_message("%s row %d col %d empty" % [id, row, col])
					. is_true()
				)
	for id: String in ENEMIES_32:
		_assert_size("res://assets/sprites/enemies/%s.png" % id, 128, 192)


func test_props_pickups_projectiles_fx() -> void:
	_assert_size("res://assets/sprites/props/chest.png", 64, 16)
	_assert_size("res://assets/sprites/pickups.png", 256, 16)
	_assert_size("res://assets/sprites/projectiles.png", 256, 16)
	_assert_size("res://assets/sprites/fx/particles.png", 64, 16)
	var proj := _load("res://assets/sprites/projectiles.png")
	for col: int in range(16):
		assert_bool(_cell_has_pixels(proj, col, 0, 16)).is_true()
	var pick := _load("res://assets/sprites/pickups.png")
	for col: int in range(11):
		assert_bool(_cell_has_pixels(pick, col, 0, 16)).is_true()


func test_traps() -> void:
	for kind: String in TRAP_FRAMES.keys():
		var frames: int = TRAP_FRAMES[kind]
		var path := "res://assets/sprites/traps/%s.png" % kind
		_assert_size(path, frames * 16, 16)
		var img := _load(path)
		for col: int in range(frames):
			(
				assert_bool(_cell_has_pixels(img, col, 0, 16))
				. override_failure_message("%s frame %d empty" % [kind, col])
				. is_true()
			)
	_assert_size("res://assets/sprites/traps/arrow.png", 8, 4)


func test_chest_frames_differ() -> void:
	var img := _load("res://assets/sprites/props/chest.png")
	for col: int in range(4):
		(
			assert_bool(_cell_has_pixels(img, col, 0, 16))
			. override_failure_message("chest frame %d empty" % col)
			. is_true()
		)
	assert_bool(_cells_equal(img, 0, 1)).override_failure_message("closed == open").is_false()
	assert_bool(_cells_equal(img, 0, 3)).override_failure_message("closed == wobble").is_false()


func test_animation_rows_are_not_static() -> void:
	# Death and windup frames must actually differ, otherwise the sheet reads as a freeze.
	for id: String in ENEMIES_16:
		var img := _load("res://assets/sprites/enemies/%s.png" % id)
		(
			assert_bool(_cells_equal_at(img, 0, 5, 3, 5))
			. override_failure_message("%s death frames identical" % id)
			. is_false()
		)
		(
			assert_bool(_cells_equal_at(img, 0, 2, 1, 2))
			. override_failure_message("%s windup frames identical" % id)
			. is_false()
		)


func _cells_equal(img: Image, col_a: int, col_b: int) -> bool:
	return _cells_equal_at(img, col_a, 0, col_b, 0)


func _cells_equal_at(
	img: Image, col_a: int, row_a: int, col_b: int, row_b: int, cell: int = 16
) -> bool:
	for y: int in range(cell):
		for x: int in range(cell):
			var a := img.get_pixel(col_a * cell + x, row_a * cell + y)
			var b := img.get_pixel(col_b * cell + x, row_b * cell + y)
			if not a.is_equal_approx(b):
				return false
	return true


## Nearest authoring-ramp index of a pixel; 0 for transparent (see `TileRamp.RAMP`).
func _ramp_index(c: Color) -> int:
	if c.a == 0.0:
		return 0
	for i: int in range(RAMP.size()):
		if RAMP[i].is_equal_approx(c):
			return i + 1
	return -1


## Ramp index covering most of a rectangle, counting only the four *structural* shades
## (2 wall, 3 floor, 4 floor_alt, 5 wall_top). Outlines and accents are ignored on purpose:
## a lone pillar is mostly outline and a lava seam mostly accent, but neither may change
## the theme role of the surface underneath.
func _dominant_structural_index(img: Image, rect: Rect2i) -> int:
	var counts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var idx := _ramp_index(img.get_pixel(x, y))
			if idx >= 2 and idx <= 5:
				counts[idx] += 1
	var best := 2
	for i: int in range(2, 6):
		if counts[i] > counts[best]:
			best = i
	return best


func test_items_and_ui() -> void:
	_assert_size("res://assets/sprites/items/weapons.png", 320, 16)
	_assert_size("res://assets/sprites/items/armor.png", 96, 16)
	_assert_size("res://assets/sprites/ui/ability_icons.png", 1024, 16)
	_assert_size("res://assets/sprites/ui/glyphs.png", 256, 16)
	_assert_size("res://assets/sprites/ui/icons.png", 256, 16)
	_assert_size("res://assets/sprites/ui/cursor.png", 16, 16)
	var icons := _load("res://assets/sprites/ui/ability_icons.png")
	for col: int in range(27):
		assert_bool(_cell_has_pixels(icons, col, 0, 16)).is_true()
	var logo := _load("res://assets/sprites/logo.png")
	assert_int(logo.get_width()).is_greater_equal(180)
	assert_int(logo.get_height()).is_equal(40)


func test_fonts_present() -> void:
	for f: String in ["PressStart2P-Regular.ttf", "Silkscreen-Regular.ttf", "VT323-Regular.ttf"]:
		assert_bool(FileAccess.file_exists("res://assets/fonts/%s" % f)).is_true()


func test_tile_ramp_indices_carry_their_theme_role() -> void:
	# `TileRamp.target_colors()` pins index 2 -> `wall`, 3 -> `floor`, 4 -> `floor_alt`,
	# 5 -> `wall_top`, so a floor drawn in index 2 (or a wall in index 3) comes out of the
	# palette swap in the wrong role colour and the level stops reading.
	for biome: String in BIOMES:
		var img := _load("res://assets/tiles/%s.png" % biome)
		for col: int in range(4):
			(
				assert_int(_dominant_structural_index(img, Rect2i(col * 16, 0, 16, 16)))
				. override_failure_message("%s floor %d must be index 3 (floor)" % [biome, col])
				. is_equal(3)
			)
			(
				assert_int(_dominant_structural_index(img, Rect2i(col * 16, 32, 16, 16)))
				. override_failure_message(
					"%s wall cap %d must be index 5 (wall_top)" % [biome, col]
				)
				. is_equal(5)
			)
		for mask: int in range(16):
			if mask & 4:
				continue  # a wall with a wall to the south shows its top, not a face
			var face := Rect2i(mask * 16, 16 + 4, 16, 12)
			(
				assert_int(_dominant_structural_index(img, face))
				. override_failure_message("%s wall face %d must be index 2 (wall)" % [biome, mask])
				. is_equal(2)
			)


func test_autotile_cells_are_all_distinct() -> void:
	# Every mask must look different, otherwise the autotile cannot show which side of a
	# run a wall (or pit) edge is on. Also guards against a flat placeholder atlas being
	# dropped over the generated sheets.
	for biome: String in BIOMES:
		var img := _load("res://assets/tiles/%s.png" % biome)
		for a: int in range(16):
			for b: int in range(a + 1, 16):
				(
					assert_bool(_cells_equal_at(img, a, 1, b, 1))
					. override_failure_message(
						"%s wall masks %d and %d are identical" % [biome, a, b]
					)
					. is_false()
				)
				(
					assert_bool(_cells_equal_at(img, a, 3, b, 3))
					. override_failure_message(
						"%s pit masks %d and %d are identical" % [biome, a, b]
					)
					. is_false()
				)


func test_biome_sheets_differ_from_each_other() -> void:
	# Guards against a flat placeholder atlas (FloorBuilder.make_placeholder_atlas) being
	# dropped over one of the generated sheets: those are identical for every biome.
	var bytes: Dictionary = {}
	for biome: String in BIOMES:
		bytes[biome] = FileAccess.get_file_as_bytes("res://assets/tiles/%s.png" % biome)
	for a: int in range(BIOMES.size()):
		for b: int in range(a + 1, BIOMES.size()):
			var left: PackedByteArray = bytes[BIOMES[a]]
			var right: PackedByteArray = bytes[BIOMES[b]]
			(
				assert_bool(left == right)
				. override_failure_message(
					"%s and %s tilesets are identical" % [BIOMES[a], BIOMES[b]]
				)
				. is_false()
			)


func test_prop_columns_match_gameplay_kinds() -> void:
	# `Prop.setup()` picks the sprite by kind index but reads hp/STURDY from the kind name,
	# so the art column order has to equal `Prop.KINDS` and `Biome.prop_kinds`.
	var raw := FileAccess.get_file_as_string("res://tools/art/prop_kinds.json")
	assert_str(raw).override_failure_message("tools/art/prop_kinds.json missing").is_not_empty()
	var parsed: Variant = JSON.parse_string(raw)
	assert_bool(parsed is Dictionary).is_true()
	var art: Dictionary = parsed as Dictionary
	for biome: String in BIOMES:
		var drawn: Array = art.get(biome, [])
		var kinds: Array = Prop.KINDS[StringName(biome)]
		assert_int(drawn.size()).override_failure_message("%s prop count" % biome).is_equal(
			Prop.KIND_COUNT
		)
		for i: int in range(Prop.KIND_COUNT):
			(
				assert_str(str(drawn[i]))
				. override_failure_message(
					(
						"%s column %d: art draws %s, Prop.KINDS says %s"
						% [biome, i, drawn[i], kinds[i]]
					)
				)
				. is_equal(str(kinds[i]))
			)
		var res := load("res://data/biomes/%s.tres" % biome) as Biome
		if res != null:
			for i: int in range(Prop.KIND_COUNT):
				(
					assert_str(str(drawn[i]))
					. override_failure_message("%s column %d vs data/biomes" % [biome, i])
					. is_equal(str(res.prop_kinds[i]))
				)


func test_item_icon_cells_match_item_resources() -> void:
	# data/items/<id>.tres already fixes which cell of the sheet each item shows.
	var raw := FileAccess.get_file_as_string("res://tools/art/item_cells.json")
	assert_str(raw).override_failure_message("tools/art/item_cells.json missing").is_not_empty()
	var parsed: Variant = JSON.parse_string(raw)
	assert_bool(parsed is Dictionary).is_true()
	var cells: Dictionary = parsed as Dictionary
	for sheet: String in ["weapons", "armor"]:
		var names: Array = cells.get(sheet, [])
		(
			assert_bool(names.is_empty())
			. override_failure_message("%s order missing" % sheet)
			. is_false()
		)
		for i: int in range(names.size()):
			var path := "res://data/items/%s.tres" % str(names[i])
			if not ResourceLoader.exists(path):
				continue
			var item := load(path) as ItemBase
			assert_object(item).override_failure_message("%s unreadable" % path).is_not_null()
			var atlas := item.icon as AtlasTexture
			(
				assert_object(atlas)
				. override_failure_message("%s icon not an atlas" % path)
				. is_not_null()
			)
			(
				assert_int(int(atlas.region.position.x) / 16)
				. override_failure_message(
					(
						"%s points at cell %d but the art draws it at %d"
						% [path, int(atlas.region.position.x) / 16, i]
					)
				)
				. is_equal(i)
			)
	var armor := _load("res://assets/sprites/items/armor.png")
	for a: int in range(6):
		assert_bool(_cell_has_pixels(armor, a, 0, 16)).is_true()
		for b: int in range(a + 1, 6):
			(
				assert_bool(_cells_equal(armor, a, b))
				. override_failure_message("armor cells %d and %d are identical" % [a, b])
				. is_false()
			)


func test_big_enemy_sheets_have_every_frame() -> void:
	var counts: Array[int] = [4, 4, 2, 3, 1, 4]
	for id: String in ENEMIES_32:
		var path := "res://assets/sprites/enemies/%s.png" % id
		_assert_size(path, 128, 192)
		var img := _load(path)
		for row: int in range(6):
			for col: int in range(counts[row]):
				(
					assert_bool(_cell_has_pixels(img, col, row, 32))
					. override_failure_message("%s row %d col %d empty" % [id, row, col])
					. is_true()
				)
		(
			assert_bool(_cells_equal_at(img, 0, 5, 3, 5, 32))
			. override_failure_message("%s death frames identical" % id)
			. is_false()
		)
		(
			assert_bool(_cells_equal_at(img, 0, 2, 1, 2, 32))
			. override_failure_message("%s windup frames identical" % id)
			. is_false()
		)


func test_walk_cycles_have_distinct_frames() -> void:
	# A run row whose second half copies the first reads as a 3-frame hop, not a run.
	for cls: String in CLASSES:
		var img := _load("res://assets/sprites/player/%s.png" % cls)
		for a: int in range(6):
			for b: int in range(a + 1, 6):
				(
					assert_bool(_cells_equal_at(img, a, 1, b, 1))
					. override_failure_message(
						"%s run frames %d and %d are identical" % [cls, a, b]
					)
					. is_false()
				)
	for id: String in ENEMIES_16:
		var img := _load("res://assets/sprites/enemies/%s.png" % id)
		for a: int in range(4):
			for b: int in range(a + 1, 4):
				(
					assert_bool(_cells_equal_at(img, a, 1, b, 1))
					. override_failure_message(
						"%s move frames %d and %d are identical" % [id, a, b]
					)
					. is_false()
				)


func test_hurt_frames_keep_the_silhouette_readable() -> void:
	# Code already flashes on hit (Player._flash / EnemyBase.self_modulate), so the hurt
	# art must be a pose, not a solid white silhouette.
	for cls: String in CLASSES:
		var img := _load("res://assets/sprites/player/%s.png" % cls)
		assert_int(_distinct_colors(img, 0, 3, 16)).is_greater(4)
	for id: String in ENEMIES_16:
		var img := _load("res://assets/sprites/enemies/%s.png" % id)
		assert_int(_distinct_colors(img, 0, 4, 16)).is_greater(4)


func _distinct_colors(img: Image, col: int, row: int, cell: int) -> int:
	var seen: Dictionary = {}
	for y: int in range(row * cell, (row + 1) * cell):
		for x: int in range(col * cell, (col + 1) * cell):
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				seen[c.to_html()] = true
	return seen.size()
