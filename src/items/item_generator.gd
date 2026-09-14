## Procedural item generation (docs §4.5): base + rarity + rolled affixes + themed name.
## Every function is a pure function of its inputs and the RandomNumberGenerator passed in.
class_name ItemGenerator
extends RefCounted

## Value multiplier per rarity (common..legendary).
const RARITY_SCALE: Array[float] = [1.0, 1.15, 1.3, 1.5]
## Affix count per rarity.
const AFFIX_COUNT: Array[int] = [1, 2, 3, 4]
## Floor-0, luck-0 weights (common, rare, epic, legendary).
const BASE_RARITY_WEIGHTS: Array[float] = [70.0, 22.0, 7.0, 1.0]
## Per-floor drift added to the base weights.
##
## NOTE (round 5, measured, not changed): the playtest asked for a lower Legendary drift,
## because a finished build is 24% Legendary-with-a-unique-effect. Three simulated variants
## were run against `tests/unit/balance` at 300 runs per class:
##
##   shipped  [-4.0, 2.0, 1.5, 0.5]  offered Legendary 10.6%   worn 23.7%
##   softened [-3.0, 1.5, 1.5, 0.2]  offered Legendary  8.8%   worn 21.1%
##   ...plus a halved luck lift        offered Legendary  8.1%  worn 20.3%
##
## Halving the supply moves what the player *wears* by three points, because a Legendary is
## never the card anybody leaves behind: the worn share is dominated by how long an item is
## kept, not by how often one is offered. And every one of those variants broke
## `test_difficulty_rises_smoothly` (and the softened one also the boss-threat ramp and the
## class-weapon identity table), because the difficulty curve is tuned against this item
## power. The lever that would actually work is on the *keeping* side - an upgrade rule, or
## Legendaries that are sideways rather than strictly better - and it is not a number here.
## `balance_targets_test.test_worn_item_rarity_is_a_pyramid_too` now measures the worn mix so
## the next attempt has a number to move.
const FLOOR_RARITY_DRIFT: Array[float] = [-4.0, 2.0, 1.5, 0.5]
const MIN_RARITY_WEIGHT := 0.5

## Stats whose flat rolls are whole numbers; every other flat stat is a fraction (0.1 = +10%).
const INTEGER_STATS: Array[StringName] = [
	&"vitality",
	&"might",
	&"precision",
	&"arcana",
	&"swiftness",
	&"fortune",
	&"max_hp",
	&"armor",
	&"life_on_kill",
	&"pickup_radius",
	&"projectile_count",
	&"pierce",
	&"move_speed",
]

## Count-style stats that must never be multiplied by the rarity scale: a "+1 projectile"
## affix would otherwise round up to +2 on legendaries.
const UNSCALED_STATS: Array[StringName] = [&"projectile_count", &"pierce"]

