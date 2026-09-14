## Cross-module content integrity (docs §1: content is data).
##
## Every registry under data/ must hold what docs/GAME_DESIGN.md asks for, and every id one
## module hands to another — class start weapons and abilities, biome trap/prop kinds, the
## mimic's enemy id, unlock ids, ability icon cells — must resolve in the module that owns it.
## This suite exists so content can never rot silently; it reads data only and asserts nothing
## about behaviour.
class_name RegistryIntegrityTest
extends GdUnitTestSuite

const CLASS_DIR := "res://data/classes/"
const BIOME_DIR := "res://data/biomes/"

## docs §4.3 — the four playable classes.
const CLASS_IDS: Array[StringName] = [&"fighter", &"ranger", &"wizard", &"oligarch"]
## docs §7 — 14 non-boss enemies (5 clowns, 5 greybeards, 4 tinkerers).
const ENEMY_IDS: Array[StringName] = [
	&"juggler",
	&"honker",
	&"balloon_clown",
	&"mime",
	&"clown_car",
	&"manpage_hurler",
	&"beard_warden",
	&"rant_priest",
	&"vim_zealot",
	&"kernel_panic",
	&"ricer",
	&"distro_hopper",
	&"config_gremlin",
	&"dotfile_golem",
]
## docs §4.4 — 8 generic actives, 4 class actives and the Oligarch's Contract.
const ACTIVE_IDS: Array[StringName] = [
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
]
## docs §4.4 — 10 offered passives plus the 4 class innates.
const PASSIVE_IDS: Array[StringName] = [
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
]
## docs §8 — cursed chests attach one of these.
const CURSE_IDS: Array[StringName] = [&"curse_1", &"curse_2", &"curse_3"]
## docs §9 — the eight placeable trap types.
const TRAP_KINDS: Array[StringName] = [
	&"spike_floor",
	&"arrow_wall",
	&"fire_vent",
	&"pit",
	&"pressure_plate",
	&"ice_slide",
	&"laser_grid",
	&"mimic_chest",
]
## Hazards enemies request through EventBus.spawn_hazard (Ricer, Kernel Panic).
const HAZARD_KINDS: Array[StringName] = [&"ricer_trap", &"kernel_spike"]
## docs §4.5 — the item pool must stay at least this big for the generator to feel varied.
const MIN_ITEM_BASES := 22
const MIN_AFFIXES := 30

# --- enemies -------------------------------------------------------------------------------


func test_enemy_registry_holds_every_designed_enemy() -> void:
	var registry := _enemies()
	var seen: Dictionary = {}
	var non_boss: Array[StringName] = []
	for def: EnemyDef in registry.defs:
		assert_object(def).is_not_null()
		assert_bool(def.id.is_empty()).override_failure_message("EnemyDef with no id").is_false()
		var label := String(def.id)
		assert_bool(seen.has(def.id)).override_failure_message("duplicate " + label).is_false()
		seen[def.id] = true
		assert_object(def.scene).override_failure_message(label + " has no scene").is_not_null()
		assert_object(def.texture).override_failure_message(label + " has no texture").is_not_null()
		if not def.is_boss:
			non_boss.append(def.id)
	for id: StringName in ENEMY_IDS:
		var def := registry.find(id)
		assert_object(def).override_failure_message("missing enemy " + String(id)).is_not_null()
		assert_bool(def.is_boss).override_failure_message(String(id) + " is a boss").is_false()
	# The spawnable roster is exactly the designed 14; bosses are extra and opt out via is_boss.
	assert_array(non_boss).contains_exactly_in_any_order(ENEMY_IDS)


func test_bosses_never_enter_the_spawn_pool() -> void:
	var registry := _enemies()
	for floor_index in range(9):
		for elite: bool in [false, true]:
			for def: EnemyDef in registry.candidates(floor_index, elite):
				(
					assert_bool(def.is_boss)
					. override_failure_message(
						"boss %s is spawnable on floor %d" % [def.id, floor_index]
					)
					. is_false()
				)
		(
			assert_int(registry.candidates(floor_index, false).size())
			. override_failure_message("no ordinary enemy for floor %d" % floor_index)
			. is_greater(0)
		)
		(
			assert_int(registry.candidates(floor_index, true).size())
			. override_failure_message("no elite for floor %d" % floor_index)
			. is_greater(0)
		)


