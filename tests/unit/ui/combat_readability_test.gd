## Pillar 1, "readable chaos", measured rather than admired.
##
## Three testers looked at three independent combat captures and could not find their own
## character in any of them: four 16 px figures, all flashed white on the same frame, with a
## damage number, a crit and a stolen-stat toast printed on top of each other at one anchor.
## Every assertion here is about one of the three things that fixes: the player carries a mark
## nothing else has, a flash cannot bleach the whole screen at once, and floating text gets
## off the body and out of its neighbours' way.
##
## The theme cases are the guard for the property this work was *not* about. Round three
## bought readability by re-exposing every theme to one target and flattened six themes into
## one look; so the marker is asserted both readable on every fixture's floor *and* different
## on each of them.
class_name CombatReadabilityTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const HUD_SCENE := "res://src/ui/hud.tscn"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "nord", "catppuccin-latte", "white"
]
## Half the height of a 16 px character plus a margin: a number this far above the hit point
## is not covering the thing it describes.
const CLEAR_OF_BODY := 20.0
## Fraction of a number's life by which it must already be clear.
const CLEAR_BY := 0.3


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


func _profile() -> FeelProfile:
	return FeelProfile.load_default()


func _number() -> DamageNumber:
	var number: DamageNumber = auto_free(DamageNumber.new())
	add_child(number)
	return number


func _hud() -> Hud:
	var hud: Hud = auto_free((load(HUD_SCENE) as PackedScene).instantiate())
	add_child(hud)
	return hud


## Steps a number's animation by hand, so the assertion is about the curve and not about how
## many frames the test machine managed to render.
func _advance(number: DamageNumber, seconds: float) -> void:
	var step := 1.0 / 60.0
	var left := seconds
	while left > 0.0:
		number._process(minf(step, left))
		left -= step


# --- floating text ----------------------------------------------------------------------------


## The old rise was `RISE * delta * (1 - t)`, which integrates to about 7 px - under half a
## tile - so the number parked itself on the fight for three quarters of a second.
func test_a_damage_number_travels_far_enough_to_leave_the_body_behind() -> void:
	var number := _number()
	number.pop_text(Vector2(100, 100), "12", false, Color.RED)
	_advance(number, number.lifetime())
	assert_float(100.0 - number.position.y).is_greater_equal(number.total_rise() - 2.0)
	assert_float(number.total_rise()).is_greater_equal(24.0)


## Every number climbs at the same constant speed. That is what makes the HUD's lanes hold:
## with an ease-out, a number that popped late sprinted up into the tail of an earlier one and
## the two collided in mid-air, several lanes above where either of them had been placed.
func test_two_numbers_keep_the_gap_they_were_placed_with() -> void:
	var early := _number()
	var late := _number()
	early.pop_text(Vector2(100, 100), "10", false, Color.RED)
	_advance(early, early.lifetime() * 0.4)
	late.pop_text(Vector2(100, 130), "20", false, Color.RED)
	var gap := absf(late.position.y - early.position.y)
	for _step in range(5):
		_advance(early, early.lifetime() * 0.1)
		_advance(late, late.lifetime() * 0.1)
		(
			assert_float(absf(late.position.y - early.position.y))
			. override_failure_message("the two numbers drifted into each other in mid-air")
			. is_equal_approx(gap, 1.5)
		)


## With motion reduced, "do not animate" must not become "sit on the character". The number
## takes its whole travel on the first frame instead and then only fades.
func test_reduced_motion_places_the_number_where_it_would_have_ended_up() -> void:
	var was: bool = GameState.settings.get("reduce_motion", false)
	GameState.settings["reduce_motion"] = true
	var number := _number()
	number.pop_text(Vector2(100, 100), "12", false, Color.RED)
	_advance(number, 1.0 / 60.0)
	GameState.settings["reduce_motion"] = was
	(
		assert_float(100.0 - number.position.y)
		. override_failure_message("reduce_motion parked the number on the character")
		. is_greater_equal(number.total_rise() - 1.0)
	)


## Where the HUD starts a number, plus what it has travelled by the time anyone reads it, has
## to clear a 16 px character. This is the assertion the capture failed.
func test_a_hit_number_is_clear_of_the_character_by_the_time_it_is_read() -> void:
	var hud := _hud()
	var hit := Vector2(240.0, 140.0)
	var anchor := hud.place_number(hit)
	assert_float(hit.y - anchor.y).is_greater(0.0)
	var number := _number()
	number.pop_text(anchor, "12", false, Color.RED)
	_advance(number, number.lifetime() * CLEAR_BY)
	(
		assert_float(hit.y - number.position.y)
		. override_failure_message("the number is still sitting on the body it describes")
		. is_greater_equal(CLEAR_OF_BODY)
	)


