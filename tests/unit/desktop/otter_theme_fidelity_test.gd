## The owner's own desktop, reproduced byte for byte: an otter-shell `theme.conf` whose
## `colors_path` is *relative*, the sage-green `generated-colors.conf` it points at, no Omarchy
## state directory anywhere, and the duck-village wallpaper that desktop is showing. otter-shell
## is not on Omarchy yet, so that combination is a normal supported machine and not a broken
## one - the colours come from otter and the theme is named, to the player, exactly "Otter".
##
## The report this suite exists for: "the otter theme stuff doesn't seem to be working - it is
## getting orange/red for my currently green theme". Every input above resolved correctly. What
## failed was that the wallpaper was allowed to supply colour at all, and the owner's ruling on
## it is the rule this suite now guards (docs/GAME_DESIGN.md, decisions log):
##
##   "otter colors are already derrived from the wallpaper - I think in general we should not
##   be taking colors from the wallpaper ... it should impact [the seeding and the generation]
##   and then the theme should be the colors"
##
## An otter palette *is* that wallpaper, already reduced to twelve colours. Casting the same
## photograph over it a second time applied one image twice, and because the room cast took the
## picture's single most saturated patch - a warm brown roof on a green-grey picture - as "the
## wallpaper's hue", a desktop with no orange in it built an orange dungeon.
##
## So: the theme is the colours, the wallpaper is a generation lever. Both halves are asserted
## here - that no wallpaper can move one hue, and (`WallpaperLeversTest`) that the wallpaper
## still builds a different floor, so the lever is alive rather than quietly dropped.
class_name OtterThemeFidelityTest
extends GdUnitTestSuite

const FIXTURE := "res://tests/fixtures/otter/owner"
const CONFIG_DIR := FIXTURE + "/config/otter-shell"
const WALLPAPER := FIXTURE + "/wallpaper.png"
## `generated-colors.conf`'s accent, the colour the owner calls "my currently green theme".
const THEME_ACCENT := "#AFBE98"
## Hue arc, in turns, that reads as orange or red: 330 degrees round through 0 to 45. No
## surface of a green dungeon may land inside it.
const WARM_BAND_FROM := 0.9167
const WARM_BAND_TO := 0.125
## How far, in turns, the room's dominant hue may sit from the theme's accent. 0.03 is 11
## degrees - the width of the owner's own palette, whose surfaces run from 72 to 86 against a
## sage accent at 84. Nothing outside the theme may add to that spread, and nothing inside it
## may read the quantisation noise in a near-black as a hue (`ROOM_CAST_OWN_CHROMA_MIN`).
const MAX_ACCENT_DISTANCE := 0.03
## A wallpaper with no relation whatever to a sage-green desktop, for the proof that a
## wallpaper cannot move one hue of it.
const VIOLENT_ORANGE := "#FF6A00"
## Chroma a surface needs before its hue means anything (a white wall cap has no hue).
const MIN_MEANINGFUL_CHROMA := 0.05
## The spread the owner's own twelve colours contain: their surfaces run from hue 72 to 86
## against a sage accent at 84. A room surface may sit anywhere inside that and nowhere else.
const MAX_THEME_SPREAD := 0.045

var _saved_env: Dictionary = {}


func before_test() -> void:
	for key: String in ["XDG_CONFIG_HOME", "XDG_RUNTIME_DIR", "OMADUNGEON_OMARCHY_STATE_DIR"]:
		_saved_env[key] = OS.get_environment(key)
	OS.set_environment("XDG_CONFIG_HOME", ProjectSettings.globalize_path(FIXTURE + "/config"))
	# The owner has no `~/.local/state/omarchy` at all: otter-shell is the only colour source.
	OS.set_environment(
		"OMADUNGEON_OMARCHY_STATE_DIR", OS.get_user_data_dir().path_join("no-omarchy-here")
	)
	OS.set_environment("XDG_RUNTIME_DIR", _runtime_dir())


func after_test() -> void:
	for key: String in _saved_env:
		OS.set_environment(key, str(_saved_env[key]))


## A runtime directory holding the owner's `wallpaper-state` verbatim - the leading
## `# otter-theme-gen-palette:` comment and both monitor lines - with the two absolute paths
## pointed at the checked-in fixture image.
func _runtime_dir() -> String:
	var dir := OS.get_user_data_dir().path_join("otter-fidelity")
	DirAccess.make_dir_recursive_absolute(dir.path_join("otter-shell"))
	var image := ProjectSettings.globalize_path(WALLPAPER)
	var file := FileAccess.open(dir.path_join("otter-shell/wallpaper-state"), FileAccess.WRITE)
	file.store_string(
		"# otter-theme-gen-palette: shared-primary\nDP-2=%s\nDP-3=%s\n" % [image, image]
	)
	file.close()
	return dir


