## The class sheets, asserted on the shipped PNGs: a character carries exactly one weapon, and
## the four classes are still told apart without one.
##
## The owner played a build in which every class sprite had a weapon painted into its 16x16 art
## *and* the equipped weapon drawn on top of it - a Fighter with a blade at the hip and a blade
## in the hand, a Ranger with a bow on the back and a bow in the hand. An anchoring pass is not
## enough to fix that: the second weapon is in the art, so the guard has to be on the art.
##
## The measurable form of "only one weapon" is the *hand region*. `WeaponController` puts the
## grip on the hand at `WeaponGrip.reach` px along the aim from the body centre, and the weapon
## is drawn from there outward. Sprites are authored facing right and mirrored by the carry
## state, so in sheet coordinates the hand is always on the +X side: anything the class art
## paints past it, at the height the arm carries, is a second object held out in front. Nothing
## else in the sheet is constrained - a shield strapped on the far arm, a cloak, a quiver strap
## are all gear rather than weapons, and they are what the silhouettes are built from now.
class_name ClassArtTest
extends GdUnitTestSuite

const CLASSES: PackedStringArray = ["fighter", "ranger", "wizard", "oligarch"]
const CELL := 16
## Sheet rows the player sees while carrying a weapon, with the frame count of each: idle and
## run. The dodge, hurt and death rows scale and rotate the whole body, so a column band means
## nothing in them.
const CARRY_ROWS: Dictionary = {0: 4, 1: 6}
## Centre of the cell: `WeaponGrip.reach`/`lateral` are measured from the body's own origin,
## which is where a centred `Sprite2D` puts the middle of the cell.
const BODY_CENTRE := 8.0
## Ceiling on how much of its silhouette one class may share with another. Two humanoids on a
## 16x16 grid share most of their pixels by construction; what has to differ is the gear, and
## these are the numbers the shipped sheets measure (0.848 whole body, 0.826 head).
const SILHOUETTE_OVERLAP := 0.90
const HEAD_OVERLAP := 0.88
## Rows the headgear lives in: the hood, the pointed hat, the top hat, the crested helm.
const HEAD_ROWS := 5
## The Fighter's off-hand gear inside the idle cell: x 0-5, y 8-12 (`tools/art/characters.py`).
const SHIELD_COLS := 6
const SHIELD_ROWS := Vector2i(8, 12)
## Colours the shield has to draw before it is an object rather than a block: an outline, a lit
## rim, a face, a shaded face and a boss. Counted on the drawn pixels of the cell.
const SHIELD_MIN_COLOURS := 4


func _load(path: String) -> Image:
	assert_bool(FileAccess.file_exists(path)).override_failure_message("missing " + path).is_true()
	var img := Image.new()
	assert_int(img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))).is_equal(OK)
	return img


func _sheet(cls: String) -> Image:
	return _load("res://assets/sprites/player/%s.png" % cls)


## First cell column a held weapon reaches: the nearest hand any shipped grip puts it on.
func _hand_column() -> int:
	var reach := 99.0
	for entry: WeaponGrip in WeaponGrips.shared().entries:
		if entry != null:
			reach = minf(reach, entry.reach)
	assert_float(reach).override_failure_message("no grips shipped").is_less(99.0)
	return int(ceil(BODY_CENTRE + reach))


## Cell rows the hand travels through: the aim line plus the widest lateral offset any grip
## carries, which is how far off that line a weapon is ever held.
func _hand_rows() -> Vector2i:
	var lateral := 0.0
	for entry: WeaponGrip in WeaponGrips.shared().entries:
		if entry != null:
			lateral = maxf(lateral, absf(entry.lateral))
	return Vector2i(int(floor(BODY_CENTRE - lateral)), int(ceil(BODY_CENTRE + lateral)))


## Opaque mask of one cell, as a flat row-major array of bools.
func _mask(img: Image, col: int, row: int, rows: int = CELL) -> Array:
	var out: Array = []
	for y in range(rows):
		for x in range(CELL):
			out.append(img.get_pixel(col * CELL + x, row * CELL + y).a > 0.0)
	return out


func _overlap(a: Array, b: Array) -> float:
	var both := 0
	var either := 0
	for i in range(a.size()):
		if bool(a[i]) and bool(b[i]):
			both += 1
		if bool(a[i]) or bool(b[i]):
			either += 1
	return float(both) / float(either) if either > 0 else 1.0


