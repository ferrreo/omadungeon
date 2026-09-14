# Testing Omadungeon

Three tiers, each answering a different question. They are cumulative: a change
that passes tier 1 can still look wrong, and a change that looks right in the
fixtures can still be wrong on a real machine.

| Tier | Question it answers | Runs where | Typical time |
|------|--------------------|------------|--------------|
| 1 — unit & integration | Does the logic do what it says? | headless Godot, no compositor | ~2 min |
| 2 — rendered checks | Does it *look* right, in six themes? | nested headless sway, on this machine | ~30 s per capture |
| 3 — real Omarchy VM | Does the shipped package work on a genuine Omarchy desktop? | QEMU/KVM, loopback only | ~10 min to build, ~2 min to re-verify |

Nothing in any tier may open a window on your real Wayland session. Tier 2 runs
inside a nested headless sway; tier 3 runs inside a VM whose display is a
loopback-only VNC server. If you find yourself reaching for `godot --path .`
without a harness, you are about to break that rule.

---

## Before anything: the cheap checks

```bash
tools/check-scripts.sh                  # every .gd compiles; prints "scripts ok - N parsed"
tools/lint.sh                           # gdformat --check + gdlint over src/ and tests/
tools/check-quit.sh headless <fixture>  # the game exits within 5 s of quit(0) on a live floor
tools/check-quit.sh close-headless <fixture>  # ... and within 5 s of a window-close request
~/.local/bin/gdformat <files>           # format just the files you touched
~/.local/bin/gdlint   <files>           # lint just the files you touched
```

Line length is 110. `untyped_declaration` is an error, so a missing type
annotation fails the lint rather than merely reading badly.

`check-scripts.sh` gets its own `user://` the way the other three harnesses do
(`$XDG_DATA_HOME`, removed on exit, `OMADUNGEON_KEEP_USER_DIR=1` opts out). Both of
its Godot passes bring up every autoload, so without it the compile gate wrote the
player's real `profile.json`, pruned `user://test` under whatever gate was using it,
and moved the mtime on the real log directory; `SaveManager.SANDBOX_ARG_MARKERS`
does not cover it, because it passes none of `gdUnit4`, `--test-scenario` or
`--screenshot-dir`.

`check-quit.sh` runs the `quit` scenario (`src/core/test_scenarios.gd`: a built floor with
the radio playing and the lights up, one frame of it on disk where a display exists, then
`QuitGuard.request`) and fails when the process is still alive `QUIT_BUDGET` (5) seconds
after the driver's "exiting at" line, or exits with anything but 0 or the watchdog's 143. `headless` is the tier-1 shape;
`rendered` runs the same inside nested sway with the real GL driver, which is where the
shutdown hang was seen (a capture that had written its PNG sat for 235 s until the harness
killed it, three times in one run of the scenarios check). Register ids `quit-time` (cheap)
and `quit-time-rendered` (rendered), a dark and a light fixture each.

`close-headless` and `close` measure the *other* way out: the window manager asking the window
to close, rather than the game asking to quit. `close-headless` hands the root the
`NOTIFICATION_WM_CLOSE_REQUEST` the engine delivers for that, so it runs where there is no
compositor; `close` sends a real one (`swaymsg kill` against the nested sway, the same
`xdg_toplevel.close` a title-bar X or Alt+F4 sends) over a live floor. Register ids `quit-close`
(cheap) and `quit-close-rendered` (rendered). They exist because that request used to reach
nobody once a run had started: `Main` answered it, `RunManager.new_run()` frees `Main`, and the
game then stayed up - measured 2026-09-14, still alive 30 s after `swaymsg kill`, window and
all. The answer is the `Quit` autoload now (`src/core/quit_service.gd`); with the handler put
back in `Main`, `close-headless` fails at the deadline instead of passing in 0.1 s, which is the
proof the check has teeth.

What the hang was, so nobody re-derives it: the process sat in `pthread_join` on Godot
4.7.1's "Wayland Events" thread, and that thread sat in `poll(fd, -1)` - the engine's
`WaylandThread::destroy` sets `thread_done`, sends one roundtrip to wake the reader and joins
it, but a reader that was busy dispatching (a frame callback, on a loaded machine) at that
instant never sees the reply and never checks the flag (`_poll_events_thread`, unchanged on
master). Stacks were taken by attaching gdb to the hung capture through an `LD_PRELOAD`
shim calling `prctl(PR_SET_PTRACER, PR_SET_PTRACER_ANY)`, since Yama scope 1 refuses a
sibling attach. Headless never hangs (0 of 40 under the same load) because there is no
reader. A third of a second of render silence before the quit was tried first and did not
help (3 hangs in 40): the teardown itself makes the compositor talk, so the race is inside
`destroy()`. Re-measured 2026-09-14 on six parallel lanes of the `floor` capture: 11 wedged in
120, and six of those were caught with `kill -ABRT` and read back through `coredumpctl` - all
six identical, main thread in `__pthread_clockjoin_ex` on a thread whose `comm` is "Wayland
Events" and whose own stack is `__GI___poll`, at the same call site every time. The *title
screen* wedges too (1 in 120 under the same load), which is what rules the game's own content
out: less compositor traffic in the teardown, a narrower window, the same race.
With the watchdog armed, all 11 ended at 4.0-4.1 s with exit 143 and none ran longer, so the
hang is bounded rather than fixed - nothing a project can reach touches that join. This is not
a harness-only problem: `project.godot` pins `display_server/driver.linuxbsd="wayland"`, so a
player on Hyprland or sway quits through the same `WaylandThread::destroy`, and what the
watchdog buys them is a window that is gone in four seconds instead of one that never closes.
The rate above was measured on six parallel software-rendered lanes and is not a player's rate;
a real GPU tears down faster and the window is narrower. How much narrower is not measured here,
because nothing in this repository is allowed to open a window on the real session. `QuitGuard` (src/core/quit_guard.gd) is the workaround that holds: it arms a
detached shell that sends SIGTERM to the game 4 s after the request if it is still alive,
then calls `quit()`; `Main` routes the Quit button and the `Quit` autoload the window
manager's close request through it, and `request()` arms at most one watchdog per process, so
a button press and a close landing in the same frame cannot leave a second one behind. A run the engine wedged ends with 143, which the harnesses name in their output as "the engine
hung on exit and the quit watchdog ended it", so the ledger shows how often the engine needs it
instead of hiding it.

143 is a signal, not a verdict, and treating it as one licensed a false green. A watchdog kill
takes the exit code the run asked for with it, and `run-scenario.sh`, `ui-gallery.sh` and
`capture-scene.sh` all used to fill that gap by assuming a pass whenever the pictures had
landed. Pictures landing is not evidence of a pass: a capture scene reads its own PNGs back and
asserts on them, so it can write every file it promised and still have found four failures.
Measured by lighting2 on 2026-09-14 - a `pickup_frame` capture printed four FAIL contrast rows,
called `QuitGuard.request(tree, 2)`, wedged on the way out and was recorded in the results
ledger as ok. The rate of that false green is the rate of the hang, so the hang does not only
cost time, it launders verdicts.

`tools/check-exit-verdict.sh` (register `exit-verdict`) is what stops the old behaviour coming
back. The race cannot be summoned on demand, but what a harness *sees* of it can be reproduced
exactly: all three harnesses take a `GODOT_BIN` override, so a stub writes the PNGs they are
waiting for, records a code the way `QuitGuard` would, and then ends itself with `kill -TERM $$`.
It drives `run-scenario.sh` and `capture-scene.sh` end to end and the shipped 143 branch of
`ui-gallery.sh` straight out of the file, over three states each: a recorded 2 must be reported
as 2, a recorded 0 as 0, and a missing file as a failure. Validated against a known-bad tree
rather than trusted for being green - with the folds put back, it reports six failures and exits
1, and it passes only on the fixed harnesses.

So the verdict is written down before it can be lost. `QuitGuard.request` writes the requested
code to the file named by `OMADUNGEON_EXIT_FILE` *before* arming the watchdog, and writes
nothing when that variable is unset, so a player's run leaves nothing behind. Each harness
exports it and, on 143, reads the code back instead of guessing. A 143 with no file on disk is
a failure, not a pass: a verdict that died with the process is not a green one. Every caller is
covered without touching a single scene, because they all already hand `request()` their code -
the capture scenes, `UiGallery` and the scenario driver alike.

The *other* stall, found the same way, is at launch and is not the engine's: with no PipeWire
in the nested compositor's runtime dir, Godot's ALSA driver probes alsa-lib's pipewire plugin
and the plugin's failed connect can sit in `pw_thread_loop_stop` -> `pthread_join` for
minutes (main thread in `snd_pcm_open` 110 s after launch, before the main loop exists, so
no in-game timeout can fire; the run reads as "never reached its subject", exit 124). Every
capture fell back to the dummy driver after that probe anyway, so `run-scenario.sh`,
`capture-scene.sh` and `check-quit.sh` now launch with `--audio-driver Dummy` and skip it.

`check-scripts.sh` re-parses every `.gd` under `src/`, `tests/` and `tools/`
(`tools/check_scripts.gd`, loaded with `CACHE_MODE_IGNORE` inside a real main
loop so the autoloads exist) and prints how many it checked. It used to be
`godot --headless --import` plus a grep, which is not a compile check at all:
the importer will not re-parse a script whose cache it believes is current, so
the documented compile gate printed "scripts ok" and exited 0 over a tree with a
hard parse error in it. The `--import` pass is still there as the asset-cache
check it really was. A file that does not compile is named on stderr with the
engine's own `Parse Error` / `Compile Error` lines; exit 1. Takes ~6 s for the
~500 scripts in the tree — deliberately not an exact number here, because it moves every round
and the count that is true is the one the run prints.

---

## The register — every check, and what runs it

