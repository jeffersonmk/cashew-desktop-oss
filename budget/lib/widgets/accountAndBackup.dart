// Cashew Desktop OSS: local-only backups.
//
// The original file handled Google Sign-In, Google Drive backups and
// multi-device sync. All of that has been removed. Backups are now plain
// copies of the SQLite database written to a folder on this computer.

import 'dart:async';
import 'dart:io';

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/main.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/importDB.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

const String localBackupFilePrefix = "cashew-backup-";

Future forceDeleteDB() async {
  if (kIsWeb) {
    final html.Storage localStorage = html.window.localStorage;
    localStorage.clear();
  } else {
    final dbFile = File(p.join(await getDatabaseDirectoryPath(), 'db.sqlite'));
    await dbFile.delete();
  }
}

bool openDatabaseCorruptedPopup(BuildContext context) {
  if (isDatabaseCorrupted) {
    openPopup(
      context,
      icon: appStateSettings["outlinedIcons"]
          ? Icons.heart_broken_outlined
          : Icons.heart_broken_rounded,
      title: "database-corrupted".tr(),
      description: "database-corrupted-description".tr(),
      descriptionWidget: CodeBlock(
        text: databaseCorruptedError,
      ),
      barrierDismissible: false,
      onSubmit: () async {
        popRoute(context);
        await importDB(context, ignoreOverwriteWarning: true);
      },
      onSubmitLabel: "import-backup".tr(),
      onCancel: () async {
        popRoute(context);
        await openLoadingPopupTryCatch(() async {
          await forceDeleteDB();
          await sharedPreferences.clear();
        });
        restartAppPopup(context);
      },
      onCancelLabel: "reset".tr(),
    );
    // Lock the side navigation
    lockAppWaitForRestart = true;
    appStateKey.currentState?.refreshAppState();
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Local backups
// ---------------------------------------------------------------------------

Future<Directory> getDefaultLocalBackupDirectory() async {
  Directory base = await getApplicationSupportDirectory();
  return Directory(p.join(base.path, "backups"));
}

// Financial data: only the current user may read the folder (chmod 700).
// Home folders are world-readable on some distributions.
Future<void> restrictToOwner(String path) async {
  if (!(Platform.isLinux || Platform.isMacOS)) return;
  try {
    await Process.run("chmod", ["700", path]);
  } catch (e) {
    print("Could not restrict permissions of " + path + ": " + e.toString());
  }
}

Future<Directory> getLocalBackupDirectory() async {
  String custom = (appStateSettings["localBackupFolder"] ?? "").toString();
  Directory directory = custom.trim() != ""
      ? Directory(custom)
      : await getDefaultLocalBackupDirectory();
  if (!await directory.exists()) {
    await directory.create(recursive: true);
    // Only lock down folders we created, never one the user picked as-is.
    await restrictToOwner(directory.path);
  }
  return directory;
}

Future<List<File>> getLocalBackups() async {
  if (kIsWeb) return [];
  Directory directory = await getLocalBackupDirectory();
  List<File> files = directory
      .listSync()
      .whereType<File>()
      .where((file) =>
          p.basename(file.path).startsWith(localBackupFilePrefix) &&
          (file.path.endsWith(".sqlite") || file.path.endsWith(".sql")))
      .toList();
  files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  return files;
}

Future<File?> createLocalBackup({bool silent = false}) async {
  if (kIsWeb) return null;
  try {
    if (!silent) loadingIndeterminateKey.currentState?.setVisibility(true);
    await backupSettings();
    DBFileInfo currentDBFileInfo = await getCurrentDBFileInfo();
    Directory directory = await getLocalBackupDirectory();
    String timestamp = DateFormat("yyyy-MM-dd-HHmmss").format(DateTime.now());
    File backupFile = File(p.join(directory.path,
        "$localBackupFilePrefix$timestamp-v$schemaVersionGlobal.sqlite"));
    await backupFile.writeAsBytes(currentDBFileInfo.dbFileBytes, flush: true);
    await updateSettings("lastBackup", DateTime.now().toString(),
        pagesNeedingRefresh: [], updateGlobalState: false);
    await deleteOldLocalBackups();
    if (!silent) {
      openSnackbar(
        SnackbarMessage(
          title: "backup-created".tr(),
          description: backupFile.path,
          icon: appStateSettings["outlinedIcons"]
              ? Icons.backup_outlined
              : Icons.backup_rounded,
        ),
      );
    }
    return backupFile;
  } catch (e) {
    print("Error creating local backup: " + e.toString());
    openSnackbar(
      SnackbarMessage(
        title: "error-saving".tr(),
        description: e.toString(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.error_outlined
            : Icons.error_rounded,
      ),
    );
    return null;
  } finally {
    if (!silent) loadingIndeterminateKey.currentState?.setVisibility(false);
  }
}

Future<void> deleteOldLocalBackups() async {
  int limit = int.tryParse(appStateSettings["backupLimit"].toString()) ?? 20;
  List<File> backups = await getLocalBackups();
  for (File file in backups.skip(limit)) {
    try {
      await file.delete();
    } catch (e) {
      print("Could not delete old backup " + file.path);
    }
  }
}

Future<void> restoreLocalBackup(BuildContext context, File file) async {
  dynamic result = await openPopup(
    context,
    title: "load-backup".tr(),
    subtitle: getWordedDateShortMore(
      file.lastModifiedSync(),
      includeTime: true,
      includeYear: true,
      showTodayTomorrow: false,
    ),
    beforeDescriptionWidget: Padding(
      padding: const EdgeInsetsDirectional.only(top: 8, bottom: 5),
      child: CodeBlock(text: p.basename(file.path)),
    ),
    description: "load-backup-warning".tr(),
    icon: appStateSettings["outlinedIcons"]
        ? Icons.warning_outlined
        : Icons.warning_rounded,
    onSubmit: () => popRoute(context, true),
    onSubmitLabel: "load".tr(),
    onCancel: () => popRoute(context),
    onCancelLabel: "cancel".tr(),
  );
  if (result != true) return;
  await openLoadingPopupTryCatch(() async {
    await overwriteDefaultDB(await file.readAsBytes());
    await resetLanguageToSystem(context);
    await updateSettings("databaseJustImported", true,
        pagesNeedingRefresh: [], updateGlobalState: false);
    return true;
  }, onSuccess: (_) {
    openSnackbar(
      SnackbarMessage(
        title: "backup-restored".tr(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.settings_backup_restore_outlined
            : Icons.settings_backup_restore_rounded,
      ),
    );
    restartAppPopup(context,
        description: "restart-required-to-load-backup".tr());
  }, onError: (e) {
    openSnackbar(SnackbarMessage(
      title: "error-importing".tr(),
      description: e.toString(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.error_outlined
          : Icons.error_rounded,
    ));
  });
}

// Runs once on launch: creates a local backup when one is due.
Future<void> createBackupInBackground(context) async {
  if (kIsWeb) return;
  if (appStateSettings["autoBackups"] != true) return;
  DateTime lastBackup =
      DateTime.tryParse(appStateSettings["lastBackup"].toString()) ??
          DateTime(0);
  int frequency =
      int.tryParse(appStateSettings["autoBackupsFrequency"].toString()) ?? 3;
  if (DateTime.now().isAfter(lastBackup.add(Duration(days: frequency)))) {
    print("Creating automatic local backup");
    await createLocalBackup(silent: true);
  }
}