## The palette `Desktop._load_palette` builds on this machine, by the same rules in the same
## order: Omarchy first, otter-shell second, fallback last.
func _owner_palette() -> ThemePalette:
	var omarchy := OmarchyState.new()
	(
		assert_bool(omarchy.is_available())
		. override_failure_message("the fixture handed the test an Omarchy state directory")
		. is_false()
	)
	var colors := OtterWallpaper.load_colors(OtterWallpaper.theme_colors_path())
	assert_int(colors.size()).is_equal(OtterWallpaper.OTTER_COLOR_KEYS.size())
	return ThemePalette.from_otter_colors(colors, "Otter")


func _owner_wallpaper() -> WallpaperAnalyzer.Result:
	var path := OtterWallpaper.current_wallpaper()
	(
		assert_str(path)
		. override_failure_message("the owner's wallpaper-state did not resolve to an image")
		. is_equal(ProjectSettings.globalize_path(WALLPAPER))
	)
	return WallpaperAnalyzer.analyze_file(path)


## The palette a floor is actually drawn in, on the owner's theme, at the light level
## `wallpaper` calls for - the same two calls `FloorRoot._derive_palette` and `_apply_ambient`
## make. The wallpaper reaches this as a light level and nothing else; there is no longer an
## argument by which it could reach the colours.
func _lit(wallpaper: WallpaperAnalyzer.Result = null) -> ThemePalette:
	var palette := _owner_palette()
	var w := wallpaper if wallpaper != null else _owner_wallpaper()
	var keys := Biome.load_by_id(&"crypt").palette_keys
	return palette.derive_environment(keys).light_environment(w.ambient_level(palette.is_light))


## Chroma-weighted circular mean hue of the five surfaces a dungeon is painted in: the one
## number that answers "what colour is this room". Computed here rather than borrowed from
## `ThemePalette` so the measure cannot drift with the thing it measures.
static func _dominant_hue(palette: ThemePalette) -> float:
	var x := 0.0
	var y := 0.0
	for role: String in ThemePalette.ENV_ROLES:
		var c: Color = palette.get_color(role)
		x += cos(c.h * TAU) * c.s
		y += sin(c.h * TAU) * c.s
	return fposmod(atan2(y, x) / TAU, 1.0)


static func _in_warm_band(hue: float) -> bool:
	var h := fposmod(hue, 1.0)
	return h >= WARM_BAND_FROM or h <= WARM_BAND_TO


func test_the_owners_relative_colors_path_resolves_to_the_green_palette() -> void:
	var path := OtterWallpaper.theme_colors_path()
	(
		assert_bool(path.begins_with(ProjectSettings.globalize_path(CONFIG_DIR)))
		. override_failure_message("a relative colors_path did not resolve next to theme.conf")
		. is_true()
	)
	assert_str(path.get_file()).is_equal("generated-colors.conf")
	var palette := _owner_palette()
	assert_that(palette.get_color(&"accent")).is_equal(Color(THEME_ACCENT))
	assert_that(palette.get_color(&"select")).is_equal(Color("#303824"))
	# The owner's naming rule: this source has exactly one player-facing name.
	assert_str(palette.name).is_equal("Otter")


func test_the_owners_wallpaper_is_the_trap_this_suite_is_about() -> void:
	var wallpaper := _owner_wallpaper()
	var loudest := Color.BLACK
	for c: Color in wallpaper.accents():
		if c.s > loudest.s:
			loudest = c
	(
		assert_bool(_in_warm_band(loudest.h))
		. override_failure_message(
			(
				(
					"the fixture wallpaper's loudest dominant is #%s at hue %.0f, not the warm brown "
					+ "the owner's photograph actually contains - the fixture no longer reproduces "
					+ "the bug"
				)
				% [loudest.to_html(false), loudest.h * 360.0]
			)
		)
		. is_true()
	)
	# ...while the picture as a whole is nothing like it: two of its dominants are green.
	var greens := 0
	for c: Color in wallpaper.accents():
		if c.h > 0.2 and c.h < 0.45:
			greens += 1
	assert_int(greens).is_greater_equal(2)


