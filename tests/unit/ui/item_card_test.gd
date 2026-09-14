## The item card's content model. These assert what a player can read off a card, because the
## bug they cover was invisible to a green suite: every function returned, and the one number
## that decides an item chest - how hard a weapon hits - was never in the output at all.
class_name ItemCardTest
extends GdUnitTestSuite


func _weapon(damage: float, rate: float, reach: float) -> ItemInstance:
	var base := WeaponBase.new()
	base.id = &"test_sword"
	base.display_name = "Test Sword"
	base.base_damage = damage
	base.attacks_per_second = rate
	base.range_px = reach
	var item := ItemInstance.new()
	item.base = base
	item.display_name = "Test Sword"
	return item


func _ring(implicit: Dictionary) -> ItemInstance:
	var base := ItemBase.new()
	base.id = &"test_ring"
	base.display_name = "Test Ring"
	base.slot = ItemBase.Slot.RING
	base.implicit_flat = implicit
	var item := ItemInstance.new()
	item.base = base
	item.display_name = "Test Ring"
	return item


func test_a_weapon_card_states_damage_rate_dps_and_reach() -> void:
	var lines := ItemCard.item_lines(_weapon(8.0, 2.0, 20.0))
	assert_int(lines.size()).is_greater_equal(2)
	assert_str(lines[0]).is_equal("8 damage  2/s")
	assert_str(lines[1]).is_equal("16 dps  20 range")


func test_fractional_rates_keep_their_decimal() -> void:
	var lines := ItemCard.item_lines(_weapon(9.0, 1.75, 22.0))
	assert_str(lines[0]).is_equal("9 damage  1.8/s")
	assert_str(lines[1]).is_equal("15.8 dps  22 range")


func test_only_weapons_get_a_weapon_block() -> void:
	assert_array(ItemCard.weapon_lines(null)).is_empty()
	var lines := ItemCard.item_lines(_ring({&"might": 2}))
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).is_equal("+2 Might")


## data/items/whetstone.tres carries `damage_physical: 0.05`; printed as an int that is "+0".
func test_a_fractional_implicit_never_renders_as_zero() -> void:
	var lines := ItemCard.item_lines(_ring({&"damage_physical": 0.05}))
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).is_equal("+5% Physical Damage")
	assert_str(lines[0]).not_contains("+0 ")


## "+2 Might" printed twice reads as a rendering bug; it is +4.
func test_two_sources_of_the_same_stat_are_one_row() -> void:
	var item := _ring({&"might": 2})
	var affix := UiFakes.make_affix("sharp", &"might", Affix.Mode.FLAT, 1, 3)
	item.affixes.append({"affix": affix, "value": 2.0})
	var lines := ItemCard.item_lines(item)
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).is_equal("+4 Might")


func test_a_flat_and_a_percent_of_one_stat_stay_two_rows() -> void:
	var item := _ring({&"might": 2})
	item.base.implicit_percent = {&"might": 0.1}
	var lines := ItemCard.item_lines(item)
	assert_int(lines.size()).is_equal(2)
	assert_str(lines[0]).is_equal("+2 Might")
	assert_str(lines[1]).is_equal("+10% Might")


func test_on_hit_affixes_keep_their_own_wording() -> void:
	var item := _ring({})
	var affix := UiFakes.make_affix("burning", &"might", Affix.Mode.ON_HIT_STATUS, 0.1, 0.2)
	item.affixes.append({"affix": affix, "value": 0.15})
	var lines := ItemCard.item_lines(item)
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).contains("on hit")


func test_weapon_deltas_are_signed_and_cover_every_number() -> void:
	var rows := ItemCard.weapon_delta_rows(
		_weapon(12.0, 1.8, 24.0).base as WeaponBase, _weapon(8.0, 2.0, 20.0).base as WeaponBase
	)
	assert_int(rows.size()).is_equal(2)
	assert_str(str(rows[0]["text"])).is_equal("+4 dmg  -0.2/s")
	assert_str(str(rows[1]["text"])).is_equal("+5.6 dps  +4 range")
	assert_that(rows[1]["role"]).is_equal(&"heal")


