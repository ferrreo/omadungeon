## Corner minimap: rooms as squares, corridors as lines.
## Fed via `set_rooms(rooms, edges, links)`; rooms are {id: int, rect: Rect2i, cleared: bool,
## visited: bool, current: bool, type: int} in tile units, edges are Vector4i(x1, y1, x2, y2)
## tile centres, and links are the routes those edges are drawn along (`MinimapModel.links`).
##
## Every channel is derived from the plate the map is drawn on rather than from raw roles, so
## it reads the same on a light theme as on a dark one:
##   * fog       - a room you have not entered is an outline stub with no type colour
##   * progress  - visited rooms fill at half strength, cleared rooms at full
##   * kind      - special rooms take a type tint, but only once they are visited
##   * you       - the current room gets a two-pixel ring plus a centre pip, both guarded
##                 against that room's own fill, so it is never "the same square but paler"
##   * shape     - a visited special room is stamped with its own shape
##                 (`Accessibility.ROOM_SHAPES`), so a boss and a shop are not two squares
##                 that differ only in hue. Drawn on every install, not only with
##                 `colorblind_glyphs` on: gating it left a default map of identical
##                 rectangles, and the player had no way to read it at all
##   * where next - the floor's goal (the stairs, or the boss arena) is stamped as soon as a
##                 corridor from a room you have entered reaches it, before you enter it.
##                 The objective is not a secret; a treasure room still is
##   * missed     - a room a corridor reaches from somewhere you have been, but that you have
##                 not entered, is drawn as a brighter dashed outline than deep fog, and the
##                 strip under the map counts what the floor still holds ("2 rooms left,
##                 1 item on the floor"). That strip replaced the stairs' "you are leaving
##                 rewards behind" confirmation: the map says it all the time, quietly,
##                 instead of the exit saying it once, loudly, at the worst moment
class_name Minimap
extends Control

## Mirrors FloorData.RoomType so the HUD does not depend on the generator module.
enum RoomKind { START, COMBAT, ELITE, TRAP, TREASURE, ALTAR, SHOP, SHRINE, STAIRS, BOSS }

const PAD := 3
## Rooms never shrink below this on screen, or the fog/visited channels stop being legible.
const MIN_ROOM := 5.0
## Height of the strip under the map that counts what is left on the floor.
const CAPTION_HEIGHT := 10.0
## Fill strength of the outline of a room you know about but have not entered.
const KNOWN_MIX := 0.85
## Dash length of that outline, in pixels.
const DASH := 2.0
## Room kinds worth going back for (`DescendNotice.REWARD_ROOM_TYPES`, mirrored so the HUD
## does not depend on the generator module): the ones the caption counts by name.
const REWARD_KINDS: Array[int] = [
	RoomKind.TREASURE, RoomKind.ALTAR, RoomKind.SHOP, RoomKind.SHRINE, RoomKind.ELITE
]
## Width of the "you are here" ring.
const RING := 2.0
## Fill strength of a visited-but-uncleared room, as a mix between plate and mark.
const VISITED_MIX := 0.55
## Fill strength of the outline a fogged room is reduced to.
const FOG_MIX := 0.34
const PULSE_SECONDS := 1.2

## Type tints, applied only to visited rooms. Everything else uses the neutral mark.
const KIND_ROLES: Dictionary = {
	RoomKind.BOSS: &"danger",
	RoomKind.STAIRS: &"accent",
	RoomKind.TREASURE: &"loot",
	RoomKind.SHOP: &"loot",
	RoomKind.ALTAR: &"magic",
	RoomKind.SHRINE: &"magic",
	RoomKind.ELITE: &"heat",
}

## Room kinds that are the floor's objective: the thing "where do I go?" is asking about.
const GOAL_KINDS: Array[int] = [RoomKind.STAIRS, RoomKind.BOSS]
## Fill strength of a goal room that is known but not yet entered, as a mix toward its tint.
const GOAL_HINT_MIX := 0.5

var _rooms: Array[Dictionary] = []
var _edges: Array[Vector4i] = []
## Routes for `_edges`, same order. Empty entries (and a short feed) fall back to `elbow()`.
var _links: Array[PackedVector2Array] = []
var _bounds: Rect2i = Rect2i()
var _pulse: float = 0.0
var _animating: bool = false
## Ids of rooms a corridor connects to a room the player has entered, recomputed per feed.
var _adjacent_ids: Array[int] = []
## Item drops still lying on the floor, as `EventBus.floor_leftovers` last said.
var _items_left: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(96, 64)
	EventBus.palette_changed.connect(func(_p: ThemePalette) -> void: queue_redraw())
	EventBus.floor_leftovers.connect(set_items_left)
	EventBus.floor_started.connect(func(_i: int) -> void: set_items_left(0))


