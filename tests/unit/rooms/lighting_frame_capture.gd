## The lighting layer measured on drawn frames: the cost of a frame at each quality and the
## legibility of the floor under the darkness, on the theme fixture the run was given.
##
## A real generated floor (floor 1 of the fixture theme's own parameters) is built in the main
## viewport with a camera on the start room, at each of the three qualities in turn - OFF is
## the floor as it was before the layer existed, LOW adds darkness, lanterns and emitters,
## HIGH casts shadows from the nearest `LightingProfile.shadow_casters` lights - and:
##   * the wall-clock cost of `FRAMES` frames is sampled (`FrameSampler`), vsync off, so the
##     number is what the renderer spent and not what the compositor paced it to. On the
##     harness that is llvmpipe, so it is a software-rasteriser figure, honest about that;
##   * one PNG is written per quality, `tests/out/lighting_<quality>[_<theme>].png`;
##   * at HIGH the frame is measured against the rule the round was built on - every lit pixel
##     has a source you can point at, and the rest is dark:
##       - the floor the player is *fighting on* (within `FIGHT_RADIUS`, which is the reach of a
##         weapon rather than the width of a room) has to be `PLAYER_POOL_MIN` times brighter
##         than the same tiles with the player's own light switched off. This is the playability
##         line, and it is a guarantee about the light the player is *carrying*: whatever else is
##         true, you can see what is next to you;
##       - the darkest quarter of the floor in view has to be **under** `UNLIT_SHARE` of the
##         level the theme authored its floor at. This is the new one and it is the point of the
##         round: with no ambient left, unlit ground is genuinely unlit, and a check that only
##         has a brightness floor under it would pass just as happily on the wash the owner
##         deleted;
##       - the lantern pools have to lift the floor they fall on above the floor between them,
##         so a lantern can never be decoration;
##       - on a light theme the player's pool may not blow the paper floor out
##         (`POOL_RESTORE_MAX`).
##     Nothing here is an absolute luminance except the crush floor: tokyo-night authors a floor
##     at 0.08 and white one at 1.00, and a pool restores each of them through its own light's
##     colour, so one absolute number could only ever be right for one of them.
## The numbers go to `tests/out/lighting_perf[_<theme>].txt`; exit 2 when a floor is under
## its legibility line, 0 otherwise. `tools/capture-scene.sh lighting_frame [theme]` runs it.
class_name LightingFrameCapture
extends Node

