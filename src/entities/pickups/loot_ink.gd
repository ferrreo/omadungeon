## The colours a drop lying in the dungeon paints itself with: its ink, and the halo it wears
## when one ink cannot do the job.
##
## `ThemePalette.world_color()` guards a loot role against every surface the dungeon paints, and
## it is the right guard - but it is measured on the palette's *authored* surfaces, and the room
## is not drawn in those. The lighting layer lays a darkness over the environment (docs 10), and
## a room nobody has walked into carries a shade on top of it, so a wall a drop may land on is
## drawn at `ambient x (1 - unexplored_shade)` of the colour the guard measured. On the two
## light fixtures that is the whole failure: the ink solves to 3.04:1 against the authored wall,
## which is 0.04 of headroom over its own 3.0 line, and the darkness takes it to 2.52:1 - a coin
## the player cannot see on a wall tile (`pickup_frame`, catppuccin-latte and white).
##
## Deepening the ink does not fix it, and that is the point. On the `white` fixture the floor is
## paper and the wall is mid-grey: an ink dark enough for the floor is too close to the drawn
## wall, an ink bright enough for the wall is too close to the floor, and no single colour
## clears 3.0 against both. The guard already knows this - `ensure_contrast_all` degrades to
## "the highest worst contrast available" rather than promising what it cannot give.
##
## So a drop is two colours, not one. The ink is the guard's answer; the halo is a one-pixel
## ring behind it in the opposite direction, and the line is met *per surface* rather than
## globally: whichever of the two the surface is close to, the other one reads. It is drawn only
## where it is needed - when the ink already clears every drawn surface, `halo_for` hands back a
## transparent colour and nothing changes - so on the four dark fixtures, and with the lighting
## layer off anywhere, a drop is exactly the single-colour shape it has always been.
class_name LootInk

## Contrast a drop has to reach against every surface it can land on. The same line
## `ThemePalette.WORLD_MIN_CONTRAST` sets; restated here because this is where it is *met*.
const MIN_CONTRAST := ThemePalette.WORLD_MIN_CONTRAST
## Pixels the halo stands out past the shape it wraps. One: an outline, not a glow. The check
## reads any colour covering `PickupFrameCapture.MIN_RUN` pixels, and a ring one pixel wide
## around a three-pixel body is about twenty.
const HALO_WIDTH := 1.0


## The world surfaces as the lighting layer draws them: each one under the darkness for this
## palette and under the unexplored-room shade as well, because a drop has to be readable in a
## room nobody has entered yet and that is the darkest a floor ever gets. Hands back the
## authored surfaces when the layer is off, so the model and the picture agree either way.
static func surfaces_as_drawn(palette: ThemePalette) -> Array[Color]:
	var out: Array[Color] = []
	if palette == null:
		return out
	var dim := darkness_for(palette)
	for surface: String in ThemePalette.WORLD_SURFACES:
		var c := palette.get_color(StringName(surface))
		out.append(Color(c.r * dim, c.g * dim, c.b * dim, 1.0))
	return out


## How far the lighting layer takes a surface down where a player can still judge it: the shade
## an unentered room stands under, and nothing else. 1.0 when the layer is off.
##
## It used to multiply by the ambient level as well. There is no ambient level now
## (`LightingProfile.unlit_floor`), and using the *unlit* one here would be wrong rather than
## merely stale: an unlit surface is near black, a drop lying on it is near black too (loot takes
## the dark like every other body, `LightRig.loot_mask`), and solving a halo for a pair of
## near-blacks answers a question nobody can see the answer to. The ink is solved where a drop is
## visible at all, which is inside a pool, where a light restores the surface to the level the
## theme authored it at.
static func darkness_for(_palette: ThemePalette) -> float:
	if not LightingProfile.enabled():
		return 1.0
	return 1.0 - LightingProfile.resolve().unexplored_shade


## The halo `ink` needs on `palette`, or a fully transparent colour when it needs none.
##
## The direction is away from the ink: a dark ink gets a light ring and a light ink a dark one,
## pushed until it clears `MIN_CONTRAST` against every drawn surface the ink does not already
## clear. When even the extreme cannot clear one of them, the extreme is what comes back, which
## is the most readable ring available - the same degradation `ensure_contrast_all` makes.
static func halo_for(ink: Color, palette: ThemePalette) -> Color:
	var surfaces := surfaces_as_drawn(palette)
	if surfaces.is_empty():
		return Color.TRANSPARENT
	if ThemePalette.worst_contrast(ink, surfaces) >= MIN_CONTRAST:
		return Color.TRANSPARENT
	var toward := Color.BLACK if ThemePalette.relative_luminance(ink) > 0.5 else Color.WHITE
	var ring := ThemePalette.ensure_contrast_all(ink, surfaces, MIN_CONTRAST, toward)
	# `ensure_contrast_all` may walk the *other* way when the first direction cannot clear the
	# surfaces; a ring on the ink's own side of the value range is no ring at all, so the
	# extreme is taken instead. It is the colour the drop needs behind it either way.
	if absf(ThemePalette.relative_luminance(ring) - ThemePalette.relative_luminance(ink)) < 0.1:
		ring = toward
	return Color(ring.r, ring.g, ring.b, 1.0)


## Whether `halo` is one to paint (`halo_for` returns a transparent colour for "none needed").
static func has_halo(halo: Color) -> bool:
	return halo.a > 0.0
