## Screenshot gallery for weapon anchoring: one grid of live `Player` nodes per beat of an
## attack, every weapon family across every facing, captured to
## `<screenshot-dir>/weapon_pose_<beat>.png`.
##
## It exists because "the weapon looks held" is not a claim a unit test can make. A test can
## assert that the hand is 6 px from the body centre; only a picture shows that the sword is
## hanging off the character's face when they turn around. The grid is deliberately the shape
## of the bug report - *the same weapon, in every facing, side by side* - so a facing that is
## anchored differently from its neighbours is visible at a glance instead of needing eight
## separate captures compared from memory.
##
## Captured by `tools/art/weapon-poses.sh [theme-fixture]`, which runs it the way
## `tools/ui-gallery.sh` runs the UI one: against an rsync'd copy, inside a nested headless
## compositor, never on the real session.
##
## Poses are driven through the real `WeaponController.handle_input` with the pivot aimed the
## way `Player._physics_process` aims it, so the picture shows the shipping code path and not a
## pose posed by hand.
class_name WeaponPoseGallery
extends Node2D

## Rendered size of one capture. Far larger than the game's 480x270 so a 16 px weapon on a
## 16 px character is actually inspectable, with a margin for the row and column labels.
const VIEW_SIZE := Vector2i(1000, 700)
## World units one grid cell occupies.
const CELL := Vector2(40.0, 36.0)
## Camera zoom. The grid is `CELL * (columns, rows) * ZOOM` pixels and must fit in `VIEW_SIZE`.
const ZOOM := 2.5
## Facing label, aim direction. Eight directions, because the four diagonals are where a
## quadrant-based anchor betrays itself.
const FACINGS: Array[Array] = [
	["E", Vector2(1, 0)],
	["SE", Vector2(1, 1)],
	["S", Vector2(0, 1)],
	["SW", Vector2(-1, 1)],
	["W", Vector2(-1, 0)],
	["NW", Vector2(-1, -1)],
	["N", Vector2(0, -1)],
	["NE", Vector2(1, -1)],
]
## Row label, item id, class the row is captured as.
const ROWS: Array[Array] = [
	["sword", "rusty_sword", "fighter"],
	["spear", "spear", "fighter"],
	["bow", "shortbow", "ranger"],
	["wand", "wand", "wizard"],
	["knives", "throwing_knives", "ranger"],
	["cane", "golden_cane", "oligarch"],
]
## Capture name, seconds into the held attack the shot is taken at. The melee timeline is
## anticipation 0-0.05 s, impact 0.05-0.17 s, recovery after that.
const BEATS: Array[Array] = [
	["rest", 0.0],
	["wind", 0.035],
	["impact", 0.105],
	["recover", 0.26],
]
## Seconds the dodge capture waits after the roll starts.
const DODGE_AT := 0.12
const BACKDROP := Color(0.13, 0.14, 0.19)
const LABEL_COLOR := Color(0.72, 0.76, 0.86)
const GRID_COLOR := Color(1, 1, 1, 0.06)

var _out_dir: String = "tests/out"
var _view: SubViewport
var _world: Node2D
var _labels: CanvasLayer
var _players: Array[Player] = []
var _aims: Array[Vector2] = []
var _holding: bool = false


func _ready() -> void:
	_out_dir = str(GameState.cli_args.get("screenshot-dir", "tests/out"))
	_build_view()
	# Deferred: a `Player` adds its own feel children in `_ready`, and the engine refuses an
	# `add_child` made while a parent is still setting up its own.
	_start.call_deferred()


func _start() -> void:
	_build_grid()
	_run()


func _build_view() -> void:
	_view = SubViewport.new()
	_view.size = VIEW_SIZE
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_view)
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.size = Vector2(VIEW_SIZE)
	_view.add_child(backdrop)
	_world = Node2D.new()
	_world.name = "World"
	_view.add_child(_world)
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE * ZOOM
	camera.position = _grid_centre()
	_world.add_child(camera)
	camera.make_current()
	_labels = CanvasLayer.new()
	_view.add_child(_labels)


func _grid_centre() -> Vector2:
	return Vector2(float(FACINGS.size()) * CELL.x, float(ROWS.size()) * CELL.y) * 0.5


func _cell_position(col: int, row: int) -> Vector2:
	return Vector2((float(col) + 0.5) * CELL.x, (float(row) + 0.5) * CELL.y)


## World position -> pixel in the capture, for the label layer.
func _screen_position(world: Vector2) -> Vector2:
	return (world - _grid_centre()) * ZOOM + Vector2(VIEW_SIZE) * 0.5


