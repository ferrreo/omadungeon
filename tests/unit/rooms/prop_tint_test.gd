## The readable tint props, hazards and interactables are drawn with (docs §10): the room's
## own tile colours pushed off its floor colour so nothing the player must see or avoid is
## painted the same as the tile behind it.
class_name PropTintTest
extends GdUnitTestSuite

const FLOOR := Prop.FLOOR_RAMP_INDEX
const CELL := 16
const CRYPT_PROPS := "res://assets/sprites/props/crypt.png"
## Every shipped fixture, dark and light: a tint model that only works on one of them is not a
## tint model.
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "nord", "catppuccin-latte", "white"
]
## Minimum contrast between neighbouring body rungs. The geometric spread delivers 1.29-1.68 on
## the shipped fixtures; the model it replaced delivered 1.12-1.30, which is the flat sprite.
const BODY_STEP := 1.25
## How much of a rung's clearance the accent re-hue may round away. Relative rather than
## absolute: a light theme's top rung clears its floor by 9.3, and a hundredth of a ratio that
## size is below what a Color can hold. It is not zero because the re-hue has one degree of
## freedom and two readings to satisfy - it lands the rung on its drawn value under the room's
## own light, and the torchless reading of the same rung then moves by a per cent or two.
const CLEARANCE_SLACK := 0.98


func _palette(name: String) -> ThemePalette:
	var toml := ColorsToml.load_file(
		"res://tests/fixtures/omarchy/%s/state/current/theme/colors.toml" % name
	)
	assert_object(toml).is_not_null()
	return ThemePalette.from_colors_toml(toml, name)


func _room_colors(name: String) -> PackedColorArray:
	return PackedColorArray(TileRamp.target_colors(_palette(name), TileRamp.Variant.BASE, 7))


## Every tinted ramp index has to clear the room's *own* floor colour, not the tinted one.
##
## Index 1 is skipped: it is the ink, and it clears the floor on the *dark* side of it, which
## `_assert_ink` covers. Everything else rises off the floor as before.
func _assert_ladder(tinted: PackedColorArray, room: PackedColorArray, ambient: float) -> void:
	var targets := Prop.readable_contrast()
	var lit := func(c: Color) -> Color: return Color(c.r * ambient, c.g * ambient, c.b * ambient)
	var floor_lit: Color = lit.call(room[FLOOR])
	for i in range(2, TileRamp.RAMP_SIZE):
		var got := ThemePalette.contrast_ratio(lit.call(tinted[i]), floor_lit)
		(
			assert_float(got)
			. override_failure_message(
				"ramp index %d: contrast %f < %f at ambient %f" % [i, got, targets[i], ambient]
			)
			. is_greater_equal(targets[i] - 0.01)
		)


## The ink rung's own contract: it is the darkest colour in the prop, and it stands off the
## body rung next to it by at least `Prop.INK_BODY_RATIO`. That second half is the rim - the
## thing the owner's verifier measured at 1.17 on a shipped crate and called a rimless block.
func _assert_ink(tinted: PackedColorArray, ambient: float, where: String) -> void:
	var lit := func(c: Color) -> Color: return Color(c.r * ambient, c.g * ambient, c.b * ambient)
	var ink: Color = tinted[Prop.INK_RUNG]
	for rung: int in Prop.BODY_RUNGS:
		(
			assert_float(ThemePalette.relative_luminance(ink))
			. override_failure_message(
				"%s: the ink is not the darkest rung (body rung %d is darker)" % [where, rung]
			)
			. is_less_equal(ThemePalette.relative_luminance(tinted[rung]) + 0.0001)
		)
	var neighbour := Prop.nearest_body_rung(tinted, tinted[FLOOR], ambient)
	(
		assert_float(ThemePalette.contrast_ratio(lit.call(ink), lit.call(neighbour)))
		. override_failure_message(
			"%s: the outline and the body it wraps render the same value" % where
		)
		. is_greater_equal(Prop.INK_BODY_RATIO - 0.01)
	)


