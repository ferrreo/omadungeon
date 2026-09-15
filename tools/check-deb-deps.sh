#!/usr/bin/env bash
# Derives the Debian runtime dependencies of the exported Omadungeon binary and
# prints ready-to-paste Depends/Recommends/Suggests lines for debian/control.
#
# The Godot Linux export template links only against the C library and opens
# everything else - X11, Wayland, GL, ALSA, udev - with dlopen() at runtime.
# dpkg-shlibdeps therefore sees nothing but libc6, which is why this script
# exists: it reads the ELF NEEDED list *and* the dlopen'd SONAMEs recorded as
# strings in the binary, resolves each SONAME through the dynamic linker cache,
# and asks dpkg which package owns the resulting file.
#
# Usage:
#   tools/check-deb-deps.sh [--check] [binary]
#     --check   compare the derived Depends, Recommends and Suggests sets
#               against BOTH binary stanzas of debian/control - omadungeon and
#               omadungeon-lite carry the same lists - and exit non-zero on a
#               mismatch (for CI and for Godot upgrades)
#     binary    defaults to export/linux/omadungeon (exported on demand)
set -euo pipefail
cd "$(dirname "$0")/.."

check_mode=0
binary=""
for arg in "$@"; do
  case "$arg" in
    --check) check_mode=1 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) binary="$arg" ;;
  esac
done
binary="${binary:-export/linux/omadungeon}"

if [[ ! -x "$binary" ]]; then
  echo "==> $binary missing, exporting" >&2
  tools/export.sh "Linux x86_64" >&2
fi
[[ -x "$binary" ]] || { echo "no such binary: $binary" >&2; exit 1; }

# --- SONAME classification -------------------------------------------------
# required  : the game cannot open a window, draw or play sound without it
# optional  : a feature degrades but the game runs  -> Recommends
# extra     : niche, off by default                 -> Suggests
# devlink   : unversioned "libfoo.so" development symlink that Godot probes
#             before the real SONAME; owned by a -dev package, never a runtime
#             dependency
# ignore    : provided by the C library or the linker itself
soname_class() {
  case "$1" in
    libc.so.*|libm.so.*|libdl.so.*|librt.so.*|libpthread.so.*|ld-linux*) echo ignore ;;
    *.so)                                                                echo devlink ;;
    libX11.so.*|libXcursor.so.*|libXext.so.*|libXi.so.*|libXinerama.so.*) echo required ;;
    libXrandr.so.*|libXrender.so.*|libxkbcommon.so.*)                     echo required ;;
    libwayland-client.so.*|libwayland-cursor.so.*|libwayland-egl.so.*)    echo required ;;
    libGL.so.*|libEGL.so.*|libGLESv2.so.*)                                echo required ;;
    libasound.so.*|libudev.so.*)                                          echo required ;;
    libpulse.so.*|libdecor-0.so.*|libdbus-1.so.*|libfontconfig.so.*)      echo optional ;;
    libvulkan.so.*)                                                       echo optional ;;
    libspeechd.so.*)                                                      echo extra ;;
    *)                                                                    echo unknown ;;
  esac
}

# Why each non-required library is not a hard dependency.
soname_note() {
  case "$1" in
    libpulse.so.*)     echo "PulseAudio/PipeWire output; falls back to ALSA" ;;
    libdecor-0.so.*)   echo "client-side window decorations under Wayland" ;;
    libdbus-1.so.*)    echo "screensaver inhibit and desktop portals" ;;
    libfontconfig.so.*) echo "system font fallback; the game bundles its fonts" ;;
    libvulkan.so.*)    echo "only for the forward+ renderer; the game ships gl_compatibility" ;;
    libspeechd.so.*)   echo "speech-dispatcher text to speech, off by default" ;;
    *)                 echo "" ;;
  esac
}

# libasound2 was renamed libasound2t64 by the 64-bit time_t transition. Offer
# both names so one package installs on bookworm as well as on trixie, sid and
# Ubuntu. Only libraries that actually went through that rename belong here:
# naming a package that exists in no suite would be worse than naming one.
package_alternatives() {
  case "$1" in
    libasound2|libasound2t64) echo "libasound2t64 | libasound2" ;;
    *)                        echo "$1" ;;
  esac
}

