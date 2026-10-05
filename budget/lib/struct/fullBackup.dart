// Cashew Desktop: backups that include the local attachments.
//
// When the attachments folder has files, backups are written as a .zip:
//
//   db.sqlite
//   attachments/<file name>
//   ...
//
// Without attachments the backup stays a plain .sqlite file, exactly as
// before (and still readable by older versions).
//
// Restoring a .zip replaces the database and copies the attachments back
// (existing attachments are kept). Entries are validated: only "db.sqlite"
// and "attachments/<plain file name>" are read; anything else, including
// paths with "..", is ignored.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:budget/struct/localAttachments.dart';
import 'package:path/path.dart' as p;

const String backupDatabaseEntry = "db.sqlite";
const String backupAttachmentsPrefix = "attachments/";

bool isZipBackup(String path) => path.toLowerCase().endsWith(".zip");

Future<List<File>> listAttachmentFiles() async {
  if (!localAttachmentsSupported) return [];
  Directory directory = await getAttachmentsDirectory();
  return directory
      .listSync()
      .whereType<File>()
      .where((file) =>
          attachmentFileNameFromLink(
              attachmentScheme + p.basename(file.path)) !=
          null)
      .toList();
}

// Writes [databaseBytes] and every attachment into a zip at [zipPath].
// The zip is written next to the target and renamed when complete, so an
// interrupted backup never leaves a broken file with the final name.
Future<void> writeZipBackup(
    String zipPath, List<int> databaseBytes, List<File> attachments) async {
  String partialPath = zipPath + ".part";
  ZipFileEncoder encoder = ZipFileEncoder();
  encoder.create(partialPath);
  try {
    Uint8List bytes = Uint8List.fromList(databaseBytes);
    encoder.addArchiveFile(ArchiveFile(backupDatabaseEntry, bytes.length, bytes));
    for (File file in attachments) {
      await encoder.addFile(
          file, backupAttachmentsPrefix + p.basename(file.path));
    }
  } finally {
    encoder.close();
  }
  await File(partialPath).rename(zipPath);
}

class ZipBackupContents {
  ZipBackupContents(this.databaseBytes, this.attachmentCount);
  final Uint8List databaseBytes;
  final int attachmentCount;
}

// Reads a zip backup: returns the database and copies the attachments into
// the attachments folder (files that already exist there are kept).
Future<ZipBackupContents> readZipBackup(String zipPath,
    {bool restoreAttachments = true}) async {
  InputFileStream input = InputFileStream(zipPath);
  try {
    Archive archive = ZipDecoder().decodeBuffer(input);
    Uint8List? databaseBytes;
    int attachmentCount = 0;
    Directory? attachmentsDirectory =
        restoreAttachments ? await getAttachmentsDirectory() : null;
    for (ArchiveFile entry in archive.files) {
      if (!entry.isFile) continue;
      String name = entry.name.replaceAll("\\", "/");
      if (name == backupDatabaseEntry) {
        databaseBytes = Uint8List.fromList(entry.content as List<int>);
      } else if (attachmentsDirectory != null &&
          name.startsWith(backupAttachmentsPrefix)) {
        String fileName = name.substring(backupAttachmentsPrefix.length);
        // Same check as links in notes: a plain, safe file name only.
        if (attachmentFileNameFromLink(attachmentScheme + fileName) == null) {
          continue;
        }
        File destination = File(p.join(attachmentsDirectory.path, fileName));
        if (!p.isWithin(attachmentsDirectory.path, destination.path)) continue;
        attachmentCount++;
        if (await destination.exists()) continue;
        await destination.writeAsBytes(entry.content as List<int>, flush: true);
        if (Platform.isLinux || Platform.isMacOS) {
          await Process.run("chmod", ["600", destination.path]);
        }
      }
    }
    if (databaseBytes == null) {
      throw Exception("db.sqlite not found in the backup");
    }
    return ZipBackupContents(databaseBytes, attachmentCount);
  } finally {
    await input.close();
  }
}
