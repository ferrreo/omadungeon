# Omadungeon — Architecture & Contracts

Read this before touching code. It is the contract between modules so many people can
work in parallel without stepping on each other. Design intent lives in
`GAME_DESIGN.md`; this file is *how the code is shaped*.

## 1. Ground rules

- Godot 4.7, GDScript, **static typing everywhere** (`untyped_declaration` is an error).
  `class_name` on every script. No `Variant` leaking through public APIs.
- No `get_node("../..")`. Reach siblings via exported NodePaths, `%UniqueName`, or signals.
  Cross-system communication goes through `EventBus` (autoload) signals.
- Content is data: `Resource` subclasses in `data/**.tres`. Code is behaviour.
- Every generator/resolver is a pure function of (inputs, RandomNumberGenerator) and has
  a gdUnit4 test in `tests/unit/`. Never use global `randf()` in gen/loot code; take an
  RNG from `RunRng`.
- Physics at 60 Hz. Internal resolution 480×270, tile = 16 px (`Layers.TILE`).
- Style: `gdformat` + `gdlint` clean (`tools/lint.sh`). Doc comment (`##`) on every class
  and public method that isn't obvious. Line length 110.
- Tests must pass headless: `tools/test.sh`. Scripts must compile: `tools/check-scripts.sh`,
  which re-parses every `.gd` through `tools/check_scripts.gd` and prints the count it checked.
  It is not `--import` any more: the importer will not re-parse a script whose cache it thinks
  is current, so it used to print "scripts ok" over a tree holding a hard parse error.
  When several people test at once, use `OMADUNGEON_TEST_COPY=1 tools/test.sh`: it rsyncs
  the project **and** gives the run its own `$XDG_DATA_HOME`, so neither `res://` nor
  `user://` is shared. Until round 7 it isolated `res://` only, and two overlapping runs
  wrote each other's save files and fixtures — the advice above was manufacturing red
  gates that named healthy suites. Every harness (`test.sh`, `run-scenario.sh`,
  `ui-gallery.sh`, `check-scripts.sh`) does this now, copy mode or not;
  `OMADUNGEON_KEEP_USER_DIR=1` opts out. They share `tools/sandbox-lib.sh` for deciding when a
  leftover sandbox belongs to nobody: not "the pid in its name is gone" (that pid is the
  harness shell, and Godot outlives a killed shell while still reading the copy) but "no lock
  held, no live process working inside it, and no live owner".
- Never run anything that opens a window on the real session. Rendered checks go through
  `tools/run-scenario.sh <scenario> [theme]` (nested headless sway → `tests/out/<scenario>.png`,
  or `tests/out/<scenario>_<theme>.png` for any theme other than the default `tokyo-night`).
- No AI attribution anywhere (commits, comments, docs).

## 2. Autoloads (in order)

The order below is the order in `project.godot [autoload]`, and it matters: `Desktop` reads
`GameState.cli_args`, and `RunManager` needs every other autoload up before it starts a run.

| # | Name | Script | Role |
|---|------|--------|------|
| 1 | `EventBus` | `src/core/event_bus.gd` | Typed global signals. Add signals here, never ad-hoc buses. |
| 2 | `GameState` | `src/core/game_state.gd` | Settings dict, CLI args (`cli_args`), run seed/floor/class. |
| 3 | `Desktop` | `src/desktop/desktop_watcher.gd` | Live `palette: ThemePalette`, `profile: ThemeProfile`, `wallpaper`. Polls the Omarchy state dir; emits `EventBus.palette_changed`. |
| 4 | `SaveManager` | `src/core/save_manager.gd` | `run.json` / `profile.json`, unlocks, debounced autosave. |
| 5 | `Audio` | `src/audio/audio_manager.gd` | SFX buses, player pooling, EventBus-driven feedback. |
| 6 | `Music` | `src/music/music_manager.gd` | Radio playlist, crossfades, spectrum/beat, `MusicProfile`; owns the music lights (`MusicReactiveLayer`) and hands them each track's `MusicMood`. |
| 7 | `RunManager` | `src/core/run_manager.gd` | Run lifecycle, floor building, offer flows, `--test-scenario` driver. |
| 8 | `UiNav` | `src/ui/ui_nav_service.gd` | Owns the one `UiStickNav`: the gamepad left stick turned into discrete UI presses. |
| 9 | `Quit` | `src/core/quit_service.gd` | Answers the window manager's close request, from any screen, through `QuitGuard`. |