func test_a_worse_weapon_reads_as_a_loss() -> void:
	var rows := ItemCard.weapon_delta_rows(
		_weapon(6.0, 2.0, 20.0).base as WeaponBase, _weapon(8.0, 2.0, 20.0).base as WeaponBase
	)
	# The rate and the reach did not change, so only the numbers that moved are printed.
	assert_int(rows.size()).is_equal(2)
	assert_str(str(rows[0]["text"])).is_equal("-2 dmg")
	assert_str(str(rows[1]["text"])).is_equal("-4 dps")
	assert_that(rows[1]["role"]).is_equal(&"danger")


func test_identical_weapons_have_nothing_to_say() -> void:
	var rows := ItemCard.weapon_delta_rows(
		_weapon(8.0, 2.0, 20.0).base as WeaponBase, _weapon(8.0, 2.0, 20.0).base as WeaponBase
	)
	assert_array(rows).is_empty()


func test_a_ring_compared_to_a_ring_has_no_weapon_rows() -> void:
	var rows := ItemCard.compare_rows(_ring({&"might": 1}), _ring({&"might": 2}), {&"might": -1.0})
	assert_int(rows.size()).is_equal(1)
	assert_str(str(rows[0]["text"])).is_equal("-1 Might")


func test_weapon_rows_come_first_and_survive_the_stat_cap() -> void:
	var deltas := {&"might": 2.0, &"vitality": 1.0, &"precision": 1.0, &"arcana": 1.0, &"luck": 0.5}
	var rows := ItemCard.compare_rows(_weapon(12.0, 2.0, 20.0), _weapon(8.0, 2.0, 20.0), deltas, 2)
	assert_str(str(rows[0]["text"])).is_equal("+4 dmg")
	assert_str(str(rows[1]["text"])).is_equal("+8 dps")
	# Two stat rows kept, three hidden - and the card is told how many so it can say so.
	assert_int(rows.size()).is_equal(4)
	assert_int(ItemCard.hidden_stat_rows(deltas, 2)).is_equal(3)


func test_stat_delta_units_come_from_the_stat_not_the_magnitude() -> void:
	var rows := ItemCard.stat_delta_rows({&"armor": -0.6, &"crit_mult": 1.0, &"crit_chance": 0.05})
	assert_int(rows.size()).is_equal(3)
	assert_str(str(rows[0]["text"])).is_equal("-1 Armor")
	assert_str(str(rows[1]["text"])).is_equal("+5% Crit Chance")
	assert_str(str(rows[2]["text"])).is_equal("+100% Crit Mult")


func test_deltas_that_would_render_as_zero_are_dropped() -> void:
	var rows := ItemCard.stat_delta_rows({&"might": 2.0, &"move_speed": 0.001, &"armor": 0.0})
	assert_int(rows.size()).is_equal(1)
	assert_str(str(rows[0]["text"])).is_equal("+2 Might")


# ------------------------------------------------ the before/after block (owner report 6)


## A delta is the answer to a subtraction the player has to do against a number the card never
## showed. Every comparison row now carries both sides of it.
func test_a_swap_row_carries_the_number_now_and_the_number_after() -> void:
	var rows := ItemCard.swap_rows(_weapon(8.0, 2.0, 20.0), _weapon(12.0, 1.8, 24.0))
	assert_int(rows.size()).is_equal(4)
	assert_str(ItemCard.swap_text(rows[0])).is_equal("Damage 12 -> 8")
	assert_str(ItemCard.swap_text(rows[1])).is_equal("Rate 1.8 -> 2")
	assert_str(ItemCard.swap_text(rows[2])).is_equal("Dps 21.6 -> 16")
	assert_str(ItemCard.swap_text(rows[3])).is_equal("Range 24 -> 20")
	assert_that(rows[0]["role"]).is_equal(&"danger")
	assert_that(rows[1]["role"]).is_equal(&"heal")


func test_a_number_that_does_not_move_is_not_a_row() -> void:
	var rows := ItemCard.swap_rows(_weapon(8.0, 2.0, 20.0), _weapon(6.0, 2.0, 20.0))
	assert_int(rows.size()).is_equal(2)
	assert_str(ItemCard.swap_text(rows[0])).is_equal("Damage 6 -> 8")
	assert_str(ItemCard.swap_text(rows[1])).is_equal("Dps 12 -> 16")


