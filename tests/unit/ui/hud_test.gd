class_name HudTest
extends GdUnitTestSuite

const HUD_SCENE := "res://src/ui/hud.tscn"


class FakePlayer:
	extends Node2D
	var health: Health
	var stats: Stats = Stats.new()
	var gold: int = 12
	var potions: int = 2

	func _ready() -> void:
		health = Health.new()
		health.max_hp = 80.0
		add_child(health)


func _make_hud() -> Hud:
	var hud: Hud = auto_free((load(HUD_SCENE) as PackedScene).instantiate())
	add_child(hud)
	return hud


func test_hp_bar_follows_health_signal() -> void:
	var hud := _make_hud()
	var player: FakePlayer = auto_free(FakePlayer.new())
	add_child(player)
	hud.bind(player)
	var bar: HpBar = hud.get_node("%HpBar")
	assert_float(bar.hp).is_equal(80.0)
	assert_float(bar.max_hp).is_equal(80.0)
	var info := DamageInfo.create(60.0, [DamageInfo.TAG_TRUE], null, Layers.Team.ENEMY)
	player.health.take_damage(info)
	assert_float(bar.hp).is_equal(20.0)
	assert_bool(bar.is_danger()).is_true()
	assert_str((hud.get_node("%HpText") as Label).text).is_equal("20/80")


func test_toast_shows_bus_messages() -> void:
	var hud := _make_hud()
	EventBus.toast.emit("Hello dungeon", 0.5)
	await await_idle_frame()
	var toast := hud.toast_widget()
	assert_bool(toast.is_showing()).is_true()
	assert_str(toast.current_text()).is_equal("Hello dungeon")


func test_gold_counter_tweens_to_target() -> void:
	var hud := _make_hud()
	hud.set_gold(0, true)
	EventBus.gold_changed.emit(150)
	await await_millis(600)
	assert_int(hud.gold_displayed()).is_equal(150)


func test_damage_numbers_respect_setting() -> void:
	var hud := _make_hud()
	var was: bool = GameState.settings.get("damage_numbers", true)
	GameState.settings["damage_numbers"] = true
	EventBus.damage_number.emit(Vector2(100, 100), 12.0, true, Color.RED)
	assert_int(hud.active_damage_numbers()).is_equal(1)
	GameState.settings["damage_numbers"] = false
	EventBus.damage_number.emit(Vector2(100, 100), 12.0, false, Color.RED)
	assert_int(hud.active_damage_numbers()).is_equal(1)
	GameState.settings["damage_numbers"] = was


func test_minimap_and_floor_label() -> void:
	var hud := _make_hud()
	var rooms: Array[Dictionary] = [
		{"rect": Rect2i(0, 0, 6, 5), "cleared": true, "current": false, "type": 0},
		{"rect": Rect2i(10, 2, 8, 6), "cleared": false, "current": true, "type": 1},
	]
	var edges: Array[Vector4i] = [Vector4i(3, 2, 14, 5)]
	hud.set_minimap(rooms, edges)
	assert_int((hud.get_node("%Minimap") as Minimap).room_count()).is_equal(2)
	# Floor index 2 is a boss floor (docs §2), so the label carries the marker too.
	hud.set_floor(2, "Crypt")
	assert_str((hud.get_node("%FloorLabel") as Label).text).is_equal("Floor 3 - Crypt (Boss)")


