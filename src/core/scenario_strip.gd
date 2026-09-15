## Lays a series of captured frames side by side as one picture.
##
## Lives outside `TestScenarios` because it is a pure image operation with no scenario state,
## and because that file sits against the 1200-line cap: the music scenarios grew a guarantee
## and this was the part that owed nobody anything by being in there.
class_name ScenarioStrip
extends RefCounted

## Each frame is drawn at a third of its size, in order, left to right.
const SCALE_DIVISOR := 3


## Returns the strip, or null when there is nothing to lay out.
static func build(frames: Array[Image]) -> Image:
	if frames.is_empty():
		return null
	var w := frames[0].get_width() / SCALE_DIVISOR
	var h := frames[0].get_height() / SCALE_DIVISOR
	if w <= 0 or h <= 0:
		return null
	var strip := Image.create(w * frames.size(), h, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var small := frames[i].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(w, h, Image.INTERPOLATE_BILINEAR)
		strip.blit_rect(small, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	return strip