# Resolve a SONAME to an absolute path through the linker cache (64-bit only).
# awk must read its input to the end: exiting early would SIGPIPE ldconfig and,
# with pipefail set, fail the assignment that calls this.
resolve_soname() {
  /sbin/ldconfig -p 2>/dev/null \
    | awk -v s="$1" '$1 == s && /x86-64/ && !found { print $NF; found = 1 }'
}

# Ask dpkg which package owns a path. dpkg -S prints "diversion by ..." lines
# first when a path is diverted (glx-diversions on hybrid-graphics systems), so
# take the last "package: /path" line instead of the first.
# The trailing `|| true` is load-bearing. `grep -v` exits 1 when it filters every line away,
# which happens whenever dpkg does not own the library at all, and under `set -o pipefail`
# that fails the whole pipeline and `set -e` then kills the script - silently, in the middle
# of the table, before a single comparison is printed. Every library on a developer's machine
# is dpkg-owned, so this only ever fired in a container: CI showed a bare table header and
# "FAILED exit 1" with no reason. An unowned path is a normal answer here, not an error; the
# caller already handles the empty string by printing "(unowned)".
owning_package() {
  {
    dpkg -S "$1" 2>/dev/null \
      | grep -v '^diversion by ' \
      | sed -n 's/^\([^ :]*\):.*/\1/p' \
      | sed 's/:.*$//' \
      | tail -n 1
  } || true
}

# --- collect SONAMEs -------------------------------------------------------
needed=$(objdump -p "$binary" 2>/dev/null | awk '$1 == "NEEDED" { print $2 }')
# dlopen'd names live in .rodata; keep only plausible SONAMEs.
dlopened=$(strings -a "$binary" \
  | grep -oE '\blib[A-Za-z0-9_.+-]+\.so(\.[0-9]+)*' \
  | sort -u)

all_sonames=$(printf '%s\n%s\n' "$needed" "$dlopened" | sed '/^$/d' | sort -u)

# Pre-resolve everything once so the loop can tell a genuinely missing library
# from an ABI variant that this system does not happen to carry.
resolved_sonames=$(while read -r so; do
  [[ -n "$so" ]] || continue
  [[ -n "$(resolve_soname "$so")" ]] && echo "$so"
done <<< "$all_sonames")

declare -a req_pkgs=() rec_pkgs=() sug_pkgs=() unknown_sonames=() missing_sonames=()

printf '%-24s %-16s %-46s %s\n' SONAME CLASS PATH PACKAGE
printf '%-24s %-16s %-46s %s\n' ------ ----- ---- -------
while read -r so; do
  [[ -n "$so" ]] || continue
  class=$(soname_class "$so")
  [[ "$class" == ignore || "$class" == devlink ]] && continue
  path=$(resolve_soname "$so")
  if [[ -z "$path" ]]; then
    # Godot probes several ABI versions of the same library and uses whichever
    # it finds. If a sibling SONAME of the same library did resolve, this one
    # is a fallback that this system simply does not need.
    base=${so%%.so*}
    if grep -q "^${base}\.so\." <<< "$resolved_sonames"; then
      continue
    fi
    printf '%-24s %-16s %-46s %s\n' "$so" "$class" "-" "(not installed here)"
    missing_sonames+=("$so")
    continue
  fi
  pkg=$(owning_package "$path")
  [[ -n "$pkg" ]] || pkg="(unowned)"
  printf '%-24s %-16s %-46s %s\n' "$so" "$class" "$path" "$pkg"
  case "$class" in
    required) req_pkgs+=("$(package_alternatives "$pkg")") ;;
    optional) rec_pkgs+=("$(package_alternatives "$pkg")") ;;
    extra)    sug_pkgs+=("$(package_alternatives "$pkg")") ;;
    unknown)  unknown_sonames+=("$so  -> $pkg") ;;
  esac
done <<< "$all_sonames"

dedupe() { printf '%s\n' "$@" | sed '/^$/d' | awk '!seen[$0]++'; }

# libc6 comes from the ELF NEEDED list; pin the glibc version the export
# template was built against so the package refuses to install on older systems.
libc_min=$(objdump -T "$binary" 2>/dev/null \
  | grep -oE 'GLIBC_2\.[0-9]+' | sort -uV | tail -n 1 | cut -d_ -f2- || true)
libc_dep="libc6"
[[ -n "${libc_min:-}" ]] && libc_dep="libc6 (>= $libc_min)"

