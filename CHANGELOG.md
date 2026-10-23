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

## [1.0.8] - 2026-10-23

### Added
- Exchange rates: currencies the rates API has no rate for (about 200 of
  the crypto list, e.g. TON, WBTC, MATIC) are now marked "No exchange rate"
  in the currency picker and on the Exchange Rates page, and an account in
  such a currency shows a warning (tap to set a custom rate). Before, they
  were silently counted as 1 = 1 USD.
- Exchange Rates page shows the date of the rates and when they were
  downloaded.

### Changed
- Exchange rates fall back to the API's official mirror on Cloudflare
  (`latest.currency-api.pages.dev`) when jsDelivr fails, as the API author
  recommends. Responses are only accepted if they are a valid USD rate
  table.

### Fixed
- Side menu clock: the time no longer fades out on its right side (e.g.
  "11:2" with a faded "2") when the side menu is narrow; the whole time
  now fits, shrinking a little if needed.
- Installments of a goal or loan set to "until goal reached" / "until loan
  paid off" now stop once the goal is reached or the loan is settled. Before
  (also in the original Cashew) a new installment was created forever: the
  check read the wrong column for goals and skipped loans. The check now
  uses the same progress shown on the goal page, in the primary currency.
- "Erase everything" no longer says Google Drive backups will be kept: it
  now says local backups and attachment files stay on the computer. The CSV
  export warning points to Backups instead of Google Drive.

## [1.0.7] - 2026-10-21

### Added
- **Bank icon for accounts**: in Edit account → "Bank or Digital Account",
  pick the logo of the bank or digital account (32 Brazilian institutions:
  Nubank, Inter, Itaú, Banco do Brasil, Caixa, Bradesco, Santander, C6,
  PicPay, Mercado Pago, PagBank, Sicoob, Sicredi, XP...) or your own image.
  The logo appears on the account cards, the account lists and pickers,
  the transaction filters and the account tag of each transaction. It is
  saved in a field the original Cashew already had, so the database and
  backups stay compatible. Custom images are kept in the attachments folder
  and go into .zip backups. Logos from
  [logos-bancos-br](https://github.com/rzmt/logos-bancos-br); see
  `budget/assets/banks/NOTICE.md`.

## [1.0.6] - 2026-10-16

### Added
- Install from source (`install.sh`): at the end it offers to delete the
  downloaded source folder (or use `--remove-source` / `--keep-source`). It
  is never deleted if it has changes or commits not on GitHub. The new
  `cashew-desktop-uninstall` command removes the app without the source.
- **Flatpak**: each release now also has a `.flatpak` file. It uses the same
  data folder and keyring entry as the AppImage. See README for install,
  update and uninstall.
- Restoring a backup: a "Restart Now" button reopens the app by itself, and
  the window shows what was restored (date, transactions, attachments).
- "Undo Restore" in Backups brings back the data from before the last restore.
- Tray icon: left click shows or hides the window; the menu has "Add
  Transaction" and "Backup Now" (the result is shown as a notification).
- Privacy mode: hides all amounts (balances, transactions, budgets, graphs)
  behind dots. Toggle it with `Ctrl + H`, the eye button in the side menu or
  the tray menu; it is remembered between runs. Amounts are still shown
  while adding or editing a transaction.
- "Clean Unused Attachments" in Backups: finds attachment files no
  transaction uses anymore and, after confirming, moves them to the trash.
- Encrypted backups (optional, in Backups): AES-256-GCM with a password
  (Argon2id). The password is either saved in the system keyring (GNOME
  Keyring/KWallet), so automatic backups keep working, or asked every time.
  An optional recovery key (shown once, to write down) also opens the
  backups if the password is forgotten. Encrypted backups (`.enc`) can also
  be opened without the app with `tools/decrypt-backup.py`.

### Changed
- Built with Flutter 3.47 (was 3.22) and updated dependencies. Rendering now
  uses Impeller.

### Fixed
- Restoring a backup no longer resets the language, and no longer turns off
  backup encryption or other settings of this computer.
- A restored backup is checked first and swapped in at the next start instead
  of being written over the open database; a file that is not a Cashew backup
  is refused without changing anything.
- A "Biometrics Error" popup on the first launch after restoring a backup
  (Linux has no biometric unlock; the check is now skipped).

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

[Unreleased]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.8...HEAD
[1.0.8]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.7...v1.0.8
[1.0.7]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/jeffersonmk/cashew-desktop-oss/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/jeffersonmk/cashew-desktop-oss/releases/tag/v1.0.0
