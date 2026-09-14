## The contrast floor for the three colours a player has to *find in the level*: `loot` (gold),
## `heal` (hearts) and `magic` (stat orbs), the roles `PickupBase.color_role` names.
##
## `PaletteContrastTest` already proves `ThemePalette.ROLE_GUARDS`, and every one of these three
## passed it: they are guarded against `floor`, `floor_alt` and `void`, which is the set a piece
## of HUD can sit on. A dropped coin does not sit on a HUD surface. It lands where the fight
## ended, pops, and bobs - over floor tiles, over the decorated floor variants, and over the wall
## face at the edge of the room - and on the two light fixtures the wall is the one surface it was
## never measured against. It measured **1.30:1** there on `white` and **1.20:1** on
## `catppuccin-latte`, which is the owner's "gold, hearts and stat orbs are invisible on the light
## theme".
##
## `ThemePalette.WORLD_ROLES` / `WORLD_SURFACES` are the contract this suite holds to, and
## `world_color()` is where it lands: the guard makes a *second* colour for the dungeon and leaves
## the role alone, because `loot` is also the gold counter, a minimap room tint and a status chip,
## and those sit on the HUD plate rather than on a wall.
class_name PickupWorldContrastTest
extends GdUnitTestSuite

const FIXTURES := "res://tests/fixtures/omarchy"
const THEMES: PackedStringArray = [
	"tokyo-night", "gruvbox", "catppuccin", "catppuccin-latte", "nord", "white"
]
const LIGHT_THEMES: PackedStringArray = ["catppuccin-latte", "white"]
## Slack for the last lerp of the guard's search, which lands on the target rather than exactly on
## it.
const EPSILON := 0.01


func _palette(theme: String) -> ThemePalette:
	var toml := ColorsToml.load_file("%s/%s/state/current/theme/colors.toml" % [FIXTURES, theme])
	return ThemePalette.from_colors_toml(toml, theme)


## The guarantee itself, on every shipped fixture and every surface the dungeon paints.
func test_every_pickup_role_clears_every_surface_it_is_drawn_over() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		for role: String in ThemePalette.WORLD_ROLES:
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


## The reported bug, pinned to the surface it was reported on. A light theme's wall is the darkest
## thing in the room and its floor is paper, so this is the pair that decides whether a drop can
## be seen at all - and it is the pair the old guard never looked at.
func test_the_pickup_roles_read_against_the_wall_on_the_light_fixtures() -> void:
	for theme: String in LIGHT_THEMES:
		var p := _palette(theme)
		var wall := p.get_color(&"wall")
		for role: String in ThemePalette.WORLD_ROLES:
			var ratio := ThemePalette.contrast_ratio(p.world_color(StringName(role)), wall)
			(
				assert_float(ratio)
				. override_failure_message(
					(
						"%s: %s on the wall is %.2f:1 (it was 1.30:1 when this was filed)"
						% [theme, role, ratio]
					)
				)
				. is_greater_equal(ThemePalette.WORLD_MIN_CONTRAST - EPSILON)
			)


## ...and the floor reading is not what paid for it. Pushing a role until it clears every surface
## can make it *worse* on the one it usually lands on, which would be the same bug wearing the
## other shoe, so the surface a drop actually lies on is measured on its own.
func test_the_guard_did_not_spend_the_floor_reading() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		for role: String in ThemePalette.WORLD_ROLES:
			for surface: String in ThemePalette.SURFACES:
				var ratio := ThemePalette.contrast_ratio(
					p.world_color(StringName(role)), p.get_color(StringName(surface))
				)
				(
					assert_float(ratio)
					. override_failure_message(
						"%s: %s on %s fell to %.2f:1" % [theme, role, surface, ratio]
					)
					. is_greater_equal(3.0 - EPSILON)
				)


