## The two things the game never names.
##
## 1. The third HUD slot is a full secondary attack on its own cooldown, and nothing in the
##    game said so: the pause Abilities page listed two actives, two passives and an innate,
##    so the third box on the bar was an unexplained icon with a timer.
## 2. A class is its innate passive and its class-only active (GDD §4.3). The class card named
##    neither, so the first decision a new player makes was taken off a one-line blurb and six
##    stat bars.
class_name BuildIdentityTest
extends GdUnitTestSuite


func _player() -> UiFakes.FakePlayer:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	return player


func _pause() -> PauseMenu:
	var pause: PauseMenu = auto_free(
		(load("res://src/ui/pause_menu.tscn") as PackedScene).instantiate()
	)
	add_child(pause)
	return pause


func _select() -> ClassSelect:
	var select: ClassSelect = auto_free(
		(load("res://src/ui/class_select.tscn") as PackedScene).instantiate()
	)
	add_child(select)
	return select


## Every Label text under `node`, joined, so a test can assert on what a page says.
static func _labels(node: Node) -> String:
	var parts := PackedStringArray()
	for child: Node in node.get_children():
		if child is Label:
			parts.append((child as Label).text)
		parts.append(_labels(child))
	return " ".join(parts)


# ------------------------------------------------------------------ the third slot


func test_the_pause_page_names_the_weapon_skill_and_its_cooldown() -> void:
	var player := _player()
	var pause := _pause()
	pause.bind(player)
	var text := _labels(pause.loadout_screen())
	var skill := LoadoutModel.weapon_skill(player)
	assert_object(skill).is_not_null()
	(
		assert_str(text)
		. override_failure_message("the Build page still does not mention the weapon skill")
		. contains("Weapon skill")
	)
	assert_str(text).contains(skill.display_name)


## No weapon, no row: the page must not invent a skill the player does not have.
func test_a_player_without_a_weapon_gets_no_skill_row() -> void:
	var pause := _pause()
	pause.bind(null)
	assert_str(_labels(pause.loadout_screen())).not_contains("Weapon skill")


## The HUD says it out loud when the weapon changes, with the button that fires it, because
## the slot itself is an icon and a number.
func test_the_hud_announces_a_new_weapon_skill_by_name() -> void:
	var hud: Hud = auto_free((load("res://src/ui/hud.tscn") as PackedScene).instantiate())
	add_child(hud)
	var player := _player()
	hud.bind(player)
	hud.prime_stats(true)
	var skill := UiFakes.make_active("cleave", "Cleave", 6.0, 0.0)
	player.weapon_controller.skill = skill
	player.weapon_controller.weapon_changed.emit(null)
	assert_object(hud.skill_slot().ability).is_equal(skill)
	assert_str(hud.toast_widget().current_text()).contains("Cleave")
	assert_str(hud.toast_widget().current_text()).contains("Weapon skill")


## The banner names the button too, so "what fires this?" is answered in the same line.
func test_the_skill_banner_names_the_button() -> void:
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD)
	var skill := UiFakes.make_active("cleave", "Cleave", 6.0, 0.0)
	var banner := Hud.skill_banner(skill)
	assert_str(banner).contains("Cleave")
	assert_str(banner).contains(
		InputGlyphs.binding_name(Hud.SKILL_ACTION, InputGlyphs.Device.KEYBOARD)
	)


# ------------------------------------------------------------------ the class cards


## Every shipped class states both defining abilities on its card, by display name.
func test_every_class_card_states_its_innate_and_its_class_ability() -> void:
	var select := _select()
	for i in select.classes.size():
		var entry: Dictionary = select.classes[i]
		var card := select._cards[i]
		var traits := card.find_child("Traits", true, false)
		(
			assert_object(traits)
			. override_failure_message("%s has no innate/ability block" % entry["id"])
			. is_not_null()
		)
		var text := _labels(traits)
		assert_str(text).contains("Innate")
		assert_str(text).contains("Ability")
		for name: String in ClassSelect.trait_names(entry):
			(
				assert_str(text)
				. override_failure_message("%s card omits '%s'" % [entry["id"], name])
				. contains(name)
			)


## The names come from the ability registry, not from the id, so the card reads "Second Wind"
## rather than "second_wind" - and the four shipped classes all resolve.
func test_the_shipped_classes_resolve_real_ability_names() -> void:
	var expected: Dictionary = {
		&"fighter": ["Second Wind", "Bulwark"],
		&"ranger": ["Sure-Footed", "Volley"],
		&"wizard": ["Overflow", "Chain Lightning"],
		&"oligarch": ["Buyout", "Hostile Takeover"],
	}
	var select := _select()
	for entry: Dictionary in select.classes:
		var id: StringName = entry["id"]
		if not expected.has(id):
			continue
		var names := ClassSelect.trait_names(entry)
		assert_int(names.size()).is_equal(2)
		for name: String in names:
			assert_str(name).is_not_empty()
			(
				assert_bool(name.contains("_"))
				. override_failure_message("%s shows the raw id '%s'" % [id, name])
				. is_false()
			)


## An unknown id still produces something a human can read, so a card is never blank.
func test_an_unknown_ability_id_is_still_spelled_out() -> void:
	assert_str(ClassSelect.ability_name(&"frost_nova_ii")).is_equal("Frost Nova Ii")
	assert_str(ClassSelect.ability_name(&"")).is_empty()
