## What the rendered music scenarios are allowed to assert about a track change.
##
## Kept out of `TestScenarios` because it is a rule about music rather than scenario plumbing,
## and because that file is against its 1200-line cap.
class_name ScenarioMusicRules
extends RefCounted

## How far luminance may fall between two frames of a crossfade before it stops being one.
## Not zero: the frames are measured off a rendered viewport, so the last digit wobbles.
const FADE_SLACK := 0.002


## Returns the complaint to fail with, or "" when the series is what a track change looks like.
##
## Monotonic while the crossfade runs, and after it only that the loud track is still louder
## than the calm one it replaced. A frame past `crossfade_seconds` is not measuring the fade
## any more: the mood has arrived and the live envelope owns the light, and that follows what
## the track is doing right now, which is allowed to fall. Requiring the whole series to rise
## asserted that the owner's in-track reaction had not been built, and CI failed on exactly
## that - luminance climbed 0.10 to 0.27 across the fade, then dipped on the 6 s frame, which
## is a quiet passage doing its job.
static func fault_in_change(
	luminances: PackedFloat32Array, frame_times: PackedFloat32Array, fade_seconds: float
) -> String:
	if luminances.size() < 2:
		return "the track-change series has fewer than two frames"
	for i in range(1, luminances.size()):
		if i < frame_times.size() and frame_times[i] > fade_seconds:
			continue
		if luminances[i] < luminances[i - 1] - FADE_SLACK:
			return "luminance fell between frames %d and %d: not a monotonic crossfade" % [i - 1, i]
	if luminances[luminances.size() - 1] <= luminances[0]:
		return "the loud track ended no brighter than the calm one it replaced"
	return ""
