## Sound-effect playback (autoload `Audio`): creates the Master/Music/SFX/UI buses, pools
## players, lazily loads `assets/sfx/<id>.wav`, throttles repeats and auto-plays feedback
## for common EventBus signals. Safe under the Dummy audio driver (headless tests).
class_name AudioManager
extends Node

const SFX_DIR := "res://assets/sfx/"
const POOL_SIZE := 16
## Minimum spacing between two plays of the same id (stops machine-gun stacking).
const MIN_INTERVAL_MS := 40
## Coin pickups are spammy; throttle them harder.
const GOLD_INTERVAL_MS := 120
const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"
## Every sound id the generator produces (tools/gen-sfx.py). Kept here so tests and the
## preload can check completeness.
const IDS: Array[StringName] = [
	&"ui_move",
	&"ui_accept",
	&"ui_back",
	&"hit_melee",
	&"hit_ranged",
	&"shoot_bow",
	&"shoot_wand",
	&"dodge",
	&"potion",
	&"stat_up",
	&"ability_cast",
	&"trap_spike",
	&"trap_fire",
	&"explosion",
	&"door_close",
	&"door_open",
	&"chest_open",
	&"coin",
	&"level_up",
	&"boss_roar",
	&"honk",
	&"clown_pop",
	&"tome_thud",
	&"teleport",
	&"freeze",
	&"burn",
	&"shock",
	&"hurt",
	&"heal",
	&"death",
	&"room_clear",
	&"equip",
	&"laser",
	&"pit_fall",
	&"shield",
]
## Trap `kind` -> sound id for the EventBus.trap_triggered hook (unknown kinds use trap_spike).
const TRAP_SOUNDS: Dictionary = {
	&"spike_floor": &"trap_spike",
	&"kernel_spike": &"trap_spike",
	&"arrow_wall": &"shoot_bow",
	&"fire_vent": &"trap_fire",
	&"laser_grid": &"laser",
	&"pit": &"pit_fall",
	&"ice_slide": &"freeze",
	&"ricer_trap": &"shock",
	&"mimic_chest": &"clown_pop",
	&"pressure_plate": &"door_open",
}
## Player death cue: the shared `death` clip slowed down and louder, throttle bypassed.
const PLAYER_DEATH_PITCH := 0.6
const PLAYER_DEATH_DB := 3.0

## Distance (px) at which positional sounds fall silent. With a 480x270 view, one screen away
## tapers to silence while on-screen sounds stay within a few dB.
@export var max_distance: float = 640.0
## Attenuation exponent of positional sounds (1 = linear roll-off).
@export var attenuation: float = 1.0

## Number of successful plays since startup (diagnostics / tests).
var play_count: int = 0

var _library: Dictionary = {}
var _last_played_ms: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _players_2d: Array[AudioStreamPlayer2D] = []
var _next: int = 0
var _next_2d: int = 0
var _rng := RandomNumberGenerator.new()
var _warned: Dictionary = {}
## True once a floor of the current run is up (gates the level_up jingle past run setup).
var _floor_ready: bool = false
## Last gold total seen on EventBus.gold_changed (-1 = none yet, so the first one is silent).
var _last_gold: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	_rng.randomize()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.bus = BUS_SFX
		add_child(p)
		_players.append(p)
		var p2 := AudioStreamPlayer2D.new()
		p2.name = "Sfx2D%d" % i
		p2.bus = BUS_SFX
		p2.max_distance = max_distance
		p2.attenuation = attenuation
		add_child(p2)
		_players_2d.append(p2)
	apply_settings()
	_connect_bus()


