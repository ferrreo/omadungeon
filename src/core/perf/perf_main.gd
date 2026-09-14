## Standalone benchmark runner — the numbers to quote come from here, not from the test suite,
## because a test runner's own work lands in the same frames it is trying to measure.
##
##     godot --headless --path . -s res://src/core/perf/perf_main.gd
##     godot --headless --path . -s res://src/core/perf/perf_main.gd -- --no-pool
##     godot --headless --path . -s res://src/core/perf/perf_main.gd -- --scale 4
##
## Prints the load report, then the five-floor build/teardown census. `--no-pool` repeats the
## load with `Projectile.new()` per shot instead of the pool, for an A/B on the same machine;
## `--scale N` multiplies the budgeted projectile and enemy counts, to find the cliff rather
## than only confirming the target.
class_name PerfMain
extends SceneTree

const BENCH_SCRIPT := "res://src/core/perf/perf_bench.gd"
const CENSUS_SCRIPT := "res://src/core/perf/node_census.gd"
const SANDBOX_SCRIPT := "res://src/core/perf/perf_sandbox.gd"
## Frames waited before the benchmark starts, so the autoloads are live.
const SETTLE_FRAMES := 8


func _initialize() -> void:
	_run()


func _run() -> void:
	# `_initialize()` runs before the tree has entered: the autoloads exist as nodes but
	# `Desktop` has not read the theme yet and `get_tree()` is not answerable from a node just
	# added to `root`. Let a few frames pass before anything asks either of them a question.
	for i in range(SETTLE_FRAMES):
		await process_frame
	# The benchmark drives a real run, and a `-s` launch is not one of the shapes SaveManager
	# recognises as a test: without this it would overwrite the player's own save files.
	var sandbox := load(SANDBOX_SCRIPT) as GDScript
	var dir: String = sandbox.apply(self, "perf")
	if not sandbox.is_safe(self):
		push_error("PerfMain: refusing to run, the save sandbox is not in place")
		quit(2)
		return
	print("\nsaves sandboxed in %s" % dir)
	# Loaded at runtime, not with a typed reference: a `-s` main-loop script is compiled before
	# the autoloads exist as global identifiers, and `PerfBench` reaches for `RunManager`.
	var bench_script := load(BENCH_SCRIPT) as GDScript
	var census := load(CENSUS_SCRIPT) as GDScript
	if bench_script == null or census == null:
		push_error("PerfMain: could not load the perf module")
		quit(2)
		return
	var pooled := not _has_flag("--no-pool")
	var scale := maxf(0.1, _flag_value("--scale", 1.0))
	var bench: Node = bench_script.new()
	bench.pool_projectiles = pooled
	if not is_equal_approx(scale, 1.0):
		var budget: Resource = bench.budget.duplicate()
		budget.projectile_count = int(roundf(budget.projectile_count * scale))
		budget.enemy_count = int(roundf(budget.enemy_count * scale))
		bench.budget = budget
	root.add_child(bench)
	print(
		(
			"\n=== omadungeon perf bench (%s, %dx%d load) ==="
			% [
				"pooled" if pooled else "unpooled",
				bench.budget.projectile_count,
				bench.budget.enemy_count,
			]
		)
	)
	print("boot to this point: %d ms" % Time.get_ticks_msec())
	var report: Dictionary = await bench.run_load()
	print(bench_script.format_report(report))

	var cycles: Dictionary = await bench.run_floor_cycles()
	var build: Dictionary = cycles["build_ms"]
	print(
		(
			"\n%d floors built and torn down: build avg %.1f ms worst %.1f ms"
			% [int(cycles["cycles"]), build["average_ms"], build["worst_ms"]]
		)
	)
	print("  before %s" % census.describe(cycles["before"]))
	print("  after  %s" % census.describe(cycles["after"]))
	print("  diff   %s" % census.describe(cycles["diff"]))
	bench.queue_free()
	await process_frame
	quit()


static func _has_flag(flag: String) -> bool:
	return _args().has(flag)


## Value after `flag` on the command line, or `fallback` when it is absent.
static func _flag_value(flag: String, fallback: float) -> float:
	var args := _args()
	var at := args.find(flag)
	if at < 0 or at + 1 >= args.size():
		return fallback
	return float(args[at + 1])


static func _args() -> PackedStringArray:
	var out := PackedStringArray(OS.get_cmdline_user_args())
	out.append_array(PackedStringArray(OS.get_cmdline_args()))
	return out
