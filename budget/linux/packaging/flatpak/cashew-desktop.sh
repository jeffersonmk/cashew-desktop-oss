#!/bin/sh
# Cashew Desktop (Flatpak): keep the data in the same folder as the AppImage,
# ~/.local/share/io.github.jeffersonmk.CashewDesktop, instead of
# ~/.var/app/... (the manifest gives access to that one folder). So both
# versions see the same data and switching between them needs no migration.
export XDG_DATA_HOME="$HOME/.local/share"
exec /app/cashew/cashew-desktop "$@"
