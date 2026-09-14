## Catalogue of every ability (data/abilities/registry.tres). Resolves ids, builds weighted
## offers for chests/altars and assigns icons from the shared 16x16 sheet.
class_name AbilityRegistry
extends Resource

const DEFAULT_PATH := "res://data/abilities/registry.tres"
const ICON_SHEET_PATH := "res://assets/sprites/ui/ability_icons.png"
const ICON_SIZE := 16

## Class innates are granted at run start and never offered.
const INNATE_IDS: Array[StringName] = [&"second_wind", &"sure_footed", &"overflow", &"buyout"]
## Fallback innate/starting-active tables used only when no ClassDef is supplied (tests).
## `data/classes/<id>.tres` is the source of truth: `innate_passive_id`, `extra_ability_ids`.
const CLASS_INNATES: Dictionary = {
	&"fighter": &"second_wind",
	&"ranger": &"sure_footed",
	&"wizard": &"overflow",
	&"oligarch": &"buyout",
}
## Actives a class starts the run with *on top of* its class active. Empty on purpose: every
## class must reach floor 1 with the same number of empty ability slots, or it makes one fewer
## build decision for the whole run. The Oligarch used to start with Contract in here, which
## filled both of its active slots and turned every active it was ever offered into a forced
## downgrade of a class-defining ability. Contract is still its class-only pick.
const CLASS_STARTING_ACTIVES: Dictionary = {}

## Sheet cell order (row-major) in assets/sprites/ui/ability_icons.png. Must stay in
## lock-step with `ABILITY_ICONS` in tools/art/ui.py, which draws that sheet: the order
## here is the only thing that says which cell an ability gets.
const ICON_ORDER: Array[StringName] = [
	&"fireball",
	&"frost_nova",
	&"shadowstep",
	&"whirlwind",
	&"turret",
	&"warcry",
	&"rm_rf",
	&"reboot",
	&"bulwark",
	&"volley",
	&"chain_lightning",
	&"hostile_takeover",
	&"contract",
	&"thorns",
	&"glass_cannon",
	&"vampiric",
	&"tiling_wm",
	&"dotfiles",
	&"lucky_coin",
	&"ricochet",
	&"adrenaline",
	&"heavy_hands",
	&"hotkey",
	&"second_wind",
	&"sure_footed",
	&"overflow",
	&"buyout",
	&"curse_1",
	&"curse_2",
	&"curse_3",
	&"kill_9",
	&"fork_bomb",
	&"smoke_bomb",
	&"stack_smash",
	&"siphon",
	&"sudo",
	&"close_quarters",
	&"pipeline",
	&"rootkit",
	&"cron_job",
	&"firewall",
	&"bit_shift",
	&"man_page",
	&"overclock",
	&"verbose_logging",
	&"kernel_headers",
	&"hardlink",
	&"undervolt",
]

@export var abilities: Array[Ability] = []
var _icons_ready := false


static func load_default() -> AbilityRegistry:
	return load(DEFAULT_PATH) as AbilityRegistry


## The registry's own instance (NOT a copy) for `id`, or null. Read-only: never hand the
## result to AbilitySlots.add()/replace() directly — use `instance(id)` or
## `Ability.duplicate_ability()` (AbilitySlots copies defensively, but callers that mutate
## `tier` themselves would poison the shared `.tres`).
func find(id: StringName) -> Ability:
	ensure_icons()
	for a: Ability in abilities:
		if a != null and a.id == id:
			return a
	return null


## Fresh copy (tier 1) of ability `id`, or null.
func instance(id: StringName) -> Ability:
	var found := find(id)
	if found == null:
		return null
	var copy := found.duplicate_ability()
	copy.tier = 1
	return copy


func is_innate(id: StringName) -> bool:
	return INNATE_IDS.has(id)


## Fresh copy of the class innate passive. Pass the `ClassDef` (its `innate_passive_id` is the
## source of truth) or, for tests, a bare class id resolved through CLASS_INNATES.
func innate_for(class_source: Variant) -> PassiveAbility:
	if class_source is ClassDef:
		return instance((class_source as ClassDef).innate_passive_id) as PassiveAbility
	var class_id := StringName(str(class_source))
	if not CLASS_INNATES.has(class_id):
		return null
	return instance(CLASS_INNATES[class_id]) as PassiveAbility


