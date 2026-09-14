## Every offer in the registry put on a real board, asking one question: can anything still
## reach the `"+N more"` tail?
##
## `OfferCard.tail_text` has two tails. An offer that displaces something says `COMPARE_TAIL` -
## "Pick to compare every row" - because the full table is one press away and a count of hidden
## rows is not a comparison, which was the owner's complaint. An offer that displaces *nothing*
## has no comparison block to point at, so it still counts: `"+%d more"`. That path was kept on
## the claim that no registry entry is long enough to reach it, and a claim about every item in
## the game is the kind that rots the next time somebody writes a description. This is the
## claim, executable.
##
## It goes through `ChestUi.show_offers`, and that is the method rather than a detail. Two
## earlier versions of this suite built cards by hand out of `OfferCard.make` and `fill_body`,
## and both produced confident nonsense. The first omitted the board context, which sends
## `describe_offer` down its documented no-lookup fallback - uncapped `ALL_ROWS` deltas *and* an
## empty `replaces`, the one combination that reaches the counting tail - and reported 372
## offenders. The second supplied the context but still sized each card alone against a bare
## host, and reported 96: every ring and trinket, "+4 more" on a Legendary. On the real board
## that same Legendary Gold Ring draws all five of its rows and no tail at all. A card's height
## is decided across the whole row of cards by `ChestUi._relayout`, so a card measured on its
## own is not the card the player sees, and a sweep that builds its own cards is only measuring
## its own arithmetic. Nothing here constructs a card.
class_name OfferCardRegistryTest
extends GdUnitTestSuite

const SCENE := "res://src/ui/chest_ui.tscn"
## Every rarity, because affix count is what makes a description long.
const RARITIES: Array[int] = [0, 1, 2, 3]
## Seeds for the affix roll, so the sweep sees more than one combination per base and rarity.
const AFFIX_SEEDS: Array[int] = [11, 404, 7717]
## Offers per board. Three is what a chest shows, and the card width the board picks depends on
## how many are up, so the sweep asks at the width the game asks at.
const PER_BOARD := 3


func _chest(player: UiFakes.FakePlayer) -> ChestUi:
	var chest: ChestUi = auto_free((load(SCENE) as PackedScene).instantiate())
	add_child(chest)
	chest.context = UiFakes.chest_context(player)
	return chest


## Every offer the game can put on a card: each item base at each rarity over several affix
## rolls, and every ability, which is where rings, curses and passives live.
func _every_offer() -> Array:
	var out: Array = []
	var items := ItemRegistry.load_default()
	var abilities := AbilityRegistry.load_default()
	var rng := RandomNumberGenerator.new()
	for base: ItemBase in items.bases:
		for rarity: int in RARITIES:
			for affix_seed: int in AFFIX_SEEDS:
				rng.seed = affix_seed
				var item := ItemGenerator.instance_of(base, rng, rarity as ItemInstance.Rarity)
				item.affixes = ItemGenerator.roll_affixes(items, base, rarity, rng)
				out.append(item)
	for ability: Ability in abilities.abilities:
		out.append(ability)
	return out


## The text of every Label under `node`, so the board is read the way a player reads it.
func _label_texts(node: Node, into: PackedStringArray) -> PackedStringArray:
	var label := node as Label
	if label != null:
		into.append(label.text)
	for child: Node in node.get_children():
		_label_texts(child, into)
	return into


func _counting_tails(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for text: String in _label_texts(node, PackedStringArray()):
		if text.begins_with("+") and text.ends_with(" more"):
			out.append(text)
	return out


func test_no_offer_in_the_registry_reaches_the_count_tail() -> void:
	# The fake player wears a weapon and armour and has empty ring and trinket slots, so the
	# sweep sees both a card that names what it displaces and a card that fills an empty slot -
	# and the empty slot is the case with no comparison to point at, which is the one that can
	# still count.
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	var chest := _chest(player)
	var offers := _every_offer()
	(
		assert_int(offers.size())
		. override_failure_message("the sweep found no offers at all; the registries are empty")
		. is_greater(20)
	)
	var context := UiFakes.chest_context(player)
	var offenders := PackedStringArray()
	var boards := 0
	for start in range(0, offers.size(), PER_BOARD):
		var batch: Array = offers.slice(start, mini(start + PER_BOARD, offers.size()))
		chest.show_offers(ChestUi.Kind.ITEM, batch, context)
		await get_tree().process_frame
		boards += 1
		for tail: String in _counting_tails(chest):
			offenders.append("board %d (from offer %d) -> %s" % [boards, start, tail])
	(
		assert_int(boards)
		. override_failure_message("no board was ever shown, so nothing was measured")
		. is_greater(10)
	)
	(
		assert_array(offenders)
		. override_failure_message(
			(
				(
					"%d card(s) fell back to counting hidden rows, which is the tail the owner "
					+ "rejected: %s. Either a description has outgrown the tallest card the 480x270 "
					+ "frame allows, or OfferCard should close its row gap and scroll the way "
					+ "CompareView does rather than count what it hid."
				)
				% [offenders.size(), ", ".join(offenders)]
			)
		)
		. is_empty()
	)


## The control, and this suite needs one more than most: its whole history is of measuring the
## wrong thing and believing the answer. A sweep that never sees a card overrun cannot tell
## "nothing reaches the tail" from "the scan cannot see a tail". So the scan is pointed at a
## card built to overrun on purpose and has to find it. This one does build a card by hand,
## because that is the only way to get a description longer than anything shippable; it proves
## the detector, not the board.
func test_the_scan_can_see_a_counting_tail_when_there_is_one() -> void:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	var chest := _chest(player)
	var info := chest.describe_offer(null)
	info["title"] = "A Very Long Name Indeed"
	info["replaces"] = ""
	var rows: Array[Dictionary] = []
	for i in range(40):
		rows.append(
			{"text": "row %d of a description nobody should have written" % i, "role": &"dim"}
		)
	info["rows"] = rows
	var one: Array[Dictionary] = [info]
	var head_h := CardFit.head_height_for(one, ChestUi.CARD_SIZE.x, ChestUi.MAX_CARD_HEIGHT)
	var card := OfferCard.make(info, &"loot", ChestUi.CARD_SIZE.x, ChestUi.CARD_SIZE.y, head_h)
	add_child(card)
	OfferCard.fill_body(card, head_h)
	var seen := _counting_tails(card)
	card.free()
	(
		assert_array(seen)
		. override_failure_message(
			(
				"a 40-row offer produced no counting tail, so the sweep above is not measuring "
				+ "what it claims to measure"
			)
		)
		. is_not_empty()
	)
