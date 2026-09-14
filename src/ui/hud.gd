## In-game HUD (CanvasLayer): HP, potions, gold, actives with cooldowns, passives,
## floor, minimap, toasts, track banner, damage numbers and the interact prompt.
##
## The run seed is deliberately not on it. It is a power-user handle, not a fact a player is
## playing against, and a number nobody can act on sitting in the corner of every screenshot
## is exactly the kind of developer detail this HUD had too much of. `set_seed` still records
## it so the pause menu's Settings page can show it to whoever goes looking.
## `bind(player)` duck-types `health`, `stats`, `gold`, `potions`, `ability_slots`.
class_name Hud
extends CanvasLayer

const DAMAGE_POOL := 24
const PASSIVE_ICON := 12
## HUD text floats over the level, so it gets a 1 px outline in the void colour.
const TEXT_OUTLINE := 1
## Clear px left between two stacked floating numbers.
const LANE_GAP := 2.0
## Input action the weapon skill (secondary attack) is bound to.
const SKILL_ACTION := &"secondary"
## Short names for the primary stats, used by the stat-change toast and floater.
const STAT_SHORT: Dictionary = {
	&"vitality": "VIT",
	&"might": "MGT",
	&"precision": "PRE",
	&"arcana": "ARC",
	&"swiftness": "SWI",
	&"fortune": "FOR",
}
## How long a primary-stat change stays on the banner.
const STAT_TOAST_DURATION := 2.0
## What a boss floor's label adds. It used to be "[BOSS]", which is a debug tag: square
## brackets and shouting caps are how a log line marks a level, not how a game names a place.
const BOSS_SUFFIX := " (Boss)"
## 0-based floor indices that hold a boss arena (docs §2: floors 3, 6 and 9). Mirrors
## `RunManager.BOSS_FLOORS` so the HUD does not depend on the run-lifecycle autoload.
const BOSS_FLOOR_INDICES: Array[int] = [2, 5, 8]
## The objective line, by floor kind and by whether the goal room has been found. The game
## said "Floor 1 - Crypt" and stopped: there is no tutorial and the map marks nothing, so a
## first-time player was told neither what to do nor where to go (docs §2: "Explore - find
## stairs"). One dim line under the floor label answers both.
const OBJECTIVE_FIND_STAIRS := "Find the stairs down"
const OBJECTIVE_TAKE_STAIRS := "Stairs found - descend"
const OBJECTIVE_FIND_BOSS := "Find the boss arena"
const OBJECTIVE_FIGHT_BOSS := "Boss found - end it"
## The one-off hint on the first floor of a run, in the gameplay lane. Shown once per run.
## Kept short on purpose: the banner is centred and a longer sentence reaches back over the
## top-left plate, so the line that explains the game would be sitting on the player's HP.
##
## It deliberately does *not* mention the stairs. The objective line above says where to go
## and keeps saying it; the banner used to say it too, in a sentence frozen at floor start,
## so the moment the stairs room was discovered inside the hint's four seconds the HUD was
## telling a new player two different things at once. Two lanes are worth having only while
## they carry two different facts: the objective is the goal, the hint is the rule that gates
## it. `_stand_down_hint` also pulls the banner the instant either of them stops applying.
const FIRST_FLOOR_HINT := "Clear a room to unlock its doors"
const FIRST_FLOOR_HINT_DURATION := 4.0
## How long the floor-arrival banner ("Floor 3 - Crypt") stays up.
const ARRIVAL_DURATION := 2.0
## How long the line after it, saying what the music made of the floor, stays up.
const MUSIC_BANNER_DURATION := 3.5
## How long the line naming the desktop that shaped the floor stays up.
const DESKTOP_BANNER_DURATION := 3.0
## The line after the arrival banner that names the desktop as the floor's source. The owner's
## report was that the theme and the wallpaper "don't do enough", and half of that is that
## nothing ever *said* they did anything: a lever the player cannot see is a lever that does
## not exist. Every word of it is literal: the wallpaper's luminance is the floor's light
## level and its colour statistics lay the floor out (docs §3.4), and the theme is the only
## thing in the game that says what colour any of it is (§16, "The theme is the colours").
const DESKTOP_LINE_WALLPAPER := "Lit and shaped by your wallpaper - coloured by %s"
const DESKTOP_LINE_THEME := "Shaped by %s"

