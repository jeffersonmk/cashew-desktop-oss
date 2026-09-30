#!/usr/bin/env bash
# Cashew Desktop: build and install for the current user (no sudo).
#
#   ./linux/packaging/install.sh            build (release) and install
#   ./linux/packaging/install.sh --uninstall remove it (your data is kept)
#
# Installs to:
#   ~/.local/opt/cashew-desktop/            the app
#   ~/.local/bin/cashew-desktop             command to start it
#   ~/.local/share/applications/            menu entry
#   ~/.local/share/icons/hicolor/           icons
# Your data stays in ~/.local/share/io.github.jeffersonmk.CashewDesktop

set -euo pipefail

APP_ID="io.github.jeffersonmk.CashewDesktop"
BIN_NAME="cashew-desktop"
PACKAGING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$PACKAGING_DIR/../.." && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
OPT_DIR="$HOME/.local/opt/$BIN_NAME"
BIN_LINK="$HOME/.local/bin/$BIN_NAME"
DESKTOP_FILE="$DATA_HOME/applications/$APP_ID.desktop"
ICON_DIR="$DATA_HOME/icons/hicolor"

uninstall() {
  rm -rf "$OPT_DIR"
  rm -f "$BIN_LINK" "$DESKTOP_FILE"
  find "$ICON_DIR" -name "$APP_ID.png" -delete 2>/dev/null || true
  refresh_caches
  echo "Cashew Desktop removed. Your data in $DATA_HOME/$APP_ID was kept."
}

refresh_caches() {
  command -v update-desktop-database >/dev/null &&
    update-desktop-database -q "$DATA_HOME/applications" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null &&
    gtk-update-icon-cache -q -t "$ICON_DIR" 2>/dev/null || true
}

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
  exit 0
fi

cd "$PROJECT_DIR"
if command -v fvm >/dev/null; then FLUTTER=(fvm flutter); else FLUTTER=(flutter); fi
echo "==> Building (release)..."
"${FLUTTER[@]}" build linux --release

BUNDLE="$PROJECT_DIR/build/linux/x64/release/bundle"
[[ -x "$BUNDLE/$BIN_NAME" ]] || { echo "Build output not found: $BUNDLE"; exit 1; }

echo "==> Installing to $OPT_DIR"
rm -rf "$OPT_DIR"
mkdir -p "$OPT_DIR" "$(dirname "$BIN_LINK")" "$(dirname "$DESKTOP_FILE")"
cp -r "$BUNDLE/." "$OPT_DIR/"
ln -sf "$OPT_DIR/$BIN_NAME" "$BIN_LINK"

for size in 16 24 32 48 64 128 256 512; do
  mkdir -p "$ICON_DIR/${size}x${size}/apps"
  cp "$PACKAGING_DIR/icons/$size.png" "$ICON_DIR/${size}x${size}/apps/$APP_ID.png"
done

sed "s|^Exec=.*|Exec=$OPT_DIR/$BIN_NAME|" \
  "$PACKAGING_DIR/$APP_ID.desktop" > "$DESKTOP_FILE"

refresh_caches
echo "==> Done. Open \"Cashew Desktop\" from your app menu, or run: $BIN_NAME"
