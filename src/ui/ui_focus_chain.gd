## Explicit focus wiring for a list a controller has to walk from end to end.
##
## Why this exists. Godot only falls back to a *geometric* search for the next focus target
## when `focus_neighbor_*` is empty, and that search refuses a control its container has
## clipped away - which every row below the fold of a `ScrollContainer` is. So a pad walking
## the Settings list stopped dead at the last row that happened to fit the viewport: `ui_down`
## found no neighbour, focus never moved, the list never scrolled (nothing scrolls a list
## until focus has moved into it) and thirteen rebind rows in two columns were unreachable.
## `ScrollContainer.follow_focus` only papers over it, and only by accident.
##
## An explicit neighbour is checked for visibility and focus mode and nothing else - clipping
## is not consulted - so a chain wired here walks into the clipped part of the list, and the
## list scrolls afterwards because focus moved (`UiListReveal`). That is the order a scrolled
## list has to work in.
##
## Rows may hold more than one control (the rebind rows are Keyboard + Gamepad): left/right
## wrap inside the row, up/down step to the same column of the next row, clamped to its width.
## The ends of the chain take an explicit exit - the page's Back button, the pause menu's
## footer - so the bottom of a list is never a cul-de-sac and never strands focus on whatever
## destructive button happens to sit below it.
class_name UiFocusChain
extends RefCounted

var _rows: Array = []


## Starts a new row. Rows with no focusable control in them are dropped by `wire`.
func begin_row() -> void:
	_rows.append([] as Array[Control])


## Adds `control` to the row `begin_row` opened (opening one first if none is).
func add(control: Control) -> void:
	if control == null:
		return
	if _rows.is_empty():
		begin_row()
	var row: Array[Control] = _rows[_rows.size() - 1]
	row.append(control)


## Forgets every row, for a page that rebuilds its list.
func clear() -> void:
	_rows.clear()


## The rows that actually hold something, in order.
func rows() -> Array:
	var out: Array = []
	for row: Array in _rows:
		if not row.is_empty():
			out.append(row)
	return out


## The control a page should focus when it opens, or null for an empty chain.
func first() -> Control:
	var packed := rows()
	if packed.is_empty():
		return null
	var row: Array[Control] = packed[0]
	return row[0]


## The last row's first control: where a walk down the list ends up.
func last() -> Control:
	var packed := rows()
	if packed.is_empty():
		return null
	var row: Array[Control] = packed[packed.size() - 1]
	return row[0]


## Wires every row to its neighbours. `above` and `below` are the controls the chain hands
## focus to off its top and bottom ends; with neither, the chain wraps into a ring. Both are
## wired back into the list as well, so the exit is a door and not a trapdoor.
func wire(above: Control = null, below: Control = null) -> void:
	var packed := rows()
	if packed.is_empty():
		return
	for i in packed.size():
		var row: Array[Control] = packed[i]
		var width := row.size()
		for j in width:
			var control := row[j]
			if width > 1:
				control.focus_neighbor_left = row[wrapi(j - 1, 0, width)].get_path()
				control.focus_neighbor_right = row[wrapi(j + 1, 0, width)].get_path()
			control.focus_neighbor_top = _step(packed, i, -1, j, above)
			control.focus_neighbor_bottom = _step(packed, i, 1, j, below)
	var top_row: Array[Control] = packed[0]
	var bottom_row: Array[Control] = packed[packed.size() - 1]
	if above != null:
		above.focus_neighbor_bottom = top_row[0].get_path()
	if below != null:
		below.focus_neighbor_top = bottom_row[0].get_path()


## The neighbour path one row away from row `index` in direction `dir`, staying in column `col`
## where the next row is wide enough. Off either end it takes `exit`, or wraps when there is
## none.
static func _step(packed: Array, index: int, dir: int, col: int, exit: Control) -> NodePath:
	var next := index + dir
	if next < 0 or next >= packed.size():
		if exit != null:
			return exit.get_path()
		next = wrapi(next, 0, packed.size())
	var row: Array[Control] = packed[next]
	return row[mini(col, row.size() - 1)].get_path()