var player: Node
var floor_index: int = 0
var biome_name: String = ""
## The seed of the run in progress, kept for the screens that may show it.
var run_seed: int = 0
var _gold_target: int = 0
var _gold_shown: float = 0.0
var _potions_shown: int = -1
var _damage_pool: Array[DamageNumber] = []
## Feel numbers for the floating-text lanes (`data/feel/feel.tres`).
var _feel_profile: FeelProfile = FeelProfile.load_default()
var _actives: Array[Resource] = []
var _passives: Array[Resource] = []
var _gold_tween: Tween
var _prompt_tween: Tween
## Last primary value seen per stat, so `stat_changed` (which carries only the new total)
## can be turned into the signed delta the player actually needs to read.
var _stat_seen: Dictionary = {}
## False while a run is still being assembled (`apply_class` and `restore_from_dict` both
## re-emit every primary). Turned on by `floor_started`, which is the first moment a stat
## change can only have come from play.
var _stats_live: bool = false
var _weapon_controller: Node
## Ability last shown in the weapon-skill slot, so a weapon swap can announce the new skill
## by name. The third slot is a full secondary attack on its own cooldown and nothing in the
## game ever said so out loud.
var _skill_shown: Resource
## True once the first-floor hint has been shown for this run.
var _hinted: bool = false
## The arrival banner this HUD last put up, so the next floor can pull it back down.
var _arrival_banner: String = ""
## The music line this HUD last queued behind it, dismissed the same way.
var _music_banner: String = ""
## The desktop line this HUD last put up, so the next floor can pull it back down.
var _desktop_banner: String = ""
## Objective state, recomputed from the minimap feed: whether the floor's goal room is known.
var _goal_found: bool = false

@onready var _root: Control = %Root
@onready var _hp_bar: HpBar = %HpBar
@onready var _hp_text: Label = %HpText
@onready var _potion_count: Label = %PotionCount
@onready var _gold_label: Label = %GoldCount
@onready var _floor_label: Label = %FloorLabel
@onready var _objective_label: Label = %ObjectiveLabel
@onready var _slot_1: AbilitySlot = %Slot1
@onready var _slot_2: AbilitySlot = %Slot2
@onready var _skill_slot: AbilitySlot = %SkillSlot
@onready var _passive_row: HBoxContainer = %Passives
@onready var _statuses: StatusRow = %Statuses
@onready var _minimap: Minimap = %Minimap
@onready var _toast: Toast = %Toast
@onready var _prompt: PanelContainer = %Prompt
@onready var _prompt_label: Label = %PromptLabel
@onready var _prompt_glyph: GlyphIcon = %PromptGlyph
@onready var _numbers: Node2D = %DamageNumbers
@onready var _potion_icon: TextureRect = %PotionIcon
@onready var _potion_glyph: GlyphIcon = %PotionGlyph
@onready var _gold_icon: TextureRect = %GoldIcon
@onready var _tooltip: ItemTooltip = %ItemTooltip


func _ready() -> void:
	UiTheme.apply(_root)
	_slot_1.set_action(&"active_1")
	_slot_2.set_action(&"active_2")
	_skill_slot.set_action(SKILL_ACTION)
	_potion_icon.texture = UiTheme.icon(UiTheme.Icon.POTION)
	_potion_glyph.action = &"potion"
	_gold_icon.texture = UiTheme.icon(UiTheme.Icon.GOLD)
	_prompt.modulate.a = 0.0
	_prompt_glyph.action = &"interact"
	for _i in DAMAGE_POOL:
		var number := DamageNumber.new()
		_numbers.add_child(number)
		_damage_pool.append(number)
	EventBus.damage_number.connect(_on_damage_number)
	_toast.lane_source = banner_lanes
	EventBus.interact_prompt.connect(show_prompt)
	EventBus.item_hover.connect(_on_item_hover)
	EventBus.music_track_changed.connect(_on_track_changed)
	EventBus.floor_started.connect(_on_floor_started)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.ability_slot_changed.connect(_on_ability_slot_changed)
	EventBus.run_started.connect(set_seed)
	EventBus.palette_changed.connect(_on_palette_changed)
	EventBus.stat_changed.connect(_on_stat_changed)
	EventBus.equipment_changed.connect(_on_equipment_changed)
	_refresh_outlines()
	set_seed(GameState.run_seed)
	set_floor(GameState.floor_index, biome_name)
	set_hp(100.0, 100.0)
	set_gold(0, true)
	set_potions(0)


