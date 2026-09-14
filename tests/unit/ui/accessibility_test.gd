## The colour-free channel: rarity pips/shapes, status tags, room shapes, danger hatching,
## and the reduce-motion / reduced-flash policy every widget routes its animation through.
class_name AccessibilityTest
extends GdUnitTestSuite

var _saved: Dictionary


func before_test() -> void:
	_saved = GameState.settings.duplicate(true)


func after_test() -> void:
	GameState.settings = _saved


func _glyphs(on: bool) -> void:
	GameState.settings[Accessibility.SETTING_GLYPHS] = on


func _player() -> UiFakes.FakePlayer:
	var player: UiFakes.FakePlayer = auto_free(UiFakes.make_player())
	add_child(player)
	return player


# ------------------------------------------------------------------ policy


## `test_a_badge_reserves_room_for_its_shape` below bounds the badge's minimum size with
## `ShapeBadge.SIZE` itself, so shrinking the constant shrinks the bound with it: at SIZE = 1
## the colourblind shape is a dot nobody can tell from another dot, and that test still passes.
## This is the literal. Eight pixels is the size the shapes were drawn at and the smallest at
## which a square, a triangle and a diamond are distinguishable at the scale the HUD renders -
## which is the entire job of the badge, since it is what a player who cannot use the colour
## has instead of the colour.
func test_the_badge_size_is_a_number_not_a_tautology() -> void:
	(
		assert_int(ShapeBadge.SIZE)
		. override_failure_message(
			(
				(
					"ShapeBadge.SIZE is %d; the badge tests measure against this same constant, so "
					+ "shrinking it hides the colourblind shapes without failing anything"
				)
				% ShapeBadge.SIZE
			)
		)
		. is_greater_equal(8)
	)


func test_motion_and_flash_scale_with_the_settings() -> void:
	GameState.settings["reduce_motion"] = false
	GameState.settings["reduced_flash"] = false
	assert_float(Accessibility.motion(0.4)).is_equal_approx(0.4, 0.001)
	assert_float(Accessibility.flash(1.0)).is_equal_approx(1.0, 0.001)
	assert_bool(Accessibility.animates()).is_true()
	GameState.settings["reduced_flash"] = true
	# Reduced flash keeps a trace so the event is still visible, without strobing.
	assert_float(Accessibility.flash(1.0)).is_equal_approx(0.1, 0.001)
	assert_float(Accessibility.motion(0.4)).is_equal_approx(0.4, 0.001)
	GameState.settings["reduce_motion"] = true
	assert_float(Accessibility.motion(0.4)).is_equal_approx(0.0, 0.001)
	assert_float(Accessibility.flash(1.0)).is_equal_approx(0.0, 0.001)
	assert_bool(Accessibility.animates()).is_false()


func test_every_rarity_and_status_has_its_own_mark_and_shape() -> void:
	var marks: Array[String] = []
	var shapes: Array[int] = []
	for rarity in ItemInstance.RARITY_NAMES.size():
		marks.append(Accessibility.rarity_mark_always(rarity))
		shapes.append(Accessibility.rarity_shape(rarity))
	assert_array(marks).is_equal(["*", "**", "***", "****"])
	assert_int(_unique(shapes).size()).is_equal(shapes.size())
	var tags: Array[String] = []
	for kind in StatusEffect.Kind.size():
		tags.append(Accessibility.status_mark(kind))
	assert_int(_unique_strings(tags).size()).is_equal(tags.size())
	assert_str(Accessibility.status_mark(StatusEffect.Kind.BURN)).is_equal("BRN")
	# One palette role per kind, never a blanket "danger" for everything that hurts: see
	# `status_legibility_test.gd`. "Is this bad for me?" is still a separate question.
	var roles: Array[String] = []
	for kind in StatusEffect.Kind.size():
		roles.append(String(Accessibility.status_role(kind)))
	assert_int(_unique_strings(roles).size()).is_equal(roles.size())
	assert_bool(Accessibility.status_is_harmful(StatusEffect.Kind.POISON)).is_true()
	assert_bool(Accessibility.status_is_harmful(StatusEffect.Kind.HASTE)).is_false()


func test_rarity_mark_is_empty_until_the_setting_is_on() -> void:
	_glyphs(false)
	assert_str(Accessibility.rarity_mark(ItemInstance.Rarity.EPIC)).is_empty()
	_glyphs(true)
	assert_str(Accessibility.rarity_mark(ItemInstance.Rarity.EPIC)).is_equal("***")


func test_special_rooms_have_shapes_and_ordinary_ones_do_not() -> void:
	assert_int(Accessibility.room_shape(Minimap.RoomKind.COMBAT)).is_equal(-1)
	assert_int(Accessibility.room_shape(Minimap.RoomKind.START)).is_equal(-1)
	var shapes: Array[int] = []
	for kind: int in [
		Minimap.RoomKind.ELITE,
		Minimap.RoomKind.TRAP,
		Minimap.RoomKind.TREASURE,
		Minimap.RoomKind.ALTAR,
		Minimap.RoomKind.SHOP,
		Minimap.RoomKind.SHRINE,
		Minimap.RoomKind.STAIRS,
		Minimap.RoomKind.BOSS,
	]:
		var shape := Accessibility.room_shape(kind)
		assert_int(shape).is_greater_equal(0)
		shapes.append(shape)
	assert_int(_unique(shapes).size()).is_equal(shapes.size())


# ------------------------------------------------------------------ widgets