func test_every_ramp_index_clears_the_floor_on_a_dark_theme() -> void:
	var base := _room_colors("tokyo-night")
	# The untreated tile ramp paints a prop body in the floor's own colour.
	assert_float(ThemePalette.contrast_ratio(base[FLOOR], base[FLOOR])).is_equal(1.0)
	_assert_ladder(Prop.readable_colors(base), base, 1.0)


func test_every_ramp_index_clears_the_floor_on_a_light_theme() -> void:
	var base := _room_colors("white")
	_assert_ladder(Prop.readable_colors(base), base, 1.0)


func test_a_dimmed_floor_brightens_the_tint_instead_of_swallowing_it() -> void:
	for name: String in ["tokyo-night", "white", "gruvbox"]:
		var base := _room_colors(name)
		# A dark wallpaper dims the whole environment; the guarantee is on what is drawn.
		_assert_ladder(Prop.readable_colors(base, null, 0.55), base, 0.55)


func test_a_dim_aware_tint_is_at_least_as_separated_as_an_undimmed_one() -> void:
	var base := _room_colors("tokyo-night")
	var plain := Prop.readable_colors(base)
	var dimmed := Prop.readable_colors(base, null, 0.55)
	for i in range(1, TileRamp.RAMP_SIZE):
		var a := ThemePalette.contrast_ratio(plain[i], base[FLOOR])
		var b := ThemePalette.contrast_ratio(dimmed[i], base[FLOOR])
		assert_float(b).is_greater_equal(a - 0.01)


func test_readable_material_keeps_the_shader_and_ramp_of_the_tiles() -> void:
	var base := TileRamp.make_material(_palette("tokyo-night"), TileRamp.Variant.BASE, 7)
	var mat := Prop.readable_material(base)
	assert_object(mat.shader).is_same(base.shader)
	assert_array(Array(mat.get_shader_parameter(&"ramp") as PackedColorArray)).is_equal(
		Array(PackedColorArray(TileRamp.RAMP))
	)
	assert_float(float(mat.get_shader_parameter(&"blend"))).is_equal(1.0)
	assert_object(Prop.readable_material(null)).is_null()


func test_floor_root_draws_props_with_the_accent_tint_and_stairs_with_the_readable_one() -> void:
	var root: FloorRoot = auto_free(FloorRoot.new())
	add_child(root)
	root.build_from_path(RoomsTestFixtures.three_rooms(), RoomsTestFixtures.ATLAS)
	assert_int(root.props.size()).is_greater(0)
	var prop := root.props[0]
	var room := root.room_at_world(prop.position)
	assert_object(room).is_not_null()
	var expected := root.prop_accent_material_for_room(room.id)
	assert_object(prop.sprite.material).is_same(expected)
	# Interactables are furniture the player has learnt the shape of, not set dressing: they
	# keep the plain readable tint.
	assert_object(root.stairs.sprite.material).is_same(
		root.prop_material_for_room(root.data.stairs_room)
	)
	var tiles := Prop.ramp_targets(root.material_for_room(room.id))
	var props := Prop.ramp_targets(expected)
	for i in range(1, TileRamp.RAMP_SIZE):
		var before := ThemePalette.contrast_ratio(tiles[i], tiles[FLOOR])
		var after := ThemePalette.contrast_ratio(props[i], tiles[FLOOR])
		(
			assert_float(after)
			. override_failure_message(
				"ramp index %d did not separate: %f -> %f" % [i, before, after]
			)
			. is_greater_equal(before - 0.01)
		)
	assert_float(ThemePalette.contrast_ratio(props[FLOOR], tiles[FLOOR])).is_greater(2.0)


