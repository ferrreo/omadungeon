# Omadungeon — Game Design Document

Status: v0.1 draft (design only, no code yet)
Target: Godot 4.7 (GDScript), Linux / Omarchy native only

---

## 1. Vision

Omadungeon is a fast, room-based, procedural rogue-like dungeon crawler in the mould of
*Tiny Rogues*: short runs (20–35 min), top-down 2D pixel art, rooms that lock until
cleared, a chest after every clear, a build that snowballs from stats, loot and a small
set of chosen abilities. Death is permanent per run; meta-progression is unlocks only,
never power.

The twist: the game is *skinned by your desktop*. It reads the currently selected
Omarchy theme (and, optionally, the wallpaper) and derives its palette, lighting,
floor/wall tile flavour, and even level-generation parameters from it. Switch theme
and the dungeon retints in front of you; the next floor generates differently. Enemies are the people who hate your
setup: clowns, greybeards, and assorted config-tinkerers.

Pillars:

1. **Readable chaos.** Dense fights, but everything on screen is legible at a glance.
   Pixel art at 1x internal resolution, few colours, strong silhouettes.
2. **Build every run.** Class + 2 passives + 2 actives + procedural gear + stat drops.
   No two runs play the same.
3. **Your desktop is the dungeon.** Theme-driven look and gen. Deterministic per theme
   so a theme always "feels" the same, but seeds still vary.
4. **Native, not ported.** Wayland-first, controller and KB+M first-class, no Windows /
   macOS export ever. XDG paths, no telemetry.

Non-goals (v1): multiplayer, mod support, procedural music, story/cutscenes,
mid-fight save state (quit is resumable at room granularity, see §12).

---

## 2. Core Loop

```
Title ─► Pick class ─► Pick 1 starting passive ─► Floor 1
   │
   ▼  per floor (repeat ×N)
   Enter room ─► Doors lock ─► Fight (avoid traps) ─► Room clear
      ─► Chest spawns (stat / item / ability choice) ─► Explore ─► Find stairs
      ─► Boss floor every 3rd ─► Next floor (biome shift)
   │
   ▼
   Death or Final boss ─► Run summary ─► Unlocks ─► Title
```

Run length: 9 floors (3 biomes × 3 floors, boss on 3/6/9). Floors grow from ~7 rooms
to ~13 rooms. Target total run time 20–35 min.

---

## 3. Desktop Integration (Omarchy theme, wallpaper, live changes)

### 3.1 Omarchy: what is guaranteed

Verified against upstream `basecamp/omarchy` (all 22 shipped themes, Sept 2026):

| Path | Guaranteed | Purpose |
|------|-----------|---------|
| `~/.local/state/omarchy/current/theme` | symlink → theme dir | Active theme |
| `~/.local/state/omarchy/current/theme.name` | file | Display name ("Tokyo Night") |
| `~/.local/state/omarchy/current/background` | symlink → media file | Active wallpaper (image **or video**) |
| `<theme>/colors.toml` | **every theme** | Semantic palette (below) |
| `<theme>/backgrounds/` | every theme | Wallpaper pool |
| `<theme>/icons.theme`, `preview.png` | every theme | Not used |
| `<theme>/light.mode` | legacy, optional | Mode hint (handled by resolver) |

Per-app files (`alacritty.toml`, `hyprland.lua`, `neovim.lua`, `waybar.css`…) are
generated from `colors.toml` by templates at theme-set time and are **not** shipped by
every theme, so the game never reads them. `colors.toml` is the single source.

**Palette resolution** mirrors `bin/omarchy-theme-color` exactly (so we agree with
every other Omarchy consumer). Keys and the fallback cascade the game implements:

```
mode                 = mode | theme_type | light.mode file | bg luminance > 382/765 → light | dark
accent, selection, muted
background, dark_background, darker_background, lighter_background
foreground, dark_foreground, light_foreground, bright_foreground
red yellow orange green cyan blue magenta brown
bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta
legacy: color0..color15 aliases (red←color1 … bright_cyan←color14), purple→magenta,
        orange←yellow, brown←mix(orange, black, 50%), muted←color8, …
```

Resolution order: `OMADUNGEON_OMARCHY_STATE_DIR` env override → `~/.local/state/omarchy`
→ built-in fallback (a vendored copy of upstream `tokyo-night/colors.toml` plus
`catppuccin-latte` for light-mode tests). The game runs fully without Omarchy and
logs one info line. If `omarchy-theme-color --all` is on `$PATH`, its output is used
as a cross-check in debug builds only (tests assert our resolver equals it).

### 3.2 Palette mapping (environment only, see §10)

`colors.toml` → `ThemePalette` roles:

| Role | Source key | Used for |
|------|-----------|----------|
| `void` | `darker_background` | Out-of-bounds, pits (exposed, see below) |
| `floor` | `background` | Floor base (exposed, see below) |
| `floor_alt` | `lighter_background` | Floor variation tiles |
| `wall` | `dark_background` | Wall body |
| `wall_top` | `muted` | Wall caps / edges |
| `prop_a` / `prop_b` | rolled per room from `red…brown` set | Props, banners, liquids |
| `text` | `foreground` | UI text |
| `text_dim` | `dark_foreground` | UI secondary |
| `text_bright` | `bright_foreground` | Titles, highlights |
| `accent` | `accent` | UI focus, doors, player cloak trim |
| `select` | `selection` | UI selected card |
| `danger` | `red` / `bright_red` | Enemy tells, traps armed, low HP |
| `heal` | `green` | Potions |
| `loot` | `yellow` | Chests, gold |
| `magic` | `magenta` | Altars, arcane props |
| `cold` | `cyan` | Frost biome, ice |
| `heat` | `orange` | Forge biome, lava |
| `earth` | `brown` | Library/crypt props |
| `rarity[]` | `blue`, `magenta`, `yellow`, `bright_red` | Common/Rare/Epic/Legendary outlines |

**The exposure model.** The environment roles above name where a colour *comes from*,
not what is drawn. A theme background is authored to sit behind terminal text, so on
every dark theme shipped it is near black (L = 0.012 - 0.034) and its three background
keys sit inside 1.4:1 of each other - painted raw, floor, wall and surround render as
one value and the room loses its outline. `ThemePalette.light_environment(ambient)` is
therefore applied before anything is tinted:

- the **floor** is re-exposed into a luminance band (`LIT_FLOOR_LUMINANCE_MIN` ..
  `LIT_FLOOR_LUMINANCE_MAX`). Where it lands inside that band is the *theme's* own
  business - `theme_light_position()` reads its background luminance - so a theme
  authored lighter than another gets the lighter dungeon. The band guarantees a
  minimum; it does not dictate a value, because an exposure that pins every dark theme
  to one number renders the same dungeon for all of them;
- every **other environment role** is placed relative to that floor by *contrast ratio*
  (the ladder in `LIT_LADDER_*`), so the relationships between floor, wall, wall cap,
  floor detail and surround do not change with the light level - only the whole room
  gets darker or lighter;
- the **surround** is never taken below `LIT_SURROUND_LUMINANCE_MIN`. It is the largest
  region on screen, and at black it stops carrying the theme's hue at all;
- the wallpaper's `ambient` (§3.4) scales the theme's exposure between
  `LIT_AMBIENT_DIM` and 1.0. It is a lever *on* the theme's light level, not a
  replacement for it.

**The room's cast.** The exposure model above moves luminance and nothing else, so a theme
whose three background keys are grey *by authorship* gets a grey dungeon however well it is
lit. Three of the six shipped fixtures are that theme, and captures of floor 1 measured them at
1–6% mean screen saturation against 25–29% for the vivid ones — while the accent roles (props,
torches, liquids, doors) cover about 2% of the screen on *every* theme, so there was nothing
left to carry the room and it read as a white-tiled bathroom.
`ThemePalette.apply_room_cast()` therefore hands the room the theme's own colour, inside the
lighting model and before the contrast guard:

- the **hue** is the theme's own environment cast wherever it has one, however faint:
  catppuccin-latte authors a blue-grey paper at 4% saturation and a blue-grey dungeon is what
  that theme looks like, and gruvbox — whose `background` is a pure `#282828` — still carries a
  warm grey in `muted`, so its crypt comes out as warm sandstone rather than as some invented
  colour. A surface with a hue of its own keeps it (`ROOM_CAST_OWN_CHROMA_MIN`, measured as
  absolute chroma on the colour the theme authored, not as HSV saturation on the exposed
  one — a near-black `#0F0F0D` reports 13% saturation from two 8-bit steps, and the
  exposure turns that rounding error into a visible floor); only a theme with
  no chroma in any of the five surfaces falls back to the tell colours (`red…magenta`), on the
  grounds that a theme keeping all of its colour in its accents is still that colour;
- the **strength** scales with the chroma the desktop actually contains
  (`ROOM_CAST_SOURCE_FULL`), so a greyscale theme — `white` is one, and it is a legitimate
  Omarchy theme — keeps a greyscale dungeon instead of being handed a hue it does not own;
- the four **room surfaces** (floor, floor detail, wall, wall cap) are lifted to
  `ROOM_CAST_SATURATION` (0.26) only where the theme authored them grey, and a theme already
  at `ROOM_CAST_ENV_FULL` keeps its own chroma untouched. That ceiling is not taste: the prop
  ladder (`Prop.accent_colors`) re-hues a prop's body at the room's own saturation and places
  it under the room's light, and measured with the room lifted to 0.34–0.50 the interior steps
  it guarantees fall to 1.07–1.11 against its 1.12, in a pattern that is not monotonic in
  saturation. Until that ladder is re-spread after the re-hue, the room's own chroma is where
  it was;
- the **surround** is lifted to `SURROUND_CAST_SATURATION` (0.50) on every theme with chroma.
  It is the largest region on screen and nothing the readability model measures a prop
  against, so it is where the theme's colour is loud: navy on tokyo-night, slate on nord,
  mauve on catppuccin, a warm brown on gruvbox, and never below `LIT_SURROUND_LUMINANCE_MIN`
  (0.02 — 0.012 was above black by the numbers and black to the eye);
