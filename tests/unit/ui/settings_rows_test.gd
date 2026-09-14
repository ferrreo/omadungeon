## The settings page as data (`SettingsRows`): every drawn key has a default, the panel draws
## a CHOICE row as one cycling button, and the aliases the panel keeps still point at the
## same lists - so a row added by another module lands on the page without touching the
## 1200-line panel.
class_name SettingsRowsTest
extends GdUnitTestSuite

const PANEL_SCENE := preload("res://src/ui/settings_panel.tscn")

var _saved: Dictionary


func before_test() -> void:
	_saved = GameState.settings.duplicate(true)


func after_test() -> void:
	GameState.settings = _saved
	SettingsPanel.apply_all(GameState.settings)


func test_every_drawn_key_has_a_default_and_a_control_kind() -> void:
	for row: Dictionary in SettingsRows.all_rows():
		var key := str(row["key"])
		(
			assert_bool(SettingsRows.DEFAULTS.has(key))
			. override_failure_message("row %s has no default" % key)
			. is_true()
		)
		var kind := int(row["type"])
		(
			assert_bool(
				(
					kind
					in [
						SettingsRows.RowType.BOOL,
						SettingsRows.RowType.SLIDER,
						SettingsRows.RowType.CHOICE
					]
				)
			)
			. is_true()
		)
		if kind == SettingsRows.RowType.CHOICE:
			assert_array(row.get("choices", [])).is_not_empty()
	assert_that(SettingsPanel.SECTIONS).is_same(SettingsRows.SECTIONS)
	assert_that(SettingsPanel.DEFAULTS).is_same(SettingsRows.DEFAULTS)
	assert_bool(SettingsRows.row_for("music_lights_amount").is_empty()).is_false()
	assert_bool(SettingsRows.row_for("no_such_key").is_empty()).is_true()


func test_a_choice_row_cycles_and_labels_its_values() -> void:
	var row := {
		"key": "lighting_quality",
		"label": "Lighting",
		"type": SettingsRows.RowType.CHOICE,
		"choices":
		[
			{"value": "off", "label": "Off"},
			{"value": "low", "label": "Low"},
			{"value": "high", "label": "High"},
		]
	}
	assert_str(SettingsRows.choice_label(row, "low")).is_equal("Low")
	assert_str(SettingsRows.choice_label(row, "weird")).is_equal("weird")
	assert_str(str(SettingsRows.next_choice(row, "off"))).is_equal("low")
	assert_str(str(SettingsRows.next_choice(row, "high"))).is_equal("off")
	assert_str(str(SettingsRows.next_choice(row, "weird"))).is_equal("off")


## A CHOICE row drawn by the panel is a button; pressing it steps the setting and the label.
func test_the_panel_draws_a_choice_row_as_a_cycling_button() -> void:
	var panel: SettingsPanel = auto_free(PANEL_SCENE.instantiate())
	add_child(panel)
	var row := {
		"key": "hold_to_toggle",
		"label": "Probe",
		"type": SettingsRows.RowType.CHOICE,
		"choices": [{"value": false, "label": "Never"}, {"value": true, "label": "Always"}]
	}
	GameState.settings["hold_to_toggle"] = false
	panel._add_row(row)
	var button := panel._controls["hold_to_toggle"] as Button
	assert_object(button).is_not_null()
	assert_str(button.text).is_equal("Never")
	button.pressed.emit()
	assert_bool(bool(GameState.settings["hold_to_toggle"])).is_true()
	# `_sync_control` finds no SECTIONS row for a probe key, so the label is what the press
	# wrote before it; a real row (in SECTIONS) is relabelled from the setting on every write.
	button.pressed.emit()
	assert_bool(bool(GameState.settings["hold_to_toggle"])).is_false()