## The accent tint is what makes a prop a different *colour* from the room rather than a
## lighter value of it. It must cost the readable ladder nothing, and the invariant that
## delivers that is "the rung is *drawn* at the value it was drawn at before the hue changed".
##
## It used to be the authored luminance instead, which is a weaker claim than it looks: the
## room's torches add a flat value to all three channels, and the sRGB curve turns that into
## more luminance on a grey than on a saturated hue, so two rungs of equal authored luminance
## render up to 0.04 of contrast apart once a torch is on them. Measured here the way the
## ladder is built - on the drawn value, and on the clearance in both readings of the room.
func test_the_accent_tint_recolours_the_body_without_losing_the_readable_ladder() -> void:
	for name: String in ["tokyo-night", "gruvbox", "catppuccin", "nord", "catppuccin-latte"]:
		var base := _room_colors(name)
		var readable := Prop.readable_colors(base)
		var accented := Prop.accent_colors(base)
		_assert_ladder(accented, base, 1.0)
		var floor_c := base[FLOOR]
		var bloom := Prop.bloom_for(floor_c)
		for i in range(1, TileRamp.RAMP_SIZE):
			for light: Color in [Color.BLACK, bloom]:
				var before := ThemePalette.contrast_ratio(
					Prop.shown(readable[i], 1.0, light), Prop.shown(floor_c, 1.0, light)
				)
				var after := ThemePalette.contrast_ratio(
					Prop.shown(accented[i], 1.0, light), Prop.shown(floor_c, 1.0, light)
				)
				# One direction only. The re-hue may not *spend* the clearance the ladder
				# bought; adding some is harmless, and it does add a few per cent to the top
				# rungs because it has one degree of freedom and two readings of the room to
				# satisfy. What that could cost - the step between two rungs - is measured
				# directly by `test_the_rungs_of_a_prop_are_separated_from_each_other` and,
				# under the room's own light, by `prop_render_test`.
				(
					assert_float(after)
					. override_failure_message(
						(
							(
								"%s: the re-hue moved ramp index %d's clearance at bloom %s "
								% [name, i, light.to_html(false)]
							)
							+ "(%.2f -> %.2f)" % [before, after]
						)
					)
					. is_greater_equal(before * CLEARANCE_SLACK)
				)
		var accent := base[TileRamp.FLAME_A]
		for i: int in [2, 3, 4, 5]:
			(
				assert_float(TileRamp.hue_distance(accented[i].h, accent.h))
				. override_failure_message(
					(
						"%s: prop body rung %d renders %s, not the room's accent hue %s"
						% [name, i, accented[i].to_html(false), accent.to_html(false)]
					)
				)
				. is_less(0.02)
			)
			(
				assert_bool(TileRamp.differs_in_hue(accented[i], base[FLOOR]))
				. override_failure_message(
					(
						"%s: prop body rung %d is the floor's own hue (%s)"
						% [name, i, accented[i].to_html(false)]
					)
				)
				. is_true()
			)


## A greyscale theme has no hue to lend. Painting one on would put a colour in the dungeon that
## the player's desktop does not contain, so the accent tint stands aside.
func test_a_greyscale_theme_keeps_the_plain_readable_tint() -> void:
	var base := _room_colors("white")
	var readable := Prop.readable_colors(base)
	var accented := Prop.accent_colors(base)
	for i in range(TileRamp.RAMP_SIZE):
		assert_bool(accented[i].is_equal_approx(readable[i])).is_true()


