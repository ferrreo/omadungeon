#!/usr/bin/env python3
"""Reader for ``tools/checks.json``, the register of every check this repository owns.

Shell cannot parse JSON, and three things need to agree about the register:
``tools/run-checks.sh`` (which runs a tier of it), ``tools/capture-scene.sh`` (which needs a
scene's path and the PNGs it must leave behind) and ``tests/unit/tools/check_registry_test.gd``
(which is in the gate and fails when a check has no runner). Duplicating the parsing three
times is how they drift apart, so it lives here once.

Pure stdlib: it has to run anywhere the test suite runs, with nothing to install.

The results ledger
------------------
A check that ran leaves a record behind: ``reports/checks/<id>.json``, written by
``tools/run-checks.sh`` with the check's identity, the exact invocations it made, their exit
codes and the wall clock either side of them. That file is the only thing that can say a check
passed. Nothing in ``tools/checks.json`` may claim it: the register says what a check *is* and
what must run it, the ledger says what happened, and the gate
(``tests/unit/tools/check_registry_test.gd``) reads the ledger. The previous arrangement -
a ``known_failing`` string somebody typed - made the gate's colour a function of an editable
field, and it was stale within the hour of being written.

Subcommands
-----------
    tools/checks.py ids [<tier>]              check ids, optionally only one tier's
    tools/checks.py tiers                     every tier named in the register
    tools/checks.py plan <tier>|<id>|all      one TAB-separated row per invocation:
                                              id, env assignments, then the argv
    tools/checks.py required                  ids the gate demands a fresh passing result for
    tools/checks.py record <id> ...           write a result record (see `record`)
    tools/checks.py verify [<tier>|all]       exit 1 naming every required check whose record
                                              is missing, stale or failing
    tools/checks.py results                   one line per record in the ledger
    tools/checks.py scene-ids                 capture-scene ids
    tools/checks.py scene-path <scene-id>     that scene's res:// path
    tools/checks.py scene-outputs <id> <sfx>  the PNG basenames it must write
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import socket
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
REGISTER = ROOT / "tools" / "checks.json"
## The tier the gate itself is in. Its result cannot be a precondition of its own run, so it is
## the one tier `required()` leaves out; `tests/unit/tools/check_registry_test.gd` checks that
## nothing else has been parked in there.
GATE_TIER = "unit"
DEFAULT_MAX_AGE_HOURS = 48.0


def load() -> dict:
    """The register, parsed."""
    with REGISTER.open(encoding="utf-8") as handle:
        return json.load(handle)


def text(value: object) -> str:
    """A register field that may be a string or a list of lines, as one string."""
    if isinstance(value, list):
        return "\n".join(str(line) for line in value)
    return str(value)


def policy(data: dict) -> dict:
    """The register's policy block: where results live and how old one may be."""
    return data.get("policy", {}) or {}


def results_dir(data: dict | None = None) -> pathlib.Path:
    """Where result records are written and read.

    ``OMADUNGEON_CHECK_RESULTS_DIR`` overrides it, and ``tools/test.sh`` sets that when it runs
    the gate against an rsync'd copy of the project: the copy excludes ``reports/``, so a gate
    running inside one would otherwise look for the ledger in a directory the rsync never made
    and conclude that nothing has ever been run.
    """
    env = os.environ.get("OMADUNGEON_CHECK_RESULTS_DIR")
    if env:
        return pathlib.Path(env)
    relative = str(policy(data or load()).get("results_dir", "reports/checks"))
    return ROOT / relative


def max_age_hours(data: dict) -> float:
    """How old a record may be before the gate calls it no evidence at all."""
    return float(policy(data).get("result_max_age_hours", DEFAULT_MAX_AGE_HOURS))


def plan_lines(check: dict) -> list[str]:
    """Every invocation this check makes, one line each, exactly as the runner would type it.

    This is what a record is pinned to. A matrix row added to the register, a theme dropped
    from one, a changed command - any of them makes the recorded plan stop matching the
    register's, and the record stops counting as evidence about the check as it is declared
    today.
    """
    env = " ".join("%s=%s" % kv for kv in sorted(check.get("env", {}).items()))
    out = []
    for row in check.get("matrix", [[]]):
        argv = list(check["command"]) + list(row)
        out.append((env + " " + " ".join(argv)).strip())
    return out


