// Cashew Desktop: local attachments.
//
// The original Cashew uploaded attachments to Google Drive and put the link
// in the transaction note. Here the chosen file is copied into the app's own
// data folder and the note gets a reference to it:
//
//   cashew-attachment://20261001-142530-receipt.pdf
//
// Only the file name is stored, never a path, so the reference keeps working
// if the data folder moves. The name is checked before use so a crafted note
// can never point outside the attachments folder.

import 'dart:io';

import 'package:budget/functions.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String attachmentScheme = "cashew-attachment://";

bool get localAttachmentsSupported => !kIsWeb && isDesktopPlatform;

bool isLocalAttachmentLink(String link) => link.startsWith(attachmentScheme);

Future<Directory> getAttachmentsDirectory() async {
  Directory base = await getApplicationSupportDirectory();
  Directory directory = Directory(p.join(base.path, "attachments"));
  if (!await directory.exists()) {
    await directory.create(recursive: true);
    await restrictToOwner(directory.path);
  }
  return directory;
}

// Letters (any language), digits, dot, dash and underscore. Everything else,
// including spaces and path separators, becomes "_".
String sanitizeAttachmentName(String name) {
  String base = p.basename(name);
  String clean = base.replaceAll(RegExp(r'[^\p{L}\p{N}._-]', unicode: true), "_");
  clean = clean.replaceAll(RegExp(r'_+'), "_");
  // No hidden files / no "." or ".."
  clean = clean.replaceFirst(RegExp(r'^\.+'), "");
  if (clean == "") clean = "file";
  if (clean.length > 120) {
    String extension = p.extension(clean);
    if (extension.length > 12) extension = "";
    clean = clean.substring(0, 120 - extension.length) + extension;
  }
  return clean;
}

// The file name stored in a link, or null if it isn't a safe plain name.
String? attachmentFileNameFromLink(String link) {
  if (!isLocalAttachmentLink(link)) return null;
  String name = link.substring(attachmentScheme.length).trim();
  if (name == "" ||
      name.contains("/") ||
      name.contains("\\") ||
      name.startsWith(".") ||
      name != sanitizeAttachmentName(name)) {
    return null;
  }
  return name;
}

// Name shown to the user: without the date prefix added when it was copied.
String attachmentDisplayName(String link) {
  String? name = attachmentFileNameFromLink(link);
  if (name == null) return "attachment-missing".tr();
  return name.replaceFirst(RegExp(r'^\d{8}-\d{6}(-\d+)?-'), "");
}

Future<File?> getAttachmentFile(String link) async {
  String? name = attachmentFileNameFromLink(link);
  if (name == null) return null;
  Directory directory = await getAttachmentsDirectory();
  File file = File(p.join(directory.path, name));
  // Defense in depth: the resolved path must stay inside the folder.
  if (!p.isWithin(directory.path, file.path)) return null;
  return file;
}

String _timestamp(DateTime now) {
  String two(int n) => n.toString().padLeft(2, "0");
  return now.year.toString() +
      two(now.month) +
      two(now.day) +
      "-" +
      two(now.hour) +
      two(now.minute) +
      two(now.second);
}

// Copies [source] into the attachments folder; returns the link for the note.
Future<String> copyFileToAttachments(File source) async {
  Directory directory = await getAttachmentsDirectory();
  String baseName = sanitizeAttachmentName(source.path);
  String prefix = _timestamp(DateTime.now());
  String name = prefix + "-" + baseName;
  int counter = 1;
  while (await File(p.join(directory.path, name)).exists()) {
    counter++;
    name = prefix + "-" + counter.toString() + "-" + baseName;
  }
  File destination = File(p.join(directory.path, name));
  await source.copy(destination.path);
  if (Platform.isLinux || Platform.isMacOS) {
    // Same as the database: only the user can read their receipts.
    await Process.run("chmod", ["600", destination.path]);
  }
  return attachmentScheme + name;
}

// Lets the user pick a file and copies it. Null if cancelled or on error.
Future<String?> pickAndAttachFile() async {
  try {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: "add-attachment".tr(),
      allowMultiple: false,
    );
    String? path = result?.files.single.path;
    if (path == null) return null;
    File source = File(path);
    if (!await source.exists()) return null;
    return await copyFileToAttachments(source);
  } catch (e) {
    print("Attachment error: " + e.toString());
    openSnackbar(SnackbarMessage(
      title: "attachment-error".tr(),
      description: e.toString(),
      icon: Icons.warning_rounded,
    ));
    return null;
  }
}

// Opens the attachment with the system's default app.
Future<bool> openLocalAttachment(String link) async {
  File? file = await getAttachmentFile(link);
  if (file == null || !await file.exists()) {
    openSnackbar(SnackbarMessage(
      title: "attachment-missing".tr(),
      description: "attachment-missing-description".tr(),
      icon: Icons.warning_rounded,
    ));
    return false;
  }
  return await _openWithSystem(file.path);
}

// ---------------------------------------------------------------------------
// Drag and drop. The native side calls handleDroppedFiles(); the screen that
// can take attachments (add/edit transaction notes) registers a handler while
// it is visible. The most recently registered handler wins.
// ---------------------------------------------------------------------------

typedef DroppedAttachmentHandler = void Function(List<String> links);

final List<DroppedAttachmentHandler> _dropHandlers = [];

void registerAttachmentDropHandler(DroppedAttachmentHandler handler) {
  _dropHandlers.remove(handler);
  _dropHandlers.add(handler);
}

void unregisterAttachmentDropHandler(DroppedAttachmentHandler handler) {
  _dropHandlers.remove(handler);
}

Future<void> handleDroppedFiles(List<String> paths) async {
  if (!localAttachmentsSupported) return;
  if (_dropHandlers.isEmpty) {
    openSnackbar(SnackbarMessage(
      title: "drop-attachment-here".tr(),
      description: "drop-attachment-here-description".tr(),
      icon: Icons.attach_file_rounded,
    ));
    return;
  }
  List<String> links = [];
  for (String path in paths) {
    File file = File(path);
    // Regular files only (no folders, no device files).
    if (FileSystemEntity.typeSync(path, followLinks: true) !=
        FileSystemEntityType.file) continue;
    try {
      links.add(await copyFileToAttachments(file));
    } catch (e) {
      print("Attachment error: " + e.toString());
    }
  }
  if (links.isEmpty) {
    openSnackbar(SnackbarMessage(
      title: "attachment-error".tr(),
      icon: Icons.warning_rounded,
    ));
    return;
  }
  _dropHandlers.last(links);
  openSnackbar(SnackbarMessage(
    title: links.length == 1
        ? "attachment-added".tr()
        : "attachments-added".tr(namedArgs: {"count": links.length.toString()}),
    description: links.map(attachmentDisplayName).join(", "),
    icon: Icons.attach_file_rounded,
  ));
}

Future<bool> openAttachmentsFolder() async {
  Directory directory = await getAttachmentsDirectory();
  return await _openWithSystem(directory.path);
}

Future<bool> _openWithSystem(String path) async {
  try {
    String command = Platform.isLinux
        ? "xdg-open"
        : Platform.isMacOS
            ? "open"
            : "explorer";
    // Arguments are passed directly (no shell), so the path is never parsed
    // as a command.
    await Process.start(command, [path], mode: ProcessStartMode.detached);
    return true;
  } catch (e) {
    print("Could not open " + path + ": " + e.toString());
    return false;
  }
}
