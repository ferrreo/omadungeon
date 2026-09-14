#!/usr/bin/env bash
# Runs a whole tier of the register in tools/checks.json and reports which parts of it failed.
# Usage: tools/run-checks.sh <tier|check id|all|list|verify|results>
#   cheap    compile + style
#   unit     the gdUnit4 gate
#   rendered every capture that needs a compositor: scenarios, the UI gallery, the four
#            capture scenes, the weapon pose sheets
#   soak     the death/drop/teardown soak
#   package  both .deb variants and their Depends
#   vm       tier 3 - declared, never run from here (it needs /dev/kvm; see why_manual)
#   all      every tier above whose checks are marked runs: ci
#   <id>     one check by name, all of its matrix rows - what you want after fixing one red
#            check, rather than sitting through the other 40 invocations of its tier
#   list     print the register instead of running it
#   results  print the ledger: what every check did the last time it ran here
#   verify   exit 1 naming every check whose recorded result is missing, stale or failing
#
# Every check that runs here leaves a record behind - tools/checks.py record, one
# reports/checks/<id>.json per check, carrying the check's identity, the exact invocations the
# register asked for, the exit code the process returned and the clock either side of it. That
# ledger is what tests/unit/tools/check_registry_test.gd reads, which is how the gate's colour
# came to mean anything about the 41 invocations outside tier 1. It is written by this script
# and by nothing else; there is no field anywhere a person can set to make a check look green.
#
# Why: for five rounds the release gate was `tools/test.sh -c` and nothing else, and every
# rendered check in the tree was a command typed by hand out of a doc comment. One of them -
# tests/unit/rooms/prop_frame_capture, which exits 2 rather than merely printing - had been
# failing on the default theme the whole time, and the gate reported green over it. This is
# the runner that makes "did every check this repository owns pass?" a question with one
# answer. tests/unit/tools/check_registry_test.gd is the other half: it is inside the gate and
# it fails when a check exists with no runner, and when a check this file is supposed to run
# has no recent record here or has a record that says it failed.
#
# Manual checks are listed and deliberately not run; the register says what runs them instead.
# Nothing here opens a window on the real session: every rendered check goes through
# tools/headless-sway.sh.
#
# Exit: 0 when every check that ran passed, 1 when any of them failed.
set -uo pipefail
cd "$(dirname "$0")/.."
tier="${1:-all}"

if [[ "$tier" == "results" ]]; then
  exec python3 tools/checks.py results
fi

if [[ "$tier" == "verify" ]]; then
  exec python3 tools/checks.py verify "${2:-all}"
fi

if [[ "$tier" == "list" || "$tier" == "--list" ]]; then
  python3 - <<'PY'
import sys
sys.path.insert(0, "tools")
import checks

data = checks.load()
width = max(len(c["id"]) for c in data["checks"])
required = {c["id"] for c in checks.required(data)}
for check in data["checks"]:
    # The flag is read out of the ledger, never out of the register: "RED" means a recorded
    # exit code, "?" means no usable record, and neither is a sentence anyone can type.
    if check["id"] in required:
        why = checks.verdict(check, data)
        flag = "   " if not why else ("RED" if "exited" in why else "  ?")
    else:
        flag = "man" if check["runs"] == "manual" else "   "
    rows = len(check.get("matrix", [[]]))
    print("%s  %-*s  %-8s  %-6s  x%-3d %s" % (
        flag, width, check["id"], check["tier"], check["runs"], rows, check["title"]))
for check in data["checks"]:
    if check["runs"] == "manual":
        print("\nmanual %s:\n%s" % (check["id"], checks.text(check["why_manual"])))
    elif check["id"] in required:
        why = checks.verdict(check, data)
        if why:
            print("\nno usable result for %s: %s" % (check["id"], why))
PY
  exit 0
fi

plan="$(python3 tools/checks.py plan "$tier")" || exit $?
if [[ -z "$plan" ]]; then
  # A tier whose every check is manual runs nothing, and "nothing ran" must never print as a
  # pass - that is the failure this whole register exists to end.
  echo "run-checks: '$tier' has no check with runs: ci." >&2
  echo "run-checks: 'tools/run-checks.sh list' says what runs it instead." >&2
  exit 1
fi

failed=()
passed=0
# The check the loop is inside, and what has happened to it so far. A check is one register
# entry however many matrix rows it has, so the record is written when the last of its rows is
# done - with the worst exit code any row returned, because a check with one red row is red.
cur_id=""
cur_start=0
cur_exit=0
cur_failed=0
record_current() {
  [[ -n "$cur_id" ]] || return 0
  python3 tools/checks.py record "$cur_id" \
    --exit "$cur_exit" --started "$cur_start" --finished "$(date +%s)" \
    --failed-rows "$cur_failed" ||
    echo "run-checks: could not record the result of $cur_id" >&2
}
while IFS=$'\t' read -r -a row; do
  [[ ${#row[@]} -ge 3 ]] || continue
  id="${row[0]}"
  env_spec="${row[1]}"
  argv=("${row[@]:2}")
  if [[ "$id" != "$cur_id" ]]; then
    record_current
    cur_id="$id"
    cur_start=$(date +%s)
    cur_exit=0
    cur_failed=0
  fi
  echo "=== $id: ${argv[*]}"
  start=$(date +%s)
  status=0
  # "-" is checks.py's stand-in for an empty environment; see the note beside it there.
  if [[ -n "$env_spec" && "$env_spec" != "-" ]]; then
    # shellcheck disable=SC2086
    env $env_spec "${argv[@]}" || status=$?
  else
    "${argv[@]}" || status=$?
  fi
  took=$(($(date +%s) - start))
  if ((status == 0)); then
    echo "--- $id ok (${took}s)"
    passed=$((passed + 1))
  else
    echo "--- $id FAILED exit $status (${took}s)" >&2
    failed+=("$id: ${argv[*]} -> exit $status")
    cur_failed=$((cur_failed + 1))
    ((status > cur_exit)) && cur_exit=$status
  fi
done <<<"$plan"
record_current

echo
echo "run-checks: '$tier': $passed passed, ${#failed[@]} failed; results recorded in" \
  "$(python3 -c 'import sys; sys.path.insert(0, "tools"); import checks; print(checks.results_dir())')."
if ((${#failed[@]} > 0)); then
  printf 'run-checks:   %s\n' "${failed[@]}" >&2
  exit 1
fi
exit 0