func test_ability_slots_map_indices_to_actives_and_passives() -> void:
	var hud := _make_hud()
	var fire := UiFakes.make_active("fireball", "Fireball", 6.0)
	var nova := UiFakes.make_active("frost_nova", "Frost Nova", 9.0)
	var thorns := UiFakes.make_passive("thorns", "Thorns", "Reflect damage.")
	hud.set_abilities([fire, nova], [thorns])
	assert_object((hud.get_node("%Slot1") as AbilitySlot).ability).is_same(fire)
	assert_object((hud.get_node("%Slot2") as AbilitySlot).ability).is_same(nova)
	assert_int((hud.get_node("%Passives") as HBoxContainer).get_child_count()).is_equal(1)
	var vamp := UiFakes.make_passive("vampiric", "Vampiric", "Lifesteal.")
	EventBus.ability_slot_changed.emit(3, vamp)
	assert_int((hud.get_node("%Passives") as HBoxContainer).get_child_count()).is_equal(2)
	var swap := UiFakes.make_active("shadowstep", "Shadowstep", 7.0)
	EventBus.ability_slot_changed.emit(0, swap)
	assert_object((hud.get_node("%Slot1") as AbilitySlot).ability).is_same(swap)


func test_set_abilities_accepts_typed_player_arrays() -> void:
	var hud := _make_hud()
	var actives: Array[ActiveAbility] = [UiFakes.make_active("fireball", "Fireball", 6.0)]
	var passives: Array[PassiveAbility] = [UiFakes.make_passive("thorns", "Thorns", "Reflect.")]
	hud.set_abilities(actives, passives)
	assert_object((hud.get_node("%Slot1") as AbilitySlot).ability).is_same(actives[0])


func test_floor_label_capitalises_the_biome_id() -> void:
	var hud := _make_hud()
	hud.set_floor(1, "crypt")
	assert_str((hud.get_node("%FloorLabel") as Label).text).is_equal("Floor 2 - Crypt")


func test_gold_bursts_do_not_stack_tweens() -> void:
	var hud := _make_hud()
	hud.set_gold(0, true)
	EventBus.gold_changed.emit(10)
	EventBus.gold_changed.emit(25)
	EventBus.gold_changed.emit(60)
	await await_millis(600)
	assert_int(hud.gold_displayed()).is_equal(60)


func test_interact_prompt_stays_centred_however_long_the_text_is() -> void:
	var hud := _make_hud()
	var root: Control = hud.get_node("%Root")
	root.size = Vector2(480, 270)
	var prompt: PanelContainer = hud.get_node("%Prompt")
	var centres: Array[float] = []
	for text: String in ["Open", "Open chest", "Buy Legendary Copper Ring of Tiling (240g)"]:
		hud.show_prompt(text, true)
		await get_tree().process_frame
		(
			assert_float(prompt.size.x)
			. override_failure_message(
				(
					"prompt '%s' is %f wide but needs %f"
					% [text, prompt.size.x, prompt.get_combined_minimum_size().x]
				)
			)
			. is_greater_equal(prompt.get_combined_minimum_size().x)
		)
		centres.append(prompt.position.x + prompt.size.x * 0.5)
	for centre: float in centres:
		assert_float(centre).is_between(238.0, 242.0)


## The finding this guards: HUD text was guarded against the dungeon *floor* only, at 3:1,
## while the HUD floats over walls and props too - on the `white` fixture the HP readout
## measured 1.87:1 where it crossed a wall band, which is exactly where the eye is when the
## HP is dropping. The fix is structural: the resource block and the floor/seed block sit on
## an opaque `void` plate, so the surface behind the text is a palette role the guard can
## actually reach, and every label on it clears 4.5:1 (docs 3.2) on every shipped fixture.
func test_hud_text_clears_45_on_its_plate_in_every_theme() -> void:
	var hud := _make_hud()
	for theme: String in [
		"tokyo-night", "gruvbox", "catppuccin", "nord", "catppuccin-latte", "white"
	]:
		var toml := ColorsToml.load_file(
			"res://tests/fixtures/omarchy/%s/state/current/theme/colors.toml" % theme
		)
		var palette := ThemePalette.from_colors_toml(toml, theme)
		UiTheme.rebuild(palette)
		# Controls pick up a mutated Theme on the next frame's theme-changed notification,
		# so a colour read in the same call still reports the previous palette.
		await get_tree().process_frame
		for plate_name: String in ["TopLeftPlate", "TopRightPlate"]:
			var plate := hud.get_node("%%Root/%s" % plate_name) as PanelContainer
			(
				assert_object(plate)
				. override_failure_message("%s is missing" % plate_name)
				. is_not_null()
			)
			var style := plate.get_theme_stylebox(&"panel") as StyleBoxFlat
			(
				assert_float(style.bg_color.a)
				. override_failure_message(
					(
						"%s is translucent, so the guard cannot know what is behind the text"
						% plate_name
					)
				)
				. is_equal_approx(1.0, 0.001)
			)
			for label: Label in _labels_under(plate):
				var ratio := ThemePalette.contrast_ratio(
					label.get_theme_color(&"font_color"), style.bg_color
				)
				(
					assert_float(ratio)
					. override_failure_message(
						"%s: '%s' reads %.2f:1 on the HUD plate" % [theme, label.text, ratio]
					)
					. is_greater_equal(ThemePalette.MIN_CONTRAST - 0.01)
				)
	UiTheme.rebuild(Desktop.palette)