func _input(event: InputEvent) -> void:
	InputGlyphs.observe(event)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var gold: Variant = player.get("gold")
	if gold != null and int(gold) != _gold_target:
		set_gold(int(gold))
	var potions: Variant = player.get("potions")
	if potions != null and int(potions) != _potions_shown:
		set_potions(int(potions))


## Binds to a player node by duck typing; safe to call with partial implementations.
func bind(new_player: Node) -> void:
	player = new_player
	if player == null:
		_statuses.bind(null)
		return
	var health: Variant = player.get("health")
	if health is Health:
		var h := health as Health
		if not h.hp_changed.is_connected(set_hp):
			h.hp_changed.connect(set_hp)
		set_hp(h.hp, h.max_hp)
	var gold: Variant = player.get("gold")
	if gold != null:
		set_gold(int(gold), true)
	var potions: Variant = player.get("potions")
	if potions != null:
		set_potions(int(potions))
	if (
		player.has_signal(&"potion_used")
		and not player.is_connected(&"potion_used", _on_potion_used)
	):
		player.connect(&"potion_used", _on_potion_used)
	var slots: Variant = player.get("ability_slots")
	if slots != null:
		_bind_slots(slots)
	_bind_weapon_skill()
	prime_stats(false)
	_statuses.bind(player)


## Points the third slot at the weapon skill - a full secondary attack with its own cooldown
## that had no representation anywhere in the game. Re-read whenever the weapon changes.
func _bind_weapon_skill() -> void:
	var controller: Variant = player.get("weapon_controller") if player != null else null
	var node := controller as Node
	_weapon_controller = node
	if node != null and node.has_signal("weapon_changed"):
		if not node.is_connected("weapon_changed", _on_weapon_changed):
			node.connect("weapon_changed", _on_weapon_changed)
	refresh_weapon_skill()


## Re-reads `weapon_controller.skill` into the skill slot and announces it by name when it
## changes. The slot is a full secondary attack with its own cooldown, and an anonymous third
## box next to the two actives was the only thing that ever said so.
func refresh_weapon_skill() -> void:
	var skill: Resource = null
	if _weapon_controller != null and is_instance_valid(_weapon_controller):
		skill = _weapon_controller.get("skill") as Resource
	_skill_slot.set_ability(skill)
	if skill == _skill_shown:
		return
	_skill_shown = skill
	if skill == null or not _stats_live:
		return
	toast(skill_banner(skill), STAT_TOAST_DURATION)


## "Weapon skill: Cleave (Mouse R)" - the name, and the button that fires it.
static func skill_banner(skill: Resource) -> String:
	var name := str(skill.get("display_name")) if skill != null else ""
	if name.is_empty():
		name = "Weapon skill"
	var bound := InputGlyphs.binding_name(SKILL_ACTION, InputGlyphs.current_device())
	if bound == "-":
		return "Weapon skill: %s" % name
	return "Weapon skill: %s (%s)" % [name, bound]


## The weapon-skill slot, so tests and the gallery can inspect it.
func skill_slot() -> AbilitySlot:
	return _skill_slot


func _on_weapon_changed(_weapon: Resource) -> void:
	refresh_weapon_skill()


func _on_equipment_changed(_slot: StringName, _item: RefCounted) -> void:
	refresh_weapon_skill()


