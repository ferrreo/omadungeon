## Timings for `CompositorWindow`, the query that asks the desktop's compositor whether the
## game window is fullscreen. They live in `data/desktop/compositor.tres` rather than in the
## script because how often the game may shell out to `hyprctl` is a tuning decision.
class_name CompositorProfile
extends Resource

## Seconds between two queries. The answer only has to be fresh enough that a player who
## fullscreens with a window-manager keybind and then looks at the Video page sees the truth,
## so this is deliberately slower than a frame and far slower than the 0.3 s the theme watcher
## polls files at - a query costs a process spawn, a file poll does not.
@export var poll_seconds: float = 0.5

## Hard deadline for one query, handed to `timeout(1)` when the system has it. A compositor
## that has stopped answering must not wedge a worker thread for the rest of the session.
@export var query_timeout_seconds: float = 2.0