## Both sides of a stat row are the item's own contribution, so "what I lose" is as visible as
## "what I gain" - including a stat only the worn item had, which a delta list renders as a
## bare negative with no clue where it came from.
func test_a_stat_only_the_worn_item_has_still_gets_a_row() -> void:
	var rows := ItemCard.swap_rows(_ring({&"might": 4}), _ring({&"might": 2, &"armor": 3}))
	assert_int(rows.size()).is_equal(2)
	assert_str(ItemCard.swap_text(rows[0])).is_equal("Might +2 -> +4")
	assert_str(ItemCard.swap_text(rows[1])).is_equal("Armor +3 -> none")
	assert_that(rows[1]["role"]).is_equal(&"danger")


func test_an_empty_side_reads_as_none_rather_than_plus_zero() -> void:
	var rows := ItemCard.swap_rows(_ring({&"might": 2}), _ring({}))
	assert_int(rows.size()).is_equal(1)
	assert_str(ItemCard.swap_text(rows[0])).is_equal("Might none -> +2")


## A fraction stat reads as a percentage on both sides, and its label is the one a player uses
## rather than the code identifier ("Crit Mult").
func test_swap_labels_are_player_words_and_units_follow_the_stat() -> void:
	var offered := _ring({})
	offered.base.implicit_percent = {&"crit_mult": 0.5}
	var worn := _ring({})
	worn.base.implicit_percent = {&"crit_mult": 0.2}
	var rows := ItemCard.swap_rows(offered, worn)
	assert_str(ItemCard.swap_text(rows[0])).is_equal("Crit dmg +20% -> +50%")
	assert_str(ItemCard.swap_label(&"crit_mult")).is_equal("Crit dmg")
	assert_str(ItemCard.swap_label(&"crit_chance")).is_equal("Crit")
	# A stat with no short name of its own still gets the generated label, never a raw key.
	assert_str(ItemCard.swap_label(&"might")).is_equal("Might")


func test_swap_rows_can_be_capped_and_say_how_many_were_cut() -> void:
	var offered := _ring({&"might": 4, &"vitality": 3, &"armor": 2, &"max_hp": 10})
	var worn := _ring({})
	assert_int(ItemCard.swap_rows(offered, worn, 2).size()).is_equal(2)
	assert_int(ItemCard.hidden_swap_rows(offered, worn, 2)).is_equal(2)
	assert_int(ItemCard.hidden_swap_rows(offered, worn, 6)).is_equal(0)


## The block used to be headed "vs equipped", which names nothing: the player had to remember
## what they were wearing to read it.
func test_the_comparison_heading_names_the_gear_that_comes_off() -> void:
	var worn := _ring({&"might": 1})
	worn.display_name = "Vital Copper Ring of Warding"
	assert_str(ItemCard.worn_name(worn)).is_equal("Test Ring")
	assert_str(ItemCard.compare_header(ItemCard.worn_name(worn))).is_equal("Replaces Test Ring")
	# Only when the board could not say what it is: the old caption is the fallback.
	assert_str(ItemCard.compare_header("")).is_equal(ItemCard.COMPARE_HEADER)


## "Unique: Tiling Wm" is an internal id with a capital letter on it.
func test_an_unregistered_unique_effect_never_prints_its_id() -> void:
	var item := _ring({})
	item.unique_effect = &"tiling_wm"
	var lines := ItemCard.item_lines(item)
	assert_array(lines).contains([ItemCard.UNKNOWN_UNIQUE])
	for line: String in lines:
		assert_str(line.to_lower()).not_contains("tiling_wm")
		assert_str(line.to_lower()).not_contains("tiling wm")


## "rng" is the random number generator everywhere else in a rogue-like.
func test_the_reach_row_does_not_call_itself_rng() -> void:
	for line: String in ItemCard.item_lines(_weapon(8.0, 2.0, 20.0)):
		assert_str(line).not_contains("rng")
