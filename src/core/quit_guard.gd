## The one way out of the process (docs 14, "the exit is a check"): `request(tree, code)`
## arms a watchdog and asks the tree to quit. `Main` routes the Quit button through it, the `Quit`
## autoload routes the window manager's close request, and so does the capture driver.
##
## Why a watchdog: Godot 4.7.1's Wayland display server runs its event reader on a thread
## whose loop is `wl_display_prepare_read` -> `poll(fd, -1)` -> check `thread_done`
## (`platform/linuxbsd/wayland/wayland_thread.cpp`, `_poll_events_thread`, unchanged on
## master), and shutdown (`WaylandThread::destroy`) sets `thread_done`, sends one
## `wl_display_roundtrip` to wake that poll, then joins the thread. If the reader is busy
## dispatching at that instant - and the teardown itself makes the compositor talk (buffer
## releases, surface leaves) - the roundtrip's reply is consumed by the main thread alone,
## the reader then enters its infinite poll with nothing left on the socket, `thread_done` is
## never looked at, and the join waits forever: the window stays up and the process never
## exits until some unrelated event happens to arrive. Measured here 2026-09-13/14: 1 exit in
## 12-24 under load, then 3 in 40 with a third of a second of render silence before the quit
## (so silence is no cure: the race is inside the teardown); every one stuck in
## `pthread_join` on the "Wayland Events" thread with that thread in `poll`; never headless
## (0 of 40), because there is no reader to race. Nothing a project can do reaches that join,
## so the guarantee is made from outside: a detached shell that sends SIGTERM to this process
## `WATCHDOG_SECONDS` after the request if it is still alive. A process that came down on
## its own is gone by then and the watchdog finds nothing; one the engine wedged ends with
## 143, which `tools/run-scenario.sh` and `tools/check-quit.sh` accept - and name - when the
## capture had already landed. Everything the game owes the disk is flushed before the
## request (`SaveManager.flush_autosave`), and the engine's own cleanup past the scene tree
## saves nothing.
class_name QuitGuard
extends RefCounted

## Seconds the engine gets to come down on its own before the watchdog ends the process.
## A clean rendered exit measures 1.4 s on this machine; the budget `tools/check-quit.sh`
## enforces is 5 s.
const WATCHDOG_SECONDS := 4
const SHELL := "/bin/sh"
## Environment variable naming a file to write the requested exit code into before quitting.
## Set by the harnesses (`tools/capture-scene.sh`, `tools/run-scenario.sh`, `tools/ui-gallery.sh`);
## unset for a player, and then nothing is written and nothing is left behind.
const EXIT_FILE_ENV := "OMADUNGEON_EXIT_FILE"

## Process id of the last watchdog armed, -1 when none was (tests read it).
static var watchdog_pid: int = -1

## True once a quit has been asked for. A second ask is a no-op: the Quit button and the
## window manager's close can both land in one frame (the button closes the window, which
## the compositor answers with a close request), and two asks used to leave two detached
## watchdogs behind - the second one outliving the process it was armed for by four seconds
## and then signalling a pid the kernel may have handed to somebody else. `kill -0` narrows
## that window but does not close it; not arming twice does.
static var requested: bool = false


## Quits `tree` with `code`. Records the code, then arms the watchdog, then asks the tree to go.
## The first call wins: a later one cannot change the exit code of a quit already under way.
static func request(tree: SceneTree, code: int = 0) -> void:
	if tree == null or requested:
		return
	requested = true
	record_exit_code(code)
	arm_watchdog()
	tree.quit(code)


## Writes `code` to the file named by `EXIT_FILE_ENV`, and does nothing when that is unset.
##
## Why the code has to reach the disk before the watchdog is armed. A watchdog kill ends the
## process with SIGTERM, so it exits 143 and the code the caller asked for is gone - and a
## harness looking only at 143 cannot tell "hung after a passing run" from "hung after a
## failing one". All three of them used to guess, and they guessed pass: measured by lighting2
## on 2026-09-14, a `pickup_frame` capture printed four FAIL contrast rows, called
## `request(tree, 2)`, wedged in the Wayland teardown, and was recorded in the results ledger
## as ok. The hang is bounded (docs 14) but it is not rare, so that is a standing licence for a
## red rendered check to read green. The verdict is written here instead of guessed there, and
## a harness that sees 143 with no file fails rather than passes: a verdict that died with the
## process is not a green one.
static func record_exit_code(code: int) -> void:
	var path := OS.get_environment(EXIT_FILE_ENV)
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("QuitGuard: could not write the exit code to %s" % path)
		return
	file.store_string("%d\n" % code)
	file.close()


## Forgets that a quit was asked for, so the next `request` arms again. For tests, which run
## many cases in one process; the game never needs it.
static func reset() -> void:
	requested = false
	watchdog_pid = -1


## Starts the detached watchdog. Returns its pid, or -1 when it could not be started (no
## shell, a platform without `OS.create_process`), in which case the exit is the engine's.
static func arm_watchdog(seconds: int = WATCHDOG_SECONDS) -> int:
	if not FileAccess.file_exists(SHELL):
		return -1
	watchdog_pid = OS.create_process(SHELL, ["-c", watchdog_command(OS.get_process_id(), seconds)])
	return watchdog_pid


## The shell line the watchdog runs: wait, then TERM the game if it is still there. `kill -0`
## first, so a pid that already went away is never signalled.
static func watchdog_command(pid: int, seconds: int) -> String:
	return "sleep %d; kill -0 %d 2>/dev/null && kill -TERM %d" % [seconds, pid, pid]
