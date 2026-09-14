## Turns a shipped `Ability` resource into numbers the balance simulation can add up.
##
## Nothing here re-implements an ability: every value is read off the resource's own exports
## (`data/abilities/<id>.tres`), so retuning an ability retunes the simulation. What this file
## owns is the *conversion* — how "freeze for 3 s every 9 s" becomes a share of damage avoided
## — and every conversion constant lives in `BalanceProfile`, never in this script.
##
## Passives split in two: the half that is a plain `Stats` modifier goes through
## `apply_stats()` (registered under the same `passive:<id>` owner id the live game uses) and
## the half that is not goes through `effect_of()`.
class_name SimAbilityModel
extends RefCounted

## Actives whose damage is dealt once per cast to a small group around the aim point.
const AREA_RADIUS_KEYS: Array[StringName] = [&"burst_radius", &"radius", &"sweep_radius"]


## Registers the `Stats` half of a passive under `passive:<id>`. Actives register nothing.
static func apply_stats(
	ability: Ability, tier: int, stats: Stats, profile: BalanceProfile, equipped_items: int
) -> void:
	if ability == null or ability.kind != Ability.Kind.PASSIVE:
		return
	var oid := StringName("passive:" + String(ability.id))
	var t := maxi(1, tier)
	match ability.id:
		&"glass_cannon":
			var bonus := _scaled(ability, &"damage_bonus", &"damage_per_tier", t)
			for stat: StringName in [&"damage_melee", &"damage_ranged", &"damage_ability"]:
				stats.add_flat(stat, oid, bonus)
			var relief := _num(ability, &"hp_penalty_relief_per_tier", 0.0) * float(t - 1)
			stats.add_percent(
				&"max_hp", oid, -maxf(0.0, _num(ability, &"hp_penalty", 0.0) - relief)
			)
		&"dotfiles":
			var points := _num(ability, &"points_per_item", 1.0) * float(equipped_items * t)
			if points > 0.0:
				stats.add_flat(DotfilesPassive.lowest_primary(stats), oid, points)
		&"lucky_coin":
			stats.add_flat(&"luck", oid, _num(ability, &"luck_per_tier", 0.0) * float(t))
		&"buyout":
			stats.add_flat(&"gold_find", oid, _scaled(ability, &"gold_drop_bonus", &"per_tier", t))
		&"sure_footed":
			stats.add_percent(
				&"move_speed", oid, _scaled(ability, &"move_speed_bonus", &"per_tier", t)
			)
		&"adrenaline":
			var window := _scaled(ability, &"attack_speed_bonus", &"per_tier", t)
			stats.add_percent(&"attack_speed", oid, window * profile.adrenaline_uptime)
		&"close_quarters", &"second_wind":
			stats.add_flat(&"armor", oid, _scaled(ability, &"armor", &"armor_per_tier", t))
		_:
			var stat_passive := ability as StatPassive
			if stat_passive != null:
				var copy := stat_passive.duplicate_ability() as StatPassive
				copy.tier = t
				copy.apply_to_stats(stats)


## The non-`Stats` half of an ability. `context` carries {"ranged": bool, "max_hp": float}
## because a few conversions depend on the build the ability landed in.
static func effect_of(
	ability: Ability, tier: int, stats: Stats, profile: BalanceProfile, context: Dictionary
) -> SimEffect:
	if ability == null:
		return SimEffect.new()
	if ability.kind == Ability.Kind.ACTIVE:
		return _active_effect(ability as ActiveAbility, tier, stats, profile, context)
	return _passive_effect(ability, tier, profile, context)


## Expected targets an ability with `radius` px of reach covers, given how far apart a pack
## stands (`BalanceProfile.enemy_spacing_px`).
static func targets_for(radius: float, profile: BalanceProfile) -> float:
	if radius <= 0.0:
		return profile.single_target_count
	var spread := 1.0 + radius / maxf(1.0, profile.enemy_spacing_px)
	return clampf(spread, profile.single_target_count, profile.max_ability_targets)