`UiNav` is an autoload rather than a node the first screen inserts because `add_child()` is
refused on a parent that is itself mid-insertion - which the scene root is while the main scene
is being added - so a screen asking from its own `_ready()` got the refusal on stderr and a dead
stick on the title screen only. Deferring the insert instead let two screens build two services
and turned one flick of the stick into two presses.

`Quit` is an autoload for the same shape of reason, found the same way. `SceneTree.auto_accept_quit`
has to be off so `QuitGuard` can arm its watchdog before the tree goes (docs 14), and the moment it
is off the close request does nothing unless a node in the tree turns it back into a quit. That node
was `Main` - the *boot* scene, which `RunManager.new_run()` swaps for `src/game.tscn` and frees. From
the first floor onwards nobody answered: measured 2026-09-14 in nested sway with a built floor up,
`swaymsg kill` (the same `xdg_toplevel.close` a title-bar X or Alt+F4 sends) arrived, `SaveManager`
flushed on it, and the game was still running 30 s later. Not a race and not Wayland-specific - a
player simply could not close the window during a run. An autoload is added before the main scene
exists and outlives every scene swap, so the answer is there on the title, on floor 1 and on the
summary alike. `tools/check-quit.sh close-headless|close` is what stops it moving back into a scene.

`project.godot` also sets `use_custom_user_dir` with `custom_user_dir_name="omadungeon"`, so
`user://` is `$XDG_DATA_HOME/omadungeon/`. That is one directory per *machine*, not per
checkout: a project copy does not get a `user://` of its own, which is why the harnesses
move `$XDG_DATA_HOME` per run rather than relying on the copy. A fixed `user://` path in a
test is therefore a cross-run shared resource; write inside
`SaveManager.test_sandbox_dir()` (`user://test/<pid>`) instead.

## 3. Directory ownership

```
src/core       EventBus, GameState, RunRng, Layers, RunManager, SaveManager, RunState, Profile,
               FloorRestore/FloorPopulator/FloorPickups, PackLedger, RunTally, test_scenarios, ArenaCapture;
               core/feel (GameFeel, FeelProfile, DangerTell, FxPool), core/balance,
               core/perf, core/progression
src/desktop    theme/wallpaper integration (done in M0); CompositorWindow, the window manager
               asked about the game's own window (the fullscreen the engine cannot see)
src/combat     DamageInfo, Stats, Health, Hitbox, Hurtbox, StatusEffect(+Controller), Projectile
src/entities   Entity base; enemies/ (EnemyBase, EnemyDef, per-enemy scripts+scenes, bosses/)
src/player     Player, PlayerInput, ClassDef, weapon controller, dodge
src/abilities  Ability/ActiveAbility/PassiveAbility bases, AbilitySlots, actives/, passives/
src/items      ItemBase, WeaponBase, Affix, ItemInstance, ItemGenerator, Equipment, ProcSprite
src/gen        FloorData, FloorGenerator (archetype → graph → layout → corridors → dressing → fill → lantern anchors → validate), FloorArchetype, RoomShape, RoomBudget, ArenaSpawns, LanternAnchors, Biome
src/rooms      FloorBuilder (FloorData → TileMapLayer + nodes), Room, Door, Chest, Stairs, Altar, Shop, Shrine;
               DungeonLight (light profile + the live light contract: ambient_color/energy,
               torch_color/energy_scale/flicker_amplitude, all read from Music.mood_state());
               rooms/lighting/ = the dynamic layer built on that contract: LightingProfile
               (data/rooms/lighting.tres), LightRig (the `Lighting` child of every FloorRoot:
               darkness, lanterns, occluders, room shades, blobs, the emitter pool),
               WallLantern, WallOccluders, LightEmitter
src/traps      TrapBase + concrete traps
src/ui         Screens (Title, ClassSelect, Hud, ChestUi, LoadoutScreen, PauseMenu, SettingsPanel,
               RunSummary, StatsScreen, AccessibilityBoard, Credits) + widgets (Toast, Minimap,
               ItemTooltip, CompareView, OfferCard, InputGlyphs, ItemCard, AbilityCard,
               CompareRows, LoadoutModel, ShapeBadge, HpBar, StatusRow, AbilitySlot);
               UiTheme/UiRuntime, Accessibility, CardFit; controller navigation
               (UiFocusChain, UiStickNav, UiListReveal, UiHintLine, InputBindings,
               UiNavProfile, ui_nav_service.gd = the `UiNav` autoload); UiFakes + UiGallery
src/audio      AudioManager (SFX buses, pooling)
src/music      MusicManager (radio playlist, analyzer, MusicProfile); MusicMood/MusicMoodLevers/
               MusicMoodState (per-track measured mood -> live look), MusicReactiveLayer +
               MusicMotes (the music lights; shader globals music_tint/music_tone read by
               src/desktop/music_grade.gdshaderinc)
data/          .tres content: abilities/, affixes/, balance/, biomes/, classes/, desktop/,
               enemies/, feel/, items/, music/, perf/, pickups/, progression/, rooms/, themes/,
               traps/, ui/
assets/        sprites/, tiles/, fonts/, sfx/, music/
tests/unit     one *_test.gd per module, plus six capture scenes that are main scenes rather
               than suites (feel/tell_capture, rooms/prop_frame_capture,
               rooms/pickup_frame_capture, rooms/lighting_frame_capture, ui/stats_capture,
               ui/trade_pages_capture) and the death_soak scene, each declared in
               tools/checks.json with the command that runs it
tools/         scripts only, and tools/checks.json - the register of every check the repository
               owns. Every file under tools/ is declared there, one entry per file (no
               directory claims), and the gate fails when one is not
               (tests/unit/tools/check_registry_test.gd)
reports/checks the results ledger: one <check id>.json per check tools/run-checks.sh has run
               here, carrying its exit code and when. Gitignored, machine-written, and what
               the gate reads to decide whether the checks outside tier 1 have passed lately
```

