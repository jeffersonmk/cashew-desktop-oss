// Cashew Desktop: check GitHub for a newer release.
//
// Once a day (and when the user asks) the app reads the latest release of the
// repository from the public GitHub API. Nothing is downloaded or installed:
// if a newer version exists, the user gets a notice with a link to the
// release page. Only the request itself reaches GitHub (no personal data).

import 'dart:convert';

import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String _latestReleaseApi =
    "https://api.github.com/repos/jeffersonmk/cashew-desktop-oss/releases/latest";
const String releasesPage =
    "https://github.com/jeffersonmk/cashew-desktop-oss/releases/latest";

class ReleaseInfo {
  ReleaseInfo(this.version, this.url);
  final String version; // without the leading "v"
  final String url;
}

// "v1.2.3" / "1.2.3+4" / "1.2" -> [1, 2, 3]. Non-numeric parts count as 0.
List<int> parseVersion(String version) {
  String clean = version.trim();
  if (clean.startsWith("v") || clean.startsWith("V")) clean = clean.substring(1);
  clean = clean.split("+").first.split("-").first;
  List<int> parts =
      clean.split(".").map((p) => int.tryParse(p.trim()) ?? 0).toList();
  while (parts.length < 3) parts.add(0);
  return parts;
}

// True when [latest] is a higher version than [current].
bool isNewerVersion(String latest, String current) {
  List<int> a = parseVersion(latest);
  List<int> b = parseVersion(current);
  for (int i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return a.length > b.length;
}

String get currentAppVersion => packageInfoGlobal?.version ?? "";

Future<ReleaseInfo?> fetchLatestRelease() async {
  final response = await http.get(
    Uri.parse(_latestReleaseApi),
    headers: {
      "Accept": "application/vnd.github+json",
      "User-Agent": "CashewDesktop/" + currentAppVersion,
    },
  ).timeout(Duration(seconds: 15));
  if (response.statusCode != 200) {
    throw Exception("GitHub returned " + response.statusCode.toString());
  }
  Map data = jsonDecode(response.body);
  String tag = (data["tag_name"] ?? "").toString();
  if (tag == "" || data["draft"] == true || data["prerelease"] == true) {
    return null;
  }
  String url = (data["html_url"] ?? releasesPage).toString();
  // Only ever open pages of this repository.
  if (!url.startsWith("https://github.com/jeffersonmk/cashew-desktop-oss/")) {
    url = releasesPage;
  }
  return ReleaseInfo(tag.replaceFirst(RegExp(r"^[vV]"), ""), url);
}

void _showUpdateAvailable(ReleaseInfo release) {
  openSnackbar(
    SnackbarMessage(
      title: "update-available".tr(),
      description: "update-available-description".tr(namedArgs: {
        "version": release.version,
        "current": currentAppVersion,
      }),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.system_update_outlined
          : Icons.system_update_rounded,
      timeout: Duration(seconds: 15),
      onTap: () => openUrl(release.url),
    ),
  );
}

// Automatic check on startup: at most once a day, silent on errors.
Future<void> checkForUpdatesAutomatically() async {
  if (kIsWeb || !isDesktopPlatform) return;
  if (appStateSettings["desktopCheckForUpdates"] != true) return;
  DateTime now = DateTime.now();
  DateTime? lastCheck =
      DateTime.tryParse(appStateSettings["desktopLastUpdateCheck"] ?? "");
  if (lastCheck != null && now.difference(lastCheck) < Duration(hours: 20)) {
    return;
  }
  try {
    ReleaseInfo? release = await fetchLatestRelease();
    await updateSettings("desktopLastUpdateCheck", now.toIso8601String(),
        updateGlobalState: false);
    if (release == null) return;
    if (!isNewerVersion(release.version, currentAppVersion)) return;
    // Don't repeat the notice for a version the user already saw.
    if (appStateSettings["desktopNotifiedUpdateVersion"] == release.version) {
      return;
    }
    await updateSettings("desktopNotifiedUpdateVersion", release.version,
        updateGlobalState: false);
    _showUpdateAvailable(release);
  } catch (e) {
    print("Update check failed: " + e.toString());
  }
}

// Manual check (button in Settings): always reports the result.
Future<void> checkForUpdatesNow() async {
  try {
    ReleaseInfo? release = await fetchLatestRelease();
    await updateSettings(
        "desktopLastUpdateCheck", DateTime.now().toIso8601String(),
        updateGlobalState: false);
    if (release != null && isNewerVersion(release.version, currentAppVersion)) {
      _showUpdateAvailable(release);
    } else {
      openSnackbar(SnackbarMessage(
        title: "up-to-date".tr(),
        description: "v" + currentAppVersion,
        icon: appStateSettings["outlinedIcons"]
            ? Icons.check_circle_outline
            : Icons.check_circle_rounded,
      ));
    }
  } catch (e) {
    print("Update check failed: " + e.toString());
    openSnackbar(SnackbarMessage(
      title: "update-check-failed".tr(),
      description: "update-check-failed-description".tr(),
      icon: Icons.warning_rounded,
    ));
  }
}
