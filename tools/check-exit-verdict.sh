#!/usr/bin/env bash
# Proves that a watchdog kill cannot turn a failing run into a passing one.
#
# Why this exists. `QuitGuard.request(tree, code)` arms a detached watchdog and then asks the
# tree to quit; when the engine wedges in Godot 4.7.1's Wayland teardown the watchdog's SIGTERM
# is what ends the process, so it exits 143 and the code the run asked for is gone. The
# harnesses used to fill that gap by assuming a pass whenever the pictures had landed - and
# pictures landing is not evidence of a pass, because a capture scene reads its own PNGs back
# and asserts on them. Measured 2026-09-14: a `pickup_frame` capture printed four FAIL contrast
# rows, called `request(tree, 2)`, hung on the way out and was recorded in the results ledger as
# ok. The rate of that false green is the rate of the hang, which is not small.
#
# The fix is that `request()` writes the code to `$OMADUNGEON_EXIT_FILE` before arming, and the
# harnesses read it back. This check is the part that stops the old behaviour returning.
#
# How it forces the wedge without waiting for one. The hang is a race and cannot be summoned on
# demand, but what a harness *sees* of it can be reproduced exactly: a process that writes its
# PNG, records a code, and then dies by SIGTERM. `tools/run-scenario.sh` takes `GODOT_BIN`, so a
# stub standing in for the engine produces that signature every time, and the harness under test
# is the real one, unmodified, with its real nested compositor and its real lock.
#
# Three states, because the interesting one is the third:
#   recorded 2  -> the harness must report 2. This is the laundering bug; it must fail.
#   recorded 0  -> the harness must report 0, and say the engine hung.
#   no file     -> the harness must fail. A verdict that died with the process is not a green
#                  one, and "we did not hear" must never read as "it passed".
# The shipped 143 branch of `tools/ui-gallery.sh` is then driven over the same three states
# directly out of the file, so the text under test is the text that ships there too.
#
# Usage: tools/check-exit-verdict.sh
set -uo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d "${TMPDIR:-/var/tmp}/omadungeon-exitverdict-XXXXXX")"
# A suffix of our own, so a stub run can never overwrite a real capture in tests/out.
suffix="_exitverdict"
shot="$PWD/tests/out/floor${suffix}.png"
cleanup() {
  rm -rf -- "$work"
  rm -f -- "$shot"
  rm -f -- "$PWD"/tests/out/*_exitverdict.png
}
trap cleanup EXIT

failures=0
note() { echo "check-exit-verdict: $*"; }
fail() {
  echo "check-exit-verdict: FAIL $*" >&2
  failures=$((failures + 1))
}

# The stand-in for the engine. Writes the PNG the harness is waiting for, records the code the
# run "asked for" the way QuitGuard would, then ends itself with SIGTERM exactly as the watchdog
# does. STUB_CODE is the code to record; STUB_NOFILE=1 records nothing, which is the case where
# the process died before it could say anything.
cat >"$work/stub-godot" <<'STUB'
#!/usr/bin/env bash
set -u
dir=""
suffix=""
prev=""
for arg in "$@"; do
  case "$prev" in
    --screenshot-dir) dir="$arg" ;;
    --screenshot-suffix) suffix="$arg" ;;
  esac
  prev="$arg"
done
# A capture scene writes its own files and is told where by nothing on the command line, so
# the caller names them in STUB_PNGS; the scenario driver is told by --screenshot-dir.
if [[ -n "${STUB_PNGS:-}" ]]; then
  for png in $STUB_PNGS; do
    printf 'not a real png, but non-empty\n' >"$png"
  done
elif [[ -n "$dir" ]]; then
  printf 'not a real png, but non-empty\n' >"$dir/floor${suffix}.png"
fi
if [[ "${STUB_NOFILE:-0}" != "1" && -n "${OMADUNGEON_EXIT_FILE:-}" ]]; then
  printf '%s\n' "${STUB_CODE:-0}" >"$OMADUNGEON_EXIT_FILE"
fi
# What the watchdog does to a wedged engine, minus the wait.
kill -TERM $$
sleep 30
STUB
chmod +x "$work/stub-godot"

run_case() {
  local label="$1" expectation="$2"
  shift 2
  local status=0
  # `floor` and the `white` fixture only so the harness has a real scenario and theme to name;
  # nothing of the game runs, because GODOT_BIN is the stub.
  env "$@" GODOT_BIN="$work/stub-godot" SCENARIO_SUFFIX="$suffix" SCENARIO_TIMEOUT=90 \
    tools/run-scenario.sh floor white >"$work/$label.log" 2>&1 || status=$?
  case "$expectation" in
    pass)
      if ((status == 0)); then
        note "$label: the harness reported 0, as it should"
      else
        fail "$label: a run that recorded 0 was reported as $status, not a pass"
        sed -n '1,20p' "$work/$label.log" >&2
      fi
      ;;
    fail)
      if ((status != 0)); then
        note "$label: the harness reported $status - the finding survived the signal"
      else
        fail "$label: THE LAUNDERING IS BACK - a run killed by the watchdog was reported as a pass"
        sed -n '1,20p' "$work/$label.log" >&2
      fi
      ;;
  esac
}

note "driving tools/run-scenario.sh with an engine that dies by SIGTERM"
run_case "recorded-2" fail STUB_CODE=2
run_case "recorded-0" pass STUB_CODE=0
run_case "no-verdict" fail STUB_NOFILE=1

# The same three states over the shipped 143 branch of tools/ui-gallery.sh, taken out of the
# file itself rather than retyped, so this cannot pass while the real script says something else.
branch="$work/ui-gallery-branch.sh"
sed -n "/^# 143 is SIGTERM from the game's own quit watchdog/,/^fi$/p" tools/ui-gallery.sh >"$branch"
if [[ ! -s "$branch" ]]; then
  fail "could not find the 143 branch in tools/ui-gallery.sh; has it been renamed?"
else
  note "driving the shipped 143 branch of tools/ui-gallery.sh"
  for state in 2 0 missing; do
    exit_file="$work/ef"
    rm -f "$exit_file"
    [[ "$state" != "missing" ]] && printf '%s\n' "$state" >"$exit_file"
    status=143
    # shellcheck disable=SC1090
    . "$branch" >/dev/null 2>&1
    case "$state" in
      2) ((status == 2)) && note "ui-gallery branch: a recorded 2 stays 2" || fail "ui-gallery branch: a recorded 2 became $status" ;;
      0) ((status == 0)) && note "ui-gallery branch: a recorded 0 passes" || fail "ui-gallery branch: a recorded 0 became $status" ;;
      missing) ((status != 0)) && note "ui-gallery branch: no verdict fails ($status)" || fail "ui-gallery branch: no verdict was treated as a pass" ;;
    esac
  done
fi

# And tools/capture-scene.sh, which is the harness the false green actually came through: a
# `pickup_frame` capture printed four FAIL rows, asked to exit 2, hung, and was recorded ok.
# Same stub, same three states. CAPTURE_SUFFIX keeps the stub's files out of the real captures.
capture_suffix="_exitverdict"
capture_scene="ui_stats"
mapfile -t capture_pngs < <(python3 tools/checks.py scene-outputs "$capture_scene" "$capture_suffix")
if ((${#capture_pngs[@]} == 0)); then
  fail "tools/checks.py scene-outputs named no files for $capture_scene; cannot drive capture-scene.sh"
else
  capture_paths=()
  for name in "${capture_pngs[@]}"; do
    capture_paths+=("$PWD/tests/out/$name")
  done
  cleanup_capture() { rm -f -- "${capture_paths[@]}"; }
  note "driving tools/capture-scene.sh with an engine that dies by SIGTERM"
  run_capture_case() {
    local label="$1" expectation="$2"
    shift 2
    local status=0
    cleanup_capture
    env "$@" GODOT_BIN="$work/stub-godot" STUB_PNGS="${capture_paths[*]}" \
      CAPTURE_SUFFIX="$capture_suffix" CAPTURE_TIMEOUT=90 \
      tools/capture-scene.sh "$capture_scene" white >"$work/$label.log" 2>&1 || status=$?
    case "$expectation" in
      pass)
        if ((status == 0)); then
          note "$label: capture-scene reported 0, as it should"
        else
          fail "$label: a capture that recorded 0 was reported as $status, not a pass"
          sed -n '1,20p' "$work/$label.log" >&2
        fi
        ;;
      fail)
        if ((status != 0)); then
          note "$label: capture-scene reported $status - the finding survived the signal"
        else
          fail "$label: THE LAUNDERING IS BACK in capture-scene.sh - a killed run reported a pass"
          sed -n '1,20p' "$work/$label.log" >&2
        fi
        ;;
    esac
  }
  run_capture_case "capture-recorded-2" fail STUB_CODE=2
  run_capture_case "capture-recorded-0" pass STUB_CODE=0
  run_capture_case "capture-no-verdict" fail STUB_NOFILE=1
  cleanup_capture
fi

if ((failures > 0)); then
  echo "check-exit-verdict: $failures case(s) failed; a hung run can be recorded as a pass." >&2
  exit 1
fi
note "ok - a watchdog kill cannot report a pass the run did not ask for"