static func _passive_effect(
	ability: Ability, tier: int, profile: BalanceProfile, context: Dictionary
) -> SimEffect:
	var out := SimEffect.new()
	var t := maxi(1, tier)
	var curse := ability as CursePassive
	if curse != null and curse.damage_penalty > 0.0:
		# A curse's damage cut lives on the outgoing-hit path, not in `Stats`, so `apply_stats`
		# cannot see it. Without this the simulation would price the pact as free.
		out.damage_mult *= maxf(0.0, 1.0 - curse.damage_penalty)
	match ability.id:
		&"vampiric":
			out.lifesteal = _scaled(ability, &"lifesteal", &"per_tier", t)
		&"thorns":
			out.reflect = _scaled(ability, &"reflect_fraction", &"per_tier", t)
			var pool := _scaled(ability, &"max_hp_fraction", &"max_hp_per_tier", t)
			out.reflect_per_hit = pool * float(context.get("max_hp", 100.0))
		&"tiling_wm":
			out.damage_mult = (
				1.0 + _scaled(ability, &"bonus", &"per_tier", t) * profile.tiling_uptime
			)
		&"second_wind":
			var bonus := _scaled(ability, &"damage_bonus", &"per_tier", t)
			out.damage_mult = 1.0 + bonus * profile.low_hp_uptime
		&"heavy_hands":
			var mult := _scaled(ability, &"multiplier", &"per_tier", t)
			out.avoid = maxf(0.0, mult - 1.0) * profile.knockback_to_avoidance
		&"sure_footed":
			var speed := _scaled(ability, &"move_speed_bonus", &"per_tier", t)
			out.avoid = speed * profile.speed_to_avoidance
		&"ricochet":
			if bool(context.get("ranged", false)):
				var bounces := _num(ability, &"bounces_per_tier", 1.0) * float(t)
				out.damage_mult = 1.0 + bounces * profile.bounce_dps_gain
		&"hotkey":
			var refund := _scaled(ability, &"refund_fraction", &"per_tier", t)
			var saved := clampf(refund * profile.hotkey_kill_share, 0.0, 0.75)
			out.ability_rate_mult = 1.0 / (1.0 - saved)
		&"overflow":
			var every := maxf(2.0, _num(ability, &"every_n", 4.0))
			out.ability_rate_mult = every / (every - 1.0)
			out.ability_damage_mult = 1.0 + _scaled(ability, &"power_bonus", &"per_tier", t) / every
		&"close_quarters":
			# The armour half is a Stats modifier; only the melee damage half lands here, and
			# only for a build actually swinging a melee weapon.
			if not bool(context.get("ranged", false)):
				out.damage_mult = 1.0 + _scaled(ability, &"melee_bonus", &"per_tier", t)
		&"pipeline":
			var stacks := _num(ability, &"max_stacks", 5.0) * profile.kill_stack_uptime
			out.damage_mult = 1.0 + _scaled(ability, &"per_stack", &"per_tier", t) * stacks
		&"rootkit":
			var first := _scaled(ability, &"first_hit_bonus", &"per_tier", t)
			out.damage_mult = 1.0 + first * profile.first_hit_share
		&"buyout":
			out.damage_per_gold = _num(ability, &"damage_per_gold", 0.0) * float(t)
			out.damage_per_gold_cap = _num(ability, &"damage_cap", 0.0)
		&"cron_job":
			var share := _scaled(ability, &"heal_fraction", &"per_tier", t)
			var max_hp := float(context.get("max_hp", 100.0))
			out.heal_per_second = share * max_hp / maxf(1.0, profile.room_fight_seconds)
	return out


static func _active_effect(
	ability: ActiveAbility, tier: int, stats: Stats, profile: BalanceProfile, context: Dictionary
) -> SimEffect:
	var out := SimEffect.new()
	var cooldown := maxf(0.5, ability.cooldown * (1.0 - stats.get_value(&"cooldown_reduction")))
	var casts := profile.ability_uptime / cooldown
	var per_cast := _damage_per_cast(ability, tier, profile)
	if per_cast > 0.0:
		out.dps = per_cast * casts * _tag_multiplier(ability.tags, stats) * _crit_factor(stats)
	out.merge(_active_utility(ability, tier, profile, context, cooldown, casts))
	return out


