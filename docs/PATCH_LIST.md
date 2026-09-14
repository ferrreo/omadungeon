# Patch list

Everything three release judges raised that was not fixed before sign-off, in the order a
first patch should take it. Nothing here loses player progress, breaks a mechanic, or makes
the release gate untrustworthy — those were the bar for shipping, and they are all closed.

Each item names what a judge measured, not a guess. Where a judge proposed a fix, it is kept.

## Economy

1. **A mimic chest is recorded as spent the moment it is sprung, not when the enemy it becomes
   is dealt with.** Spring a mimic, quit before killing it, and the fight is gone while the
   chest stays consumed. Record it against the enemy's death instead.
   `src/rooms/floor_root.gd`, `_on_mimic_revealed`.
2. **The Oligarch's buyout price can fall below the chest skip bonus on later floors.** Opening
   costs `12 + 2 x floor` while skipping pays `10 + 3 x floor`, so from the mid run onward the
   class that pays to open chests can make money by opening and skipping. Make the open price
   outgrow the skip bonus, or cap the skip bonus for that class.
3. **A breakable prop rebuilds whole on resume and re-rolls the same deterministic gold.**
   Measured at roughly thirteen gold per reload on floor one. Needs a broken-tile list in the
   floor block and a `restore_broken()` that does not re-drop. `src/rooms/prop.gd`,
   `src/rooms/floor_root.gd`.
4. **A gremlin whose theft failed still drops a stat orb.** The bite path treats its helper's
   return value as a success test when it is not, so a failed steal pays out anyway.
   `src/entities/enemies/tinkerers/config_gremlin.gd`, `_on_bite`.

## Persistence

5. **An unanswered offer board only reaches the disk on the next scheduled autosave.** Opening
   a board does not request one, so a crash between opening and the next autosave loses the
   board. Queue an autosave when a board opens.
6. **No test pins a rolled curse to its board across a resume.** The curse survives as an
   ability id and is re-instanced, which is correct, but nothing would catch it regressing.

## Interface

7. **Destructive buttons lose their danger colour on some palettes.** The danger button style is
   built from the raw palette role rather than the contrast-guarded one, so on a low-contrast
   theme "Abandon Run" reads like any other button. `src/ui/ui_theme.gd`, `_write`.

## Tooling

8. **The test harness deletes the sandbox lock it just claimed.** The claim is written and the
   next line runs a mirroring copy that removes it. Harmless today because the sweep falls back
   to checking the process, but the lock is doing nothing. `tools/test.sh`.
9. **A scenario run can exit 2 under heavy load with nothing printed.** It should say which
   scenario was skipped and why. `tools/run-scenario.sh`.
10. **Captures accumulate in the output directory.** A review can compare two images taken hours
    apart without noticing. Stamp or clear per run.
11. **Root-cause the "resources still in use at exit" line.** Several modules deliberately cache
    a resource in a static variable, which outlives the resource system, so the engine reports
    it on every clean shutdown. The package smoke test now allows exactly that one line and
    nothing else. Either release the caches on exit or confirm the pattern is intended and
    document it.

## Balance instrument

12. **The simulated player never quits.** The offer policy answers every board it is shown, so
    no simulated number reflects a player who walks away from an offer, which is exactly the
    behaviour the economy exploits above depend on. Teach it to leave.

## Documentation

13. **The design document's section 12 still describes the old reward contract.** It names the
    two fields that predate offer-board persistence and should describe boards.
14. **The design document's status line still says draft.** It is the document the readme points
    contributors at.

## Checks and the gate (found this round, deliberately not fixed here)