`tools/checks.json` lists every check this repository owns; `tools/run-checks.sh <tier>` runs a
tier of it, **records what happened**, and is what `.github/workflows/ci.yml` calls;
`tests/unit/tools/check_registry_test.gd` is inside the gate and fails when the register and the
tree disagree — or when a check outside tier 1 has no recent passing record.

```bash
tools/run-checks.sh list        # the whole register; the flag column is read out of the ledger
tools/run-checks.sh cheap       # compile + style
tools/run-checks.sh unit        # the gdUnit4 gate
tools/run-checks.sh rendered    # every capture that needs a compositor
tools/run-checks.sh soak        # the death/drop/teardown soak
tools/run-checks.sh package     # both .deb variants, their Depends, and the installed layout
tools/run-checks.sh results     # one line per check: exit code, when, how many invocations
tools/run-checks.sh verify      # exit 1 naming every check with no usable result
tools/run-checks.sh ui-trade    # one check by name, every row of its matrix, re-recorded
tools/run-checks.sh death-soak  # ... the soak tier's one check, by its id
```

A bare check id is what you want after fixing one red check: it runs that check's whole matrix
and replaces its record, instead of sitting through the other forty invocations of its tier. Ids and
tier names share a namespace, so `test_no_check_id_collides_with_a_tier_name` keeps them apart —
it is what renamed the `soak` and `vm` *checks* to `death-soak` and `omarchy-vm`, leaving the
tiers those names belonged to.

**Why this exists.** For five rounds "the gate is green" meant `OMADUNGEON_TEST_COPY=1
tools/test.sh -c` and nothing else, and every other check in the tree was a command somebody had
to type out of a doc comment. `tests/unit/rooms/prop_frame_capture` is not a picture-taker — it
reads its own PNG back and **exits 2** when a prop is under target — and it had been exiting 2 on
the default theme the whole time, under a gate reporting green. It was not alone: four capture
scenes, the 32-screen UI gallery, ten of the eleven rendered scenarios, the weapon pose sheets and
the death soak were all run by nobody. CI ran one scenario (`boot`, one theme); the register's
rendered tier is 41 invocations today. **A check nobody runs is worse than no check, because it
reads as coverage.**

The register closes that five ways, and the gate enforces all five:

1. **Every file under `tools/` is declared** (`inventory`), one entry per file, as a harness, a
   library, a generator, a fixer, a packaging step, data, a doc or a check. A new tool with
   nothing running it fails the gate. *Per file* is this round's correction: an entry could name
   a **directory** (`tools/vm/`, `tools/art/`), and those two covered 33 of the ~55 files under
   `tools/` — so a check dropped into either arrived declared, by a line written before it
   existed. `test_no_inventory_entry_claims_a_whole_directory` refuses directory claims now.
   (It works: `tools/vm/fullscreen.sh` landed in the tree while this was being written and the
   gate named it within the minute.)
2. **Every `.tscn` under `tests/` is declared** (`capture_scenes`) and names the check that runs
   it. A `.tscn` is a main scene, invisible to the gdUnit selector, so this is the only place one
   can be pinned down.
3. **A check that CI cannot run must say why**, in `why_manual`, and say what runs it instead.
   `manual` is a claim about the world, not a place to put checks to make them stop failing.
4. **Collections that can shrink are pinned to their source list.** `scenarios.subjects` must
   equal `TestScenarios.SUBJECTS` and every subject must be in the matrix (dark and light,
   except the two `theme_swap` scenarios that pin their own pair); `ui-gallery.screens` must
   equal `UiGallery.SCREENS` in order; `prop-frame.outputs` must equal `Biome.ALL_IDS`. Both of
   the first two were claimed in the register and enforced by nothing, so either list could lose
   an entry — a scenario nobody photographs, a screen nobody captures — without a word.
5. **The gate fails when a check has no recent passing result.** This is the one that replaced
   `known_failing`, and it is the point of the round.

### The ledger: results, not claims

The register says what a check **is**. It no longer says how a check **went**.

It used to: a `known_failing` field held a sentence a person typed about why a check was red,
the gate failed on the presence of that string, and clearing the string — not fixing the check —
turned the gate green. It was free text, nothing re-derived it from a run, and it was stale
within an hour of being written. One level up, it was the same disease the register exists to
cure: a claim standing in for a result.

`tools/run-checks.sh` now writes one record per check it runs, `reports/checks/<id>.json`:

```json
{
  "exit": 0,
  "failed_rows": 0,
  "finished": 1789302205.0,
  "host": "freya",
  "id": "soak",
  "pid": 35784,
  "plan": ["tools/soak.sh --processes 3 --runs 2 --floors 4"],
  "recorded_by": "tools/run-checks.sh",
  "seconds": 56.0,
  "started": 1789302149.0,
  "tier": "soak"
}
```

Everything in it is observed: the exit code is the one the process returned, the timestamps are
the clock either side of it, and `plan` is every invocation the register asked for at the moment
of the run. `CheckRegistryTest.test_every_check_outside_the_gate_has_a_recent_passing_result`
reads those records and fails when a check the register says CI runs has

* no record at all (*never run here*),
* a record whose `plan` no longer matches the register (the check changed shape; re-run it),
* a non-zero `exit`, or
* a `finished` older than `policy.result_max_age_hours` (48 h).

**There is no field anywhere that makes a check look green.** The window is a tunable in the
register, but its bounds are constants in the suite (`MAX_RESULT_AGE_CEILING_HOURS` = 168,
`MIN_RESULT_AGE_FLOOR_HOURS` = 1), so widening it past a week fails the gate rather than buying
anybody a longer silence; `FORBIDDEN_STATUS_FIELDS` fails the gate if `known_failing` — or
`passing`, `status`, `skip`, or any other verdict-shaped field — comes back; and tier `unit` is
exempt from the rule only because the gate cannot require its own result to exist before it
runs, with `test_only_the_gate_lives_in_the_gates_own_tier` stopping anything else being parked
there. The ledger lives under `reports/`, which is gitignored: a record cannot be committed,
reviewed or edited into a pull request.

So **the gate is red on a fresh checkout until the other tiers have been run**, and that is the
intended reading: the gate is *one* of the register's 48 CI invocations, and a green gate over
1 of 48 was exactly the state this register was built to end. `tools/run-checks.sh verify`
prints the same list from a shell, without waiting for a gate run.

`tools/test.sh` exports `OMADUNGEON_CHECK_RESULTS_DIR` pointing at the real checkout's
`reports/checks`, because copy mode rsyncs `res://` without `reports/` — a gate inside a copy
would otherwise find no ledger and report that nothing has ever been run.

**CI is three jobs now, and the order is the point**: `checks` (cheap, rendered, soak) and `deb`
(the package tier) each upload their records as an artifact; `gate` needs both, downloads them
into `reports/checks`, and runs the unit tier last — because the gate is the thing that reports
on everything else.

### The soak asserts something now

`tools/soak.sh` runs `tests/unit/tools/death_soak.gd` in many processes and reports a crash
rate. That is a real finding, but "no process crashed" is only evidence about the death, drop
and teardown path *if the process walked it*, and nothing said it had: a run that killed
nothing, saw no drop and took no item printed the same `SOAK done` line, exited 0, and counted
as coverage of all three. It was declared as covering that path and passing at zero.

Each process now has minima, and a process under any of them exits 1 with a
`SOAK below minimum:` line naming the number:

| minimum | why that number |
|---|---|
| `kills ≥ 3 × floors_built` | measured on the register's matrix (`--processes 3 --runs 2 --floors 4`): 102, 102 and 89 kills over 8 floors each, so ~12 per floor. Three is a floor that went badly and still died on |
| `pickups ≥ 1 × floors_built` | every death rolls gold, so this is the drop half of the path, and unlike an item drop it does not need the generator to have put an ELITE room on the floor. Measured: 114 and 122 per 8 floors on the two blocks whose lines were kept. Counted off `EventBus.spawn_pickup`, not by sweeping the floor — the soak stands on the enemy it kills, so a homing pickup is collected a frame or two after it spawns, and the first version of this minimum reported `pickups_seen=0` beside `kills=55` |
| `drops_missed = 0` | every item drop the soak walked up to was equipped |
| `floors_built ≥ runs` | a run that never built a floor is not a run |
| one death **and** one abandon, when `runs ≥ 2` | the two endings free the floor from different call stacks, which is the whole reason both are driven |

Two things fell out of writing them, which is the argument for minima in one paragraph. Item
drops come from elites only (`EnemyBase._drop_loot`), so a seed block can genuinely see none:
`--processes 4 --runs 2 --floors 3` measured 2, 0, 3 and 1 item drops over its four blocks. And
of the one drop block 3 did see, it took **zero** — the soak walked onto the drop, asked
`can_interact()` two physics frames later and moved on, while `ItemPickup.SETTLE_TIME` holds a
fresh drop shut for 0.4 s. The pickup, equip and displaced-item path had never once run in a
soak that claimed to cover it. It waits the settle out now (`DROP_SETTLE_FRAMES`).

Because a *block* can honestly see no item drop, "at least one item drop was seen and taken"
is a fleet-level minimum rather than a per-process one: `tools/soak.sh` sums the `SOAK done`
lines and fails the whole soak when the fleet is under `SOAK_MIN_DROPS` / `SOAK_MIN_ITEMS`
(1 each). A per-process rule there would be a flaky check, which is its own kind of lie. The
register's matrix was widened to `--processes 3 --runs 2 --floors 4` for the same reason — 24
floors rather than 12, which took the measured fleet from 2 drops to 8 and the run from 29 s to
56 s.

The soak now reads, on the register's own matrix:

```
soak: process 2 ok - SOAK done: runs=2 floors_built=8 kills=102 pickups=122 drops_seen=4 \
      items_taken=4 drops_missed=0 deaths=1 abandons=1 failures=0 shortfalls=0
soak: 3 processes, 0 crashed, 0 failed; exit codes: 0 0 0
soak: fleet totals: kills=293 drops_seen=8 items_taken=8
```