## The floor ladder guarantees each rung against the *floor*. That is not enough to keep a prop
## readable: the ink draws the outline and the four body rungs the shadow, the body, the lit
## face and the highlight, and pushing all five the same way off the floor cleared every target
## at once and handed back five colours of the same value - a crate rendered as a plain block
## with no rim, which is what the owner's verifier measured at a contrast ratio of 1.17.
## `Prop.ink_color` sends the outline the other way and `Prop.spread_rungs` opens the rest out.
func test_the_rungs_of_a_prop_are_separated_from_each_other() -> void:
	for name: String in THEMES:
		var tinted := Prop.readable_colors(_room_colors(name))
		for i in range(1, Prop.BODY_RUNGS.size()):
			var previous: Color = tinted[Prop.BODY_RUNGS[i - 1]]
			var rung: Color = tinted[Prop.BODY_RUNGS[i]]
			(
				assert_float(ThemePalette.contrast_ratio(rung, previous))
				. override_failure_message(
					(
						"%s: prop rungs %d and %d render the same value, so the prop is flat"
						% [name, Prop.BODY_RUNGS[i - 1], Prop.BODY_RUNGS[i]]
					)
				)
				. is_greater(BODY_STEP)
			)
		_assert_ink(tinted, 1.0, name)
		var ink: Color = tinted[Prop.INK_RUNG]
		var top: Color = tinted[Prop.BODY_RUNGS[Prop.BODY_RUNGS.size() - 1]]
		(
			assert_float(ThemePalette.contrast_ratio(top, ink))
			. override_failure_message("%s: the whole prop ramp is one value" % name)
			. is_greater_equal(Prop.INK_BODY_RATIO - 0.01)
		)


## The ink is the one rung that goes *down*, and it is why the four above it have a band to
## spread across. Asserted through the shipped lighting model rather than on a raw palette,
## because "black clears the floor" is a promise about a floor that has been lit into
## `ThemePalette.LIT_FLOOR_LUMINANCE_MIN..MAX` - a raw theme background can be darker than
## anything, and then no outline exists that stands off it.
func test_the_ink_rung_sits_under_the_floor_on_a_lit_dark_theme() -> void:
	for name: String in ["tokyo-night", "gruvbox", "catppuccin", "nord"]:
		for ambient: float in [1.0, 0.7, WallpaperAnalyzer.AMBIENT_MIN]:
			var lit := _palette(name).light_environment(ambient)
			var room := PackedColorArray(TileRamp.target_colors(lit, TileRamp.Variant.BASE, 7))
			var tinted := Prop.readable_colors(room)
			var where := "%s @ %.2f" % [name, ambient]
			(
				assert_float(ThemePalette.relative_luminance(tinted[Prop.INK_RUNG]))
				. override_failure_message("%s: the outline is brighter than the floor" % where)
				. is_less(ThemePalette.relative_luminance(room[FLOOR]))
			)
			(
				assert_float(ThemePalette.contrast_ratio(tinted[Prop.INK_RUNG], room[FLOOR]))
				. override_failure_message("%s: the outline vanishes into the floor" % where)
				. is_greater_equal(Prop.INK_FLOOR_RATIO - 0.01)
			)
			_assert_ladder(tinted, room, 1.0)
			_assert_ink(tinted, 1.0, where)


## The spread never brings a body rung closer to the floor than the ladder's own minimum, so it
## cannot undo the guarantee it is opening out. (It may move the anchor rung toward the floor -
## that is the point of an anchor - but only as far as its target.)
func test_spreading_the_rungs_keeps_every_ladder_minimum() -> void:
	for name: String in THEMES:
		var base := _room_colors(name)
		var floor_c := base[FLOOR]
		var targets := Prop.readable_contrast()
		var tinted := Prop.readable_colors(base)
		for i: int in Prop.BODY_RUNGS:
			(
				assert_float(ThemePalette.contrast_ratio(tinted[i], floor_c))
				. override_failure_message(
					"%s: rung %d ended up %.2f from the floor" % [name, i, targets[i]]
				)
				. is_greater_equal(targets[i] - 0.01)
			)