15. **Closed: the red flag is no longer a field anybody can clear.** This entry used to read
    "`prop-frame` is red and the gate is red with it", with the failure recorded as
    `prop-frame.known_failing` — a sentence a person typed, which nothing re-derived from a run
    and which turned the gate green when deleted. `known_failing` is gone, and with it every
    other verdict-shaped field (`CheckRegistryTest.FORBIDDEN_STATUS_FIELDS` fails the gate if one
    comes back). What is red now is whatever `tools/run-checks.sh` last recorded in
    `reports/checks/<id>.json`: the exit code the process returned, with the clock either side of
    it and the exact invocations the register asked for. `tools/run-checks.sh results` prints the
    ledger and the gate reads it. Nothing in this document, or in `tools/checks.json`, can make a
    check look green any more.
16. **`tools/test.sh` passes `--remote-debug tcp://127.0.0.1:0`, which never connects.** Measured:
    the engine prints `The remote port number must be between 1 and 65535 (inclusive)` and
    `Remote Debugger: Unable to connect to host '127.0.0.1:0'` on every gate run, so the `-d`
    flag buys nothing. It does not change the freed-instance behaviour either way (that was
    measured with and without it), but two engine errors on every run is noise in the one log a
    reviewer reads, and the flag should either be dropped or given a port.
