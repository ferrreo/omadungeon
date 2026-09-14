## The fourth pickup kind. `PickupWorldContrastTest` holds the contract for the three homing
## drops - gold, hearts, stat orbs - and this suite holds it for the one the first pass of that
## guard stopped short of: the item drop.
##
## `PickupBase` was routed through `ThemePalette.world_color()` and the three drops were fixed
## together. `ItemPickup` is not a `PickupBase` - an item changes the build, so it is an
## `Interactable` the player has to walk up to and ask for - and nothing moved it onto that
## path. It went on reading `get_color(item.rarity_role())`, which is guarded against
## `ThemePalette.SURFACES` (floor, floor_alt, void) and against nothing the *dungeon* paints, so
## on a light fixture a dropped item lying against a wall was gone while the coin beside it read
## cleanly. The same bug, one node further along, which is the shape of bug this suite exists to
## stop repeating.
##
## The two halves are measured separately: the colour model (`WORLD_RARITY_ROLES` clears every
## dungeon surface) and the wiring (the node draws that colour rather than the plain role). A
## model nothing reads is the half the first pass got right.
class_name PickupWorldRolesTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
## Slack for the last lerp of the guard's search, which lands on the target rather than exactly
## on it (same value and same reason as `PickupWorldContrastTest`).
const EPSILON := 0.01

var _registry: ItemRegistry
var _world: Node2D
var _saved_palette: ThemePalette


func before_test() -> void:
	_registry = ItemRegistry.load_default()
	_world = auto_free(Node2D.new()) as Node2D
	add_child(_world)
	_saved_palette = Desktop.palette


## `Desktop.palette` is an autoload field and the wiring cases point it at a light fixture, so
## it is put back whatever the case did with it - a suite that leaves the desktop on somebody
## else's theme is a cross-suite shared resource.
func after_test() -> void:
	Desktop.palette = _saved_palette
	await get_tree().physics_frame


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _item(rarity: int) -> ItemInstance:
	return ItemGenerator.generate(
		_registry, 4, _rng(4400 + rarity), 0.0, [ItemBase.Slot.WEAPON], rarity
	)


## The two lists the guard is applied through cannot drift apart: `WORLD_GUARDED_ROLES` is what
## `_apply_world_guard` walks, and a role dropped out of it silently stops being guarded while
## every doc comment still says it is.
func test_the_guarded_list_is_the_union_of_the_two_it_is_made_of() -> void:
	var want: Array[String] = []
	for role: String in ThemePalette.WORLD_ROLES:
		want.append(role)
	for role: String in ThemePalette.WORLD_RARITY_ROLES:
		want.append(role)
	var have: Array[String] = []
	for role: String in ThemePalette.WORLD_GUARDED_ROLES:
		have.append(role)
	(
		assert_array(have)
		. override_failure_message(
			"WORLD_GUARDED_ROLES is %s, but WORLD_ROLES + WORLD_RARITY_ROLES is %s" % [have, want]
		)
		. is_equal(want)
	)


## Every rarity an item can drop at, against every surface the dungeon paints, on every shipped
## fixture. This is the `PickupWorldContrastTest` guarantee extended to the fourth kind.
func test_every_rarity_clears_every_surface_an_item_can_land_on() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		for role: String in ThemePalette.WORLD_RARITY_ROLES:
			for surface: String in ThemePalette.WORLD_SURFACES:
				var ratio := ThemePalette.contrast_ratio(
					p.world_color(StringName(role)), p.get_color(StringName(surface))
				)
				(
					assert_float(ratio)
					. override_failure_message(
						(
							"%s: %s on %s is %.2f:1, needs %.1f:1"
							% [theme, role, surface, ratio, ThemePalette.WORLD_MIN_CONTRAST]
						)
					)
					. is_greater_equal(ThemePalette.WORLD_MIN_CONTRAST - EPSILON)
				)


## The reported gap, pinned to the reading that made it a bug rather than a preference: on the
## light fixtures the plain rarity role - the one the node used to read - does not clear the
## wall, and the guarded colour does. If the first ever stops being true the pin is stale and
## should be re-measured, not deleted.
func test_the_plain_rarity_role_is_the_one_that_fails_on_a_light_wall() -> void:
	var reported := 0
	for theme: String in ["catppuccin-latte", "white"]:
		var p := _palette(theme)
		var wall := p.get_color(&"wall")
		for role: String in ThemePalette.WORLD_RARITY_ROLES:
			var plain := ThemePalette.contrast_ratio(p.get_color(StringName(role)), wall)
			var guarded := ThemePalette.contrast_ratio(p.world_color(StringName(role)), wall)
			if plain < ThemePalette.WORLD_MIN_CONTRAST:
				reported += 1
			(
				assert_float(guarded)
				. override_failure_message(
					(
						"%s: %s on the wall is %.2f:1 guarded (%.2f:1 unguarded)"
						% [theme, role, guarded, plain]
					)
				)
				. is_greater_equal(ThemePalette.WORLD_MIN_CONTRAST - EPSILON)
			)
	(
		assert_int(reported)
		. override_failure_message(
			"no unguarded rarity role fails on a light wall any more - re-measure this pin"
		)
		. is_greater(0)
	)


