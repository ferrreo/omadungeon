## The perf tools drive the real game from a `-s` main loop, which `SaveManager` does not
## recognise as a test launch — so without `PerfSandbox` a benchmark run overwrites the
## player's own run.json / profile.json / settings.json. This suite pins the guard.
class_name PerfSandboxTest
extends GdUnitTestSuite

const ENTRY_POINTS: Array[String] = [
	"res://src/core/perf/perf_main.gd", "res://src/core/perf/boot_probe.gd"
]

var _run_path: String = ""
var _profile_path: String = ""
var _settings_path: String = ""


func before_test() -> void:
	var save := _autoload(&"SaveManager")
	if save != null:
		_run_path = str(save.get(&"run_path"))
		_profile_path = str(save.get(&"profile_path"))
	_settings_path = GameState.settings_path


func after_test() -> void:
	var save := _autoload(&"SaveManager")
	if save != null:
		save.set(&"run_path", _run_path)
		save.set(&"profile_path", _profile_path)
	GameState.settings_path = _settings_path


func test_apply_points_every_save_path_into_the_sandbox() -> void:
	var dir := PerfSandbox.apply(get_tree(), "unit")
	assert_str(dir).starts_with(PerfSandbox.ROOT + "/")
	var save := _autoload(&"SaveManager")
	assert_object(save).is_not_null()
	assert_str(str(save.get(&"run_path"))).is_equal(dir + "/run.json")
	assert_str(str(save.get(&"profile_path"))).is_equal(dir + "/profile.json")
	assert_str(GameState.settings_path).is_equal(dir + "/settings.json")
	assert_bool(PerfSandbox.is_safe(get_tree())).is_true()


func test_is_safe_actually_catches_the_unsandboxed_case() -> void:
	# A guard that always says yes is worse than none: point the autoload at the real file and
	# the check must fail. This is exactly the state a `-s` launch starts in.
	var save := _autoload(&"SaveManager")
	assert_object(save).is_not_null()
	save.set(&"run_path", "user://run.json")
	assert_bool(PerfSandbox.is_safe(get_tree())).is_false()
	PerfSandbox.apply(get_tree(), "unit")
	assert_bool(PerfSandbox.is_safe(get_tree())).is_true()


func test_every_perf_entry_point_sandboxes_before_it_drives_the_game() -> void:
	for path: String in ENTRY_POINTS:
		var text := FileAccess.get_file_as_string(path)
		assert_str(text).override_failure_message("%s does not load PerfSandbox" % path).contains(
			"perf_sandbox.gd"
		)
		var applied := text.find("sandbox.apply(")
		var guarded := text.find("is_safe(")
		assert_int(applied).override_failure_message("%s never applies it" % path).is_greater(-1)
		assert_int(guarded).override_failure_message("%s never checks it" % path).is_greater(
			applied
		)


func _autoload(autoload_name: StringName) -> Node:
	return get_tree().root.get_node_or_null(NodePath(autoload_name))