mapfile -t req_sorted < <(dedupe "${req_pkgs[@]:-}" | sort)
mapfile -t rec_sorted < <(dedupe "${rec_pkgs[@]:-}" | sort)
mapfile -t sug_sorted < <(dedupe "${sug_pkgs[@]:-}" | sort)

join_deps() {
  local out="" dep
  for dep in "$@"; do
    [[ -n "$dep" ]] || continue
    [[ -n "$out" ]] && out+=", "
    out+="$dep"
  done
  printf '%s' "$out"
}

depends_line="\${misc:Depends}, $libc_dep, $(join_deps "${req_sorted[@]}")"
recommends_line="$(join_deps "${rec_sorted[@]}")"
suggests_line="$(join_deps "${sug_sorted[@]}")"

echo
echo "Binary:        $binary"
echo "ELF NEEDED:    $(echo "$needed" | tr '\n' ' ')"
echo "Highest glibc: ${libc_min:-unknown}"
echo
echo "Paste into both binary stanzas of debian/control:"
echo
echo "Depends: $depends_line"
echo "Recommends: $recommends_line"
echo "Suggests: $suggests_line"

for n in "${unknown_sonames[@]:-}"; do
  [[ -n "$n" ]] || continue
  echo
  echo "WARNING: unclassified SONAME (Godot may have gained a dependency): $n"
  echo "         add it to soname_class() in $0"
done
for n in "${missing_sonames[@]:-}"; do
  [[ -n "$n" ]] || continue
  echo "NOTE: $n is not installed on this machine, so no package could be mapped"
done

# --- optional verification against debian/control ---------------------------
#
# Both binary stanzas carry the same three dependency fields, so check both:
# anchoring on "omadungeon" alone would leave omadungeon-lite unverified and a
# hand-edit to one stanza only would pass. Recommends and Suggests are compared
# too, as sorted sets, so the field order in debian/control is free but its
# content is not.

# Print one field of one binary stanza of debian/control, continuation lines
# folded in. The source stanza is skipped: it opens with "Source:", not
# "Package:", and the two share the name "omadungeon".
control_field_of() {
  local pkg="$1" field="$2"
  awk -v pkg="$pkg" -v field="$field" '
    /^#/                        { next }
    /^Package: /                { inpkg = ($2 == pkg); fld = 0; next }
    /^Source: /                 { inpkg = 0; fld = 0; next }
    /^$/                        { inpkg = 0; fld = 0; next }
    !inpkg                      { next }
    $0 ~ "^" field ":"          { fld = 1; sub("^" field ":[ \t]*", ""); print; next }
    fld && /^[ \t]/             { sub(/^[ \t]+/, ""); print; next }
    fld                         { fld = 0 }
  ' debian/control | tr -d '\n' | sed 's/[ \t]\+/ /g'
}

if (( check_mode )); then
  echo
  # A set comparison: one dependency per line, trimmed, sorted. Alternatives
  # ("libasound2t64 | libasound2") stay on one line, so a changed alternative
  # is still a difference.
  norm() { tr ',' '\n' <<< "$1" | sed 's/^[ \t]*//; s/[ \t]*$//' | sed '/^$/d' | sort; }

  diff_file="$(mktemp "${TMPDIR:-/tmp}/omadungeon-deps-XXXXXX")"
  trap 'rm -f "$diff_file"' EXIT

  status=0
  for pkg in omadungeon omadungeon-lite; do
    if [[ -z "$(control_field_of "$pkg" Package)$(control_field_of "$pkg" Architecture)" ]]; then
      echo "MISMATCH: debian/control has no binary stanza for $pkg"
      status=1
      continue
    fi
    for field in Depends Recommends Suggests; do
      case "$field" in
        Depends)    derived="$depends_line" ;;
        Recommends) derived="$recommends_line" ;;
        Suggests)   derived="$suggests_line" ;;
      esac
      if diff -u <(norm "$(control_field_of "$pkg" "$field")") <(norm "$derived") \
           > "$diff_file" 2>&1; then
        echo "OK: $pkg $field matches the exported binary."
      else
        echo "MISMATCH: $pkg $field differs from the derived set"
        echo "  (-) in debian/control only, (+) derived from $binary"
        sed -n '4,$p' "$diff_file"
        status=1
      fi
    done
  done

  if (( ${#unknown_sonames[@]} )); then
    echo "MISMATCH: unclassified SONAMEs above"
    status=1
  fi
  exit "$status"
fi