## Records the current primaries without announcing them. `live` arms the announcements:
## a run being set up re-emits every primary, and none of those is news.
func prime_stats(live: bool) -> void:
	_stat_seen = {}
	_stats_live = live
	if player == null:
		return
	var stats := player.get("stats") as Stats
	if stats == null:
		return
	for stat: StringName in Stats.PRIMARY:
		_stat_seen[stat] = stats.primary(stat)


## Primary stats used to move in both directions in total silence - a Config Gremlin could
## eat a point of Vitality and the only trace was a max-HP number nobody was watching. Every
## change now gets a banner and a floating number over the player, coloured by direction.
func _on_stat_changed(stat: StringName, value: int) -> void:
	if not STAT_SHORT.has(stat):
		return
	var had: bool = _stat_seen.has(stat)
	var previous := int(_stat_seen.get(stat, value))
	_stat_seen[stat] = value
	if not _stats_live or not had or value == previous:
		return
	var delta := value - previous
	var name := String(stat).capitalize()
	var role: StringName = &"heal" if delta > 0 else &"danger"
	var text := "+%d %s" % [delta, name] if delta > 0 else "-%d %s - stolen!" % [-delta, name]
	# The floater pops now, so the banner has to be now too: queued behind another message it
	# arrived seconds after the number it explains, and the two read as unrelated events.
	_toast.push_now(text, STAT_TOAST_DURATION)
	_pop_stat_number("%+d %s" % [delta, STAT_SHORT[stat]], role)


## A damage-number-style floater over the player: "+1 MGT" / "-1 VIT".
func _pop_stat_number(text: String, role: StringName) -> void:
	if player == null or not is_instance_valid(player):
		return
	var node := player as Node2D
	if node == null or not node.is_inside_tree():
		return
	if not bool(GameState.settings.get("damage_numbers", true)):
		return
	var screen := get_viewport().get_canvas_transform() * node.global_position
	var number := _free_number()
	number.pop_text(
		place_number(screen),
		text,
		false,
		ThemePalette.ensure_contrast(UiTheme.signal_color(role), UiTheme.color(&"floor"), 3.0)
	)


func _bind_slots(slots: Variant) -> void:
	var obj := slots as Object
	if obj == null:
		return
	var actives: Variant = obj.get("actives")
	var passives: Variant = obj.get("passives")
	var a: Array = actives.duplicate() if actives is Array else []
	var p: Array = passives.duplicate() if passives is Array else []
	set_abilities(a, p)
	# Live updates come from `EventBus.ability_slot_changed`, which `AbilitySlots` mirrors
	# every `slot_changed` to. `changed` is only for simpler duck-typed stubs that do not.
	if (
		not obj.has_signal("slot_changed")
		and obj.has_signal("changed")
		and not obj.is_connected("changed", _refresh_slots)
	):
		obj.connect("changed", _refresh_slots)


func _refresh_slots() -> void:
	if player != null:
		_bind_slots(player.get("ability_slots"))


func set_hp(hp: float, max_hp: float) -> void:
	_hp_bar.set_hp(hp, max_hp)
	_hp_text.text = "%d/%d" % [int(ceilf(hp)), int(max_hp)]
	_hp_text.theme_type_variation = &"Danger" if _hp_bar.is_danger() else &"Dim"


func set_gold(gold: int, instant: bool = false) -> void:
	_gold_target = gold
	if _gold_tween != null and _gold_tween.is_valid():
		_gold_tween.kill()
	if instant or not Accessibility.animates():
		_gold_shown = float(gold)
		_gold_label.text = str(gold)
		_gold_label.scale = Vector2.ONE
		return
	var tween := create_tween()
	_gold_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(_set_gold_shown, _gold_shown, float(gold), 0.35).set_trans(Tween.TRANS_QUAD)
	_gold_label.scale = Vector2(1.2, 1.2)
	tween.parallel().tween_property(_gold_label, "scale", Vector2.ONE, 0.25).set_trans(
		Tween.TRANS_BACK
	)


func _set_gold_shown(value: float) -> void:
	_gold_shown = value
	_gold_label.text = str(int(roundf(value)))


func gold_displayed() -> int:
	return int(roundf(_gold_shown))