func test_enemy_summons_resolve_in_the_registry() -> void:
	var registry := _enemies()
	for def: EnemyDef in registry.defs:
		for summon: EnemyDef in def.summon_defs:
			(
				assert_object(summon)
				. override_failure_message(String(def.id) + " summons null")
				. is_not_null()
			)
			(
				assert_object(registry.find(summon.id))
				. override_failure_message("%s summons unregistered %s" % [def.id, summon.id])
				. is_not_null()
			)


func test_every_player_facing_faction_can_fill_a_room() -> void:
	var registry := _enemies()
	var factions: Array[int] = [
		EnemyDef.Faction.CLOWNS, EnemyDef.Faction.GREYBEARDS, EnemyDef.Faction.TINKERERS
	]
	for faction: int in factions:
		var count := 0
		var elites := 0
		for def: EnemyDef in registry.defs:
			if def.is_boss or int(def.faction) != faction:
				continue
			count += 1
			if def.is_elite:
				elites += 1
		var label := String(EnemyDef.Faction.keys()[faction])
		assert_int(count).override_failure_message(label + " has no enemies").is_greater(0)
		assert_int(elites).override_failure_message(label + " has no elite").is_greater(0)


# --- items ---------------------------------------------------------------------------------


func test_item_registry_is_complete_and_consistent() -> void:
	var registry := _items()
	assert_int(registry.bases.size()).is_greater_equal(MIN_ITEM_BASES)
	assert_int(registry.affixes.size()).is_greater_equal(MIN_AFFIXES)
	var seen: Dictionary = {}
	for base: ItemBase in registry.bases:
		assert_object(base).is_not_null()
		assert_bool(base.id.is_empty()).override_failure_message("ItemBase with no id").is_false()
		(
			assert_bool(seen.has(base.id))
			. override_failure_message("duplicate " + String(base.id))
			. is_false()
		)
		seen[base.id] = true
	for slot: int in ItemBase.Slot.values():
		(
			assert_int(registry.bases_in_slot(slot).size())
			. override_failure_message("no item base in slot %d" % slot)
			. is_greater(0)
		)


func test_every_weapon_base_has_a_weapon_skill() -> void:
	for base: ItemBase in _items().bases:
		var weapon := base as WeaponBase
		if weapon == null:
			continue
		(
			assert_object(weapon.skill)
			. override_failure_message(String(weapon.id) + " has no weapon skill")
			. is_not_null()
		)


func test_affix_stats_and_slots_resolve() -> void:
	var stat_names := Stats.PRIMARY.duplicate()
	stat_names.append_array(Stats.SECONDARY)
	var slot_names: Array[StringName] = []
	for slot: int in ItemBase.Slot.values():
		slot_names.append(StringName((ItemBase.Slot.keys()[slot] as String).to_lower()))
	var seen: Dictionary = {}
	for affix: Affix in _items().affixes:
		assert_object(affix).is_not_null()
		(
			assert_bool(seen.has(affix.id))
			. override_failure_message("duplicate " + String(affix.id))
			. is_false()
		)
		seen[affix.id] = true
		for slot_name: StringName in affix.slots:
			(
				assert_bool(slot_names.has(slot_name))
				. override_failure_message("%s rolls on unknown slot %s" % [affix.id, slot_name])
				. is_true()
			)
		if affix.mode == Affix.Mode.FLAT or affix.mode == Affix.Mode.PERCENT:
			(
				assert_bool(stat_names.has(affix.stat))
				. override_failure_message("%s modifies unknown stat %s" % [affix.id, affix.stat])
				. is_true()
			)


func test_unique_effect_ids_resolve_to_passives() -> void:
	var ids := UniqueEffects.ids()
	assert_int(ids.size()).is_greater(0)
	for id: StringName in ids:
		var effect := UniqueEffects.find(id)
		assert_object(effect).override_failure_message("unique effect " + String(id)).is_not_null()
		assert_int(int(effect.kind)).is_equal(int(Ability.Kind.PASSIVE))


# --- abilities -----------------------------------------------------------------------------


