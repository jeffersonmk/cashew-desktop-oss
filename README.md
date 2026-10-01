<h1 align="center"><b>Cashew Desktop</b></h1>

<div align="center">
  <img alt="Cashew Desktop icon" src="promotional/icons/cashew-desktop.png" width="150px">
</div>

<p align="center">
  A native desktop build of the <a href="https://github.com/jameskokoska/Cashew">Cashew</a> budget app, with <b>no cloud and no Google account</b>: your data stays on your computer.
</p>

---

> **Fork notice.** Cashew Desktop is an unofficial fork of
> [Cashew](https://github.com/jameskokoska/Cashew) by
> [James Kokoska](https://github.com/jameskokoska), licensed under GPL-3.0.
> It is not affiliated with or endorsed by the original author.
> The original README is kept in [README-upstream.md](README-upstream.md).

## What is different from Cashew

| | Cashew | Cashew Desktop |
|---|---|---|
| Platforms | Android, iOS, Web | **Linux** (Windows planned) |
| Google Sign-In | Yes | **Removed** |
| Google Drive backup / sync | Yes | **Removed**, replaced by local backups |
| Shared budgets (Firebase) | Yes | Removed |
| Gmail auto-transactions | Yes | Removed |
| Transaction attachments | Uploaded to Google Drive | Removed (local attachments planned) |
| Notifications | Yes | Not yet on desktop |

Everything else (budgets, transactions, goals, subscriptions, loans,
graphs, CSV import, themes, translations) comes from Cashew.

## Local backups

Open **Backups** in the side menu:

- **Backup**: saves a copy of your database to the backup folder.
- **Auto backups**: creates a backup every *N* days when the app starts.
- **Backup limit**: keeps only the newest backups.
- **Backup folder**: choose another folder (for example one synced with
  Syncthing or Nextcloud). Long-press to go back to the default.
- **Export / Import**: save or load a `.sqlite` file anywhere. Files are
  compatible with the original Cashew app.

Where your data lives on Linux:

| What | Path |
|---|---|
| Database | `~/.local/share/io.github.jeffersonmk.CashewDesktop/db.sqlite` |
| Backups (default) | `~/.local/share/io.github.jeffersonmk.CashewDesktop/backups/` |

## Keyboard shortcuts

| Action | Keys |
|---|---|
| New transaction | `Ctrl + N` |
| Search transactions | `Ctrl + F` |
| Home / Transactions / Budgets / More | `Ctrl + 1` … `Ctrl + 4` |
| Backups | `Ctrl + B` |
| Back / close | `Esc` |
| Quit | `Ctrl + Q` |
| Show all shortcuts | `Ctrl + /` or `F1` |

The window size is remembered between runs
(`~/.config/io.github.jeffersonmk.CashewDesktop/window.ini`).

## Privacy

- Your financial data is stored **only on your computer** (see the paths
  above). There is no account, no cloud sync and no analytics.
- The app makes only two network requests on its own, and neither sends
  personal data:
  - downloading public currency exchange rates from
    [jsDelivr](https://github.com/fawazahmed0/exchange-api);
  - once a day, asking the GitHub API for the latest release of this
    repository (update check). It can be turned off in
    Settings → Desktop → Check for Updates. Nothing is downloaded or installed
    automatically.
- Links (GitHub, help pages) only open in your browser when you click them.

## Download (AppImage)

Get the latest `Cashew_Desktop-*-x86_64.AppImage` from the
[Releases page](https://github.com/jeffersonmk/cashew-desktop-oss/releases), then:

```bash
chmod +x Cashew_Desktop-*-x86_64.AppImage
./Cashew_Desktop-*-x86_64.AppImage
```

If it does not start, install FUSE 2 (`libfuse2` on Debian/Ubuntu,
`fuse2` on Arch/Fedora) or run it with `--appimage-extract-and-run`.

## Install on Linux (from source)

Requirements:

- [Flutter](https://docs.flutter.dev/get-started/install/linux) **3.22.3**
  (the version is pinned in `.fvmrc`; [fvm](https://fvm.app) is recommended)
- Linux build tools: `clang cmake ninja-build pkg-config libgtk-3-dev`

```bash
git clone https://github.com/jeffersonmk/cashew-desktop-oss.git
cd cashew-desktop-oss/budget
fvm install          # or make sure `flutter --version` is 3.22.3
./linux/packaging/install.sh
```

The script builds a release version and installs it for your user only
(no `sudo`). Afterwards, open **Cashew Desktop** from your app menu or run
`cashew-desktop`.

To uninstall (your data is kept):

```bash
./linux/packaging/install.sh --uninstall
```

## Development

```bash
cd budget
fvm flutter pub get
fvm flutter run -d linux
```

Debug builds print the app logs to the terminal.

### Database changes

1. Change the schema in `lib/database/tables.dart`.
2. Bump `schemaVersionGlobal` in the same file.
3. Run `dart run build_runner build` inside `budget/`.

## Roadmap

- [x] Remove Google Sign-In, Google Drive, Gmail and Firebase
- [x] Local backups
- [x] Native Linux build, icon and menu entry
- [x] AppImage
- [ ] Flatpak
- [ ] Windows build
- [ ] Local attachments
- [x] Keyboard shortcuts and remembered window size
- [x] Right-click menu on transactions
- [x] Desktop notifications, tray icon and start with the system
- [x] Update check (notice when a new release is out)
- [x] Popups as centered windows instead of bottom panels

## Contact

- **Bugs and suggestions:** open an
  [issue](https://github.com/jeffersonmk/cashew-desktop-oss/issues).
- **Security problems or private matters:** see [SECURITY.md](SECURITY.md).

Please don't contact the original Cashew author about this fork.

## License

[GPL-3.0](LICENSE), the same as the original Cashew.
Original work © James Kokoska and Cashew contributors.
Desktop changes © jeffersonmk.

Bundled third-party packages (in `budget/packages/`) keep their own licenses.
