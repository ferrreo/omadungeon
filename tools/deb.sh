#!/usr/bin/env bash
# Builds Omadungeon .deb packages without debhelper, dpkg-buildpackage or any
# build-dependency beyond dpkg-deb itself, so it works on a plain Debian or
# PikaOS box with only dpkg installed.
#
#   tools/deb.sh [full|lite|both]        default: both -> dist/*.deb
#   tools/deb.sh --export <full|lite>    run the Godot export for one variant
#   tools/deb.sh --stage <full|lite> <destdir>
#                                        populate the install layout only, with
#                                        no DEBIAN/ directory; this is the mode
#                                        debian/rules calls so that the dh path
#                                        and this path lay files out identically
#
# Environment:
#   DEB_OUTPUT_DIR   where the .deb files land          (default: dist)
#   DEB_XZ_LEVEL     xz compression level               (default: 1)
#   GODOT_BIN        passed through to tools/export.sh
#
# The package metadata comes from debian/control and debian/changelog, so those
# stay the single source of truth; this script only substitutes the fields that
# can be known at build time (Version, Installed-Size) and drops the debhelper
# substitution variables. Re-run tools/check-deb-deps.sh --check after a Godot
# upgrade to confirm the Depends list in debian/control still matches.
#
# Before it packages anything it verifies the export: every non-resource file
# the game loads by path has to be in the binary's PCK directory, and the game
# has to run headless with no desktop theme present without logging an engine
# error. See the "payload verification" section.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${DEB_OUTPUT_DIR:-dist}"
XZ_LEVEL="${DEB_XZ_LEVEL:-1}"
ARCH=amd64

die() { echo "deb.sh: $*" >&2; exit 1; }

# The staging tree is a full copy of the payload - 73 MB for lite, 232 MB for
# full - so it has to go even when the build dies half way through. A RETURN
# trap inside build() does not fire when "set -e" or a die() ends the shell, and
# on a box where $TMPDIR is a tmpfs a few failed runs then sit in RAM. One EXIT
# trap over one variable covers every exit path, including SIGINT.
stagedir=""
cleanup() { [[ -n "$stagedir" ]] && rm -rf "$stagedir"; return 0; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# --- metadata --------------------------------------------------------------

version() {
  if command -v dpkg-parsechangelog >/dev/null 2>&1; then
    dpkg-parsechangelog -l debian/changelog -S Version
  else
    sed -n '1s/.*(\(.*\)).*/\1/p' debian/changelog
  fi
}

# Print one stanza of debian/control, with comment lines removed. The source
# stanza and the first binary stanza share the name "omadungeon", so the field
# that opens a stanza has to be matched explicitly rather than by name alone.
control_stanza() {
  local key="$1" want="$2"
  awk -v key="$key" -v want="$want" '
    /^#/ { next }
    /^(Package|Source): / { inside = ($1 == key ":" && $2 == want) }
    /^$/ { inside = 0; next }
    inside { print }
  ' debian/control
}

# Read one field out of a stanza, folding its continuation lines into one line.
control_field() {
  local stanza="$1" field="$2"
  awk -v f="$field" '
    $0 ~ "^" f ": " { got = 1; sub("^" f ":[ \t]*", ""); print; next }
    got && /^[ \t]/  { sub(/^[ \t]+/, ""); print; next }
    got             { exit }
  ' <<< "$stanza" | paste -sd' ' - | sed 's/[ \t]\+/ /g; s/ *$//'
}

# Drop debhelper substitution variables and tidy the separators left behind.
resolve_substvars() {
  local value="$1" version="$2"
  value="${value//\$\{binary:Version\}/$version}"
  value="${value//\$\{source:Version\}/$version}"
  sed -e 's/\${[a-zA-Z:-]*}//g' \
      -e 's/^[, ]*//' -e 's/[, ]*$//' \
      -e 's/ *, */, /g' -e 's/,\+/,/g' -e 's/, *$//' <<< "$value"
}

# --- export ----------------------------------------------------------------

# Check the variant name here, in a plain statement, and not inside the case
# arms below. binary_for and friends are called as "$(binary_for ...)", and a
# die() in a command substitution kills only the subshell: the message is
# printed, the assignment yields the empty string and the caller carries on -
# far enough, before this guard existed, to re-export the full preset over the
# top of a good build and then fail with a nonsense message. Every entry point
# calls this before it looks anything up.
require_variant() {
  case "${1-}" in
    full|lite) ;;
    *) die "unknown variant: ${1-} (expected full or lite)" ;;
  esac
}

