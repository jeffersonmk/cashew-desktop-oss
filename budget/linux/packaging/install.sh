#!/usr/bin/env bash
# Cashew Desktop: build and install for the current user (no sudo).
#
#   ./linux/packaging/install.sh                 build, install, then ask
#                                                whether to delete the source
#   ./linux/packaging/install.sh --remove-source build, install and delete the
#                                                downloaded source folder
#   ./linux/packaging/install.sh --keep-source   build and install, keep it
#   ./linux/packaging/install.sh --uninstall     remove it (your data is kept)
#
# Installs to:
#   ~/.local/opt/cashew-desktop/            the app
#   ~/.local/bin/cashew-desktop             command to start it
#   ~/.local/bin/cashew-desktop-uninstall   command to remove it (works
#                                           without the source folder)
#   ~/.local/share/applications/            menu entry
#   ~/.local/share/icons/hicolor/           icons
# Your data stays in ~/.local/share/io.github.jeffersonmk.CashewDesktop

set -euo pipefail

APP_ID="io.github.jeffersonmk.CashewDesktop"
BIN_NAME="cashew-desktop"
PACKAGING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$PACKAGING_DIR/../.." && pwd)"
REPO_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
OPT_DIR="$HOME/.local/opt/$BIN_NAME"
BIN_LINK="$HOME/.local/bin/$BIN_NAME"
UNINSTALL_LINK="$HOME/.local/bin/$BIN_NAME-uninstall"
DESKTOP_FILE="$DATA_HOME/applications/$APP_ID.desktop"
ICON_DIR="$DATA_HOME/icons/hicolor"

uninstall() {
  rm -f "$BIN_LINK" "$UNINSTALL_LINK" "$DESKTOP_FILE"
  find "$ICON_DIR" -name "$APP_ID.png" -delete 2>/dev/null || true
  refresh_caches
  rm -rf "$OPT_DIR"
  echo "Cashew Desktop removed. Your data in $DATA_HOME/$APP_ID was kept."
}

refresh_caches() {
  command -v update-desktop-database >/dev/null &&
    update-desktop-database -q "$DATA_HOME/applications" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null &&
    gtk-update-icon-cache -q -t "$ICON_DIR" 2>/dev/null || true
}

# Deletes the downloaded source folder (the git clone this script is in).
# Refuses when it holds work that exists nowhere else: changed or new files,
# commits not pushed, or stashes.
remove_source() {
  if [[ ! -d "$REPO_DIR/.git" || ! -f "$REPO_DIR/budget/pubspec.yaml" ]]; then
    echo "Source folder kept: $REPO_DIR is not a git clone of Cashew Desktop."
    return
  fi
  if [[ "$REPO_DIR" == "/" || "$REPO_DIR" == "$HOME" ]]; then
    echo "Source folder kept: refusing to delete $REPO_DIR."
    return
  fi
  local reason=""
  if [[ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ]]; then
    reason="it has changed or new files"
  elif [[ -n "$(git -C "$REPO_DIR" log --branches --not --remotes --oneline 2>/dev/null)" ]]; then
    reason="it has commits that were not pushed"
  elif [[ -n "$(git -C "$REPO_DIR" stash list 2>/dev/null)" ]]; then
    reason="it has stashed changes"
  fi
  if [[ -n "$reason" ]]; then
    echo "Source folder kept: $reason ($REPO_DIR)."
    return
  fi
  cd "$HOME"
  rm -rf "$REPO_DIR"
  echo "==> Source folder deleted: $REPO_DIR"
}

SOURCE_ACTION="ask"
case "${1:-}" in
  --uninstall) uninstall; exit 0 ;;
  --remove-source) SOURCE_ACTION="remove" ;;
  --keep-source) SOURCE_ACTION="keep" ;;
  "") ;;
  *) echo "Unknown option: $1 (see the top of this script)"; exit 1 ;;
esac

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
# A copy of this script, so it can be uninstalled after the source is gone.
install -m755 "$PACKAGING_DIR/install.sh" "$OPT_DIR/uninstall.sh"
ln -sf "$OPT_DIR/uninstall.sh" "$UNINSTALL_LINK"

for size in 16 24 32 48 64 128 256 512; do
  mkdir -p "$ICON_DIR/${size}x${size}/apps"
  cp "$PACKAGING_DIR/icons/$size.png" "$ICON_DIR/${size}x${size}/apps/$APP_ID.png"
done

sed "s|^Exec=.*|Exec=$OPT_DIR/$BIN_NAME|" \
  "$PACKAGING_DIR/$APP_ID.desktop" > "$DESKTOP_FILE"

refresh_caches
echo "==> Done. Open \"Cashew Desktop\" from your app menu, or run: $BIN_NAME"
echo "    To uninstall later: $BIN_NAME-uninstall --uninstall"

if [[ "$SOURCE_ACTION" == "ask" ]]; then
  if [[ -t 0 ]]; then
    SIZE="$(du -sh "$REPO_DIR" 2>/dev/null | cut -f1)"
    echo
    echo "The app is installed; the downloaded source folder is no longer needed:"
    echo "    $REPO_DIR (${SIZE:-?})"
    read -r -p "Delete it? [y/N] " answer
    [[ "$answer" =~ ^[yYsS]$ ]] && SOURCE_ACTION="remove"
  fi
fi
if [[ "$SOURCE_ACTION" == "remove" ]]; then
  remove_source
fi
exit 0
