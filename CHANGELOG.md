# Changelog

All notable changes to Cashew Desktop are listed here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

<!--
How to use:
- While working, add each change under "Unreleased".
- When releasing: rename "Unreleased" to the version and date, bump
  `version:` in budget/pubspec.yaml, commit, then tag (git tag vX.Y.Z).
  The release workflow uses this section as the release notes.
-->

## [Unreleased]

### Added
- Keyboard shortcuts: `Ctrl+N` new transaction, `Ctrl+F` search,
  `Ctrl+B` backups, `Ctrl+Q` quit, `Ctrl+/` or `F1` shows the list.
- `Ctrl+1` … `Ctrl+4` now switch pages from any screen, not only the main one.
- The window size is remembered between runs (and the position on X11).
- "Keyboard shortcuts" item in Settings (Tools & Extras) listing all shortcuts.
- Right-click menu on transactions: Edit, Duplicate, Duplicate (Today),
  Select and Delete (asks for confirmation).
- Desktop notifications on Linux: daily reminder and upcoming bills /
  subscriptions. Clicking a notification opens the app. Reminders are shown
  while the app is running (window open or in the tray).
- Settings → Desktop:
  - "Keep running in the tray": closing the window keeps the app in the tray
    (right-click the icon for Open / Quit).
  - "Start with the system": opens minimized to the tray when you log in.
- Opening the app again brings the existing window back instead of starting a
  second copy.

### Fixed
- Shortcuts that leave a page (`Ctrl+1` … `Ctrl+4`, `Ctrl+B`, `Esc`) now ask
  before discarding an unsaved transaction instead of closing it.

## [1.0.2] - 2026-09-30

### Changed
- About page: shows the fork maintainer and keeps the credit to the original
  Cashew authors (James Kokoska and YuYing).
- Contact and feedback go to GitHub Issues; private security reports are
  explained in `SECURITY.md`.
- FAQ and help links point to this repository.

### Removed
- "Google Cloud APIs" credit (no longer used).

## [1.0.1] - 2026-09-30

### Fixed
- The app crashed when closing its window on Linux.

### Changed
- The app has its own version number (the About page showed Cashew's 5.4.3).
- The original Cashew changelog no longer opens automatically.
- About page links point to this repository.

### Removed
- Premium popups, banner and store connection (in-app purchases only exist in
  the original mobile app). All features stay unlocked.

## [1.0.0] - 2026-09-30

First release of Cashew Desktop, a fork of
[Cashew](https://github.com/jameskokoska/Cashew) for Linux.

### Added
- Native Linux build, distributed as an AppImage.
- Local backups: manual and automatic backups, backup limit, custom backup
  folder, restore and delete.
- New name, icon and app id (`io.github.jeffersonmk.CashewDesktop`).

### Removed
- Google Sign-In, Google Drive backup and sync, shared budgets (Firebase),
  Gmail auto-transactions and Drive attachments.

### Fixed
- Startup on Linux (notifications and time zone detection).

[Unreleased]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/jeffersonmk/cashew-desktop-oss/releases/tag/v1.0.0
