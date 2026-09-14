## Owner rule: no otter-shell wording ever reaches the player. otter-shell support keeps
## working, silently; the one name a player may see for that source is "Otter" ("Dungeon of
## Otter", "Theme: Otter"). Omarchy wording is fine and welcome.
##
## Enforced two ways: the palette and source labels the desktop module hands to the UI are
## checked directly, and every string literal in `src/desktop` is scanned - a literal that
## mentions otter must be either the display name "Otter" exactly or a file-system token (a
## path, a config file name, a state file), never a sentence or a label.
class_name NoOtterWordingTest
extends GdUnitTestSuite

const DESKTOP_DIR := "res://src/desktop"
const DISPLAY_NAME := "Otter"
## What a file-system token looks like: something the player never reads. "otter-shell" on
## its own is deliberately not a marker - a toast saying it is exactly the failure.
const PATH_MARKERS: PackedStringArray = ["/", ".conf", "-state"]


func test_the_otter_palette_and_source_are_named_otter_and_nothing_else() -> void:
	var colors := {
		"background": Color("#1a1b26"),
		"foreground": Color("#c0caf5"),
		"accent": Color("#7aa2f7"),
		"danger": Color("#f7768e"),
		"success": Color("#9ece6a"),
		"warning": Color("#e0af68"),
	}
	var palette := ThemePalette.from_otter_colors(colors, DISPLAY_NAME)
	assert_str(palette.name).is_equal(DISPLAY_NAME)
	# The watcher is the only caller, and it must pass exactly that name.
	var source := FileAccess.get_file_as_string(DESKTOP_DIR + "/desktop_watcher.gd")
	assert_str(source).contains('from_otter_colors(otter_colors, "%s")' % DISPLAY_NAME)
	assert_str(source).not_contains('"otter-shell"')
	assert_str(source).not_contains('"Otter Shell"')
	assert_str(Hud.desktop_line(DISPLAY_NAME, false)).is_equal("Shaped by Otter")
	assert_str(Toast.THEME_PREFIX + palette.name).is_equal("Theme: Otter")


func test_no_string_literal_in_the_desktop_module_wears_otter_shell_wording() -> void:
	var dir := DirAccess.open(DESKTOP_DIR)
	assert_object(dir).is_not_null()
	var offenders := PackedStringArray()
	var scanned := 0
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		scanned += 1
		var lines := FileAccess.get_file_as_string(DESKTOP_DIR.path_join(file)).split("\n")
		for i in range(lines.size()):
			var line: String = lines[i]
			if line.strip_edges().begins_with("#"):
				continue
			for literal: String in _string_literals(line):
				if literal.to_lower().find("otter") < 0:
					continue
				if literal == DISPLAY_NAME or _is_path_token(literal, line):
					continue
				offenders.append("%s:%d %s" % [file, i + 1, literal])
	assert_int(scanned).is_greater(3)
	(
		assert_array(offenders)
		. override_failure_message("player-facing otter wording: %s" % ", ".join(offenders))
		. is_empty()
	)


## A literal that is a path, a config file name, or a segment handed to `path_join`.
static func _is_path_token(literal: String, line: String) -> bool:
	if line.find("path_join(") >= 0:
		return true
	for marker: String in PATH_MARKERS:
		if literal.find(marker) >= 0:
			return true
	return false


## Every double-quoted literal on one line (escapes skipped), without the quotes.
static func _string_literals(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var i := 0
	while i < line.length():
		if line[i] != '"':
			i += 1
			continue
		var j := i + 1
		var literal := ""
		while j < line.length() and line[j] != '"':
			if line[j] == "\\" and j + 1 < line.length():
				j += 1
			literal += line[j]
			j += 1
		out.append(literal)
		i = j + 1
	return out