## The one that would have caught the shipped double weapons: every class painted into the
## columns past the hand - the Fighter's blade at x 13-14, the Ranger's bow at 13-14, the
## Wizard's staff at 14-15, the Oligarch's cane at 13.
func test_no_class_sheet_paints_a_weapon_into_the_hand() -> void:
	var first := _hand_column()
	var rows := _hand_rows()
	for cls: String in CLASSES:
		var img := _sheet(cls)
		for row: int in CARRY_ROWS:
			for col in range(int(CARRY_ROWS[row])):
				for y in range(rows.x, rows.y + 1):
					for x in range(first, CELL):
						var px := img.get_pixel(col * CELL + x, row * CELL + y)
						(
							assert_bool(px.a > 0.0)
							. override_failure_message(
								(
									(
										"%s row %d frame %d paints (%d,%d), past the hand at x=%d: "
										+ "the player would carry that and their own weapon at once"
									)
									% [cls, row, col, x, y, first]
								)
							)
							. is_false()
						)


## The other half of the same change: with the weapons gone the classes still have to be four
## different people. Checked on the silhouette alone, so it holds when a theme, a flash or a
## colour-blind filter has taken the colour away.
func test_the_four_classes_keep_distinct_silhouettes() -> void:
	var bodies: Dictionary = {}
	var heads: Dictionary = {}
	for cls: String in CLASSES:
		var img := _sheet(cls)
		bodies[cls] = _mask(img, 0, 0)
		heads[cls] = _mask(img, 0, 0, HEAD_ROWS)
	for i in range(CLASSES.size()):
		for j in range(i + 1, CLASSES.size()):
			var a: String = CLASSES[i]
			var b: String = CLASSES[j]
			(
				assert_float(_overlap(bodies[a], bodies[b]))
				. override_failure_message("%s and %s are the same shape" % [a, b])
				. is_less(SILHOUETTE_OVERLAP)
			)
			(
				assert_float(_overlap(heads[a], heads[b]))
				. override_failure_message("%s and %s wear the same headgear silhouette" % [a, b])
				. is_less(HEAD_OVERLAP)
			)


## A class still has to be a drawn character, not an empty cell the weapon hangs off.
func test_every_class_still_draws_a_body() -> void:
	for cls: String in CLASSES:
		var img := _sheet(cls)
		var opaque := 0
		for painted: bool in _mask(img, 0, 0):
			if painted:
				opaque += 1
		(
			assert_int(opaque)
			. override_failure_message("%s idle frame is nearly empty" % cls)
			. is_greater(100)
		)


# ------------------ the Fighter's off-hand gear is gear (owner report 3, round 3)


## With the sword taken out of the class art the Fighter's silhouette leans on the shield, and
## what shipped was not one: a flat 4x4 block painted in the *helm crest's* red with a single
## white pixel in it, which on a dark floor was the brightest thing on the player and read as a
## held object rather than as strapped gear. A shield has a rim, a face and a boss, and it is
## not painted in the colour the character's plume is.
func test_the_fighters_shield_is_shaped_gear_and_not_the_crest_in_a_box() -> void:
	var img := _sheet("fighter")
	var crest := img.get_pixel(7, 0)
	assert_float(crest.a).is_greater(0.5)
	var shades: Dictionary = {}
	for y in range(SHIELD_ROWS.x, SHIELD_ROWS.y + 1):
		for x in range(SHIELD_COLS):
			var px := img.get_pixel(x, y)
			if px.a < 0.5:
				continue
			(
				assert_bool(px.is_equal_approx(crest))
				. override_failure_message(
					"the shield at %d,%d is painted in the helm crest's own colour" % [x, y]
				)
				. is_false()
			)
			shades[px.to_html(false)] = true
	(
		assert_int(shades.size())
		. override_failure_message(
			(
				"the shield draws %d colours - a flat block, not a rim, a face and a boss"
				% shades.size()
			)
		)
		. is_greater_equal(SHIELD_MIN_COLOURS)
	)
	# ... and it is not the brightest thing on the character either.
	var brightest := 0.0
	var shield_peak := 0.0
	for y in range(CELL):
		for x in range(CELL):
			var px := img.get_pixel(x, y)
			if px.a < 0.5:
				continue
			var lum := ThemePalette.relative_luminance(px)
			brightest = maxf(brightest, lum)
			if x < SHIELD_COLS and y >= SHIELD_ROWS.x and y <= SHIELD_ROWS.y:
				shield_peak = maxf(shield_peak, lum)
	(
		assert_float(shield_peak)
		. override_failure_message("the shield is still the brightest thing on the Fighter")
		. is_less(brightest)
	)