## Damage, a crit and a stolen stat all land in the same beat on the same target. They used to
## be drawn at one anchor, and the capture shows "-1 MIGHT" printed through "151".
func test_numbers_landing_together_take_separate_lanes() -> void:
	var hud := _hud()
	var was: bool = GameState.settings.get("damage_numbers", true)
	GameState.settings["damage_numbers"] = true
	var hit := Vector2(200.0, 160.0)
	for i in range(3):
		EventBus.damage_number.emit(hit, 10.0 + i, false, Color.RED)
	GameState.settings["damage_numbers"] = was
	var placed: Array[Vector2] = []
	for number: DamageNumber in hud.damage_numbers():
		if number.visible:
			placed.append(number.position)
	assert_int(placed.size()).is_equal(3)
	var glyph := DamageNumber.height_for(false)
	var width := _profile().number_lane_width_px
	for i in range(placed.size()):
		for j in range(i + 1, placed.size()):
			var delta: Vector2 = placed[i] - placed[j]
			(
				assert_bool(absf(delta.y) >= glyph or absf(delta.x) >= width)
				. override_failure_message(
					"two numbers overprint each other at %s / %s" % [placed[i], placed[j]]
				)
				. is_true()
			)


## A lane is freed again once the number in it has risen out of the way, so a long fight does
## not walk every later number off the top of the screen.
func test_a_lane_is_released_once_its_number_has_risen() -> void:
	var hud := _hud()
	var hit := Vector2(200.0, 160.0)
	var first := hud.place_number(hit)
	var number := hud.damage_numbers()[0]
	number.pop_text(first, "10", false, Color.RED)
	_advance(number, number.lifetime() * 0.9)
	assert_vector(hud.place_number(hit)).is_equal(first)


## A number that is still hanging over the anchor pushes the next one up a lane, and that lane
## is a real gap rather than a nudge.
func test_a_live_number_pushes_the_next_one_a_whole_lane_up() -> void:
	var hud := _hud()
	var hit := Vector2(200.0, 160.0)
	var first := hud.place_number(hit)
	hud.damage_numbers()[0].pop_text(first, "10", false, Color.RED)
	var second := hud.place_number(hit)
	assert_float(first.y - second.y).is_greater_equal(DamageNumber.height_for(false))


## A crit is drawn in the taller heading font, so it needs a taller lane. A fixed lane step
## was shorter than its glyphs and the crit printed its ascenders through the number above it.
func test_a_crit_reserves_the_taller_lane_its_glyphs_need() -> void:
	var hud := _hud()
	var hit := Vector2(200.0, 160.0)
	var first := hud.place_number(hit, true)
	hud.damage_numbers()[0].pop(first, 151.0, true, Color.RED)
	var second := hud.place_number(hit, false)
	(
		assert_float(first.y - second.y)
		. override_failure_message("a body number was stacked inside a crit's glyphs")
		. is_greater_equal(DamageNumber.height_for(true))
	)
	assert_float(DamageNumber.height_for(true)).is_greater(DamageNumber.height_for(false))


## The glyphs carry a full outline rather than a one-pixel drop shadow: over a scrum, a shadow
## leaves three of the four sides touching whatever sprite is behind them. The outline has to
## stay apart from the glyph colour on a light theme too, where damage colours are pushed dark.
func test_the_number_outline_stays_apart_from_the_glyph_on_every_theme() -> void:
	for theme: String in THEMES:
		var palette := _palette(theme)
		UiTheme.rebuild(palette)
		for role: StringName in [&"danger", &"heal", &"loot"]:
			var glyph := ThemePalette.ensure_contrast(
				UiTheme.signal_color(role), palette.get_color(&"floor"), 3.0
			)
			var ink := DamageNumber.outline_for(glyph)
			(
				assert_float(ThemePalette.contrast_ratio(ink, glyph))
				. override_failure_message(
					"%s: %s outline is the same tone as the glyph" % [theme, role]
				)
				. is_greater_equal(DamageNumber.OUTLINE_CONTRAST)
			)
	UiTheme.rebuild(Desktop.palette)


# --- the hit flash ----------------------------------------------------------------------------


## The flash used to peak at `self_modulate` 3.0, which clips all three channels: every hit
## sprite became the same flat white, and four of them touching became one shape.
func test_a_flash_brightens_the_sprite_without_clipping_it_to_white() -> void:
	var feel := FeelTestHelpers.fresh(get_tree())
	var peak := feel.flash_peak(feel.claim_flash(1.0))
	assert_float(peak).is_greater(1.0)
	(
		assert_float(peak)
		. override_failure_message("the flash still bleaches the sprite to flat white")
		. is_less(2.6)
	)
	feel.reset()


