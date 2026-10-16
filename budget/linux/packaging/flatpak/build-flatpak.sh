#!/usr/bin/env bash
# Cashew Desktop: build a Flatpak bundle (.flatpak) from the release build.
#
#   ./linux/packaging/flatpak/build-flatpak.sh            build release + Flatpak
#   ./linux/packaging/flatpak/build-flatpak.sh --no-build pack an existing build
#
# Output: build/flatpak/Cashew_Desktop-<version>-x86_64.flatpak
# Needs flatpak-builder (or: flatpak install flathub org.flatpak.Builder) and
# the GNOME 50 SDK (installed automatically from Flathub).

set -euo pipefail

APP_ID="io.github.jeffersonmk.CashewDesktop"
FLATPAK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$FLATPAK_DIR/../../.." && pwd)"
OUT_DIR="$PROJECT_DIR/build/flatpak"
cd "$PROJECT_DIR"

if [[ "${1:-}" != "--no-build" ]]; then
  if command -v fvm >/dev/null; then FLUTTER=(fvm flutter); else FLUTTER=(flutter); fi
  echo "==> Building (release)..."
  "${FLUTTER[@]}" build linux --release
fi
[[ -x build/linux/x64/release/bundle/cashew-desktop ]] || {
  echo "Build output not found"; exit 1; }

VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
VERSION="${VERSION#v}"
OUTPUT="$OUT_DIR/Cashew_Desktop-$VERSION-x86_64.flatpak"

if command -v flatpak-builder >/dev/null; then
  BUILDER=(flatpak-builder)
else
  BUILDER=(flatpak run --filesystem="$PROJECT_DIR" org.flatpak.Builder//stable)
fi

mkdir -p "$OUT_DIR"
echo "==> flatpak-builder"
"${BUILDER[@]}" --user --install-deps-from=flathub --force-clean \
  --state-dir="$OUT_DIR/.flatpak-builder" --repo="$OUT_DIR/repo" \
  "$OUT_DIR/build-dir" "$FLATPAK_DIR/$APP_ID.yml"

echo "==> Bundle"
rm -f "$OUTPUT"
# --runtime-repo: installing the bundle also adds Flathub for the runtime.
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  "$OUT_DIR/repo" "$OUTPUT" "$APP_ID"
echo "==> $OUTPUT"