`items_taken` equalling `drops_seen` is the settle fix; before it, 8 drops would have produced
somewhere between 0 and 8 equips and nothing would have minded.

**Deliberately not in CI**, with the reason the register gives:

| check | why not | what runs it |
|---|---|---|
| `omarchy-vm` (tier 3) | needs `/dev/kvm`, a ~6 GB ISO and ~10 min of unattended install; no hosted runner has nested virtualisation | by hand before a release, `tools/vm/verify.sh` |
| `appimage` | downloads `appimagetool` at build time, so it fails for reasons that are not this project; the `.deb` is the shipped artefact and CI builds and unpacks it | by hand before an AppImage release |
| `colourblind` | with no `--swatch` coordinates it renders simulations and **always exits 0** — a step that cannot fail is the disease, not the cure | `accessibility_test` and `status_legibility_test` in the gate, plus the gallery's three `*_glyphs` screens |

---

## Tier 1 — unit and integration tests (gdUnit4)

```bash
tools/test.sh                                     # the whole res://tests tree
tools/test.sh -c                                  # ... without fail-fast: report every failure
tools/test.sh -c -a res://tests/unit/rooms        # one subtree
tools/test.sh -c -a res://tests/unit/gen/floor_generator_test.gd   # one file
OMADUNGEON_TEST_COPY=1 tools/test.sh -c           # run against an rsync'd copy
```

* `-a` **replaces** the default whole-tree selector, so passing one narrows the
  run instead of adding to it. `-i` skips a suite, `-rd` / `-rc` move the report
  directory and how many are kept.
* `-c` disables gdUnit4's fail-fast, so one run tells you about every failure
  instead of stopping at the first. Use it by default.
* `OMADUNGEON_TEST_COPY=1` copies the project to the copy root first and runs
  there, so several people (or agents) can test at once without fighting over
  the shared `.godot/` import cache. Use it whenever you are not alone on the
  box. The copy root is `$OMADUNGEON_COPY_DIR`, else `$TMPDIR`, else
  `/var/tmp` — a ~1 GB copy in a RAM tmpfs competes with the machine. Each run
  cleans its own copy up, and every harness sweeps the sandboxes of runs that are
  over on the way in, because an EXIT trap cannot fire on a KILL and the leftovers
  used to fill the tmpfs and make the harness fail in ways that look like project
  bugs.
* **"Over" is not "the pid in the directory name is gone."** That pid is the
  harness *shell*, and the shell is half a run: Godot outlives a shell that is
  killed (a caller timeout, a Ctrl-C, a runner killing the process-group leader)
  and Godot is the half still reading the copy. Sweeping on the shell's pid alone
  deleted a live gate's `res://` out from under it — observed as a
  `GdUnitCmdTool.gd` reparented to init with 2h36m of CPU and a cwd reading
  `/var/tmp/omadungeon-test-2455577 (deleted)`, while four healthy concurrent runs
  were untouched. `tools/sandbox-lib.sh` is the shared rule now, and a sandbox is
  left alone if **any** of three things is true: its `.sandbox.lock` flock is still
  held (taken by the harness, inherited by Godot, released by the kernel when the
  last of them exits — so it means "in use", not "someone remembered to clean up"),
  it is some live process's working directory, or the pid in its name is alive.
  `tools/test.sh` also traps INT/TERM/HUP and takes Godot down with it, which the
  capture harnesses get from their `timeout -k` deadline instead.
* **Every import has a deadline now** (`IMPORT_TIMEOUT`, 300 s). `tools/godot-import.sh` is the
  first thing every harness runs, and nothing bounded it: measured this round, with several
  agents capturing at once, a `godot --headless --import` sat for **14 minutes on 3 seconds of
  CPU**, blocked in `futex_wait`, after another harness's sandbox sweep deleted the project
  directory out from under it — `/proc/<pid>/fd` showed its own `.sandbox.lock` as `(deleted)`
  and `ls /var/tmp/omadungeon-capture-*` found nothing, while the `capture-scene.sh` shell that
  owned it was still alive and waiting. One wedged import stops a gate, a capture tier or a soak
  for as long as anybody is prepared to wait, with no output to read. It is a failed attempt
  with a kept log now, and the retry usually clears it.
* **A claim used to cost the harness its stderr**, which is worth knowing because it
  invalidates the mental model "if it had gone wrong it would have said so". `sandbox_claim`
  took the lock with `exec {fd}>"$dir/.sandbox.lock" 2>/dev/null`, and an `exec` with no
  command applies every redirection on the line *to the shell*, permanently: from the first
  sandbox any harness claimed — the first thing `test.sh`, `soak.sh`, `run-scenario.sh` and
  `ui-gallery.sh` each do — the run had no stderr at all. `test.sh: the run wrote no gdUnit
  report - not a pass`, the class-cache refusal, every capture harness's failure line: written,
  exit codes set, nothing printed. Found by a soak that exited 1 in silence. The redirection is
  scoped to a group now (`{ exec {fd}>...; } 2>/dev/null`), and
  `HarnessGuardsTest.test_a_claim_does_not_take_the_harnesss_stderr_with_it` drives the real
  function and fails on the old shape.
