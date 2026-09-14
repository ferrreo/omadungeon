## Global typed signal bus. Systems publish here; nobody reaches across the tree.
extends Node

## Emitted when the desktop theme and/or wallpaper changed. `kind` is one of
## DesktopChangeKind.
signal desktop_changed(kind: int)
## Emitted after a new ThemePalette is active (following desktop_changed or a reload).
signal palette_changed(palette: ThemePalette)

signal run_started(run_seed: int)
signal run_ended(victory: bool)
signal floor_started(floor_index: int)
signal room_entered(room_id: int)
signal room_locked(room_id: int)
signal room_cleared(room_id: int)
signal enemy_spawned(enemy: Node2D)
signal enemy_died(enemy: Node2D, killer: Node2D)
signal player_damaged(amount: int, source: Node2D)
signal player_healed(amount: int)
signal player_died
signal stat_changed(stat: StringName, value: int)
signal gold_changed(amount: int)
signal item_equipped(item: Resource, slot: StringName)
signal ability_slot_changed(index: int, ability: Resource)
signal chest_opened(chest: Node2D)
signal music_track_changed(title: String, artist: String)
signal music_beat(strength: float)
signal toast(text: String, duration: float)
## UI: floating damage number at a world position (HUD pools DamageNumber labels).
signal damage_number(pos: Vector2, amount: float, is_crit: bool, color: Color)
## UI: interaction prompt near the bottom of the screen ("Open chest"), hidden when visible=false.
signal interact_prompt(text: String, visible: bool)
## Input: active device changed (0 = keyboard/mouse, 1 = gamepad); UI swaps glyphs.
signal input_device_changed(device: int)
## Music: duck (on=true) or restore the music bus; `amount` is the 0..1 volume fraction to drop.
signal music_duck(amount: float, on: bool)
## Rooms: player used the stairs; RunManager builds the next floor.
signal floor_exit_requested
## Rooms: player interacted with an Altar node (ability choice UI opens).
signal altar_used(altar: Node2D)
## Rooms: player interacted with a Shop node (shop UI opens with shop.offers).
signal shop_opened(shop: Node2D)
## Rooms: player interacted with a Shrine node (buff-for-cost UI opens with shrine.options).
signal shrine_used(shrine: Node2D)
## Rooms: something wants a pickup spawned (gold, heart, orb) at a world position.
signal spawn_pickup(kind: StringName, pos: Vector2, amount: int)
signal screen_shake(strength: float, duration: float)  # px amplitude; PlayerCamera listens

## Player (or a player-owned ability/hireling) dealt damage to `target` (abilities module hooks).
signal player_hit_dealt(target: Node2D, info: DamageInfo)
## Player performed a dodge; `style` is the class dodge flavour (roll/dash/blink/hop).
signal player_dodged(style: StringName)
## An active ability was cast from slot `index` (HUD/audio feedback).
signal ability_used(index: int, ability: Resource)
## Emitted by SaveManager when an achievement/unlock is newly earned (id -> title for the toast).
signal unlock_earned(id: StringName, title: String)
## Enemies/traps: request a timed hazard (`kernel_spike`, `ricer_trap`, ...) at a world position.
signal spawn_hazard(kind: StringName, pos: Vector2, duration: float)
## FX: full-screen colour tint (e.g. Kernel Panic) fading out over `duration` seconds.
signal screen_tint(color: Color, duration: float)
## Audio/UI: a GameState.settings entry changed (key is the settings dictionary key).
signal settings_changed(key: String)
## Traps: the player fell into a pit at `pos` (RunManager respawns them at the room entry).
signal player_fell(pos: Vector2)
## Traps: a pressure plate with this id was stepped on (doors/cages/linked traps react).
signal plate_pressed(id: StringName)
## Traps/rooms: something asks the RunManager to spawn enemy `id` at a world position (mimics).
signal spawn_enemy_requested(id: StringName, pos: Vector2)
## Traps: a trap became dangerous (audio/screen-shake hook).
signal trap_triggered(trap: Node2D)
## Items: a worn slot changed; `item` is the ItemInstance (RefCounted) or null after an unequip.
signal equipment_changed(slot: StringName, item: RefCounted)
## Items: the player is near (`level` 1) or standing on (2) a ground drop, or has left it (0).
## `item` is the drop's ItemInstance; the HUD's `ItemTooltip` draws the answer.
signal item_hover(pickup: Node2D, item: RefCounted, level: int)
## Floor: what descending would leave behind right now - item drops still lying on the floor.
## `DescendNotice` counts them; the HUD's minimap prints the count under the map.
signal floor_leftovers(items: int)

## Bosses: health bar feed for the HUD (boss display name, 0..1 hp fraction, phase).
signal boss_health_changed(name: String, fraction: float, phase: int)

enum DesktopChangeKind { THEME = 1, WALLPAPER = 2, BOTH = 3 }
