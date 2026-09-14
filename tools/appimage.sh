#!/usr/bin/env bash
# Builds Omadungeon-x86_64.AppImage from the exported Linux binary.
# Requires appimagetool (downloaded on demand into ~/.cache/omadungeon-build/).
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="export/linux/omadungeon"
[[ -x "$BIN" ]] || tools/export.sh "Linux x86_64"
CACHE="$HOME/.cache/omadungeon-build"
mkdir -p "$CACHE"
TOOL="$CACHE/appimagetool-x86_64.AppImage"
if [[ ! -x "$TOOL" ]]; then
  curl -L -o "$TOOL" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$TOOL"
fi
APPDIR="$CACHE/Omadungeon.AppDir"
rm -rf "$APPDIR"
install -Dm755 "$BIN" "$APPDIR/usr/bin/omadungeon"
install -Dm644 packaging/omadungeon.desktop "$APPDIR/usr/share/applications/omadungeon.desktop"
install -Dm644 packaging/omadungeon.desktop "$APPDIR/omadungeon.desktop"
install -Dm644 packaging/omadungeon.metainfo.xml "$APPDIR/usr/share/metainfo/org.omadungeon.Omadungeon.metainfo.xml"
install -Dm644 packaging/icons/omadungeon-256.png "$APPDIR/usr/share/icons/hicolor/256x256/apps/omadungeon.png"
install -Dm644 packaging/icons/omadungeon-256.png "$APPDIR/omadungeon.png"
cat > "$APPDIR/AppRun" <<'RUN'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/omadungeon" "$@"
RUN
chmod +x "$APPDIR/AppRun"
# appimagetool is itself an AppImage, so running it needs FUSE - which a CI container does
# not have ("fuse: device not found" then "No suitable fusermount binary found"). Its own
# APPIMAGE_EXTRACT_AND_RUN unpacks it to a temporary directory and runs it from there
# instead, which costs a second and works everywhere. Harmless on a desktop with FUSE.
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" "$APPDIR" "Omadungeon-x86_64.AppImage"
ls -lh Omadungeon-x86_64.AppImage