## Theme flavour words used in legendary names. Keys are matched as substrings of the
## lower-cased theme name; the first match wins.
const THEME_FLAVOURS: Dictionary = {
	"tokyo":
	{
		"prefix": ["Tokyo", "Neon-lit", "Shibuya"],
		"suffix": ["of the Night", "of Neon", "of Shinjuku"],
	},
	"nord":
	{
		"prefix": ["Nord-forged", "Fjord", "Aurora"],
		"suffix": ["of the North", "of Frost Harbour", "of the Polar Sky"],
	},
	"gruvbox":
	{
		"prefix": ["Gruvboxen", "Retro", "Groovy"],
		"suffix": ["of Warm Terminals", "of the Groove", "of Amber"],
	},
	"catppuccin":
	{
		"prefix": ["Catppuccin", "Frappé", "Pastel"],
		"suffix": ["of Mocha", "of Latte", "of Macchiato"],
	},
	"everforest":
	{
		"prefix": ["Everforest", "Mossy", "Verdant"],
		"suffix": ["of the Canopy", "of Old Growth", "of Ferns"],
	},
	"rose":
	{
		"prefix": ["Rosé", "Pine-scented", "Dawnlit"],
		"suffix": ["of Moon", "of Dawn", "of Iris"],
	},
	"kanagawa":
	{
		"prefix": ["Kanagawa", "Wave-tempered", "Ukiyo"],
		"suffix": ["of the Great Wave", "of Ink", "of Fuji"],
	},
	"matte":
	{
		"prefix": ["Matte", "Void-black", "Sable"],
		"suffix": ["of the Void", "of Obsidian", "of Silence"],
	},
	"osaka":
	{
		"prefix": ["Osaka", "Jade-veined", "Emerald"],
		"suffix": ["of Jade", "of the Harbour", "of Dotonbori"],
	},
	"ristretto":
	{
		"prefix": ["Ristretto", "Espresso", "Roasted"],
		"suffix": ["of the Bean", "of Crema", "of Midnight Coffee"],
	},
	"flexoki":
	{
		"prefix": ["Flexoki", "Inked", "Paper-bound"],
		"suffix": ["of Ink", "of Parchment", "of the Press"],
	},
	"ethereal":
	{
		"prefix": ["Ethereal", "Mist-woven", "Spectral"],
		"suffix": ["of Vapour", "of the Veil", "of Dreams"],
	},
	"hacker":
	{
		"prefix": ["Hackerman", "Phreaked", "Root"],
		"suffix": ["of /dev/null", "of the Mainframe", "of Zero-day"],
	},
}
const DEFAULT_FLAVOURS: Dictionary = {
	"prefix": ["Omarchy", "Tiled", "Hyprland"],
	"suffix": ["of the Dotfiles", "of the Compositor", "of Super+Enter"],
}


## Rarity weights for a floor and luck value (luck is the `luck` stat, 0.0 = none).
static func rarity_weights(floor_index: int, luck: float) -> Array[float]:
	var out: Array[float] = []
	var f := float(maxi(0, floor_index))
	var l := maxf(0.0, luck)
	for i in range(4):
		var w := BASE_RARITY_WEIGHTS[i] + FLOOR_RARITY_DRIFT[i] * f
		if i == 0:
			w *= maxf(0.2, 1.0 - l)
		else:
			# NOTE (round 5): this flat lift quadruples the Legendary weight at luck 1.0, and
			# the simulation says it - not the floor drift above - is what dominates the
			# *worn* Legendary share. Softening it for the top rung is the next lever; it was
			# not changed here because it could not be re-simulated in this round.
			w *= 1.0 + l * float(i)
		out.append(maxf(MIN_RARITY_WEIGHT, w))
	return out


static func roll_rarity(
	floor_index: int, rng: RandomNumberGenerator, luck: float
) -> ItemInstance.Rarity:
	return _weighted_index(rarity_weights(floor_index, luck), rng) as ItemInstance.Rarity


## Generates one item. `slot_filter` holds ItemBase.Slot ints (empty = any slot);
## `force_rarity` overrides the rarity roll (-1 = roll). `theme_name` seasons legendary
## names (empty = current desktop theme, "" also when no desktop is running).
## `style_filter` holds `WeaponBase.Style` ints and narrows *weapon* bases only (empty = any),
## which is how a chest offers a weapon in the family the player is already fighting with.
static func generate(
	registry: ItemRegistry,
	floor_index: int,
	rng: RandomNumberGenerator,
	luck: float = 0.0,
	slot_filter: Array[int] = [],
	force_rarity: int = -1,
	theme_name: String = "",
	style_filter: PackedInt32Array = PackedInt32Array()
) -> ItemInstance:
	var candidates := registry.bases_for(slot_filter, floor_index, style_filter)
	if candidates.is_empty():
		push_error("ItemGenerator: registry has no bases")
		return null
	var base := candidates[_weighted_index(draw_weights(candidates), rng)]
	var rarity: ItemInstance.Rarity
	if force_rarity >= 0:
		rarity = clampi(force_rarity, 0, 3) as ItemInstance.Rarity
	else:
		rarity = roll_rarity(floor_index, rng, luck)
	var item := instance_of(base, rng, rarity)
	item.affixes = roll_affixes(registry, base, rarity, rng)
	if rarity == ItemInstance.Rarity.LEGENDARY:
		item.unique_effect = UniqueEffects.pick(rng)
	var prefix := ""
	var suffix := ""
	for entry: Dictionary in item.affixes:
		var affix: Affix = entry["affix"]
		if prefix.is_empty() and not affix.prefix.is_empty():
			prefix = affix.prefix
		elif suffix.is_empty() and not affix.suffix.is_empty():
			suffix = affix.suffix
	var theme := theme_name if not theme_name.is_empty() else current_theme_name()
	item.display_name = compose_name(base.display_name, prefix, suffix, rarity, theme, rng.randf())
	return item