17. **Three of the four capture scenes assert nothing.** `feel_tell`, `ui_stats` and `ui_trade`
    are eye checks: they are declared `"asserts": false` in the register and the only way they
    can fail is by not writing their PNGs. That is honest but thin — `prop_frame` shows what a
    capture that measures its own output is worth. Anything in them that can be stated as a
    number (the tell's ring contrast against the floor, a stats row against its column) should
    become one.
18. **The ledger is tamper-*evident*, not tamper-proof.** A record is machine-written, lives
    under gitignored `reports/`, and is pinned to the plan the register describes — so it cannot
    be committed, reviewed into a pull request, or survive the check changing shape. It is still
    a JSON file on a developer's disk: somebody determined to lie to their own gate can write one
    by hand, or point `OMADUNGEON_CHECK_RESULTS_DIR` at a directory of forgeries. The property
    this round bought is narrower and worth stating exactly: **there is no field in the source
    tree a person can edit to make a check read green**, which is what `known_failing` was. A
    signed or CI-only ledger would close the rest, and is not worth the machinery today.
19. **The shipped binary leaks on the way out.** `tools/check-package-layout.sh` runs the packaged
    `omadungeon` headless with an empty `HOME` and no Omarchy state, and its log carries
    `WARNING: 2 ObjectDB instances were leaked at exit` and `ERROR: 1 resources still in use at
    exit` on a clean run. Neither is what that check is asking about, so both are printed as a
    note rather than failing the packages — but nobody owns them, and "1 resource still in use"
    at the end of a 120-frame headless boot should be identifiable. gdUnit's orphan count covers
    the test tree, not the shipped binary; this is the only place the binary's own exit is
    looked at.
20. **The soak cannot make an item drop happen.** Item drops come from elites only
    (`EnemyBase._drop_loot`), so a seed block genuinely sees none — measured 2, 0, 3 and 1 across
    four blocks — which is why "at least one drop seen and taken" is a fleet minimum in
    `tools/soak.sh` rather than a per-process one in `death_soak.gd`. A `--soak-force-elite` that
    made every pack carry one would turn the fleet rule into a per-process rule and make the drop
    path covered on every run rather than on most of them.
21. **The freed-instance scan reads one file.** `tests/unit/freed_instance_test.gd` walks
    `src/core/test_scenarios.gd`, because that is where the two core dumps came from. The rule it
    enforces — nothing may call a method on a node it picked up before an `await` — is a rule
    about the whole codebase, and the scan is now general enough (every local, every `for`
    binding, string literals blanked) to be pointed at `src/**` and `tests/**`. Doing that would
    be a round's work in itself: the first sweep will find reads that are fine in context and the
    scan has no way to know it.
22. **Concurrent harnesses still delete each other's sandboxes, and the lock is not enough.**
    Observed live this round while several agents were capturing at once: a
    `tools/capture-scene.sh pickup_frame white` shell was alive and waiting on its
    `godot --import`, and its sandbox `/var/tmp/omadungeon-capture-<pid>` had been removed by
    somebody else's sweep — `/proc/<import pid>/fd` showed the sandbox's own `.sandbox.lock` as
    `(deleted)`, and the import then sat in `futex_wait` for 14 minutes on 3 seconds of CPU. The
    flock rule in `tools/sandbox-lib.sh` is supposed to make exactly that impossible, so either
    the sweep tested a lock file that had already been replaced, or something is deleting
    sandboxes without consulting `sandbox_is_stale` at all. The import deadline added this round
    turns the symptom into a failed attempt with a log rather than an unbounded hang, but the
    deletion itself is unexplained and needs someone to reproduce it with two harnesses and an
    `inotifywait` on the copy root.
23. **Two fixed-frame waits are left inside `tests/unit/ui/text_fit_test.gd`.** `_screen()`'s
    three-frame settle is gone — it is `TextFitTest.settled()`, a poll with a deadline, and it
    is what stopped the strengthened bounds check passing alone and failing in the tree. The two
    `for _i in 2: await process_frame` waits after a `hint.text` assignment were left as they
    are, because changing them would mean re-running the gate for a line that measured stable in
    every run tried (alone, the `tests/unit/ui` subtree, the whole tree, and the deliberately
    broken copy). They are still the wrong shape and should become `settled(panel)`.

## Fullscreen, the half that is still open (measured this round)

24. **The game cannot put its own window *into* fullscreen on Hyprland.** Owner report 12 is two
    problems wearing one coat. The reading half is closed: `CompositorWindow` asks the window
    manager about this process's window, so a fullscreen made with SUPER+F now reaches the Video
    row (`tests/out/vm/vm_fullscreen_{before,after}.png`, Hyprland 0.56.2 in the Omarchy VM).
    Leaving fullscreen from the row works too, because the panel writes the compositor's truth
    into `window.mode` before writing the player's choice, which gives Godot a fullscreen on its
    books to unset — the VM goes back to a tiled 1896×1030 on an untick.

    **Entering** fullscreen does not work, and not because of anything in this repository.
    Measured three ways in the VM, all with the same result — `hyprctl` keeps reporting
    `fullscreen: 0` and the window keeps its tiled 1896×1030 geometry:

    - ticking the Video row (`window.mode = Window.MODE_FULLSCREEN` through `_apply_window`),
    - a launch with `"fullscreen": true` already in `settings.json`, so the boot-time
      `SettingsPanel.apply_all` asks for it before anything is drawn,
    - and **Godot's own `-f` flag**, which never goes near this repository's code.

    The compositor's own dispatcher works on the same window in the same session
    (`hl.dsp.window.fullscreen({ mode = "fullscreen" })` — what SUPER+F is bound to), so the
    window is fullscreenable; it is the request from inside the engine that does not arrive.
    That is a Godot Wayland-backend limitation on this compositor, and it predates this round:
    the old one-way toggle simply hid it, because the row echoed the mode the game had just
    written to itself and reported success for a window that had not moved. The row is honest
    now — asked for fullscreen, the window does not follow, and the checkbox says so.

    Two ways forward, in order of preference. **Confirm it on the owner's real machine first**:
    everything above is a VM with `virtio-vga` and the OpenGL3 driver, and an engine path that
    fails there may work on real hardware. If it fails there too, the same compositor route this
    round opened for reading will carry the write: `CompositorWindow` can dispatch
    `hl.dsp.window.fullscreen` (Hyprland) or `[pid=…] fullscreen enable` (sway) instead of
    asking the engine. It was deliberately not done here — issuing commands to the player's
    window manager on a UI click is a different thing from asking it a question, and it needs its
    own safety design: Hyprland's dispatcher takes no window selector (measured: a `window = {…}`
    option is refused and the dispatch lands on the *active* window anyway), so the game would
    have to confirm it is the focused window before every write.

