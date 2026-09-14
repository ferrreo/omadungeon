## The §14 debug-flag list in docs/GAME_DESIGN.md against the flags the source actually reads.
##
## The doc listed nine flags for a long time and the build read two of them. Four of the seven
## missing ones (`--god`, `--screenshot-every`, `--debug-http`, `--no-music`) were never written;
## `--seed`, `--floor` and `--class` never were either, though their names appear all over the
## source as ordinary words, which is how a `grep` for them keeps saying otherwise. One of them
## was load-bearing in the documented VM methodology: §14.3b said the theme-switch test asserted
## the retint "via the game's `--debug-http` endpoint", and `tools/vm/verify.sh` cannot do that,
## because no such endpoint exists.
##
## So the list is pinned here in both directions. A flag the source reads must be documented as
## available; a flag documented as *not implemented* must not be readable. Adding a flag without
## documenting it fails, and so does documenting one nobody wrote.
class_name DebugFlagsTest
extends GdUnitTestSuite

const DOC_PATH := "res://docs/GAME_DESIGN.md"
const SRC_ROOT := "res://src"
const AVAILABLE_MARKER := "Debug flags the build actually reads"
const MISSING_MARKER := "**Not implemented**"


func test_the_documented_flags_are_exactly_the_flags_the_source_reads() -> void:
	var documented := _flags_in(_doc_section(AVAILABLE_MARKER, MISSING_MARKER))
	var read := _flags_read_by_source()
	assert_array(documented).override_failure_message("§14 lists no available flags").is_not_empty()
	(
		assert_array(documented)
		. override_failure_message(
			"docs §14 says the build reads %s; it reads %s" % [str(documented), str(read)]
		)
		. is_equal(read)
	)


func test_no_flag_the_doc_calls_unimplemented_is_readable() -> void:
	var missing := _flags_in(_doc_section(MISSING_MARKER, "\n---"))
	var read := _flags_read_by_source()
	(
		assert_array(missing)
		. override_failure_message("§14 lists no unimplemented flags")
		. is_not_empty()
	)
	for flag: String in missing:
		(
			assert_bool(read.has(flag))
			. override_failure_message(
				"docs §14 calls --%s unimplemented, but the source reads it" % flag
			)
			. is_false()
		)


## The paragraph between two markers in the design doc, or "" when the first is missing.
func _doc_section(from_marker: String, to_marker: String) -> String:
	var text := FileAccess.get_file_as_string(DOC_PATH)
	assert_str(text).override_failure_message("%s is unreadable" % DOC_PATH).is_not_empty()
	var start := text.find(from_marker)
	if start < 0:
		return ""
	var end := text.find(to_marker, start + from_marker.length())
	return text.substr(start, end - start) if end > start else text.substr(start)


## Every `` `--flag` `` named in `section`, sorted and deduplicated.
func _flags_in(section: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string("`--([a-z0-9-]+)")
	for m: RegExMatch in re.search_all(section):
		var flag := m.get_string(1)
		if not out.has(flag):
			out.append(flag)
	out.sort()
	return out


## Every flag name reached through `GameState.cli_args` anywhere under `src/`, sorted. Covers
## the three shapes the source uses: `.get("x", default)`, `.has("x")` and `["x"]`.
func _flags_read_by_source() -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string('cli_args(?:\\.(?:get|has)\\(|\\[)\\s*"([a-z0-9-]+)"')
	for path: String in _scripts_under(SRC_ROOT):
		var text := FileAccess.get_file_as_string(path)
		for m: RegExMatch in re.search_all(text):
			var flag := m.get_string(1)
			if not out.has(flag):
				out.append(flag)
	out.sort()
	return out


func _scripts_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for name: String in dir.get_directories():
		out.append_array(_scripts_under(dir_path.path_join(name)))
	for name: String in dir.get_files():
		if name.ends_with(".gd"):
			out.append(dir_path.path_join(name))
	return out