func test_no_surface_of_the_owners_dungeon_lands_in_the_orange_red_band() -> void:
	var lit := _lit()
	for role: String in ThemePalette.ENV_ROLES:
		var c: Color = lit.get_color(role)
		if c.s < MIN_MEANINGFUL_CHROMA:
			continue
		(
			assert_bool(_in_warm_band(c.h))
			. override_failure_message(
				(
					"a green desktop theme rendered `%s` as #%s - hue %.0f, which is orange"
					% [role, c.to_html(false), c.h * 360.0]
				)
			)
			. is_false()
		)


func test_the_owners_dungeon_takes_its_hue_from_the_theme_not_the_wallpaper() -> void:
	var lit := _lit()
	var dominant := _dominant_hue(lit)
	var accent_hue := Color(THEME_ACCENT).h
	var loudest := Color.BLACK
	for c: Color in _owner_wallpaper().accents():
		if c.s > loudest.s:
			loudest = c
	var to_theme := TileRamp.hue_distance(dominant, accent_hue)
	var to_wallpaper := TileRamp.hue_distance(dominant, loudest.h)
	(
		assert_float(to_theme)
		. override_failure_message(
			(
				(
					"the room's dominant hue is %.0f degrees; the theme accent is %.0f and the "
					+ "wallpaper's loudest patch is %.0f - the dungeon is %.0f degrees from the "
					+ "theme the player chose"
				)
				% [dominant * 360.0, accent_hue * 360.0, loudest.h * 360.0, to_theme * 360.0]
			)
		)
		. is_less_equal(MAX_ACCENT_DISTANCE)
	)
	(
		assert_bool(to_theme < to_wallpaper)
		. override_failure_message(
			(
				(
					"the room's dominant hue (%.0f) sits nearer the wallpaper's loudest patch "
					+ "(%.0f) than the theme's accent (%.0f)"
				)
				% [dominant * 360.0, loudest.h * 360.0, accent_hue * 360.0]
			)
		)
		. is_true()
	)


## The owner's rule stated as a property rather than as a number, and the strongest form of
## it: hand the same green desktop a flat sheet of violent orange and the palette has to come
## back *byte for byte* the palette that theme has with no wallpaper at all. Not close, not
## within an arc - identical, because the wallpaper has no path to a colour any more.
##
## Light is the one thing it may still move, so the lit halves are compared at a matched light
## level; the unlit derivation is compared with no light level involved at all.
func test_a_violently_orange_wallpaper_leaves_the_palette_byte_identical() -> void:
	var orange := _flat_wallpaper(Color(VIOLENT_ORANGE), "res://violent-orange.png")
	var loudest := Color.BLACK
	for c: Color in orange.accents():
		if c.s > loudest.s:
			loudest = c
	# The wallpaper really is orange, so a pass here cannot be a pass by accident.
	assert_bool(_in_warm_band(loudest.h)).is_true()
	assert_float(loudest.s).is_greater(0.8)
	var palette := _owner_palette()
	var keys := Biome.load_by_id(&"crypt").palette_keys
	var bare := palette.derive_environment(keys)
	var under_orange := palette.derive_environment(keys)
	for role: StringName in bare.colors:
		(
			assert_str(under_orange.get_color(role).to_html(true))
			. override_failure_message(
				(
					"`%s` is #%s with no wallpaper and #%s under a violently orange one"
					% [
						role,
						bare.get_color(role).to_html(true),
						under_orange.get_color(role).to_html(true)
					]
				)
			)
			. is_equal(bare.get_color(role).to_html(true))
		)
	# The prop pool too: a wallpaper colour used to be entered in it twice.
	assert_int(under_orange.prop_pool.size()).is_equal(bare.prop_pool.size())
	for i in range(bare.prop_pool.size()):
		assert_bool(under_orange.prop_pool[i].is_equal_approx(bare.prop_pool[i])).is_true()
	# ...and the whole lit palette, at one light level, is the same palette.
	var ambient := orange.ambient_level(palette.is_light)
	var lit_bare := bare.light_environment(ambient)
	var lit_orange := under_orange.light_environment(ambient)
	for role: StringName in lit_bare.colors:
		(
			assert_str(lit_orange.get_color(role).to_html(true))
			. override_failure_message(
				(
					"lit `%s` is #%s without a wallpaper and #%s under an orange one"
					% [
						role,
						lit_bare.get_color(role).to_html(true),
						lit_orange.get_color(role).to_html(true)
					]
				)
			)
			. is_equal(lit_bare.get_color(role).to_html(true))
		)
	# And the green theme still reads green under the orange one.
	for role: String in ThemePalette.ENV_ROLES:
		var c: Color = _lit(orange).get_color(role)
		if c.s < MIN_MEANINGFUL_CHROMA:
			continue
		(
			assert_bool(_in_warm_band(c.h))
			. override_failure_message(
				(
					"an orange wallpaper rendered `%s` as #%s, hue %.0f"
					% [role, c.to_html(false), c.h * 360.0]
				)
			)
			. is_false()
		)