- nothing outside the theme touches a hue here. The wallpaper used to turn every surface a
  third of the arc toward its own dominant colour; the owner removed that (§16, "The theme is
  the colours"), so the only colours in this model are the ones the desktop palette contains;
- and every surface keeps its **luminance exactly**, so the ladder, the room's outline and
  every guarantee above are the ones the exposure computed. The cast changes what colour a
  surface is, never how light it is — which is why it cannot buy identity with readability.

The theme's chroma is also pushed through the two things the room is *lit* by, which no
ladder reads: the torches burn in `heat` turned `DungeonLight.torch_accent_mix` (0.35) of the
way toward the theme's `accent` (§10), so the pools of light are pink on tokyo-night, amber on
gruvbox and straw on nord rather than one orange everywhere; and the prop accent rungs are
lifted to `TileRamp.ACCENT_SATURATION` (0.62) and rolled with a bias toward the pool's most
saturated entries (`ACCENT_CHROMA_BIAS`), so the urns and banners are the theme's brightest
colour first.

A light theme's paper floor is close enough to white that no colour of that luminance can be
very saturated (about 0.06 for a blue at L = 0.87). There the cast lands on the walls, the
caps and the surround, and the floor takes what physics leaves it. That is a property of
near-white surfaces, not a tuning choice.

Re-exposure means scaling the linear channels, so hue and chroma survive: the colour is
lit differently, never tinted. The same applies to props (`Prop.ensure_visible`) and to
the accent rungs of the tile ramp - a rung lerped toward white to make it legible comes
out grey, which is a dungeon with no theme in it.

`mode == light` flips the lighting model: floors bright, walls darker than floor,
ambient 1.0, enemy outlines darkened. Contrast guard: any UI text/bg or danger/floor
pair below 4.5:1 is pushed toward `bright_foreground`/`darker_background` until it
passes.

The guard is measured against *every* surface a role can land on, not just the floor:
`floor` (panels and the dungeon floor), `floor_alt` (cards, buttons) and `void` (the HUD
plate). `wall`/`wall_top` are deliberately excluded, because they cannot be satisfied at the
same time as the floor - a light theme's floor is near-white and its walls a mid grey, so the
ink that clears 4.5:1 on the paper is at best 3:1 on the wall. HUD text is therefore never
left floating over the level: the resource block (HP, potion, gold, statuses) and the
floor/seed block sit on an **opaque** `void` plate, so what is behind the text is a palette
role the guard can reach rather than whichever tile the camera happens to be over. A
translucent plate does not count - it composites with the dungeon and stops being `void`.

### 3.3 Theme → generation parameters

A stable hash of `theme.name` plus derived colour statistics seeds a `ThemeProfile`
that biases (not dictates) generation. Derived scalars:

| Parameter | Derived from | Range |
|-----------|-------------|-------|
| `hue_dominant` | Mean hue of `red…magenta` | 0–360 |
| `saturation` | Mean saturation of same | 0–1 |
| `env_chroma` | Mean saturation of the five environment surfaces | 0–1 |
| `warmth` | (red+orange+yellow) vs (blue+cyan) weight | −1..1 |
| `brightness` | `mode` | 0/1 |
| `corridor_wiggle` | `saturation` + `env_chroma` | 0.10 straight halls ↔ 0.90 winding, and through it 1–3 loops |
| `openness` | `hue_dominant` + `warmth` | Tight ↔ open floor plans |
| `room_size_bias` | `brightness` + `openness` | **Signed**, −0.25..0.5: a warm, tight theme pulls rooms *under* the default sizes, a cool or light one pushes them over |
| `trap_density` | `1 − saturation` | Muted → more traps (the one difficulty lever, ±10%) |
| `hazard_weights` | `warmth` | Which *kinds* of trap a floor lays, never how many: warm favours fire vents and spikes, cold ice and pits, neutral plates, arrows and lasers (`HAZARD_TILT`) |
| `prop_density` | `saturation` | Vivid → more clutter, above a floor (see below) |
| `biome_order` | `warmth` | Warm: Crypt→Forge→Void; Cold: Crypt→Frost→Void; Neutral: Crypt→Library→Void |
| `enemy_faction_weight` | `hue_dominant` band | The favoured faction at `FACTION_FAVOURED` (2.0) — half of every pack; see §7 |

Biases are clamped so any theme stays fun; theme never changes difficulty beyond
±10% trap density. No geometry lever may be derived from `saturation` alone: several
shipped themes agree on it to two decimal places, and when every lever hung off it they
generated bit-identical floor plans. `corridor_wiggle` was the last lever that still was,
which is why it now reads `env_chroma` as well — how much colour a desktop paints its own
*backgrounds* in is independent of its accents by construction (gruvbox authors vivid accents
over a pure grey background, nord calmer ones over a blue-grey one). On top of the biases the
theme hash is folded into the layout seed (`FloorGenerator.layout_seed`), so the §5.1 promise
holds even for two themes whose derived scalars happen to coincide — and that is not a
formality: with the theme identity neutralised, two such themes do land on one floor plan on
individual floors. Boss floors take the same levers as every other floor; they used to pin
`extra_loops` to 1 for every theme, which took the desktop off floors 3, 6 and 9 entirely
(see `GenParams.BOSS_LOOP_SCALE`). Profile is captured **at floor generation**; a mid-floor
theme change retints (§3.5) but does not regenerate.

**What a theme's character actually is.** This section used to promise that players would
notice "Catppuccin runs are twistier and cosier; Gruvbox runs are blocky and trap-heavy".
Measured, neither half was true: catppuccin had the *straightest*, shortest corridors of any
dark theme, and gruvbox was fourth of six on traps — and it could never have been trap-heavy,
because traps are derived from `1 − saturation` and gruvbox is the second most saturated dark
theme shipped. Naming a theme in a design document is a promise the derivation has to keep, so
the promise is now a table of what the derivation produces. Measured 2026-09-13 over 10 seeds
× 9 floors per fixture, after the levers were widened (the owner, from the chair, confirmed
the earlier version was "below perception"); the corridor and trap columns re-measured the
same day after the floor overhaul (§5.1: dressed corridors are wider, and traps are counted
outside the trap gauntlet, whose presence is the room budget's roll and not the theme's).
The *geometry* orderings — gruvbox and white the straight-halled pair, tokyo-night the most
connected dark theme, the light fixtures the biggest rooms — are asserted in
`ThemeLayoutTest`, and the spread between the extremes in `ThemeShapeTest`; the trap column
only at its ends (the fixture that derives the highest `trap_density` lays the most, the one
that derives the lowest lays the fewest), because the gaps in the middle of it are smaller
than their own sampling noise. That is also the reason no theme is named for its traps here.

| Fixture | room area | corridor tiles | loops | spacing | traps | hazard tilt | character |
|---------|-----------|----------------|-------|---------|-------|-------------|-----------|
| gruvbox | 97 | 72 | 1.0 | 0 | 7.9 | warm: spikes and fire vents lead | tightest and blockiest: rooms a fifth smaller than the open themes, straight halls, one loop, no spacing |
| nord | 99 | 103 | 1.8 | 0 | 8.0 | mildly warm | small rooms packed close, more loops than gruvbox |
| catppuccin | 125 | 109 | 1.9 | 2 | 7.9 | neutral: plates lead | open rooms on mid-length corridors |
| tokyo-night | 121 | 142 | 2.3 | 2 | 7.5 | neutral | the most connected dark theme: most loops, most corridor to walk |
| catppuccin-latte | 135 | 142 | 2.4 | 3 | 7.2 | neutral | the sprawling, heavily furnished plan a vivid light theme gets; the most saturated fixture, so the fewest traps |
| white | 134 | 116 | 1.5 | 1 | 8.4 | neutral | big open rooms on ruler-straight halls; the least saturated theme shipped, so the most traps |

**How big those differences are, honestly.** Side by side on one seed the themes are plainly
different dungeons: every pair of the six differs on at least a fifth of its tiles on every
floor of a run, and the numbers above now span 1.4× in mean room area, 1.6× in corridor tiles
and 1.0–2.4 loops between the tightest fixture and the most open. Mean room area over the
light fixtures beats the mean over the dark ones by about 24 tiles against a per-floor
standard deviation of 19 — a difference a player reads off a floor, not only off a session.
Difficulty is untouched: the trap count band and the spawn count are what they were, because
the room-size lever changes how much floor there is and not how many enemies stand on it.

`prop_density` carries a hard floor (`GenParams.PROP_DENSITY_MIN`) applied after the music
and wallpaper levers, because those levers are multiplicative and subtractive: a greyscale
theme playing a quiet track under a flat wallpaper used to stack down to 0.105, and its
rooms came out as empty tiled halls. The theme still moves the number; it cannot take the
dungeon below "somewhere worth being".

### 3.4 Wallpaper sources

Two engines supported, detected in this order:

**A. Omarchy shell** (Quickshell-based `omarchy-shell`; its `background` plugin polls
the symlink every 300 ms). The game does the same:

- Read target of `~/.local/state/omarchy/current/background` (`readlink -f`).
- Image (`png jpg jpeg gif bmp webp`) → analyse. Video (`mp4 m4v mov webm mkv avi`)
  → analyse the theme's `preview.png` instead (cheap, always present). `Desktop`
  records that substitution as `wallpaper_is_video`, and **nothing reads the flag**:
  the Void "glitch" tile animation it was meant to drive is not implemented and is a
  scope-trim candidate (§16). A video wallpaper therefore looks exactly like its
  theme's preview image, which is the whole of the behaviour today.
- Rotation via `omarchy-theme-bg-next` just changes the symlink, so it's covered.

**B. otter-wallpaper** (otter-shell). No IPC/D-Bus; the state file is the contract:

- `$XDG_RUNTIME_DIR/otter-shell/wallpaper-state`, legacy `/tmp/<uid>/otter-wallpaper-state`.
- Text; skip blank / `#` lines; `OUTPUT=absolute/path` per line; primary output is
  written first, so first entry = current wallpaper. Reject relative paths and `..`.
- Header comment `# otter-theme-gen-palette: shared-primary | first-output` (ignored).
- File is truncated-in-place on every change and deleted when the daemon exits →
  missing file means "no wallpaper", not error. Images only (`png jpg jpeg bmp webp`).
- Daemon not running (no state file) → fall back to `otter-wallpaper.conf`
  (`path` + `filename`, user then `/etc`) so a single configured wallpaper still counts.
- **otter-theme colours**: when otter-shell is the desktop and no Omarchy state dir
  exists, `ThemePalette` is built from
  `~/.config/otter-shell/theme.conf` → `colors_path` (relative to theme.conf or
  absolute; 12 semantic `#RRGGBBAA` keys `background surface surface_alt foreground
  muted accent on_accent selected border success warning danger`), mapped:
  background→floor, surface→wall, surface_alt→floor_alt, muted→wall_top,
  accent→accent, danger→danger, success→heal, warning→loot, selected→select.
  This covers both setups: a stock theme (`colors_path` → `/usr/share/otter-shell/...`)
  with any wallpaper, and wallpaper-generated colours (`colors_path` →
  `generated-colors.conf`). `generated-colors.conf` is never read unless it *is* the
  active `colors_path`. **otter-shell with no Omarchy state directory is a normal
  supported configuration**, not a degraded one — otter is not on Omarchy yet — and the
  theme is shown to players as exactly "Otter" (§16 #8). When `colors_path` is
  `generated-colors.conf` these twelve keys *are* the wallpaper, already reduced by
  otter-theme-gen; the game never analyses the picture for colour a second time (§16 #12).
- Change detection: theme.conf or its colours file mtime → THEME retint;
  wallpaper state/path → WALLPAPER re-analysis.

**The wallpaper shapes the run; it never colours it.** An otter-shell palette is *already*
generated from the wallpaper, so a second pass of the same picture over the theme applies one
image twice — which is exactly how a sage-green desktop came to build an orange dungeon (§16,
"The theme is the colours"). Not one colour measured here reaches the palette.

Wallpaper analysis (both engines): downscale to 64×36, k-means k=4 → 4 dominant
colours, mean luminance of top third → ambient (clamped 0.55–1.0), Sobel edge density →
`prop_density` ±0.15, image-path hash → `wallpaper_seed` used as an extra tie-breaker in
room fill choice. The dominant colours are read as two *statistics*, and nothing is ever drawn
in them: their chroma-weighted circular variance is `hue_spread` (how many hues the picture
holds) and their mean chroma is `colour_energy` (how vivid it is). Hue spread offsets
`room_size_bias` by up to `GenParams.WALLPAPER_OPENNESS_PUSH` (±0.12) and tilts the archetype
roll toward the irregular plans (`FloorArchetype.WALLPAPER_TILT`) — a monochrome picture
builds grids and rings, a many-hued one caverns and winding paths. Chroma offsets
`trap_density` by up to `WALLPAPER_HAZARD_PUSH` (±0.06): a vivid desktop is a more hazardous
floor. The ambient scales the theme's exposure between `LIT_AMBIENT_DIM` (0.72) and 1.0 — a rung and a half of the depth
ladder between the darkest wallpaper and the brightest, where 0.82 was under one rung and
nobody saw it. And the floor-start banner says so: the line after "Floor 3 - Crypt" reads
"Lit and shaped by your wallpaper - coloured by Tokyo Night" (`Hud.desktop_line`), because a lever the
player cannot see is a lever that does not exist. That line is now literally true: the
wallpaper lights and shapes, the theme colours.

### 3.5 Live change listener (always on)

Theme and wallpaper changes are applied **immediately, mid-level, always** — not on
next floor, not on next room. Mechanism (no inotify in Godot; polling is what
Omarchy's own shell does):

- `DesktopWatcher` autoload ticks every 300 ms (idle timer, ~free): stats the three
  Omarchy symlink targets (`theme`, `theme.name` mtime, `background`) and the
  otter state file mtime + `generated-colors.conf` mtime. Any change → debounce
  150 ms → `EventBus.desktop_changed(kind)` where kind ∈ {theme, wallpaper, both}.
- Optional zero-latency path: `tools/omarchy-hook/theme-set`, copied to
  `~/.config/omarchy/hooks/theme-set.d/50-omadungeon` (Omarchy runs
  `omarchy-hook theme-set <name>` after every switch). The hook touches
  `$XDG_RUNTIME_DIR/omadungeon/theme-changed`, which the watcher stats alongside the
  symlinks (`DesktopWatcher.HOOK_FILE`), so a switch is picked up on the next tick
  instead of waiting for a symlink mtime. Never required, and nothing installs it for
  you; `tests/unit/tools/omarchy_hook_test.gd` runs the script and checks it touches the
  path the watcher actually polls.
- On `theme` change: rebuild `ThemePalette`, push uniforms to all environment
  `ShaderMaterial`s, retint UI theme, CanvasModulate, lights — animated as a 0.6 s
  crossfade (old palette → new palette lerp in the shader) with a subtle "reconfigure"
  SFX and a HUD toast "Theme: Nord". Each room keeps its rolled *variant* (§10) so
  variety survives the swap. Music-reactive lights continue uninterrupted.
- On `wallpaper` change: re-run analysis in a `WorkerThread`, then swap prop
  colours/ambient with the same crossfade.
- Gameplay never pauses or stutters: analysis is off the main thread; palette push is
  O(materials) and measured < 1 ms.
- Debug: F5 forces a reload; `--theme-state <dir>` points at fixtures; test scenario
  `theme_swap_midfight` flips a fixture symlink during a fight and screenshots
  before/after.

## 4. Player

### 4.1 Controls

Twin-stick style. Move with left stick / WASD; aim with right stick / mouse. Attack is
held-to-repeat. Dodge has i-frames. All bindings remappable through Godot's InputMap
and a settings UI.

| Action | Keyboard/Mouse | Controller (Xbox naming) |
|--------|----------------|--------------------------|
| Move | WASD | Left stick |
| Aim | Mouse position | Right stick (auto-aim assist if stick idle) |
| Primary attack | LMB | RT |
| Secondary / weapon skill | RMB | LT |
| Dodge roll | Space / Shift | A / B (configurable) |
| Active 1 | Q | LB |
| Active 2 | E | RB |
| Interact / open chest | F | X |
| Potion | R | Y |
| Map overlay (hold) | Tab | Back/Select |
| Pause | Esc | Start |

Controller detection swaps all UI glyphs live. Mouse cursor hides on controller input.
Deadzones configurable. Rumble on hit/dodge (toggle).

### 4.2 Stats

Six primary stats, all shown in the pause menu with derived values:

| Stat | Effect per point |
|------|------------------|
| **Vitality** | +5 max HP |
| **Might** | +4% melee damage, +1% knockback |
| **Precision** | +4% ranged/projectile damage, +1% crit chance |
| **Arcana** | +4% ability damage, −1.5% cooldowns |
| **Swiftness** | +2% move speed, +1.5% attack speed, +1 dodge distance/5 pts |
| **Fortune** | +1.5% crit chance, +2% loot rarity roll, +1% dodge chance (cap 25%) |

Secondary: armor (flat reduction, diminishing), crit multiplier (base 1.5×), life on
kill, pickup radius, damage % by tag (fire/frost/arcane/physical).

"With derived values" includes the *damage* ones. The pause stats page lists the melee,
ranged and ability damage bonuses alongside max HP, armor, speeds, crit, cooldowns, dodge
and gold find, plus lifesteal and life on kill: that page is where a player chooses which
stat orb to take, so the per-point payoff of Might, Precision and Arcana has to be on it.

Stat-ups come from **stat orbs** in room chests (§8). Base stats per class:

| Class | VIT | MGT | PRC | ARC | SWF | FOR |
|-------|-----|-----|-----|-----|-----|-----|
| Fighter | 6 | 6 | 2 | 1 | 3 | 2 |
| Ranger | 4 | 2 | 5 | 2 | 5 | 2 |
| Wizard | 4 | 0 | 2 | 7 | 4 | 3 |
| Oligarch | 4 | 3 | 3 | 2 | 2 | 6 |

`data/classes/<id>.tres` is the source of truth for this table and
`tests/unit/player/class_def_test.gd` pins it to the shipped values; the Ranger and the
Wizard were retuned after the table was first written and the table was not.

### 4.3 Classes

Each class: starting weapon, one innate passive (uncounted), a unique class active
available in its pool, and a distinct dodge flavour.

**A new player has the Fighter and nothing else.** The other three are earned (§12): the
Ranger by clearing a floor, the Wizard at 120 lifetime kills, the Oligarch by clearing three
floors in one run. They are alternative ways to play rather than better ones - nothing a class
unlock grants is a stat increase - so the ladder is there to give the first three or four runs
something to be *for*, not to gate power behind grinding. Three classes used to be available on
the first launch with only the Oligarch locked, and a first run therefore ended with nothing
won.

**Fighter** — melee, sustain, knockback.
- Start: Rusty Sword (arc slash, 3-hit combo, 3rd hit knockback).
- Innate: *Second Wind* — +5 armour always, +25% damage below 40% HP.
- Dodge: short roll, i-frames 0.25 s, can cancel combo.
- Class active: *Bulwark* — 3 s shield absorbing 40% max HP; absorbed hits reflect a
  melee pulse.

**Ranger** — ranged, mobility, traps-for-you.
- Start: Shortbow (charged shot; full charge pierces).
- Innate: *Sure-footed* — immune to floor traps while dodging; +10% move.
- Dodge: long dash, no i-frames but leaves a caltrop patch (small).
- Class active: *Volley* — 5 arrows in a fan, +25% crit chance each.

**Wizard** — abilities, cooldown scaling, fragile.
- Start: Staff (bolt, slow but homing slightly).
- Innate: *Overflow* — every 4th ability cast is free and 25% stronger.
- Dodge: blink (teleport 3 tiles, 0.15 s startup, i-frames on arrival).
- Class active: *Chain Lightning* — arcs to 4 targets.

**Oligarch** — economy, luck, hirelings, pays for everything.
- Start: Golden Cane (weak melee) + 150 starting gold.
- Innate: *Buyout* — chests offer one extra option but cost gold to open (price
  scales by floor), +50% gold find, and the gold in hand is itself damage.
- Dodge: "Delegation" — a short hop; a decoy briefly taunts enemies.
- Class active: *Contract* — hire a Bodyguard for 20 s (cooldown 35 s). It starts **equipped**,
  in the Oligarch's first active slot, exactly as the Fighter starts with Bulwark: every class
  is granted its `class_active_id` (`RunManager` instances it and adds it to the slots
  unconditionally), and no class begins with both actives filled, so the asymmetry this bullet
  used to guard against does not arise. The class-only card that waits in the pool is *Hostile
  Takeover*, below.
- Also class-only, offered alongside everything else: *Hostile Takeover* — convert the
  nearest non-elite enemy to fight for you for 10 s.

### 4.4 Abilities (2 passives + 2 actives, max)

A run has **4 ability slots**: 2 passive, 2 active. Offered in chests and ability
altars. Taking a 3rd of a kind requires *replacing* (with confirmation). Abilities have
up to 3 tiers; picking a duplicate upgrades it.

Actives (cooldown-based, examples, ~20 total in v1):

| Name | Effect | CD |
|------|--------|----|
| Fireball | AoE 2 tiles, burn | 6 s |
| Frost Nova | Freeze radius 2.5, 1.5 s | 9 s |
| Shadowstep | Teleport to aim, +50% crit next hit | 7 s |
| Whirlwind | 1.2 s spin, hits all around | 8 s |
| Turret | Drop turret 10 s | 14 s |
| Warcry | +25% dmg, taunt, 5 s | 12 s |
| Rm -rf | Delete all projectiles + traps on screen | 15 s |
| Reboot | Full heal 20% over 3 s, silence self | 30 s |
| + class actives above | | |

Passives (examples, ~25 total in v1):

| Name | Effect |
|------|--------|
| Thorns | Reflect 20% melee dmg |
| Glass Cannon | +40% dmg, −30% max HP |
| Vampiric | 3% lifesteal |
| Tiling WM | Enemies take +15% dmg when ≥3 are aligned in a row/column with you |
| Dotfiles | Each equipped item gives +1 to its lowest stat |
| Lucky Coin | Reroll chests once for free per floor |
| Ricochet | Projectiles bounce once |
| Adrenaline | +30% attack speed 3 s after dodge |
| Heavy Hands | Melee knockback ×2 |
| Hotkey | Actives refund 20% CD on kill |

### 4.5 Equipment

Slots: **Weapon, Armor, Ring ×2, Trinket**. Items are procedurally generated:

```
Item = BaseType + Rarity + [Prefix] + [Suffix] + rolled affixes (1–4)
```

- **Base types** (v1): swords, axes, spears, daggers, bows, crossbows, wands, staves,
  thrown; light/medium/heavy armor; rings; trinkets. Each base has stat ranges and a
  *weapon skill* (RMB/LT).
- **Rarity**: Common (1 affix), Rare (2), Epic (3), Legendary (4 + unique effect).
  Colours from `rare_tiers`.
- **Affix pool**: flat/percent stats, on-hit effects (burn/frost/shock/poison), on-kill,
  on-dodge, projectile mods (+1 proj, size, speed, pierce), cooldown, gold/lucky.
- **Names**: `<Prefix> <Base> of <Suffix>` where prefix/suffix reflect affixes. Wordlist
  seasoned with the theme (e.g. "Nord-forged", "Gruvboxen", "Catppuccin Ring of Mocha").
- Equipping is instant from a chest or ground pickup; comparison tooltip shows deltas.
- Selling is not a thing, and neither is salvage: an item you skip is left where it is.
  (An earlier draft of this line promised gold for skipped items. No salvage code was ever
  written, and the Oligarch's economy is fed by `gold_find` and chest pricing instead.)

Weapon skill examples: sword *Lunge*, axe *Cleave*, bow *Rain*, staff *Barrier*,
dagger *Fan of Knives*, spear *Sweep*.

---

## 5. Level Generation

### 5.1 Layout

Room-and-corridor graph, Tiny Rogues style (rooms are the unit, not open caves).

1. **Archetype, then graph**: every floor is laid to one of five plans (`FloorArchetype`),
   rolled from the seed and tilted by the biome, the theme's geometry levers and the
   music, so two floors of one run read as different places:

   | Archetype | Plan | Leans toward |
   |-----------|------|--------------|
   | `hub` | a big central crossroads room (23×17, up to 5 exits) with short spokes; an elite holds the hub when one is rolled | forge, library; open themes; loud tracks |
   | `winding` | one long path carrying ~85% of the rooms, dead-end side pockets, one loop fewer; galleries and L-shapes | crypt, void; winding themes |
   | `ring` | the spine curls and a loop closes it back near the start; octagons | frost, void; straight themes; fast tracks |
   | `grid` | a tight complex: rooms packed at the minimum gap, two extra loops, closets and small rooms, plus-shaped rooms | crypt, library; tight themes |
   | `cavern` | irregular: wide gaps, octagons and L-shapes, half the corridors widened or given chambers | frost, void; open, winding themes |

   Then a spanning tree of N rooms (N by floor: 7,8,9 | 10,11,12 | 12,13,13) with a
   guaranteed spine (the archetype's share of the rooms) and 0–4 loop edges: the theme's
   1–3 (`corridor_wiggle`) plus the archetype's delta. Constraint: stairs room is ≥ 3 edges
   from start; boss floors are linear-ish whatever the archetype (start → 2–3 rooms → boss
   arena, side rooms hanging off the spine, the arena a single-door leaf).
2. **Placement**: grid-tree layout, rooms snapped to 16px tiles, sized from a table
   (closet 7×5, small 9×7, medium 13×9, large 17×13, hall 21×9, gallery 17×7, arena 21×15,
   hub 23×17) with `room_size_bias` and the archetype's size odds; about a third of rooms
   are turned on their side. Each room then takes a *shape* (`RoomShape`: rect, L, T, cross,
   octagon) stamped as wall inside its bounding rect, with the centre 3×3 always kept for
   the player spawn, the stairs and the altar; at least two rooms in five on a floor are not
   rectangles. The archetype steers where a child room goes (snake on, curl, fan out from
   the hub) and how far apart rooms sit. Rejection sampling for overlaps; up to 50 attempts
   then re-seed.
3. **Corridors**: L-shaped or wiggly (A* with jitter) between door anchors; a door only ever
   opens onto floor. After carving, `CorridorDressing` widens a share of corridors to two
   tiles, gives some a 5×3 chamber half-way and some a side alcove, at rates the archetype
   sets — never opening a tile that would touch another corridor or a foreign door, so the
   walkable topology is still exactly the room graph. Doors are 1 tile wide with lockable
   door entities.
4. **Room types**: Start, Combat (majority), Elite, Trap gauntlet, Treasure (no fight,
   trapped), Altar (ability choice), Shop (Oligarch-friendly; sells 3 items + reroll),
   Shrine (buff-for-a-cost), Stairs, Boss.
   Not every type on every floor (`RoomBudget`, the owner's report of 2026-09-13). Per
   floor: exactly one *blessing* room (an Altar **or** a Shrine, never both), a Shop where
   the table guarantees one and a roll elsewhere, then the optional rooms the table and the
   ≥ 60% fight quota (Combat/Elite/Trap over the free pool) allow, one of each at most:

   | Floor | Altar (else Shrine) | Shop | Elite | Trap gauntlet | Treasure |
   |-------|---------------------|------|-------|---------------|----------|
   | 1 | always | never | never | never | 40% |
   | 2 | 60% | **guaranteed** | 50% | 40% | 60% |
   | 3 (boss) | 50% | 35% | 40% | 50% | 25% |
   | 4 | 50% | 45% | 60% | 50% | 50% |
   | 5 | 50% | **guaranteed** | 60% | 60% | 60% |
   | 6 (boss) | 50% | 35% | 40% | 60% | 30% |
   | 7 | 50% | 50% | 60% | 50% | 50% |
   | 8 | 50% | **guaranteed** | 90% | 80% | 50% |
   | 9 (boss) | 40% | 30% | 50% | 70% | 30% |

   Services and the treasure room take dead ends, the elite and the gauntlet through-rooms.
   The balance simulation (`SimFloorPlan`) rolls the same table, and the validator enforces
   the caps and the shop guarantees.
5. **Interior**: each room gets a *fill template* (empty, pillars, cross, ring, rubble,
   pits, vault) weighted per biome (`RoomTemplate.biome_weights`: a library leans on
   pillars, a forge and the void on pits, the frost on rings, the crypt on rubble) then
   props scattered by `prop_density`, then traps by `trap_density`,
   respecting a walkability check (flood fill from every door to every door).
6. **Decoration pass**: Wang/autotile walls, floor variation with `bg_alt`, wallpaper
   colours on props (§3.4).
7. **Validation**: full A* connectivity, no spawn overlaps, trap never blocks the only
   path, a room's spawn points never within 3 tiles of any door, and in a boss arena every
   spawn at least 8 tiles from every door (`ArenaSpawns.DOOR_CLEARANCE`).
8. **Lantern anchors**: the last thing written onto a floor is `FloorData.lantern_anchors`
   (`LanternAnchors`), the wall tiles the lighting system may hang a lantern on: along every
   room's wall ring and every corridor's walls, one every `Biome.lantern_spacing` tiles
   (forge and library 5, crypt 6, frost 7, void 8), at least one per room side that has
   room for it, never in a doorway or the tile beside one (the door carries its own torch
   pair), never two anchors touching. Rolled from the floor's own rng, so the same seed and
   `gen_params` give the same lanterns and a resumed floor is lit as it was. Tile semantics
   are the contract this rests on: VOID is outside, WALL is solid wherever it stands (ring,
   shape cut, pillar, corridor ring), FLOOR / CORRIDOR / DOOR are walkable, PIT is a hole.

#### What a seed does and does not reproduce

Seed: 64-bit; displayed on HUD and run summary; enterable at start.

A seed is **not** the whole identity of a run. The seed fixes the *random rolls* — the order
every `RunRng` stream produces, and therefore layout, loot, affixes and offers given the same
inputs. The *inputs* are deliberately not fixed by it: generation folds in the desktop theme
(§3.3), the wallpaper analysis (§3.4) and the track playing when each floor is generated
(§10.2). So:

- Same seed, same theme, same wallpaper **and the same recorded `gen_params`** → the same
  dungeon, floor for floor. That is what *Continue* replays.
- Same seed under a *different* Omarchy theme → a different dungeon. That is the point of
  pillar 3, not a bug; "your desktop is the dungeon" would be meaningless if the theme could
  not move the floor plan.
- Same seed, same theme, same *track*, twice → **not** necessarily the same dungeon. Two of
  the music levers (§10.2) are sampled live at the instant a floor is built: `energy` is a
  30 s rolling RMS and `tempo` is a live BPM estimate, and they move `enemy_count_scale`,
  `prop_density` and `corridor_wiggle` (and through it `extra_loops`). Start a floor 20
  seconds later in the same track and the floor plan moves. The seed still fixes every
  *roll*; it does not fix what the rolls are made against.
- Swapping the theme *mid-run* only retints what is already built; floors already generated
  keep their layout. Only floors generated after the swap take the new parameters.

Because of that, anything that offers to replay a run must carry the inputs, not just the
number: `run.json` records `gen_params` alongside the seed and the RNG stream states, which is
what makes *Continue* rebuild the floor you left rather than a fresh one. Nothing in the UI
may promise more than that. The title screen's seed caption names the live theme and the other
inputs rather than a reproducible dungeon ("A seed fixes the rolls. Tokyo Night, the wallpaper
and the music shape each floor too."), and the run summary's seed button is *Reuse seed* — it
starts a new run on the same seed and class, and its tooltip says the dungeon will differ.
A button labelled "Retry seed" would be promising a replay only `gen_params` can give.

### 5.2 Biomes (3 per run)

| Biome | Floors | Tileset flavour | Signature hazard |
|-------|--------|-----------------|------------------|
| Crypt | 1–3 | Stone, cobwebs, coffins | Spike floors |
| Forge / Frost / Library | 4–6 (by `warmth`) | Lava & anvils / ice & wind / shelves & candles | Fire vents / ice slides / falling books |
| Void | 7–9 | Glitched tiles, floating platforms | Pits, laser grids |

All tilesets are drawn in the indexed ramp so themes recolour them.

---

## 6. Combat

- 60 Hz fixed physics; hitboxes are Area2D with shapes, damage numbers pop (toggle).
- Damage = base × stat mult × crit × tag mult − armor (armor: `dmg × 100/(100+armor)`).
- Enemy tells: 0.3–0.6 s windup with `danger` colour flash; attacks have hit-stop 2–4
  frames; screen shake scaled by hit (toggle).
- Status effects: Burn (DoT), Frost (slow, then freeze at stack 3), Shock (chain on
  hit), Poison (DoT, stacks), Stun, Taunt.
- Knockback resolved against walls; heavy enemies resist.
- Player HP starts 100 (+Vit). Potion: 1 slot, heals 40%, refilled by Shrines/drops.
- Room lock: doors close when player is ≥ 1 tile inside and enemies exist. Open when
  all dead. Chest spawns at room centre (or nearest free tile).

---

## 7. Enemies — "People Who Dislike Omarchy"

Faction weighting uses `hue_dominant`: warm hues → more *Clowns*; cool hues → more
*Greybeards*; green/purple → more *Tinkerers*. The favoured faction is weighted
`ThemeProfile.FACTION_FAVOURED` (2.0) against 1 for the other two — half of every pack, where
1.5 was 43% and nobody read it. Every floor still mixes all three, and the weighting never
changes how many enemies a room holds.

### 7.1 Clowns (chaos, projectiles, mobility)
| Enemy | Behaviour |
|-------|-----------|
| Juggler | Throws 3 pins in arc, retreats |
| Honker | Charges, honk AoE stuns 0.5 s on impact |
| Balloon Clown | Floats over pits, pops into confetti shrapnel on death |
| Mime | Invisible walls (temporary blocking tiles), fragile |
| Clown Car (elite) | Spawns 4 clowns, then rams |

### 7.2 Greybeards (slow, tanky, "it worked fine in 1998")
| Enemy | Behaviour |
|-------|-----------|
| Manpage Hurler | Lobs heavy tomes, slow arc, big damage |
| Beard Warden | Shield front, must flank |
| Rant Priest | Buffs allies' damage, screams (knockback) |
| Vim Zealot | Only moves in hjkl cardinal dashes, very fast |
| Kernel Panic (elite) | Screen goes `danger` tint; random tiles become spikes for 5 s |

### 7.3 Tinkerers (traps, summons, ranged)
| Enemy | Behaviour |
|-------|-----------|
| Ricer | Drops decorative props that become traps |
| Distro Hopper | Teleports every 3 s, weak shots |
| Config Gremlin | Steals a random stat point, drops it on death |
| Dotfile Golem (elite) | Big, slow, splits into 3 gremlins |

### 7.4 Bosses

**The arena opening.** The boss never stands in the doorway (owner report #6). The generator
puts its spawn on the far side of the arena — the deepest reachable tile along the door's
inward normal, on the centre line, two tiles off the wall, and never under 8 tiles from any
door (`ArenaSpawns`; the validator refuses a floor that breaks it). The boss is spawned
*dormant* (`BossBase.sleep_until_engaged`): it idles at its spot and neither moves nor attacks
until the player crosses the arena's deep trigger, three tiles past the door
(`RoomNode.BOSS_TRIGGER_INSET`). At that moment the room seals its doors, `BossArena` wakes
every enemy in it, plays the roar, shakes the screen and puts "<name> awakens" through the HUD
toast lane, and the boss music starts. A hit on a dormant boss wakes it too, so it cannot be
sniped from the door for free. The elite pack that stands in for an unbuilt boss takes the
same far-side spots (the arena records the boss's tile plus three pack tiles around it) and
wakes on the same trigger.

- **Floor 3 — The Ringmaster**: three phases; summons, ring of fire, whip pull.
- **Floor 6 — The Elder Greybeard**: arena tiles rotate; RTFM beam; beard tentacles.
- **Floor 9 — The Suit (Oligarch's rival / final)**: buys your abilities (disables one
  slot per phase), hires enemies from all factions, "hostile takeover" of the arena.

Enemy scaling is a **table, not a formula**: `data/balance/difficulty_curve.tres` holds one
HP and one damage multiplier per floor, so the ramp can be shaped floor by floor instead of
being a straight line (`EnemyDef.scaled_hp` / `scaled_damage` read it). As shipped that runs
from ×1.00 HP / ×0.82 damage on floor 1 to ×2.70 / ×2.62 on floor 9 — a steeper curve than
the ×2.44 / ×1.96 the old formula in this paragraph described. Elites take the curve's
`elite_hp_multiplier` (×3) and `elite_damage_multiplier` (×1 — an elite's `.tres` damage is
the number the player is hit for), and always drop a Rare+ item.

---

## 8. Rooms, Chests and Rewards

After a room clears a chest appears. Chest kind is rolled by room type and floor:

| Chest | Contents (choose 1 of 3) |
|-------|--------------------------|
| **Stat chest** (most common) | 3 stat orbs (+1 to a shown stat; Fortune-scaled chance for +2) |
| **Item chest** | 3 generated items (at least one for a slot you have empty/weak) |
| **Ability chest** | 3 abilities (mix of active/passive, respects slots) |
| **Gold chest** | Gold only, larger |
| **Cursed chest** | Legendary offer but attaches a Curse passive (takes a passive slot until removed at a Shrine) |

Reroll costs gold (base 25, ×1.5 per use per floor). Oligarch: +1 option, pays to open.
Skipping a chest grants small gold. Chests can be trapped in Treasure rooms.

Drops from enemies: gold (auto-pickup radius), hearts (rare), stat orb (rare, elites).

---

## 9. Traps

All traps telegraph. Types:

| Trap | Tell | Effect |
|------|------|--------|
| Spike floor | Tile darkens 0.5 s before | 15 dmg, hits enemies too |
| Arrow wall | Slot glow | Projectile line |
| Fire vent | Puff | Burn zone 2 s |
| Pit | Always visible | Fall = 10 dmg + respawn at room entry |
| Pressure plate | Visible | Triggers arrow walls/door lock/enemy cage |
| Ice slide | Visible | Momentum preserved |
| Laser grid (Void) | Rhythmic | High dmg, on/off pattern |
| Mimic chest | Slight wobble | Fights back |

Traps damage enemies (except Tinkerer-placed traps). Ranger dodges through them.

---

## 10. Art & Audio

- Internal resolution **480×270**, integer-scaled to window; pixel-perfect (Godot
  `canvas_items` stretch + `nearest` filtering, snap 2D transforms).
- Tiles 16×16, characters 16×16 (bosses 32–48).
- **Tinting scope: environment only.** Theme colours drive floors, walls, props,
  lighting, fog/void, doors, chest glow, UI, and the *player's* cloak/accent trim.
  Enemies, items and projectiles keep their own authored colours so factions and
  threats stay readable under any theme. Exceptions: the `danger` tell flash and
  rarity outlines use theme colours (guarded for contrast).
- **Palette authoring ramp** for environment tiles (indices): 0 transparent,
  1 outline, 2 dark, 3 mid, 4 light, 5 highlight, 6 accent A, 7 accent B. Shader
  maps these to `ThemePalette` roles per tile category (floor, wall, prop, liquid).
- **Variety inside a theme.** A flat theme tint gets samey by floor 3, so each room
  rolls a *palette variant* (seeded): 60% base mapping, 20% "accent-shifted" (accent A/B
  swap to a different theme colour, e.g. `magenta`→`cyan`), 15% "warm/cool push"
  (floor lightened/darkened toward `orange`/`blue`), 5% "inverted lighting" (uses
  `bright_*` set as base). Biomes also pick from different subsets of theme keys
  (Crypt: `brown`/`green`; Forge: `orange`/`red`; Frost: `cyan`/`bright_blue`;
  Library: `brown`/`yellow`; Void: `magenta`/`cyan`). Variants must pass
  the same contrast guard. Music energy (§10.2) modulates light intensity on top.
  A subset must be an *accent* subset: the first draft gave Crypt `background`/`muted`
  and Void `dark_background`/`magenta`, and every shipped theme authors its three
  background keys at one hue, so those two biomes rolled both accent slots onto the wall's
  own colour and floor 1 rendered as a lavender grid with lavender pots in it. The
  downstream guard is `TileRamp.is_accent_candidate`: a pool colour whose hue is the room's
  own hue is dropped, and the theme's tell colours (§3.2) fill the pool instead.
- **Clutter.** Nine prop kinds a biome (four shared: barrel, crate, sack, rubble; five of the
  biome's own - crypt coffin/gravestone/urn/candle/bones, forge anvil/cart/brazier/chain/slag,
  frost ice block/lantern/snowman/boulder/snow, library bookshelf/desk/lectern/globe/books,
  void crystal/monolith/floater/orb/rift), each with a silhouette of its own - tall, round,
  square, wide or pointed - and one identifying feature in the accent (a flame, book spines,
  a rune). All drawn in-house as pixel maps (`tools/art/prop_maps.py`), never generated from a
  grammar or noise. Solid kinds wear an ink outline and a contact shadow, block, cast a shadow
  (a `LightOccluder2D` the size of their base) and break; flat kinds carry no ink, lie low,
  have no collider and are walked over. They stand where furniture stands: solids in clusters of two or three against
  walls and in corners, flats sparse in the open, never in a doorway or on the line between
  two doors (`PropPlacement`, tuned from `data/rooms/rooms_content.tres`). Traps keep their
  own hazard colours and warning frame, chests their gold; nothing on the floor shares a look
  with either. See `assets/tiles/README.md` "Solid or flat" and `tools/art/prop_maps.py`.
- Asset sources (must be CC0 / OGA-BY / CC-BY, credited in `docs/CREDITS.md`):
  - Tilesets & props: Kenney "Tiny Dungeon" (CC0), 0x72 "DungeonTileset II" (CC0),
    Pixel-boy "Ninja Adventure" (CC0) for FX.
  - Characters: 0x72 heroes as base (CC0), recoloured/edited to ramp; new enemies
    drawn in-house or proc-generated (§10.1).
  - UI: Kenney UI packs (CC0).
  - SFX: Kenney audio (CC0) + jsfxr-generated blips (proc, committed as WAV).
  - Music: **Omarchy Radio** tracks (https://radio.omarchy.org, repo
    `omacom/radio.omarchy.org`, `public/tracks/*.mp3` + `playlist.json` with
    title/artist/explicit/lyrics). The repo states no licence (checked root README,
    tracks README, DESIGN.md, GitHub licence field); tracks are artist-submitted
    songs "set in the Omarchy universe". Decision: this is an Omarchy-universe game,
    so tracks are **bundled** in `assets/music/radio/` with `playlist.json` kept
    verbatim, every artist/title credited in `docs/CREDITS.md` and the in-game
    credits screen, and the track/artist shown as a toast on change (as the site
    does). `tools/sync-radio.sh` pulls the latest playlist from the repo; explicit-
    flagged tracks are filterable in settings; `.lrc` lyrics are shipped where
    present and shown on the pause screen for the current track. If any artist
    objects, their track is dropped from the sync list. Bosses get the "Oligarchy"
    tracks (Rich Kilmer / YZL81 mixes); Oligarch class menu music = *public code,
    private yacht*. Size budget: ~170 MB for 34 tracks; export preset can exclude
    music for a "lite" build.
- **10.1 Procedural sprites** for some props, items and minor enemies: symmetric
  bit-mask generation (classic "spaceship" style) with the ramp, seeded from item
  hash so a given item always looks the same. Used for rings/trinkets/wands and
  Tinkerer "props".
- **Lighting.** Two layers, and the second is built on the first, never instead of it.
  - *The palette exposure model* (§3.2): every environment material is built from
    `lit_palette()`, the theme lit at the wallpaper's ambient, and the readability ladder
    (floor over void, wall over floor, cap over wall, prop over floor) is guaranteed there,
    on colours, before a single light is drawn. Nothing below may dim it out of the ladder.
  - *The dynamic layer* (`src/rooms/lighting/`, tuned from `data/rooms/lighting.tres` =
    `LightingProfile`, built by `FloorRoot` as a child named `Lighting` = `LightRig`):
    - **Darkness**: a flat `PointLight2D` the size of the floor in MIX toward black, x0.32
      (sRGB; about x0.09 in linear light) on a dark theme and x0.92 on a light one (a paper
      floor at 0.32 is a grey floor; a light theme only dims a touch and its lanterns only
      warm). It was x0.72 for a round, and the owner's word for that was "lighting is there
      but BARELY makes a difference": a darkness that keeps three quarters of the light has
      almost nothing for a pool to undo, and `lighting_frame` measured the floor under a
      lantern at 8% over the floor between the pools. A light rather than a `CanvasModulate`
      because what it reaches is then a
      `light_mask` question: the environment (bit 1) takes it whole; props, interactables,
      chests, enemies and the player (bit 3, `LightRig.PROP_MASK`) sit under a lighter one at
      `ambient ^ 0.144` (x0.85, the exposure they stood at under the old x0.72 floor, which is
      why the readability ladders did not have to move when the room went dark) on a dark
      theme and `ambient ^ 1.5` on a light one, so the prop
      ladder `Prop.readable_colors` guarantees against the floor is measured as drawn with
      more room than it had (`prop_frame` green on every fixture with the layer on) while a
      crate still sits in the dark room; and tells - traps, enemy health bars, alert marks,
      telegraphs, damage numbers, the player marker - are on bit 4 (`TELL_MASK`), which no
      light reaches. Loot (a pickup, a dropped item) takes the exemption only on a **dark**
      theme, where it is what lets a coin read in an unlit corner; on a light theme loot is
      dark ink on bright paper, the exemption would leave the ink still while the darkness
      took the surface down toward it, so loot moves with its surface on `PROP_MASK` instead
      (`LightRig.loot_mask`, re-read on every `palette_changed`).

      Loot is guarded against the surfaces **as drawn**, which is the same rule the prop ladder
      follows and the one the pickup guard was missing. `ThemePalette.world_color()` solves an
      ink against the *authored* surfaces, and on `white` that lands at 3.04:1 against the wall
      - 0.04 over its own 3.0 line - so the darkness alone took it to 2.52:1 and a coin on a
      wall tile was gone. Deepening the ink cannot fix that fixture: its floor is paper and its
      wall is mid-grey, so no single colour clears 3.0 against both. A drop is therefore two
      colours (`LootInk`): the guard's ink, and a one-pixel ring behind it in the opposite
      direction, so the line is met **per surface** instead of globally. The ring is solved
      against `ambient x (1 - unexplored_shade)` of each surface, the darkest a floor ever
      gets, and is drawn only where a single ink cannot carry every surface - which is the two
      light fixtures and nowhere else, so a dark theme's drop, and any drop with the layer
      Off, is exactly the single-colour shape it has always been. (A
      CanvasModulate was the first draft; measured on a frame it reached unshaded items too,
      and the prop ladder had no way out of it. A `DirectionalLight2D` was the second; in the
      compatibility renderer it did nothing at all. Both are recorded so nobody tries them a
      third time.) The HUD is a CanvasLayer and never under any of it. The
      level follows the music through the `DungeonLight` live contract: half of the mood's
      `ambient_energy()` (the shader grade already carries the other half on every surface),
      in the mood's `ambient_color()` temperature, slewed at 0.004 a frame on top of the 3 s
      crossfade upstream, so it can never step and never pulses. Rooms nobody has entered
      stand under a 12% shade (a flat MIX-toward-black light the size of the room, over the
      environment and the bodies alike - a shade on the floor alone took the floor out from
      under the props standing in it); entering one fades it out over 0.6 s and a cleared room
      on a dark theme earns a 5% additive lift the same way.

      The masks are what the *darkness* is split by, and a **wall lantern's pool** is split by
      them too, because the floor and the bodies on it no longer stand under the same darkness
      and one pool cannot restore both: the floor gets `lantern_energy`, and a body gets
      `LightRig.body_pool_energy` - its own darkness undone, and no more. Door torches and
      every emitter that *lives with its host* - a chest, an altar, a shrine, the stairs, a
      fire, a bolt in flight, the player's own light - still reach a body with the pool they
      put on the floor beside it, on `LIT_MASK`, because their energies are small enough to.
      An emitter with a fade of its
      own - a swing, a spell bloom, an explosion, any one-shot - is on `ENV_MASK` and lights
      the ground alone, because a light that is on its way out from the moment it appears has
      no business rewriting what a crate looks like.

      Every pool is drawn with one shared radial texture whose alpha falls as
      `(1 - t) ^ DungeonLight.FALLOFF_POWER` (2.5), not linearly. Light is additive, so over a
      floor at a third of its own light the faint outer half of a linear ramp is still a large
      relative lift: every lantern threw a haze most of a room wide and six of them washed the
      room back to even, which is the flat look the darkness was supposed to fix. A power
      falloff gives a pool a bright core and an edge, and the room reads as islands of light.
    - **Wall lanterns**: one `WallLantern` on every anchor the generator rolls
      (`FloorData.lantern_anchors`, `LanternAnchors`: wall runs, one every
      `Biome.lantern_spacing` tiles, never in or beside a doorway) - a sprite in the biome's
      own fixture (crypt torch, forge brazier, frost cage lantern, library candelabra, void
      crystal; tile atlas row 4 columns 7-12) drawn in the room's flame material, and one
      `PointLight2D` on the wall's lip in the fixture's palette role (`heat` for fire, turned
      toward the accent like a door torch; `loot` for a lantern or candle; `magic` for a
      crystal), on `ENV_MASK` at 0.68 - the darkness *undone* at the pool's centre and never
      more, exactly (0.32 + 0.68 = 1), since a pool that lifts a surface past its undarkened
      level is light the readability ladders were never measured under. That makes the lit
      floor x3.1 of the floor between the pools, where the old 0.72/0.28 pair made x1.39.
      A second light on `PROP_MASK` carries the same pool to the bodies standing in it, at
      `LightRig.body_pool_energy` - the *body's* darkness undone, a much smaller number,
      because a body is barely darkened in the first place. One light for both was right while
      the floor and the bodies stood under nearly the same darkness and stops being right the
      moment they do not: 0.68 landing on a body already at x0.85 takes it to x1.53, which
      pins its brightest channels and collapses the ladder inside it - on `prop_frame` the
      catppuccin forge crate's top two rungs came within 1.03 of each other against a
      `Prop.LIT_BODY_STEP` of 1.12, and gruvbox lost three biomes the same way.
      The opposite failure is on record too, from when the split was first tried over a floor
      at 0.72: a pool that lifted the floor faster than the body took the void sack's ladder
      *against the floor* from 2.36 to 2.10 against a 2.2 line. Over a floor at 0.32 the same
      props read 4.3 to 7.5 against that line, so the headroom the split costs is headroom
      there is now plenty of, and `prop_frame` measures both ends on all six fixtures.
      Each surface gets its own darkness undone and neither gets more. Both lights take the
      mood's `torch_energy_scale()` and `torch_radius_scale()`.
    - **Shadows**: every WALL tile lies inside a merged `LightOccluder2D` rectangle
      (`WallOccluders`: cells become runs, runs become rectangles; the generated floor-1 layouts
      the frame check builds carry 120-185 rectangles for 7 rooms and their corridors). A face that touches walkable ground is stood in 5 px so
      the wall's own lip stays lit and the shadow starts behind it; faces on wall or void stay
      flush, so runs meeting at a corner leave no gap. Solid props and bosses carry their own
      occluder (bit 2), and cast from the player's own light only - one short soft blob that
      turns with the player; a lantern's pool shadowed by the crate beside it left that
      crate's floor dark under a lit crate, and `prop_frame` measured the contrast fall. The
      player and every enemy stand on a soft shadow blob. Every shadow is PCF13 at alpha
      0.45: it dims, it never blacks out. Only the nearest **8** lights to the camera cast
      (`shadow_casters`): a shadow-casting light is the one thing in the 2D renderer that
      costs per light *and* per occluder, and a light standing inside a wall core (a door
      torch on a corner cell) never casts, since it would light nothing at all.
    - **Emitters**: gameplay light is data - `LightingProfile.emitters` is a table of kind ->
      palette role, energy, radius, fade - and `LightEmitter.attach(host, kind)` /
      `LightEmitter.flash(kind, pos)` take a pooled `PointLight2D` from the rig (24 warm, 64
      cap, a request past the cap is dropped rather than queued). A sword swing glows in the
      accent for 0.18 s from the hand; every projectile carries `shot` (accent) or
      `enemy_shot` (danger) until it lands; a fireball is `fire` (heat) and its burst an
      `explosion` (heat, x1.2, fading over 0.45 s from a 60 ms rise - a bloom, never a flash);
      frost nova `frost` (cold), chain lightning `shock` (cold) at every arc, fork bomb and
      shadowstep `arcane` (magic), stack smash `explosion`, warcry `danger`, reboot `heal`;
      an enemy's slam `enemy_burst`; a closed chest `chest` (loot) until it opens; the stairs,
      altars and shrines glow in `text_bright`, `magic` and `heal`. The player's own pool is
      the table's `player` row too - the light is a node in `player.tscn`, and the rig drives
      its energy from the row on every build, palette change and caster tick, so the scene and
      the data cannot drift. Every gameplay light is turned down to `emitter_light_scale`
      (0.25) on a light theme, for the reason the lantern pool is: paper has no headroom for an
      additive pool. At full energy the player's 0.7 accent pool clipped the floor around it to
      #f0f4ff on catppuccin-latte, a white blob with the pixel art's tile seams gone, and the
      readability *minimum* said nothing about it. `lighting_frame` measures the other end as
      well: the 99th-percentile floor *pixel* by the player may not draw over
      `LIGHT_FLOOR_CEILING` (0.90) on a light theme. Pixels, not tile means - a tile mean
      averages the seams back in and topped out at 0.74 even fully blown, so a ceiling written
      against means could never fire. Measured: full energy catppuccin-latte 0.9657 and white
      1.0000, at 0.25 they are 0.8248 and 0.8963. `white` is what sets the number; its paper
      floor is already 0.8469 with no pool at all. Every colour resolves
      through the same `light_color_for(role)` (the lit palette's role, made a light, graded
      by the mood), so a theme swap mid-run retints all of them from the one
      `palette_changed` the tiles follow (`live_swap_test`).
    - **Settings**: *Lighting* Off / Low / High and *Shadows* on/off (Video). Off is exactly
      the floor as it was before this layer existed - no darkness, no lanterns, no occluders,
      no emitters, the door torches untouched (`lighting_rig_test`); Low is everything but
      shadows.
    - **Measured** (`tools/capture-scene.sh lighting_frame <theme>`, 1440x810, generated
      floor 1, three qualities in turn, 180 frames each, vsync off, one frame in ms avg /
      p95). On llvmpipe (`LIBGL_ALWAYS_SOFTWARE=1`, 2026-09-14): tokyo-night Off 4.2 / 4.6,
      Low 7.0 / 7.6, High 11.6 / 12.6; gruvbox 7.7 / 8.1, 10.0 / 10.9, 14.4 / 15.3;
      catppuccin-latte 6.4 / 6.8, 7.9 / 8.5, 11.9 / 12.7; white 6.6 / 7.2, 8.4 / 9.1,
      12.7 / 13.6 - so the whole layer with shadows costs 5-7 ms a frame on the software
      rasteriser over Off, 35-41 lanterns and 120-187 wall occluders on screen-size floors,
      and the game stays over 70 fps there. A software rasteriser answers to what else the
      machine is doing: a tokyo-night pass under load read 7.6 / 11.8 / 16.7, the same shape
      with every row moved up. The default path in the harness is the box's own GPU, where the whole layer
      is under half a millisecond (latte Off 0.15, Low 0.16, High 0.47 on an RTX 5090).
      `tests/out/lighting_perf*.txt` is the record. The floor around the player must clear
      0.04 mean luminance on a dark theme and 0.35 on a light one, and the nearest lantern's
      pool must lift the floor it falls on above the floor three tiles along the same wall, or
      the check exits 2.
  - The door torches (`DungeonLight`, `data/rooms/dungeon_light.tres`) are as before:
    additive on top of the exposure model, coloured from `heat` turned `torch_accent_mix`
    (0.35) toward `accent` (`DungeonLight.torch_role_color`, so the pool of light is the
    desktop's colour and not one orange on every theme), budgeted per floor, flicker through
    the accessibility policy (damped by reduced flash, off under reduce motion); the two
    accent rungs of a torch cell are forced onto `heat`/`loot` (`TileRamp.flame_colors`) so a
    flame is warm on every theme. The rig moves each torch's light onto the wall's lip so it is
    outside the wall's occluder core.

### 10.2 Music as a generation and visual lever

The currently playing track is a third input alongside theme and wallpaper:

- **Analysis**: `AudioEffectSpectrumAnalyzer` on the music bus, 3 bands (bass
  60–250 Hz, mid 250–2 kHz, high 2–8 kHz) sampled every frame; a simple onset
  detector on bass gives a beat pulse; the band power feeds a short "now" average
  (1.5 s) and a long baseline (40 s), and *energy* (0–1) is the gap between them in dB:
  0.5 means "as loud as this track usually is", a breakdown falls, a drop rises.
  Tunables in `data/music/music_analysis.tres` (`MusicAnalysis`).
- **Why relative and not absolute.** Energy used to be an absolute 30 s RMS mapped over
  −42…−8 dBFS. Measured over five bundled radio tracks (band RMS extracted with ffmpeg and run
  through the same pipeline), that produced mean energies of 0.713, 0.712, 0.717, 0.715 and
  0.713 — a spread of 0.005 across a synthwave mix, a shanty and a punk track, because
  mastering normalises loudness and the window was wider than music ever gets. The lever was
  alive in the code and a constant in the game: enemy counts moved by well under a percent
  between tracks. The relative measure gives the same five tracks a 0.00–0.90 range, a
  per-track standard deviation of 0.11–0.20, and readings of 0.28–0.85 at the moments floors
  are actually generated. Any change to this chain has to be re-measured the same way, not
  eyeballed: the failure mode is a number that looks fine and never moves.
- **The track's mood, live (slow, never on the beat).** The owner's report after the
  generation levers landed was "I still see no difference when the song changes", and it was
  right: the levers only reach a floor when it is built, and the live vignette followed a
  *relative* energy that says "louder than this track usually is", which is 0.5 for every
  track on average and nothing at all under the headless Dummy driver. So each bundled track
  now has a **mood** of its own, measured offline once (`tools/analyze-radio.py` → 
  `data/music/track_moods.json`, read by `MusicMood`): loudness and treble share ranked across
  the set to 0..1 (`energy`, `brightness`; the calmest bundled track is exactly 0, the loudest
  exactly 1), a tempo, and a hue seed from the file name. A track not in the table (a fallback
  loop, a custom stream) gets a middling hashed mood, energy 0.35..0.65, so it can never be
  the calmest or loudest thing the dungeon has seen; silence is exactly neutral.
  `MusicMoodLevers` (`data/music/music_mood.tres`) turns a mood into a `MusicMoodState`, the
  look the screen is driven by, and `MusicReactiveLayer` (owned by the `Music` autoload) applies
  it while a run is live. The mapping, energy 0 → 1:
  - **Colour grade over every environment surface** (a `global uniform` pair read by
    `src/desktop/music_grade.gdshaderinc`, included by the palette-swap and surround shaders,
    so it reaches tiles, props, torches and the surround and never the player, enemies or HUD; the surround takes only the darkening side of it, per channel, so it is still never drawn brighter than `FloorRoot.void_color()` and every readability contrast stays a lower bound):
    intensity ×0.68 → ×1.26 on a dark theme (×0.82 → ×1.0 on a light one, which may only
    dim), ±0.04 more by brightness; chroma ×0.72 → ×1.30; every hue pulled up to 9.4° toward
    a cool blue (216°) → a warm amber (29°), the target leaned ±25° by the track's seed; at
    middling energy the pull fades out and the seed instead rotates every hue up to ±9.4°, so
    two steady tracks still colour the same room differently; and a temperature tint of
    chroma 0.05 at unit luminance. `MusicMoodState.grade()` is the GDScript reference for the
    shader, line for line, so the bounds are measured on colours, not eyeballed.

    The hue budget is **enforced at the end of the grade**, not hoped for
    (`MusicMoodState.hue_guarded`, mirrored in the shader include): whatever the chroma scaling,
    the tint and the clip to 0..1 did, a surface's hue comes back to within the mood's own
    bounded rotation of where the theme put it. The rotation was always bounded; nothing after
    it was, and on a *desaturated* surface — which a dungeon floor is, and a dark one since the
    darkness round — the tint turns a hue a long way, because there is little of the theme's own
    colour left for it to be small against. On the owner's green otter theme the room rendered
    #47424C, a blue-violet grey, where the same code with the slider at 0 rendered #927D54. The
    15° budget had only ever been measured on *authored* palette colours, which carry enough
    chroma that the same tint barely turns them, so it never saw this. The theme is the only
    colour authority (decisions log): music modulates light, warmth, intensity and chroma, and
    does not relocate a hue.
  - **Vignette** +0.20 → −0.10 alpha on top of the energy path; **haze** 0.16 → 0 alpha of a
    mist in the **room's own hue**, at chroma 0.10 capped by the floor's own, and at a luminance
    *derived from the floor the room is actually drawn at* — 1.7× it on a dark theme, where a
    mist lightens, and 0.5× on a light one, where it dims.
    The mist used to carry the mood's hue at chroma 0.35 and an absolute value of 0.75. That is
    a mist over the floor it was written against and **paint** over the darkness round's much
    darker one, and it is drawn as a full-rect `ColorRect` over the whole frame — outside the
    shader grade, and so outside the guard that holds the grade to the theme's budget. Measured
    on an exposed floor it drifted the owner's green otter theme 54.7° and nord 101°. Scattered
    light cannot be brighter than the room scattering it, and it is not the music's to colour:
    the mood sets how *thick* the mist is, the room decides what colour it is, and every
    temperature the mood wants goes through a path that has a bound on it — the tint inside the
    grade, and the lights, which get a much wider budget because a flame is not a surface. With
    that, the worst drift over 198 readings on seven palettes is 9.4°, which is the grade's own
    bounded rotation and nothing on top of it.
  - **Torches**: light energy ×0.70 → ×1.35, pool radius ×0.78 → ×1.28, flicker amplitude
    ×0.5 → ×1.6, and the light's colour turned on the hue circle by the *light's* own budget —
    `light_hue_pull`, 36°, against a surface's 9.4°. A surface is the desktop's theme and may
    only be tinted; a flame is fire, and one that goes from a cold rose under a brooding track
    to a deep amber under a fierce one is fire behaving like fire. Once the dungeon is lit in
    a few strong pockets rather than evenly, the colour and the width of those pockets are the
    largest coloured things on the screen, which is where the mood has to speak from: measured
    on tokyo-night, a torch burns 72° apart between the calmest and the loudest bundled track
    while the floor under it stays inside its 15° budget. The flicker itself is value noise along
    time (it was a 2.3 Hz sine per torch, which is a periodic brightness change by another
    name); `tests/unit/reactivity/music_live_mood_test.gd` checks it carries no peak at the
    old frequency. Everything a light source needs from the mood is published as one
    contract on the light profile — `DungeonLight.ambient_color()` (unit-luma temperature
    tint), `ambient_energy()` (×0.68 → ×1.26, ≤ 1 on a light theme), `torch_color(palette)`,
    `torch_energy_scale()`, `torch_radius_scale()` and `torch_flicker_amplitude()` — each
    already crossfaded and
    exactly neutral when the lights are off or the slider is at 0, so a lighting system reads
    six numbers and never the music module.
  - **Motes**: 18% → 100% of 48 ambient motes (dust; embers in the forge, snow in the frost,
    magic in the void), drawn by hand (`MusicMotes`) so their number can change by a slow
    fade per mote rather than a particle restart; they drift at 3–9 px/s and sway once every
    6–10 s, synced to nothing. Reduce-motion caps them at 8 and stops the drift.
  - **The live envelope — what the track is *doing***: the per-track mood above is the base, and
    it answers "which song is on". It does not answer "what is the song doing", and a look that
    is constant for four minutes is a look a player stops seeing — the owner's words were "it
    needs to change based on what is happening over the current track". So the layer also
    follows the track's own **envelope**: `Music.energy` (a slow relative loudness, 0.5 = "as
    loud as this track usually is") through two multi-second low-pass stages and then a hard
    cap of `MusicMoodLevers.live_rate` = 0.065 of the energy a second, offsetting the track's
    measured energy by up to `live_swing` = ±0.22. Everything the mood drives then breathes
    with it: the darkness, the pool radius and level, the torch colour, the motes.
    It follows the envelope and never the beat. The rate cap is not a smoothing — it makes a
    spike impossible to follow at all, so crossing the whole band takes about seven seconds
    whatever the music does. Measured on a synthetic 140 BPM track with a real mood set: the
    middle of the frame moves 40.9% between a quiet passage and a loud one, the worst
    frame-to-frame change is 0.00055 against a 0.0006 ceiling, and the luminance carries
    0.000009 at the beat frequency. It is a band, not a takeover: the calmest track at its
    loudest still lights the room less than the loudest track at its quietest, so which song is
    on stays visible underneath.
  - **Played order**: the shuffled playlist is then **spread by mood** (`RadioPlaylist.spread`):
    the next track is drawn at random from those at least 0.30 of the energy range from the
    current one, and from the furthest one left when nothing clears that. This is the fix for
    the complaint that survived every widening of the mapping above. The bundled moods are
    *ranks*, spread evenly over 0..1, so a plain shuffle deals adjacent energies at random: the
    mean step between two tracks a player actually hears in a row was 0.355 of the range and
    the tenth-percentile step 0.080 — nearly half of all track changes moved the look by less
    than a third of what the calm-versus-loud measurement promised, and one in ten by nothing
    at all. Spread takes those to 0.495 and 0.316, and the deal is still random rather than a
    march from calm to loud. A change nobody can see happening is a change nobody believes is
    there, and it is the *adjacent* pair a player sees twenty times a run.
  - **Track change**: the whole state crossfades over 4.5 s with a smoothstep — monotonic, still
    at both ends, a third of the way there inside the first second (3 s while the bands were
    narrower; the widened intensity band and the spread order put a 3 s smoothstep's steepest
    frame at 0.0049 against the 0.004 the anti-flash bound allows, so the duration moved and
    the bound did not). The now-playing banner
    names the cause: "Now playing: No Title Bar - Obstinatus (quiet, fast and bright)"
    (`MusicMood.words_line`, `Hud._on_track_changed`).
  - **Gameplay, a little**: the enemies of the *next room the player enters* get the current
    track's aggression multiplier (`MusicLevers.live_push` = 0.1: sight range and move speed
    ×0.9 → ×1.1, attack cooldown ÷ the same) once each, the moment that room wakes, never a
    boss, never an enemy already nudged, never mid-fight (`MusicManager._on_room_entered`).
  Measured (`tests/unit/audio/music_mood_test.gd`, tokyo-night): the worst hue drift of any
  coloured environment role under any bundled track is 9.4°, under the 15° the theme's
  identity is guaranteed to, and a grey role gains under 0.1 chroma; a torch burns 72° apart
  calm to loud, which is the budget a light gets and a surface does not. Middle of the frame
  across a calm-to-loud track change
  (`music_reactive_layer_test.gd`): +99.6% luminance, worst frame-to-frame change 0.0033,
  no reversal, settled at 4.5 s, and frame-for-frame identical with beats on the bus or
  none. Rendered evidence: `tools/run-scenario.sh music_moods` shoots the same room under the
  calmest, the loudest, and **the first two tracks of a real played order** — the pair a
  player hears in a row, which is the comparison the mood has to survive — and writes the
  measured luminance and hue around the player to `music_moods.txt`; `music_change` shoots
  the frames at 0, 1, 2, 3, 4 and 6 s after a calm→loud switch, asserts the luminance never
  falls between frames, and writes them side by side as `music_change_strip.png`.
  **It never pulses.** The first version lifted the vignette on every beat and laid a warm
  bloom over the frame with it, which is a brightness change at the tempo of the music for as
  long as a track plays — a photosensitivity risk, and the owner's report ("make sure it
  doesn't pulse — don't want to cause fits") rules it out. There is no beat path anywhere in
  this: the layer does not listen to `EventBus.music_beat`, the mood is a per-file constant
  that changes only with the track, the crossfade is a one-off smoothstep, and the relative
  energy still goes through two 2 s low-pass stages and a slew limit of 0.05 alpha/s
  (`MusicAnalysis.light_smoothing`, `light_slew`), so a kick drum cannot reach the screen.
  Measured (`music_reactive_layer_test.gd`, a synthetic 140 BPM track with a kick on every
  beat, 24 s at 60 Hz): worst frame-to-frame change in the middle of the frame 0.00034 of
  its luminance, amplitude at the beat frequency 0.000009 and at its harmonic 0.000002, while
  the light drifted 0.11 over the passage. The test asserts under 0.0006 a frame and under
  0.0004 at the beat, and under 0.004 a frame during a track change. Settings: *Music shapes
  the light (slow, never flashes)* (`music_lights`) switches it off; *How far the music moves
  the light* (`music_lights_amount`, 0–100%, default 100) scales every lever toward neutral,
  and at 0 the state is `MusicMoodState.neutral()` — the theme untouched, by construction
  (`test_the_amount_slider_at_zero_is_pure_theme`). Never affects hitboxes or tells.
- **Generation (per floor)**: the track playing when a floor is *generated* seeds
  `MusicProfile`, and `MusicLevers` (`data/music/music_levers.tres`) says how far each
  reading may move the floor. This is where the music's impact lives now that the screen
  will not flash: things a player notices over a floor, not a frame.
  - `energy` → enemy count ×0.7..1.3 (spawn points *and* the spawner's budget), prop
    density ×0.7..1.3, trap density ±0.3, the pack size of trap rooms ×1.4..0.6 (a calm
    track ambushes), the floor light ×0.6..1.4 (clamped to the wallpaper band, and a light
    theme keeps its pinned full light), room size ±0.15, and three runtime scalars every
    regular enemy on the floor is handed by `FloorPopulator` (`EnemyBase.set_mood`): sight
    range ×0.75..1.25, attack cooldown ×1.3..0.7, gold ×0.8..1.2. Bosses are left alone.
    Low energy is a quieter, darker floor with more traps and an ambush in its trap rooms;
    high energy is a brighter, busier floor with more enemies, keener and faster, and more
    loot. Silence reads as energy 0.5, and every pair straddles 1.0 there: a floor built with
    the radio off is the theme's own floor.
  - `tempo` (BPM estimate) → corridor wiggle, and room size (fast tracks tighten the rooms).
  - track-name hash → tie-break for room fill template choice, and the floor's *signature
    prop*: one of the biome's prop kinds, drawn for 40% of every room's props, so two tracks
    furnish the same biome differently at a glance.
  Measured (`tests/unit/reactivity/music_levers_test.gd`, nord, seed 771010, floor 5, energy
  0.1 vs 0.9 on the same track): spawn points 25 vs 32, traps 20 vs 10, props 23 vs 34,
  44.5% of tiles differing, light ×0.68 vs ×1.32, sight ×0.80 vs ×1.20, cooldown ×1.24 vs
  ×0.76. Same seed and same `MusicProfile` is still the same floor, and every lever is a
  `GenParams` field a save carries (`FloorRestore`).
  `energy` and `tempo` are read *live*, so they carry where in the track you were, not just
  which track it was: the same seed and the same playlist do not reproduce a floor plan.
  §5.1 says what a seed does and does not pin down; no UI may promise more than that.
- **Reported, per floor.** `MusicManager.profile()` is called exactly once per floor built, so
  it records a floor log (`floor_log()`: floor, title, artist, energy, tempo). Two things
  read it, because a lever nobody can see is indistinguishable from a lever that does not
  work. The HUD's floor banner is followed by the cause — "Built to Super Space - dense, fast
  and bright" (`MusicLevers.banner`, `Hud.announce_music`), or "Built in silence - a steady
  floor" — and the run summary carries a "Floors" section with one line per floor ("Floor 3
  - Rm -rf: dense, fast and bright, 26% more enemies, fewer traps"; `MusicLevers.floor_line`)
  under the build, plus its one-sentence calmest/loudest summary in the chrome. The
  percentage is the generator's own number.
  The floor log is per process: a run resumed after a relaunch reports only the floors played
  since (`restore_floor_log()` exists for whoever wires it into `RunState`).
- **Debug/capture levers** (user args): `--music-energy <0..1>` pins the energy,
  `--music-bpm <n>` pins the tempo the floor profile reports (and emits a metronome on the
  bus). The headless Dummy audio driver produces no spectrum at all, so without them a
  rendered check of what the music does to a floor photographs the silent floor and proves
  nothing. `tools/run-scenario.sh floor --music-energy 0.1 --music-bpm 140` against
  `--music-energy 0.9` is the pair to look at for the generation levers;
  `--music-track <file>` starts the playlist on a chosen bundled track for the live mood, and
  `Music.play_track_file(file)` does the same from a scenario or a test.
- **Track selection**: shuffled playlist per run; boss rooms pull from a boss subset;
  volume ducks 30% in chest UI. Radio order is preserved when "play in playlist
  order" is on.

---

## 11. UI / UX

- HUD: HP bar, potion, gold, active 1/2 with cooldown wedges, passive icons, floor,
  seed (small), minimap corner (rooms as squares, cleared/uncleared). The two text blocks
  (top-left resources, top-right floor/seed) sit on opaque `void` plates so they stay at
  4.5:1 wherever the camera is (§3.2).
- Build screen (`LoadoutScreen`): the one page that answers "what do I have right now" -
  class, both actives (cooldown, button, description), both passives, the innate, the weapon
  skill, every gear slot with the item's lines, and the stat sheet with where each number
  comes from (class, orbs, each item and passive by name). Opened with Tab / pad Back from
  the run, and embedded as the pause menu's Build tab; the run seed lives in its footer.
- Pause: Build (the screen above), Controls, Settings, abandon run.
- Chest UI: 3 cards, big, gamepad-navigable, reroll button. An offer that displaces something
  opens the **compare screen** (`CompareView`) before it is taken: yours on the left, new on
  the right, every stat line of both on the same row, coloured and marked by direction, the
  unique effect in full. It never elides - a tall table closes its row gap and then scrolls.
  A (Swap) / B (Keep mine) on a pad, buttons of the same names for a mouse.
- Ground drops: a name tag over the item while near it; the compare card only while standing
  on it - on the left edge, in the band between the HP block and the ability bar, so it is
  beside the player and never over them, at most a quarter of the frame, one column carrying
  every stat row of the trade (a pickup equips at once, so the card is the whole comparison).
- Minimap: 96x64 in the corner; a room you have stood next to and not entered is a dashed
  outline, and a strip under the map counts what the floor still holds ("2 rooms left, 1 item
  on the floor"). The stairs say "Descend" and never hold a descent back.
- Title: class select with art card + stat bars; theme name shown ("Dungeon of
  *Catppuccin*"); seed entry with a caption naming the live theme and the other generation
  inputs, so it is obvious that a seed fixes the rolls rather than the dungeon (§5.1);
  unlocks; settings.
- Settings: video (window/fullscreen, vsync, scaling, screen shake, damage numbers),
  audio (3 sliders, explicit-track filter, beat-reactive lights, lyrics toggle),
  input (rebind, deadzones, rumble), accessibility (colour-blind overlay glyphs on
  rarity/status, reduced flash, hold→toggle), gameplay (wallpaper influence on/off;
  theme integration is always on).
- Fonts: m5x7 / m3x6 (free bitmap fonts) or Kenney Pixel. All UI uses `fg`/`accent`.

---

## 12. Meta-progression & Persistence

- **Unlocks** (content and options only, never stat boosts). A new profile has the **Fighter
  and nothing else**; the other three classes and five abilities are earned. The table is data
  (`data/progression/unlocks.tres`, `UnlockTable`), the set of gated ids is
  `Profile.GATED_UNLOCKS`, and `SaveManager` evaluates it — a gate with no rule, or a rule on a
  counter nothing increments, is content nobody can reach, so both are asserted
  (`tests/unit/save/unlock_table_test.gd`).

  | Unlock | Kind | Earned by |
  |--------|------|-----------|
  | The Ranger | class | clear a floor |
  | The Wizard | class | 120 lifetime kills |
  | The Oligarch | class | clear three floors in one run |
  | Tiling WM | ability | clear a floor without taking a hit |
  | Whirlwind | ability | 50 clowns |
  | Reboot | ability | 50 greybeards |
  | rm -rf | ability | 50 tinkerers |
  | Lucky Coin | ability | 1000 gold across all runs |

  The ladder is deliberately front-loaded: the first class lands inside the first run or two,
  so a new player is *shown* that runs are worth something before being asked to grind for
  anything.
- **Where the player sees it.** Class select: locked cards carry a padlock, selecting one
  states the achievement and the count on the hint line, and **Down** opens the unlock board —
  every gated class and ability, what earns it, and how close, locked-and-closest first. The
  run summary names what the run unlocked, what is next, and how far the run moved it
  ("Next: The Ranger — Clear a floor. 0 / 1"). `SaveManager.progress_rows()` /
  `unlocks_this_run()` / `counter_gains_this_run()` are the API both read.
- **Migration.** `Profile.VERSION` 2 gates the Ranger and the Wizard, which v1 handed to
  everybody; `_migrate_1_to_2` grants both to any existing profile. A meta-progression change
  never takes a class away from somebody who has been playing it.
- **Stats page**: runs, wins, best floor per class, per-theme win counts ("Gruvbox:
  3 wins").
- **Save data**: `$XDG_DATA_HOME/omadungeon/` (`profile.json`, `settings.json`).
  Atomic writes. Version field for migration.
- **Run persistence**: quitting is always resumable. `run.json` is written atomically
  on every floor transition, every room clear, and on quit (pause → *Save & Quit*).
  Resume restores floor layout (from seed + recorded `gen_params` + gen RNG state, so a theme
  change between sessions cannot reshape the floor under you), cleared-room set, player
  stats/gear/abilities, gold, potion, HP, and current room; mid-fight state is not
  saved (resume puts you at the door of the room you were in, enemies reset).
  A separate **Abandon Run** button (pause menu, red, confirmation) deletes `run.json`
  and records the run as a loss. Title screen shows *Continue* when `run.json` exists.
  Theme is re-read on resume, so a run saved under Gruvbox resumes looking like Nord if
  you switched (§3.5).
- **Resume never pays twice.** "Enemies reset" is about *state*, not about *loot*: a
  resumed floor may not sell the player anything they have already been paid for. The
  drops a resume keeps on the floor are the ones nobody picked up; everything already
  banked stays banked, and the thing that produced it does not come back to produce it
  again. Concretely, `run.json` also carries, per floor: the tiles whose breakable prop is
  smashed (`broken_prop_tiles` — prop gold is rolled from a (seed, tile, floor) stream, so
  a rebuilt barrel would pay the *same* coins forever), the tiles whose mimic chest is
  sprung (`revealed_mimic_tiles`), and the enemies already killed in a room that never
  finished clearing (`defeated_spawns`). The pack of such a room still comes back — at full
  HP, at its spawn tiles, as this section promises — but one enemy is dropped from it per
  enemy already killed there, so a room can never pay out more than the pack it was
  generated with. This costs an honest player nothing: someone who simply quits and comes
  back keeps the progress they made instead of re-fighting it, and a room entered but never
  fought in comes back whole. Each room draws its pack from its own (floor spawn seed, room
  id) stream for the same reason props do, so continuing a run cannot re-roll the rooms
  still standing either.
- **A reward is not spent until it is taken.** A chest opens its lid when the player
  presses the key, but the offer it raises may still be unanswered when a save is written
  (the autosave a room clear queues runs while the picker is up — the tree is paused,
  `SaveManager` is not). Such a save records the chest as *still owed*
  (`chest_offer_room_id`) and the resume re-opens the picker, the same way the mandatory
  opening passive pick is carried by `starting_passive_pending`. Nothing the player has not
  actually answered for is ever marked spent.

---

## 13. Technical Architecture

### 13.1 Stack
- Godot 4.7.1 stable, GDScript with static typing everywhere (`--warnings-as-errors`
  style: untyped declaration warnings elevated to errors in project settings).
- Renderer: `gl_compatibility` (broad Linux GPU/driver support, lowest input latency)
  with option to use Forward+ later.
- Export: Linux x86_64 only. Distribution: tarball + AppImage; AUR `omadungeon`
  package (Omarchy is Arch-based). `.desktop` file, icon, `omadungeon` launcher.
- Wayland native (`display/display_server/driver=wayland`), X11 fallback only if
  Godot cannot init Wayland.

### 13.2 Project layout

```
omadungeon/
├── project.godot
├── docs/                    GDD, credits, testing, architecture notes
├── addons/gdUnit4/          test framework (vendored)
├── src/
│   ├── core/                Autoloads: GameState, RunManager, EventBus, Rng, Theme
│   ├── desktop/             OmarchyState, OtterWallpaper, ColorsToml resolver, DesktopWatcher,
│   │                        WallpaperAnalyzer, ThemePalette, ThemeProfile, palette shader
│   ├── music/               RadioPlaylist (bundled playlist.json), MusicAnalyzer, MusicProfile
│   ├── gen/                 Graph, Layout, Corridors, RoomFiller, Validator, Biome data
│   ├── player/              Player, Controller input, Classes (resources)
│   ├── combat/              Damage, Hitbox/Hurtbox, StatusEffect, Projectile
│   ├── entities/enemies/    Base enemy, factions, behaviours (state machines), bosses
│   ├── items/               ItemGenerator, affixes, base types, ProcSprite
│   ├── abilities/           Ability resources, actives, passives, slot manager
│   ├── traps/
│   ├── rooms/               Room scene, door, chest, altar, shop, shrine
│   ├── ui/                  HUD, menus, chest cards, settings, input glyphs
│   └── audio/
├── assets/                  sprites (indexed ramp), tiles, fonts, sfx, music
├── data/                    .tres resources: enemies, items, abilities, biomes, rooms
├── tests/                   unit + integration tests (gdUnit4), headless
├── tools/                   scripts: run headless tests, headless sway launcher, asset import
└── export_presets.cfg
```

### 13.3 Key systems / patterns
- **EventBus** autoload with typed signals (`enemy_died`, `room_cleared`, `item_equipped`,
  `stat_changed`…). Systems subscribe; no cross-node reaching.
- **Resources** for all content (`EnemyDef`, `ItemBase`, `Affix`, `Ability`, `Biome`,
  `RoomTemplate`); content is data, code is behaviour.
- **Deterministic RNG**: one `RandomNumberGenerator` per subsystem, derived from the run
  seed (`gen`, `loot`, `combat`, `ai`) so gen is reproducible regardless of fight RNG.
- **Enemy AI**: small hand-written state machines (`Idle → Approach → Windup → Attack →
  Recover`), behaviours as composable resources; navigation via `NavigationServer2D`
  with per-room nav regions baked at gen time.
- **Palette shader** applied via a single `ShaderMaterial` per sprite category;
  colours pushed as uniforms once per theme load.
- **Stat system**: `Stats` object with base + additive + multiplicative layers,
  recomputed on change; all modifiers are tagged for removal (item id / ability id).

### 13.4 Quality bar
- Static typing, no `Variant` leaks in gameplay code; `class_name` on every script.
- gdlint/gdformat (from `gdtoolkit`) in pre-commit; CI runs format check + tests.
- No `get_node("../../..")`; use exported NodePaths, `%UniqueNames`, or signals.
- Every generator function is pure given RNG + params and covered by tests.
- Performance budget: the **CPU/simulation** cost of 200 projectiles + 40 enemies must fit
  in a 60 fps frame — average and 95th-percentile script frame under 16.67 ms, worst under
  50 ms (`data/perf/benchmark.tres`). `PerfBench` measures exactly that and no more: it runs
  headless, so **rendering is not in the measurement**, and neither is the physics server's
  own step. There is no GPU number here and the doc used to claim one ("on integrated GPU");
  nothing this project can run measures it — the nested-sway harness and the VM both
  rasterise on llvmpipe, which would be a claim about a software rasteriser, not about
  integrated graphics. Treat the budget as a necessary condition, not a sufficient one.

---

## 14. Testing Strategy (headless, never the main session)

Hard rule: nothing the tests or dev loop do may touch the user's active Wayland
session. Two layers:

1. **Logic tests — `godot --headless`.** gdUnit4 unit/integration tests for gen,
   items, stats, abilities, theme parsing, save/load. Fast, run on every change:
   `tools/test.sh` → `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/`.
2. **Rendered / input tests — nested headless sway.** `tools/headless-sway.sh` starts
   `WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 sway -c tools/sway-headless.conf`
   with its own `WAYLAND_DISPLAY=wayland-omadungeon-test` and XDG_RUNTIME_DIR subdir,
   then launches the game inside it with `--test-scenario <name>`. Scenarios drive
   input via `Input.parse_input_event` and capture frames with
   `get_viewport().get_texture().get_image().save_png()` to `tests/out/`. Used for
   smoke tests (boot, theme swap, class select, one room fight, chest UI), screenshot
   regression, and controller mapping checks (virtual joypad events).
   Screenshots are also how the assistant *sees* the game during development.
3. **Theme fixtures**: `tests/fixtures/omarchy/state/current/{theme,theme.name,
   background}` mirrors of the real Omarchy state dir for a handful of upstream themes
   (tokyo-night, gruvbox, catppuccin, catppuccin-latte, nord, white). Tests set
   `OMADUNGEON_OMARCHY_STATE_DIR` to a fixture. A fixture-mutation test flips the
   `theme` symlink mid-run and asserts the live retint (§3.5).
3b. **Real Omarchy in a VM** (integration, manual/nightly): QEMU/KVM directly — no
   libvirt, no `virsh`. `tools/vm/create.sh` performs Omarchy's own unattended install
   from the ISO onto a disk image (`-display none`, VNC bound to `127.0.0.1:5999`, SSH
   on `127.0.0.1:2222`), `install-game.sh` unpacks the shipped `.deb` payload with
   `bsdtar` (Omarchy is Arch; there is no dpkg on it), `game.sh` drives the game inside
   the guest's real Hyprland and `shot.sh` brings `grim` captures back to
   `tests/out/vm/`. The live-retint proof is `tools/vm/verify.sh`, which switches the
   machine's real theme with `omarchy-theme-set`, advances the wallpaper with
   `omarchy-theme-bg-next`, and asserts three things *from the outside*, because the
   game exposes no debug endpoint: the capture after each switch shows that theme (the
   title screen prints "Dungeon of \<theme\>"), the game's pid never changes across the
   switches, and the game process's environment carries no
   `OMADUNGEON_OMARCHY_STATE_DIR` while the machine holds no `tests/fixtures/omarchy`
   tree — which leaves `~/.local/state/omarchy/current/` as the only thing it can have
   read. Never touches the host Wayland session. Full runbook: docs/TESTING.md tier 3.
4. **Gen fuzz**: 1,000 seeds × each theme fixture; every layout must validate (§5.1 #7).
5. **Determinism test**: same seed and same generation inputs (theme profile, wallpaper
   analysis, track) twice → identical layout hash. The companion test is the opposite one:
   the same seed under two different theme fixtures must *not* produce the same layout hash,
   because the theme is a generation input by design (§5.1).

Debug flags the build actually reads (`GameState._parse_cli_args`, after `--`):
`--theme-state <dir>` (point `Desktop` at a fixture state dir), `--test-scenario <name>`,
`--scenario-floor N`, `--scenario-archetype <id>` (lay every floor of the capture to one
`FloorArchetype`), `--scenario-arena entry|engaged` (walk the `floor` capture into the boss
arena, `ArenaCapture`), `--starting-passive`, `--screenshot-dir <dir>`,
`--screenshot-suffix <s>`, `--quit-by request|self-close|wm-close` (which exit the `quit`
scenario measures: asking `QuitGuard`, handing the root the window manager's close request, or
waiting for a real one - `tools/check-quit.sh`), `--only <screen>` and `--hold` (the UI gallery).
`tests/unit/tools/debug_flags_test.gd` pins this list to the flags the source reads, in
both directions, so it cannot rot again.

**Not implemented** (listed here as intent, not behaviour): `--seed N`, `--floor N`,
`--class X`, `--god`, `--screenshot-every N`, `--debug-http PORT`, `--no-music`. A run is
seeded and a floor is reached through the scenario driver and the test suites instead;
`--debug-http` in particular never existed, which is why 3b above asserts the retint from
outside the process.

---

## 15. Milestones

| M | Deliverable | Definition of done |
|---|-------------|--------------------|
| 0 | Skeleton | Project, autoloads, colors.toml resolver + fallback, DesktopWatcher live retint, palette shader, headless test tooling, CI green |
| 1 | Walk & fight | Player (Fighter), one room, 2 enemies, doors lock/unlock, chest with stat orbs, KB+M + controller |
| 2 | Floors | Full gen pipeline, stairs, Crypt biome, traps, minimap, seed display |
| 3 | Build | Items generator + equip UI, abilities (10 actives, 12 passives), all 4 classes |
| 4 | Content | 3 factions (12 enemies + 4 elites), 3 biomes, 3 bosses, shop/altar/shrine |
| 5 | Polish | Theme → gen params, wallpaper (both engines), music lever, settings, accessibility, unlocks, packaging (AppImage + AUR) |

Each milestone ends with headless smoke tests + screenshots reviewed.

---

## 16. Decisions log

| # | Question | Decision |
|---|----------|----------|
| 1 | Theme source | `colors.toml` only (guaranteed in all upstream themes); resolver mirrors `omarchy-theme-color`. Real-Omarchy testing in a libvirt VM (§14.3b). |
| 2 | Wallpaper | Omarchy shell symlink + otter-wallpaper state file; analysis → props/ambient/seed tie-break. |
| 3 | Quit | Resumable at room granularity; separate Abandon Run. |
| 4 | Art | Environment-only tinting; per-room palette variants for variety; live retint on change, always. |
| 5 | Music | Omarchy Radio bundled with full credits (repo has no licence; same-universe use accepted by owner); spectrum/energy → visuals + gen lever. |
| 6 | Metaprogression | Start with the Fighter only; the other three classes and a set of abilities are earned through named achievements. Unlocks are content and options, never raw power. Owner's direction, 2026-09-12. |
| 7 | Enemy health bars | Revealed when an enemy takes damage, then fading, rather than always on screen. Confirmed by the owner after play, 2026-09-12: do not change this to always-visible. |
| 8 | otter-shell naming | otter-shell support stays fully functional but silent: no "otter-shell" or internal source labels in player-facing text. When the palette derives from otter-shell the theme is shown simply as "Otter" ("Dungeon of Otter"). Omarchy wording is welcome everywhere. Owner's direction, 2026-09-13. |
| 9 | Comparison and build UI | A comparison is one table with both sides on every row and is never elided (compact, then scroll). One build screen (Tab / pad Back, also the pause menu's Build tab) is the source of "what I have"; the pause menu's separate Stats / Equipment / Abilities pages are gone. Ground-drop tooltips are a tag near the item and a left-edge card, beside the player, only while standing on it, capped at a quarter of the frame and carrying every row. Settings rows are data in `SettingsRows` so any module can add one. The stairs never intercept a descent; the minimap carries the "rooms left" count and marks skipped rooms. Owner's round-5 report, 2026-09-13. |
| 9 | Floor variety and curation | Owner's playtest of 2026-09-13 (#4 "no real map or room variety", #5 "not every type of room should be on every floor", #6 "bosses should not stand in the doorway"): five floor archetypes rolled per floor (§5.1 #1), shaped rooms and a wider size table (§5.1 #2), dressed corridors (§5.1 #3), the per-floor room budget table (§5.1 #4) replacing "1 Altar, 1 Shop or Shrine on every floor", and the far-side dormant boss with a deep trigger (§7.4). The theme levers keep their measured character (§3.3); the archetype roll is tilted by them, never fixed by them. |
| 9 | The exit is a check | A game that sometimes refuses to exit ships nowhere. Measured 2026-09-13: 1 capture in 12-24 under load never came down after its PNG, every one stuck in `pthread_join` on Godot 4.7.1's "Wayland Events" thread with that thread in an infinite `poll` (`WaylandThread::destroy` races its own reader; not reproducible headless, 0 of 40). Render silence before the quit did not help (3 in 40): the race is inside the engine's own teardown. Every exit now goes through `QuitGuard`, which arms a detached watchdog (SIGTERM 4 s after the request if the process is still alive) and then calls `quit()`; a hung engine ends with 143, which the harnesses accept and name. `tools/check-quit.sh` (register `quit-time`, `quit-time-rendered`) fails when the process is still alive 5 s after the request. Re-measured 2026-09-14 with core dumps rather than a live attach: 11 wedged in 120 rendered captures under load, all six sampled identical (main thread joining the "Wayland Events" thread, that thread in `poll`), the *title screen* wedges too, and the watchdog ended every one of the 11 at 4.0-4.1 s. The same round found a second, deterministic exit bug: the window manager's close request was answered only by `Main`, which `RunManager.new_run()` frees, so from the first floor onwards closing the window did nothing at all. It is the `Quit` autoload's job now (`src/core/quit_service.gd`), with `quit-close` and `quit-close-rendered` measuring it. |
| 9 | Lantern anchors | The generator, not the rooms module, says where a lantern may hang (§5.1 #8, `FloorData.lantern_anchors`): wall tiles along wall runs at a per-biome spacing, never in or beside a doorway, deterministic per seed. The lighting system reads the list; it never derives its own from the tiles, so a floor's lights are as reproducible as its layout. 2026-09-13. |
| 9 | Clutter | Third round of "clutter makes little sense": the 27-kind procedurally shaded catalogue is replaced by hand-drawn pixel maps with designed silhouettes (no grammar, no noise, no third-party art), a hard visual rule (solid = ink outline + contact shadow + occluder, flat = no ink and no collider) and wall-cluster placement with the middle of the room kept open. Fourth pass trimmed it to 9 kinds a biome (cobweb, furnace, ice patch, pages and glitch cut: each read as another kind's texture) and redrew cart, desk, floater and bones; the remaining mid-room "confetti" turned out to be the decorated *floor tiles* (a skull, a candle, a jar drawn on one tile in eight), redrawn as surface marks in `tools/art/tiles.py`. Owner's finding, 2026-09-13. |
| 10 | Music, live | Per-track moods measured offline (`tools/analyze-radio.py`), applied live as a bounded colour grade + vignette/haze/torch/mote levers with a 3 s monotonic crossfade on track change; theme hue kept within 15°, calm-vs-loud ≥ 25% luminance and ≥ 20° apart; slider to 0 is pure theme; a ±10% aggression nudge on the next room only. No beat path, ever. Owner's report "I still see no difference when the song changes", 2026-09-13. |
| 11 | Lighting | A dynamic layer on top of the palette exposure model, never instead of it: darkness x0.72 dark / x0.92 light, a lantern on every generator anchor in the biome's own fixture and the theme's role colour, merged wall occluders with the nearest 8 lights casting, unexplored rooms shaded 12%, and every gameplay light (swing, shot, spell, explosion, chest, fixture) a row of a data table resolved through the theme and the music contract. Quality Off is the previous look, byte for byte in intent. The mood moves the darkness by half its energy, slewed; nothing pulses. The darkness is a flat MIX-toward-black point light and is what the light masks split: bodies sit under `ambient ^ 0.5` (dark) / `^ 1.5` (light) of it, tells under none. A *pool* is never split - any light that reaches a body reaches it with the pool it puts on the floor beside it, one light on `LIT_MASK`, lanterns and standing emitters included. Two lights at different energies is precisely what a readable-prop failure looked like (`prop_frame`, the void sack beside a lantern, 2.10 against 2.2). Loot is guarded against the surfaces *as drawn* and carries a one-pixel ring where one ink cannot clear them all (`LootInk`); every gameplay light is turned down to 0.25 on a light theme, because paper has no headroom for an additive pool, and `lighting_frame` holds a pixel ceiling at 0.90 so that cannot drift back. Measured on llvmpipe at 1440x810: High costs 5-7 ms a frame over Off (tokyo-night 4.6 -> 11.7 ms avg); under half a millisecond on a real GPU. 2026-09-14. Owner's request "proper dynamic lighting with shadows, darkness, light casting from lanterns... make sure it works with the theme stuff and the music stuff", 2026-09-13. |
| 12 | The theme is the colours | Owner, 2026-09-14, on a sage-green otter-shell desktop rendering an orange dungeon: *"otter colors are already derrived from the wallpaper - I think in general we should not be taking colors from the wallpaper that was not what the wallpaper looking at was for it was to add another cool factor to the seeding of the dungeon and the generation it should impact that and then the theme should be the colors"*. The palette — Omarchy's `colors.toml`, or otter-shell's twelve keys when otter is the source — is the **sole** colour authority for the dungeon. The wallpaper cast is gone, not reduced: `derive_environment` no longer takes a wallpaper, there is no `wallpaper_cast`, and no dominant colour enters the prop pool or `floor_alt`. It was a genuine double-dip — an otter palette *is* that wallpaper already reduced to twelve colours, so casting the picture over it again applied one image twice, and because the cast took the picture's single most saturated patch as "the wallpaper's hue", a green-grey photograph with one warm-brown roof in it painted the room orange. The wallpaper stays a **generation** lever and grew two new ones to replace what it lost: `hue_spread` (chroma-weighted circular variance of the dominant hues) offsets `room_size_bias` and tilts the archetype roll toward irregular plans, `colour_energy` (mean chroma) offsets `trap_density`, on top of the existing edge-density → prop-density, path-hash → fill tie-break and top-third-luminance → ambient. A second defect surfaced under the same fixture and is fixed with it: the "does this surface have a hue of its own" test was HSV saturation, which a near-black lies about — otter's `#0F0F0D` background reports 13% saturation from two 8-bit steps of green over blue, and the exposure then lifted that rounding error to the floor's luminance and painted a third of the frame in it. It is absolute chroma now (`ROOM_CAST_OWN_CHROMA_MIN`, measured before the exposure), and the theme-wide cast hue is weighted by absolute chroma too, so only colours that have a hue vote on one. That moved the owner's room from 61° to 76.5° against a sage accent at 83.7°. The same rule then applies one layer down, in the per-room ramp variants: `TileRamp`'s `WARM_COOL` lerped the room's surfaces toward the theme's `heat` or `cold`, and a lerp toward a colour is a hue rotation — measured on the owner's palette it swung the floor from 75° to 51° and the wall cap from 77° to 27°, so roughly one room in seven rendered tan. It is `TileRamp.temper` now, which takes the mix's chroma and light and keeps the rung's own hue, so a warm room is still a different room and never a different theme. The biome itself was already hue-neutral on the room surfaces (measured at 0°); it picks which of the theme's keys become prop accents, which is what keeps the five biomes apart (`BiomeTintTest`). Guarded by `OtterThemeFidelityTest` (the owner's exact machine: a violently orange wallpaper leaves the palette byte-identical to the same theme with no wallpaper) and `WallpaperLeversTest` (two wallpapers, one seed, different floors — so the lever is alive rather than quietly dropped). Also confirmed in the same exchange: otter-shell is not available on Omarchy yet, so **otter present with no `~/.local/state/omarchy` is a normal supported configuration**, not a broken one. |

Remaining open items:
- Scope trim candidates if needed: Oligarch hireling, Mime invisible walls, procedural sprites, video-wallpaper glitch mode.