* **Every run also gets its own `user://`.** The copy isolates `res://` and
  nothing else: `user://` is `$XDG_DATA_HOME/omadungeon`, one directory per
  machine, so before round 7 two overlapping runs shared gdUnit4's `user://tmp`
  scratch, every fixture written at a fixed `user://` name, and the developer's
  own `profile.json`. `tools/test.sh`, `tools/run-scenario.sh` and
  `tools/ui-gallery.sh` now each export a per-pid `XDG_DATA_HOME`
  (`<copy root>/omadungeon-userdata-<pid>`, swept by the same dead-pid rule as
  the copies) and a matching `OMADUNGEON_TEST_USER_DIR` marker.
  `OMADUNGEON_KEEP_USER_DIR=1` opts out when you want to inspect what a run
  wrote. Measured: two concurrent runs of
  `tests/unit/tools/godot_import_test.gd` with the isolation reverted went red
  in 1 of 6 (`test_an_ordinary_import_still_passes` — the fake `godot` binary was
  deleted by the other run's `after_test()`); with it, 6 of 6 green, and three
  full concurrent gates were 1417/0/0/0/0, exit 0 each.
* **A fixed `user://` path in a test is a cross-run shared resource**, and
  `OS.get_user_data_dir()` is worse — it ignores the sandbox entirely. Write
  under `SaveManager.test_sandbox_dir()` (`user://test/<pid>`) instead.
  `tests/unit/tools/user_dir_isolation_test.gd` is the guard: it fails the run
  when the harness did not isolate `user://`, when `user://` resolves to the real
  data directory, when saving no longer round-trips through it, and when any test
  reaches for `OS.get_user_data_dir()`. Still outstanding, and *not* fixed by
  this pass: `tests/unit/audio/music_manager_test.gd` (`user://music_test/`) and
  `tests/unit/otter_wallpaper_test.gd` (`user://otter-colors-test.conf`,
  `user://otter-test-config{,2}`) still use fixed names. The harness isolation
  makes them harmless *between* runs; they are still the wrong shape.
* **The music lights are measured, not eyeballed, for pulsing.**
  `tests/unit/audio/music_reactive_layer_test.gd` feeds `MusicReactiveLayer.step()` a
  synthetic 140 BPM track (a kick on every beat over a loud passage, 24 s at 60 Hz, starting
  from the calm end so the light has the whole swing to make) and asserts the frame-to-frame
  change in the middle of the frame stays under 0.0006 of its luminance and the detrended
  spectrum of that luminance carries under 0.0004 at the beat frequency and its harmonic,
  while the light still drifts by more than 0.05 over the passage. It prints the numbers
  (last run: worst frame delta 0.000344, beat amplitude 0.000009, harmonic 0.000002, drift
  0.11). It also asserts nothing in the layer is connected to `EventBus.music_beat`, and that
  a calm-to-loud *track change* is a monotonic crossfade: no frame moves the middle of the
  frame more than 0.004 of its luminance, no frame reverses, it settles at
  `MusicMoodLevers.crossfade_seconds`, and the passage is frame-for-frame identical with beats
  on the bus or none (last run: +99.6%, worst delta 0.0033). The mapping itself is measured on
  colours in `tests/unit/audio/music_mood_test.gd` - `MusicMoodState.grade()` is the GDScript
  reference for the `music_grade` shader include - against thresholds: calmest versus loudest
  bundled track on the tokyo-night floor at least x1.25 luminance and 20 degrees of hue apart,
  no coloured environment role of any fixture theme more than 15 degrees from the theme under
  any track, a *light's* own colour at least 30 degrees apart calm to loud (a flame gets a
  budget a surface does not) and a pool at least x1.4 wider, amount slider at 0 exactly
  neutral. The same suite's `music_reactive_layer_test` covers the two things the *rendered*
  path does that a colour test on authored palette entries cannot see: the hue budget measured
  on the floor **as drawn** - the lit palette under the lighting layer's darkness, graded and
  then hazed - on all six fixtures plus the owner's own green otter palette (198 readings,
  worst 9.4 degrees against the 15 the theme is guaranteed, and 9.4 on otter specifically,
  which is asserted separately because it is the palette the blue-violet room was reported on), and the **live envelope**: with a
  real mood set and a synthetic 140 BPM track, a quiet passage and a loud one of the same track
  are 40.9% apart in the middle of the frame, no frame moves more than 0.00055 of its luminance
  against a 0.0006 ceiling, and the beat bin carries 0.000009. A separate case steps the
  envelope from silence to full and asserts it cannot cross faster than `live_rate` allows.
  What a player actually experiences of all that is the step between two tracks
  played in a row, and `tests/unit/audio/radio_playlist_test.gd` measures it over 40 shuffles
  of the bundled playlist: `RadioPlaylist.spread` has to keep the mean adjacent step at 0.45
  of the energy range and the tenth percentile at 0.25, and to beat a plain shuffle on both
  (last run: 0.357/0.080 shuffled against 0.494/0.319 spread). `tests/unit/reactivity/music_live_mood_test.gd`
  covers the live side against the real playlist (torch colour/level/flicker per track, the
  `DungeonLight` light contract leaning calm/loud and neutral with the switch off, the noise
  flicker's spectrum, the once-per-enemy room-entry nudge), and skips itself when no radio
  tracks are bundled. `live_swap_test.gd` pins the music lights to neutral before it builds,
  because the torch colour it asserts on now carries the mood. The rendered evidence is `tools/run-scenario.sh music_moods` and
  `music_change` (both themes in the `scenarios` matrix): the same room under four tracks - the
  calmest, the loudest, and the first two of a real played order, which is the pair a player
  hears in a row - and
  six frames across a track change with a monotonic-luminance assertion and a strip PNG. A
  third, `music_within`, is the answer to "it needs to change based on what is happening over
  the current track": the same room at the quietest, typical and loudest passage of *one* track
  and the same three with the music lights off, at the track's own measured envelope values
  (`MusicMood.live_points`, mirrored offline from the real waveform), failing when the room did
  not move between them. The
  counterpart for the generation side is
  `tests/unit/reactivity/music_levers_test.gd`, which prints the enemy, trap, prop, tile and
  light differences one seed makes under two energies (GAME_DESIGN §10.2 quotes them).
* Outside copy mode the run also gets its own report directory,
  `reports/run-<pid>/`. gdUnit4 numbers reports `report_<last+1>` *within one
  directory*, so two runs sharing `reports/` can claim the same index and the
  "newest report" lookup below can read the other run's results as its own. In
  copy mode the copy already has a `reports/` to itself. A caller's own `-rd` is
  honoured and wins (it used not to be: a `-rd` run read `reports/` anyway).
  Dead-pid `reports/run-*` directories beyond the newest 5 are swept
  (`KEEP_RUN_REPORTS`).
* A run that reports **zero test cases is a failure**, not a pass: the harness
  exits non-zero and prints the selector. It also refuses to start when the
  project's global class cache is missing or incomplete — that is what a full
  copy root looks like from the inside (`Could not find type
  "GdUnitTestCIRunner"`, no tests, exit 1), and it is not a project failure.
* `OMADUNGEON_OMARCHY_STATE_DIR` is pinned to the `tokyo-night` fixture for the
  whole run, so a test never depends on the theme the developer happens to be
  using.
* Reports land in `reports/report_<n>/results.xml` — gdUnit4 keeps 20 and writes
  `report_<last+1>`, so only the first run in a fresh checkout writes `report_1`.
  The script resolves the newest **numerically** (lexicographic sorting puts
  `report_9` after `report_22`) and reads that one file for both the case count
  and the failure dump, after checking it is not older than the run. That is the
  bug that made the zero-test guard useless outside `OMADUNGEON_TEST_COPY=1`:
  runs 2-21 read run 1's stale numbers and a run that executed nothing exited 0
  claiming the first run's case count. A run with no report newer than itself
  exits 5 and says so.

**Rules.** Never weaken or delete a test to make it pass. Every behaviour you
fix gets a test. Anything that generates or rolls loot takes a
`RandomNumberGenerator` parameter and is tested with a fixed seed — global
`randf()` in generation or loot code is a bug, not a style preference.

**Isolation.** A test must leave the process exactly as it found it. `EventBus`
is an autoload, so a handler a test connects to one of its signals keeps firing
for every suite that runs afterwards — which is how a case comes to pass alone
and fail in the whole tree. Connect through `EventBusProbe`
(`tests/support/event_bus_probe.gd`), keep it as a suite member and call
`release()` in `after_test`. `tests/unit/tools/test_isolation_test.gd` checks it
two ways: it asks the live `EventBus` whether any signal still holds a callable
owned by a test script or by a freed object (the guarantee — it sees every shape
of leak, including one made through a local `Signal` or a `Callable.bind`), and
it scans `res://tests` for the usual `connect` without `disconnect` shape (a
fast hint that can name the file, not a proof). The product side of the same
rule: gameplay must never branch on a global signal's connection count or on any
other cross-suite state (`UniqueYacht` used to, and it is why the gate was red at
random).

**The flush rule.** A hit is applied inside `area_entered`, while the physics
server is flushing its queries, and it refuses collider writes there. Anything
reached from a hit that adds a node with a collision shape must defer the
insertion — go through `PhysicsFlush.add_child_at()`, which defers inside a flush
and inserts immediately outside one. A test that kills an enemy with
`entity.hurtbox.receive(info)` never opens that window, so it cannot see a
violation: `tests/unit/tools/physics_deferral_test.gd` kills through a live
`Hitbox` overlap instead and compares the result against a control killed outside
one. Add a case there when you add an on-death effect.

**Waiting.** Never wait a fixed number of frames for something asynchronous.
The NavigationServer bakes its map on its own schedule, so
`await floor_root.await_nav_ready()` is the wait, not `for i in range(6)`. A
poll with a deadline reports one honest failure; a frame count reports a
different result depending on machine load.

**A UI layout is asynchronous too**, which is easy to forget because it looks instantaneous.
`tests/unit/ui/text_fit_test.gd` built each screen and waited `for _i in 3: await
process_frame`, and measured: `run_summary`'s panel was at y 25.9 after those three frames when
the suite ran alone and at y 43.1 after the same three frames when it ran after the rest of
`tests/unit/ui` — same host, same 480x270 viewport, same fixture, the layout simply got further
along in one run than the other. Nothing noticed while the suite only asked each control
whether it had been given its own minimum size; the moment it started asking whether controls
fit the *screen*, the same code passed alone and failed in the tree. `TextFitTest.settled()` is
the replacement: poll until two consecutive frames lay the subtree out identically, with a
deadline.

---

## A freed instance is a crash, not an error you can handle

**The rule.** Nothing may call a method on a node it picked up before an `await`. Re-validate the
reference first — `TestScenarios.live_room()` is that re-validation for the scenario driver — and
do not reach for a `!= null` check instead, because it does not answer the question.

Measured this round on Godot 4.7.1, inside the gate itself: a suite that frees a real `RoomNode`
and calls a method on it, run through `tools/test.sh`. The explanation that used to be written
down here — that `Variant::callp` only checks the ObjectDB when a debugger is attached — is a
Godot 3 story and is not what 4.7.1 does; the conclusion survives the correction, but not for
that reason, and the gate's own `--remote-debug tcp://127.0.0.1:0` never connects anyway (the
engine refuses port 0), so the gate runs with no debugger attached either way.

**A call is a hard crash, and which kind of hard you get is not your choice.**

| what you call on a freed `RoomNode` | what happens | seen as |
|---|---|---|
| a **GDScript** method (`room.pending_enemy_count()`) | **SIGSEGV** — `handle_crash: Program crashed with signal 11` — the process dies where it stands | `tools/test.sh` exits 134, no gdUnit report, no test result: the run has no answer at all |
| the same call through a `Variant` | **SIGSEGV** as well; going through `Variant` buys nothing | as above |
| an **engine** method (`room.get_name()`) | uncatchable script error ("Cannot call method 'get_name' on a previously freed instance"), the function aborts | gdUnit counts 1 error, harness exit 100 |

GDScript has no way to catch either one — there is no arrangement of the code under which the
call is merely "an error" you can branch on. The crash carries the engine's own backtrace with
the same two frames (`Variant::callp` → `GDScriptFunction::call`) both of the controller-session
core dumps carry, and the GDScript backtrace names the line.

**One honest boundary on that.** The crash row was reproduced against a project class in the real
tree; a throwaway project with no global class cache answered the *same* call with the checked
"previously freed" error instead. So "you might get the polite one" is not a plan: the shape the
game is written in — `class_name` types, a warm class cache, a real node — is the shape that
crashes, and the polite error is what you see for engine methods and in toy reproductions.
`tests/unit/freed_instance_test.gd` holds the parts that can be asserted without taking the gate
down with them; the crash rows are measured by hand, because a case that asserts them would
delete the run's own report.

**A null check does not answer the question**, and this is the part that is easy to get wrong,
because two of the three states a dying node passes through are invisible to it:

| the reference | `!= null` | `is_instance_valid()` | `is_queued_for_deletion()` | calling a method |
|---|---|---|---|---|
| `queue_free()`d, this frame | **true** | **true** | true | works |
| the same node, next frame | false | false | — | **SIGSEGV** |
| out of the tree, not freed | true | true | false | works |
| `free()`d | false | false | — | **SIGSEGV** |

`FloorRoot.clear_floor()` takes a floor down with `queue_free()`, so the row that matters is the
first one: the room the run just tore down is `!= null`, is `is_instance_valid()`, answers every
method you ask it — and is gone by the next frame, which is the far side of the `await` the
scenario is sitting on. A guard written as `if room != null` therefore passes on exactly the
frame it needed to fail. (On a genuinely `free()`d node `== null` does happen to be true in
4.7.1, which is a change from the Godot 3 behaviour the older notes describe — but you cannot
lean on reaching that comparison, because *casting* the reference is itself a runtime error:
`live_room()` asks `is_instance_valid` first, on the raw `Variant`, for that reason.)

So the guard is all three questions, in this order: `is_instance_valid(room)`, then
`is_queued_for_deletion()`, then `is_inside_tree()`. That is what `live_room()` does, and
`tests/unit/freed_instance_test.gd` scans `src/core/test_scenarios.gd` for a local that is read
after an `await` without being re-fetched or re-validated in between.