## 4. Core contracts (already implemented — use, don't reinvent)

### Physics layers — `Layers`
Bits: `WORLD, PLAYER, ENEMY, PLAYER_HURTBOX, ENEMY_HURTBOX, PLAYER_HITBOX, ENEMY_HITBOX,
PROJECTILE, PICKUP, INTERACTABLE, TRAP, PIT, PROP`. `Layers.Team {PLAYER, ENEMY, NEUTRAL}`.
Helpers `hurtbox_layer_for(team)`, `hitbox_mask_for(team)`.

### Damage — `DamageInfo`
`DamageInfo.create(amount, tags, source, team)`, `.with_knockback(dir, strength)`,
`.with_status(StatusEffect)`. Tags: `melee ranged ability physical fire frost shock poison
arcane trap true`. `applied` is filled by `Health`.

### Stats — `Stats` (RefCounted, on every Entity as `entity.stats`)
Primaries `vitality might precision arcana swiftness fortune` (ints via `add_primary`).
Secondaries computed from primaries (docs §4.2 table) plus layered modifiers:
`add_flat(stat, owner_id, v)`, `add_percent(stat, owner_id, v)`, `remove_owner(owner_id)`.
Read with `get_value(stat)`. Owner ids: `item:<uid>`, `passive:<id>`, `class:<id>`, `buff:<id>`.
Always tag modifiers so they can be removed.

### Health / Hurtbox / Hitbox
`Entity` auto-creates `Health`, `StatusController`, `Hurtbox` children if missing.
A `Hitbox` (Area2D) dealing damage: set `team`, `damage`, `tags`, `knockback`, then
`activate(duration)`; or set `damage_builder` to a `Callable(target) -> DamageInfo`
(use `entity.make_damage(base, tags, dir, kb, rng)` to get stats/crit applied).
Hitboxes only collide with the *other* team's hurtboxes + `PROP` bodies exposing `take_hit(info)`.

**The deferral rule.** Damage is applied synchronously inside `area_entered`, which the physics
server emits while it is flushing its queries, and it refuses collider state changes there
(`monitoring`, `monitorable`, `collision_layer`, `CollisionShape2D.shape`). So **anything reached
from a hit that adds a node with a collision shape to the tree must defer the insertion** — a
pickup, a dropped item, a hazard, an on-death split or shrapnel burst. `Hitbox` marks that window
(`PhysicsFlush.enter/exit` around its signal callbacks) and the insertion points read it:
`PhysicsFlush.add_child_at(parent, node, pos)` defers inside a flush and inserts immediately
outside one, so a caller reading the node straight back still can. Use it —
`EnemyBase.spawn_sibling`, `EnemySpawner.spawn_group` and `EnemyAttack.make_hitbox` all do; so do
`PickupSpawner._place` and `ItemPickup.drop` with their own `call_deferred`. Do **not** reach for
`Engine.is_in_physics_frame()`: it is also true in `_physics_process`, where the insertion is
legal. `tests/unit/tools/physics_deferral_test.gd` kills enemies through a real overlap and is
what catches a new violation.

