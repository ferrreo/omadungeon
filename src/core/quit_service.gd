## Autoload (`Quit`): owns the one answer to "the window manager asked us to close".
##
## Why this is an autoload and not a line in whichever screen is up. The engine's default is
## `SceneTree.auto_accept_quit`, which ends the process the instant the close arrives and
## gives `QuitGuard` no chance to arm its watchdog (docs 14, "the exit is a check"), so the
## flag is turned off - and the moment it is off, the close request does nothing at all unless
## some node in the tree turns it back into a quit. That node used to be `Main`. `Main` is the
## *boot* scene: `RunManager.new_run()` swaps it for `src/game.tscn` and frees it, so from the
## first floor onwards nobody answered. Measured 2026-09-14 in nested sway with a built floor
## up (`swaymsg kill`, the same `xdg_toplevel.close` a title-bar X or Alt+F4 sends): the
## request arrived, `SaveManager` flushed on it, and the game then sat there - still alive
## 30 s later, window and all. Not intermittent, not a race: a player could not close the
## window during a run at all, on any platform.
##
## An autoload is added by the engine before the main scene exists and outlives every scene
## swap, so the answer is there on the title screen, on floor 1 and on the summary alike.
## `SaveManager` flushes on the same notification; the quit only takes effect at the end of
## the frame, so both happen whatever order the notification reaches them in.
extends Node


func _ready() -> void:
	# The pause menu and the boards pause the tree; a close request has to be answered under
	# them too.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Off the engine's instant exit, so the close request reaches `_notification` below and
	# leaves through `QuitGuard` like the Quit button does.
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	SaveManager.flush_autosave()
	QuitGuard.request(get_tree())