func set_potions(count: int) -> void:
	_potions_shown = count
	_potion_count.text = "x%d" % count
	_potion_count.theme_type_variation = &"Dim" if count <= 0 else &"Bright"


## Floor label, including the boss marker. Boss floors (docs §2: 3, 6 and 9) drove generation
## only and were invisible to the player, so the label carries the same "BOSS" the arrival
## banner and the staircase prompt use.
func set_floor(index: int, biome: String) -> void:
	floor_index = index
	biome_name = biome
	_floor_label.text = floor_text(index, biome)
	refresh_objective()


## "Floor 3 - Crypt (Boss)". Shared by the HUD label and `RunManager`'s arrival banner, which
## is why it is static. Boss floors (docs §2: floors 3, 6 and 9) drove generation only and were
## signposted nowhere, so a new player descended into one with no reason to heal first.
static func floor_text(index: int, biome: String) -> String:
	var text := "Floor %d" % (index + 1)
	if not biome.is_empty():
		text += " - " + biome.capitalize()
	if is_boss_floor(index):
		text += BOSS_SUFFIX
	return text


## Whether `index` (0-based) is a boss floor. Mirrors `RunManager.BOSS_FLOORS` rather than
## reaching into the generator module, the same way `Minimap.RoomKind` mirrors `RoomType`.
static func is_boss_floor(index: int) -> bool:
	return BOSS_FLOOR_INDICES.has(index)


## Records the run's seed. The HUD does not draw it (see the class comment); Settings does.
func set_seed(new_seed: int) -> void:
	run_seed = new_seed


## Untyped Arrays on purpose: `AbilitySlots.actives` is `Array[ActiveAbility]` and typed
## arrays are invariant, so an `Array[Resource]` parameter could not take it.
func set_abilities(actives: Array, passives: Array) -> void:
	_actives = _as_resources(actives)
	_passives = _as_resources(passives)
	_slot_1.set_ability(_actives[0] if _actives.size() > 0 else null)
	_slot_2.set_ability(_actives[1] if _actives.size() > 1 else null)
	for child in _passive_row.get_children():
		_passive_row.remove_child(child)
		child.queue_free()
	for passive: Resource in _passives:
		if passive == null:
			continue
		var icon := UiTheme.icon_for(passive)
		var rect := TextureRect.new()
		rect.custom_minimum_size = Vector2(PASSIVE_ICON, PASSIVE_ICON)
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.texture = icon if icon != null else UiTheme.icon(UiTheme.Icon.FORTUNE)
		rect.tooltip_text = str(passive.get("display_name"))
		_passive_row.add_child(rect)


## Copies any (possibly narrowly typed) ability array into a plain `Array[Resource]`,
## so a later slot update can write a different Ability subclass into it.
static func _as_resources(source: Array) -> Array[Resource]:
	var out: Array[Resource] = []
	for entry: Variant in source:
		out.append(entry as Resource)
	return out


## The status-effect strip, so tests and the gallery can drive it without a live player.
func status_row() -> StatusRow:
	return _statuses


## `rooms`: {rect: Rect2i, cleared: bool, current: bool, type: int}; `edges`: tile-centre pairs;
## `links`: the route each edge is drawn along, same order (`FloorRoot.minimap_links`).
func set_minimap(
	rooms: Array[Dictionary], edges: Array[Vector4i], links: Array[PackedVector2Array] = []
) -> void:
	_minimap.set_rooms(rooms, edges, links)
	var was_found := _goal_found
	_goal_found = _minimap.goal_room_known(objective_room_kind())
	if _goal_found and not was_found:
		_stand_down_hint()
	refresh_objective()


## The room kind this floor's objective points at: the boss arena on a boss floor, the
## staircase on every other. A boss floor has stairs too, and marking those as "found" while
## the arena is still fogged would answer a question nobody asked.
func objective_room_kind() -> int:
	return Minimap.RoomKind.BOSS if is_boss_floor(floor_index) else Minimap.RoomKind.STAIRS


