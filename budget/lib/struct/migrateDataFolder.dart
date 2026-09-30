// Cashew Desktop: move data from the old app folder after the app id change.
//
// Early development builds used the id "com.jeffersonmk.budget", so the
// database and settings were stored in ~/.local/share/com.jeffersonmk.budget.
// The app is now "io.github.jeffersonmk.CashewDesktop". If the new folder is
// empty and the old one exists, move the old one over once.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const List<String> _oldAppIds = ["com.jeffersonmk.budget"];

Future<void> migrateOldDataFolder() async {
  if (kIsWeb || !Platform.isLinux) return;
  try {
    Directory newDir = await getApplicationSupportDirectory();
    bool newHasData = File(p.join(newDir.path, "db.sqlite")).existsSync() ||
        File(p.join(newDir.path, "shared_preferences.json")).existsSync();
    if (newHasData) return;
    for (String oldId in _oldAppIds) {
      Directory oldDir = Directory(p.join(newDir.parent.path, oldId));
      if (!oldDir.existsSync()) continue;
      if (newDir.existsSync()) await newDir.delete(recursive: true);
      await oldDir.rename(newDir.path);
      print("Moved data folder from " + oldDir.path + " to " + newDir.path);
      return;
    }
  } catch (e) {
    print("Could not migrate old data folder: " + e.toString());
  }
}