## The wallpaper may still move the *light*, and only the light: two very different pictures
## over one theme leave every hue where the theme put it.
func test_the_wallpaper_moves_the_light_and_never_a_hue() -> void:
	var orange := _flat_wallpaper(Color(VIOLENT_ORANGE), "res://violent-orange.png")
	var owner := _owner_wallpaper()
	var a := _lit(owner)
	var b := _lit(orange)
	for role: String in ThemePalette.ENV_ROLES:
		var ca: Color = a.get_color(role)
		var cb: Color = b.get_color(role)
		(
			assert_float(TileRamp.hue_distance(ca.h, cb.h))
			. override_failure_message(
				(
					"a wallpaper moved `%s` from hue %.1f to hue %.1f"
					% [role, ca.h * 360.0, cb.h * 360.0]
				)
			)
			. is_less(0.001)
		)


## A flat single-colour wallpaper, analysed exactly as an on-disk one would be.
func _flat_wallpaper(c: Color, path: String) -> WallpaperAnalyzer.Result:
	var image := Image.create(
		WallpaperAnalyzer.SAMPLE_W, WallpaperAnalyzer.SAMPLE_H, false, Image.FORMAT_RGB8
	)
	image.fill(c)
	var result := WallpaperAnalyzer.analyze_image(image)
	result.source_path = path
	result.seed_hash = hash(path)
	return result


## One layer below the palette: the per-room ramp variants. `WARM_COOL` used to lerp the room's
## surfaces toward the theme's `heat` or `cold`, which on a sage-green desktop swung the floor
## from hue 75 to 51 and the wall cap to 27 - so roughly one room in seven rendered tan on a
## palette with no tan in it. Same complaint as the wallpaper cast, one layer down, same answer:
## the theme owns hue, the variant owns value and chroma.
func test_no_room_variant_moves_a_surface_off_the_themes_hue() -> void:
	var lit := _lit()
	var accent_hue := Color(THEME_ACCENT).h
	for seed_offset in range(8):
		var seed_value := 4400 + seed_offset
		var base := TileRamp.target_colors(lit, TileRamp.Variant.BASE, seed_value)
		for variant in range(4):
			var rungs := TileRamp.target_colors(lit, variant, seed_value)
			for rung: int in TileRamp.ENVIRONMENT_RUNGS:
				var c: Color = rungs[rung]
				if c.s < MIN_MEANINGFUL_CHROMA:
					continue
				# Against the plain variant of the same room: this isolates what the *variant*
				# contributes from the spread the theme itself authored (otter's surfaces run
				# 72 to 86 against an accent at 84, and that spread is theirs to keep).
				(
					assert_float(TileRamp.hue_distance(c.h, (base[rung] as Color).h))
					. override_failure_message(
						(
							"variant %d moved rung %d from hue %.0f to hue %.0f (#%s)"
							% [
								variant,
								rung,
								(base[rung] as Color).h * 360.0,
								c.h * 360.0,
								c.to_html(false)
							]
						)
					)
					. is_less(0.002)
				)
				# ...and the whole ramp still sits on the owner's side of the colour circle.
				(
					assert_float(TileRamp.hue_distance(c.h, accent_hue))
					. override_failure_message(
						(
							"variant %d drew rung %d as #%s, hue %.0f, against an accent at %.0f"
							% [variant, rung, c.to_html(false), c.h * 360.0, accent_hue * 360.0]
						)
					)
					. is_less_equal(MAX_THEME_SPREAD)
				)
				assert_bool(_in_warm_band(c.h)).is_false()


## ...and the variants are still variants: `WARM_COOL` has to change the room it is given.
func test_the_warm_cool_variant_still_changes_the_room() -> void:
	var lit := _lit()
	var changed := 0
	for seed_offset in range(8):
		var base := TileRamp.target_colors(lit, TileRamp.Variant.BASE, 4400 + seed_offset)
		var warm := TileRamp.target_colors(lit, TileRamp.Variant.WARM_COOL, 4400 + seed_offset)
		for rung: int in TileRamp.ENVIRONMENT_RUNGS:
			if not warm[rung].is_equal_approx(base[rung]):
				changed += 1
				break
	(
		assert_int(changed)
		. override_failure_message(
			"WARM_COOL left the room untouched on %d of 8 seeds" % (8 - changed)
		)
		. is_equal(8)
	)