### Status — `StatusEffect` (Resource) + `StatusController`
`StatusEffect.make(kind, duration, magnitude, source)`; kinds `BURN FROST SHOCK POISON STUN
TAUNT SLOW HASTE WEAKEN EMPOWER`. Controller ticks DoTs every 0.5 s, 3 frost stacks → freeze.

### Entity — `Entity` (CharacterBody2D)
Fields: `team, health, stats, status, hurtbox, knockback_velocity, facing`. Use
`move_with_knockback(delta)` after setting `velocity`. `can_act()`, `effective_speed()`,
`make_damage(...)`. Override `_die(killer)` for death FX (default `queue_free`).
Signals: `hit_received(info)`, `died(killer)`.

### Abilities
`Ability` (Resource: id, display_name, description, kind, icon, max_tier, class_only, weight, tier).
`ActiveAbility`: `cooldown, damage, tags, cooldown_left`; implement `_activate(player, aim) -> bool`;
call `tick(delta)` each frame; `try_activate(player, aim, free_cast)`.
`PassiveAbility`: `apply(player)/remove(player)` register stats under `owner_id()`; hooks
`on_hit_dealt, on_hit_received, on_kill, on_dodge, on_room_cleared, on_active_used,
outgoing_damage_multiplier`. Concrete abilities: `src/abilities/actives/<id>.gd` +
`data/abilities/<id>.tres`.

### Items
`ItemBase` (slot, implicit stats, weight, min_floor), `WeaponBase` (style, base_damage,
attacks_per_second, range_px, knockback, tags, projectile_scene, combo_length, skill),
`Affix` (stat, mode FLAT/PERCENT/ON_HIT_STATUS, ranges, prefix/suffix, slots, weight, min_rarity),
`ItemInstance` (base, rarity, affixes[{affix,value}], display_name, unique_effect; `apply_to(stats)`,
`remove_from(stats)`, `to_dict()`).

### Enemies — `EnemyDef`
Numbers + `scene` per enemy; `scaled_hp(floor)`, `scaled_damage(floor)`; `faction`, `cost`,
`is_elite`, `is_boss`, floor range, gold range, weight.

### Generation — `FloorData`
`Tile {VOID FLOOR WALL DOOR PIT CORRIDOR}`, `RoomType {START COMBAT ELITE TRAP TREASURE ALTAR
SHOP SHRINE STAIRS BOSS}`, `Room {id, type, rect, neighbors, doors, enemy_spawns, prop_positions,
trap_positions, fill_template, palette_variant, graph_distance}`, `Corridor {from_room, to_room, path}`.
Grid helpers `get_tile/set_tile/is_walkable`, `layout_hash()`, `to_ascii()`.

### RNG — `RunRng`
`RunRng.new(seed).stream(&"gen"|&"loot"|&"combat"|&"ai")`, `floor_stream(&"gen", floor_index)`.

The rule at the top of this file — never global `randf()`, take a stream — held everywhere but
one line, and that line was `PickupBase._bob_phase`. A coin's bob was drawn from the global RNG
in `_ready`, which meant a resumed floor drew its coins at a different phase from the session
that dropped them, no capture of loose loot could be compared pixel for pixel, and
`pickup_frame` was quietly flaky: a frozen coin sat anywhere in a one-pixel band, so its rim
landed on a different tile rung from run to run and one kind read 4.31:1 on one pass and 2.42:1
on the next. `PickupSpawner` now seeds its own stream from `(run_seed, floor_index)` rather than
`randomize()`, and hands the phase out of it (`set_bob_phase`), so a drop is the same drop every
time a run and floor are replayed. `tests/unit/enemies/pickups_test.gd` holds that, and there is
no global `randf()` left under `src/`.

### Desktop — `Desktop.palette.get_color(&"floor"|...)` roles listed in `ThemePalette.ROLES`.
Anything that shows theme colours must connect to `EventBus.palette_changed` and retint
(crossfade ~0.6 s via a Tween on shader `blend` or modulate).