**The scan has been narrowed twice, each time because it was reporting nothing about real
lines.** First it tracked only locals assigned straight from `_busiest_room()` — and the
scenarios do not carry *that* local across their awaits, they carry the guarded one `live_room()`
hands back, so deleting the one `require(live_room(room) != null, ...)` in `_scenario_chest` left
it green. Then it tracked both room shapes **and nothing else**, and a room is not the only node
a scenario holds across a wait. `Main`, `Game` and `Title` are nodes too, `Main.show_screen()`
frees the screen it replaces, and `_settle()` is an await. Five real reads were in that blind
spot, and the scan named none of them:

```
test_scenarios.gd:211  require(main.current is ClassSelect, ...)
test_scenarios.gd:492  require(view.pause_menu.is_open(), ...)
test_scenarios.gd:646  var button := title.get_node_or_null(^"%NewRun") as Button
test_scenarios.gd:651  require(title.confirm_visible(), ...)
test_scenarios.gd:653  require(not (main.current is ClassSelect), ...)
```

It tracks **every** local now, and every `for` binding, and reports every `name.member` read
after a wait. Re-validation is `live_room(<the expression the local was validated with>)`,
`is_instance_valid(name)`, or assigning the name again — which is what "re-fetch it, do not
carry it" looks like in source, and is how all five were fixed (`_main()` again after the
settle, `RunManager.game` again after the settle, `_title_of(_main())` for the title screen).
String literals are blanked before the line is read, because without that the scan reports the
guard `require(opened != null, "main.tscn went away …")` as a read of `main`.

### The floor-plan suites (`tests/unit/gen`)

The owner's 2026-09-13 playtest (#4 "no real map or room variety", #5 "not every type of
room on every floor", #6 "bosses standing in the doorway") is pinned by four suites beside the
older generator ones, and one that draws:

* `floor_archetype_test.gd` — every `FloorArchetype` rolls over 200 seeds pooled across three
  fixtures and three floors, none past half of them; same seed, same archetype and layout hash;
  a forced archetype is honoured on every floor and still validates; the levers tilt the roll
  without zeroing anything; the archetype survives `FloorRestore.gen_params_to_dict/for`.
* `room_shape_test.gd` — every `RoomShape` keeps the centre 3×3 on every size in the table;
  at least two rooms in five on generated floors are not rectangles and every shape rolls;
  every door opens onto floor; room areas spread past 2:1 on most floors; turned rooms exist.
* `room_budget_test.gd` — the `RoomBudget` table has a row per floor; floor 1 has no elite, no
  gauntlet and no shop over 100 seeds; exactly one altar-or-shrine on every floor; the shop is
  present on every seed of floors 2, 5, 8 and sometimes elsewhere; every optional type the
  table allows turns up and none the table forbids; the fight quota holds; `SimFloorPlan`
  rolls the same mix.
* `arena_spawns_test.gd` — over 100 seeds across the six fixtures every arena spawn is at
  least `ArenaSpawns.DOOR_CLEARANCE` (8) tiles from every door and off the wall; the boss's
  tile is across from the door on the centre line; the fallback pack has its own spots; no
  ordinary pack spawns within two tiles of a door; the validator refuses a boss in the
  doorway; corridor dressing never opens a walkable tile next to a foreign corridor; a
  restored floor carries the same arena spawns.