## The objective line: what this floor wants, and whether the room that grants it is on the
## map yet. Exposed so tests read the sentence a player reads.
func objective_text() -> String:
	if is_boss_floor(floor_index):
		return OBJECTIVE_FIGHT_BOSS if _goal_found else OBJECTIVE_FIND_BOSS
	return OBJECTIVE_TAKE_STAIRS if _goal_found else OBJECTIVE_FIND_STAIRS


func refresh_objective() -> void:
	if _objective_label == null:
		return
	_objective_label.text = objective_text()


## A ground drop the player is near: the tooltip draws its tag, or its compare card while the
## player stands on it, against the gear the bound player wears.
func _on_item_hover(pickup: Node2D, item: RefCounted, level: int) -> void:
	if _tooltip == null:
		return
	if level == ItemTooltip.Level.NONE and pickup != _tooltip.pickup:
		return
	var gear: Equipment = player.get("equipment") as Equipment if player != null else null
	var stats: Stats = player.get("stats") as Stats if player != null else null
	var band := tooltip_band()
	_tooltip.set_band(band.x, band.y)
	_tooltip.show_item(pickup, item as ItemInstance, level, gear, stats)


## The tooltip, so tests and the gallery can read what it shows.
func item_tooltip() -> ItemTooltip:
	return _tooltip


## The spans of screen x the two banner lanes may draw in (`Toast.lane_source`): the top lane
## between the HP block and the floor label, the bottom lane between the ability bar and the
## minimap. Read live, so a status strip that grew or a map that moved is honoured.
func banner_lanes() -> Dictionary:
	var top_left := (get_node("%Root/TopLeftPlate") as Control).get_global_rect()
	var top_right := (get_node("%Root/TopRightPlate") as Control).get_global_rect()
	var bar := get_node("%Root/BottomLeft") as Control
	var bar_right := bar.global_position.x + bar.get_combined_minimum_size().x
	var map := (get_node("%Minimap") as Control).get_global_rect()
	return {
		"top": Vector2(top_left.end.x, top_right.position.x),
		"bottom": Vector2(bar_right, map.position.x),
	}


## Every HUD block that may be on screen at once, by name, as screen rects. Empty rects are
## blocks not showing. `hud_layout_test` asserts they never overlap.
func block_rects() -> Dictionary:
	var bar := get_node("%Root/BottomLeft") as Control
	var out := {
		"top_left": (get_node("%Root/TopLeftPlate") as Control).get_global_rect(),
		"top_right": (get_node("%Root/TopRightPlate") as Control).get_global_rect(),
		"bottom_left":
		Rect2(bar.global_position, Vector2(bar.get_combined_minimum_size().x, bar.size.y)),
		"minimap": (get_node("%Minimap") as Control).get_global_rect(),
		"toast": _toast.panel_rect(),
		"track": _toast.track_rect(),
		"prompt": _prompt.get_global_rect() if _prompt.modulate.a > 0.0 else Rect2(),
	}
	if _tooltip.visible and _tooltip.level == ItemTooltip.Level.CLOSE:
		out["tooltip"] = _tooltip.card_rect()
	return out


## The free band on the left of the screen the tooltip's compare card may sit in: from the
## bottom of the top-left plate (HP, potion, gold, statuses) to the top of the ability bar.
## Neither the player at the centre nor a HUD block is ever under the card.
func tooltip_band() -> Vector2:
	var top := (get_node("%Root/TopLeftPlate") as Control).get_global_rect().end.y
	var bottom := (get_node("%Root/BottomLeft") as Control).get_global_rect().position.y
	return Vector2(top, bottom)


func show_prompt(text: String, prompt_visible: bool) -> void:
	_prompt_label.text = text
	center_prompt()
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	var tween := create_tween()
	_prompt_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_prompt, "modulate:a", 1.0 if prompt_visible else 0.0, 0.12)


## Re-centres the interact prompt on the screen. The panel is anchored to the bottom centre
## but keeps its left offset when it resizes, so without this a longer prompt than the one the
## scene was laid out for ("Open chest") grows off to one side instead of around the centre.
func center_prompt() -> void:
	_prompt.reset_size()
	var width := maxf(_prompt.size.x, _prompt.get_combined_minimum_size().x)
	_prompt.offset_left = -floorf(width * 0.5)
	_prompt.offset_right = _prompt.offset_left + width