## A cleave through a pack claims one flash per enemy on one frame. Past the budget they still
## flash - the hit has to read on every target - but quietly enough to leave silhouettes.
func test_only_the_first_few_entities_flash_at_full_strength_in_one_frame() -> void:
	var feel := FeelTestHelpers.fresh(get_tree())
	var budget := feel.profile.flash_budget_per_frame
	var claims: Array[float] = []
	for _i in range(budget + 3):
		claims.append(feel.claim_flash(1.0))
	for i in range(budget):
		assert_float(claims[i]).is_equal_approx(feel.flash_scale(), 0.001)
	for i in range(budget, claims.size()):
		assert_float(claims[i]).is_less(claims[0])
		(
			assert_float(claims[i])
			. override_failure_message("a crowded flash was silenced instead of dimmed")
			. is_greater(0.0)
		)
	feel.reset()


## The budget is per physics frame, not a running total: the next frame starts fresh.
func test_the_flash_budget_refills_next_frame() -> void:
	var feel := FeelTestHelpers.fresh(get_tree())
	for _i in range(feel.profile.flash_budget_per_frame + 2):
		feel.claim_flash(1.0)
	await get_tree().physics_frame
	assert_float(feel.claim_flash(1.0)).is_equal_approx(feel.flash_scale(), 0.001)
	feel.reset()


# --- telling the player apart -------------------------------------------------------------------


## The mark that answers "which one am I". It is the only ring on the floor, and it has to be
## legible against the floor of every theme the desktop can hand us.
func test_the_player_marker_reads_on_every_theme_floor() -> void:
	for theme: String in THEMES:
		var palette := _palette(theme)
		var ring := PlayerMarker.ring_color(palette)
		(
			assert_float(ThemePalette.contrast_ratio(ring, palette.get_color(&"floor")))
			. override_failure_message("%s: the player ring is invisible on its own floor" % theme)
			. is_greater_equal(PlayerMarker.RING_CONTRAST)
		)


## ...and against the floor the dungeon is *painted* in, which is not the `floor` role: the
## world is drawn through `ThemePalette.light_environment`, and the marker's guard was pointed
## at the unlit role. On catppuccin-latte the ring measured 3.93:1 against the floor actually
## under it while clearing a 4.5 check against a colour nothing ever draws, and every dark
## theme was worse still - nord's ring sat at 2.16:1 on its own lit floor.
func test_the_player_marker_reads_on_the_floor_the_dungeon_is_painted_in() -> void:
	for theme: String in THEMES:
		var palette := _palette(theme)
		var ring := PlayerMarker.ring_color(palette)
		var target := (
			PlayerMarker.LIT_RING_CONTRAST_GREY
			if PlayerMarker.chroma(ring) < PlayerMarker.RING_CHROMA_MIN
			else PlayerMarker.LIT_RING_CONTRAST
		)
		for lit: Color in PlayerMarker.lit_floors(palette):
			(
				assert_float(ThemePalette.contrast_ratio(ring, lit))
				. override_failure_message(
					(
						"%s: the player ring is %.2f:1 on the lit floor, under %.1f"
						% [theme, ThemePalette.contrast_ratio(ring, lit), target]
					)
				)
				. is_greater_equal(target - 0.01)
			)


## A grey ring has only value to be told apart by, so it is held to the full text threshold on
## the floor it is drawn on. The `white` fixture's accent is a literal grey, and its marker was
## the least salient figure on a screen with four enemies on it.
func test_a_ring_with_no_hue_is_held_to_the_full_contrast() -> void:
	var palette := _palette("white")
	var ring := PlayerMarker.ring_color(palette)
	assert_float(PlayerMarker.chroma(ring)).is_less(PlayerMarker.RING_CHROMA_MIN)
	for lit: Color in PlayerMarker.lit_floors(palette):
		assert_float(ThemePalette.contrast_ratio(ring, lit)).is_greater_equal(
			PlayerMarker.LIT_RING_CONTRAST_GREY - 0.01
		)


## A theme whose accent is a grey (the `white` fixture ships three) would otherwise get a ring
## and a halo of the same tone, which thickens into one blob instead of reading as a ring.
func test_the_marker_halo_stays_apart_from_the_ring_on_every_theme() -> void:
	for theme: String in THEMES:
		var palette := _palette(theme)
		var ring := PlayerMarker.ring_color(palette)
		var halo := PlayerMarker.halo_color(palette)
		(
			assert_float(ThemePalette.contrast_ratio(halo, ring))
			. override_failure_message("%s: the ring and its halo are the same tone" % theme)
			. is_greater_equal(PlayerMarker.HALO_CONTRAST)
		)