const FRAMES := 180
const WARMUP := 20
const SETTLE_SECONDS := 0.6
## The two lines the round turns on, and they are a pair: how much of the light on the ground the
## player is standing on comes from the light *they are carrying*, and the most of the theme's own
## floor the darkest quarter of the visible floor may keep.
##
## Either on its own is satisfied by the thing the owner deleted. An ambient wash passes any
## brightness line; a black screen passes any darkness ceiling. Together they say "pools of light
## with real dark between them, and one of the pools moves with you", which is the sentence the
## round was given.
##
## The lit line is measured by switching the player's own light off and taking the same tiles
## again, rather than by comparing the lit floor with the dark. A ratio against the dark is not a
## guarantee about the player: a room whose torches happen to reach the spawn satisfies it while
## the thing in the player's hand does nothing. Measured with the pool on and off: x9.6 on
## tokyo-night, x7.5 on gruvbox, x9.1 on catppuccin-latte, x9.8 on white - the player's own light
## is nearly the whole of what they are standing in, which is what a dungeon this dark means.
const PLAYER_POOL_MIN := 1.5
const UNLIT_SHARE := 0.14
## Absolute floor under the lit reading, so "a share of a very dark theme" can never be black.
const FLOOR_CRUSH_MIN := 0.004
## Which floor tile "the dark" is read off: the darkest quarter of the floor in view, on the frame
## taken with the player's own light switched off. A quarter rather than the single darkest tile,
## because one shadowed corner is not a dungeon lit in pockets and a rule satisfied by one tile is
## a rule that cannot fail; with the pool off, because the question is whether the *room* is dark
## and the player is carrying a light bright enough to fight by.
const UNLIT_QUANTILE := 0.25
## Least floor tiles in view before the reading means anything at all.
const FLOOR_MIN_TILES := 40
## How far from the player counts as "what you are fighting". Two and a half tiles: a melee
## swing's reach, not the width of the room. It was 120 px - seven and a half tiles - which was a
## fair question while an ambient wash lit the whole room and is the wrong one now: most of that
## disc is deliberately dark, so averaging over it measures how much of the room the player
## cannot see rather than whether they can fight.
const FIGHT_RADIUS := 40.0
## How far past the level the room's own tile material authored a floor at the player's pool may
## push it.
##
## This is the other end of the invariant `unlit_floor + lantern_energy = 1` puts on the resource,
## measured on a drawn frame: a pool is the dark exactly undone, so at its centre a surface comes
## back to the colour the room's material carries and stops. Past that the light is not restoring
## detail, it is erasing it.
##
## It was an absolute 0.97 - "the floor has not clipped to white" - and an absolute is the wrong
## question. `white` authors a floor at luminance 1.00, so a pool that restores it perfectly draws
## 1.00 and an absolute ceiling calls that a blow-out; meanwhile a dark theme whose floor is
## authored at 0.08 could be driven to five times its own level and sail under 0.97 with the tile
## seams long gone. The defect is *exceeding what the theme authored*, so that is what is measured
## and `white` and tokyo-night are asked the same question.
##
## The reference is the room's own **tile material** (`_authored_floor`), not the palette's `floor`
## role. A first attempt used the role and gruvbox reported x1.92 of it with nothing over-driven:
## a room is painted from a palette *variant*, so its floor rung is not the base role's colour,
## and a floor tile paints `floor_alt` as well as `floor`.
##
## 1.15 rather than 1.00 because two pools do overlap, and neither is wrong to be there: a player
## standing under a door torch receives both.
const POOL_RESTORE_MAX := 1.15
## Which floor pixel the ceiling is read off: the brightest hundredth are the antialiased edge of
## a torch sprite and the odd highlight dot, not the floor, so the ceiling is taken just under
## them rather than at the single brightest pixel in the frame.
const CEILING_PERCENTILE := 0.99
const NEAR_RADIUS := 120.0
## Radius of the two lantern samples, in image pixels (a window is 3x the base resolution).
const POOL_RADIUS := 18.0
## Least the darkest floor tile under a lantern's pool may fall to, as a fraction of the
## pool's mean tile: a cast shadow (a prop's, a wall's) dims the floor, it never blacks it out.
const SHADOW_FLOOR_FRACTION := 0.4
## How much of a pool's own radius the darkest tile is searched within, centred on the light,
## and the least floor tiles that window has to contain for the reading to mean anything.
##
## Derived from the light rather than written in pixels, because the rule is about *shadows*
## and a fixed window stops being about shadows the moment the falloff changes. It used to be
## three tiles of a linear ramp, which was fine while a light was still worth a third of itself
## out there; `DungeonLight.FALLOFF_POWER` shapes every pool now - deliberately, so a pool has
## an edge instead of a room-wide haze - and at three tiles it is under a tenth, so on gruvbox
## the rule fired at 0.0154 against a 0.0441 mean with nothing casting anything.
##
## The window is not the fix, though: shrinking it until the falloff stops mattering leaves one
## floor tile in it, and a rule measured on one tile is a rule that cannot fail. So the window
## stays wide enough to hold a real sample and every tile in it is divided by the falloff at
## its own distance first (`_shadow_profile`). What is compared is then what the *pool* puts on
## each tile, which is the same on every unshadowed tile however far out it is, and a shadow is
## the only thing that can take one of them under the line.
const SHADOW_SEARCH_SHARE := 0.7
const SHADOW_MIN_TILES := 4
const QUALITIES: Array[LightingProfile.Quality] = [
	LightingProfile.Quality.OFF, LightingProfile.Quality.LOW, LightingProfile.Quality.HIGH
]
const QUALITY_NAMES: PackedStringArray = ["off", "low", "high"]