func test_ability_registry_holds_every_designed_ability() -> void:
	var registry := _abilities()
	var seen: Dictionary = {}
	for ability: Ability in registry.abilities:
		assert_object(ability).is_not_null()
		assert_bool(ability.id.is_empty()).override_failure_message("ability with no id").is_false()
		(
			assert_bool(seen.has(ability.id))
			. override_failure_message("duplicate " + String(ability.id))
			. is_false()
		)
		seen[ability.id] = true
	for id: StringName in ACTIVE_IDS:
		var active := registry.instance(id)
		assert_object(active).override_failure_message("missing active " + String(id)).is_not_null()
		(
			assert_object(active as ActiveAbility)
			. override_failure_message(String(id) + " is not an ActiveAbility")
			. is_not_null()
		)
	for id: StringName in PASSIVE_IDS:
		var passive := registry.instance(id)
		(
			assert_object(passive)
			. override_failure_message("missing passive " + String(id))
			. is_not_null()
		)
		(
			assert_object(passive as PassiveAbility)
			. override_failure_message(String(id) + " is not a PassiveAbility")
			. is_not_null()
		)
	for id: StringName in CURSE_IDS:
		(
			assert_object(registry.instance(id))
			. override_failure_message("missing " + String(id))
			. is_not_null()
		)
	# Extra abilities may be added later, but never fewer than the designed set.
	assert_int(registry.abilities.size()).is_greater_equal(
		ACTIVE_IDS.size() + PASSIVE_IDS.size() + CURSE_IDS.size()
	)


func test_every_ability_has_an_icon_cell_on_the_sheet() -> void:
	var sheet := load(AbilityRegistry.ICON_SHEET_PATH) as Texture2D
	assert_object(sheet).is_not_null()
	var columns := maxi(1, sheet.get_width() / AbilityRegistry.ICON_SIZE)
	var rows := maxi(1, sheet.get_height() / AbilityRegistry.ICON_SIZE)
	var cells := columns * rows
	for ability: Ability in _abilities().abilities:
		var index := AbilityRegistry.icon_index(ability.id)
		(
			assert_int(index)
			. override_failure_message(String(ability.id) + " not in ICON_ORDER")
			. is_greater_equal(0)
		)
		(
			assert_int(index)
			. override_failure_message("%s icon cell %d is past the sheet" % [ability.id, index])
			. is_less(cells)
		)
		(
			assert_object(AbilityRegistry.icon_for(ability.id))
			. override_failure_message(String(ability.id) + " has no icon region")
			. is_not_null()
		)


func test_icon_order_lists_only_real_abilities() -> void:
	var registry := _abilities()
	for id: StringName in AbilityRegistry.ICON_ORDER:
		(
			assert_object(registry.find(id))
			. override_failure_message("ICON_ORDER lists unknown ability " + String(id))
			. is_not_null()
		)


func test_innate_ids_are_class_passives() -> void:
	var registry := _abilities()
	for id: StringName in AbilityRegistry.INNATE_IDS:
		var innate := registry.find(id)
		assert_object(innate).override_failure_message("missing innate " + String(id)).is_not_null()
		assert_int(int(innate.kind)).is_equal(int(Ability.Kind.PASSIVE))
		(
			assert_bool(innate.class_only.is_empty())
			. override_failure_message(String(id) + " is an innate but not class-locked")
			. is_false()
		)


# --- classes -------------------------------------------------------------------------------


func test_class_defs_resolve_every_id_they_reference() -> void:
	var items := _items()
	var abilities := _abilities()
	for class_id: StringName in CLASS_IDS:
		var path := CLASS_DIR + String(class_id) + ".tres"
		var def := load(path) as ClassDef
		assert_object(def).override_failure_message("missing " + path).is_not_null()
		assert_str(String(def.id)).is_equal(String(class_id))
		var weapon := items.find_base(def.start_weapon_id) as WeaponBase
		(
			assert_object(weapon)
			. override_failure_message(
				"%s starts with unknown weapon %s" % [class_id, def.start_weapon_id]
			)
			. is_not_null()
		)
		var innate := abilities.instance(def.innate_passive_id) as PassiveAbility
		(
			assert_object(innate)
			. override_failure_message(
				"%s innate %s is not a passive" % [class_id, def.innate_passive_id]
			)
			. is_not_null()
		)
		(
			assert_bool(AbilityRegistry.INNATE_IDS.has(def.innate_passive_id))
			. override_failure_message(String(def.innate_passive_id) + " missing from INNATE_IDS")
			. is_true()
		)
		var active := abilities.instance(def.class_active_id) as ActiveAbility
		(
			assert_object(active)
			. override_failure_message(
				"%s active %s is not an active" % [class_id, def.class_active_id]
			)
			. is_not_null()
		)
		(
			assert_str(String(active.class_only))
			. override_failure_message(
				String(def.class_active_id) + " is not locked to " + String(class_id)
			)
			. is_equal(String(class_id))
		)
		for extra: StringName in def.extra_ability_ids:
			(
				assert_object(abilities.instance(extra))
				. override_failure_message("%s starts with unknown ability %s" % [class_id, extra])
				. is_not_null()
			)


