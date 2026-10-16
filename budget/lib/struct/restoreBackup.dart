// Cashew Desktop: restoring a backup.
//
// The backup database is not written over the open one. It is saved next to
// it as db.sqlite.restore and swapped in at the next start, before the
// database is opened (applyPendingRestore). The data in use before the swap
// is kept as before-restore.sqlite, so a restore can be undone.
import 'dart:io';
import 'dart:typed_data';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

const String pendingRestoreFileName = "db.sqlite.restore";
const String beforeRestoreFileName = "before-restore.sqlite";

// Settings that belong to this computer, not to the data: a restored backup
// keeps the current values instead of the ones saved in it. (An old backup
// must not turn encryption off or bring back an old recovery key.)
const List<String> settingsKeptOnRestore = [
  "locale",
  "privacyMode",
  "encryptBackups",
  "backupPasswordMode",
  "backupRecoveryPublicKey",
  "localBackupFolder",
];

bool isSettingKeptOnRestore(String key) =>
    settingsKeptOnRestore.contains(key) || key.startsWith("desktop");

class RestoreSummary {
  RestoreSummary(this.backupDate, this.transactionCount, this.attachmentCount);
  // When the backup was made (settings saved in it), if known.
  final DateTime? backupDate;
  final int transactionCount;
  final int attachmentCount;
}

// Reads a few facts from a database file; throws if it is not a Cashew
// database, so a wrong file is refused before anything is replaced.
RestoreSummary readRestoreSummary(String path, {int attachmentCount = 0}) {
  final db = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
  try {
    int transactions =
        db.select("SELECT count(*) AS n FROM transactions").first["n"] as int;
    DateTime? date;
    try {
      final rows = db.select("SELECT max(date_updated) AS d FROM app_settings");
      final value = rows.isEmpty ? null : rows.first["d"];
      if (value is int && value > 0) {
        date = DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
    } catch (_) {}
    return RestoreSummary(date, transactions, attachmentCount);
  } on sql.SqliteException catch (e) {
    print("Not a Cashew backup: " + e.message);
    throw "not-a-cashew-backup".tr();
  } finally {
    db.close();
  }
}

Future<File> _pendingFile() async =>
    File(p.join(await getDatabaseDirectoryPath(), pendingRestoreFileName));

Future<File> beforeRestoreFile() async =>
    File(p.join(await getDatabaseDirectoryPath(), beforeRestoreFileName));

// Saves the backup database to be swapped in at the next start.
Future<RestoreSummary> stageRestore(Uint8List databaseBytes,
    {int attachmentCount = 0}) async {
  File pending = await _pendingFile();
  File partial = File(pending.path + ".part");
  await partial.writeAsBytes(databaseBytes, flush: true);
  if (Platform.isLinux || Platform.isMacOS) {
    await Process.run("chmod", ["600", partial.path]);
  }
  RestoreSummary summary;
  try {
    summary = readRestoreSummary(partial.path, attachmentCount: attachmentCount);
  } catch (e) {
    await partial.delete();
    rethrow;
  }
  // The data in use becomes the undo copy: save today's settings in it.
  try {
    await backupSettings();
  } catch (e) {
    print("Could not save settings before restoring: " + e.toString());
  }
  await partial.rename(pending.path);
  await updateSettings("databaseJustImported", true,
      pagesNeedingRefresh: [], updateGlobalState: false);
  return summary;
}

// Undo: the data from before the last restore is restored the same way (and
// the current data becomes the new undo copy).
Future<RestoreSummary> stageUndoRestore() async {
  File before = await beforeRestoreFile();
  return stageRestore(await before.readAsBytes());
}

Future<bool> hasPendingRestore() async => (await _pendingFile()).exists();

// Called before the database is opened.
void applyPendingRestore(String directory) {
  File pending = File(p.join(directory, pendingRestoreFileName));
  if (!pending.existsSync()) return;
  File current = File(p.join(directory, "db.sqlite"));
  try {
    if (current.existsSync()) {
      current.renameSync(p.join(directory, beforeRestoreFileName));
    }
    for (String suffix in ["-journal", "-wal", "-shm"]) {
      File extra = File(current.path + suffix);
      if (extra.existsSync()) extra.deleteSync();
    }
    pending.renameSync(current.path);
    print("Restored backup swapped in");
  } catch (e) {
    print("Could not apply the restored backup: " + e.toString());
  }
}