var _lines: PackedStringArray = []
var _bad: PackedStringArray = []
var _sampler := FrameSampler.new()
var _sampling: bool = false
var _last_usec: int = 0
var _warmup_left: int = 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var theme := _theme_name()
	var world := Node2D.new()
	world.name = "World"
	add_child(world)
	var camera := Camera2D.new()
	camera.name = "Camera"
	world.add_child(camera)
	var params := GenParams.from_profile(ThemeProfile.from_palette(_palette()), 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260913
	var data := FloorGenerator.generate(params, rng)
	var size := get_viewport().get_visible_rect().size
	_lines.append(
		(
			"lighting frame: theme %s, viewport %dx%d, floor %dx%d tiles, %d rooms"
			% [theme, int(size.x), int(size.y), data.width, data.height, data.rooms.size()]
		)
	)
	for i in range(QUALITIES.size()):
		GameState.settings[LightingProfile.SETTING_QUALITY] = QUALITIES[i]
		GameState.settings[LightingProfile.SETTING_SHADOWS] = true
		var root := FloorRoot.new()
		world.add_child(root)
		root.build_with_biome(data, Biome.load_by_id(data.biome), null, _palette())
		var player := RoomsTestFixtures.make_player()
		player.global_position = root.player_spawn_position()
		var light := PointLight2D.new()
		light.name = "Light"
		light.texture = DungeonLight.make_texture(96)
		# Driven from the emitter table, not authored here: the rig sets these on its own caster
		# tick, and a fixture that opens on its own numbers photographs a light the game does not
		# have.
		var table := LightingProfile.resolve()
		light.texture_scale = float(table.emitter_spec(&"player")["radius"])
		light.energy = float(table.emitter_spec(&"player")["energy"])
		light.color = DungeonLight.resolve().light_color(root.lit_palette().get_color(&"accent"))
		player.add_child(light)
		world.add_child(player)
		camera.global_position = player.global_position
		camera.make_current()
		var rig := LightRig.of(root)
		if rig != null:
			rig.add_blob(player)
		await get_tree().create_timer(SETTLE_SECONDS).timeout
		root.set_process(false)
		var energy := root.torch_light_energy()
		for torch: PointLight2D in root.torch_lights():
			torch.energy = energy
		_sampler.reset()
		_warmup_left = WARMUP
		_sampling = true
		_last_usec = Time.get_ticks_usec()
		for _f in range(FRAMES + WARMUP):
			await get_tree().process_frame
		_sampling = false
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var name := QUALITY_NAMES[i]
		var path := ProjectSettings.globalize_path(_out_path("lighting_%s" % name, "png"))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var saved := image.save_png(path)
		var lanterns := 0 if rig == null else rig.lanterns.size()
		var casters := 0 if rig == null else rig.shadow_casters().size()
		var runs := 0 if rig == null else rig.occluders.size()
		_lines.append(
			(
				"%s: %s | lanterns %d, occluders %d, shadow casters %d | %s (%s)"
				% [
					name,
					_sampler.format_line("frame"),
					lanterns,
					runs,
					casters,
					path,
					error_string(saved)
				]
			)
		)
		if QUALITIES[i] == LightingProfile.Quality.HIGH:
			await _measure(image, root, player, rig)
		player.queue_free()
		root.clear_floor()
		root.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	var report := ProjectSettings.globalize_path(_out_path("lighting_perf", "txt"))
	var file := FileAccess.open(report, FileAccess.WRITE)
	if file != null:
		for line: String in _lines:
			file.store_line(line)
		for line: String in _bad:
			file.store_line("UNDER: " + line)
		file.close()
	for line: String in _lines:
		print(line)
	for line: String in _bad:
		push_error("lighting frame: " + line)
	QuitGuard.request(get_tree(), 0 if _bad.is_empty() else 2)


func _process(_delta: float) -> void:
	if not _sampling:
		return
	var now := Time.get_ticks_usec()
	# The first WARMUP frames are the build settling; they are dropped.
	_warmup_left -= 1
	if _warmup_left < 0:
		_sampler.feed(float(now - _last_usec) / 1_000_000.0)
	_last_usec = now


## The floor around the player and the floor under the nearest lantern pool, measured on the
## drawn frame, against the legibility lines.
func _measure(image: Image, root: FloorRoot, player: Node2D, rig: LightRig) -> void:
	var pal := root.lit_palette()
	# The level the theme authored its floor at: what a pool restores a surface to, and the unit
	# both playability lines below are written in.
	var theme_floor := ThemePalette.relative_luminance(pal.get_color(&"floor"))
	# Floor tiles only, and each tile's own pixels: a disc of every pixel around the player
	# averages walls, props and the player's own sprite into the answer, and on gruvbox that read
	# *darker* close in than wide out, because the player was standing beside a wall.
	var fighting := _mean_of(
		_floor_tile_luminances(image, root, player.global_position, FIGHT_RADIUS)
	)
	# The darkest quarter of the floor the camera can see, as one number. Not "tiles far from a
	# light": on gruvbox, which generates a warren of four-tile rooms with a door on every wall,
	# no tile is ever four tiles from a doorway and the rule measured nothing at all; and not
	# "tiles no light reaches", which on a floor carrying twenty lights is almost as empty. What
	# the rule is about is whether a quarter of the ground in front of the player is dark, and
	# that is a question every frame has an answer to.
	var floor_tiles := _visible_floor_luminances(image, root)
	# What the *player's own* light is worth on that ground, measured rather than inferred: the
	# same tiles again with the player's pool switched off. This is the playability guarantee in
	# the only form that has teeth - a room whose torches happen to reach the spawn would satisfy
	# any "the floor is bright enough" line while the thing the player carries did nothing.
	# One extra frame with the player's own light switched off, and both playability readings come
	# off it. The lit one is the point of the pool; the dark one is the room *without* the thing
	# the player is carrying, which is the only honest way to ask whether the dungeon is dark -
	# a pool bright enough to fight by lifts a good part of the floor the camera can see, and
	# measuring the darkest quarter with it on counted the pool's own edge as an ambient wash
	# (tokyo-night reported x0.177 against a x0.14 ceiling with nothing washing anything).
	var without := await _without_player_light(root, player, rig)
	var carried := without.x
	var unlit := without.y
	_lines.append(
		(
			(
				"theme floor %.4f | floor the player is fighting on (%.0f px): %.4f, x%.2f of it "
				+ "with the player's own pool switched off (line x%.2f) | darkest quarter of %d "
				+ "visible floor tiles, pool off: %.4f = x%.3f of the theme's own (ceiling x%.2f)"
			)
			% [
				theme_floor,
				FIGHT_RADIUS,
				fighting,
				fighting / maxf(carried, 0.0001),
				PLAYER_POOL_MIN,
				floor_tiles.size(),
				unlit,
				unlit / maxf(theme_floor, 0.0001),
				UNLIT_SHARE
			]
		)
	)
	if carried > 0.0 and fighting / carried < PLAYER_POOL_MIN:
		_bad.append(
			(
				(
					"the player carries no pool: the ground they are standing on reads %.4f, and "
					+ "%.4f with their own light switched off - x%.2f, under the x%.2f line. "
					+ "Whatever else is lit, a player has to be able to fight what is next to them"
				)
				% [fighting, carried, fighting / maxf(carried, 0.0001), PLAYER_POOL_MIN]
			)
		)
	if floor_tiles.size() < FLOOR_MIN_TILES:
		_bad.append(
			(
				"only %d floor tiles in view: there is not enough floor here to measure"
				% floor_tiles.size()
			)
		)
	if unlit > UNLIT_SHARE * theme_floor:
		_bad.append(
			(
				(
					"the darkest quarter of the floor in view keeps x%.3f of the theme's own "
					+ "floor, over the x%.2f ceiling: that is an ambient wash, not a dark room"
				)
				% [unlit / maxf(theme_floor, 0.0001), UNLIT_SHARE]
			)
		)
	if fighting < FLOOR_CRUSH_MIN:
		_bad.append(
			"the floor the player is standing on reads %.4f: that is black, not dark" % fighting
		)
	# The other end of the invariant, on every theme rather than only the light ones: a pool is
	# the dark undone and no more, so the brightest floor the player is standing in may not be
	# pushed past the level the room's own tile material authored it at.
	var top := _floor_pixel_percentile(
		image, root, player.global_position, NEAR_RADIUS / 3.0, CEILING_PERCENTILE
	)
	var authored := _authored_floor(root, player)
	var restored := top / maxf(authored, 0.0001)
	_lines.append(
		(
			(
				"floor by the player at the %d%% pixel: %.4f against an authored floor of %.4f = "
				+ "x%.2f of it (ceiling x%.2f)"
			)
			% [int(CEILING_PERCENTILE * 100.0), top, authored, restored, POOL_RESTORE_MAX]
		)
	)
	if authored > 0.0 and restored > POOL_RESTORE_MAX:
		_bad.append(
			(
				(
					"the player's pool blows the floor out: the %d%% pixel reads x%.2f of the "
					+ "level the room's own tile material authored its floor at, over the x%.2f a "
					+ "pool that is the dark exactly undone can reach - past that the light is "
					+ "erasing detail rather than restoring it"
				)
				% [int(CEILING_PERCENTILE * 100.0), restored, POOL_RESTORE_MAX]
			)
		)

	if rig == null or rig.lanterns.is_empty():
		_bad.append("no lanterns on the floor")
		return
	# The nearest lantern to the player: the floor one tile in from it against the floor two
	# tiles further along the same wall, both of them floor tiles of the room.
	var best: WallLantern = null
	var best_d := INF
	for lantern: WallLantern in rig.lanterns:
		var d := lantern.global_position.distance_to(player.global_position)
		if d < best_d and lantern.light != null:
			best_d = d
			best = lantern
	var tile := float(Layers.TILE)
	var pool := best.global_position + best.facing * tile * 1.5
	var lit := _mean_luminance(image, _screen_of(pool, image), POOL_RADIUS)
	# Against the floor tiles of the room that stand at least four tiles from every lantern and
	# door torch: the floor between the pools, which is what a pool has to stand off.
	var far := _floor_tiles_away_from_lights(root, rig, best, tile * 4.0)
	var dark := 0.0
	for spot: Vector2 in far:
		dark += _mean_luminance(image, _screen_of(spot, image), POOL_RADIUS)
	dark = dark / float(far.size()) if not far.is_empty() else 0.0
	_lines.append(
		(
			"nearest lantern %s: floor under the pool %.4f, floor between the pools %.4f (%d tiles)"
			% [best.tile, lit, dark, far.size()]
		)
	)
	if not far.is_empty() and lit <= dark:
		_bad.append(
			"lantern %s lifts nothing: %.4f under it, %.4f between" % [best.tile, lit, dark]
		)
	# What the pool puts on each floor tile inside it, with the falloff at that tile's own
	# distance divided back out: a prop's or a wall's shadow across a tile dims the floor, it
	# never blacks it out. Tiles, not pixels, so a grout line or an outline is not mistaken for
	# a shadow; floor tiles only, and never a prop's own. `dark` is the unlit floor the pool is
	# added on top of, so when there is no unlit floor to read there is nothing to divide out
	# and the rule says so rather than guessing.
	var reach := best.light.texture_scale * float(DungeonLight.resolve().light_texture_size) * 0.5
	if far.is_empty():
		_lines.append(
			"pool of lantern %s: no unlit floor in the room to measure it against" % best.tile
		)
		return
	var base_floor := dark
	var share := _shadow_profile(image, root, rig, best, reach, base_floor)
	if share.size() < SHADOW_MIN_TILES:
		(
			_lines
			. append(
				(
					"pool of lantern %s: only %d floor tiles inside it, under the %d the shadow line needs"
					% [best.tile, share.size(), SHADOW_MIN_TILES]
				)
			)
		)
		return
	# Pass one: what the pool is worth at its centre, as the *median* of the tiles that can see
	# it. A mean is what a second light breaks: a tile this lantern lights that also sits in a
	# door torch's pool reports far more than the lantern put there, and two such tiles raise the
	# prediction every other tile is then held to. With the room lit by nothing but its own
	# lights that read as a shadow blacking the floor out - 34% against a 40% line, with nothing
	# casting anything. The median asks what a *typical* tile of this pool receives.
	var levels: Array[float] = []
	for reading: Vector2 in share:
		levels.append(reading.x)
	levels.sort()
	var pool_mean := levels[levels.size() / 2]
	# Pass two: each tile's drawn floor against the floor the falloff alone predicts there - the
	# unlit floor plus the pool's own share at that distance. The comparison is in *drawn*
	# luminance, which is the unit "a shadow dims the floor, it never blacks it out" is written
	# in and the one `SHADOW_FLOOR_FRACTION` was chosen against; the falloff goes into the
	# prediction rather than into the reading, so a tile far from the light is held to a
	# far-from-the-light line instead of to the line a tile at the centre is held to.
	var worst := INF
	for reading: Vector2 in share:
		var drawn := base_floor + reading.x * reading.y
		var expected := base_floor + pool_mean * reading.y
		worst = minf(worst, drawn / maxf(expected, 0.0001))
	_lines.append(
		(
			(
				"pool of lantern %s: %d floor tiles, pool at its centre %.4f, dimmest tile %.0f%%"
				+ " of what the falloff predicts there (line %.0f%%)"
			)
			% [best.tile, share.size(), pool_mean, worst * 100.0, SHADOW_FLOOR_FRACTION * 100.0]
		)
	)
	if worst < SHADOW_FLOOR_FRACTION:
		_bad.append(
			(
				(
					"a shadow blacks the floor out under lantern %s: a tile draws %.0f%% of what"
					+ " the falloff alone predicts there"
				)
				% [best.tile, worst * 100.0]
			)
		)


## `world` in pixels of the captured image: through the canvas transform (base resolution) and
## then the stretch onto the window the image was read from.
func _screen_of(world: Vector2, image: Image) -> Vector2:
	var view := get_viewport()
	var base := view.get_visible_rect().size
	var at := view.get_canvas_transform() * world
	return at * Vector2(image.get_width() / base.x, image.get_height() / base.y)


## Two readings off one frame taken with the player's own light switched off: `x` is the floor
## they are standing on, `y` is the darkest quarter of the floor the camera can see. The light is
## put back before this returns, so the PNG already written and the readings still to be taken are
## unaffected.
func _without_player_light(root: FloorRoot, player: Node2D, rig: LightRig) -> Vector2:
	var light := rig.player_light()
	if light == null:
		return Vector2.ZERO
	# `enabled`, not `energy`: the rig drives the player's energy from the emitter table on its
	# own caster tick (`LightRig._drive_player_light`), so an energy of zero is back to 0.94
	# before the frame it was meant to change. The rig's processing is stopped as well, so
	# nothing else moves between the two readings either.
	rig.set_process(false)
	light.enabled = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var dark_frame := get_viewport().get_texture().get_image()
	light.enabled = true
	rig.set_process(true)
	await RenderingServer.frame_post_draw
	return Vector2(
		_mean_of(_floor_tile_luminances(dark_frame, root, player.global_position, FIGHT_RADIUS)),
		_quantile(_visible_floor_luminances(dark_frame, root), UNLIT_QUANTILE)
	)


## The level the room the player is standing in authored its floor at: the brighter of the two
## rungs a floor tile actually paints (`floor` and `floor_alt`) off that room's own tile material.
## This is what a pool restores a surface to, and therefore what "blown out" is measured against.
func _authored_floor(root: FloorRoot, player: Node2D) -> float:
	var room := root.room_at_world(player.global_position)
	if room == null:
		return 0.0
	var targets := Prop.ramp_targets(root.material_for_room(room.id))
	if targets.size() < TileRamp.RAMP_SIZE:
		return 0.0
	return maxf(
		ThemePalette.relative_luminance(targets[Prop.FLOOR_RAMP_INDEX]),
		ThemePalette.relative_luminance(targets[Prop.FLOOR_RAMP_INDEX + 1])
	)


static func _mean_of(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


## The luminance of every FLOOR tile the camera can see, read off the drawn frame as the mean of
## that tile's own pixels. Floor only: a wall cap is lit differently and a prop is not the ground.
func _visible_floor_luminances(image: Image, root: FloorRoot) -> Array[float]:
	var out: Array[float] = []
	var data := root.data
	var props: Dictionary = {}
	for prop: Prop in root.props:
		props[FloorRoot.tile_of(prop.position)] = true
	var tile := float(Layers.TILE)
	var view := get_viewport().get_visible_rect().size
	var transform := get_viewport().get_canvas_transform()
	for y in range(data.height):
		for x in range(data.width):
			if data.get_tile(x, y) != FloorData.Tile.FLOOR or props.has(Vector2i(x, y)):
				continue
			var world := root.global_position + (Vector2(x, y) + Vector2(0.5, 0.5)) * tile
			# On screen only: a tile the camera is not looking at was never drawn, and its
			# pixels are whatever the frame happens to hold there.
			var at := transform * world
			if at.x < tile or at.y < tile or at.x > view.x - tile or at.y > view.y - tile:
				continue
			out.append_array(_floor_tile_luminances(image, root, world, tile * 0.4))
	return out


## The `q`-th value of `values`, sorted ascending; 0.0 when there are none.
static func _quantile(values: Array[float], q: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(int(floorf(float(sorted.size() - 1) * q)), 0, sorted.size() - 1)
	return sorted[index]


static func _mean_luminance(image: Image, centre: Vector2, radius: float) -> float:
	var total := 0.0
	var n := 0
	var r := int(radius)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var x := int(centre.x) + dx
			var y := int(centre.y) + dy
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			total += ThemePalette.relative_luminance(image.get_pixel(x, y))
			n += 1
	return total / float(n) if n > 0 else 0.0


## Per FLOOR tile (no prop on it) inside the pool: `x` is what the pool would be worth at its
## *centre* judging by this tile - the tile's drawn luminance less the unlit floor `base`,
## divided by the falloff at its own distance - and `y` is that falloff.
##
## Dividing the falloff out is what makes the tiles comparable across the window. Every
## unshadowed tile then reports about the same `x`, however far out it sits, so the only thing
## that can put one well under the others is something standing between it and the light.
## Without it the falloff is indistinguishable from a shadow, and the choice is between a
## window too narrow to hold a sample and a rule that fires on nothing. `y` is handed back so
## the caller can put the prediction back into drawn luminance, the unit the line is written
## in.
func _shadow_profile(
	image: Image, root: FloorRoot, rig: LightRig, lantern: WallLantern, reach: float, base: float
) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var light := lantern.light_position()
	# Every other light on the floor, so a tile that belongs to one of them can be left out: the
	# rule is about what *this* lantern's pool does to the floor, and a tile nearer some other
	# source is not evidence about this one either way.
	var others: Array[Vector2] = []
	for other: WallLantern in rig.lanterns:
		if other != lantern and other.light != null:
			others.append(other.light_position())
	for torch: PointLight2D in root.torch_lights():
		if is_instance_valid(torch):
			others.append(torch.global_position)
	var player_light := rig.player_light()
	if player_light != null:
		others.append(player_light.global_position)
	var window := reach * SHADOW_SEARCH_SHARE
	var gradient := (DungeonLight.make_texture(96) as GradientTexture2D).gradient
	var data := root.data
	# The room the lantern faces, and only that room. A lantern hangs on a wall, so a window
	# centred on it reaches floor on the far side of that wall too - floor the light never
	# touches at all, because the wall's own occluder stops it. Those tiles report nothing of
	# the pool and read as the blackest shadow in the room, which is a wall being mistaken for
	# a shadow across a lit floor. The rule is about the floor this lantern lights.
	var room := data.room_at(lantern.tile + Vector2i(lantern.facing))
	if room == null:
		return out
	var props: Dictionary = {}
	for prop: Prop in root.props:
		props[FloorRoot.tile_of(prop.position)] = true
	var tile := float(Layers.TILE)
	var span := int(ceilf(window / tile))
	var origin := FloorRoot.tile_of(light - root.global_position)
	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var t := origin + Vector2i(dx, dy)
			if not room.rect.has_point(t):
				continue
			if data.get_tile(t.x, t.y) != FloorData.Tile.FLOOR or props.has(t):
				continue
			var world := root.global_position + (Vector2(t) + Vector2(0.5, 0.5)) * tile
			var d := world.distance_to(light)
			if d > window:
				continue
			var owned := true
			for other: Vector2 in others:
				if other.distance_to(world) < d:
					owned = false
					break
			if not owned:
				continue
			var falloff := gradient.sample(clampf(d / maxf(reach, 1.0), 0.0, 1.0)).a
			if falloff <= 0.02:
				continue
			var lum := _mean_luminance(image, _screen_of(world, image), tile * 0.5)
			out.append(Vector2(maxf(lum - base, 0.0) / falloff, falloff))
	return out


## Mean luminance of every FLOOR tile (no prop on it) within `radius` world px of `centre`,
## each read off the drawn frame as the mean of its own pixels.
func _floor_tile_luminances(
	image: Image, root: FloorRoot, centre: Vector2, radius: float
) -> Array[float]:
	var out: Array[float] = []
	var data := root.data
	var props: Dictionary = {}
	for prop: Prop in root.props:
		props[FloorRoot.tile_of(prop.position)] = true
	var tile := float(Layers.TILE)
	var reach := int(ceilf(radius / tile))
	var origin := FloorRoot.tile_of(centre - root.global_position)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var t := origin + Vector2i(dx, dy)
			if data.get_tile(t.x, t.y) != FloorData.Tile.FLOOR or props.has(t):
				continue
			var world := root.global_position + (Vector2(t) + Vector2(0.5, 0.5)) * tile
			if world.distance_to(centre) > radius:
				continue
			var at := _screen_of(world, image)
			var half := _screen_of(world + Vector2(tile * 0.5, 0.0), image).x - at.x
			var total := 0.0
			var n := 0
			for py in range(int(at.y - half) + 1, int(at.y + half) - 1):
				for px in range(int(at.x - half) + 1, int(at.x + half) - 1):
					if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
						continue
					total += ThemePalette.relative_luminance(image.get_pixel(px, py))
					n += 1
			if n > 0:
				out.append(total / float(n))
	return out


## Luminance of the `q`-th pixel of every FLOOR tile (no prop on it) within `radius` world px of
## `centre`, sorted brightest last: the ceiling is a question about the lit part of a tile, and a
## tile mean averages the seams and the speckle back into it.
func _floor_pixel_percentile(
	image: Image, root: FloorRoot, centre: Vector2, radius: float, q: float
) -> float:
	var values: Array[float] = []
	var data := root.data
	var props: Dictionary = {}
	for prop: Prop in root.props:
		props[FloorRoot.tile_of(prop.position)] = true
	var tile := float(Layers.TILE)
	var reach := int(ceilf(radius / tile))
	var origin := FloorRoot.tile_of(centre - root.global_position)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var t := origin + Vector2i(dx, dy)
			if data.get_tile(t.x, t.y) != FloorData.Tile.FLOOR or props.has(t):
				continue
			var world := root.global_position + (Vector2(t) + Vector2(0.5, 0.5)) * tile
			if world.distance_to(centre) > radius:
				continue
			var at := _screen_of(world, image)
			var half := _screen_of(world + Vector2(tile * 0.5, 0.0), image).x - at.x
			for py in range(int(at.y - half) + 1, int(at.y + half) - 1):
				for px in range(int(at.x - half) + 1, int(at.x + half) - 1):
					if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
						continue
					values.append(ThemePalette.relative_luminance(image.get_pixel(px, py)))
	if values.is_empty():
		return 0.0
	values.sort()
	var index := clampi(int(floorf(float(values.size() - 1) * q)), 0, values.size() - 1)
	return values[index]


## World centres of the FLOOR tiles of the room `lantern` faces that lie at least `distance`
## world px from every lantern and door-torch light, prop tiles excluded.
func _floor_tiles_away_from_lights(
	root: FloorRoot, rig: LightRig, lantern: WallLantern, distance: float
) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var data := root.data
	var facing_tile := lantern.tile + Vector2i(lantern.facing)
	var room := data.room_at(facing_tile)
	if room == null:
		return out
	var lights: Array[Vector2] = []
	for other: WallLantern in rig.lanterns:
		lights.append(other.light_position())
	for torch: PointLight2D in root.torch_lights():
		lights.append(torch.global_position)
	# The player's own pool counts as a light. It was left out while it was a small thing the
	# player carried; the darkness round made it the pool a player sees *by*, and a floor tile
	# four tiles from every lantern but standing in it is not "the floor between the pools" -
	# on gruvbox that is what made a lantern look as though it lifted nothing.
	var player := rig.player_light()
	if player != null:
		lights.append(player.global_position)
	var props: Dictionary = {}
	for prop: Prop in root.props:
		props[FloorRoot.tile_of(prop.position)] = true
	var tile := float(Layers.TILE)
	for y in range(room.rect.position.y, room.rect.end.y):
		for x in range(room.rect.position.x, room.rect.end.x):
			var t := Vector2i(x, y)
			if data.get_tile(x, y) != FloorData.Tile.FLOOR or props.has(t):
				continue
			var world := root.global_position + (Vector2(t) + Vector2(0.5, 0.5)) * tile
			var clear := true
			for light: Vector2 in lights:
				if light.distance_to(world) < distance:
					clear = false
					break
			if clear:
				out.append(world)
	return out


static func _palette() -> ThemePalette:
	return Desktop.palette if Desktop.palette != null else ThemePalette.fallback()


static func _theme_name() -> String:
	var state := OS.get_environment("OMADUNGEON_OMARCHY_STATE_DIR")
	var theme := state.trim_suffix("/").get_base_dir().get_file() if not state.is_empty() else ""
	return "tokyo-night" if theme.is_empty() else theme


## `tests/out/<name>.<ext>`, with `_<theme>` for any fixture but the default, the way
## `tools/run-scenario.sh` names its captures.
static func _out_path(name: String, ext: String) -> String:
	var theme := _theme_name()
	if theme == "tokyo-night":
		return "res://tests/out/%s.%s" % [name, ext]
	return "res://tests/out/%s_%s.%s" % [name, theme, ext]