def required(data: dict) -> list[dict]:
    """Every check the gate demands a fresh, passing record for.

    Derived, never declared: it is every check the register says CI runs, apart from the gate's
    own tier. There is deliberately no field a check can carry to excuse itself - the only way
    out is ``runs: manual``, which already has to say what runs it instead.
    """
    return [c for c in data["checks"] if c.get("runs") == "ci" and c.get("tier") != GATE_TIER]


def record_path(check_id: str, data: dict | None = None) -> pathlib.Path:
    return results_dir(data) / ("%s.json" % check_id)


def read_record(check_id: str, data: dict | None = None) -> dict | None:
    """The record left by the last run of this check, or None when it has never run here."""
    path = record_path(check_id, data)
    try:
        with path.open(encoding="utf-8") as handle:
            loaded = json.load(handle)
    except (OSError, ValueError):
        return None
    return loaded if isinstance(loaded, dict) else None


def verdict(check: dict, data: dict, now: float | None = None) -> str:
    """"" when this check's record says it passed, or the reason it does not."""
    now = time.time() if now is None else now
    record = read_record(str(check["id"]), data)
    if record is None:
        return "never run here: no %s" % record_path(str(check["id"]), data).relative_to(ROOT)
    want = plan_lines(check)
    got = [str(line) for line in record.get("plan", [])]
    if got != want:
        return "recorded against a different plan (%d invocation(s), now %d): re-run it" % (
            len(got),
            len(want),
        )
    exit_code = int(record.get("exit", -1))
    finished = float(record.get("finished", 0.0))
    age = (now - finished) / 3600.0
    if exit_code != 0:
        return "last run exited %d, %.1f h ago" % (exit_code, age)
    if age > max_age_hours(data):
        return "last passed %.1f h ago; the register allows %.1f h" % (age, max_age_hours(data))
    return ""


def checks(data: dict, selector: str | None = None) -> list[dict]:
    """Every check, only the ones in a tier, or the single check with that id.

    A bare check id is accepted anywhere a tier is, because the thing you want after fixing one
    red check is to run *that* check and have its record replace the failing one - not to sit
    through the other 40 invocations of its tier. `test_no_check_id_collides_with_a_tier_name`
    in the gate keeps the two namespaces apart.
    """
    if selector not in (None, "all") and not any(c["tier"] == selector for c in data["checks"]):
        by_id = [c for c in data["checks"] if c["id"] == selector]
        if by_id:
            return by_id
    return [c for c in data["checks"] if selector in (None, "all", c["tier"])]


def scene(data: dict, scene_id: str) -> dict | None:
    """The capture-scene entry with this id."""
    for entry in data["capture_scenes"]:
        if entry["id"] == scene_id:
            return entry
    return None


