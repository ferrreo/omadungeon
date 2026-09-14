## What a theme write is allowed to cost, and the one thing that makes it affordable.
##
## The owner, twice: "it lags like shit when I swap omarchy theme", then "there is still one
## large pause at the end of the transition ... it should be SMOOTH". Both were this.
##
## `UiTheme._write` sets about eighty theme items. Each one notifies every Control using that
## theme, and each notified Control re-resolves its styleboxes, fonts and icons. Measured on a
## real renderer, one write cost ~830 ms of a frame and three cost ~2.5 s - linear in writes,
## which is what says the cost is the notifications rather than the work. `_write` itself runs
## in under 20 ms.
##
## So the write detaches the theme from its controls first, changes it while nobody is
## listening, and hands it back. The swap went from a 4.9 s stall to an 83 ms frame.
class_name UiThemeWriteCostTest
extends GdUnitTestSuite


## The guarantee, stated as a behaviour rather than a duration: a write must not be seen by the
## controls while it is in progress. A duration would be a flaky assertion on a shared runner;
## this is the property that made the duration small, and it fails the moment someone writes
## the theme with the controls still attached.
func test_a_write_does_not_notify_the_controls_it_is_changing() -> void:
	var host: Control = auto_free(Control.new()) as Control
	add_child(host)
	UiTheme.apply(host)
	await get_tree().process_frame
	var seen := [0]
	# NOTIFICATION_THEME_CHANGED reaches a Control once per theme item that changes while it is
	# attached. With the detach in place it arrives for the reattach, and not once per item.
	host.theme_changed.connect(func() -> void: seen[0] += 1)
	UiTheme.rebuild(ReactivityFixtures.palette_for("gruvbox"))
	await get_tree().process_frame
	(
		assert_int(seen[0])
		. override_failure_message(
			(
				(
					"the control was notified %d times by one theme write: the theme is being "
					+ "changed while controls are still attached to it, which is the 830 ms frame"
				)
				% seen[0]
			)
		)
		. is_less_equal(4)
	)


## And the write still has to actually land, or the cheap version above is cheap for the wrong
## reason.
func test_a_write_still_reaches_the_controls() -> void:
	var host: Control = auto_free(Control.new()) as Control
	add_child(host)
	UiTheme.apply(host)
	UiTheme.rebuild(ReactivityFixtures.palette_for("gruvbox"))
	await get_tree().process_frame
	assert_object(host.theme).is_not_null()
	assert_object(host.theme).is_same(UiTheme.theme())
	var gruvbox := ReactivityFixtures.palette_for("gruvbox")
	assert_float(UiTheme.color(&"accent").r).is_equal_approx(gruvbox.get_color("accent").r, 0.02)