func toast(text: String, duration: float = Toast.DEFAULT_DURATION) -> void:
	_toast.push(text, duration)


func toast_widget() -> Toast:
	return _toast


func _on_palette_changed(_palette: ThemePalette) -> void:
	_refresh_outlines()


## Outlines the free-floating HUD labels so they stay readable over any floor.
func _refresh_outlines() -> void:
	var outline := UiTheme.color(&"void")
	outline.a = 0.85
	for label: Label in [_hp_text, _potion_count, _gold_label, _floor_label, _objective_label]:
		label.add_theme_constant_override(&"outline_size", TEXT_OUTLINE * 2)
		label.add_theme_color_override(&"font_outline_color", outline)


## The radio gets its own lane. It used to share the single gameplay banner, so a track change
## could hold up - or, at the queue cap, delete - "-1 Might - stolen!" while that loss was
## already floating over the player's head.
func _on_track_changed(title: String, artist: String) -> void:
	var text := title if artist.is_empty() else "%s - %s" % [title, artist]
	# The track's mood in words ("brooding, slow"), so the banner names the cause of the look
	# the lights are crossfading to (docs 10.2). Empty when nothing is known about the track.
	var words := Music.mood_words()
	if not words.is_empty():
		text += " (%s)" % words
	_toast.push_track("Now playing: " + text, 3.0)


func _on_floor_started(index: int) -> void:
	_goal_found = false
	set_floor(index, biome_name)
	prime_stats(true)
	refresh_weapon_skill()
	if index == 0 and not _hinted:
		_hinted = true
		toast(FIRST_FLOOR_HINT, FIRST_FLOOR_HINT_DURATION)
	else:
		# A four-second banner outlives a floor change: a capture of floor 6 still carried the
		# first-floor hint. Nothing that was true only of floor 1 may still be on screen here.
		_stand_down_hint()


## Drops the first-floor hint if it is still up. Called whenever the thing it explains has
## stopped being the player's next problem, so the banner can never contradict the objective.
func _stand_down_hint() -> void:
	if _toast != null:
		_toast.dismiss(FIRST_FLOOR_HINT)


## Puts up the arrival banner for a floor, having pulled down the one the floor before it left
## in the queue. A banner is a sentence frozen when it was pushed, and the gameplay lane holds
## a backlog: descending quickly used to leave "FLOOR 5 - LIBRARY" sitting over a HUD header
## that already read "Floor 8 - Void", which is the HUD contradicting itself.
func announce_floor(index: int, biome: String, duration: float = ARRIVAL_DURATION) -> void:
	if _toast == null:
		return
	if not _arrival_banner.is_empty():
		_toast.dismiss(_arrival_banner)
	_arrival_banner = floor_text(index, biome)
	_toast.push(_arrival_banner, duration)


## Queues the sentence that says what the music made of this floor ("Built to Super Space -
## dense, fast and bright") behind the arrival banner, so the cause is on screen next to the
## effect. Pulls the previous floor's line first, for the reason `announce_floor` does.
func announce_music(text: String, duration: float = MUSIC_BANNER_DURATION) -> void:
	if _toast == null or text.is_empty():
		return
	if not _music_banner.is_empty():
		_toast.dismiss(_music_banner)
	_music_banner = text
	_toast.push(_music_banner, duration)


## The floor-start line for a desktop. With a wallpaper it names the two halves of the
## owner's rule (docs §16, "The theme is the colours"): the picture lit the floor and laid
## it out, the theme said what colour all of it is. With no wallpaper the theme did both.
static func desktop_line(theme_name: String, has_wallpaper: bool) -> String:
	var who := theme_name if not theme_name.is_empty() else "your theme"
	if has_wallpaper:
		return DESKTOP_LINE_WALLPAPER % who
	return DESKTOP_LINE_THEME % who