## Records how many item drops are still lying on the floor, for the caption.
func set_items_left(count: int) -> void:
	_items_left = maxi(0, count)
	queue_redraw()


func items_left() -> int:
	return _items_left


## Rooms the player has not entered yet.
func unvisited_count() -> int:
	var count := 0
	for room: Dictionary in _rooms:
		if not bool(room.get("visited", false)):
			count += 1
	return count


## Unentered rooms whose kind is worth going back for.
func unvisited_reward_count() -> int:
	var count := 0
	for room: Dictionary in _rooms:
		if not bool(room.get("visited", false)) and REWARD_KINDS.has(int(room.get("type", 1))):
			count += 1
	return count


## The strip under the map: "2 rooms left, 1 item on the floor". Empty once the floor is
## walked and picked clean, so a finished floor says nothing rather than "0 rooms left".
func caption_text() -> String:
	return caption_for(unvisited_count(), _items_left)


static func caption_for(rooms_left: int, items: int) -> String:
	var parts: PackedStringArray = []
	if rooms_left > 0:
		parts.append("%d %s left" % [rooms_left, "room" if rooms_left == 1 else "rooms"])
	if items > 0:
		parts.append("%d %s on the floor" % [items, "item" if items == 1 else "items"])
	return ", ".join(parts)


## Whether `room` is unentered but reached by a corridor from somewhere the player has been:
## a room the player can see they have skipped.
func is_known(room: Dictionary) -> bool:
	if bool(room.get("visited", false)):
		return false
	return _adjacent_ids.has(int(room.get("id", -1)))


func _process(delta: float) -> void:
	# Only the "current room" marker animates; with nothing pulsing there is nothing to redraw.
	if not _animating or not Accessibility.animates():
		return
	_pulse = fmod(_pulse + delta, PULSE_SECONDS)
	queue_redraw()


## `links` carries the route each edge actually takes (`MinimapModel.links`), in the same
## order as `edges`. A feed that omits it gets the `elbow()` route instead of a chord.
func set_rooms(
	rooms: Array[Dictionary], edges: Array[Vector4i], links: Array[PackedVector2Array] = []
) -> void:
	_rooms = rooms
	_edges = edges
	_links = links
	_bounds = Rect2i()
	_animating = false
	var first := true
	for room: Dictionary in rooms:
		if bool(room.get("current", false)):
			_animating = true
		var rect: Rect2i = room["rect"]
		if first:
			_bounds = rect
			first = false
		else:
			_bounds = _bounds.merge(rect)
	_adjacent_ids = _compute_adjacent()
	queue_redraw()


## Ids of rooms one corridor away from a room the player has entered. The feed carries no
## graph, so adjacency is read back off the corridor endpoints, which are room centres.
func _compute_adjacent() -> Array[int]:
	var out: Array[int] = []
	for edge: Vector4i in _edges:
		var a := _room_at(Vector2i(edge.x, edge.y))
		var b := _room_at(Vector2i(edge.z, edge.w))
		if a.is_empty() or b.is_empty():
			continue
		if bool(a.get("visited", false)) and not bool(b.get("visited", false)):
			out.append(int(b.get("id", -1)))
		elif bool(b.get("visited", false)) and not bool(a.get("visited", false)):
			out.append(int(a.get("id", -1)))
	return out


## Whether `room` is the floor's objective and the player may be shown where it is: either
## they have stood in it, or a corridor reaches it from somewhere they have. A treasure room
## stays fogged - the objective is the one thing fog of war has no business hiding.
func is_goal_hint(room: Dictionary) -> bool:
	if not GOAL_KINDS.has(int(room.get("type", RoomKind.COMBAT))):
		return false
	if bool(room.get("visited", false)):
		return false
	return _adjacent_ids.has(int(room.get("id", -1)))