static func _labels_under(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child: Node in node.get_children():
		if child is Label:
			out.append(child as Label)
		out.append_array(_labels_under(child))
	return out


## Boss floors were invisible: `GenParams.is_boss_floor` drove generation and nothing on
## screen said a boss was down there. The HUD label and the arrival banner share one string.
func test_the_floor_label_marks_a_boss_floor() -> void:
	var hud := _make_hud()
	var label: Label = hud.get_node("%FloorLabel")
	hud.set_floor(0, "crypt")
	assert_str(label.text).is_equal("Floor 1 - Crypt")
	hud.set_floor(2, "crypt")
	assert_str(label.text).is_equal("Floor 3 - Crypt (Boss)")
	hud.set_floor(5, "forge")
	assert_str(label.text).contains(Hud.BOSS_SUFFIX)
	hud.set_floor(8, "void")
	assert_str(label.text).contains(Hud.BOSS_SUFFIX)
	hud.set_floor(7, "void")
	assert_str(label.text).not_contains(Hud.BOSS_SUFFIX)


## docs §2 puts the bosses on floors 3, 6 and 9. Three modules hold that list (the generator,
## the run lifecycle and now the HUD); if they ever disagree the player is warned about the
## wrong floor, which is worse than not being warned at all.
func test_every_module_agrees_on_which_floors_hold_a_boss() -> void:
	for index in range(RunManager.FLOOR_COUNT):
		var by_gen := GenParams.is_boss_floor_index(index)
		(
			assert_bool(Hud.is_boss_floor(index))
			. override_failure_message("floor %d: HUD disagrees with GenParams" % (index + 1))
			. is_equal(by_gen)
		)
		(
			assert_bool(RunManager.is_boss_floor(index))
			. override_failure_message(
				"floor %d: RunManager disagrees with GenParams" % (index + 1)
			)
			. is_equal(by_gen)
		)
	assert_array(RunManager.BOSS_FLOORS).contains_exactly([2, 5, 8])


## The banner the player sees on arrival is the label they keep seeing all floor.
func test_the_arrival_banner_and_the_hud_label_say_the_same_thing() -> void:
	assert_str(Hud.floor_text(2, "crypt")).is_equal("Floor 3 - Crypt (Boss)")
	assert_str(Hud.floor_text(1, "")).is_equal("Floor 2")


## The owner's report: the seed was a permanent fixture of the top-right plate, a number no
## player can act on, sitting in the corner of every screenshot. It is recorded, not drawn.
func test_the_hud_never_shows_the_run_seed() -> void:
	var hud := _make_hud()
	hud.set_seed(20240911)
	assert_int(hud.run_seed).is_equal(20240911)
	assert_object(hud.get_node_or_null("%SeedLabel")).is_null()
	for label: Label in _labels_under(hud.get_node("%Root")):
		(
			assert_str(label.text.to_lower())
			. override_failure_message("the HUD still prints '%s'" % label.text)
			. not_contains("seed")
		)
	for label: Label in _labels_under(hud.get_node("%Root")):
		assert_str(label.text).not_contains("20240911")


## The boss marker used to be "[BOSS]", which is how a log line marks a level.
func test_the_boss_marker_is_not_a_debug_tag() -> void:
	assert_str(Hud.BOSS_SUFFIX).not_contains("[")
	assert_str(Hud.BOSS_SUFFIX).not_contains("]")
	assert_str(Hud.floor_text(2, "crypt")).contains("Boss")


# ------------- the arrival banner never names a floor the player has left (round 3)


## A banner is a sentence frozen when it was pushed, and the gameplay lane holds a backlog: a
## capture of floor 8 carried "FLOOR 5 - LIBRARY" across the middle of the screen because
## nothing pulled the old arrival banner down. Arriving somewhere dismisses the last arrival.
func test_arriving_on_a_floor_drops_the_banner_of_the_floor_before_it() -> void:
	var hud := _make_hud()
	var toast := hud.toast_widget()
	hud.announce_floor(4, "library")
	await await_idle_frame()
	assert_str(toast.current_text()).is_equal(Hud.floor_text(4, "library"))
	hud.announce_floor(7, "void")
	await await_idle_frame()
	(
		assert_str(toast.current_text())
		. override_failure_message("the banner still names the floor the player has left")
		. is_not_equal(Hud.floor_text(4, "library"))
	)
	# The old banner fades out and the new one takes the lane; the old one never comes back.
	await await_millis(400)
	assert_str(toast.current_text()).is_equal(Hud.floor_text(7, "void"))
	assert_int(toast.queued_count()).is_equal(0)


## The cause follows the effect: the line saying what the music made of the floor ("Built
## to Super Space - dense, fast and bright") is queued right behind the arrival banner, and a
## new floor pulls the old floor's line down the same way it pulls the old arrival.
func test_the_music_line_follows_the_arrival_banner_and_leaves_with_the_floor() -> void:
	var hud := _make_hud()
	var toast := hud.toast_widget()
	hud.announce_floor(4, "library")
	hud.announce_music("Built to Super Space - dense, fast and bright")
	await await_idle_frame()
	assert_str(toast.current_text()).is_equal(Hud.floor_text(4, "library"))
	assert_int(toast.queued_count()).is_equal(1)
	hud.announce_floor(7, "void")
	hud.announce_music("Built in silence - a steady floor")
	await await_idle_frame()
	# The two lines of floor 7 wait behind the fading floor-4 arrival; the floor-4 music line
	# is gone from the queue, or this would be three.
	assert_int(toast.queued_count()).is_equal(2)
	await await_millis(400)
	assert_str(toast.current_text()).is_equal(Hud.floor_text(7, "void"))
	toast.dismiss(Hud.floor_text(7, "void"))
	await await_millis(400)
	assert_str(toast.current_text()).is_equal("Built in silence - a steady floor")
	assert_int(toast.queued_count()).is_equal(0)
	# An empty line (a floor the log never saw) queues nothing.
	hud.announce_music("")
	assert_int(toast.queued_count()).is_equal(0)


## ...including while it is still waiting its turn behind another message, which is how the
## queue produced the contradiction in the first place.
func test_a_queued_arrival_banner_is_dropped_when_the_next_floor_starts() -> void:
	var hud := _make_hud()
	var toast := hud.toast_widget()
	hud.toast("Equipped Rusty Sword", 4.0)
	hud.announce_floor(4, "library")
	await await_idle_frame()
	assert_int(toast.queued_count()).is_equal(1)
	hud.announce_floor(7, "void")
	await await_idle_frame()
	assert_int(toast.queued_count()).is_equal(1)
	assert_str(toast.current_text()).is_equal("Equipped Rusty Sword")
	# The one message still queued is the new floor, not the old one.
	toast.dismiss("Equipped Rusty Sword")
	await await_millis(400)
	assert_str(toast.current_text()).is_equal(Hud.floor_text(7, "void"))