## Draw weights for `candidates`: each base's own `weight`, with the weapon bases redistributed
## so that every `WeaponBase.Family` present is equally likely to be the family drawn.
##
## A weapon drop picks a family first and a base inside it second. Without that rule the family
## that happens to ship the most bases wins every unbiased roll: `data/items/**` holds seven
## melee bases droppable on floor 7 against four projectile and two arcane ones, so a raw
## weighted draw handed *every* class a melee weapon 54% of the time. The chest's own
## family bias could not undo it, because it re-rolls towards the weapon the player is
## *holding*: one good sword from a shop and a Ranger's chests start reinforcing the sword.
##
## The weapon slot's total weight is preserved, so this changes which weapon drops and never
## how often a weapon drops instead of armour or a ring.
static func draw_weights(candidates: Array[ItemBase]) -> Array[float]:
	var family_total: Dictionary = {}
	var weapon_total := 0.0
	for base: ItemBase in candidates:
		var weapon := base as WeaponBase
		if weapon == null:
			continue
		var weight := maxf(0.01, base.weight)
		weapon_total += weight
		family_total[int(weapon.family())] = (
			float(family_total.get(int(weapon.family()), 0.0)) + weight
		)
	var per_family := weapon_total / float(maxi(1, family_total.size()))
	var out: Array[float] = []
	for base: ItemBase in candidates:
		var weight := maxf(0.01, base.weight)
		var weapon := base as WeaponBase
		if weapon == null:
			out.append(weight)
			continue
		var total := float(family_total.get(int(weapon.family()), weight))
		out.append(per_family * weight / maxf(0.01, total))
	return out


## A bare instance of `base` with no affixes (class start weapons, shop stock fillers).
static func instance_of(
	base: ItemBase,
	rng: RandomNumberGenerator,
	rarity: ItemInstance.Rarity = ItemInstance.Rarity.COMMON
) -> ItemInstance:
	var item := ItemInstance.new()
	item.base = base
	item.rarity = rarity
	# 53 bits so the uid survives a JSON (double) round trip in saves.
	item.uid = (rng.randi() << 21) | (rng.randi() & 0x1FFFFF)
	item.seed_hash = rng.randi()
	item.display_name = base.display_name
	return item