## Damage one cast lands, summed over everything the ability's own exports describe.
static func _damage_per_cast(ability: ActiveAbility, tier: int, profile: BalanceProfile) -> float:
	var base := ability.damage * (1.0 + 0.25 * float(maxi(1, tier) - 1))
	if base <= 0.0:
		return _dot_damage(ability)
	match ability.id:
		&"turret":
			var ticks := (
				_num(ability, &"duration", 0.0) / maxf(0.1, _num(ability, &"fire_interval", 0.5))
			)
			return base * _landed_ticks(ticks, profile)
		&"whirlwind":
			var hits := (
				_num(ability, &"duration", 0.0) / maxf(0.05, _num(ability, &"hit_interval", 0.2))
			)
			return (
				base
				* _landed_ticks(hits, profile)
				* targets_for(_num(ability, &"radius", 0.0), profile)
			)
		&"volley":
			var arrows := _num(ability, &"arrow_count", 1.0)
			return base * minf(arrows, profile.max_ability_targets)
		&"fork_bomb":
			# A ring of processes covers the room, but only so many of them find a body.
			var forks := (
				_num(ability, &"process_count", 1.0)
				+ _num(ability, &"processes_per_tier", 0.0) * float(maxi(1, tier) - 1)
			)
			return base * minf(forks, profile.max_ability_targets)
		&"kill_9":
			return base * _execute_multiplier(ability, profile)
		&"rm_rf":
			# The sweep hits everything in reach; the execute on top only lands sometimes.
			return (
				base
				* targets_for(_area_radius(ability), profile)
				* _execute_multiplier(ability, profile)
			)
		&"siphon":
			return base
		&"chain_lightning":
			return base * _chain_multiplier(ability)
		&"contract":
			var seconds := _num(ability, &"duration", 0.0)
			return _num(ability, &"hireling_damage", 0.0) * seconds
	return base * targets_for(_area_radius(ability), profile) + _dot_damage(ability)


## Utility half of an active: shields, heals, crowd control and pure mobility.
static func _active_utility(
	ability: ActiveAbility,
	tier: int,
	profile: BalanceProfile,
	context: Dictionary,
	cooldown: float,
	casts: float
) -> SimEffect:
	var out := SimEffect.new()
	var max_hp := float(context.get("max_hp", 100.0))
	match ability.id:
		&"reboot":
			out.heal_per_second = (
				_scaled(ability, &"heal_fraction", &"heal_per_tier", tier) * max_hp * casts
			)
		&"bulwark":
			out.heal_per_second = (
				_scaled(ability, &"shield_fraction", &"shield_per_tier", tier) * max_hp * casts
			)
		&"warcry":
			var uptime := clampf(_num(ability, &"duration", 0.0) / cooldown, 0.0, 1.0)
			var empower := _scaled(ability, &"empower", &"empower_per_tier", tier)
			out.damage_mult = 1.0 + empower * uptime
			var armor := _scaled(ability, &"armor_bonus", &"armor_per_tier", tier)
			out.mitigation = (1.0 - Stats.armor_multiplier(armor)) * uptime
		&"frost_nova":
			out.mitigation = _cc_mitigation(
				_num(ability, &"frost_duration", 0.0), cooldown, profile
			)
		&"hostile_takeover":
			var seconds := (
				_num(ability, &"duration", 0.0)
				+ _num(ability, &"duration_per_tier", 0.0) * float(tier - 1)
			)
			out.mitigation = _cc_mitigation(seconds, cooldown, profile)
		&"shadowstep":
			# The teleport itself is mobility; the guaranteed crit it queues is damage, and the
			# empower window after it multiplies everything for a few seconds.
			out.avoid = profile.utility_avoid_per_cast * casts
			var hit := float(context.get("hit_damage", 0.0))
			out.dps = hit * maxf(0.0, profile.shadowstep_crit_bonus) * casts
			var step_empower := _scaled(ability, &"empower", &"empower_per_tier", tier)
			var step_uptime := clampf(_num(ability, &"empower_duration", 0.0) / cooldown, 0.0, 1.0)
			out.damage_mult = 1.0 + step_empower * step_uptime
		&"rm_rf":
			out.avoid = profile.utility_avoid_per_cast * casts
		&"stack_smash":
			out.mitigation = _cc_mitigation(
				(
					_num(ability, &"stun_duration", 0.0)
					+ _num(ability, &"stun_per_tier", 0.0) * float(tier - 1)
				),
				cooldown,
				profile
			)
		&"smoke_bomb":
			var cloud := (
				_num(ability, &"duration", 0.0)
				+ _num(ability, &"duration_per_tier", 0.0) * float(tier - 1)
			)
			var cloud_uptime := clampf(cloud / cooldown, 0.0, 1.0)
			out.mitigation = (
				_num(ability, &"weaken_magnitude", 0.0) * cloud_uptime * profile.cc_mitigation_share
				+ _num(ability, &"slow_magnitude", 0.0) * cloud_uptime * profile.cc_mitigation_share
			)
			out.avoid = (
				_num(ability, &"self_haste", 0.0) * cloud_uptime * profile.speed_to_avoidance
			)
		&"sudo":
			var root_seconds := (
				_num(ability, &"duration", 0.0)
				+ _num(ability, &"duration_per_tier", 0.0) * float(tier - 1)
			)
			var root_uptime := clampf(root_seconds / cooldown, 0.0, 1.0)
			out.damage_mult = (
				1.0 + _scaled(ability, &"empower", &"empower_per_tier", tier) * root_uptime
			)
			out.avoid = _num(ability, &"haste", 0.0) * root_uptime * profile.speed_to_avoidance
		&"siphon":
			var drained := _damage_per_cast(ability, tier, profile)
			var share := _scaled(ability, &"heal_fraction", &"heal_per_tier", tier)
			out.heal_per_second = drained * share * casts
	return out