## The guard for the property this work was not about. Making the marker readable everywhere
## by giving every theme the same ring would trade pillar 1 for pillar 3; round three already
## paid for that lesson once.
func test_the_player_marker_is_not_the_same_colour_on_every_theme() -> void:
	var seen: Array[Color] = []
	for theme: String in THEMES:
		var ring := PlayerMarker.ring_color(_palette(theme))
		for other: Color in seen:
			(
				assert_float(UiTheme.color_distance(ring, other))
				. override_failure_message(
					"%s: the player ring has flattened into another theme's" % theme
				)
				. is_greater(0.05)
			)
		seen.append(ring)


## The ring is drawn under every body, so an enemy standing on the player cannot hide it, and
## it is wider than the 16 px sprite for the same reason.
func test_the_marker_sits_under_the_bodies_and_is_wider_than_the_sprite() -> void:
	var player: Player = auto_free(Player.new())
	add_child(player)
	# Draw order, not z: the tile layers are opaque at z 0, so a negative z would put the ring
	# under the floor. Being an earlier child than the sprite is what puts it under the body.
	assert_int(player.marker.z_index).is_equal(0)
	assert_int(player.marker.get_index()).is_less(player.sprite.get_index())
	assert_int(player.outline.get_index()).is_less(player.sprite.get_index())
	assert_float(PlayerMarker.RADIUS.x * 2.0).is_greater(16.0)


## The rim is a separate node from the sprite on purpose: a flash that bleaches the sprite
## cannot touch it, which is the only reason an edge survives the moment it is needed most.
func test_the_silhouette_rim_survives_a_flash_on_the_sprite_it_follows() -> void:
	var sprite: AnimatedSprite2D = auto_free(AnimatedSprite2D.new())
	add_child(sprite)
	var outline: SpriteOutline = auto_free(SpriteOutline.new())
	add_child(outline)
	outline.source = sprite
	outline.set_tint(Color(0.05, 0.05, 0.08, 0.85))
	sprite.self_modulate = Color(3.0, 3.0, 3.0, 1.0)
	assert_object(outline.material).is_not_null()
	var tint: Color = (outline.material as ShaderMaterial).get_shader_parameter(&"tint")
	assert_float(ThemePalette.relative_luminance(tint)).is_less(0.2)


## Every character was wearing two outlines. The sheets already ship a 1 px ink rim and the
## stamped rim added a second at +-1 px, so a 16 px figure sat inside a 2-3 px black border and
## the weapon's swing trail came out as a ragged cloud. The stamped rim now only covers the
## flash, which is the one moment the authored rim is bleached away.
func test_the_stamped_rim_is_not_a_second_outline_on_an_unflashed_sprite() -> void:
	var sprite: AnimatedSprite2D = auto_free(AnimatedSprite2D.new())
	sprite.sprite_frames = SpriteFrames.new()
	add_child(sprite)
	var outline: SpriteOutline = auto_free(SpriteOutline.new())
	add_child(outline)
	outline.source = sprite
	assert_bool(outline.is_flashing()).is_false()
	assert_bool(outline.visible).is_false()


## ...and it is there for the frames that need it.
func test_the_stamped_rim_is_raised_for_the_length_of_a_flash() -> void:
	var sprite: AnimatedSprite2D = auto_free(AnimatedSprite2D.new())
	sprite.sprite_frames = SpriteFrames.new()
	add_child(sprite)
	var outline: SpriteOutline = auto_free(SpriteOutline.new())
	add_child(outline)
	outline.source = sprite
	outline.flash_for(0.5)
	assert_bool(outline.visible).is_true()
	outline.flash_for(0.0)
	assert_bool(outline.is_flashing()).is_true()


## The guard for the property the rim used to carry on its own: with the stamped rim gone
## outside a flash, the sheets themselves have to hold the silhouette. Every player class and a
## sample of enemies must still ship an ink outline around the body.
func test_every_character_sheet_still_ships_its_own_ink_rim() -> void:
	var sheets: PackedStringArray = [
		"res://assets/sprites/player/fighter.png",
		"res://assets/sprites/player/ranger.png",
		"res://assets/sprites/player/wizard.png",
		"res://assets/sprites/player/oligarch.png",
	]
	for path: String in sheets:
		var image := Image.load_from_file(path)
		assert_object(image).override_failure_message("missing sheet %s" % path).is_not_null()
		var opaque := 0
		var ink := 0
		for y in range(mini(16, image.get_height())):
			for x in range(mini(16, image.get_width())):
				var c := image.get_pixel(x, y)
				if c.a < 0.5:
					continue
				opaque += 1
				if ThemePalette.relative_luminance(c) < 0.05:
					ink += 1
		assert_int(opaque).is_greater(40)
		(
			assert_float(float(ink) / float(maxi(1, opaque)))
			. override_failure_message("%s frame 0 has no authored outline left" % path)
			. is_greater(0.2)
		)
