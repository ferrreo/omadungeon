## The RunState floor-block contract in docs/MODULE_APIS.md against `RunState.floor_state_dict()`.
##
## That line said "nine fields" and enumerated nine while the code wrote eleven, then fifteen.
## `floor_pickups` was added in one round and `floor_drops` in the next, and neither reached the
## doc; both are fields whose whole purpose is that loot on the floor survives a Save & Quit, so
## a reader integrating against the contract had no way to know they existed. A hand-kept count
## is what rotted, so the count is gone and this is what keeps the list honest instead: every key
## the dictionary carries has to be named in the doc.
##
## Deliberately one direction only. "The doc names nothing the code does not have" cannot be
## asserted from a prose paragraph without guessing which words are meant to be field names, and
## a guess that is wrong fails the build for a sentence. The direction that matters is this one:
## a field added to the save and not written down is a contract nobody can read.
class_name RunStateDocTest
extends GdUnitTestSuite

const DOC_PATH := "res://docs/MODULE_APIS.md"
## Start of the paragraph the floor block is described in.
const FLOOR_MARKER := "floor block (`floor_state_dict()`"


func test_the_contract_doc_names_every_field_of_the_floor_block() -> void:
	var section := _floor_section()
	(
		assert_str(section)
		. override_failure_message(
			"%s no longer has a paragraph starting `%s`" % [DOC_PATH, FLOOR_MARKER]
		)
		. is_not_empty()
	)
	var missing := PackedStringArray()
	for key: String in RunState.new().floor_state_dict().keys():
		if not section.contains(key):
			missing.append(key)
	(
		assert_array(missing)
		. override_failure_message(
			(
				"docs/MODULE_APIS.md does not name %s in the floor block; the save writes them"
				% ", ".join(missing)
			)
		)
		. is_empty()
	)


## The count that rotted twice is not allowed back: a number written by hand next to a list
## nobody re-counts is the shape of this bug, not an instance of it.
func test_the_floor_block_does_not_carry_a_hand_written_field_count() -> void:
	var section := _floor_section()
	var counts := PackedStringArray(
		[
			"eight fields",
			"nine fields",
			"ten fields",
			"eleven fields",
			"twelve fields",
			"thirteen fields",
			"fourteen fields",
			"fifteen fields",
			"sixteen fields",
		]
	)
	for phrase: String in counts:
		(
			assert_bool(section.contains(phrase))
			. override_failure_message(
				'the floor block says "%s" again; the count is what went stale twice' % phrase
			)
			. is_false()
		)


## The paragraph describing the floor block: from its marker to the end of that line.
func _floor_section() -> String:
	var text := FileAccess.get_file_as_string(DOC_PATH)
	assert_str(text).override_failure_message("%s is unreadable" % DOC_PATH).is_not_empty()
	var start := text.find(FLOOR_MARKER)
	if start < 0:
		return ""
	var end := text.find("\n", start)
	return text.substr(start, end - start) if end > start else text.substr(start)
