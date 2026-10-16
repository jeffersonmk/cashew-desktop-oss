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
| Platforms | Android, iOS, Web | **Linux only** (see below) |
| Google Sign-In | Yes | **Removed** |
| Google Drive backup / sync | Yes | **Removed**, replaced by local backups |
| Shared budgets (Firebase) | Yes | Removed |
| Gmail auto-transactions | Yes | Removed |
| Transaction attachments | Uploaded to Google Drive | **Local**: copied into the data folder, included in backups |
| Notifications | Yes | Yes, as desktop notifications (while the app is running, e.g. in the tray) |
| "Rate the app" prompts | Yes | Removed |

> **Linux only. No Windows version is planned.** Linux is the maintainer's
> daily system, and this fork is built, tested and maintained only there.
> There are no plans to make, test or maintain a Windows build, and Windows
> requests or bug reports won't be worked on. If you want a Windows version,
> you are free to fork this project (GPL-3.0) and maintain it yourself.

Everything else (budgets, transactions, goals, subscriptions, loans,
graphs, CSV import, themes, translations) comes from Cashew.

## Local backups

Open **Backups** in the side menu:

- **Backup**: saves a copy of your database to the backup folder. If you
  have attachments, the backup is a single `.zip` with the database and the
  attached files; otherwise it is a plain `.sqlite`.
- **Auto backups**: creates a backup every *N* days when the app starts.
- **Backup limit**: keeps only the newest backups.
- **Backup folder**: choose another folder (for example one synced with
  Syncthing or Nextcloud). Long-press to go back to the default.
- **Export / Import**: save or load a backup anywhere. `.sqlite` files are
  compatible with the original Cashew app; `.zip` backups (with attachments)
  only work in Cashew Desktop. Restoring a `.zip` brings the attachments back
  (files already in the attachments folder are kept).
- **Attachments folder**: opens the folder with your attached files.

Where your data lives on Linux:

| What | Path |
|---|---|
| Database | `~/.local/share/io.github.jeffersonmk.CashewDesktop/db.sqlite` |
| Backups (default) | `~/.local/share/io.github.jeffersonmk.CashewDesktop/backups/` |
| Attachments | `~/.local/share/io.github.jeffersonmk.CashewDesktop/attachments/` |
| Settings | `~/.local/share/io.github.jeffersonmk.CashewDesktop/shared_preferences.json` |

## Attachments

In the add/edit transaction screen, use **Add Attachment** (below the notes)
or **drag and drop** files onto the window. The file is copied into the
attachments folder; your original file is not touched. Click the attachment,
or the paperclip in the transaction list, to open it with your default app.
Removing an attachment from a transaction does not delete the file.
**Backups → Clean Unused Attachments** moves files no transaction uses
anymore to the trash.

## Encrypted backups

In **Backups**, turn on **Encrypt Backups** to protect backup files with a
password (AES-256-GCM, key derived with Argon2id). Choose where the password
lives:

- **Saved in the system keyring** (GNOME Keyring / KWallet): automatic
  backups keep working; the password is only typed to restore on another
  computer.
- **Ask every time**: typed for every backup and restore; automatic backups
  are skipped.

When you turn encryption on, the app also offers a **recovery key** (shown
only once): write it down and keep it away from the computer. If you forget
the password, type the recovery key instead when restoring. **Without the
password or the recovery key, encrypted backups cannot be restored.**
**New Recovery Key** makes a new one; backups made before keep opening with
the old one.

Encrypted backups end in `.enc`. To open one without the app (asks for the
password or the recovery key):

```bash
uv run --with argon2-cffi --with cryptography tools/decrypt-backup.py BACKUP.enc
```

This gives the normal backup `.zip` (`db.sqlite` + `attachments/`). Only the
backup files are encrypted, not the app data on your disk (use disk
encryption for that).

## Desktop integration

In **Settings → Desktop**:

- **Keep Running in the Tray**: closing the window keeps the app in the
  system tray, so reminders and upcoming-bill notifications keep working.
  Click the tray icon to show or hide the window; its menu also has **Add
  Transaction**, **Backup Now** and **Hide Amounts**. Use **Quit** in the tray menu (or
  `Ctrl + Q`) to really close it. Needs a
  panel with tray icons (StatusNotifierItem / libayatana-appindicator).
- **Start with the System**: opens the app minimized to the tray when you log
  in (XDG autostart). If you move or replace the AppImage, open the app once
  from its new location (or turn the option off and on) so the autostart
  points to the right file.
- **Popups as Windows**: on wide windows, options open as a centered window
  instead of a panel sliding up from the bottom.
- **Check for Updates**: shows a notice when a new release is published.

Only one copy of the app runs at a time: opening it again brings the existing
window back.

## Keyboard shortcuts

| Action | Keys |
|---|---|
| New transaction | `Ctrl + N` |
| Search transactions | `Ctrl + F` |
| Home / Transactions / Budgets / More | `Ctrl + 1` … `Ctrl + 4` |
| Backups | `Ctrl + B` |
| Hide / show amounts (privacy mode) | `Ctrl + H` |
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
- Attachments are copied into `attachments/` inside the data folder, readable
  only by your user, and included in the `.zip` backups.
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

## Download (Flatpak)

Get the latest `Cashew_Desktop-*-x86_64.flatpak` from the
[Releases page](https://github.com/jeffersonmk/cashew-desktop-oss/releases).

**Install** (the first time it also downloads the GNOME runtime from Flathub,
a few hundred MB):

```bash
flatpak install --user Cashew_Desktop-*-x86_64.flatpak
```

Then open **Cashew Desktop** from your app menu, or run
`flatpak run io.github.jeffersonmk.CashewDesktop`.

**Update:** download the new `.flatpak` from Releases and run the same
`flatpak install --user ...` command again. (The app does not check for
updates in the Flatpak version: the Releases page is the place to look.)

**Uninstall** (your data is kept):

```bash
flatpak uninstall --user io.github.jeffersonmk.CashewDesktop
```

The Flatpak uses the **same data folder as the AppImage**
(`~/.local/share/io.github.jeffersonmk.CashewDesktop`) and the same keyring
entry for the backup password, so you can switch between them without moving
anything. Don't run both at the same time.

What the Flatpak is allowed to access: its data folder, `~/Downloads`
(exports), `~/.config/autostart` (start with the system), the network
(exchange rates), the tray, notifications and the keyring. Other files only
when you pick them in a file dialog. A custom backup folder chosen in an
older version must be chosen again in the Flatpak (it is then shown with an
internal path like `/run/user/1000/doc/...`; the files still go to the folder
you picked). "Clean Unused Attachments" moves files to a `removed-attachments`
folder inside the data folder when the system trash can't be used.

## Install on Linux (from source)

Requirements:

- [Flutter](https://docs.flutter.dev/get-started/install/linux) **3.47.7**
  (the version is pinned in `.fvmrc`; [fvm](https://fvm.app) is recommended)
- Linux build tools: `clang cmake ninja-build pkg-config libgtk-3-dev`

```bash
git clone https://github.com/jeffersonmk/cashew-desktop-oss.git
cd cashew-desktop-oss/budget
fvm install          # or make sure `flutter --version` is 3.47.7
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
- [x] Flatpak (`.flatpak` file on the Releases page)
- [x] Keyboard shortcuts and remembered window size
- [x] Right-click menu on transactions
- [x] Desktop notifications, tray icon and start with the system
- [x] Update check (notice when a new release is out)
- [x] Popups as centered windows instead of bottom panels
- [x] Local attachments (receipts, invoices) stored in the data folder
- [x] Backups with attachments (`.zip`) and drag and drop to attach

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