### Lighting — `LightRig`, `LightEmitter` (docs 10 "Lighting")
Every built `FloorRoot` carries a `LightRig` child named `Lighting` (`LightRig.of(root)`, or
`LightRig.current()` for the live floor). It owns the darkness (two flat `PointLight2D`s the size of the
floor in MIX toward black - the mix amount is the texture's alpha - the environment's on
`ENV_MASK`, a lighter one for bodies on `PROP_MASK`; nothing reaches `TELL_MASK`, so a tell is
exempt by `light_mask`, never by material: the compatibility renderer's CanvasModulate reaches
unshaded items too, and its DirectionalLight2D lights nothing. `LightRig.loot_mask()` says
which of the two loot draws itself with - the exemption on a dark theme, the surface's own
mask on a light one), one `WallLantern` per generator anchor (a sprite and a single pool light
on `LIT_MASK`: a pool is never split by the masks, so a lantern lifts the floor and the bodies
standing in it by the same energy, exactly as a door torch does), the merged `WallOccluders`
rectangles, the shade over unexplored rooms, the
shadow blobs and the emitter pool, and it is freed with the floor. Gameplay never touches
it directly: `LightEmitter.attach(host, &"fire")` follows a Node2D until it hides or leaves the
tree, `LightEmitter.flash(&"explosion", pos)` is a one-shot bloom, and both return null when
the layer is off (`lighting_quality` = 0), the pool is capped or there is no floor - so a call
site needs no guard. Kinds are rows of `LightingProfile.emitters` (role, energy, radius, fade,
shadow); a kind the table does not name is a plain accent glow, and
`tests/unit/rooms/lighting_emitter_test.gd` pins every kind the code asks for against the table.
Colours are never authored: `rig.light_color_for(role)` is the lit palette's role made a light
and graded by the mood (`heat` is exactly `DungeonLight.torch_color(palette)`), so every light
retints on `palette_changed`. The darkness reads `DungeonLight.ambient_energy()` /
`ambient_color()`, every light's energy `DungeonLight.torch_energy_scale()`; nothing in
`src/rooms/lighting` reaches into `src/music`. Shadows: the nearest `shadow_casters` (8) lights
to the camera cast, re-chosen every 0.1 s; a light inside a wall core is never a caster.

Four contracts cross a module line, and each is one call:

* **gen** hands the layer `FloorData.lantern_anchors` (`LanternAnchors`); `LightRig.anchors_for`
  runs the same rule itself only when that list is empty, so a restored floor hangs the lanterns
  it was generated with. Nothing in `src/rooms/lighting` writes to `src/gen`.
* **music** hands it the live light contract on `DungeonLight` - `ambient_color()`,
  `ambient_energy()`, `torch_color(palette)`, `torch_energy_scale()` - already crossfaded, and
  the rig slews the darkness again behind that. There is no beat path and no periodic term
  anywhere in the layer.
* **props** own the readable ladder, which is guaranteed against the floor *as drawn*
  (`Prop.readable_colors`, `Prop.bloom_for`). The layer's whole obligation to them is that no
  light move a body and the floor under it apart: `LightRig.mask_body` puts a body's sprites on
  `PROP_MASK` and its tells on `TELL_MASK`, and every pool is one light on `LIT_MASK`.
  `prop_frame` is where that obligation is checked, on pixels.
* **UI** owns the tells. Damage numbers, health bars, alert marks, telegraphs and the player
  marker draw on `TELL_MASK` and are never dimmed; the HUD is a CanvasLayer and out of reach
  entirely. The two quality settings are `SettingsRows`' *Lighting* and *Shadows* under Video,
  and a change to either rebuilds the rig through `EventBus.settings_changed`.

### Ask the compositor what the engine cannot see — `CompositorWindow`

