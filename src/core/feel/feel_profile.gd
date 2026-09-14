## Every tunable number the game-feel layer uses (docs §6: "hit-stop 2–4 frames; screen shake
## scaled by hit"). Lives as data so impact can be retuned without touching code:
## `data/feel/feel.tres` is the shipped profile, loaded once by `GameFeel`.
class_name FeelProfile
extends Resource

## Path of the shipped profile. `GameFeel` falls back to the script defaults when it is missing.
const DEFAULT_PATH := "res://data/feel/feel.tres"

@export_group("Hit stop")
## `Engine.time_scale` while a hit-stop is running (0 would also stall real-time timers).
@export_range(0.0, 1.0, 0.01) var hit_stop_scale: float = 0.05
## Frames a normal hit freezes for (docs §6 asks for 2–4).
@export_range(0, 12) var hit_stop_light_frames: int = 2
## Frames a heavy hit (crit, finisher, `heavy_damage`+) freezes for.
@export_range(0, 12) var hit_stop_heavy_frames: int = 4
## Hard ceiling on the queue: overlapping hits pick the longest, never the sum.
@export_range(0, 20) var hit_stop_max_frames: int = 5
## Frames after a stop ends during which another request is dropped, so a busy screen (a
## whirlwind in a pack of six) cannot chain stops into a slideshow.
@export_range(0, 60) var hit_stop_refractory_frames: int = 8
## Damage at or above this counts as a heavy hit (frames, trauma and camera punch).
@export var heavy_damage: float = 25.0

@export_group("Screen shake")
## Trauma (0..1) added by a light hit; the offset is `max_offset * trauma²`.
@export_range(0.0, 1.0, 0.01) var trauma_light: float = 0.22
@export_range(0.0, 1.0, 0.01) var trauma_heavy: float = 0.45
@export_range(0.0, 1.0, 0.01) var trauma_death: float = 0.7
## Trauma lost per second. A shake given an explicit duration decays at least fast enough to
## be gone when that duration elapses.
@export var trauma_decay: float = 2.2
## Peak camera offset in px at trauma 1.
@export var shake_max_offset: float = 6.0
## Shake oscillations per second (the offset is resampled, not smoothed, at this rate).
@export var shake_frequency: float = 26.0

@export_group("Camera")
## Peak px the camera leads the aim direction by.
@export var look_ahead_px: float = 14.0
## Exponential rate the look-ahead offset converges at.
@export var look_ahead_speed: float = 3.5
## Px the camera is kicked along the hit direction by a heavy hit.
@export var punch_px: float = 5.0
## Exponential rate the punch offset decays at.
@export var punch_decay: float = 11.0

@export_group("Flash")
## Seconds a hit flash takes to fade out.
@export var flash_time: float = 0.12
## Peak flash strength (1 = fully white).
@export_range(0.0, 4.0, 0.05) var flash_strength: float = 1.0
## Multiplier applied to every flash while the `reduced_flash` setting is on.
@export_range(0.0, 1.0, 0.05) var reduced_flash_scale: float = 0.25
## Multiplier the hit-flash peak is built from: `self_modulate` peaks at
## `1 + flash_peak_mul * strength`. The old 2.0 clipped every channel to pure white, which
## erased the sprite inside the flash and welded a scrum into one blob (docs §1 pillar 1).
@export_range(0.0, 3.0, 0.05) var flash_peak_mul: float = 1.3
## Entities allowed a full-strength flash in one physics frame. Further claims in the same
## frame are scaled by `flash_crowd_scale`, so a pack landing together still reads as a pack.
@export_range(1, 16) var flash_budget_per_frame: int = 2
## Strength multiplier for flashes past `flash_budget_per_frame` in the same frame.
@export_range(0.0, 1.0, 0.05) var flash_crowd_scale: float = 0.35

@export_group("Damage numbers")
## Seconds a floating number lives.
@export var number_lifetime: float = 0.8
## Total px a floating number travels upward over its life, at a constant speed. The old
## damped form integrated to about 7 px - under half a tile - so the number sat on the fight.
@export var number_rise_px: float = 30.0
## Px above the hit position a number starts, so it clears a 16 px character's head.
@export var number_head_offset_px: float = 14.0
## Peak horizontal drift in px over a number's life (randomised per pop, sign included).
@export var number_drift_px: float = 4.0
## How many times a number may be pushed up out of an occupied lane before it is placed anyway.
@export_range(1, 8) var number_lane_slots: int = 4
## Horizontal window, in px, two numbers must be within to count as overlapping.
@export var number_lane_width_px: float = 24.0
## Extra scale a normal number pops in at.
@export_range(0.0, 2.0, 0.05) var number_punch: float = 0.25
## Extra scale a crit pops in at.
@export_range(0.0, 2.0, 0.05) var number_crit_punch: float = 0.35

@export_group("Death")
## Particles in a normal death burst (scaled up for big sprites).
@export_range(1, 128) var death_burst_count: int = 16
## `Engine.time_scale` for the brief slow after the blow that empties a room.
@export_range(0.05, 1.0, 0.05) var room_clear_slow_scale: float = 0.35
## Real seconds that slow lasts.
@export var room_clear_slow_time: float = 0.3
## Frames within which a `room_cleared` must follow the last `enemy_died` to count as the
## room-ending blow (rather than a room that was already empty being unlocked).
@export_range(1, 60) var room_clear_window_frames: int = 12

@export_group("Danger tell")
## Pulses per second of every "this will hurt" tell (enemy windup and trap arming alike).
@export var tell_pulse_hz: float = 7.0
## Tell alpha at the bottom of the pulse.
@export_range(0.0, 1.0, 0.01) var tell_alpha_min: float = 0.15
## Tell alpha at the top of the pulse.
@export_range(0.0, 1.0, 0.01) var tell_alpha_max: float = 0.5

@export_group("FX pool")
## Particles in a pooled impact puff. Kept low on purpose: a puff is dust marking where a hit
## landed, and at 480x270 a dozen bright dots per hit is a bigger white mass than the flash.
@export_range(1, 64) var puff_count: int = 5
## Particles in the puff a heavy hit (`heavy_damage`+) throws.
@export_range(1, 64) var puff_heavy_count: int = 7
## Smallest and largest scale of a pooled particle, on a 2x2 px dot. Above about 1.0 a spark
## is wider than a character's eye, which is the point at which dust starts hiding sprites.
@export_range(0.1, 4.0, 0.1) var puff_scale_min: float = 0.4
@export_range(0.1, 4.0, 0.1) var puff_scale_max: float = 0.9
## Seconds a pooled puff lives.
@export var puff_lifetime: float = 0.22
## Particles alive in a pooled projectile trail.
@export_range(1, 64) var trail_count: int = 10
## Seconds a pooled trail particle lives.
@export var trail_lifetime: float = 0.3


## The shipped profile, or a default-constructed one when `data/feel/feel.tres` is missing.
static func load_default() -> FeelProfile:
	if ResourceLoader.exists(DEFAULT_PATH):
		var res := load(DEFAULT_PATH) as FeelProfile
		if res != null:
			return res
	return FeelProfile.new()


## Frames a hit of `amount` damage freezes for; crits and finishers pass `heavy` directly.
func hit_stop_frames(amount: float, heavy: bool = false) -> int:
	if heavy or amount >= heavy_damage:
		return hit_stop_heavy_frames
	return hit_stop_light_frames


## Trauma a hit of `amount` damage adds.
func hit_trauma(amount: float, heavy: bool = false) -> float:
	if heavy or amount >= heavy_damage:
		return trauma_heavy
	return trauma_light
