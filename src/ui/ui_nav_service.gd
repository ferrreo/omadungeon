## Autoload (`UiNav`): owns the process-wide `UiStickNav` node.
##
## Why the service is installed here and not lazily by the first screen that wants it.
## `Node.add_child()` is refused outright on a parent that is itself in the middle of adding
## children - "Parent node is busy setting up children, `add_child()` failed" - and that is
## exactly the state the scene tree root is in while the engine is inserting the main scene.
## A screen asking for the service from its own `_ready` therefore got the refusal, on stderr
## and nowhere else, on the one screen the game boots into: the left stick was dead on the
## title and alive on every screen opened later, which read as a title-screen bug rather than
## as an installation bug. Deferring the insertion only moves the problem: the node is then
## absent for a frame, a second screen asking inside that frame builds a *second* service, and
## two services turn one flick of the stick into two presses.
##
## An autoload is added by the engine before the main scene exists. The service is up before
## any screen can ask for it, there is exactly one of it for the life of the process, and
## `UiStickNav.instance()` becomes a lookup that never inserts anything.
extends Node


func _ready() -> void:
	# The boards and the pause menu pause the tree; the service has to keep ticking under them.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var nav := UiStickNav.new()
	nav.name = UiStickNav.NODE_NAME
	add_child(nav)