**On Wayland the engine cannot tell a fullscreen window from a tiled one.** Measured in the
Omarchy VM (Hyprland 0.56.2, Godot's Wayland backend): tiled at 1896×1030 and then fullscreen at
1920×1080, `Window.mode` and `DisplayServer.window_get_mode()` are both `MODE_MAXIMIZED` in
*both* states, and every position and size call returns the same numbers in both. The backend
never reports the compositor's configure back to the window, so there is no rectangle to compare
and no mode to read.

The compositor knows. `hyprctl clients -j` lists every window with the **pid** that owns it and
its fullscreen mode; sway answers the same through `swaymsg -t get_tree`. `CompositorWindow`
runs whichever of those the session is using, off the main thread, once per
`data/desktop/compositor.tres` `poll_seconds`, and matches on `OS.get_process_id()` so the answer
is about *this* window rather than whatever happens to be focused. Its `State` has three values,
and `UNKNOWN` — no compositor, no matching window, a query that failed — is a real answer that
callers fall back to the engine on. It is off under a test run, so no gate depends on the
developer's desktop and no capture depends on the harness's nested sway.

This is the pattern for anything else the engine cannot see on a desktop it is a guest of: ask
the desktop, off the main thread, identify yourself by pid, and degrade to the engine's own
answer rather than to a guess.

### Controller navigation — `UiFocusChain`, `UiStickNav`, `UiListReveal`

**A scrolled list needs an explicit focus chain.** Godot falls back to a *geometric* neighbour
search only when `focus_neighbor_*` is empty, and that search **refuses a control its container
has clipped** — which is every row below the fold of a `ScrollContainer`. So a pad walking a
scrolled list stops at the last row that happens to fit: `ui_down` finds no neighbour, focus
never moves, and the list never scrolls, because nothing scrolls a list until focus has moved
into it. `ScrollContainer.follow_focus` does not fix this — it only reacts *after* focus has
moved — and thirteen rebind rows in two columns were unreachable on a pad for exactly this
reason. An **explicit** neighbour is checked for visibility and focus mode and nothing else, so a
wired chain walks into the clipped part of the list and the list scrolls afterwards. That is the
order a scrolled list has to work in. Build the chain with `UiFocusChain`
(`begin_row()`/`add()`/`wire(above, below)`, rebuilt whenever the list is), give it explicit
exits at both ends so the bottom of a list is never a cul-de-sac, and scroll with
`UiListReveal.reveal()` rather than `follow_focus`, which stops flush against the viewport edge
and slices the section heading above the focused row in half.

The left stick is not bound to `ui_*` directly: `InputEventJoypadMotion.action_match()` has no
edge detection and reports "pressed" for every motion event past the deadzone, so one physical
flick arrived as three or four presses. `UiStickNav` (owned by the `UiNav` autoload) turns the
axis into discrete presses with push/release hysteresis and auto-repeat; a board calls
`UiStickNav.serve(self)` in `_ready()` and is dropped again automatically when it leaves the
tree. Every timing — thresholds, repeat,
`capture_hold_seconds` (how long B must be *held* in the rebind capture before it binds itself
instead of backing out, so B stays bindable and a tap still leaves the screen) and
`notice_seconds` — lives in `data/ui/nav.tres` (`UiNavProfile`), not in a literal. Rebinding goes
through `InputBindings`, never `InputMap` directly, so the live map and
`GameState.settings["bindings"]` stay in step.

**A prompt is `UiPrompt` markup, never a sentence with a button's name in it.** Every hint
line, footer and capture prompt is a `UiPrompt` (`HFlowContainer` of words and `GlyphIcon`s)
fed markup that names the *action* - `"{ui_accept} pick   {ui_cancel} skip"` - and draws the
glyph for it on the device in the player's hands: the sprite from `glyphs.png` on a pad, a
labelled key-cap on a keyboard. `{ui_cancel@pad}` pins a token to one device for a line that
talks about the other one, `{#dpad}` draws a sheet cell that is not an action, `{=Start}` a
key-cap with a literal label, and `InputGlyphs.event_token()` turns a live pad event into one.
Tests read `plain()` ("A pick   B skip"). Before this every board typed "A pick   B skip"
while the HUD beside it drew the sprite, which is the "shows A B instead of the pad symbols"
the owner saw; `tests/unit/ui/prompt_glyphs_test.gd` scans `src/ui` so it cannot come back.

**Which device is live is decided in one place**, `InputGlyphs.observe`, and `PlayerInput`
follows it rather than deciding for itself. A pad button or a stick past
`PAD_MOTION_THRESHOLD` makes the pad live; a key or a mouse *click* makes the keyboard live
at once; mouse *motion* does so only after the pad has been quiet for
`UiNavProfile.mouse_grace_seconds` (1 s), because a nudged mouse or a cursor warp is a motion
event too, and each one used to flip every prompt to key-caps for a frame.

### Props and hazards are guaranteed *as drawn*

`Prop.readable_colors()` / `accent_colors()` push a room's tile colours off its own floor so
nothing the player must see or avoid is painted the same as the tile behind it. The guarantee is
made on the **drawn** pixel: a torch is an additive `PointLight2D`, and an additive light lands
the same value on the prop and on the floor beside it, which pulls every ratio toward 1 and clips
the brightest rungs into one another. A ladder built on the authored colours therefore measured
2.2 in memory and 1.87 in a frame. Every placement is now judged in both readings of the room —
unlit, and with `Prop.bloom_for()` of one torch on top — and the interior ladder is spread in
drawn luminance. See `Prop` in `MODULE_APIS.md` for the numbers, and
`tests/unit/rooms/prop_frame_capture.tscn` for the check that reads them back out of a rendered
PNG: one frame per `Biome.ALL_IDS` entry, every kind `Prop.kind_names()` gives it, 45 props a run.

Two things that check taught the model, both of them invisible to it. A **light theme's floor is
clipped at white**, so a torch raises the prop alone and the ratio closes from one side where a
dark theme's light lifts both together — which is why the anchor rung is placed with
`ANCHOR_CLEARANCE_MARGIN` of headroom on a descending body and exactly on its target on a rising
one. And the **interior ladder still collapses** at the top of the ramp for a prop standing in
+0.11 to +0.13 of light on a dark theme, inside the band `BLOOM_MAX` says it is guaranteed
across; that one is open, and `TESTING.md` lists the eight props it happens to.

### Props are solid or flat, and the sprite says which

The other half of readable clutter is *what happens when you walk at it*, and until the third
report it was decided by nothing a player could see. Now every kind is one of two things
(`Prop.SOLID`, `prop_solid` in `data/rooms/rooms_content.tres`, `Prop.is_solid()`): an
**upright** object wears an ink outline, stands on a baked contact shadow, sits on `Layers.PROP`,
blocks and breaks into a debris frame; a **flat** one (bones, rubble, a snowdrift) lies low with
no ink and no shadow, is on no collision layer at all and is never hit. The rule is authored once in the art generator
(`tools/art/props.py::SOLID`), which refuses a drawing that contradicts it, and
`tests/unit/rooms/prop_test.gd` reads the shipped PNG back against the code and the data and
pushes a `CharacterBody2D` at both kinds. `FloorRoot` carves only solid props out of the nav
polygon; the generator's reachability check (`FloorValidator`) still treats every prop as
blocking, which is conservative in the safe direction. See "Solid or flat" in
`assets/tiles/README.md`.

The catalogue itself is nine kinds a biome (`Prop.KIND_COUNT`: four shared, five of the biome's own), every one a hand-drawn pixel map in `tools/art/prop_maps.py` with a silhouette of its own; the fourth pass cut the five kinds that read as another kind's texture (cobweb, furnace, ice patch, pages, glitch) and redrew cart, desk, floater and bones. A solid prop also carries a `LightOccluder2D` child (`Prop.OCCLUDER`, polygon from `Prop.base_rect()`: the bottom six rows of the sprite's opaque box) so the floor's lighting can throw its shadow, hidden the moment it breaks; a flat prop has neither an occluder nor a live collision shape. `PropPlacement.place` resolves `RoomsContent` once per room - resolving it per lookup was ~30x the fill time.

## 5. Scene flow (RunManager, M1)

```
Title (src/ui/title.tscn) → ClassSelect → Game (src/game.tscn)
Game: [FloorRoot] [Player] [Camera] [HUD CanvasLayer] [Overlay CanvasLayer: chest/pause/toasts]
RunManager (autoload): new_run(seed, class) → build_floor(i) → on stairs → build_floor(i+1)
                       → on player_died / final boss → RunSummary → Title
```
Rooms lock on entry when enemies alive (`EventBus.room_locked`), unlock and spawn a chest on
`room_cleared`. Enemies register themselves via `EventBus.enemy_spawned/enemy_died`.

## 6. Adding content (checklists)

**New enemy**: `data/enemies/<id>.tres` (EnemyDef) + `src/entities/enemies/<faction>/<id>.gd`
extending `EnemyBase` + scene `<id>.tscn` + sprite in `assets/sprites/enemies/<id>.png` + a unit
test that instantiates it headless and checks def numbers → registered in
`data/enemies/registry.tres` (EnemyRegistry).

**New ability**: script in `src/abilities/actives|passives/<id>.gd` extending the base,
`data/abilities/<id>.tres`, added to `data/abilities/registry.tres`, test in
`tests/unit/abilities/<id>_test.gd` exercising the effect on a dummy `Entity`.

**New affix / item base**: `.tres` in `data/affixes` / `data/items`, registry entry, generator test
asserts it can roll and its name fragments compose.

**New trap**: `src/traps/<id>.gd` extending `TrapBase`, scene, registered in `TrapRegistry`.

**New UI screen**: `UiTheme.apply(self)` so it retints with the palette; `UiStickNav.serve(self)`
in `_ready()`; its hint line a `UiPrompt` fed `{action}` markup (§4), never a Label naming a
button; every animation length through
`Accessibility.motion()` and every flash through `Accessibility.flash()`; timings from
`data/ui/nav.tres`, not literals. **If its content scrolls, build a `UiFocusChain` and `wire()`
it** (§4) — the geometric focus search cannot reach a clipped row, so without one the pad stops
at the fold. Add the screen to `UiGallery.SCREENS` with a deterministic `UiFakes` fixture and
capture it with `tools/ui-gallery.sh --only <screen>` in a dark *and* a light theme; a screen
that pins the active device to the gamepad goes at the **end** of `SCREENS`, with the ones
already there, because that flag lives on the SceneTree for the rest of the process. Any line the
screen can print has to fit the narrowest panel that screen is ever drawn in — `SettingsPanel`
has 44 px more line standalone than it has inside the pause menu, and that is where its
Keyboard-column notice ran off both ends.

## 7. Testing layers
1. `tools/test.sh` — gdUnit4 unit/integration (headless). Required green before commit.
   `tools/test.sh -c -a res://tests/unit/<dir>` runs one subtree; with no `-a` the whole
   `res://tests` tree runs. Prefix with `OMADUNGEON_TEST_COPY=1` when others may be testing.
   Every run gets its own `user://` (`$XDG_DATA_HOME`), and outside copy mode its own
   `reports/run-<pid>/`, so two runs at once share neither save files nor report numbering.
   The case count and the failure dump come from the report the run *just wrote*, resolved
   numerically (`report_<n>`, newest wins; `sorted()` would pick `report_9` over `report_22`)
   and rejected if it is older than the run. "No report newer than this run" is what "the run
   produced nothing" looks like, and it exits 5.
2. `tools/run-scenario.sh <scenario> [theme]` — nested headless sway, `--test-scenario` drives the
   game (see `src/core/test_scenarios.gd`), screenshots to `tests/out/`. The default theme keeps
   the bare `<scenario>.png` name; any other fixture gets `<scenario>_<theme>.png`, so a second
   theme never overwrites the first. `theme_swap` and `theme_swap_midfight` refuse a theme
   argument (exit 4): they pin their own `tokyo-night` → `white` pair in `test_scenarios.gd`,
   so a theme in the filename would be a claim the picture does not support.
   `SCENARIO_TIMEOUT` (default 240 s) is a hard deadline on the
   whole capture, KILL included, so a startup hang fails instead of stalling the caller. The
   compositor log stays in the throwaway runtime dir and is copied to
   `tests/out/sway-failed-<pid>.log` when sway fails to start or when that deadline fires.
3. Capture scenes — a main scene rather than a gdUnit suite, when a question can only be
   answered by a rendered frame. `tools/capture-scene.sh <id> [theme]` is the harness for all
   six (`prop_frame`, `pickup_frame`, `lighting_frame`, `feel_tell`, `ui_stats`, `ui_trade`),
   with the same guards as (2) and the
   scene's own exit code passed through; before this round there was no harness at all and the
   only way to run one was to retype a `headless-sway.sh godot ...` line out of its doc comment,
   which is how `prop_frame_capture` came to be failing under a green gate for five rounds.
   `tests/unit/feel/tell_capture.tscn` -> `tests/out/feel_tell[_<theme>].png` (the danger tell at
   1:1) and
   `tests/unit/rooms/prop_frame_capture.tscn` -> `tests/out/prop_frame_<biome>[_<theme>].png`,
   which *measures* the PNGs it just wrote (every prop's rungs against the floor pixels beside
   it, in all five biomes) and exits non-zero when a frame is under target, so the numbers cannot
   rot unlooked-at. It pins the torch flicker and polls until the viewport draws the same frame
   twice first: a settle counted in seconds photographed a different light level every run.
4. `tools/ui-gallery.sh [theme]` — the same harness over the UI screens, `tests/out/ui_*.png`,
   with (2)'s naming rule: bare `ui_<screen>.png` for `tokyo-night`, `ui_<screen>_<theme>.png`
   otherwise. Same three guards as (2): the expected PNGs are deleted first and must exist,
   non-empty and newer than the
   run, afterwards (exit 2 otherwise); the nested compositor runs under the same
   `tests/out/.scenario.lock`; the copy goes to `$OMADUNGEON_COPY_DIR`/`$TMPDIR`/`/var/tmp`.
5. `tools/vm/` — real Omarchy VM (later).
6. `tools/run-checks.sh <tier>` — runs a whole tier of `tools/checks.json`, records what
   happened in `reports/checks/<id>.json`, and is what `.github/workflows/ci.yml` calls.
   `tools/run-checks.sh list` prints the register (the status column is read out of the ledger),
   `results` prints the ledger, `verify` exits 1 naming every check with no usable result. A
   check that CI cannot run must say so in `why_manual`. **Nothing declares its own status**:
   the tier-1 gate fails when a check the register says CI runs has no record, a record older
   than `policy.result_max_age_hours`, or one with a non-zero exit. The register describes
   checks; the ledger says how they went.
