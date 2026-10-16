// Cashew Desktop: file and folder choosers.
//
// file_picker opens zenity/qarma/kdialog on Linux, which do not exist inside
// a Flatpak. There the native GTK chooser is used instead: in a sandbox it
// goes through the file chooser portal, so any file the user picks can be
// read. Elsewhere file_picker is kept as before.
import 'dart:io';

import 'package:budget/struct/desktopIntegration.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

Future<String?> _nativePickPath({String? title, bool directory = false}) {
  return desktopChannel.invokeMethod<String>("pickPath", {
    "title": title ?? "",
    "directory": directory,
  });
}

Future<FilePickerResult?> pickFilesCompat({
  String? dialogTitle,
  bool allowMultiple = false,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) async {
  if (!isFlatpak) {
    return FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      allowMultiple: allowMultiple,
      type: type,
      allowedExtensions: allowedExtensions,
    );
  }
  String? path = await _nativePickPath(title: dialogTitle);
  if (path == null) return null;
  return FilePickerResult([
    PlatformFile(
      path: path,
      name: p.basename(path),
      size: await File(path).length(),
    ),
  ]);
}

Future<String?> getDirectoryPathCompat({String? dialogTitle}) {
  if (!isFlatpak) {
    return FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle);
  }
  return _nativePickPath(title: dialogTitle, directory: true);
}