## Queues the desktop line behind the arrival banner (`RunManager` calls it right after
## `announce_floor`, from the live `Desktop`) and pulls the previous floor's copy down first,
## like the arrival and music banners. Not folded into `announce_floor`: the arrival banner
## is pinned to be the only thing that call queues, so a stale one is always found and dropped.
func announce_desktop(text: String, duration: float = DESKTOP_BANNER_DURATION) -> void:
	if _toast == null or text.is_empty():
		return
	if not _desktop_banner.is_empty():
		_toast.dismiss(_desktop_banner)
	_desktop_banner = text
	_toast.push(_desktop_banner, duration)


func _on_gold_changed(amount: int) -> void:
	set_gold(amount)


func _on_ability_slot_changed(index: int, ability: Resource) -> void:
	if index < 0:
		return
	if index < 2:
		while _actives.size() <= index:
			_actives.append(null)
		_actives[index] = ability
	else:
		var p := index - 2
		while _passives.size() <= p:
			_passives.append(null)
		_passives[p] = ability
	set_abilities(_actives, _passives)


## Potion feedback. `potion_used` had no listener at all: spending the run's single heal moved
## the HP bar and nothing else, which reads as "did the key even register?".
func _on_potion_used(amount: float) -> void:
	var healed := int(roundf(amount))
	if healed <= 0:
		return
	_pop_stat_number("+%d HP" % healed, &"heal")


func _on_damage_number(pos: Vector2, amount: float, is_crit: bool, color: Color) -> void:
	if not bool(GameState.settings.get("damage_numbers", true)):
		return
	var screen := get_viewport().get_canvas_transform() * pos
	var number := _free_number()
	var readable := ThemePalette.ensure_contrast(color, UiTheme.color(&"floor"), 3.0)
	number.pop(place_number(screen, is_crit), amount, is_crit, readable)


## Where a floating number should start, given the canvas-space point it describes and whether
## it is a crit (crits are drawn in the taller heading font and need a taller lane).
##
## Two moves, both readability rather than polish (docs §1 pillar 1). First the anchor lifts
## clear of a 16 px character's head, so a number never opens on top of the thing it is
## reporting. Then it climbs until its glyph box is not sitting on a number that is still on
## screen: damage, a crit and a stolen stat all landing in the same beat used to overprint
## each other at one anchor, and the result read as a single smear of glyphs. Lanes are packed
## by measured glyph height rather than by a fixed step, and checked against live positions,
## so a number that has already risen frees the room it was using. Because every number then
## climbs at the same constant speed, the gap found here is the gap they keep.
func place_number(screen: Vector2, is_crit: bool = false) -> Vector2:
	var height := DamageNumber.height_for(is_crit)
	var anchor := screen + Vector2(0.0, -_feel_profile.number_head_offset_px)
	for _slot in range(maxi(1, _feel_profile.number_lane_slots)):
		var push := _lane_push(anchor, height)
		if push <= 0.0:
			break
		anchor.y -= push
	return anchor


## Px this anchor has to climb to clear every live number it currently collides with, or 0
## when it already fits. A number's glyphs run from `position.y - height()` to `position.y`.
func _lane_push(anchor: Vector2, height: float) -> float:
	var push := 0.0
	for number: DamageNumber in _damage_pool:
		if not number.visible:
			continue
		if absf(number.position.x - anchor.x) >= _feel_profile.number_lane_width_px:
			continue
		var other_top := number.position.y - number.height()
		if anchor.y - height >= number.position.y or anchor.y <= other_top:
			continue
		push = maxf(push, anchor.y - other_top + LANE_GAP)
	return push


func _free_number() -> DamageNumber:
	for number: DamageNumber in _damage_pool:
		if not number.visible:
			return number
	var oldest: DamageNumber = _damage_pool[0]
	_damage_pool.remove_at(0)
	_damage_pool.append(oldest)
	return oldest


## The floating-text pool, in slot order. Read-only for tests and debug overlays.
func damage_numbers() -> Array[DamageNumber]:
	return _damage_pool


func active_damage_numbers() -> int:
	var count := 0
	for number: DamageNumber in _damage_pool:
		if number.visible:
			count += 1
	return count