## A dropped coin is drawn from the palette a biome narrowed and a wallpaper nudged, so the guard
## has to survive `derive_environment` as well as the plain load.
func test_a_biome_palette_keeps_the_guard() -> void:
	var keys := PackedStringArray(["orange", "red"])
	for theme: String in THEMES:
		var p := _palette(theme).derive_environment(keys)
		for role: String in ThemePalette.WORLD_ROLES:
			for surface: String in ThemePalette.WORLD_SURFACES:
				var ratio := ThemePalette.contrast_ratio(
					p.world_color(StringName(role)), p.get_color(StringName(surface))
				)
				(
					assert_float(ratio)
					. override_failure_message(
						"%s biome palette: %s on %s is %.2f:1" % [theme, role, surface, ratio]
					)
					. is_greater_equal(ThemePalette.WORLD_MIN_CONTRAST - EPSILON)
				)


## The roles keep their own colour while they move. A light theme takes them a long way down, and
## a dungeon that drops a black coin, a black heart and a black orb has lost the read the shapes
## are only half of - so a theme that carries three different hues still hands back three.
func test_the_roles_keep_their_hue_where_the_theme_has_one() -> void:
	var p := _palette("catppuccin-latte")
	var hues: Array[float] = []
	for role: String in ThemePalette.WORLD_ROLES:
		var c := p.world_color(StringName(role))
		assert_float(c.s).override_failure_message("latte %s lost its chroma" % role).is_greater(
			0.2
		)
		hues.append(c.h)
	for i in range(hues.size()):
		for j in range(i + 1, hues.size()):
			(
				assert_float(TileRamp.hue_distance(hues[i], hues[j]))
				. override_failure_message("latte pickup roles %d and %d share a hue" % [i, j])
				. is_greater(0.05)
			)


## `ensure_contrast_all` walks toward an extreme in tenths and used to stop 8% short of it, which
## left `white`'s `loot` at 2.97:1 against the wall while pure black - the colour it was walking
## toward - cleared 3.07:1. A search that promises the best worst case has to consider its own
## endpoint.
func test_the_search_considers_the_extreme_it_walks_toward() -> void:
	var backgrounds: Array[Color] = [Color("#ffffff"), Color("#5b5b5b")]
	var out := ThemePalette.ensure_contrast_all(Color("#4a4a4a"), backgrounds, 3.0, Color.BLACK)
	(
		assert_float(ThemePalette.worst_contrast(out, backgrounds))
		. override_failure_message("the search stopped short of the endpoint")
		. is_greater_equal(3.0)
	)


## The other half of the same contract: the *role* does not move. `loot` is the coin on the floor
## and it is also the HUD's gold counter, a minimap room tint and a status chip, and those sit on
## the `void` plate. Guarding the role itself instead of deriving a second colour took the `white`
## fixture's three pickup roles to the same pure black and collapsed a pair of status chips, a
## minimap kind and the otter-shell mapping with them.
func test_the_guard_leaves_the_role_the_hud_reads_alone() -> void:
	for theme: String in THEMES:
		var p := _palette(theme)
		for role: String in ThemePalette.WORLD_ROLES:
			for surface: String in ThemePalette.SURFACES:
				var ratio := ThemePalette.contrast_ratio(
					p.get_color(StringName(role)), p.get_color(StringName(surface))
				)
				(
					assert_float(ratio)
					. override_failure_message(
						"%s: the HUD's %s on %s fell to %.2f:1" % [theme, role, surface, ratio]
					)
					. is_greater_equal(3.0 - EPSILON)
				)
	# ...and on a theme that keeps its colour in its accents the three stay apart from each other,
	# which is what the minimap and the status chips read them for.
	var white := _palette("white")
	for role: String in ThemePalette.WORLD_ROLES:
		(
			assert_object(white.get_color(StringName(role)))
			. override_failure_message("white: %s was moved by the world guard" % role)
			. is_not_equal(white.world_color(StringName(role)))
		)


## A palette copy carries the derived colours with it, so a biome/wallpaper palette handed to a
## floor answers `world_color()` rather than falling back to the plain role.
func test_a_copied_palette_keeps_its_world_colours() -> void:
	var p := _palette("white")
	var c := p.copy()
	for role: String in ThemePalette.WORLD_ROLES:
		assert_object(c.world_color(StringName(role))).is_equal(p.world_color(StringName(role)))
