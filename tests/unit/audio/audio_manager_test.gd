## AudioManager headless: buses, pooled playback, per-id throttling and EventBus auto-play.
class_name AudioManagerTest
extends GdUnitTestSuite

var _audio: AudioManager


func before_test() -> void:
	_audio = auto_free(AudioManager.new())
	add_child(_audio)


func test_buses_exist_with_spectrum_analyzer() -> void:
	assert_int(AudioServer.get_bus_index(&"Music")).is_greater_equal(1)
	assert_int(AudioServer.get_bus_index(&"SFX")).is_greater_equal(1)
	assert_int(AudioServer.get_bus_index(&"UI")).is_greater_equal(1)
	assert_int(AudioManager.spectrum_effect_index()).is_greater_equal(0)
	var count := AudioServer.bus_count
	AudioManager.ensure_buses()
	assert_int(AudioServer.bus_count).is_equal(count)
	assert_int(AudioServer.get_bus_effect_count(AudioServer.get_bus_index(&"Music"))).is_equal(1)


func test_play_and_throttle() -> void:
	assert_bool(_audio.play(&"hit_melee")).is_true()
	(
		assert_bool(_audio.play(&"hit_melee"))
		. override_failure_message("second play within 40 ms")
		. is_false()
	)
	assert_bool(_audio.play(&"hurt", Vector2(100, 50))).is_true()
	assert_int(_audio.play_count).is_equal(2)
	OS.delay_msec(AudioManager.MIN_INTERVAL_MS + 10)
	assert_int(_audio.ms_since(&"hit_melee")).is_greater_equal(AudioManager.MIN_INTERVAL_MS)
	assert_bool(_audio.play(&"hit_melee")).is_true()


func test_unknown_id_returns_false() -> void:
	assert_bool(_audio.play(&"does_not_exist")).is_false()
	assert_bool(_audio.has_sound(&"does_not_exist")).is_false()
	assert_bool(_audio.has_sound(&"coin")).is_true()


func test_pool_handles_burst_without_errors() -> void:
	var played := 0
	for i in 40:
		if _audio.play(AudioManager.IDS[i % AudioManager.IDS.size()], Vector2(i * 10, 0), 0.2):
			played += 1
	assert_int(played).is_greater_equal(30)
	_audio.preload_all()
	_audio.stop_all()


func test_event_bus_hooks_play_sounds() -> void:
	var before := _audio.play_count
	EventBus.player_damaged.emit(3, null)
	EventBus.room_locked.emit(1)
	EventBus.room_cleared.emit(1)
	EventBus.gold_changed.emit(5)
	EventBus.gold_changed.emit(6)
	EventBus.player_dodged.emit(&"roll")
	EventBus.enemy_died.emit(null, null)
	EventBus.chest_opened.emit(null)
	EventBus.item_equipped.emit(null, &"weapon")
	EventBus.trap_triggered.emit(null)
	assert_int(_audio.play_count - before).is_equal(9)


func test_trap_hook_maps_kind_and_plays_at_position() -> void:
	assert_str(AudioManager.trap_sound_for(&"fire_vent")).is_equal("trap_fire")
	assert_str(AudioManager.trap_sound_for(&"laser_grid")).is_equal("laser")
	assert_str(AudioManager.trap_sound_for(&"pit")).is_equal("pit_fall")
	assert_str(AudioManager.trap_sound_for(&"spike_floor")).is_equal("trap_spike")
	assert_str(AudioManager.trap_sound_for(&"unknown_kind")).is_equal("trap_spike")
	for id: StringName in AudioManager.TRAP_SOUNDS.values():
		assert_bool(_audio.has_sound(id)).override_failure_message(String(id)).is_true()
	var trap: Node2D = auto_free(Node2D.new())
	add_child(trap)
	trap.global_position = Vector2(64, 32)
	var before := _audio.play_count
	EventBus.trap_triggered.emit(trap)
	assert_int(_audio.play_count - before).is_equal(1)
	assert_int(_audio.ms_since(&"trap_spike")).is_less(AudioManager.MIN_INTERVAL_MS)


func test_player_death_bypasses_throttle_and_is_pitched_down() -> void:
	assert_bool(_audio.play(&"death")).is_true()
	assert_bool(_audio.play(&"death")).is_false()
	var before := _audio.play_count
	EventBus.player_died.emit()
	assert_int(_audio.play_count - before).is_equal(1)
	var slow := 0
	for p: AudioStreamPlayer in _audio._players:
		if p.playing and p.pitch_scale < 0.7:
			slow += 1
	assert_int(slow).is_equal(1)