func test_class_art_paths_exist() -> void:
	for class_id: StringName in CLASS_IDS:
		var def := load(CLASS_DIR + String(class_id) + ".tres") as ClassDef
		(
			assert_bool(ResourceLoader.exists(def.sprite_sheet_path()))
			. override_failure_message(String(class_id) + " sheet " + def.sprite_sheet_path())
			. is_true()
		)
		(
			assert_bool(ResourceLoader.exists(def.portrait_path()))
			. override_failure_message(String(class_id) + " portrait " + def.portrait_path())
			. is_true()
		)


func test_fallback_innate_tables_agree_with_class_data() -> void:
	for class_id: StringName in CLASS_IDS:
		var def := load(CLASS_DIR + String(class_id) + ".tres") as ClassDef
		(
			assert_str(String(AbilityRegistry.CLASS_INNATES.get(class_id, &"")))
			. override_failure_message("CLASS_INNATES disagrees for " + String(class_id))
			. is_equal(String(def.innate_passive_id))
		)
		var listed: Array = AbilityRegistry.CLASS_STARTING_ACTIVES.get(class_id, [])
		assert_int(listed.size()).is_equal(def.extra_ability_ids.size())
		for i in range(listed.size()):
			assert_str(str(listed[i])).is_equal(String(def.extra_ability_ids[i]))


# --- unlocks -------------------------------------------------------------------------------


func test_every_unlock_id_is_a_class_or_an_ability() -> void:
	var abilities := _abilities()
	var all_unlocks := Profile.DEFAULT_UNLOCKS.duplicate()
	all_unlocks.append_array(Profile.GATED_UNLOCKS)
	for id: StringName in all_unlocks:
		if CLASS_IDS.has(id):
			continue
		(
			assert_object(abilities.find(id))
			. override_failure_message(
				"unlock id " + String(id) + " is neither a class nor an ability"
			)
			. is_not_null()
		)


# --- biomes, traps and rooms ---------------------------------------------------------------


func test_biomes_are_complete() -> void:
	assert_int(Biome.ALL_IDS.size()).is_equal(5)
	for id: StringName in Biome.ALL_IDS:
		var path := BIOME_DIR + String(id) + ".tres"
		var biome := load(path) as Biome
		assert_object(biome).override_failure_message("missing " + path).is_not_null()
		assert_str(String(biome.id)).is_equal(String(id))
		assert_bool(biome.trap_kinds.is_empty()).is_false()
		assert_int(biome.prop_kinds.size()).is_equal(Prop.KIND_COUNT)


func test_biome_trap_kinds_resolve_in_the_trap_registry() -> void:
	var traps := TrapRegistry.load_default()
	assert_object(traps).is_not_null()
	for id: StringName in Biome.ALL_IDS:
		var biome := Biome.load_by_id(id)
		for kind: StringName in biome.trap_kinds:
			(
				assert_bool(traps.has_kind(kind))
				. override_failure_message("%s lists unknown trap %s" % [id, kind])
				. is_true()
			)
			(
				assert_bool(traps.get_def(kind).allows_biome(id))
				. override_failure_message("trap %s does not allow biome %s" % [kind, id])
				. is_true()
			)
		(
			assert_int(traps.defs_for_biome(id).size())
			. override_failure_message("no trap def for biome " + String(id))
			. is_greater(0)
		)


func test_biome_prop_kinds_match_the_rooms_module() -> void:
	for id: StringName in Biome.ALL_IDS:
		var biome := Biome.load_by_id(id)
		var names := Prop.kind_names(id)
		assert_int(names.size()).is_equal(Prop.KIND_COUNT)
		for i in range(biome.prop_kinds.size()):
			(
				assert_str(String(names[i]))
				. override_failure_message("%s prop column %d" % [id, i])
				. is_equal(String(biome.prop_kinds[i]))
			)


func test_biome_fill_templates_resolve() -> void:
	for id: StringName in Biome.ALL_IDS:
		var biome := Biome.load_by_id(id)
		for template_id: StringName in biome.fill_templates:
			(
				assert_bool(RoomFiller.TEMPLATE_IDS.has(template_id))
				. override_failure_message("%s lists unknown template %s" % [id, template_id])
				. is_true()
			)