* `lantern_anchors_test.gd` — `FloorData.lantern_anchors` (the lighting system's hooks):
  every anchor is a WALL tile facing walkable ground, none within two tiles of a door, the
  biome spacing holds along a room side and no two anchors touch, every room with a legal
  wall tile gets one, the list is identical on a floor regenerated from its saved
  `gen_params` and is part of `layout_hash()`.
* `floor_atlas_test.gd` — draws every archetype × floors 1/3/5/7 for `tokyo-night` and `white`
  to `tests/out/gen/floor_atlas_<theme>.png` (rooms tinted by type, doors, spawns, props) and
  fails if any drawn floor does not validate. Run it in place (no `OMADUNGEON_TEST_COPY`) when
  you want the pictures in the checkout; a copy run writes them into the copy.

Expectations that moved with the design: `floor_graph_test` and `floor_generator_test` used
to assert exactly one ALTAR and one SHOP-or-SHRINE per floor and a single boss spawn; they
now assert one ALTAR-or-SHRINE, a shop within the budget, the hub's degree cap and a spawn
list. `floor_quality_test` no longer expects an elite or a gauntlet on floor 1.

In-game evidence: `tools/run-scenario.sh floor <fixture> --scenario-floor N
--scenario-archetype <id>` lays every floor of the run to one plan (`FloorArchetype.forced`),
so the five plans can be captured one by one. `--scenario-arena entry` (`ArenaCapture`,
`src/core/arena_capture.gd`) puts the player one tile inside the boss arena's door and points
the camera at the whole arena (the dormant boss waits across the room) and
`--scenario-arena engaged` walks it past the deep trigger, so the seal and the "awakens"
banner are in the frame; either fails the capture (exit 2) when the floor has no arena or
the arena did not fire. The round's pictures: `tests/out/floor_f{1,3,5,7}.png`,
`floor_f3_arena_entry.png`, `floor_f3_arena_engaged.png`, `floor_f6_arena_entry_white.png`,
`floor_<archetype>_f{1,3,5,7}[_white].png` and the six-fixture `floor_contact_sheet.png`
(the `floor_sheet_<fixture>.png` captures of floor 5 side by side).

---

## Tier 2 — rendered checks (nested headless sway)

The game is driven by `src/core/test_scenarios.gd` through
`--test-scenario <name>`, which plays a deterministic script of real input
events, waits for the frame it wants, writes a PNG and quits.

```bash
tools/run-scenario.sh floor                       # -> tests/out/floor.png (tokyo-night)
tools/run-scenario.sh chest gruvbox               # -> tests/out/chest_gruvbox.png
tools/run-scenario.sh floor nord --scenario-floor 3
OMADUNGEON_TEST_COPY=1 tools/run-scenario.sh combat catppuccin-latte
tools/ui-gallery.sh                               # -> tests/out/ui_<screen>.png
tools/ui-gallery.sh white --only run_summary
```

**Scenarios** (`TestScenarios.SUBJECTS`, 11): `boot`, `class_select`, `floor`, `combat`,
`chest`, `loot_drop` (a killed pack's drops, then that floor torn down and rebuilt), `pause`,
`summary`, `new_run_confirm`, `theme_swap` and `theme_swap_midfight` (the last two also write
`<scenario>_before.png`). `SUBJECTS` is the list: a scenario with no entry there is one nobody
can say is broken, and the driver refuses to shoot it.

**Theme fixtures** live in `tests/fixtures/omarchy/<name>/state` and stand in for
`~/.local/state/omarchy`: `tokyo-night` (the default), `catppuccin`, `gruvbox`,
`nord`, plus the two light ones, `catppuccin-latte` and `white`. Always check at
least one light theme — most palette bugs only show up when the background is
brighter than the foreground.
A name that is not one of those is refused (exit 4) before anything else happens.
It used to be taken at face value: the state dir was pointed at a path that does not
exist, `Desktop` fell through to whatever desktop theming the machine was wearing,
and `tools/run-scenario.sh floor no-such-theme` exited 0 having written
`floor_no-such-theme.png` — a picture of the developer's own desktop under a
filename naming a fixture it never read.


**Output naming**: the default theme keeps the bare `tests/out/<scenario>.png`;
any other fixture gets `tests/out/<scenario>_<theme>.png`, so a second theme
never overwrites the first. Override with `SCENARIO_SUFFIX=`. `tools/ui-gallery.sh`
follows the same rule — `ui_<screen>.png` for `tokyo-night`,
`ui_<screen>_<theme>.png` otherwise (`GALLERY_SUFFIX=` overrides). It used to
write the bare name whatever theme it was given, so a second theme reported
"24 screens captured" straight over the first set and nothing in `tests/out` said
which theme a `ui_*.png` showed.

**`theme_swap` and `theme_swap_midfight` take no theme argument** and exit 4 if
given one. They pin their own pair — `src/core/test_scenarios.gd` builds the
"before" state from `tokyo-night` and links the "after" one to `white`, whatever
was asked for — so `theme_swap_catppuccin-latte.png` was a `white` capture
wearing a latte label, and "every scenario under a dark and a light theme"
quietly produced two palette-identical pairs. `SCENARIO_ALLOW_THEME=1` lifts the
refusal once the scenarios honour the argument. Both harnesses also stopped
treating a leading `-` as a theme name: `tools/ui-gallery.sh --only run_summary`
used to take `--only` as the fixture.

**Gallery screens** (`UiGallery.SCREENS`, 36): `title`, `class_select`, `hud`, `chest_item`,
`chest_stat`, `chest_ability`, `chest_replace` (the compare screen on an ability trade),
`chest_replace_item` (the same on a ring trade), `chest_four`, `chest_shop`, `hud_tag` (the
name tag over a ground drop), `hud_tooltip` (the compare card while standing on one),
`loadout` (the build screen as the Tab key opens it), `pause_build`, `pause_controls`,
`pause_settings`, `settings`, `settings_bindings`, `settings_capture` (a keyboard rebind
capture open, with its prompt), `settings_advanced`, `run_summary`, `run_summary_full`,
`run_death`, `credits`, `stats`, `accessibility`, `enemy_bars`, and the three
colour-blind-glyph variants ending `_glyphs` (`hud_glyphs`, `chest_item_glyphs`,
`pause_build_glyphs`).

The five UI overhaul suites the round-5 owner report produced are `compare_view_test`
(the model has every stat of both sides on one row and the view never elides - measured over
generated trades), `loadout_screen_test` (two actives, two passives, innate, skill, every gear
slot, the sheet with sources, pad reach), `item_tooltip_test` (a tag near a drop, a card only
on it, on the left edge beside the player, never over a quarter of the frame, every row of a
generated trade on it), `settings_rows_test` (every drawn key has a default; a CHOICE row is
one cycling button), `hud_layout_test` (every HUD block up at once - both banners at their
longest, the map with its strip, the prompt, the tooltip - and no two rects overlap or leave
the frame), `minimap_missed_test` (the known-room
channel, the rooms-left strip) and, in `offer_prompts_test` / `descend_confirm_test`, the
stairs no longer holding a descent back.

The last six — `pause_controls_pad`, `settings_bindings_pad`, `pause_settings_pad`,
`settings_capture_pad`, `chest_item_pad` and `chest_item_start` — are last on purpose: each
pins the active device to the gamepad, and that flag lives on the SceneTree for the rest of the
process, so anything after them would be captured wearing it. They are the screens that read
*differently* on a pad rather than just re-photographed: the Controls page teaching pad
buttons, the rebind grid with its Keyboard column drawn inert, the same Settings page embedded
in the pause menu with the notice that says why that column is inert (it is 96 px narrower
there, which is where the notice used to run off both ends of the panel), the gamepad rebind
capture with its "tap B / hold B" prompt drawn with the B sprite, the offer board with its
buttons drawn as pad sprites rather than typed as letters, and an offer board answering a
Start press it cannot honour. Every hint line in those pictures is a `UiPrompt`;
`tests/unit/ui/prompt_glyphs_test.gd` scans `src/ui` for a string literal that types a
button's name into a sentence again.

The gallery is also where the item icons get reviewed, so the offers `UiFakes` builds are a
different variant from the gear the fake player is wearing (`UiFakes.FAKE_GEAR`): a trade view
with the same rusty sword on both sides of the arrow cannot answer "do any two item icons
collide?", which is the question the surface exists for.

The asset import in front of every capture (`tools/godot-import.sh`) retries once,
and a failed attempt's log is kept as `import-failed-<pid>-attempt<n>.log` even when
the retry succeeds, with the retry named on stderr. The import aborts now and then —
one gallery run printed `godot --import exited 134` (SIGABRT) on attempt 1 and
succeeded on attempt 2 — and the evidence used to be deleted along with it, so
nobody could tell load from a real import bug without reproducing the race.

### Capture scenes

**Six** checks are main scenes rather than gdUnit suites, because the thing they measure only
exists once something has been rendered and tier 1 runs `--headless` (the dummy driver returns no
viewport image at all). `tools/capture-scene.sh` is the harness for all of them, and
`tools/checks.json` is where their ids and their expected outputs live:

```bash
tools/capture-scene.sh prop_frame              # -> tests/out/prop_frame_<biome>.png (5 of them)
tools/capture-scene.sh prop_frame white        # -> tests/out/prop_frame_<biome>_white.png
tools/capture-scene.sh feel_tell               # -> tests/out/feel_tell.png
tools/capture-scene.sh lighting_frame white    # -> tests/out/lighting_{off,low,high}_white.png + lighting_perf_white.txt
tools/capture-scene.sh ui_stats                # -> tests/out/ui_stats_{fresh,one_run,history}.png
tools/capture-scene.sh ui_trade                # -> tests/out/ui_trade_{page1,page2,price}.png
OMADUNGEON_TEST_COPY=1 tools/capture-scene.sh prop_frame gruvbox
```

Until this round there was no harness: the only way to run one was to retype a
`tools/headless-sway.sh godot --path . --rendering-driver opengl3 res://...` line out of the
scene's own doc comment, and nothing in the repository did. `capture-scene.sh` carries the same
four guards as `run-scenario.sh` — the theme fixture must exist (exit 4), the expected PNGs are
deleted first and must come back non-empty and newer than the run (exit 2), one nested compositor
at a time on `tests/out/.scenario.lock` (exit 3 when the wait runs out), and a hard deadline with
a follow-up KILL — and it passes the scene's own exit code straight through, which is how
`prop_frame`'s 2 finally reaches a caller. `tests/unit/feel/tell_capture.gd` now suffixes its
output with the theme like everything else; it used to write the bare `feel_tell.png` whatever
fixture it ran against, so a `white` capture landed straight on top of the `tokyo-night` one.

`ui_stats` and `ui_trade` assert nothing — they are eye checks, marked `"asserts": false` in the
register — but the harness still requires their PNGs to land, so they cannot silently produce
nothing.

`lighting_frame_capture` (`tests/unit/rooms/lighting_frame_capture.gd`) is the lighting layer's
proof: it generates floor 1 for the fixture theme, builds it in the main viewport at each
lighting quality in turn (Off = the look before the layer, Low = darkness + lanterns + emitters,
High = shadows from the nearest 8 lights), samples the wall-clock cost of 180 frames with vsync
off (`FrameSampler`), writes `lighting_<quality>[_<theme>].png` and `lighting_perf[_<theme>].txt`, and at
High measures the frame: the floor within 40 px of the player must clear a mean luminance of
0.04 on a dark theme and 0.35 on a light one ("darkness" never means "black"), and the floor a
tile and a half in from the nearest lantern must be brighter than the floor three tiles along
the same wall (a lantern is a light, not decoration). On a light theme it also holds the other
end: the 99th-percentile floor *pixel* near the player must stay under `LIGHT_FLOOR_CEILING`
(0.90), so the player's own pool cannot blow the paper out and take the tile seams with it. That
one is measured on pixels because a tile mean averages the seams back in and topped out at 0.74
on a fully blown frame - a ceiling written against means could not have fired. Exit 2 otherwise. It runs on
`tokyo-night`, `gruvbox`, `catppuccin-latte` and `white` in the register.

The frame cost it prints is whatever GPU the nested compositor hands Godot, which on this box is
the real card and reads under half a millisecond at every quality — a number that says nothing
about the machine the game has to run on. Put `LIBGL_ALWAYS_SOFTWARE=1` in front of it for the
llvmpipe figure (and raise `CAPTURE_TIMEOUT`, since a software pass takes minutes): that is the
number docs 10 records. A software rasteriser also answers to what else the machine is doing, so
read the *difference* between Off and High rather than any single row.

**A number that is both the bound and the thing bounded is not a guarantee.** Most readability
and mood assertions measure against the same constant the production code places rungs with,
which is right — but it means moving the constant moves the goalposts and the ball together, and
a red check can be turned green by editing the bar instead of the art. Proven by mutation:
halving `Prop.READABLE_CONTRAST`, dropping `LIT_BODY_STEP` to 1.001 and cutting `BLOOM_MAX` to
0.01 each left every ladder test in the repository passing. So the numbers that *are* the
guarantee carry a second assertion against a literal, taken from what the design promises rather
than from today's value: the prop ladder in `prop_render_test.gd`, the drawn-floor lines of
`lighting_frame` in `lighting_rig_test.gd`, the mood deltas and the 15-degree theme hue budget in
`music_mood_test.gd`, and `LootInk.MIN_CONTRAST` in `loot_ink_test.gd`. Direction matters: a
contrast target is a floor, `BLOOM_MAX` and `LIGHT_FLOOR_CEILING` are ceilings, and a pin in the
wrong direction pins nothing. Each one was proved by moving its constant and watching the pin
fail.

`tests/unit/items/loot_ink_test.gd` is the unit half of what `pickup_frame` measures on pixels:
that a drop's ink and its ring together clear `ThemePalette.WORLD_MIN_CONTRAST` against every
world surface *as the lighting layer draws it*, on all six fixtures, and that the ring appears
exactly where one ink cannot carry every surface — the two light fixtures and nowhere else. The
authored-surface guard (`PickupWorldContrastTest`, `PickupWorldRolesTest`) passed on every
fixture while the frame failed, because no check had ever put the guard and the darkness in the
same sentence.

`prop_frame_capture` does not just save a picture: it reads the PNG back and measures every prop
in it — each ramp rung the art paints, against the floor pixels of the same tile, with the room's
own torches on both — and exits 2 when one is under `Prop.READABLE_CONTRAST` or has lost its
interior ladder. It prints one line per prop with the numbers and how much light that tile is
standing in, and props inside a torch pool (past `Prop.BLOOM_MAX`, where the light is a
deliberate blow-out) have their interior reported rather than failed; the contrast against the
floor is never excused. This is the check that would have caught the coffin the owner's verifier
measured at 1.87 against a model that said 2.2: the model-level tests all passed, because none of
them looked at a frame.

**One frame per biome, every kind in it.** One run rebuilds the floor once per `Biome.ALL_IDS`
entry and fills the room with every name `Prop.kind_names()` gives that biome, so a run measures
all **45** cells the game can put on screen (5 biomes × 9 kinds) and writes one PNG each:
`tests/out/prop_frame_<biome>.png`, or `prop_frame_<biome>_<theme>.png` for any fixture but
`tokyo-night`. It used to draw six of the crypt's eight kinds and nothing else, so 34 of the 40
were covered by the model alone — and the model is exactly what missed the coffin. A biome is a
different prop *sheet* under a different tile atlas, so a rung that clears the floor in the crypt
says nothing about the same rung in the forge.

**It waits for the frame to stop changing.** The materials crossfade into the live palette, the
wallpaper analysis that sets the ambient lands when it lands, and the torches flicker ±14% at
2.3 Hz, so a fixed settle photographed whatever phase all of that was in: the same nord room
measured a drawn floor of `77788b` on one run and `797a8c` on the next, and four props moved in
and out of failing between two runs of the same code. The capture now pins the torches at the
base energy `Prop.bloom_for()` is written against and polls until the viewport draws the same
frame twice. Two runs of the same tree print identical numbers, prop for prop.

**What it found before the third clutter redraw** (all six fixtures, 40 props each; the catalogue is 45 now and every kind is redrawn, so the table below is the record of the model's open question, not of the current sheets - `tools/run-checks.sh rendered` says what they measure today). The two light fixtures (`white`,
`catppuccin-latte`) are clean — they were not when the sweep first ran: the prop standing beside
a torch drew **2.14** against a 2.2 target on four of the five biome sheets on `white`, because a
light theme's floor is already clipped at white and an additive torch lifts the prop alone. That
one is fixed (`Prop.ANCHOR_CLEARANCE_MARGIN`, applied only where the body descends from the
floor); the worst light-theme rung now reads 2.30. On the dark fixtures eight props fail the
*interior ladder* — `_worst_step` under `Prop.LIT_BODY_STEP` — and no prop on any fixture fails
contrast against the floor:

| fixture | prop | tile | light | worst step |
|---|---|---|---|---|
| tokyo-night | crypt crate | (12, 3) | +0.11 | 1.05 |
| tokyo-night | crypt urn | (12, 4) | +0.13 | 1.05 |
| tokyo-night | frost urn | (12, 4) | +0.13 | 1.06 |
| gruvbox | crypt coffin | (12, 2) | +0.11 | 1.01 |
| gruvbox | crypt crate | (12, 3) | +0.13 | 1.01 |
| gruvbox | frost crate | (12, 3) | +0.12 | 1.04 |
| nord | library crate | (12, 3) | +0.13 | 1.03 |
| catppuccin | frost crate | (12, 3) | +0.13 | 1.00 |

One more thing the wider sweep shows: a prop is only measured on the rungs its art actually
paints more than `MIN_RUN` pixels of, and several paint far fewer than four. `frost/icicle` paints
one body rung and reports an interior step of 99.00 — it has no interior to lose — and
`crypt/cobweb`, `forge/slag` and `void/beacon` paint two. Those are art decisions, not failures,
but the interior guard says nothing about them, so they are guarded by contrast alone.

Every failure above is a prop whose art paints all four body rungs, standing in +0.11 to +0.13 of
additive light — under `Prop.BLOOM_MAX` (0.13), so inside the band the ladder is guaranteed
across. The collapse is at the *top* of the ramp: nord's crate draws r4 at 3.96 and r5 at 4.10,
catppuccin's draws both at 4.95, and the bottom of the same ramp is spread perfectly well.

One candidate was tried and **ruled out by measurement**, which is worth recording so nobody
spends the afternoon on it twice. `spread_rungs` lets a rung the theme authored past its slot
keep that lead, clamped at `LIT_BODY_CEILING`, and it looked as though the rung above it would
then clamp at the same ceiling and land on the same pixel value. Placing every rung on its slot
instead — dropping the lead entirely — changed the drawn numbers on all six fixtures by
**nothing at all**: every one of the 240 readings came back unchanged. The lead branch is not
what is firing, and that edit was reverted rather than left in the model unearning its keep.

What is left is the light. The rung is placed so that it is drawn at its slot under
`bloom_for()`, and a prop next to a torch is standing in more light than that, so the brightest
rungs saturate before they reach the slots they were placed for. **This is open**: it is a tuning
question across `BLOOM_MAX`, `LIT_BODY_STEP`, `BODY_LUMINANCE_MAX` and `LIT_BODY_CEILING` and it
belongs to whoever owns the colour model — it is not a tolerance to widen here, and the check is
meant to stay red until it is answered.

**And whether it is red is visible from inside the gate — without anybody writing it down.**
The measurements above were taken in the round that found them; what the capture does *today* is
whatever `tools/run-checks.sh rendered` last recorded in `reports/checks/prop-frame.json`, which
`tools/run-checks.sh results` prints and the gate reads. While that record's exit code is
non-zero the tier-1 gate fails and names the check. It used to be a `known_failing` paragraph in
`tools/checks.json` instead: a person's sentence about a run, which went stale the moment the
props moved and which could be cleared without touching a prop. There is nothing to clear now —
the record changes when the capture's exit code changes, and only then.

**Then actually look at the PNG.** A rendered check that nobody opened has
tested nothing. When sway itself fails to start — or when a capture blows the
`SCENARIO_TIMEOUT` deadline (240 s by default; the harness follows the TERM with
a KILL, because a process wedged in GL init ignores TERM and plain `timeout`
then waits for it forever) — its log is copied to
`tests/out/sway-failed-<pid>.log`; otherwise it dies with the throwaway runtime
directory.

A scenario that cannot reach the state it exists to capture now exits non-zero
with no screenshot rather than shooting whatever is on screen: `summary` waits
for the RunSummary node to exist before it fires, and `combat` is driven and
frozen on physics frames so the capture does not shift with machine load.

The same applies to the *file*. The expected PNG is deleted before the run and
has to exist, non-empty, afterwards, so exit 0 can never mean "last run's
picture is still lying there" — a capture into an unwritable directory used to
print an error and still exit 0. Captures also serialise on a lock file
(`tests/out/.scenario.lock`, `SCENARIO_LOCK=0` to opt out): two nested
compositors at once used to fail each other at random, with the same exit code a
real regression returns. Exit codes: 2 = the scenario never reached its subject,
or wrote no PNG; 3 = the lock was still held after `SCENARIO_LOCK_WAIT` (600 s),
which is "the machine was busy", not "the game regressed".

`tools/ui-gallery.sh` now carries the same three guards, which it had none of:
it deletes the `ui_<screen>.png` it expects (read out of `UiGallery.SCREENS`, or
just the one named by `--only`), requires each of them back non-empty and newer
than the run — exit 2 with the list of the ones that did not land — takes the
same `tests/out/.scenario.lock` (`GALLERY_LOCK=0` opts out, `GALLERY_LOCK_WAIT`
bounds it), and copies to `$OMADUNGEON_COPY_DIR`/`$TMPDIR`/`/var/tmp` instead of
`/tmp`. `src/ui/ui_gallery.gd` trusts `image.save_png()`'s return code, which a
missing image or a short write can still pass, so the file is what gets checked.

---

## Tier 3 — a real Omarchy virtual machine

Tier 2 proves the game renders correctly against a *fixture* of the Omarchy
state directory. Tier 3 proves the packaged artefact installs and runs on a
genuine Omarchy desktop and reacts to the real `omarchy-theme-set`.

### What it runs on

QEMU/KVM directly — no libvirt, no `virsh`. Host needs
`qemu-system-x86_64`, `qemu-img`, `/dev/kvm` readable (be in the `kvm` group),
OVMF at `/usr/share/OVMF/OVMF_CODE_4M.fd`, plus `xorriso`, `socat`, `jq`,
`openssl`, `magick` (ImageMagick) and `ssh`/`scp`.

The VM never touches your session: QEMU runs `-display none` with a VNC server
bound to `127.0.0.1:5999`, SSH is a user-mode NAT forward on `127.0.0.1:2222`,
and the monitor is a unix socket. Screenshots come from `grim` running *inside*
the guest, or from QEMU's own framebuffer dump.

### Build one

```bash
tools/vm/fetch-iso.sh                 # ~6 GB -> ~/.cache/omadungeon-vm, sha256-checked
tools/deb.sh full                     # -> dist/omadungeon_<version>_amd64.deb
tools/vm/create.sh --fresh            # the whole bring-up, about 10 minutes
```

`create.sh` runs, in order: `cidata.sh` (build the unattended-install drive and
the VM's ssh key) → `boot.sh install` → `wait-ssh.sh` → `boot.sh run` (install
media detached) → `provision.sh` (SDDM autologin so a real Hyprland session is
actually running) → `install-game.sh`.

The install is unattended through Omarchy's own supported path, not a keystroke
robot: the ISO looks for a drive labelled `cidata` carrying the files its
interactive configurator would have written, and skips the wizard when it finds
them. The optional `authorized_keys` on that drive is what makes the finished
machine reachable — a stock Omarchy ships `sshd` disabled behind a default-deny
firewall, and the installer's own `configure_ssh_access` phase installs the key,
enables the service and opens port 22.

Omarchy is Arch, so there is no `dpkg` on it. `install-game.sh` unpacks the
`.deb`'s own payload with `bsdtar` (libarchive reads the `ar` + `data.tar.xz` a
.deb is made of) into `/`, exactly where dpkg would have put it. The artefact
users download is the artefact that runs; nothing is re-exported for the VM.

### Day-to-day

```bash
tools/vm/boot.sh run                  # start the installed machine
tools/vm/wait-ssh.sh                  # block until it answers
tools/vm/install-game.sh              # push a rebuilt .deb (defaults to newest in dist/)
tools/vm/game.sh start                # launch it in the guest's Hyprland
tools/vm/game.sh key Return           # type into it (wtype); also: hold <key> <ms>
tools/vm/shot.sh dungeon              # grim inside the guest -> tests/out/vm/dungeon.png
tools/vm/run.sh floor                 # a --test-scenario capture on real Omarchy
tools/vm/theme.sh list                # the machine's 22 real themes
tools/vm/theme.sh set gruvbox
tools/vm/theme.sh bg-next
tools/vm/theme.sh state               # what the real state dir says right now
tools/vm/game.sh env                  # the game process's own environment
tools/vm/ssh.sh                       # a shell on the machine
tools/vm/stop.sh                      # shut it down
tools/vm/console-shot.sh boot         # QEMU framebuffer dump: works with no guest network
```

`tools/vm/run.sh <scenario>` is the bridge between tiers 2 and 3: it runs the
same `--test-scenario` driver, but inside the guest's real session against the
guest's real theme, and names the result
`tests/out/vm/scenario-<scenario>-<theme>.png`. A tier-2 capture and a tier-3
capture of the same scenario differ only in "fixture vs. real Omarchy".

`theme_swap` is the one scenario that does *not* belong here: it builds its own
synthetic state directory out of `tests/fixtures/omarchy`, which is not in the
exported PCK. Tier 3 proves the same thing with `verify.sh` against the
machine's real themes instead.

### The live-retint proof

```bash
tools/vm/verify.sh                                  # gruvbox catppuccin-latte nord
tools/vm/verify.sh gruvbox catppuccin-latte nord matte-black
```

It switches the machine's theme once per argument, then advances the wallpaper,
screenshotting from inside the guest after each change, and checks three things
rather than assuming them:

1. **It recoloured** — every capture is taken after the switch and shows the
   theme the machine was on at that moment (the title screen prints it, as
   "Dungeon of \<theme\>").
2. **Without restarting** — the game's pid is sampled before and after every
   change and must be identical throughout; the script fails if it moves.
3. **From the real system paths** — the game process's environment is dumped and
   must carry no `OMADUNGEON_OMARCHY_STATE_DIR`, and the machine is searched for
   any `tests/fixtures/omarchy` tree, of which it has none. That leaves
   `~/.local/state/omarchy/current/` as the only thing it can have read.

If the game is already running it is left alone, so the switches can land on a
live dungeon rather than a freshly booted title screen.

Output: `tests/out/vm/verify.txt` plus one PNG per step. Read the PNGs.

### The fullscreen proof (owner report 12)

```bash
tools/deb.sh full && tools/vm/install-game.sh   # the artefact under test must be current
tools/vm/game.sh start                          # then Down Down Return into Settings
tools/vm/fullscreen.sh prove                    # -> tests/out/vm/vm_fullscreen_{before,after}.png
```

This is the only tier that can answer it. On Wayland nothing in the engine can see a fullscreen
the compositor made (`src/desktop/compositor_window.gd` holds the measurement), so the game asks
Hyprland — and whether that works can only be seen on a machine with a Hyprland.

`prove` refuses to produce evidence it does not believe in, because both of the ways this issue
was signed off before turned out to be worthless:

* it **checks the binary under test first**, by md5 against the `.deb` in `dist/` (or `$DEB`),
  and fails naming both — a previous round's screenshots were taken against a build that
  predated the fix. It caught a live rebuild by another agent the first time it ran;
* and it **compares the two PNGs afterwards**, failing if they are byte-identical — a previous
  round's "before and after" were the same file twice.

The fullscreen is made with the dispatcher Omarchy's SUPER+F is bound to
(`hl.dsp.window.fullscreen({ mode = "fullscreen" })`, from `hypr/bindings/tiling.lua`) rather
than by typing the key: **Hyprland does not run keybinds for `wtype`'s virtual keyboard**.
Measured — `wtype -M logo -k f -m logo` leaves `fullscreen: 0`, and so does SUPER+T, while the
same `wtype` drives the game's own menus perfectly well. Same dispatcher, same window, and the
game is told nothing either way, which is the part under test.

What it proves today: the checkbox follows the compositor into fullscreen and back out, and
unticking the row leaves a compositor-made fullscreen. What it does not prove, because it is not
true, is that the row can *enter* fullscreen on Hyprland — see `PATCH_LIST.md` §24, where the
three measurements are written down, one of them Godot's own `-f` flag.

### Troubleshooting

* **`/dev/kvm` not readable** — `sudo usermod -aG kvm $USER`, then log out and in.
* **The install seems stuck** — `tools/vm/console-shot.sh` dumps the guest's
  framebuffer through the QEMU monitor and works long before the guest has a
  network. The guest's own log is `/var/log/omarchy-install.log`.
* **No Hyprland session** — `tools/vm/provision.sh` is what configures SDDM
  autologin; without it the machine sits on the greeter with nobody to type the
  password. `ls /run/user/1000/hypr` in the guest tells you whether a session
  exists.
* **The game window never appears** — `tools/vm/game.sh log`. `MESA-EGL: failed
  to create dri2 screen` is expected and harmless: the guest has no GPU, so Mesa
  falls back to llvmpipe, which is plenty for a 480×270 internal resolution.
* **Stale `.deb`** — `install-game.sh` installs whatever is newest in `dist/`.
  If the title screen looks nothing like the current code, you are looking at an
  old artefact: rebuild with `tools/deb.sh full` first.

### Packaging checks that belong with this tier

```bash
tools/deb.sh both                     # full + lite .deb into dist/
tools/check-deb-deps.sh --check       # derived Depends vs. debian/control
tools/check-package-layout.sh         # unpack each .deb, check the layout, start it clean
tools/appimage.sh                     # the AppImage variant
```

`tools/check-package-layout.sh` is `tools/run-checks.sh package`'s third step and it used to be
thirty lines of YAML inside `.github/workflows/ci.yml`: two real assertions — every installed
path the `.desktop` file and the icon theme depend on, and one headless run with an empty `HOME`,
no Omarchy state and no otter shell, which is the state every plain Debian or Ubuntu machine is
in — that nobody could run locally and that no register knew existed. The smoke run is judged by
its **log**, not its exit status, because `push_error()` writes `ERROR:` and still exits 0: a
bare `--quit-after` once passed a package whose every colour came out magenta.

Two engine lines are excluded from that judgement and printed as a note instead —
`N resources still in use at exit` and `N ObjectDB instances were leaked at exit` — the same
distinction `tools/godot-import.sh` already makes. They are shutdown bookkeeping, they appear on
runs that are otherwise clean (the shipped binary prints both today, `PATCH_LIST.md` §19), and
this check is asking a different question: does the built-in fallback palette carry a machine
with no Omarchy and no otter shell? Everything else in the log still fails the packages.

`tools/deb.sh` verifies the export before it packages it: every non-resource
file the game loads by path has to be present in the PCK, and the binary has to
run headless with no desktop theme present without logging an engine error.
Re-run `check-deb-deps.sh --check` after any Godot upgrade — the export template
`dlopen()`s nearly everything, so `dpkg-shlibdeps` alone sees only libc.

---

## Which tier for which change

| You changed | Run |
|-------------|-----|
| Generation, loot, combat, stats, abilities | tier 1, with a seeded test |
| A UI screen, the HUD, a shader | tier 1, then tier 2 in a dark *and* a light theme |
| Anything reading `Desktop.palette` / `ThemeProfile` | tier 2 across several fixtures, then tier 3 `verify.sh` |
| A prop, hazard or interactable's readability | tier 1 `tests/unit/rooms/prop_tint_test` + `prop_render_test` (every biome's sheet: body coverage, and the *edge* - a solid's ink ring, a flat's outer pixels - against the floor on all six fixtures, dry and lit), then `tools/capture-scene.sh prop_frame <fixture>` on a dark *and* a light fixture — a contrast model cannot see an additive light. One run covers every biome and every kind, so there is no per-prop capture to remember |
| Whether a prop blocks the player, or its art | tier 1 `tests/unit/rooms/prop_test` (`Prop.SOLID`, `rooms_content.tres`, `tools/art/prop_solid.json` and the shipped PNG held to one table - ink outline and contact shadow on a solid, neither on a flat - plus a `CharacterBody2D` pushed at a barrel and at bones), then `tools/run-scenario.sh floor <fixture>` on a dark and a light fixture and *look*: an upright object has an outline and a shadow, a flat one has neither. Open `tests/out/art_props_all.png` (`python3 tools/art/gen_all.py --sheets`) and name every kind without reading the label |
| Where props stand in a room | tier 1 `tests/unit/rooms/prop_placement_test` (`PropPlacement` on a hand-built room, then real generated floors: solids on wall-side tiles in clusters, flats sparse in the open, nothing in a doorway or on the door-to-door line), then `tools/run-scenario.sh floor <fixture>` and look for open floor in the middle of every room |
| The dungeon's lighting, exposure or tinting | tier 1 `tests/unit/desktop` + `tests/unit/rooms` (they hold *both* halves: `environment_lighting_test`/`floor_lighting_test` guard readability, `theme_identity_test` guards that the themes stay apart, `theme_look_test` that they stay apart by an amount a person can see and that the wallpaper lights the room without moving one hue of it, `otter_theme_fidelity_test` that the owner's own otter-shell machine renders in its own theme colour, `dungeon_light_test` that the lights stay additive, `lighting_occluders_test` that every wall tile is inside a merged occluder run and every lantern anchor faces open ground clear of doors, `lighting_rig_test` that the darkness, lanterns, shadow cap, unexplored shade and quality switch behave on all six fixtures and that a cleared floor leaves no light behind, `lighting_emitter_test` that every gameplay light is a tuned row of the table and rises, fades and pools without a step, `live_swap_test` that lanterns and emitters retint with the tiles, and `prop_render_test` holds the prop interior ladder - which caps how far the room's own chroma may be lifted, see `ThemePalette.ROOM_CAST_SATURATION`), then tier 2 `floor` **and** `combat` on all six fixtures and look at the PNGs, and `tools/capture-scene.sh lighting_frame <theme>` for the ms/frame and the legibility line |
| A theme-to-generation lever (`ThemeProfile`, `GenParams`) | tier 1 `tests/unit/reactivity` (`theme_layout_test` for the orderings and the difficulty band, `theme_shape_test` for the spread between fixtures and the hazard tilt) and `tests/unit/gen`; then tier 2 `floor` on two fixtures and compare the plans |
| Packaging, the export preset, `debian/` | `tools/deb.sh`, `check-deb-deps.sh --check`, then tier 3 from `--fresh` |
| The Omarchy integration itself (`src/desktop/**`) | all three; tier 3 is the only one that can catch a wrong real-world path |
| A tool, a harness, or anything under `tools/` | declare it in `tools/checks.json` — **one inventory entry per file**, no directory claims (the gate fails on an undeclared file) — and if it is a check give it a `checks[]` entry and a CI tier, or `runs: manual` with a `why_manual`. Then run its tier once, so the ledger has a record of it |
| Nothing in particular, before you claim the tree is green | `tools/run-checks.sh cheap`, `rendered`, `soak`, `package`, then `unit` **last** — the gate reads the records the others write, so a gate run before them fails naming the checks with no result. `tools/run-checks.sh verify` answers "what is missing?" without a gate run |