## The promise measured the way a player meets it: on the pixels of a shipped crate, mapped
## through the material the room actually draws props with. A crate is the case the verifier
## reported - its art is an ink rim around a flat fill, so if the retint flattens anything it
## flattens this.
func test_a_shipped_crate_keeps_its_outline_against_its_own_fill() -> void:
	var atlas := Image.new()
	assert_int(atlas.load_png_from_buffer(FileAccess.get_file_as_bytes(CRYPT_PROPS))).is_equal(OK)
	var column := Prop.column_for(&"crypt", &"crate")
	assert_int(column).is_greater_equal(0)
	for name: String in THEMES:
		for ambient: float in [1.0, WallpaperAnalyzer.AMBIENT_MIN]:
			var lit := _palette(name).light_environment(ambient)
			var room := PackedColorArray(TileRamp.target_colors(lit, TileRamp.Variant.BASE, 7))
			var tinted := Prop.accent_colors(room)
			var counts: Dictionary = {}
			var ink := Color.TRANSPARENT
			for y in range(CELL):
				for x in range(CELL):
					var px := atlas.get_pixel(column * CELL + x, y)
					if px.a == 0.0:
						continue
					var index := TileRamp.index_of(px)
					if index < 0:
						continue
					if index == Prop.INK_RUNG:
						ink = tinted[index]
						continue
					counts[index] = int(counts.get(index, 0)) + 1
			var fill := -1
			var best := 0
			for index: int in counts:
				if int(counts[index]) > best:
					best = int(counts[index])
					fill = index
			var where := "%s @ %.2f" % [name, ambient]
			(
				assert_int(fill)
				. override_failure_message("%s: the crate has no fill" % where)
				. is_greater(0)
			)
			(
				assert_float(ThemePalette.contrast_ratio(ink, tinted[fill]))
				. override_failure_message(
					(
						"%s: the crate draws its outline %s on a fill of %s"
						% [where, ink.to_html(false), tinted[fill].to_html(false)]
					)
				)
				. is_greater_equal(Prop.INK_BODY_RATIO - 0.01)
			)


## The light model itself, which is what three rounds of fixes in the colour model got wrong.
##
## A dungeon torch is a `PointLight2D` in ADD, and Godot's canvas light multiplies the light by
## the surface before adding it: a lit pixel is drawn at `c * (1 + gain)`, per channel, clamped.
## The old model added a flat grey offset instead, which lights a dark floor and a bright prop by
## the same amount when the renderer lights the prop nearly twice as hard - so the model read a
## crate's top two rungs 0.69 and 0.99 of drawn luminance apart while the compositor drew both of
## them with red and green pinned at 255, one code point apart.
func test_the_light_is_multiplied_by_the_surface_and_clamped() -> void:
	var gain := Color(0.5, 0.25, 0.0, 1.0)
	var dim := Prop.under_light(Color(0.2, 0.2, 0.2, 1.0), gain)
	var bright := Prop.under_light(Color(0.6, 0.6, 0.6, 1.0), gain)
	assert_float(dim.r).is_equal_approx(0.3, 0.001)
	assert_float(bright.r).is_equal_approx(0.9, 0.001)
	(
		assert_float(bright.r - 0.6)
		. override_failure_message("the light did not scale with the surface it landed on")
		. is_greater(dim.r - 0.2)
	)
	assert_float(dim.g).is_equal_approx(0.25, 0.001)
	assert_float(dim.b).is_equal_approx(0.2, 0.001)
	# ...and it clamps, which is the whole reason the top of the ramp collapsed.
	assert_float(Prop.under_light(Color(0.8, 0.8, 0.8, 1.0), gain).r).is_equal_approx(1.0, 0.001)
	assert_bool(Prop.clipped(Color(0.8, 0.8, 0.8, 1.0), 1.0, gain)).is_true()
	assert_bool(Prop.clipped(Color(0.2, 0.2, 0.2, 1.0), 1.0, gain)).is_false()
	assert_bool(Prop.has_light(Color.BLACK)).is_false()
	assert_bool(Prop.has_light(gain)).is_true()


