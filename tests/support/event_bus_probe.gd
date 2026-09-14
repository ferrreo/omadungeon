## Records the `EventBus` connections one test makes and takes them all back again.
##
## `EventBus` is an autoload, so it outlives every suite in the process. A test that connects
## an anonymous lambda to one of its signals can never disconnect it - there is no handle to
## pass to `disconnect()` - and the handler then keeps firing for every later suite in the run.
## That is how a suite's result comes to depend on which suites ran before it: the classic
## symptom is a test that passes alone and fails in the whole tree.
##
## Usage:
## [codeblock]
## var probe := EventBusProbe.new()
## var seen: Array[StringName] = []
## probe.watch(EventBus.spawn_pickup, func(kind: StringName, _p: Vector2, _a: int) -> void:
##     seen.append(kind))
## ...
## probe.release()
## [/codeblock]
##
## Keep the probe as a suite member and call `release()` from `after_test()` as well, so a test
## that returns early still leaves the bus clean. `release()` is idempotent.
class_name EventBusProbe
extends RefCounted

var _watched: Array[Dictionary] = []


## Connects `handler` to `sig` and remembers the pair so `release()` can undo it.
func watch(sig: Signal, handler: Callable) -> void:
	sig.connect(handler)
	_watched.append({"signal": sig, "handler": handler})


## Disconnects everything this probe connected. Safe to call twice.
func release() -> void:
	for entry: Dictionary in _watched:
		var sig: Signal = entry["signal"]
		var handler: Callable = entry["handler"]
		if sig.is_connected(handler):
			sig.disconnect(handler)
	_watched.clear()


## How many connections are still outstanding (0 after `release()`).
func watched_count() -> int:
	return _watched.size()
