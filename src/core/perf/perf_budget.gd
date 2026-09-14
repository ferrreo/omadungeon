## The performance target as data (docs §13.4): the CPU/simulation cost of two hundred
## projectiles and forty enemies alive at once must fit inside a sixty-frames-per-second
## frame. Every number the benchmark and the perf tests judge against lives in
## `data/perf/benchmark.tres`, not in a script.
##
## What these budgets are *not*: a frame rate on a particular GPU. `PerfBench` runs headless,
## so nothing here has seen a rasterised frame, and the doc's old "on integrated graphics"
## was measured by nothing. The millisecond budgets below bound script time only.
class_name PerfBudget
extends Resource

const DEFAULT_PATH := "res://data/perf/benchmark.tres"

## Projectiles kept alive for the whole measurement window.
@export var projectile_count: int = 200
## Enemies kept alive for the whole measurement window.
@export var enemy_count: int = 40
## Frames simulated before sampling starts (lets spawn tweens and the first repath settle).
@export var warmup_frames: int = 60
## Frames sampled.
@export var measure_frames: int = 240
## The frame rate the load must hold.
@export var target_fps: float = 60.0
## Budget for the average frame, in milliseconds.
@export var average_budget_ms: float = 16.67
## Budget for the 95th-percentile frame, in milliseconds.
@export var p95_budget_ms: float = 16.67
## Budget for the single worst frame, in milliseconds. Deliberately looser: one spike while a
## floor streams in is acceptable, a spike every twentieth frame is not.
@export var worst_budget_ms: float = 50.0
## Floors built and torn down in a row by the leak check.
@export var floor_cycles: int = 5
## Nodes the leak check tolerates above baseline after those cycles.
@export var node_leak_tolerance: int = 0
## Seconds allowed from process start to the title screen being up.
@export var boot_budget_seconds: float = 2.0


## The shipped budget, or an all-defaults instance when the resource is missing.
static func load_default() -> PerfBudget:
	if ResourceLoader.exists(DEFAULT_PATH):
		var res := load(DEFAULT_PATH) as PerfBudget
		if res != null:
			return res
	return PerfBudget.new()


## Milliseconds one frame may take at `target_fps`.
func frame_budget_ms() -> float:
	return 1000.0 / maxf(1.0, target_fps)
