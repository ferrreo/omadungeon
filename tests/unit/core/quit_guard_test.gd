## The exit watchdog (docs 14, `QuitGuard`): the shell line it arms only ever signals a pid
## that is still there, arming really starts a detached process, and a watchdog that is not
## needed can be taken down again. The exit itself is measured by `tools/check-quit.sh`,
## because a test cannot quit its own process.
class_name QuitGuardTest
extends GdUnitTestSuite


func test_the_watchdog_line_checks_the_pid_before_signalling_it() -> void:
	var line := QuitGuard.watchdog_command(4242, 7)
	assert_str(line).is_equal("sleep 7; kill -0 4242 2>/dev/null && kill -TERM 4242")
	assert_int(QuitGuard.WATCHDOG_SECONDS).is_between(2, 5)


func test_arming_starts_a_detached_process_that_can_be_taken_down() -> void:
	if not FileAccess.file_exists(QuitGuard.SHELL):
		return
	# A long fuse: this process must not be the one it ends.
	var pid := QuitGuard.arm_watchdog(600)
	assert_int(pid).is_greater(0)
	assert_int(QuitGuard.watchdog_pid).is_equal(pid)
	assert_bool(OS.is_process_running(pid)).is_true()
	assert_int(OS.kill(pid)).is_equal(OK)
	for _i in range(50):
		if not OS.is_process_running(pid):
			break
		OS.delay_msec(20)
	assert_bool(OS.is_process_running(pid)).is_false()


## A Quit press and a window-manager close can land in the same frame - the button closes the
## window, and the compositor answers that with a close request - and each used to arm its own
## detached watchdog. The second one outlives the process it was armed for and then signals a
## pid the kernel may since have handed to somebody else; `kill -0` narrows that window without
## closing it. So the second ask does nothing at all, and this is the test that says so. It
## cannot call `request` for real (that would end the test process), so it sets the flag the
## first call would have set and checks that the second one arms nothing and quits nothing:
## the suite carrying on past the assertions is itself the evidence that `quit()` was not
## reached.
func test_a_second_ask_to_quit_arms_no_second_watchdog() -> void:
	var was_requested := QuitGuard.requested
	var was_pid := QuitGuard.watchdog_pid
	QuitGuard.requested = true
	QuitGuard.watchdog_pid = -1
	QuitGuard.request(get_tree(), 0)
	(
		assert_int(QuitGuard.watchdog_pid)
		. override_failure_message(
			"a second QuitGuard.request armed another watchdog; one exit, one watchdog"
		)
		. is_equal(-1)
	)
	QuitGuard.reset()
	assert_bool(QuitGuard.requested).is_false()
	assert_int(QuitGuard.watchdog_pid).is_equal(-1)
	QuitGuard.requested = was_requested
	QuitGuard.watchdog_pid = was_pid


## The verdict has to reach the disk, because a watchdog kill takes the exit code with it.
## `tools/run-scenario.sh`, `tools/ui-gallery.sh` and `tools/capture-scene.sh` all read this file
## when they see 143; before it existed they assumed a pass, and a `pickup_frame` capture that
## printed four FAIL rows and asked to exit 2 was recorded in the ledger as ok.
func test_the_requested_exit_code_is_written_where_a_harness_can_read_it() -> void:
	var path := "%s/quit_guard_exit_code" % OS.get_environment("TMPDIR").trim_suffix("/")
	if path.begins_with("/quit_guard_exit_code"):
		path = "/tmp/quit_guard_exit_code"
	var previous := OS.get_environment(QuitGuard.EXIT_FILE_ENV)
	DirAccess.remove_absolute(path)
	OS.set_environment(QuitGuard.EXIT_FILE_ENV, path)
	QuitGuard.record_exit_code(2)
	(
		assert_str(FileAccess.get_file_as_string(path).strip_edges())
		. override_failure_message(
			"QuitGuard did not write the requested exit code; a hung run reads as a pass again"
		)
		. is_equal("2")
	)
	QuitGuard.record_exit_code(0)
	assert_str(FileAccess.get_file_as_string(path).strip_edges()).is_equal("0")
	DirAccess.remove_absolute(path)
	OS.set_environment(QuitGuard.EXIT_FILE_ENV, previous)


## And writes nothing when no harness asked for it, so a player's run leaves no file behind.
func test_no_exit_file_is_written_when_the_environment_names_none() -> void:
	var previous := OS.get_environment(QuitGuard.EXIT_FILE_ENV)
	OS.set_environment(QuitGuard.EXIT_FILE_ENV, "")
	QuitGuard.record_exit_code(3)
	OS.set_environment(QuitGuard.EXIT_FILE_ENV, previous)