## Creates the Music/SFX/UI buses (sending to Master) and a spectrum analyzer on Music.
## Idempotent; MusicManager calls it too so autoload order does not matter.
static func ensure_buses() -> void:
	for bus_name: StringName in [BUS_MUSIC, BUS_SFX, BUS_UI]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, BUS_MASTER)
	# UI blips feed the SFX bus instead of Master so the SFX slider governs them too (whoever
	# owns the settings UI only applies Master/Music/SFX). The UI bus stays at unity and exists
	# purely as a routing/effect point for menu sounds.
	var ui_idx := AudioServer.get_bus_index(BUS_UI)
	if ui_idx > 0 and AudioServer.get_bus_index(BUS_SFX) < ui_idx:
		if AudioServer.get_bus_send(ui_idx) != BUS_SFX:
			AudioServer.set_bus_send(ui_idx, BUS_SFX)
		AudioServer.set_bus_volume_db(ui_idx, 0.0)
		AudioServer.set_bus_mute(ui_idx, false)
	var music_idx := AudioServer.get_bus_index(BUS_MUSIC)
	if music_idx != -1 and spectrum_effect_index() == -1:
		var fx := AudioEffectSpectrumAnalyzer.new()
		fx.buffer_length = 0.1
		fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
		AudioServer.add_bus_effect(music_idx, fx)


## Index of the AudioEffectSpectrumAnalyzer on the Music bus, or -1.
static func spectrum_effect_index() -> int:
	var music_idx := AudioServer.get_bus_index(BUS_MUSIC)
	if music_idx == -1:
		return -1
	for i in AudioServer.get_bus_effect_count(music_idx):
		if AudioServer.get_bus_effect(music_idx, i) is AudioEffectSpectrumAnalyzer:
			return i
	return -1


## Applies master/music/sfx volumes from GameState.settings to the buses. The UI bus is not
## touched: it sends into SFX, so the SFX volume already covers menu blips.
func apply_settings() -> void:
	set_bus_volume(BUS_MASTER, float(GameState.settings.get("master_volume", 1.0)))
	set_bus_volume(BUS_MUSIC, float(GameState.settings.get("music_volume", 0.8)))
	set_bus_volume(BUS_SFX, float(GameState.settings.get("sfx_volume", 1.0)))


## Sets a bus volume from a 0..1 linear value (0 mutes).
static func set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.0005)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0005)))


## Plays a sound. `pos == Vector2.INF` means non-positional. Returns false when throttled,
## missing or unknown. `pitch_var` is the random pitch spread (0.08 = +-8%) around `pitch`.
func play(
	id: StringName,
	pos: Vector2 = Vector2.INF,
	pitch_var: float = 0.08,
	volume_db: float = 0.0,
	pitch: float = 1.0
) -> bool:
	var stream := get_stream(id)
	if stream == null:
		return false
	var now := Time.get_ticks_msec()
	var min_interval := GOLD_INTERVAL_MS if id == &"coin" else MIN_INTERVAL_MS
	var last := int(_last_played_ms.get(id, -100000))
	if now - last < min_interval:
		return false
	_last_played_ms[id] = now
	var pitch_scale := maxf(pitch * (1.0 + _rng.randf_range(-pitch_var, pitch_var)), 0.05)
	var bus := BUS_UI if id.begins_with("ui_") else BUS_SFX
	if pos == Vector2.INF:
		var p := _acquire()
		p.stream = stream
		p.pitch_scale = pitch_scale
		p.volume_db = volume_db
		p.bus = bus
		p.play()
	else:
		var p2 := _acquire_2d()
		p2.stream = stream
		p2.pitch_scale = pitch_scale
		p2.max_distance = max_distance
		p2.attenuation = attenuation
		p2.volume_db = volume_db
		p2.bus = bus
		p2.global_position = pos
		p2.play()
	play_count += 1
	return true


## Plays a UI blip (non-positional, no pitch variation).
func play_ui(id: StringName) -> bool:
	return play(id, Vector2.INF, 0.0)


## Stops every pooled player.
func stop_all() -> void:
	for p in _players:
		p.stop()
	for p2 in _players_2d:
		p2.stop()


## Loads every known id into the library (call once at boot to avoid first-play hitches).
func preload_all() -> void:
	for id in IDS:
		get_stream(id)


## Returns the cached stream for `id`, loading it from assets/sfx on first use; null if absent.
func get_stream(id: StringName) -> AudioStream:
	if _library.has(id):
		return _library[id]
	var path := SFX_DIR + String(id) + ".wav"
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null and not _warned.has(id):
		_warned[id] = true
		push_warning("AudioManager: missing sfx %s" % path)
	_library[id] = stream
	return stream


## True when the sound file for `id` exists.
func has_sound(id: StringName) -> bool:
	return get_stream(id) != null


