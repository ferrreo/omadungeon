class_name WidgetsTest
extends GdUnitTestSuite


func test_input_glyphs_cells_per_device() -> void:
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD)
	assert_int(InputGlyphs.cell_for(&"interact")).is_equal(InputGlyphs.Cell.KEYCAP)
	assert_str(InputGlyphs.label_for(&"interact")).is_equal("F")
	assert_int(InputGlyphs.cell_for(&"attack")).is_equal(InputGlyphs.Cell.MOUSE_LEFT)
	InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
	assert_int(InputGlyphs.cell_for(&"interact")).is_equal(InputGlyphs.Cell.X)
	assert_int(InputGlyphs.cell_for(&"active_1")).is_equal(InputGlyphs.Cell.LB)
	assert_int(InputGlyphs.cell_for(&"attack")).is_equal(InputGlyphs.Cell.RT)
	assert_str(InputGlyphs.label_for(&"interact")).is_equal("")
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD)


func test_observe_emits_device_change() -> void:
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD)
	var monitor := monitor_signals(EventBus, false)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	InputGlyphs.observe(button)
	await assert_signal(monitor).is_emitted("input_device_changed", [1])
	assert_int(InputGlyphs.current_device()).is_equal(InputGlyphs.Device.GAMEPAD)
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD)


func test_run_summary_shows_data() -> void:
	var summary: RunSummary = auto_free(
		(load("res://src/ui/run_summary.tscn") as PackedScene).instantiate()
	)
	add_child(summary)
	summary.show_summary(UiFakes.summary_data(true))
	assert_str(summary.headline_text()).is_equal("VICTORY")
	assert_str(RunSummary.format_time(1463.0)).is_equal("24:23")
	assert_str(RunSummary.format_time(3661.0)).is_equal("1:01:01")


func test_stats_screen_rows() -> void:
	var stats: StatsScreen = auto_free(
		(load("res://src/ui/stats_screen.tscn") as PackedScene).instantiate()
	)
	add_child(stats)
	stats.show_stats(UiFakes.profile_stats())
	assert_int(stats.row_count()).is_equal(4 + 4 + 3)


func test_credits_build_without_sources() -> void:
	var text := Credits.build_bbcode()
	assert_str(text).contains("OMADUNGEON")
	var credits: Credits = auto_free(
		(load("res://src/ui/credits.tscn") as PackedScene).instantiate()
	)
	add_child(credits)
	assert_str(credits.text_content()).contains("OMADUNGEON")


func test_damage_number_pops_and_finishes() -> void:
	var number: DamageNumber = auto_free(DamageNumber.new())
	add_child(number)
	number.pop(Vector2(10, 10), 12.0, true, Color.WHITE)
	assert_bool(number.visible).is_true()
	await await_millis(900)
	assert_bool(number.visible).is_false()


func test_toast_queue_is_capped_and_deduplicated() -> void:
	var toast: Toast = auto_free(Toast.new())
	toast.listen_to_bus = false
	toast.size = Vector2(200, 20)
	add_child(toast)
	toast.push("first", 5.0)
	assert_bool(toast.is_showing()).is_true()
	toast.push("second", 5.0)
	toast.push("second", 5.0)
	assert_int(toast.queued_count()).is_equal(1)
	toast.push("third", 5.0)
	toast.push("fourth", 5.0)
	toast.push("fifth", 5.0)
	assert_int(toast.queued_count()).is_equal(Toast.MAX_QUEUED)


func test_ability_slot_samples_cooldown_outside_draw() -> void:
	var slot: AbilitySlot = auto_free(AbilitySlot.new())
	add_child(slot)
	var ability := UiFakes.make_active("fireball", "Fireball", 10.0, 10.0)
	slot.set_ability(ability)
	slot.sample(0.0)
	assert_float(slot.cooldown_fraction()).is_equal_approx(1.0, 0.01)
	ability.cooldown_left = 5.0
	slot.sample(0.016)
	assert_float(slot.cooldown_fraction()).is_equal_approx(0.5, 0.01)
	ability.cooldown_left = 0.0
	slot.sample(0.016)
	assert_float(slot.cooldown_fraction()).is_equal(0.0)
	assert_float(slot.ready_flash()).is_greater(0.9)