## Rolls `AFFIX_COUNT[rarity]` affixes with distinct stats for `base`.
static func roll_affixes(
	registry: ItemRegistry, base: ItemBase, rarity: int, rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pool := registry.affixes_for(base.slot_name(), rarity, base)
	var used: Array[StringName] = []
	var count := AFFIX_COUNT[clampi(rarity, 0, 3)]
	for _i in range(count):
		var candidates: Array[Affix] = []
		var weights: Array[float] = []
		for affix: Affix in pool:
			if used.has(affix.stat):
				continue
			candidates.append(affix)
			weights.append(maxf(0.01, affix.weight))
		if candidates.is_empty():
			break
		var affix := candidates[_weighted_index(weights, rng)]
		used.append(affix.stat)
		out.append({"affix": affix, "value": roll_affix_value(affix, rng, RARITY_SCALE[rarity])})
	return out


## Rolls an affix value. Whole numbers for INTEGER_STATS, fractions elsewhere
## (Affix.roll() would round every FLAT to an int, which breaks fractional stats).
static func roll_affix_value(
	affix: Affix, rng: RandomNumberGenerator, rarity_scale: float
) -> float:
	var scale := 1.0 if UNSCALED_STATS.has(affix.stat) else rarity_scale
	var v := rng.randf_range(affix.min_value, affix.max_value) * scale
	match affix.mode:
		Affix.Mode.FLAT:
			if INTEGER_STATS.has(affix.stat):
				return maxf(1.0, roundf(v))
			return _round_to(v, 200.0)
		Affix.Mode.ON_HIT_STATUS:
			return clampf(_round_to(v, 100.0), 0.0, 1.0)
	return _round_to(v, 200.0)


## Pure name composer: "<Prefix> <Base> <of Suffix>"; legendaries take a theme flavour word.
## `flavour_roll` (0..1) picks among the theme's words deterministically.
static func compose_name(
	base_name: String,
	prefix: String,
	suffix: String,
	rarity: int,
	theme_name: String,
	flavour_roll: float
) -> String:
	var roll := clampf(flavour_roll, 0.0, 0.999)
	if rarity >= ItemInstance.Rarity.LEGENDARY:
		var words := flavour_words(theme_name)
		var prefixes: Array = words["prefix"]
		var suffixes: Array = words["suffix"]
		var flavour_prefix := String(prefixes[int(roll * prefixes.size())])
		var flavour_suffix := String(suffixes[int(roll * suffixes.size())])
		var chosen_suffix := suffix if (not suffix.is_empty() and roll < 0.5) else flavour_suffix
		return "%s %s %s" % [flavour_prefix, base_name, chosen_suffix]
	var parts: PackedStringArray = []
	if not prefix.is_empty():
		parts.append(prefix)
	parts.append(base_name)
	if rarity >= ItemInstance.Rarity.RARE and not suffix.is_empty():
		parts.append(suffix)
	return " ".join(parts)


## {prefix: Array[String], suffix: Array[String]} for a theme name (fallback words otherwise).
static func flavour_words(theme_name: String) -> Dictionary:
	var key := theme_name.to_lower()
	for flavour_key: String in THEME_FLAVOURS.keys():
		if key.contains(flavour_key):
			return THEME_FLAVOURS[flavour_key]
	return DEFAULT_FLAVOURS


## Name of the live desktop theme, or "" when no Desktop autoload is running.
static func current_theme_name() -> String:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return ""
	var desktop := loop.root.get_node_or_null(^"Desktop")
	if desktop == null:
		return ""
	var palette: Variant = desktop.get("palette")
	if palette is ThemePalette:
		return (palette as ThemePalette).name
	return ""


## Stat-chest offers: `count` distinct primaries, each {stat: StringName, points: int}.
## Chance of a +2 orb rises with luck.
static func generate_stat_offers(
	rng: RandomNumberGenerator, luck: float, count: int = 3
) -> Array[Dictionary]:
	var pool: Array[StringName] = Stats.PRIMARY.duplicate()
	var out: Array[Dictionary] = []
	var double_chance := clampf(0.08 + maxf(0.0, luck) * 1.5, 0.0, 0.6)
	for _i in range(mini(count, pool.size())):
		var idx := rng.randi_range(0, pool.size() - 1)
		var stat := pool[idx]
		pool.remove_at(idx)
		var points := 2 if rng.randf() < double_chance else 1
		out.append({"stat": stat, "points": points})
	return out


## Inverse of ItemInstance.to_dict(). Returns null when the base id is unknown.
static func from_dict(data: Dictionary, registry: ItemRegistry) -> ItemInstance:
	if registry == null or data.is_empty():
		return null
	var base := registry.find_base(StringName(String(data.get("base", ""))))
	if base == null:
		return null
	var item := ItemInstance.new()
	item.base = base
	item.uid = int(data.get("uid", 0))
	item.rarity = clampi(int(data.get("rarity", 0)), 0, 3) as ItemInstance.Rarity
	item.display_name = String(data.get("name", base.display_name))
	item.unique_effect = StringName(String(data.get("unique", "")))
	item.seed_hash = int(data.get("seed", 0))
	var affix_data: Variant = data.get("affixes", [])
	if affix_data is Array:
		for raw: Variant in affix_data as Array:
			if not raw is Dictionary:
				continue
			var entry := raw as Dictionary
			var affix := registry.find_affix(StringName(String(entry.get("id", ""))))
			if affix != null:
				item.affixes.append({"affix": affix, "value": float(entry.get("value", 0.0))})
	return item


## Tooltip line for one affix roll; handles fractional flats ("+10% Fire Damage") that
## Affix.describe() would print as "+0".
static func describe_affix(affix: Affix, value: float) -> String:
	match affix.mode:
		Affix.Mode.FLAT:
			if INTEGER_STATS.has(affix.stat):
				return "+%d %s" % [int(value), stat_label(affix.stat)]
			return "+%d%% %s" % [int(roundf(value * 100.0)), stat_label(affix.stat)]
		Affix.Mode.PERCENT:
			return "+%d%% %s" % [int(roundf(value * 100.0)), stat_label(affix.stat)]
		Affix.Mode.ON_HIT_STATUS:
			return (
				"%d%% chance to %s on hit"
				% [
					int(roundf(value * 100.0)),
					(StatusEffect.Kind.keys()[affix.status_kind] as String).to_lower()
				]
			)
	return String(affix.id)


## Human label for a stat key ("damage_fire" -> "Fire Damage").
static func stat_label(stat: StringName) -> String:
	var s := String(stat)
	if s.begins_with("damage_"):
		return s.trim_prefix("damage_").capitalize() + " Damage"
	if s.begins_with("resist_"):
		return s.trim_prefix("resist_").capitalize() + " Resist"
	return s.capitalize()


## Full tooltip lines (implicits + affixes + unique) with fraction-aware formatting.
static func describe(item: ItemInstance) -> PackedStringArray:
	var lines: PackedStringArray = []
	if item == null or item.base == null:
		return lines
	for stat: StringName in item.base.implicit_flat.keys():
		var v := float(item.base.implicit_flat[stat])
		if INTEGER_STATS.has(stat):
			lines.append("%s%d %s" % ["+" if v >= 0.0 else "", int(v), stat_label(stat)])
		else:
			lines.append(
				"%s%d%% %s" % ["+" if v >= 0.0 else "", int(roundf(v * 100.0)), stat_label(stat)]
			)
	for stat: StringName in item.base.implicit_percent.keys():
		var v := float(item.base.implicit_percent[stat])
		lines.append(
			"%s%d%% %s" % ["+" if v >= 0.0 else "", int(roundf(v * 100.0)), stat_label(stat)]
		)
	for entry: Dictionary in item.affixes:
		lines.append(describe_affix(entry["affix"], float(entry["value"])))
	if item.unique_effect != &"":
		var passive := UniqueEffects.find(item.unique_effect)
		if passive != null:
			lines.append("%s: %s" % [passive.display_name, passive.description])
	return lines


## Rounds to 1/`steps_per_unit` using a correctly-rounded division so the value survives a
## JSON round trip unchanged (snappedf multiplies and can land one ulp off).
static func _round_to(v: float, steps_per_unit: float) -> float:
	return roundf(v * steps_per_unit) / steps_per_unit


static func _weighted_index(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w: float in weights:
		total += maxf(0.0, w)
	if total <= 0.0:
		return 0
	var roll := rng.randf() * total
	for i in range(weights.size()):
		roll -= maxf(0.0, weights[i])
		if roll < 0.0:
			return i
	return weights.size() - 1
