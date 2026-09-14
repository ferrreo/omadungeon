## Headless entry point for the balance simulation: prints the same tables
## `tests/unit/balance/balance_targets_test.gd` asserts on, without the test harness around
## them, so a balance pass can iterate in one run instead of a whole suite.
##
## It is a scene rather than a `--script` main loop because the simulation reads shipped
## content through registries that reach for autoloads; `-s` starts before those exist.
## [codeblock]
## godot --headless --path . res://src/core/balance/sim_main.tscn -- --runs 150
## [/codeblock]
class_name SimMain
extends Node

const DEFAULT_RUNS := 150
const DEFAULT_SEED := 20260912


func _ready() -> void:
	var runs := DEFAULT_RUNS
	var seed_value := DEFAULT_SEED
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--runs":
			runs = maxi(1, int(args[i + 1]))
		elif args[i] == "--seed":
			seed_value = int(args[i + 1])
	var sim := BalanceSim.run(runs, seed_value)
	print("\n" + sim.to_text())
	print("\n" + sim.ramp_text())
	print("\n" + sim.identity_text())
	print("\n" + sim.weapon_text())
	get_tree().quit(0)