binary_for() {
  case "$1" in
    full) echo "export/linux/omadungeon" ;;
    lite) echo "export/linux-lite/omadungeon" ;;
    *) die "unknown variant: $1" ;;
  esac
}

preset_for() {
  case "$1" in
    full) echo "Linux x86_64" ;;
    lite) echo "Linux x86_64 (lite, no music)" ;;
    *) die "unknown variant: $1" ;;
  esac
}

package_for() {
  case "$1" in
    full) echo "omadungeon" ;;
    lite) echo "omadungeon-lite" ;;
    *) die "unknown variant: $1" ;;
  esac
}

## True when any game source is newer than the export, so a stale binary is never packaged.
## A verifier caught this the hard way: the guard below only re-exported a MISSING binary, so
## days-old code was packaged and then "verified" in a virtual machine, and the evidence looked
## fine because it was a real run of the wrong build.
binary_is_stale() {
  local bin="$1" newer
  [[ -s "$bin" ]] || return 0
  newer="$(find src data assets project.godot export_presets.cfg -newer "$bin" -print -quit 2>/dev/null)"
  [[ -n "$newer" ]]
}

ensure_binary() {
  local variant="$1" bin preset
  require_variant "$variant"
  bin="$(binary_for "$variant")"
  if binary_is_stale "$bin"; then
    preset="$(preset_for "$variant")"
    echo "==> exporting \"$preset\"" >&2
    # tools/export.sh is allowed to fail: Godot 4.7 sometimes aborts on exit
    # after the pack is already written. Judge the result by the artifact.
    tools/export.sh "$preset" >&2 \
      || echo "==> export exited non-zero, checking its output anyway" >&2
  fi
  [[ -s "$bin" ]] || die "export produced no $bin"
  head -c 4 "$bin" | grep -qa 'ELF' || die "$bin is not an ELF executable"
  chmod 0755 "$bin"
  # Only the path goes to stdout; everything above went to stderr so that
  # bin="$(ensure_binary ...)" captures a path and nothing else.
  echo "$bin"
}

# --- payload verification --------------------------------------------------

# Files the game opens by path at run time that are not Godot resources.
# export_filter="all_resources" walks importable resources only, so a .toml or
# a .lrc reaches the PCK solely through include_filter in export_presets.cfg,
# and leaving one out is silent at export time and fatal at run time: without
# data/themes/fallback/colors.toml every colour role resolves to magenta on any
# machine that has neither an Omarchy nor an otter-shell theme, which is most of
# the audience for these packages. The lists are derived from the tree rather
# than spelled out, so a new fallback theme or a new lyrics file is covered the
# moment it is added.
required_pck_files() {
  local variant="$1"
  find data/themes -type f -name '*.toml' | sort
  if [[ "$variant" == full ]]; then
    [[ -f assets/music/radio/playlist.json ]] && echo assets/music/radio/playlist.json
    find assets/music/radio/lyrics -type f -name '*.lrc' 2>/dev/null | sort
  fi
  return 0
}

