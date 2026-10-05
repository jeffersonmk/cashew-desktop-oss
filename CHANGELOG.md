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

## [1.0.5] - 2026-10-05

### Added
- Backups include the attachments: when there are attached files, the backup
  (automatic, "Backup" and "Export") is a single `.zip` with the database and
  the attachments. Restoring or importing it brings the attachments back
  (files already in the attachments folder are kept). Without attachments the
  backup is still a plain `.sqlite`.
- Drag and drop: drop files on the add/edit transaction screen to attach them.

### Removed
- "Rate the app" prompts: the box on the home page (it opened the original
  app's App Store page) and the star-rating popup. Settings → Feedback now
  opens the GitHub issues page, like the About page.

## [1.0.4] - 2026-10-01

### Added
- Local attachments: "Add attachment" under the transaction notes picks a
  file (receipt, invoice, photo...) and copies it into the app's data folder
  (`attachments/`, readable only by your user). Click the paperclip in the
  transaction list or in the notes to open it. The Data Backup page has an
  "Attachments folder" shortcut. Note: `.sqlite` backups don't include the
  files, copy the attachments folder too.

### Changed
- Popups (choosing a category, entering the amount, picking a color, the
  title, the repeat period, and so on) open as a window in the center of the
  screen instead of a panel sliding up from the bottom. Narrow windows keep
  the bottom panel. Can be turned off in Settings → Desktop → "Popups as
  windows".
- Portuguese: fixed 77 machine-translation mistakes in pt-BR (46 also in
  pt-PT), e.g. "Inscrição" → "Assinatura", "balanço/equilíbrio" → "saldo",
  "Coletado" → "Recebido", "Repita todos" → "Repetir a cada". New default
  category names: Mercado, Restaurantes, Transporte (existing categories keep
  their names).
- Popup titles use sentence case outside English ("Insira o valor" instead of
  "Insira A Quantia").

## [1.0.3] - 2026-09-30

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
- Update check: once a day the app asks GitHub for the latest release and
  shows a notice with a link to the download page when a newer version is
  out. Can be turned off in Settings → Desktop, which also has "Check Now".
- Portuguese (Brazil and Portugal) translations for everything added in
  Cashew Desktop: shortcuts, right-click menu, Desktop settings, tray menu,
  notifications, About and Data Backup pages. Other languages show English.

### Fixed
- Release build: updated `actions/checkout` to v6 (Node.js 24), removing the
  Node.js 20 deprecation warning.
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

[Unreleased]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.4...HEAD
[1.0.4]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/jeffersonmk/cashew-desktop-oss/releases/tag/v1.0.0