## Lighting, after the round that made the torches the only light

25. **The dungeon has no indirect light.** The owner's words were "that isn't how light works, it
    doesn't just stop, it bounces etc". What shipped answers half of that: `DungeonLight.FALLOFF_POWER`
    gives every pool a long soft tail with no edge a player can point at, and the wall occluders
    let light wrap a corner instead of being guillotined by it. What it does not have is *bounce* —
    a lit surface does not re-emit anything, so a torch in the corner of a small stone room lights
    the corner and not the room, and a tile two steps behind a pillar gets nothing rather than the
    dim warm fill the stone around it should be throwing back.

    The shape of the fix is a per-tile light map: propagate from each source through open tiles
    with distance attenuation, attenuate hard through walls, then one or two bounce passes where
    each lit tile re-emits 0.15–0.3 of what it received to its neighbours multiplied by that
    surface's albedo, so the fill carries the theme's own colour. Feed it to the tile material (or
    a light texture) and sample it for entities as well, so a prop standing in indirect light is
    lit by it. Godot has no 2D global illumination, so this is ours to build.

    Two properties it must keep or it becomes the thing this round deleted. The fill has to be
    **derived from live sources** — extinguish every light and the room goes black — which is
    exactly what separates bounce from the ambient wash the owner rejected: bounce has a cause and
    a direction, ambient has neither. And it has to be recomputed only when the lights, the room or
    the mood change, never per frame, because the harness renders on llvmpipe; the shader
    interpolates between tiles in between. `lighting_quality` LOW should skip the bounce passes so
    the setting stays meaningful.

    Shadows follow from it: a cast shadow should keep its shape near the caster, lose definition
    with distance, and receive bounce, so a shadow is "less light" and never "no light".
    `LightingProfile.shadow_alpha` is at 0.32 for exactly that reason and is a blunt stand-in.

26. **Loot is the one surface still drawn outside the lighting layer.** `LightRig.loot_mask()` hands
    a pickup `TELL_MASK` on a dark theme, so a dropped coin keeps its authored brightness in a room
    where nothing is lighting it. It was a small offence over the old 0.32 ambient, because an
    unlit corner was gloom; over `LightingProfile.unlit_floor` at 0.06 it is the most conspicuous
    lit-by-nothing thing on the screen, and the owner's ruling is about precisely that.

    The right shape is the one the owner named for the player and the enemies: give loot its own
    small emitter and put it on `PROP_MASK` with every other body, so the thing lighting the coin
    is the coin. It was tried in the round that took the ambient out and reverted, because
    `pickup_frame` measures a drop against *the surface it covers* and an emitter lights both — the
    readings collapsed to a shadow's ratio against its own surface on the placements where the
    drop's body does not overlap the surface being asked about. Doing it properly means teaching
    that capture to measure the drop against the surface *at the same exposure*, which is a check
    rewrite rather than a one-line change. Until then it is defensible on its own terms — a drop is
    a tell, the same family as a health bar, an alert mark and a windup telegraph, all of which are
    exempt for the same reason — but it should not stay exempt indefinitely.

27. **No scenario casts a spell, so no rendered evidence shows one lighting a room.**
    `src/core/test_scenarios.gd` runs boot, class_select, floor, combat, chest, loot_drop, pause,
    the two theme swaps, summary, new_run_confirm, the three music ones and quit, and not one of
    them fires an ability. The emitter table's `fire`, `frost`, `shock`, `arcane` and `explosion`
    rows were all retuned when the ambient came out, and their energies, radii and roles are pinned
    by `tests/unit/rooms/lighting_emitter_test.gd` — but nothing photographs a fireball actually
    lighting the walls, which is the one lighting claim in this round with no picture behind it.
    Adding a `spell` scenario also means a row in `tools/checks.json` and its matching expectation
    in `tests/unit/tools/check_registry_test.gd`.