# Is this project-relative path a real entry in the binary's PCK directory?
#
# The directory is a flat list: little-endian uint32 path length, that many
# bytes of path (NUL-padded up to a multiple of four, and stored without the
# "res://" prefix), then the offset, size, MD5 and flags. Matching the length
# prefix as well as the text is what tells a directory entry apart from the same
# string appearing as a constant in compiled script bytecode - "colors.toml"
# occurs five times in the binary through src/desktop/theme_palette.gd alone,
# so a plain grep for the path proves nothing.
pck_has() {
  local bin="$1" path="$2" len pad plen prefix
  len=${#path}
  pad=$(( (4 - len % 4) % 4 ))
  plen=$(( len + pad ))
  # The length bytes have to reach grep as PCRE \xNN escapes: a shell string
  # cannot carry the NUL bytes they mostly are.
  printf -v prefix '\\x%02x\\x%02x\\x%02x\\x%02x' \
    $(( plen & 255 )) $(( (plen >> 8) & 255 )) \
    $(( (plen >> 16) & 255 )) $(( (plen >> 24) & 255 ))
  # \Q...\E makes PCRE take the path literally, dots and all.
  grep -aqP "$prefix\\Q$path\\E" "$bin"
}

verify_payload() {
  local variant="$1" bin="$2" path missing=0
  require_variant "$variant"

  # project.binary is in every Godot PCK. If it cannot be found, the pack
  # format has moved rather than the payload, and saying so beats reporting
  # every file below as missing.
  pck_has "$bin" project.binary || die \
    "cannot read the PCK directory of $bin: project.binary is not in it. The Godot pack format has probably changed; update pck_has() in tools/deb.sh."

  while read -r path; do
    [[ -n "$path" ]] || continue
    pck_has "$bin" "$path" && continue
    echo "deb.sh: $bin: $path is missing from the PCK" >&2
    missing=1
  done < <(required_pck_files "$variant")
  (( missing == 0 )) || die \
    "the $variant export does not carry every file the game loads by path; add the paths above to include_filter in export_presets.cfg and re-export."

  smoke_test "$variant" "$bin"
}

# Run the export once, headless, in an empty HOME with no Omarchy or otter-shell
# theme anywhere - the state every plain Debian or Ubuntu machine is in - and
# fail on any engine error.
#
# The exit status alone is not enough: Godot's push_error() writes "ERROR:" to
# stderr and leaves the status at 0, so the theme-missing bug this guard exists
# for exited 0 all the way into a published package. Grep the log instead.
smoke_test() {
  local variant="$1" bin="$2" home log rc=0
  home="$(mktemp -d "${TMPDIR:-/tmp}/omadungeon-smoke-XXXXXX")"
  log="$home/smoke.log"
  echo "==> smoke test $variant (headless, no desktop theme)" >&2
  env -i PATH="$PATH" \
      HOME="$home" \
      XDG_CONFIG_HOME="$home/config" \
      XDG_STATE_HOME="$home/state" \
      XDG_DATA_HOME="$home/data" \
      XDG_CACHE_HOME="$home/cache" \
      XDG_RUNTIME_DIR="$home/run" \
      OMADUNGEON_OMARCHY_STATE_DIR="$home/no-such-theme" \
      "./$bin" --headless --quit-after 120 > "$log" 2>&1 || rc=$?
  if (( rc != 0 )); then
    sed -n '1,40p' "$log" >&2
    rm -rf "$home"
    die "$bin exited $rc under --headless"
  fi
  # One engine line is expected and is not a defect: several modules cache a Resource in a
  # static var by design (ItemTuning, DifficultyCurve, FeelProfile, the projectile pool), and
  # a static outlives the resource system, so Godot reports "N resources still in use at
  # exit" on every clean shutdown. Nothing else is tolerated - the SCRIPT ERROR that this
  # guard caught on the way to this release broke the run manager in the exported build while
  # every test stayed green.
  if grep -vE '^ERROR: [0-9]+ resources still in use at exit' "$log" \
      | grep -qE '^(ERROR|SCRIPT ERROR|USER ERROR):'; then
    echo "--- $bin --headless ---" >&2
    grep -vE '^ERROR: [0-9]+ resources still in use at exit' "$log" \
      | grep -nE '^(ERROR|SCRIPT ERROR|USER ERROR):' >&2
    rm -rf "$home"
    die "$bin logged an engine error with no theme present; see above."
  fi
  rm -rf "$home"
}

# --- staging ---------------------------------------------------------------

# Lay out the installed tree. Nothing here writes DEBIAN/, so debian/rules can
# call it to fill a debhelper package directory.
#   stage <variant> <destdir>
stage() {
  local variant="$1" dest="$2" pkg bin doc
  require_variant "$variant"
  pkg="$(package_for "$variant")"
  bin="$(ensure_binary "$variant")"
  verify_payload "$variant" "$bin"
  doc="$dest/usr/share/doc/$pkg"

  # The game binary: a Godot export template carrying the project's PCK in an
  # allocated ELF section named "pck" that belongs to no segment. Never strip
  # it - strip(1) warns about that section and, depending on the binutils
  # version, can drop it, leaving a binary that starts and then reports
  # "Couldn't load project data". It arrives already stripped in any case.
  install -Dm0755 "$bin" "$dest/usr/lib/omadungeon/omadungeon"

  # Policy 10.5: a symlink between two directories under the same top-level
  # directory is relative. This is the same link dh_link would make from
  # debian/omadungeon.links.
  install -dm0755 "$dest/usr/bin"
  ln -sfn ../lib/omadungeon/omadungeon "$dest/usr/bin/omadungeon"

  install -Dm0644 packaging/omadungeon.desktop \
    "$dest/usr/share/applications/omadungeon.desktop"
  install -Dm0644 packaging/omadungeon.metainfo.xml \
    "$dest/usr/share/metainfo/org.omadungeon.Omadungeon.metainfo.xml"

  local size
  for size in 16 32 48 64 128 256; do
    install -Dm0644 "packaging/icons/omadungeon-$size.png" \
      "$dest/usr/share/icons/hicolor/${size}x${size}/apps/omadungeon.png"
  done

  install -Dm0644 LICENSE "$doc/LICENSE"
  install -Dm0644 debian/copyright "$doc/copyright"
  install -Dm0644 docs/CREDITS.md "$doc/CREDITS.md"

  # Policy 12.7: a Debian changelog, gzipped. It is a few kB of text, so unlike
  # the payload it is worth compressing.
  gzip -9nc debian/changelog > "$doc/changelog.Debian.gz"
  chmod 0644 "$doc/changelog.Debian.gz"

  # When $dest sits inside the project - debian/omadungeon under dh - a later
  # "godot --import" scan walks into it and drops .import sidecars next to the
  # icons it finds there. debian/rules exports before it stages so that cannot
  # happen, but sweep them anyway: one stray sidecar in the package is not
  # worth trusting to ordering alone.
  find "$dest" -name '*.import' -delete
}

# --- control file ----------------------------------------------------------

write_control() {
  local variant="$1" dest="$2" pkg ver src src_stanza bin_stanza size field value
  require_variant "$variant"
  pkg="$(package_for "$variant")"
  ver="$(version)"
  src="$(awk '/^Source: / { print $2; exit }' debian/control)"
  src_stanza="$(control_stanza Source omadungeon)"
  bin_stanza="$(control_stanza Package "$pkg")"
  [[ -n "$bin_stanza" ]] || die "no stanza for $pkg in debian/control"

  # dpkg reports Installed-Size in KiB, rounded up, excluding DEBIAN/ itself.
  size=$(du -sk "$dest" | cut -f1)

  install -dm0755 "$dest/DEBIAN"
  {
    echo "Package: $pkg"
    # dpkg-gencontrol emits Source only when it differs from the binary package
    # name; apt needs it to map a binary package back to its source.
    if [[ "$pkg" != "$src" ]]; then echo "Source: $src"; fi
    echo "Version: $ver"
    echo "Architecture: $ARCH"
    echo "Maintainer: $(control_field "$src_stanza" Maintainer)"
    echo "Installed-Size: $size"
    for field in Depends Recommends Suggests Conflicts Replaces Provides Breaks; do
      value="$(control_field "$bin_stanza" "$field")"
      value="$(resolve_substvars "$value" "$ver")"
      if [[ -n "$value" ]]; then echo "$field: $value"; fi
    done
    echo "Section: $(control_field "$src_stanza" Section)"
    echo "Priority: $(control_field "$src_stanza" Priority)"
    echo "Homepage: $(control_field "$src_stanza" Homepage)"
    # Description keeps its original line structure, so print it verbatim.
    awk '
      /^Description: / { got = 1; print; next }
      got && /^[ \t]/  { print; next }
      got              { exit }
    ' <<< "$bin_stanza"
  } > "$dest/DEBIAN/control"

  # No maintainer scripts: /usr/share/icons/hicolor and
  # /usr/share/applications are handled by the dpkg triggers that
  # hicolor-icon-theme and desktop-file-utils ship, so a postinst calling
  # gtk-update-icon-cache or update-desktop-database would only duplicate work
  # that dpkg already does, and a postrm would be a second chance to fail.

  # md5sums over every regular file, paths relative to the package root and
  # without the leading ./ that find prints.
  ( cd "$dest" && find . -type f ! -path './DEBIAN/*' -printf '%P\0' \
      | sort -z | xargs -0 -r md5sum ) > "$dest/DEBIAN/md5sums"
  chmod 0644 "$dest/DEBIAN/md5sums" "$dest/DEBIAN/control"
}

# --- build -----------------------------------------------------------------

build() {
  local variant="$1" pkg ver deb
  require_variant "$variant"
  pkg="$(package_for "$variant")"
  ver="$(version)"
  stagedir="$(mktemp -d "${TMPDIR:-/tmp}/omadungeon-deb-XXXXXX")"

  echo "==> staging $pkg $ver"
  stage "$variant" "$stagedir"
  write_control "$variant" "$stagedir"

  # Directories 0755, data 0644, the game binary 0755. install -m set these
  # already; re-assert them so a stale umask or a re-run cannot drift.
  find "$stagedir" -type d -exec chmod 0755 {} +
  find "$stagedir" -type f -exec chmod 0644 {} +
  chmod 0755 "$stagedir/usr/lib/omadungeon/omadungeon"

  install -dm0755 "$OUT_DIR"
  deb="$OUT_DIR/${pkg}_${ver}_${ARCH}.deb"
  rm -f "$deb"

  # The payload is ~160 MB of already-compressed audio inside the embedded PCK,
  # plus a Godot executable. xz -9 spends minutes to gain under two per cent
  # over xz -1 on this input, so build at -1 and use every core.
  echo "==> dpkg-deb --build (xz -$XZ_LEVEL)"
  dpkg-deb --root-owner-group \
           -Zxz -z"$XZ_LEVEL" --threads-max="$(nproc)" \
           --build "$stagedir" "$deb"

  printf '==> %s  %s\n' "$deb" "$(du -h "$deb" | cut -f1)"

  rm -rf "$stagedir"
  stagedir=""
}

# --- entry point -----------------------------------------------------------

if [[ "${1:-}" == "--export" ]]; then
  [[ $# -eq 2 ]] || die "usage: tools/deb.sh --export <full|lite>"
  require_variant "$2"
  ensure_binary "$2" >/dev/null
  exit 0
fi

if [[ "${1:-}" == "--stage" ]]; then
  [[ $# -eq 3 ]] || die "usage: tools/deb.sh --stage <full|lite> <destdir>"
  require_variant "$2"
  stage "$2" "$3"
  exit 0
fi

case "${1:-both}" in
  full) build full ;;
  lite) build lite ;;
  both) build full; build lite ;;
  -h|--help) sed -n '2,28p' "$0" | sed 's/^# \?//'; exit 0 ;;
  *) die "usage: tools/deb.sh [full|lite|both]" ;;
esac