func test_level_up_only_after_floor_started() -> void:
	var before := _audio.play_count
	EventBus.run_started.emit(1)
	EventBus.ability_slot_changed.emit(0, Resource.new())
	assert_int(_audio.play_count - before).is_equal(0)
	EventBus.floor_started.emit(0)
	EventBus.ability_slot_changed.emit(0, null)
	assert_int(_audio.play_count - before).is_equal(0)
	EventBus.ability_slot_changed.emit(1, Resource.new())
	assert_int(_audio.play_count - before).is_equal(1)
	EventBus.run_started.emit(2)
	OS.delay_msec(AudioManager.MIN_INTERVAL_MS + 5)
	EventBus.ability_slot_changed.emit(1, Resource.new())
	assert_int(_audio.play_count - before).is_equal(1)


func test_positional_players_use_tuned_falloff() -> void:
	_audio.max_distance = 700.0
	_audio.attenuation = 0.8
	assert_bool(_audio.play(&"chest_open", Vector2(10, 10))).is_true()
	var seen := false
	for p: AudioStreamPlayer2D in _audio._players_2d:
		if p.playing:
			seen = true
			assert_float(p.max_distance).is_equal_approx(700.0, 0.01)
			assert_float(p.attenuation).is_equal_approx(0.8, 0.001)
	assert_bool(seen).is_true()


func test_volume_settings_apply_to_buses() -> void:
	var old: float = GameState.settings.get("sfx_volume", 1.0)
	GameState.settings["sfx_volume"] = 0.5
	EventBus.settings_changed.emit("sfx_volume")
	var idx := AudioServer.get_bus_index(&"SFX")
	assert_float(AudioServer.get_bus_volume_db(idx)).is_equal_approx(linear_to_db(0.5), 0.01)
	GameState.settings["sfx_volume"] = 0.0
	_audio.apply_settings()
	assert_bool(AudioServer.is_bus_mute(idx)).is_true()
	GameState.settings["sfx_volume"] = old
	_audio.apply_settings()
	assert_bool(AudioServer.is_bus_mute(idx)).is_false()


func test_ui_blips_route_through_the_sfx_bus() -> void:
	var ui := AudioServer.get_bus_index(&"UI")
	var sfx := AudioServer.get_bus_index(&"SFX")
	assert_int(ui).is_greater(sfx)
	(
		assert_str(String(AudioServer.get_bus_send(ui)))
		. override_failure_message("UI must feed SFX so the SFX slider covers menu blips")
		. is_equal("SFX")
	)
	assert_float(AudioServer.get_bus_volume_db(ui)).is_equal_approx(0.0, 0.01)
	assert_bool(AudioServer.is_bus_mute(ui)).is_false()
	assert_bool(_audio.play_ui(&"ui_move")).is_true()
	var on_ui := 0
	for p: AudioStreamPlayer in _audio._players:
		if p.playing and String(p.bus) == "UI":
			on_ui += 1
	assert_int(on_ui).is_equal(1)


func test_gold_chirps_only_when_the_total_rises() -> void:
	var before := _audio.play_count
	EventBus.run_started.emit(1)
	EventBus.gold_changed.emit(50)
	(
		assert_int(_audio.play_count - before)
		. override_failure_message("the starting purse broadcast must be silent")
		. is_equal(0)
	)
	OS.delay_msec(AudioManager.GOLD_INTERVAL_MS + 5)
	EventBus.gold_changed.emit(70)
	assert_int(_audio.play_count - before).is_equal(1)
	OS.delay_msec(AudioManager.GOLD_INTERVAL_MS + 5)
	EventBus.gold_changed.emit(20)
	(
		assert_int(_audio.play_count - before)
		. override_failure_message("spending gold must not play the pickup jingle")
		. is_equal(1)
	)
	OS.delay_msec(AudioManager.GOLD_INTERVAL_MS + 5)
	EventBus.gold_changed.emit(20)
	assert_int(_audio.play_count - before).is_equal(1)
	OS.delay_msec(AudioManager.GOLD_INTERVAL_MS + 5)
	EventBus.gold_changed.emit(21)
	assert_int(_audio.play_count - before).is_equal(2)
