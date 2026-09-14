## The watcher's debounce, and the one property it has to hold to be a debounce at all.
##
## The owner, after switching an Omarchy theme mid-run: "it lags like shit when I swap omarchy
## theme for a few seconds, the transition should be smooth as butter". The retint itself was
## never the problem - a seven-room floor costs about 35 ms of one frame, measured. What cost
## seconds was doing it seven times.
##
## Switching a theme is not one file write. Omarchy rewrites the theme link, `colors.toml`,
## the background and the hook over a couple of seconds, and the watcher polls every
## `POLL_INTERVAL`. Each poll that sees a difference arms `DEBOUNCE`. With the debounce
## *shorter* than the poll interval, it always expired before the next poll could see the next
## file land, so every poll applied a full palette change and started a wallpaper decode.
class_name DesktopWatcherDebounceTest
extends GdUnitTestSuite


## A debounce shorter than the interval that feeds it cannot coalesce anything, because it is
## always back at rest before the next observation arrives. Asserted against the constants
## rather than a behaviour, because this is arithmetic: the relationship is the guarantee, and
## either number moving without the other reintroduces the bug.
func test_the_debounce_outlasts_the_poll_that_feeds_it() -> void:
	(
		assert_float(Desktop.DEBOUNCE)
		. override_failure_message(
			(
				(
					"DEBOUNCE %.2fs is not longer than POLL_INTERVAL %.2fs, so it coalesces nothing: "
					+ "every poll during a theme switch applies its own retint and wallpaper decode"
				)
				% [Desktop.DEBOUNCE, Desktop.POLL_INTERVAL]
			)
		)
		. is_greater(Desktop.POLL_INTERVAL)
	)


## ...and not so long that the dungeon visibly lags behind the desktop. A swap should feel
## immediate; this is the budget for "the files have stopped moving".
func test_the_debounce_still_feels_immediate() -> void:
	assert_float(Desktop.DEBOUNCE).is_less(1.0)