## ...and the role itself is left where the HUD needs it. `rarity_*` is the item card's title
## colour, the pause screen's rarity badge and the chest offer's border, all of which sit on a
## panel, so the guard has to make a second colour rather than move the role - the same split
## `loot` needed for the gold counter.
func test_the_guard_leaves_the_rarity_role_the_ui_reads_alone() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		for role: String in ThemePalette.WORLD_RARITY_ROLES:
			for surface: String in ThemePalette.SURFACES:
				var ratio := ThemePalette.contrast_ratio(
					p.get_color(StringName(role)), p.get_color(StringName(surface))
				)
				(
					assert_float(ratio)
					. override_failure_message(
						"%s: the card's %s on %s fell to %.2f:1" % [theme, role, surface, ratio]
					)
					. is_greater_equal(3.0 - EPSILON)
				)


## The palette a drop is painted from is the one the room is painted from.
##
## `Desktop.palette` is the theme as the desktop authored it; `FloorRoot` exposes that into a
## light band before it paints a tile, and on a dark theme the exposure lifts the floor and the
## wall cap a long way. A drop guarded against the authored surfaces and drawn on the exposed
## ones is guarded against a room that is not on screen: measured on tokyo-night, the desktop's
## `loot` reads 2.05:1 against the *drawn* wall cap, and the lit palette's own world colour reads
## 3.09:1 against it. Both palettes pass `test_every_rarity_clears_every_surface_an_item_can_land_on`
## - the gap only exists where the two are put in the same sentence, which is here and in the
## `pickup_frame` capture.
func test_a_drop_under_a_floor_takes_the_floor_s_lit_colour() -> void:
	var root := auto_free(FloorRoot.new()) as FloorRoot
	_world.add_child(root)
	root.build_with_biome(RoomsTestFixtures.three_rooms(), Biome.load_by_id(&"crypt"), null, null)
	var lit := root.lit_palette()
	assert_object(lit).override_failure_message("the floor built no lit palette").is_not_null()

	var coin := PickupSpawner.make(&"gold")
	root.add_child(coin)
	await get_tree().physics_frame
	(
		assert_object(coin.color)
		. override_failure_message(
			(
				"the coin drew %s; the floor's lit gold is %s and the desktop's is %s"
				% [
					coin.color.to_html(false),
					lit.world_color(&"loot").to_html(false),
					Desktop.palette.world_color(&"loot").to_html(false),
				]
			)
		)
		. is_equal(lit.world_color(&"loot"))
	)

	var item := _item(ItemInstance.Rarity.LEGENDARY)
	var drop := ItemPickup.drop(root, item, Vector2(40.0, 40.0), _rng(11))
	await get_tree().physics_frame
	assert_object(drop.draw_color()).is_equal(lit.world_color(item.rarity_role()))

	# ...and the two palettes really do disagree here, so the equalities above are a constraint
	# rather than a coincidence of a theme whose exposure happens to be a no-op.
	(
		assert_object(lit.world_color(&"loot"))
		. override_failure_message("the lit palette agreed with the desktop; re-measure this pin")
		. is_not_equal(Desktop.palette.world_color(&"loot"))
	)
	coin.queue_free()
	drop.queue_free()
	await get_tree().physics_frame


## A drop with no floor above it - a fixture, a gallery screen, a test - still has to be painted
## in something, and the desktop palette is the honest answer there.
func test_a_drop_with_no_floor_falls_back_to_the_desktop_palette() -> void:
	var coin := PickupSpawner.make(&"heart")
	_world.add_child(coin)
	await get_tree().physics_frame
	assert_object(coin.color).is_equal(Desktop.palette.world_color(&"heal"))
	coin.queue_free()
	await get_tree().physics_frame


## The wiring, on the fixture where the two answers differ most: the node draws the guarded
## colour. Asserted on a light palette on purpose - on a dark theme the rarity roles already
## clear every surface, so `world_color()` and `get_color()` agree there and an equality against
## either one would pass with the bug still in.
func test_the_item_drop_draws_the_guarded_colour() -> void:
	var p := _palette("catppuccin-latte")
	Desktop.palette = p
	var differed := 0
	for rarity: int in range(ItemInstance.RARITY_NAMES.size()):
		var item := _item(rarity)
		var role := item.rarity_role()
		var drop := ItemPickup.drop(_world, item, Vector2(float(rarity) * 24.0, 0.0), _rng(7))
		await get_tree().physics_frame
		if not p.world_color(role).is_equal_approx(p.get_color(role)):
			differed += 1
		(
			assert_object(drop.draw_color())
			. override_failure_message(
				(
					"%s drop drew %s; the guarded colour is %s and the plain role is %s"
					% [
						role,
						drop.draw_color().to_html(false),
						p.world_color(role).to_html(false),
						p.get_color(role).to_html(false),
					]
				)
			)
			. is_equal(p.world_color(role))
		)
		drop.queue_free()
		await get_tree().physics_frame
	(
		assert_int(differed)
		. override_failure_message(
			"latte's guarded rarities all equal their plain roles, so this case proves nothing"
		)
		. is_greater(0)
	)