## Whether this floor's goal room is on the map - entered, or reachable from somewhere the
## player has entered. `kind` narrows the question to one room kind (a boss floor asks about
## its arena, not about the staircase behind it); -1 asks about any goal room. The HUD turns
## the answer into the objective line.
func goal_room_known(kind: int = -1) -> bool:
	for room: Dictionary in _rooms:
		var room_kind := int(room.get("type", RoomKind.COMBAT))
		if kind >= 0 and room_kind != kind:
			continue
		if kind < 0 and not GOAL_KINDS.has(room_kind):
			continue
		if bool(room.get("visited", false)) or is_goal_hint(room):
			return true
	return false


## The room dictionary whose rect contains `tile`, or an empty one.
func _room_at(tile: Vector2i) -> Dictionary:
	for room: Dictionary in _rooms:
		var rect: Rect2i = room["rect"]
		if rect.has_point(tile):
			return room
	var empty: Dictionary = {}
	return empty


func room_count() -> int:
	return _rooms.size()


## Room id the last `set_rooms()` feed marked "you are here", or -1 when none is. The run
## lifecycle owns that flag, so this is where a stale-by-one-room marker becomes observable;
## tests read it back here instead of sampling the drawn pixels.
func current_room_id() -> int:
	for room: Dictionary in _rooms:
		if bool(room.get("current", false)):
			return int(room.get("id", -1))
	return -1


## The plate the whole map sits on. Fully opaque, for the reason docs §3.2 gives the HUD text
## blocks: room fills are judged against `void`, and at 0.94 the brickwork and torch glow
## behind the panel composited through it, so the surface they were judged against was not the
## one they were drawn on. A map you can see the dungeon through is a scribble on a window.
func plate() -> Color:
	return UiTheme.plate_color(1.0)


## Colour one room is filled with, given the plate. Fogged rooms return the plate itself (they
## are drawn as an outline only); the caller decides. Exposed so tests can assert the three
## channels stay apart on every palette without sampling pixels.
func room_fill(room: Dictionary, plate_color: Color) -> Color:
	var visited := bool(room.get("visited", false))
	var cleared := bool(room.get("cleared", false))
	if not visited:
		return mark(plate_color, 4.5, FOG_MIX)
	var kind := int(room.get("type", RoomKind.COMBAT))
	if KIND_ROLES.has(kind):
		var tint := UiTheme.readable_on(UiTheme.color(KIND_ROLES[kind]), plate_color, 2.5)
		return tint if cleared else plate_color.lerp(tint, VISITED_MIX)
	# Both the fog and the progress channel are softened marks, so both have to be softened the
	# same way: floor the visited fill too, or raising fog alone closes the gap between them.
	return mark(plate_color) if cleared else mark(plate_color, 4.5, VISITED_MIX)


func _draw() -> void:
	var plate_color := plate()
	draw_rect(Rect2(Vector2.ZERO, size), plate_color)
	draw_rect(Rect2(Vector2.ZERO, size), mark(plate_color, 3.0, 0.55), false, 1.0)
	var caption := caption_text()
	var map_h := size.y - (CAPTION_HEIGHT if not caption.is_empty() else 0.0)
	if not caption.is_empty():
		var font := UiTheme.body_font()
		var ink := mark(plate_color, 4.5, 0.9)
		draw_string(
			font,
			Vector2(PAD + 1.0, size.y - 3.0),
			caption,
			HORIZONTAL_ALIGNMENT_LEFT,
			size.x - PAD * 2.0,
			UiTheme.SIZE_S,
			ink
		)
	if _rooms.is_empty() or _bounds.size.x <= 0 or _bounds.size.y <= 0:
		return
	var inner := Vector2(size.x, map_h) - Vector2(PAD * 2, PAD * 2)
	var scale := minf(inner.x / float(_bounds.size.x), inner.y / float(_bounds.size.y))
	var offset := Vector2(PAD, PAD) + (inner - Vector2(_bounds.size) * scale) * 0.5
	_draw_edges(plate_color, scale, offset)
	for room: Dictionary in _rooms:
		_draw_room(room, plate_color, scale, offset)


## Corridors. Each link follows the route the carver took (or, for a feed without one, an
## orthogonal elbow through the gap), so a line never crosses a room it does not connect.
func _draw_edges(plate_color: Color, scale: float, offset: Vector2) -> void:
	var known := mark(plate_color, 3.0, 0.7)
	var fogged := mark(plate_color, 3.0, 0.28)
	for i in range(_edges.size()):
		var edge := _edges[i]
		var route := route_for(i)
		if route.size() < 2:
			continue
		var points := PackedVector2Array()
		for tile: Vector2 in route:
			points.append(_map(tile, scale, offset))
		var lit := _visited_at(Vector2i(edge.x, edge.y)) and _visited_at(Vector2i(edge.z, edge.w))
		draw_polyline(points, known if lit else fogged, 1.0)