## Average damage multiplier of an execute ability: `execute_multiplier` on the share of casts
## that catch a target already under the threshold, 1.0 on the rest. `rm -rf`'s execute deletes
## the target outright, which is worth the same multiplier as a very large hit.
static func _execute_multiplier(ability: ActiveAbility, profile: BalanceProfile) -> float:
	var multiplier := _num(ability, &"execute_multiplier", 2.5)
	var share := clampf(profile.execute_share, 0.0, 1.0)
	return 1.0 + (multiplier - 1.0) * share


## Ticks of a multi-hit active that connect: the first always, the rest at `tick_hit_share`.
static func _landed_ticks(ticks: float, profile: BalanceProfile) -> float:
	return 1.0 + maxf(0.0, ticks - 1.0) * profile.tick_hit_share


static func _cc_mitigation(seconds: float, cooldown: float, profile: BalanceProfile) -> float:
	return clampf(seconds / maxf(0.5, cooldown), 0.0, 1.0) * profile.cc_mitigation_share


static func _chain_multiplier(ability: ActiveAbility) -> float:
	var falloff := clampf(_num(ability, &"falloff", 1.0), 0.0, 1.0)
	var targets := maxi(1, int(_num(ability, &"max_targets", 1.0)))
	var total := 0.0
	var factor := 1.0
	for _i in range(targets):
		total += factor
		factor *= falloff
	return total


static func _dot_damage(ability: ActiveAbility) -> float:
	return _num(ability, &"burn_dps", 0.0) * _num(ability, &"burn_duration", 0.0)


static func _area_radius(ability: ActiveAbility) -> float:
	for key: StringName in AREA_RADIUS_KEYS:
		var value := _num(ability, key, 0.0)
		if value > 0.0:
			return value
	return 0.0


static func _tag_multiplier(tags: Array[StringName], stats: Stats) -> float:
	var mult := 1.0
	for tag: StringName in tags:
		mult *= 1.0 + stats.get_value(StringName("damage_" + String(tag)))
	return mult


static func _crit_factor(stats: Stats) -> float:
	return 1.0 + stats.get_value(&"crit_chance") * (stats.get_value(&"crit_mult") - 1.0)


## `base` plus `per_tier` for every tier past the first, read off the resource's exports.
static func _scaled(res: Resource, base_key: StringName, tier_key: StringName, tier: int) -> float:
	return _num(res, base_key, 0.0) + _num(res, tier_key, 0.0) * float(maxi(1, tier) - 1)


static func _num(res: Resource, key: StringName, fallback: float) -> float:
	if res == null:
		return fallback
	var value: Variant = res.get(key)
	if value == null:
		return fallback
	return float(value)