func test_trap_registry_holds_every_designed_trap() -> void:
	var traps := TrapRegistry.load_default()
	for kind: StringName in TRAP_KINDS:
		var def := traps.get_def(kind)
		assert_object(def).override_failure_message("missing trap " + String(kind)).is_not_null()
		(
			assert_object(def.scene)
			. override_failure_message(String(kind) + " has no scene")
			. is_not_null()
		)
		(
			assert_bool(def.is_hazard)
			. override_failure_message(String(kind) + " is a hazard")
			. is_false()
		)
	for kind: StringName in HAZARD_KINDS:
		var def := traps.get_def(kind)
		assert_object(def).override_failure_message("missing hazard " + String(kind)).is_not_null()
		(
			assert_bool(def.is_hazard)
			. override_failure_message(String(kind) + " is not a hazard")
			. is_true()
		)


func test_mimic_chest_enemy_id_resolves() -> void:
	var mimic := auto_free(TrapRegistry.instantiate(&"mimic_chest", Vector2.ZERO)) as MimicChest
	assert_object(mimic).is_not_null()
	(
		assert_object(_enemies().find(mimic.enemy_id))
		. override_failure_message(
			"MimicChest.enemy_id " + String(mimic.enemy_id) + " has no EnemyDef"
		)
		. is_not_null()
	)


func test_room_templates_resolve_and_reference_real_biomes() -> void:
	var templates := RoomFiller.load_templates()
	assert_int(templates.size()).is_equal(RoomFiller.TEMPLATE_IDS.size())
	var seen: Dictionary = {}
	for template: RoomTemplate in templates:
		assert_bool(seen.has(template.id)).override_failure_message("duplicate template").is_false()
		seen[template.id] = true
		(
			assert_bool(RoomFiller.TEMPLATE_IDS.has(template.id))
			. override_failure_message("template id " + String(template.id) + " is not registered")
			. is_true()
		)
		for biome_id: StringName in template.allowed_biomes:
			(
				assert_bool(Biome.ALL_IDS.has(biome_id))
				. override_failure_message("%s allows unknown biome %s" % [template.id, biome_id])
				. is_true()
			)
		for room_type: int in template.allowed_types:
			(
				assert_int(room_type)
				. override_failure_message(String(template.id) + " allows an unknown room type")
				. is_less(FloorData.RoomType.keys().size())
			)


func test_rooms_content_tables_reference_real_biomes_and_kinds() -> void:
	var content := RoomsContent.load_default()
	assert_object(content).override_failure_message("data/rooms/rooms_content.tres").is_not_null()
	for biome_id: StringName in content.prop_kinds:
		(
			assert_bool(Biome.ALL_IDS.has(biome_id))
			. override_failure_message("rooms_content lists unknown biome " + String(biome_id))
			. is_true()
		)
		assert_int(content.kinds_for(biome_id).size()).is_equal(Prop.KIND_COUNT)
	for sturdy: StringName in content.prop_sturdy_kinds:
		var found := false
		for biome_id: StringName in Biome.ALL_IDS:
			if Prop.kind_names(biome_id).has(sturdy):
				found = true
				break
		(
			assert_bool(found)
			. override_failure_message("sturdy prop kind " + String(sturdy) + " exists in no biome")
			. is_true()
		)
	for kind: StringName in content.prop_solid:
		var found := false
		for biome_id: StringName in Biome.ALL_IDS:
			if Prop.kind_names(biome_id).has(kind):
				found = true
				break
		(
			assert_bool(found)
			. override_failure_message("prop_solid names " + String(kind) + ", which no biome has")
			. is_true()
		)
	for biome_id: StringName in Biome.ALL_IDS:
		for kind: StringName in Prop.kind_names(biome_id):
			(
				assert_bool(content.prop_solid.has(kind))
				. override_failure_message(
					String(biome_id) + " prop " + String(kind) + " has no prop_solid entry"
				)
				. is_true()
			)
	for room_type: int in content.chest_weights:
		(
			assert_int(room_type)
			. override_failure_message("chest weights for an unknown room type")
			. is_less(FloorData.RoomType.keys().size())
		)


func _enemies() -> EnemyRegistry:
	var registry := load("res://data/enemies/registry.tres") as EnemyRegistry
	assert_object(registry).is_not_null()
	return registry


func _items() -> ItemRegistry:
	var registry := ItemRegistry.load_default()
	assert_object(registry).is_not_null()
	return registry


func _abilities() -> AbilityRegistry:
	var registry := AbilityRegistry.load_default()
	assert_object(registry).is_not_null()
	return registry
