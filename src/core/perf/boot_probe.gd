## Measures time to the title screen. Run it as the main loop:
##
##     godot --headless --path . -s res://src/core/perf/boot_probe.gd
##
## It prints `BOOT_MS=<n>` — engine-relative milliseconds (`Time.get_ticks_msec()` starts at
## engine init) from boot to the frame on which `Main` has the title screen up and has been
## drawn once. Every autoload in project.godot is already alive at `_initialize()`, so that
## number covers autoload construction, theme/palette discovery, scene load and first layout.
## The only thing it cannot see is process exec and dynamic linking before the engine starts;
## wrap the command in `/usr/bin/time` for the wall-clock figure that includes those.
class_name BootProbe
extends SceneTree

const MAIN_SCENE := "res://src/main.tscn"
const SANDBOX_SCRIPT := "res://src/core/perf/perf_sandbox.gd"
## Frames waited after the title screen exists, so the number covers a drawn frame and not
## just a constructed node.
const SETTLE_FRAMES := 2
## Frames after which the probe gives up rather than hanging a CI job.
const GIVE_UP_FRAMES := 600


func _initialize() -> void:
	_measure()


func _measure() -> void:
	# The title screen reads the profile and can write settings; a `-s` launch is not a shape
	# SaveManager sandboxes by itself, so redirect the save paths before the scene exists.
	var sandbox := load(SANDBOX_SCRIPT) as GDScript
	sandbox.apply(self, "boot")
	if not sandbox.is_safe(self):
		push_error("BootProbe: refusing to run, the save sandbox is not in place")
		quit(2)
		return
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("BootProbe: cannot load %s" % MAIN_SCENE)
		quit(2)
		return
	var main := packed.instantiate()
	root.add_child(main)
	current_scene = main
	var waited := 0
	while not _title_up(main) and waited < GIVE_UP_FRAMES:
		waited += 1
		await process_frame
	for i in range(SETTLE_FRAMES):
		await process_frame
	if not _title_up(main):
		push_error("BootProbe: title screen never came up")
		quit(2)
		return
	print("BOOT_MS=%d" % Time.get_ticks_msec())
	quit()


## True once `Main` has its screen instantiated and visible. Read through `get()` rather than
## a typed `as Main`: a `-s` main-loop script is compiled *before* the autoloads become global
## identifiers, so naming a class that touches `GameState` would fail to compile at boot.
static func _title_up(main: Node) -> bool:
	if main == null or not is_instance_valid(main):
		return false
	var screen := main.get(&"current") as Control
	return screen != null and is_instance_valid(screen) and screen.is_visible_in_tree()