## The tile-space route drawn for edge `index`: the corridor path the feed supplied, else an
## elbow between the two rooms' facing sides. Exposed so tests can assert the geometry without
## sampling drawn pixels.
func route_for(index: int) -> PackedVector2Array:
	if index < 0 or index >= _edges.size():
		return PackedVector2Array()
	if index < _links.size() and _links[index].size() >= 2:
		return _links[index]
	var edge := _edges[index]
	var a := _room_at(Vector2i(edge.x, edge.y))
	var b := _room_at(Vector2i(edge.z, edge.w))
	if a.is_empty() or b.is_empty():
		return PackedVector2Array(
			[Vector2(edge.x + 0.5, edge.y + 0.5), Vector2(edge.z + 0.5, edge.w + 0.5)]
		)
	return elbow(a["rect"] as Rect2i, b["rect"] as Rect2i)


## Orthogonal route from the edge of `a` to the edge of `b`, for a feed that carries no
## corridor path. Where the two rectangles face each other it is the straight segment across
## the gap between them; otherwise it leaves `a` through the side that points at `b` and turns
## once. Either way it starts and ends on a room border instead of inside one.
static func elbow(a: Rect2i, b: Rect2i) -> PackedVector2Array:
	var overlap_x := _overlap(a.position.x, a.end.x, b.position.x, b.end.x)
	if overlap_x > -INF:
		var top := a if a.position.y <= b.position.y else b
		var bottom := b if a.position.y <= b.position.y else a
		return PackedVector2Array(
			[Vector2(overlap_x, top.end.y), Vector2(overlap_x, bottom.position.y)]
		)
	var overlap_y := _overlap(a.position.y, a.end.y, b.position.y, b.end.y)
	if overlap_y > -INF:
		var left := a if a.position.x <= b.position.x else b
		var right := b if a.position.x <= b.position.x else a
		return PackedVector2Array(
			[Vector2(left.end.x, overlap_y), Vector2(right.position.x, overlap_y)]
		)
	var ac := Vector2(a.position) + Vector2(a.size) * 0.5
	var bc := Vector2(b.position) + Vector2(b.size) * 0.5
	var exit_x := float(a.end.x) if bc.x > ac.x else float(a.position.x)
	var enter_y := float(b.end.y) if ac.y > bc.y else float(b.position.y)
	return PackedVector2Array([Vector2(exit_x, ac.y), Vector2(bc.x, ac.y), Vector2(bc.x, enter_y)])


## Centre of the span two ranges share, or -INF when they share none.
static func _overlap(a0: int, a1: int, b0: int, b1: int) -> float:
	var lo := maxi(a0, b0)
	var hi := mini(a1, b1)
	if hi <= lo:
		return -INF
	return (float(lo) + float(hi)) * 0.5


func _draw_room(room: Dictionary, plate_color: Color, scale: float, offset: Vector2) -> void:
	var rect: Rect2i = room["rect"]
	var top_left := _map(Vector2(rect.position), scale, offset)
	var bottom_right := _map(Vector2(rect.end), scale, offset)
	var r := Rect2(top_left, (bottom_right - top_left).max(Vector2(MIN_ROOM, MIN_ROOM)))
	var visited := bool(room.get("visited", false))
	var kind := int(room.get("type", RoomKind.COMBAT))
	var fill := room_fill(room, plate_color)
	if visited:
		draw_rect(r, fill)
		draw_rect(r, mark(plate_color, 3.0, 0.85), false, 1.0)
		_draw_kind_shape(r, kind, fill)
	elif is_goal_hint(room):
		# Where to go. Drawn at half strength so it still reads as "not been there", but with
		# its type colour and its shape, so the map finally answers the only question it was
		# ever asked on floor 1.
		draw_rect(r, fill)
		var tint := goal_hint_color(kind, plate_color)
		draw_rect(r, tint, false, 1.0)
		_draw_kind_shape(r, kind, fill, tint)
	elif is_known(room):
		# Skipped: the player has stood next to this room and not gone in. A brighter dashed
		# outline than deep fog, still with no kind colour, so "there is something here I
		# have not looked at" is readable on the map itself.
		var ink := mark(plate_color, 4.5, KNOWN_MIX)
		_draw_dashed(r, ink)
		# A dot at its centre: a hollow dashed box reads as a gap in the map at 5 px; the dot
		# says "a room, unentered" and is the mark the strip's "rooms left" count points at.
		var centre := r.get_center().floor()
		draw_rect(Rect2(centre - Vector2(1, 1), Vector2(2, 2)), ink)
	else:
		# Fog of war: a stub outline, no fill and no type colour, so an unentered treasure
		# room gives nothing away.
		draw_rect(r, fill, false, 1.0)
	if not bool(room.get("current", false)):
		return
	var glow := Accessibility.flash(0.5 + 0.5 * sin(_pulse / PULSE_SECONDS * TAU))
	var base := fill if visited else plate_color
	var ring := UiTheme.readable_on(UiTheme.color(&"accent"), base, 3.0)
	var hot := UiTheme.readable_on(UiTheme.color(&"text_bright"), base, 4.5)
	draw_rect(r, ring.lerp(hot, glow), false, RING)
	var pip := r.get_center().floor()
	draw_rect(Rect2(pip - Vector2(1, 1), Vector2(2, 2)), hot)


