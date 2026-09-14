## Affix whose FLAT value is a fraction of 1 (`+0.12` on `damage_fire` = +12% fire damage).
## `Affix.roll()` rounds every FLAT roll to a whole number and `Affix.describe()` prints it as
## "+%d", which turns every such affix into "+0". Fractional affix resources use this script
## instead so rolls keep their precision and tooltips read as percentages.
## Stat semantics are unchanged: the value is still registered with `Stats.add_flat`.
class_name FractionAffix
extends Affix

## Rolled values are snapped to 1/200 so they survive a JSON save round trip unchanged.
const STEPS_PER_UNIT := 200.0


func roll(rng: RandomNumberGenerator, rarity_scale: float = 1.0) -> float:
	var v := rng.randf_range(min_value, max_value) * rarity_scale
	if mode == Mode.ON_HIT_STATUS:
		return clampf(roundf(v * 100.0) / 100.0, 0.0, 1.0)
	return roundf(v * STEPS_PER_UNIT) / STEPS_PER_UNIT


func describe(value: float) -> String:
	if mode == Mode.ON_HIT_STATUS:
		return super(value)
	return "+%d%% %s" % [int(roundf(value * 100.0)), ItemGenerator.stat_label(stat)]
