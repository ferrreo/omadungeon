## Compile gate. Re-parses **every** project `.gd` and exits non-zero if any of them fails.
##
## Run through `tools/check-scripts.sh`, never on its own; it is a `MainLoop` script
## (`godot --headless --path . -s res://tools/check_scripts.gd`) rather than a plain tool
## because the autoloads have to exist: `--check-only -s <script>` parses one file with no
## `EventBus`/`GameState`/`Desktop` in scope, so it reports "Identifier not found: EventBus"
## for two thirds of the tree and is useless as a gate.
##
## Why this exists at all: `godot --headless --import` - what this check used to be - does not
## re-parse a script whose cache it believes is current, so it printed "scripts ok" over a tree
## holding a hard parse error. Loading with `CACHE_MODE_IGNORE` forces the parser to run on
## every file, which is the only way the answer means anything.
##
## Verdict per file: `ResourceLoader.load(..., CACHE_MODE_IGNORE)` returns a `GDScript` whose
## `can_instantiate()` is false when the parse or the compile failed. `@abstract` scripts
## cannot be instantiated either and are not failures, so they are excluded by `is_abstract()`.
class_name ScriptCompileCheck
extends SceneTree

## Directories swept, in order. `addons/` is third-party and not this project's contract.
const ROOTS: PackedStringArray = ["res://src", "res://tests", "res://tools"]
## Exit code when at least one script failed to compile.
const EXIT_BAD_SCRIPT := 1
## Exit code when the sweep found no scripts at all - a broken sweep, not a clean tree.
const EXIT_NO_SCRIPTS := 6


func _initialize() -> void:
	# This script is the running main loop. Re-parsing it from inside itself wedges the engine
	# (no error, no exit - the process hangs until the caller's deadline), so it is skipped; the
	# shell wrapper failing to launch it at all is what catches a broken checker.
	var self_script := get_script() as Script
	var files := collect(ROOTS, self_script.resource_path if self_script != null else "")
	if files.is_empty():
		printerr(
			"check_scripts: found no .gd files under %s - the sweep is broken." % ", ".join(ROOTS)
		)
		quit(EXIT_NO_SCRIPTS)
		return
	var bad := failures(files)
	print("check_scripts: %d scripts parsed, %d failed" % [files.size(), bad.size()])
	for path: String in bad:
		print("check_scripts: FAILED %s" % path)
	quit(EXIT_BAD_SCRIPT if not bad.is_empty() else 0)


## Every `.gd` under `roots` except `skip`, sorted so two runs report in the same order.
static func collect(roots: PackedStringArray, skip: String = "") -> PackedStringArray:
	var out: PackedStringArray = []
	for root: String in roots:
		_walk(root, out)
	if not skip.is_empty():
		var kept: PackedStringArray = []
		for path: String in out:
			if path != skip:
				kept.append(path)
		out = kept
	out.sort()
	return out


## The subset of `files` that does not compile. Each is re-parsed from source (the engine's
## script cache is ignored), so a stale cache entry cannot vouch for a file it no longer matches.
static func failures(files: PackedStringArray) -> PackedStringArray:
	var bad: PackedStringArray = []
	for path: String in files:
		if not compiles(path):
			bad.append(path)
	return bad


## True when `path` parses and compiles. The engine prints the reason (`Parse Error`,
## `Compile Error`, `Failed to load script`) on stderr as a side effect; the shell wrapper
## surfaces those lines.
static func compiles(path: String) -> bool:
	var script := ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if script == null:
		return false
	return script.can_instantiate() or script.is_abstract()


static func _walk(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk(path, out)
		elif entry.ends_with(".gd"):
			out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