## Milliseconds since `id` last played (huge when never played).
func ms_since(id: StringName) -> int:
	return Time.get_ticks_msec() - int(_last_played_ms.get(id, -100000))


## Sound id for a trap kind (see TRAP_SOUNDS).
static func trap_sound_for(kind: StringName) -> StringName:
	return TRAP_SOUNDS.get(kind, &"trap_spike")


func _acquire() -> AudioStreamPlayer:
	for i in POOL_SIZE:
		var p := _players[(_next + i) % POOL_SIZE]
		if not p.playing:
			_next = (_next + i + 1) % POOL_SIZE
			return p
	var stolen := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	return stolen


func _acquire_2d() -> AudioStreamPlayer2D:
	for i in POOL_SIZE:
		var p := _players_2d[(_next_2d + i) % POOL_SIZE]
		if not p.playing:
			_next_2d = (_next_2d + i + 1) % POOL_SIZE
			return p
	var stolen := _players_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_SIZE
	return stolen


func _connect_bus() -> void:
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_healed.connect(_on_player_healed)
	EventBus.player_died.connect(_on_player_died)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.room_locked.connect(func(_room_id: int) -> void: play(&"door_close"))
	EventBus.room_cleared.connect(func(_room_id: int) -> void: play(&"room_clear"))
	EventBus.chest_opened.connect(_on_chest_opened)
	EventBus.item_equipped.connect(func(_item: Resource, _slot: StringName) -> void: play(&"equip"))
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.player_dodged.connect(func(_style: StringName) -> void: play(&"dodge"))
	EventBus.ability_slot_changed.connect(_on_ability_slot_changed)
	EventBus.ability_used.connect(
		func(_index: int, _ability: Resource) -> void: play(&"ability_cast")
	)
	EventBus.trap_triggered.connect(_on_trap_triggered)
	EventBus.run_started.connect(_on_run_started)
	EventBus.floor_started.connect(func(_floor_index: int) -> void: _floor_ready = true)
	EventBus.settings_changed.connect(_on_settings_changed)


## A new run: the first gold broadcast is the starting purse, not a pickup.
func _on_run_started(_run_seed: int) -> void:
	_floor_ready = false
	_last_gold = -1


func _on_player_damaged(_amount: int, _source: Node2D) -> void:
	play(&"hurt")


func _on_player_healed(_amount: int) -> void:
	play(&"heal")


## The player's death gets its own cue: never throttled away by an enemy dying the same frame.
func _on_player_died() -> void:
	_last_played_ms.erase(&"death")
	play(&"death", Vector2.INF, 0.0, PLAYER_DEATH_DB, PLAYER_DEATH_PITCH)


## The level_up jingle only plays for ability picks made during play, not for the innate /
## contract slots RunManager fills while setting the run up.
func _on_ability_slot_changed(_index: int, ability: Resource) -> void:
	if ability != null and _floor_ready:
		play(&"level_up", Vector2.INF, 0.0)


func _on_trap_triggered(trap: Node2D) -> void:
	var kind: StringName = &""
	if is_instance_valid(trap):
		var raw: Variant = trap.get(&"kind")
		if raw is StringName or raw is String:
			kind = StringName(raw)
	var id := trap_sound_for(kind)
	if is_instance_valid(trap) and trap.is_inside_tree():
		play(id, trap.global_position)
	else:
		play(id)


func _on_enemy_died(enemy: Node2D, _killer: Node2D) -> void:
	if is_instance_valid(enemy) and enemy.is_inside_tree():
		play(&"death", enemy.global_position, 0.12)
	else:
		play(&"death", Vector2.INF, 0.12)


func _on_chest_opened(chest: Node2D) -> void:
	if is_instance_valid(chest) and chest.is_inside_tree():
		play(&"chest_open", chest.global_position)
	else:
		play(&"chest_open")


## `gold_changed` carries the player's *total*, not a delta, and also fires on spends, on the
## class being applied and on a save being loaded. Only an increase is a pickup.
func _on_gold_changed(amount: int) -> void:
	var previous := _last_gold
	_last_gold = amount
	if previous >= 0 and amount > previous:
		play(&"coin", Vector2.INF, 0.1)


func _on_settings_changed(key: String) -> void:
	if key.ends_with("_volume"):
		apply_settings()