## `unclipped` answers "how bright may this hue be drawn before the room's own light takes it to
## white", which is the ceiling `spread_rungs` is written against.
func test_unclipped_finds_the_brightest_colour_the_light_does_not_saturate() -> void:
	var gain := Color(0.5, 0.25, 0.0, 1.0)
	var top := Prop.unclipped(Color(0.5, 0.5, 0.5, 1.0), 1.0, gain)
	assert_bool(Prop.clipped(top, 1.0, gain)).is_false()
	var above := ThemePalette.with_luminance(top, ThemePalette.relative_luminance(top) + 0.02)
	assert_bool(Prop.clipped(above, 1.0, gain)).is_true()


## The light the ladder is built against is the light `data/rooms/dungeon_light.tres` actually
## casts, not a constant: dim the torches and the model gets the band back, which is the trade the
## interior collapse was always about. It is also capped, because past `Prop.BLOOM_MAX` the
## rendered check stops asking for an interior and there is no reason to spend band on it.
func test_the_modelled_light_tracks_the_dungeon_light_resource() -> void:
	var floor_c := Color("#4d4f68")
	var bright := Prop.bloom_for(floor_c)
	assert_bool(Prop.has_light(bright)).is_true()
	var shipped := DungeonLight.resolve()
	var dim := DungeonLight.new()
	dim.torch_energy = shipped.torch_energy * 0.5
	dim.light_saturation = shipped.light_saturation
	# `bloom_for` resolves the shipped resource, so the comparison is made on the maths it uses.
	var tint := Prop.light_tint(floor_c)
	var weight := (floor_c.r * tint.r + floor_c.g * tint.g + floor_c.b * tint.b) / 3.0
	var capped := Prop.BLOOM_MAX / weight
	var shipped_energy := shipped.torch_energy
	# The gain is what the room's light puts on a surface *over* the level the theme authored it
	# at: the dark it keeps with nothing lighting it, plus every source's energy through its own
	# colour, less the 1 the authored colour already is (`Prop.bloom_for`).
	var dark := LightingProfile.resolve().unlit_level()
	var want := dark + tint.r * shipped_energy * Prop.TORCH_OVERLAP - 1.0
	(
		assert_float(bright.r)
		. override_failure_message("the gain is not the torch energy this floor burns at")
		. is_equal_approx(minf(maxf(want, 0.0), capped), 0.002)
	)
	assert_float(dim.torch_energy).is_less(shipped_energy)
	# The cap is real: a floor dark enough would otherwise ask for an unbounded gain.
	var near_black := Color(0.02, 0.02, 0.02, 1.0)
	var tint_black := Prop.light_tint(near_black)
	var w := (
		(near_black.r * tint_black.r + near_black.g * tint_black.g + near_black.b * tint_black.b)
		/ 3.0
	)
	assert_float(Prop.bloom_for(near_black).r).is_less_equal(tint_black.r * (Prop.BLOOM_MAX / w))


## The torch is lit from the room's *lit* palette, where `heat` has already been through the
## contrast guard - and on a theme whose fire colour is dark that guard takes it toward white and
## desaturates it. Reading the raw role instead modelled nord's torch at a red:green ratio of
## 1:0.50 where the frame measured 1:0.71, and a light model that is wrong about the hue is wrong
## about which channel clips first.
func test_the_torch_colour_is_guarded_against_the_floor_it_lights() -> void:
	for name: String in THEMES:
		var lit := _palette(name).light_environment(1.0)
		var floor_c := lit.get_color(&"floor")
		var tint := Prop.light_tint(floor_c, lit)
		(
			assert_float(maxf(tint.r, maxf(tint.g, tint.b)))
			. override_failure_message("%s: the torch colour is not at full value" % name)
			. is_equal_approx(1.0, 0.01)
		)
		var raw_heat := lit.get_color(&"heat")
		var guarded := ThemePalette.ensure_contrast_toward(
			raw_heat, floor_c, 3.0, Color.BLACK if lit.is_light else Color.WHITE
		)
		(
			assert_float(TileRamp.hue_distance(tint.h, guarded.h))
			. override_failure_message("%s: the torch left the theme's fire hue" % name)
			. is_less(0.02)
		)
