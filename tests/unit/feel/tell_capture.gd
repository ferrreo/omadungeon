## Rendered check for the danger tell. Runs as its own main scene inside the nested headless
## sway harness (never on the real session):
##
##   OMADUNGEON_OMARCHY_STATE_DIR=tests/fixtures/omarchy/tokyo-night/state \
##   tools/headless-sway.sh godot --path . --rendering-driver opengl3 \
##       res://tests/unit/feel/tell_capture.tscn
##
## It draws the real `Telegraph` an enemy winds up with next to the real `TrapBase` arming
## overlay inside a 480x270 SubViewport — the game's native resolution — and saves
## `tests/out/feel_tell.png`, so "is the tell unmistakable at 1:1?" is answered by looking.
class_name FeelTellCapture
extends Node

const VIEW_SIZE := Vector2i(480, 270)
## Windup length the capture samples; long enough that the tell is mid-ramp when shot.
const WINDUP := 0.8
## Real seconds between the three sampled enemies, so one capture shows the whole ramp.
const STAGGER := 0.3
## Real seconds of settling before the screenshot.
const SETTLE := 0.1


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var view := SubViewport.new()
	view.size = VIEW_SIZE
	view.transparent_bg = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(view)
	# The floor comes from the live palette, so the capture is a fair contrast test on a light
	# theme (the `white` fixture) as well as a dark one.
	var ground := ColorRect.new()
	ground.size = Vector2(VIEW_SIZE)
	ground.color = Desktop.palette.get_color(&"floor") if Desktop.palette != null else Color.BLACK
	view.add_child(ground)
	# Three enemies started STAGGER apart, so one capture shows the same windup early, mid and
	# late, all at native 1:1 scale next to an arming trap.
	_add_trap_tell(view, Vector2(350, 150))
	_add_enemy_tell(view, Vector2(230, 150))
	await get_tree().create_timer(STAGGER).timeout
	_add_enemy_tell(view, Vector2(150, 150))
	await get_tree().create_timer(STAGGER).timeout
	_add_enemy_tell(view, Vector2(70, 150))
	await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	var path := ProjectSettings.globalize_path(_out_path())
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("tell capture -> %s (%s)" % [path, error_string(image.save_png(path))])
	get_tree().quit(0)


## `tests/out/feel_tell.png`, with `_<theme>` appended for any fixture but the default.
##
## It used to write the bare name whatever fixture it was run against, so a `white` capture
## landed straight on top of the `tokyo-night` one and nothing in `tests/out` said which theme
## a `feel_tell.png` showed - the same "a filename claiming something the picture does not
## show" failure `tools/run-scenario.sh` refuses a bad theme argument over.
static func _out_path() -> String:
	var state := OS.get_environment("OMADUNGEON_OMARCHY_STATE_DIR")
	var theme := state.trim_suffix("/").get_base_dir().get_file() if not state.is_empty() else ""
	if theme.is_empty() or theme == "tokyo-night":
		return "res://tests/out/feel_tell.png"
	return "res://tests/out/feel_tell_%s.png" % theme


## The enemy half: a real Telegraph ring under a body pulsing with the same DangerTell maths.
func _add_enemy_tell(view: SubViewport, pos: Vector2) -> void:
	var holder := Node2D.new()
	holder.position = pos
	view.add_child(holder)
	var tell := Telegraph.new()
	holder.add_child(tell)
	var body := Sprite2D.new()
	body.texture = _body_texture()
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.position = Vector2(0, -8)
	holder.add_child(body)
	tell.flash(WINDUP, 16.0)
	body.self_modulate = Color.WHITE.lerp(DangerTell.color(), 0.45)


## The trap half: a real TrapBase in its TELEGRAPH state.
func _add_trap_tell(view: SubViewport, pos: Vector2) -> void:
	var trap := TrapBase.new()
	trap.kind = &"spike_floor"
	trap.telegraph_time = WINDUP + STAGGER * 2.0
	trap.hitbox_size = Vector2(16, 16)
	trap.position = pos
	view.add_child(trap)
	trap.trigger()


## A 16x16 stand-in body so the ring has something to sit under.
static func _body_texture() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(4, 2, 8, 12), Color(0.85, 0.85, 0.9))
	img.fill_rect(Rect2i(5, 4, 2, 2), Color(0.1, 0.1, 0.12))
	img.fill_rect(Rect2i(9, 4, 2, 2), Color(0.1, 0.1, 0.12))
	return ImageTexture.create_from_image(img)