func _build_grid() -> void:
	for row in range(ROWS.size()):
		var row_label := String(ROWS[row][0])
		var item_id := String(ROWS[row][1])
		var class_id := String(ROWS[row][2])
		var side := _screen_position(_cell_position(0, row)) + Vector2(-CELL.x * ZOOM * 0.8, 0.0)
		_add_label(row_label, side)
		for col in range(FACINGS.size()):
			if row == 0:
				var top := _cell_position(col, 0)
				var head := _screen_position(top) + Vector2(0.0, -CELL.y * ZOOM * 0.7)
				_add_label(String(FACINGS[col][0]), head)
			var aim := (FACINGS[col][1] as Vector2).normalized()
			var player := _make_player(class_id, item_id)
			player.position = _cell_position(col, row)
			_world.add_child(player)
			player.apply_class(load("res://data/classes/%s.tres" % class_id) as ClassDef)
			var weapon := load("res://data/items/%s.tres" % item_id) as WeaponBase
			player.weapon_controller.set_weapon(weapon)
			# After `add_child`, not before: a Player that keeps its own physics running re-aims
			# at the mouse every frame, and with no mouse in a headless capture that is the
			# viewport origin - every character in the grid pointing at the same corner.
			player.set_physics_process(false)
			_players.append(player)
			_aims.append(aim)
	_draw_guides()


func _make_player(_class_id: String, _item_id: String) -> Player:
	var player := (load("res://src/player/player.tscn") as PackedScene).instantiate() as Player
	player.input_enabled = false
	player.set_physics_process(false)
	return player


## Faint cell separators, so the eye can tell which character belongs to which facing.
func _draw_guides() -> void:
	var lines := Line2D.new()
	lines.width = 0.5
	lines.default_color = GRID_COLOR
	_world.add_child(lines)
	for col in range(1, FACINGS.size()):
		var grid := Line2D.new()
		grid.width = 0.4
		grid.default_color = GRID_COLOR
		grid.points = PackedVector2Array(
			[
				Vector2(float(col) * CELL.x, 0.0),
				Vector2(float(col) * CELL.x, float(ROWS.size()) * CELL.y)
			]
		)
		_world.add_child(grid)
	for row in range(1, ROWS.size()):
		var grid := Line2D.new()
		grid.width = 0.4
		grid.default_color = GRID_COLOR
		grid.points = PackedVector2Array(
			[
				Vector2(0.0, float(row) * CELL.y),
				Vector2(float(FACINGS.size()) * CELL.x, float(row) * CELL.y)
			]
		)
		_world.add_child(grid)


func _add_label(text: String, at: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.add_theme_font_size_override("font_size", 16)
	label.position = at - Vector2(28.0, 8.0)
	label.size = Vector2(56.0, 16.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_labels.add_child(label)


## Aims every character and, once `_holding` is set, holds the attack button down on all of
## them - exactly the calls `Player._physics_process` makes.
func _physics_process(_delta: float) -> void:
	for i in range(_players.size()):
		var player := _players[i]
		var aim := _aims[i]
		player.facing = aim
		player.weapon_pivot.rotation = aim.angle()
		player.refresh_carry(aim)
		if _holding:
			player.weapon_controller.handle_input(aim, true, false, false, false)


func _run() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	var failures := 0
	failures += await _capture("weapon_pose_rest")
	for i in range(_players.size()):
		_players[i].weapon_controller.handle_input(_aims[i], true, true, false, false)
	_holding = true
	var elapsed := 0.0
	for beat in BEATS:
		var name := String(beat[0])
		if name == "rest":
			continue
		var at := float(beat[1])
		await get_tree().create_timer(maxf(0.001, at - elapsed)).timeout
		elapsed = at
		failures += await _capture("weapon_pose_%s" % name)
	_holding = false
	failures += await _capture_dodge()
	print("Weapon pose gallery: done, %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


## The same grid in the dodge state: the beat where the weapon used to stay out on a straight
## arm while the character rolled along the ground. The characters keep their physics switched
## off, so they hold the dodge pose instead of dashing, blinking and scattering caltrops out of
## their own cells - the capture is about how the weapon is carried, not about where the roll
## ends up.
func _capture_dodge() -> int:
	for i in range(_players.size()):
		_players[i].try_dodge(_aims[i])
	await get_tree().create_timer(DODGE_AT).timeout
	return await _capture("weapon_pose_dodge")


func _capture(shot_name: String) -> int:
	await RenderingServer.frame_post_draw
	var image := _view.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir.path_join("%s.png" % shot_name)
	var err := image.save_png(path)
	print("Weapon pose gallery: %s (%s)" % [path, error_string(err)])
	return 0 if err == OK else 1