## Fresh copies of the actives a class starts with. Pass the `ClassDef` (`extra_ability_ids`)
## or, for tests, a bare class id resolved through CLASS_STARTING_ACTIVES.
func starting_actives_for(class_source: Variant) -> Array[ActiveAbility]:
	var out: Array[ActiveAbility] = []
	var ids: Array = []
	if class_source is ClassDef:
		ids = (class_source as ClassDef).extra_ability_ids
	else:
		ids = CLASS_STARTING_ACTIVES.get(StringName(str(class_source)), [])
	for id: Variant in ids:
		var a := instance(StringName(str(id))) as ActiveAbility
		if a != null:
			out.append(a)
	return out


## True when `ability` may be offered to `class_id` given the `owned` id->tier map.
func is_offerable(ability: Ability, class_id: StringName, owned: Dictionary) -> bool:
	if ability == null or ability.id == &"" or ability.weight <= 0.0:
		return false
	if is_innate(ability.id) or String(ability.id).begins_with("curse_"):
		return false
	if ability.class_only != &"" and ability.class_only != class_id:
		return false
	return int(owned.get(ability.id, 0)) < ability.max_tier


## Weighted offer of up to `count` distinct abilities. Owned ones come back at tier+1 so the
## UI can show the upgrade; maxed, innate and other-class abilities are never offered.
## `prefer_kind` (Ability.Kind) fills from that kind first and tops up with the other.
func offer(
	rng: RandomNumberGenerator,
	count: int,
	class_id: StringName,
	owned: Dictionary,
	prefer_kind: int = -1
) -> Array[Ability]:
	ensure_icons()
	var pool: Array[Ability] = []
	for a: Ability in abilities:
		if is_offerable(a, class_id, owned):
			pool.append(a)
	var out: Array[Ability] = []
	if prefer_kind >= 0:
		var preferred: Array[Ability] = pool.filter(
			func(a: Ability) -> bool: return int(a.kind) == prefer_kind
		)
		_draw_into(rng, preferred, count, out)
		var rest: Array[Ability] = pool.filter(
			func(a: Ability) -> bool: return int(a.kind) != prefer_kind
		)
		_draw_into(rng, rest, count, out)
	else:
		_draw_into(rng, pool, count, out)
	var result: Array[Ability] = []
	for a: Ability in out:
		var copy := a.duplicate_ability()
		copy.tier = clampi(int(owned.get(a.id, 0)) + 1, 1, a.max_tier)
		result.append(copy)
	return result


## Weighted draws without replacement from `pool` until `out` holds `count` entries.
func _draw_into(
	rng: RandomNumberGenerator, pool: Array[Ability], count: int, out: Array[Ability]
) -> void:
	var remaining := pool.duplicate()
	while out.size() < count and not remaining.is_empty():
		var total := 0.0
		for a: Ability in remaining:
			total += a.weight
		var roll := rng.randf() * total
		var picked := remaining.size() - 1
		var acc := 0.0
		for i in range(remaining.size()):
			acc += remaining[i].weight
			if roll < acc:
				picked = i
				break
		out.append(remaining[picked])
		remaining.remove_at(picked)


# --- icons -------------------------------------------------------------------------------------


## Cell index in the icon sheet for `id`, or -1.
static func icon_index(id: StringName) -> int:
	return ICON_ORDER.find(id)


## AtlasTexture for `id` sized from the actual sheet (row-major cells, columns = width / 16).
static func icon_for(id: StringName) -> AtlasTexture:
	var index := icon_index(id)
	if index < 0 or not ResourceLoader.exists(ICON_SHEET_PATH):
		return null
	var sheet := load(ICON_SHEET_PATH) as Texture2D
	if sheet == null:
		return null
	var columns := maxi(1, int(sheet.get_width()) / ICON_SIZE)
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(
		float((index % columns) * ICON_SIZE),
		float((index / columns) * ICON_SIZE),
		ICON_SIZE,
		ICON_SIZE
	)
	return atlas


## Assigns sheet icons to every ability (regions recomputed from the shipped sheet layout).
func ensure_icons() -> void:
	if _icons_ready:
		return
	_icons_ready = true
	for a: Ability in abilities:
		if a == null:
			continue
		var icon := icon_for(a.id)
		if icon != null:
			a.icon = icon
