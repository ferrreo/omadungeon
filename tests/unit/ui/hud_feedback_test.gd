## What the HUD says out loud: the weapon skill, the potion key, and primary stats moving.
## Each of these was silent in a green suite, so every assertion here is about something a
## player can see on screen rather than about a function returning.
class_name HudFeedbackTest
extends GdUnitTestSuite

const HUD_SCENE := "res://src/ui/hud.tscn"
const PAUSE_SCENE := "res://src/ui/pause_menu.tscn"


func _hud() -> Hud:
	var hud: Hud = auto_free((load(HUD_SCENE) as PackedScene).instantiate())
	add_child(hud)
	return hud


func _bound() -> Array:
	var hud := _hud()
	var player := auto_free(UiFakes.make_player()) as UiFakes.FakePlayer
	add_child(player)
	hud.bind(player)
	return [hud, player]


## The weapon skill is a whole secondary attack on its own cooldown and appeared nowhere in
## the game: no slot, no wedge, no name. It now has a third HUD slot on the secondary action.
func test_the_weapon_skill_has_its_own_hud_slot_with_a_cooldown() -> void:
	var pair := _bound()
	var hud: Hud = pair[0]
	var player: UiFakes.FakePlayer = pair[1]
	var slot := hud.skill_slot()
	assert_object(slot.ability).is_same(player.weapon_controller.skill)
	assert_str(String(slot.action)).is_equal("secondary")
	slot.sample(0.0)
	assert_float(slot.cooldown_fraction()).is_greater(0.0)


func test_the_skill_slot_follows_a_weapon_swap() -> void:
	var pair := _bound()
	var hud: Hud = pair[0]
	var player: UiFakes.FakePlayer = pair[1]
	player.weapon_controller.skill = UiFakes.make_active("volley", "Cleave", 5.0)
	player.weapon_controller.weapon_changed.emit(null)
	assert_str(str(hud.skill_slot().ability.get("display_name"))).is_equal("Cleave")
	player.weapon_controller.skill = null
	player.weapon_controller.weapon_changed.emit(null)
	assert_object(hud.skill_slot().ability).is_null()


## The potion showed a count and no key, while the two ability slots right below it showed
## theirs. Nothing else in the game named the potion button.
func test_the_potion_slot_shows_its_key() -> void:
	var hud := _hud()
	var glyph := hud.get_node("%PotionGlyph") as GlyphIcon
	assert_object(glyph).is_not_null()
	assert_str(String(glyph.action)).is_equal("potion")
	assert_bool(InputMap.has_action(glyph.action)).is_true()


## A Config Gremlin stealing a point of Vitality used to be completely silent: no toast, no
## floater, and the HUD shows no primaries at all.
func test_a_stolen_stat_is_announced_and_floats_over_the_player() -> void:
	var pair := _bound()
	var hud: Hud = pair[0]
	var player: UiFakes.FakePlayer = pair[1]
	hud.prime_stats(true)
	var before := hud.active_damage_numbers()
	player.stats.add_primary(&"vitality", -1)
	EventBus.stat_changed.emit(&"vitality", player.stats.primary(&"vitality"))
	assert_str(hud.toast_widget().current_text()).contains("Vitality")
	assert_str(hud.toast_widget().current_text()).contains("-1")
	assert_str(hud.toast_widget().current_text()).contains("stolen")
	assert_int(hud.active_damage_numbers()).is_greater(before)


func test_a_stat_gain_is_announced_too() -> void:
	var pair := _bound()
	var hud: Hud = pair[0]
	var player: UiFakes.FakePlayer = pair[1]
	hud.prime_stats(true)
	player.stats.add_primary(&"might", 1)
	EventBus.stat_changed.emit(&"might", player.stats.primary(&"might"))
	assert_str(hud.toast_widget().current_text()).is_equal("+1 Might")


## The pause Build page listed only the totals, so a stolen point left no trace there either.
func test_the_pause_build_page_marks_what_changed_since_it_was_last_closed() -> void:
	var pause: PauseMenu = auto_free((load(PAUSE_SCENE) as PackedScene).instantiate())
	add_child(pause)
	var player := auto_free(UiFakes.make_player()) as UiFakes.FakePlayer
	add_child(player)
	pause.bind(player)
	await _reopen(pause)
	assert_str(_delta_text(pause, &"vitality")).is_empty()
	player.stats.add_primary(&"vitality", -1)
	player.stats.add_primary(&"might", 2)
	await _reopen(pause)
	assert_str(_delta_text(pause, &"vitality")).is_equal("-1")
	assert_str(_delta_text(pause, &"might")).is_equal("+2")
	assert_str(_delta_text(pause, &"fortune")).is_empty()
	await _reopen(pause)
	assert_str(_delta_text(pause, &"vitality")).is_empty()
	await get_tree().process_frame


## Opens the menu, reads it, closes it again, letting the rebuilt pages be collected: the
## pages are torn down with `queue_free`, which only runs at the end of a frame.
func _reopen(pause: PauseMenu) -> void:
	pause.open()
	await get_tree().process_frame
	pause.close()
	await get_tree().process_frame


func _delta_text(pause: PauseMenu, stat: StringName) -> String:
	var label := pause.find_child("Delta" + String(stat).capitalize(), true, false) as Label
	return label.text if label != null else "<missing>"


## `apply_class` and `restore_from_dict` re-emit every primary while a run is being set up.
## None of that is news, and six banners on the first frame of a run would be.
func test_stat_changes_are_silent_while_the_run_is_still_being_assembled() -> void:
	var pair := _bound()
	var hud: Hud = pair[0]
	var player: UiFakes.FakePlayer = pair[1]
	hud.prime_stats(false)
	player.stats.add_primary(&"might", 1)
	EventBus.stat_changed.emit(&"might", player.stats.primary(&"might"))
	assert_str(hud.toast_widget().current_text()).is_empty()


## Spending the run's single heal used to have exactly one piece of feedback: the HP bar
## moving. `Player.potion_used` carried the amount and had no listener anywhere in the game.
func test_drinking_the_potion_floats_the_amount_it_healed() -> void:
	var pair := _bound()
	var hud: Hud = pair[0]
	var player: UiFakes.FakePlayer = pair[1]
	var before := hud.active_damage_numbers()
	player.potion_used.emit(48.0)
	assert_int(hud.active_damage_numbers()).is_greater(before)


## A heal of nothing (a full-HP drink) must not pop a "+0 HP".
func test_a_potion_that_healed_nothing_floats_nothing() -> void:
	var pair := _bound()
	var hud: Hud = pair[0]
	var player: UiFakes.FakePlayer = pair[1]
	var before := hud.active_damage_numbers()
	player.potion_used.emit(0.0)
	assert_int(hud.active_damage_numbers()).is_equal(before)


## The HUD shows a potion icon, "x1" and the key, and nothing in the game ever said what the
## potion does or how many the run allows. The pause Build page now answers both.
func test_the_pause_build_page_says_what_the_potion_does() -> void:
	var pause: PauseMenu = auto_free((load(PAUSE_SCENE) as PackedScene).instantiate())
	add_child(pause)
	var player := auto_free(UiFakes.make_player()) as UiFakes.FakePlayer
	add_child(player)
	pause.bind(player)
	await _reopen(pause)
	var row := pause.find_child("PotionRow", true, false) as Label
	assert_object(row).is_not_null()
	assert_str(row.text).contains("%d%%" % int(roundf(Player.POTION_HEAL_FRACTION * 100.0)))
	assert_str(row.text).contains("%d/%d" % [player.potions, player.max_potions])
	await get_tree().process_frame