def scene_outputs(data: dict, scene_id: str, suffix: str) -> list[str]:
    """The PNG basenames ``scene_id`` must leave in tests/out for this theme suffix."""
    entry = scene(data, scene_id)
    if entry is None:
        return []
    for check in data["checks"]:
        if check["id"] == entry.get("check"):
            return [name.replace("%s", suffix) for name in check.get("outputs", [])]
    return []


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    data = load()
    command = argv[0]
    if command == "ids":
        tier = argv[1] if len(argv) > 1 else None
        for check in checks(data, tier):
            print(check["id"])
        return 0
    if command == "tiers":
        seen: list[str] = []
        for check in data["checks"]:
            if check["tier"] not in seen:
                seen.append(check["tier"])
        print("\n".join(seen))
        return 0
    if command == "plan":
        if len(argv) < 2:
            print("checks.py plan needs a tier (or 'all')", file=sys.stderr)
            return 2
        selected = checks(data, argv[1])
        if argv[1] != "all" and not selected:
            # A tier nobody declared is a typo, and a typo that runs nothing must not look
            # like a tier that passed.
            print("checks.py: no tier or check called %r" % argv[1], file=sys.stderr)
            return 3
        for check in selected:
            if check.get("runs") != "ci":
                continue
            # "-" rather than an empty field: bash collapses runs of IFS whitespace, and a
            # tab is IFS whitespace, so an empty env column would vanish and shift every
            # argument left by one. `tools/run-checks.sh` reads "-" as "no environment".
            env = " ".join("%s=%s" % kv for kv in sorted(check.get("env", {}).items())) or "-"
            for row in check.get("matrix", [[]]):
                argv_row = list(check["command"]) + list(row)
                print("\t".join([check["id"], env] + argv_row))
        return 0
    if command == "required":
        for check in required(data):
            print(check["id"])
        return 0
    if command == "record":
        return _record(data, argv[1:])
    if command == "results":
        for check in data["checks"]:
            record = read_record(str(check["id"]), data)
            if record is None:
                print("%-14s  never run here" % check["id"])
                continue
            print(
                "%-14s  exit %-3d  %s  %d invocation(s)  %.0fs"
                % (
                    check["id"],
                    int(record.get("exit", -1)),
                    time.strftime("%Y-%m-%d %H:%M", time.localtime(record.get("finished", 0))),
                    len(record.get("plan", [])),
                    float(record.get("finished", 0)) - float(record.get("started", 0)),
                )
            )
        return 0
    if command == "verify":
        tier = argv[1] if len(argv) > 1 else "all"
        bad = []
        for check in required(data):
            if tier not in ("all", check["tier"]):
                continue
            why = verdict(check, data)
            if why:
                bad.append("%s (%s): %s" % (check["id"], check["tier"], why))
        for line in bad:
            print("checks.py verify: %s" % line, file=sys.stderr)
        if bad:
            print(
                "checks.py verify: %d check(s) have no usable result. Run them:"
                " tools/run-checks.sh <tier>" % len(bad),
                file=sys.stderr,
            )
            return 1
        print("checks.py verify: every required check has a passing result in %s" % results_dir(data))
        return 0
    if command == "scene-ids":
        print(" ".join(entry["id"] for entry in data["capture_scenes"]))
        return 0
    if command == "scene-path":
        entry = scene(data, argv[1]) if len(argv) > 1 else None
        if entry is None:
            return 1
        print(entry["path"])
        return 0
    if command == "scene-outputs":
        if len(argv) < 2:
            return 2
        suffix = argv[2] if len(argv) > 2 else ""
        for name in scene_outputs(data, argv[1], suffix):
            print(name)
        return 0
    print("checks.py: unknown subcommand %r" % command, file=sys.stderr)
    return 2


def _record(data: dict, args: list[str]) -> int:
    """Write the record of a run. Only `tools/run-checks.sh` calls this.

    Everything in the record is observed rather than claimed: the exit code is the one the
    process returned, the timestamps are the clock either side of it, and the plan is derived
    from the register at the moment of the run, so a record cannot outlive the shape of the
    check it describes.
    """
    parser = argparse.ArgumentParser(prog="checks.py record")
    parser.add_argument("id")
    parser.add_argument("--exit", dest="exit_code", type=int, required=True)
    parser.add_argument("--started", type=float, required=True)
    parser.add_argument("--finished", type=float, required=True)
    parser.add_argument("--failed-rows", type=int, default=0)
    parsed = parser.parse_args(args)
    check = next((c for c in data["checks"] if c["id"] == parsed.id), None)
    if check is None:
        print("checks.py record: no check %r in the register" % parsed.id, file=sys.stderr)
        return 2
    record = {
        "id": parsed.id,
        "tier": check["tier"],
        "exit": parsed.exit_code,
        "started": parsed.started,
        "finished": parsed.finished,
        "seconds": round(parsed.finished - parsed.started, 3),
        "plan": plan_lines(check),
        "failed_rows": parsed.failed_rows,
        "host": socket.gethostname(),
        "pid": os.getpid(),
        "recorded_by": "tools/run-checks.sh",
    }
    directory = results_dir(data)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / ("%s.json" % parsed.id)
    # Written whole and moved into place: a record half-written by a run that was killed would
    # be a check with no result at all, which reads as "never run" rather than as a truncated
    # file, and the gate would say something untrue about why.
    temporary = path.with_suffix(".json.tmp-%d" % os.getpid())
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(record, handle, indent=2, sort_keys=True)
        handle.write("\n")
    temporary.replace(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