func test_chest_card_states_rarity_in_pips_only_with_glyphs_on() -> void:
	var chest: ChestUi = auto_free(
		(load("res://src/ui/chest_ui.tscn") as PackedScene).instantiate()
	)
	add_child(chest)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var item := UiFakes.make_item(rng, ItemInstance.Rarity.EPIC, ItemBase.Slot.WEAPON)
	_glyphs(false)
	var plain := chest.describe_offer(item)
	assert_str(str(plain["subtitle"])).not_contains("*")
	_glyphs(true)
	var marked := chest.describe_offer(item)
	assert_str(str(marked["subtitle"])).starts_with("***")
	assert_str(str(marked["subtitle"])).contains("Epic")
	# The shape travels with the card whatever the setting; the badge decides to draw it.
	assert_int(int(marked["shape"])).is_equal(Accessibility.rarity_shape(ItemInstance.Rarity.EPIC))


func test_shape_badge_only_takes_space_when_it_shows() -> void:
	var badge: ShapeBadge = auto_free(ShapeBadge.new())
	badge.shape = Accessibility.Shape.DIAMOND
	badge.tag = "**"
	add_child(badge)
	_glyphs(false)
	assert_bool(badge.is_showing()).is_false()
	assert_vector(badge._get_minimum_size()).is_equal(Vector2.ZERO)
	_glyphs(true)
	assert_bool(badge.is_showing()).is_true()
	assert_float(badge._get_minimum_size().x).is_greater(float(ShapeBadge.SIZE))
	# `always` is how the gallery board draws marks with the player's setting off.
	_glyphs(false)
	badge.always = true
	assert_bool(badge.is_showing()).is_true()


func test_status_row_lists_active_effects_in_kind_order() -> void:
	var row: StatusRow = auto_free(StatusRow.new())
	add_child(row)
	var player := _player()
	player.status.add(StatusEffect.Kind.POISON)
	player.status.add(StatusEffect.Kind.BURN, 2)
	row.bind(player)
	assert_array(row.shown_kinds()).is_equal(
		[int(StatusEffect.Kind.BURN), int(StatusEffect.Kind.POISON)]
	)
	# The chip always reserves room for its three-letter tag: the tag is what names the
	# effect, so it is not behind a setting and the row does not resize when one is flipped.
	_glyphs(false)
	var plain := row.chip_width()
	assert_float(plain).is_greater_equal(float(StatusRow.CHIP) + row.tag_width())
	_glyphs(true)
	assert_float(row.chip_width()).is_equal(plain)
	row.bind(null)
	assert_array(row.shown_kinds()).is_empty()


func test_hud_binds_the_status_row_to_the_player() -> void:
	var hud: Hud = auto_free((load("res://src/ui/hud.tscn") as PackedScene).instantiate())
	add_child(hud)
	var player := _player()
	player.status.add(StatusEffect.Kind.SHOCK)
	hud.bind(player)
	assert_array(hud.status_row().shown_kinds()).is_equal([int(StatusEffect.Kind.SHOCK)])
	hud.bind(null)
	assert_array(hud.status_row().shown_kinds()).is_empty()


func test_hp_bar_danger_and_chip_obey_the_policy() -> void:
	var bar: HpBar = auto_free(HpBar.new())
	add_child(bar)
	bar.set_hp(100.0, 100.0)
	assert_bool(bar.is_danger()).is_false()
	bar.set_hp(20.0, 100.0)
	assert_bool(bar.is_danger()).is_true()
	# Reduce motion snaps the trailing chip instead of sliding it.
	GameState.settings["reduce_motion"] = true
	bar._process(0.016)
	assert_float(bar._ghost).is_equal_approx(bar.fraction(), 0.001)


func test_pause_equipment_row_carries_the_rarity_mark() -> void:
	var pause: PauseMenu = auto_free(
		(load("res://src/ui/pause_menu.tscn") as PackedScene).instantiate()
	)
	add_child(pause)
	var player := _player()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	player.equipment.slots = {
		&"weapon": UiFakes.make_item(rng, ItemInstance.Rarity.LEGENDARY, ItemBase.Slot.WEAPON)
	}
	var page: Control = pause.loadout_screen()
	_glyphs(true)
	pause.bind(player)
	assert_str(_labels(page)).contains("****")
	_glyphs(false)
	pause.loadout_screen().refresh()
	# The rows the refill replaced are queue_free'd; let that land before the suite counts.
	await get_tree().process_frame
	assert_str(_labels(page)).not_contains("****")


func test_accessibility_board_swatches_stay_inside_the_frame() -> void:
	var board: AccessibilityBoard = auto_free(AccessibilityBoard.new())
	add_child(board)
	board.size = Vector2(480, 270)
	var rects: Dictionary = board.swatch_rects()
	assert_int(rects.size()).is_greater(20)
	var frame := Rect2i(Vector2i.ZERO, Vector2i(480, 270))
	for key: String in rects.keys():
		var rect: Rect2i = rects[key]
		(
			assert_bool(frame.encloses(rect))
			. override_failure_message("%s at %s escapes the 480x270 frame" % [key, rect])
			. is_true()
		)
	# Both columns describe the same chips; only the right one draws shapes.
	assert_bool(rects.has("colour_rarity_0")).is_true()
	assert_bool(rects.has("glyph_rarity_0")).is_true()


# ------------------------------------------------------------------ helpers


static func _unique(values: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for v: int in values:
		if not out.has(v):
			out.append(v)
	return out


static func _unique_strings(values: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for v: String in values:
		if not out.has(v):
			out.append(v)
	return out


## Every Label text under `node`, joined, so a test can assert on what the page says.
static func _labels(node: Node) -> String:
	var parts := PackedStringArray()
	for child: Node in node.get_children():
		if child is Label:
			parts.append((child as Label).text)
		parts.append(_labels(child))
	return " ".join(parts)
