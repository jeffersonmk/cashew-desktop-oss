// Cashew Desktop: find and remove attachment files that no transaction uses.
//
// Removing an attachment from a transaction (or deleting the transaction, or
// restoring an older backup) never deletes the file, so the attachments
// folder can fill up with files nothing points to; they also go into every
// .zip backup. This lists them and, after the user confirms, moves them to
// the desktop trash (gio trash) so a mistake can be undone. Only if there is
// no trash are they deleted.

import 'package:budget/widgets/accountAndBackup.dart' show restrictToOwner;
import 'dart:io';

import 'package:budget/functions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/fullBackup.dart';
import 'package:budget/struct/localAttachments.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

final RegExp _attachmentLinkPattern =
    RegExp(RegExp.escape(attachmentScheme) + r'[^\s]+');

// File names referenced by any transaction note.
Future<Set<String>> referencedAttachmentNames() async {
  List<String> notes = (await database
          .customSelect("SELECT note FROM transactions WHERE note LIKE ?",
              variables: [Variable.withString("%" + attachmentScheme + "%")])
          .get())
      .map((row) => row.read<String>("note"))
      .toList();
  Set<String> names = {};
  // Cashew Desktop: custom account (bank) icons live in the same folder.
  List<String> walletIcons = (await database
          .customSelect("SELECT icon_name FROM wallets WHERE icon_name LIKE ?",
              variables: [Variable.withString(attachmentScheme + "%")])
          .get())
      .map((row) => row.read<String>("icon_name"))
      .toList();
  for (String iconName in walletIcons) {
    String? name = attachmentFileNameFromLink(iconName);
    if (name != null) names.add(name);
  }
  for (String note in notes) {
    for (RegExpMatch match in _attachmentLinkPattern.allMatches(note)) {
      String? name = attachmentFileNameFromLink(match.group(0)!);
      if (name != null) names.add(name);
    }
  }
  return names;
}

Future<List<File>> findUnusedAttachments() async {
  Set<String> used = await referencedAttachmentNames();
  return (await listAttachmentFiles())
      .where((file) => !used.contains(p.basename(file.path)))
      .toList();
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return "$bytes B";
  if (bytes < 1024 * 1024) return (bytes / 1024).toStringAsFixed(0) + " KB";
  return (bytes / (1024 * 1024)).toStringAsFixed(1) + " MB";
}

// Moves the file to the trash; false if that is not possible.
Future<bool> _moveToTrash(File file) async {
  try {
    ProcessResult result = await Process.run("gio", ["trash", file.path]);
    return result.exitCode == 0;
  } catch (e) {
    return false;
  }
}

// Where files go when the system trash can't be used (e.g. a Flatpak whose
// trash portal fails): a folder next to attachments/, so nothing is lost.
const String removedAttachmentsFolderName = "removed-attachments";

Future<void> _moveToRemovedFolder(File file) async {
  Directory folder = Directory(
      p.join(p.dirname(p.dirname(file.path)), removedAttachmentsFolderName));
  if (!await folder.exists()) {
    await folder.create(recursive: true);
    await restrictToOwner(folder.path);
  }
  String target = p.join(folder.path, p.basename(file.path));
  int n = 1;
  while (await File(target).exists()) {
    target = p.join(folder.path,
        p.basenameWithoutExtension(file.path) + "-$n" + p.extension(file.path));
    n++;
  }
  await file.rename(target);
}

class RemovedAttachments {
  int toTrash = 0;
  int toFolder = 0;
  int get total => toTrash + toFolder;
}

Future<RemovedAttachments> removeAttachmentFiles(List<File> files) async {
  RemovedAttachments removed = RemovedAttachments();
  for (File file in files) {
    try {
      if (await _moveToTrash(file)) {
        removed.toTrash++;
      } else {
        await _moveToRemovedFolder(file);
        removed.toFolder++;
      }
    } catch (e) {
      print("Could not remove attachment " + file.path + ": " + e.toString());
    }
  }
  return removed;
}

Future<void> openUnusedAttachmentsCleanup(BuildContext context) async {
  List<File> unused = await findUnusedAttachments();
  IconData icon = appStateSettings["outlinedIcons"]
      ? Icons.cleaning_services_outlined
      : Icons.cleaning_services_rounded;
  if (unused.isEmpty) {
    openSnackbar(SnackbarMessage(
      title: "no-unused-attachments".tr(),
      icon: icon,
    ));
    return;
  }
  int totalBytes = 0;
  for (File file in unused) {
    totalBytes += await file.length();
  }
  await openPopup(
    context,
    icon: icon,
    title: "clean-unused-attachments-question".tr(),
    description: "clean-unused-attachments-description".tr(namedArgs: {
      "count": unused.length.toString(),
      "size": formatFileSize(totalBytes),
    }),
    onCancelLabel: "cancel".tr(),
    onCancel: () => popRoute(context),
    onSubmitLabel: "remove".tr(),
    onSubmit: () async {
      popRoute(context);
      RemovedAttachments removed = await removeAttachmentFiles(unused);
      openSnackbar(SnackbarMessage(
        title: removed.toFolder == 0
            ? "unused-attachments-removed"
                .tr(namedArgs: {"count": removed.total.toString()})
            : "unused-attachments-moved-to-folder".tr(namedArgs: {
                "count": removed.total.toString(),
                "folder": removedAttachmentsFolderName,
              }),
        icon: icon,
      ));
    },
  );
}
