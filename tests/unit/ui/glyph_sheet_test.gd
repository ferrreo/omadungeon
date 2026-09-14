## The pad glyph sheet, read the way a player reads it: as pixels.
##
## `keycap_legibility_test` guards the labels the game *draws* over a key-cap. This guards the
## labels that are baked into `assets/sprites/ui/glyphs.png` itself, which nothing checked at
## all - and the two cells it matters most for were smears. LB and RB were a 12x6 bar with a
## two-character label blitted into it: the label's bottom row landed on the bar's own bottom
## border and its right edge touched the right one, so the strokes fused with the outline. They
## are the HUD's two ability prompts (`active_1` is LB, `active_2` is RB) and the Controls
## page's shoulder rows, which made them the two most-looked-at glyphs in the game.
##
## The invariant is the one that broke: **every pixel of a baked label has button face on all
## four sides of it.** A stroke touching the outline reads as part of the outline; a stroke
## touching transparency has been cut off by the edge of the button. Neither is legible at the
## 480x270 internal resolution, and both are things a generator can do by accident.
class_name GlyphSheetTest
extends GdUnitTestSuite

## Cells whose sprite carries a baked label rather than being drawn blank for the game to
## write over. Every one of them is checked, not just the two that were broken.
const LABELLED_CELLS: Array[int] = [
	InputGlyphs.Cell.A,
	InputGlyphs.Cell.B,
	InputGlyphs.Cell.X,
	InputGlyphs.Cell.Y,
	InputGlyphs.Cell.LB,
	InputGlyphs.Cell.RB,
	InputGlyphs.Cell.LT,
	InputGlyphs.Cell.RT,
	InputGlyphs.Cell.LSTICK,
	InputGlyphs.Cell.RSTICK,
]
## Name of each cell, for a failure that says which glyph stopped reading.
const CELL_NAMES: Array[String] = [
	"A",
	"B",
	"X",
	"Y",
	"LB",
	"RB",
	"LT",
	"RT",
	"LStick",
	"RStick",
]
## How white a pixel has to be to count as label ink rather than as the button under it.
const INK_MIN := 0.9
## How dark an opaque pixel has to be to count as the sprite's outline.
const OUTLINE_MAX := 0.16
## Ink pixels the thinnest single-character label has: an "L" in the 3x5 micro font is seven.
## The bar only has to catch a cell whose label vanished, not measure how fat it is.
const MIN_INK_PIXELS := 6


func _sheet_image() -> Image:
	var texture := UiTheme.load_texture(InputGlyphs.SHEET_PATH)
	assert_object(texture).is_not_null()
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	return image


static func _is_ink(px: Color) -> bool:
	return px.a > 0.99 and px.r >= INK_MIN and px.g >= INK_MIN and px.b >= INK_MIN


static func _is_face(px: Color) -> bool:
	if px.a < 0.99:
		return false
	return maxf(px.r, maxf(px.g, px.b)) > OUTLINE_MAX


func test_every_baked_label_sits_on_the_button_and_not_on_its_edge() -> void:
	var image := _sheet_image()
	var cell := InputGlyphs.CELL
	for i in LABELLED_CELLS.size():
		var index: int = LABELLED_CELLS[i]
		var ink := 0
		var touching := 0
		var first := ""
		for y in cell:
			for x in cell:
				if not _is_ink(image.get_pixel(index * cell + x, y)):
					continue
				ink += 1
				for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var nx := x + step.x
					var ny := y + step.y
					var inside := nx >= 0 and nx < cell and ny >= 0 and ny < cell
					var neighbour := (
						image.get_pixel(index * cell + nx, ny) if inside else Color(0, 0, 0, 0)
					)
					if _is_face(neighbour):
						continue
					touching += 1
					if first.is_empty():
						first = "(%d,%d) -> (%d,%d)" % [x, y, nx, ny]
		(
			assert_int(ink)
			. override_failure_message("the %s glyph has no label ink at all" % CELL_NAMES[i])
			. is_greater_equal(MIN_INK_PIXELS)
		)
		(
			assert_int(touching)
			. override_failure_message(
				(
					"%s: %d label pixels merge with the outline or the void, first at %s"
					% [CELL_NAMES[i], touching, first]
				)
			)
			. is_equal(0)
		)


## The two the HUD spends the whole run showing. Named on their own so a regression says
## "the ability prompts stopped reading" rather than "a glyph changed".
func test_the_hud_ability_prompts_are_the_shoulder_cells() -> void:
	InputGlyphs.set_device(InputGlyphs.Device.GAMEPAD)
	assert_int(InputGlyphs.cell_for(&"active_1")).is_equal(int(InputGlyphs.Cell.LB))
	assert_int(InputGlyphs.cell_for(&"active_2")).is_equal(int(InputGlyphs.Cell.RB))
	InputGlyphs.set_device(InputGlyphs.Device.KEYBOARD)


## A bumper and a trigger have to be two silhouettes, not one bar with different letters: the
## Controls page lists LB, RB, LT and RT within four rows of each other.
func test_the_bumpers_and_the_triggers_are_different_shapes() -> void:
	var image := _sheet_image()
	var cell := InputGlyphs.CELL
	var bumper := _silhouette(image, InputGlyphs.Cell.LB)
	var trigger := _silhouette(image, InputGlyphs.Cell.LT)
	var same := 0
	for y in cell:
		for x in cell:
			if bumper[y * cell + x] == trigger[y * cell + x]:
				same += 1
	(
		assert_int(same)
		. override_failure_message("the bumper and the trigger draw the same silhouette")
		. is_less(cell * cell)
	)


## Which pixels of a cell are opaque at all, as a flat array of bools.
func _silhouette(image: Image, index: int) -> Array[bool]:
	var out: Array[bool] = []
	var cell := InputGlyphs.CELL
	for y in cell:
		for x in cell:
			out.append(image.get_pixel(index * cell + x, y).a > 0.5)
	return out
