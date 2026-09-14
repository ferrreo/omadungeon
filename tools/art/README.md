# Art pipeline

Every PNG under `assets/sprites/`, `assets/tiles/` is generated here; never hand-edit them.

```
python3 tools/art/gen_all.py [--sheets]     # regenerate all assets (deterministic)
python3 tools/art/contact_sheet.py <png> [name] [cell]   # 4x review image -> tests/out/art_<name>.png
python3 tools/art/grammar_sheet.py [biome]   # clutter vs hazard vs reward, in colour and in value
python3 tools/art/fetch_fonts.py            # download the OFL fonts into assets/fonts
```

Needs Pillow: `uv run --with pillow python3 tools/art/gen_all.py` if it is not installed.

| Module | Output |
|--------|--------|
| `toolkit.py` | `Canvas` (RGBA buffer + primitives, mirror/outline/dither/scale/rotate), `Sheet`, ramp, micro font, frame helpers |
| `tiles.py` | `assets/tiles/<biome>.png` (see `assets/tiles/README.md`) |
| `characters.py` | `assets/sprites/player/<class>.png` + `<class>_portrait.png`. No class map draws a weapon: the only weapon on screen is the equipped one, drawn at the grip anchor (`tests/unit/player/class_art_test.gd`). The Fighter's shield is shape-checked by `_assert_shield`. |
| `enemies.py` | `assets/sprites/enemies/<id>.png` |
| `props.py` | chest, biome props, pickups, projectiles, trap strips (incl. `pit`, `mimic_chest`, `arrow`), fx particles, `hazard_frame` |
| `prop_maps.py` | the biome props' pixel maps (data only; `props.py` draws them). Nine a biome, four shared; the five drawing rules are at the top of the file, and `props.review_sheet` writes `tests/out/art_props_all.png` for judging them |
| `items.py` | `assets/sprites/items/weapons.png`, `armor.png` |
| `ui.py` | ability icons, input glyphs, HUD icons, cursor, logo |
| `grammar_sheet.py` | review sheet: the three world-art classes side by side, colour and greyscale |

Derived animation frames come from `toolkit.py`: `bob_frames` (idle, via `hover`),
`hurt_frames` (posed recoil + hot rim — the *flash* is added in code by `Player._flash` and
`EnemyBase`, so the art must keep its colours), `collapse_death` (impact flash -> squash ->
collapse -> dissolve) and `rim` (telegraph glow used by the enemy windup row). Keep new
frames derived so a pixel-map edit updates every row.

`hover(canvas, dy)` is the only way to move a sprite vertically: 16x16 body maps touch both
row 0 and row 15, so a plain `shift` would clip the head or the soles and the silhouette
flickers. It translates only when there is free margin, otherwise it sinks the body and
keeps the feet planted.

## Orders that other modules depend on

These are contracts, not preferences — the generator writes them to JSON and
`tests/unit/art/art_assets_test.gd` compares them against the game data:

| File | Pins |
|------|------|
| `prop_kinds.json` | prop atlas column order per biome == `Prop.KINDS` == `Biome.prop_kinds` == `rooms_content.tres` (`Prop.KIND_COUNT` = 10 a biome, the four `Prop.SHARED` kinds first) |
| `prop_solid.json` | which kinds are solid == `Prop.SOLID` == `prop_solid` in `rooms_content.tres`; a solid wears ink and a contact shadow, a flat wears neither (`props._assert_recipe`) |
| `item_cells.json` | `weapons.png` / `armor.png` cell order == the `AtlasTexture` regions in `data/items/*.tres`. Cells 0-11 are also the ones `WeaponController.ATLAS_INDEX` draws in the hand; 12-19 are inventory icons only, added so no two weapons share a card. |

`ui.py::ABILITY_ICONS` must stay aligned with `AbilityRegistry.ICON_ORDER`, `GLYPHS` with
`InputGlyphs.Cell` and `ICONS` with `UiTheme.Icon`. `ui.py::WEAPON_SKILL_ICONS` follows
`ABILITY_ICONS` on the same sheet and is pinned by the `region` in each
`data/items/skills/<id>.tres`; the collision check runs over the union of the two, because a
skill and an active share the HUD row.

Three rules the generator enforces on itself, so a bad asset cannot reach the repository at
all (the first two are also asserted on the shipped PNGs by
`tests/unit/rooms/art_grammar_test.gd`, the third by `tests/unit/player/class_art_test.gd`):

* **The world grammar.** `props.py::_assert_inset` refuses a prop that paints the tile's
  border ring, and `props.py::hazard_frame` stamps every trap that is not one of the two
  deliberate disguises. See "Reading the world at a glance" in `assets/tiles/README.md` for
  what the grammar is and why coverage rather than colour carries it.
* **Icon separation.** `ui.py::icon_collisions` refuses to write `ability_icons.png` while
  any two ability icons have both nearly the same shape (motif overlap >=
  `ICON_SHAPE_OVERLAP`) and nearly the same colours (mean channel difference <=
  `ICON_COLOUR_DISTANCE`). Either alone is fine - a red bolt and a blue bolt are told apart
  instantly - but both together is one icon wearing two names. When you add an ability,
  re-run the generator and it will name the clash.
* **The Fighter's off-hand gear is a shield.** `characters.py::_assert_shield` refuses a
  fighter sheet whose gear box (x 0-5, y 8-12 of the idle cell) does not taper to a point,
  is widest below its middle, draws fewer than four colours besides the outline, or is painted
  in the helm crest's own colour. The palette half alone is not enough: the block that shipped
  as "a red box" passed a recolour and stayed a box.

Environment art (tiles + `props/<biome>.png`) is restricted to the eight authoring-ramp
colours, and each index carries a fixed theme role (see `assets/tiles/README.md`): floors
must be index 3, wall faces index 2, wall caps index 5. The logo is baked from pixel maps in
`ui.py` (no FreeType) so re-running the generator is byte-identical on any machine.

Characters and enemies are explicit pixel maps (strings of palette keys, one char per pixel)
for the idle key frame; every other frame is derived (bob, leg-pose swap, squash/stretch,
flash, rotate-and-fade). Add a new enemy by adding an `EnemySpec` to `enemies.py`.
