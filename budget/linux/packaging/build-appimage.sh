#!/usr/bin/env bash
# Cashew Desktop: build a portable AppImage.
#
#   ./linux/packaging/build-appimage.sh            build release + AppImage
#   ./linux/packaging/build-appimage.sh --no-build package an existing build
#
# Output: build/appimage/Cashew_Desktop-<version>-x86_64.AppImage
# Version: $VERSION if set (e.g. from a git tag), otherwise `git describe`.
#
# Note: an AppImage only runs on systems with a glibc at least as new as the
# one it was built on. Official releases are built by GitHub Actions on
# Ubuntu 22.04 so they work on most distributions; a local build on a
# rolling-release distro may only run on equally new systems.

set -euo pipefail

APP_ID="io.github.jeffersonmk.CashewDesktop"
BIN_NAME="cashew-desktop"
# Pinned release + checksum, so a changed download is rejected.
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage"
APPIMAGETOOL_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"

PACKAGING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$PACKAGING_DIR/../.." && pwd)"
OUT_DIR="$PROJECT_DIR/build/appimage"
APPDIR="$OUT_DIR/AppDir"
BUNDLE="$PROJECT_DIR/build/linux/x64/release/bundle"

cd "$PROJECT_DIR"

if [[ "${1:-}" != "--no-build" ]]; then
  if command -v fvm >/dev/null; then FLUTTER=(fvm flutter); else FLUTTER=(flutter); fi
  echo "==> Building (release)..."
  "${FLUTTER[@]}" build linux --release
fi
[[ -x "$BUNDLE/$BIN_NAME" ]] || { echo "Build output not found: $BUNDLE"; exit 1; }

VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
VERSION="${VERSION#v}"
OUTPUT="$OUT_DIR/Cashew_Desktop-$VERSION-x86_64.AppImage"

echo "==> Preparing AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/share/applications" "$APPDIR/usr/share/metainfo"
# Flutter looks for lib/ and data/ next to the executable, so the bundle is
# copied as a whole into usr/bin.
mkdir -p "$APPDIR/usr/bin"
cp -r "$BUNDLE/." "$APPDIR/usr/bin/"

for size in 16 24 32 48 64 128 256 512; do
  mkdir -p "$APPDIR/usr/share/icons/hicolor/${size}x${size}/apps"
  cp "$PACKAGING_DIR/icons/$size.png" \
    "$APPDIR/usr/share/icons/hicolor/${size}x${size}/apps/$APP_ID.png"
done
cp "$PACKAGING_DIR/icons/256.png" "$APPDIR/$APP_ID.png"
ln -s "$APP_ID.png" "$APPDIR/.DirIcon"

cp "$PACKAGING_DIR/$APP_ID.desktop" "$APPDIR/usr/share/applications/"
cp "$PACKAGING_DIR/$APP_ID.desktop" "$APPDIR/"
cp "$PACKAGING_DIR/$APP_ID.metainfo.xml" "$APPDIR/usr/share/metainfo/"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/cashew-desktop" "$@"
EOF
chmod +x "$APPDIR/AppRun"

TOOL="$OUT_DIR/appimagetool-1.9.1"
if ! echo "$APPIMAGETOOL_SHA256  $TOOL" | sha256sum -c --status 2>/dev/null; then
  echo "==> Downloading appimagetool"
  rm -f "$TOOL"
  curl -fsSL -o "$TOOL.part" "$APPIMAGETOOL_URL"
  if ! echo "$APPIMAGETOOL_SHA256  $TOOL.part" | sha256sum -c --status; then
    rm -f "$TOOL.part"
    echo "ERROR: appimagetool checksum mismatch, refusing to use it." >&2
    exit 1
  fi
  mv "$TOOL.part" "$TOOL"
  chmod +x "$TOOL"
fi

echo "==> Creating $OUTPUT"
rm -f "$OUTPUT"
# Extract-and-run so appimagetool works even without FUSE (e.g. in CI).
APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 "$TOOL" --no-appstream "$APPDIR" "$OUTPUT"

echo "==> Done: $OUTPUT"