## A dashed rectangle outline: `DASH` px on, `DASH` px off, one pixel wide.
func _draw_dashed(r: Rect2, color: Color) -> void:
	var corners: Array[Vector2] = [
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)
	]
	for i in 4:
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		var length := a.distance_to(b)
		var dir := (b - a).normalized()
		var t := 0.0
		while t < length:
			var seg_end := minf(t + DASH, length)
			draw_line(a + dir * t, a + dir * seg_end, color, 1.0)
			t += DASH * 2.0


## Outline a known-but-unentered goal room is marked with: its own type colour, pulled to a
## readable contrast against the plate so it reads on a light theme too.
func goal_hint_color(kind: int, plate_color: Color) -> Color:
	var role: StringName = KIND_ROLES.get(kind, &"accent")
	return UiTheme.readable_on(UiTheme.color(role), plate_color, 3.0)


## Stamps a special room with its accessibility shape. Drawn on every install: gating it on
## `colorblind_glyphs` left the default map thirteen identical rectangles with no way to tell
## the stairs from a corridor stub, which is the state the fog was supposed to protect.
## `ink` overrides the derived colour (the goal hint draws its stamp in the type colour).
func _draw_kind_shape(rect: Rect2, kind: int, fill: Color, ink: Color = Color(0, 0, 0, 0)) -> void:
	var shape := Accessibility.room_shape(kind)
	if shape < 0:
		return
	var color := ink if ink.a > 0.0 else UiTheme.readable_on(UiTheme.color(&"void"), fill, 3.0)
	Accessibility.draw_shape(self, rect.grow(-1.0), shape, color)


## A neutral foreground readable on `plate_color`, optionally softened toward it.
##
## `strength` below 1.0 fades the mark into the plate, but a plain sRGB lerp is not a fade in
## contrast terms: on a near-black plate 28% of the way still reads at ~3:1, while on a
## near-white plate the same 28% lands at ~1.5:1 and the mark disappears. So the softened
## colour is pulled back up to a contrast *floor* that scales with `strength`, which leaves
## dark themes exactly where they were and keeps light ones legible. Exposed (not `_mark`)
## so tests can assert that floor on every fixture without sampling drawn pixels.
func mark(plate_color: Color, target: float = 4.5, strength: float = 1.0) -> Color:
	var full := UiTheme.readable_on(UiTheme.color(&"text"), plate_color, target)
	if strength >= 1.0:
		return full
	var soft := plate_color.lerp(full, maxf(0.0, strength))
	return ThemePalette.ensure_contrast_toward(
		soft, plate_color, mark_floor(target, strength), full
	)


## The contrast floor `mark()` guarantees for a given target and softening strength.
static func mark_floor(target: float, strength: float) -> float:
	return 1.0 + maxf(0.0, target - 1.0) * clampf(strength, 0.0, 1.0)


## Whether the tile a corridor endpoint sits on belongs to a room the player has entered.
func _visited_at(tile: Vector2i) -> bool:
	return bool(_room_at(tile).get("visited", false))


func _map(tile: Vector2, scale: float, offset: Vector2) -> Vector2:
	return ((tile - Vector2(_bounds.position)) * scale + offset).floor()
